import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/setting_row.dart';
import 'package:localfit_ai/app/design/widgets/settings_group.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/backup/application/create_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/application/export_csv_files.dart';
import 'package:localfit_ai/features/backup/application/lfb_backup_codec.dart';
import 'package:localfit_ai/features/backup/application/restore_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

/// T8（docs/32 §4 T8 / §3 D10）· 设置页清理的四条外面可见结论：
/// 1. 「食材库」组的**行序与行数**（删了「添加自定义食材」行后的形态）；
/// 2. 「添加自定义食材」的独立行**不存在**——同一动作收进「添加食物数据」弹层；
/// 3. 三个导出行文案去 "CSV" 后缀（T12 的文案部分在此一并钉住，见证据文件）；
/// 4. 点击行为不变：三行各自触发自己的导出（文件名区分，回归钉住）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late _FakeExportStore fileStore;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    fileStore = _FakeExportStore();
  });

  tearDown(() => database.close());

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget page() => MaterialApp(
    home: SettingsPage(
      createEncryptedBackup: CreateEncryptedBackup(
        database: database,
        fileStore: fileStore,
        codec: const LfbBackupCodec(iterations: 2000, derivesInIsolate: false),
      ),
      restoreEncryptedBackup: RestoreEncryptedBackup(
        database: database,
        fileStore: fileStore,
        codec: const LfbBackupCodec(iterations: 2000, derivesInIsolate: false),
      ),
      clearAllLocalData: ClearAllLocalData(database),
      exportCsvFiles: ExportCsvFiles(database: database, fileStore: fileStore),
      profileOverviewLoader: LoadProfileOverview(
        database: database,
        clock: FixedAppClock(DateTime.utc(2026, 10, 13, 4)),
      ),
      onAddCustomFood: () async {},
      onImportFoodCsv: () async {},
      onOpenMenuSources: () {},
    ),
  );

  Future<void> scrollTo(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// 「食材库」组内的行标题（按渲染顺序）。
  ///
  /// 注意 `titleKey` 挂在组**标题的 Text** 上，不是组容器；所以按
  /// `SettingsGroup.title == '食材库'` 找组，再取组内 SettingRow。
  List<String> catalogRowTitles(WidgetTester tester) {
    final group = find.byWidgetPredicate(
      (widget) => widget is SettingsGroup && widget.title == '食材库',
      description: 'SettingsGroup(title: 食材库)',
    );
    return tester
        .widgetList<SettingRow>(
          find.descendant(of: group, matching: find.byType(SettingRow)),
        )
        .map((row) => row.title)
        .toList();
  }

  testWidgets('食材库组：行序与行数就是 D10 的定稿（三行，无「添加自定义食材」）', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await scrollTo(tester, const Key('settings-food-db-row'));

    expect(catalogRowTitles(tester), [
      '食材数据库',
      '添加食物数据',
      '维护地点 / 窗口 / 菜品',
    ], reason: 'T8 删「添加自定义食材」行后，组内行序 = D10 定稿');
    // 独立行删掉 ≠ 动作没了：同一动作在「添加食物数据」弹层里（键仍在）。
    expect(find.byKey(const Key('settings-add-custom-food')), findsNothing);
    expect(find.byKey(const Key('settings-food-data')), findsOneWidget);
    // 未接 catalogBootstrap（未接线）时恢复入口也不渲染——不摆点了没反应的行。
    expect(find.byKey(const Key('settings-catalog-import')), findsNothing);
  });

  testWidgets('三个导出行：文案去 "CSV" 后缀，全页无 CSV 字样', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await scrollTo(tester, const Key('cta-export-csv'));

    expect(find.text('导出饮食记录'), findsOneWidget);
    expect(find.text('导出训练记录'), findsOneWidget);
    expect(find.text('导出食物数据'), findsOneWidget);
    expect(find.textContaining('CSV'), findsNothing, reason: 'D17：文案不带 CSV');
    // 键名一字不动（键是回归与自动化的抓手，改名只在文案层）。
    expect(find.byKey(const Key('cta-export-csv')), findsOneWidget);
    expect(find.byKey(const Key('backup-export-training-csv')), findsOneWidget);
    expect(find.byKey(const Key('backup-export-foods-csv')), findsOneWidget);
  });

  testWidgets('三行各自的点击仍触发各自的导出（文件名区分，行为未变）', (tester) async {
    useTallViewport(tester);
    // 种子：一条自建食物，保证食物库导出不是空表。
    final now = DateTime.utc(2026, 10, 13);
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'food-1',
            name: '水煮鸡胸肉',
            kcalPer100g: 165,
            proteinPer100g: 31,
            carbsPer100g: 0,
            fatPer100g: 3.6,
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await scrollTo(tester, const Key('cta-export-csv'));
    await tester.tap(find.byKey(const Key('cta-export-csv')));
    await tester.pumpAndSettle();
    expect(fileStore.saved.last.name, startsWith('localfit-meals-'));

    await scrollTo(tester, const Key('backup-export-training-csv'));
    await tester.tap(find.byKey(const Key('backup-export-training-csv')));
    await tester.pumpAndSettle();
    expect(fileStore.saved.last.name, startsWith('localfit-training-'));

    await scrollTo(tester, const Key('backup-export-foods-csv'));
    await tester.tap(find.byKey(const Key('backup-export-foods-csv')));
    await tester.pumpAndSettle();
    expect(fileStore.saved.last.name, startsWith('localfit-foods-'));
    // 食物库导出内容里必须真的有那条自建食物（不是「导了个空壳还报成功」）。
    // 字节是 UTF-8 + BOM：`utf8.decode` 会吞掉开头的 U+FEFF，正好只要正文。
    expect(utf8.decode(fileStore.saved.last.bytes), contains('水煮鸡胸肉'));
  });
}

final class _SavedFile {
  const _SavedFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

final class _FakeExportStore implements BackupFileStore {
  final saved = <_SavedFile>[];

  @override
  Future<String?> saveExport({
    required String defaultFileName,
    required Uint8List bytes,
  }) async {
    saved.add(_SavedFile(defaultFileName, bytes));
    return 'E:/AI/Zcode/tmp/fake/$defaultFileName';
  }

  @override
  Future<Uint8List?> pickRestoreFile() async => null;
}
