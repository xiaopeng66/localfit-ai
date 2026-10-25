import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/backup/application/create_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';
import 'package:localfit_ai/features/backup/application/restore_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/application/export_csv_files.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';

import '../../support/food_fixture.dart';

void main() {
  /// 新版「我的」页比旧版高：备份/恢复/清除分组在懒列表下半屏，
  /// 默认 800×600 根本没被构建。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late _InMemoryBackupFileStore fileStore;
  late CreateEncryptedBackup createBackup;
  late RestoreEncryptedBackup restoreBackup;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    fileStore = _InMemoryBackupFileStore();
    createBackup = CreateEncryptedBackup(
      database: database,
      fileStore: fileStore,
      codec: const LfbBackupCodec(iterations: 2000, derivesInIsolate: false),
    );
    restoreBackup = RestoreEncryptedBackup(
      database: database,
      fileStore: fileStore,
      codec: const LfbBackupCodec(iterations: 2000, derivesInIsolate: false),
    );
  });

  tearDown(() => database.close());

  Future<void> seedProfileAndMeal() async {
    final now = DateTime.utc(2026, 9, 12, 10);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-1',
            localDate: '2026-09-12',
            slot: 'lunch',
            eatenAt: now,
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Widget page() => MaterialApp(
    home: SettingsPage(
      createEncryptedBackup: createBackup,
      restoreEncryptedBackup: restoreBackup,
      clearAllLocalData: ClearAllLocalData(database),
      exportCsvFiles: ExportCsvFiles(database: database, fileStore: fileStore),
    ),
  );

  testWidgets('exports an encrypted backup into the file store', (
    tester,
  ) async {
    useTallViewport(tester);
    await seedProfileAndMeal();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cta-backup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-export-password')),
      '口令-1',
    );
    await tester.enterText(
      find.byKey(const Key('backup-export-password2')),
      '口令-1',
    );
    await tester.tap(find.byKey(const Key('backup-export-confirm')));
    await tester.pumpAndSettle();

    expect(fileStore.saved, hasLength(1));
    final payload =
        await const LfbBackupCodec(
          iterations: 2000,
          derivesInIsolate: false,
        ).decode(
          envelopeJson: utf8.decode(fileStore.saved.single.bytes),
          password: '口令-1',
        );
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    await RestoreLocalFitData(restored).restore(payload);
    expect(
      (await restored.select(restored.profiles).get()).single.id,
      'profile-1',
    );
  });

  testWidgets('rejects mismatched export passwords without saving', (
    tester,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cta-backup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-export-password')),
      'a',
    );
    await tester.enterText(
      find.byKey(const Key('backup-export-password2')),
      'b',
    );
    await tester.tap(find.byKey(const Key('backup-export-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('两次输入的口令不一致。'), findsOneWidget);
    expect(fileStore.saved, isEmpty);
  });

  testWidgets('restores a picked backup and replaces current data', (
    tester,
  ) async {
    useTallViewport(tester);
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    final now = DateTime.utc(2026, 9, 1);
    await other
        .into(other.workoutPlans)
        .insert(
          WorkoutPlansCompanion.insert(
            id: 'plan-other',
            name: '备份里的计划',
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final bytes = await ExportLocalFitData(other).exportJson();
    fileStore.picked = Uint8List.fromList(
      utf8.encode(
        await const LfbBackupCodec(
          iterations: 2000,
          derivesInIsolate: false,
        ).encode(payload: bytes, password: '口令-2'),
      ),
    );

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cta-restore')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-restore-password')),
      '口令-2',
    );
    await tester.tap(find.byKey(const Key('backup-restore-confirm')));
    await tester.pumpAndSettle();

    expect(
      (await database.select(database.workoutPlans).get()).single.name,
      '备份里的计划',
    );
    expect(find.textContaining('备份已恢复'), findsOneWidget);
  });

  testWidgets('keeps current data when the restore password is wrong', (
    tester,
  ) async {
    useTallViewport(tester);
    await seedProfileAndMeal();
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    final bytes = await ExportLocalFitData(other).exportJson();
    fileStore.picked = Uint8List.fromList(
      utf8.encode(
        await const LfbBackupCodec(
          iterations: 2000,
          derivesInIsolate: false,
        ).encode(payload: bytes, password: '正确口令'),
      ),
    );

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cta-restore')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-restore-password')),
      '错误口令',
    );
    await tester.tap(find.byKey(const Key('backup-restore-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('密码错误'), findsOneWidget);
    expect(
      (await database.select(database.profiles).get()).single.id,
      'profile-1',
    );
  });

  testWidgets('clears everything only after typed confirmation', (
    tester,
  ) async {
    useTallViewport(tester);
    await seedProfileAndMeal();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    // 清除行在关于分组末尾：ensureVisible 只能处理已构建的项，
    // 懒列表里它可能还没被 build，用拖拽式滚动。
    await tester.scrollUntilVisible(
      find.byKey(const Key('cta-clear-data')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cta-clear-data')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('backup-clear-confirm')), findsOneWidget);
    // 破坏性确认必须说清范围：2.0 的校园菜单与目录数据也在清除之列。
    expect(find.textContaining('校园菜单'), findsOneWidget);
    // 破坏性确认 = §3.8 B7：error 字色的**文字**按钮。设计稿
    // （`我的.html:524-532`）里没有实心 error 按钮，所以这里既不是 B2 实心，
    // 也不是带 40% 彩色阴影的确认档。
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('backup-clear-confirm')))
          .style
          ?.foregroundColor
          ?.resolve(<WidgetState>{}),
      LfSemanticColors.light.error,
    );
    // 确认按钮在未输入确认文字时禁用。
    await tester.tap(find.byKey(const Key('backup-clear-confirm')));
    await tester.pumpAndSettle();
    expect(await database.select(database.profiles).get(), isNotEmpty);

    await tester.enterText(
      find.byKey(const Key('backup-clear-confirm-text')),
      '全部清除',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-clear-confirm')));
    await tester.pumpAndSettle();

    expect(await database.select(database.profiles).get(), isEmpty);
    expect(await database.select(database.meals).get(), isEmpty);
    // 2026-10-23：内置食物（含导入）活过「清除所有数据」（用户裁决）。
    final foods = await database.select(database.foods).get();
    expect(foods.every((row) => !row.isUserCreated), isTrue);
    expect(await database.select(database.exercises).get(), isEmpty);
  });

  testWidgets('清除失败：不谎报「数据未受影响」，复位后仍可重试', (tester) async {
    useTallViewport(tester);
    await seedProfileAndMeal();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          createEncryptedBackup: createBackup,
          restoreEncryptedBackup: restoreBackup,
          // 字节清理失败：数据库行在清理之前就已提交，所以「数据其实已经
          // 删了」——提示语说「数据未受影响」就是谎报（2026-10-08 缺陷排查）。
          clearAllLocalData: ClearAllLocalData(
            database,
            dishImageStore: _ThrowingDishImageStore(),
          ),
          exportCsvFiles: ExportCsvFiles(
            database: database,
            fileStore: fileStore,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('cta-clear-data')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cta-clear-data')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('backup-clear-confirm-text')),
      '全部清除',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('backup-clear-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('数据未受影响'), findsNothing);
    expect(find.textContaining('清除未完成'), findsOneWidget);
    // 行确实已经删了（这就是那句话不能说出口的原因）。
    expect(await database.select(database.profiles).get(), isEmpty);
    // 弹层没卡在「正在清除…」：确认按钮重新可点，用户能重试。
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('backup-clear-confirm')))
          .onPressed,
      isNotNull,
    );
  });

  /// docs/21 §5.6 的「数据管理」分组只在**具备备份能力**时出现，导出行
  /// （T8 起文案为「导出饮食记录」，不再带 CSV 后缀）同组。这两条 Key 因此
  /// 挂在有完整备份接线的 harness 上（无备份能力时分组自己收起来，只在
  /// `settings_page_test` 里断言「不出现」）。
  testWidgets('docs/21 §5.6 Key 覆盖：数据管理分组与导出行入口', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final scrollable = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .first;
    const docKeys = <String>['settings-group-data', 'cta-export-csv'];
    final missing = <String>[];
    for (final key in docKeys) {
      var found = find.byKey(Key(key)).evaluate().isNotEmpty;
      for (var i = 0; i < 14 && !found; i++) {
        await tester.drag(scrollable, const Offset(0, -320));
        await tester.pump();
        found = find.byKey(Key(key)).evaluate().isNotEmpty;
      }
      if (!found) missing.add(key);
    }
    expect(
      missing,
      isEmpty,
      reason: '我的页缺少 docs/21 §5.6 的 Key：${missing.join('、')}',
    );
    expect(find.text('数据管理'), findsOneWidget);
    expect(find.text('导出饮食记录'), findsOneWidget);
  });
}

final class _InMemoryBackupFileStore implements BackupFileStore {
  final saved = <_SavedExport>[];
  Uint8List? picked;

  @override
  Future<String?> saveExport({
    required String defaultFileName,
    required Uint8List bytes,
  }) async {
    saved.add(_SavedExport(defaultFileName, bytes));
    return '/memory/$defaultFileName';
  }

  @override
  Future<Uint8List?> pickRestoreFile() async => picked;
}

final class _SavedExport {
  const _SavedExport(this.fileName, this.bytes);

  final String fileName;
  final Uint8List bytes;
}

/// 字节清理永远失败：用来验证「清除失败」的提示语与弹层复位。
final class _ThrowingDishImageStore implements DishImageStoreRef {
  @override
  Future<void> clearAll() async => throw Exception('dish image sweep failed');
}
