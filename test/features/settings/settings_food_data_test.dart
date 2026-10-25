import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// 「添加食物数据」入口与「导出食物数据」（docs/31 S5 需求 54/55；
/// 行文案自 T8 起去掉 CSV 后缀）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late _InMemoryExportStore fileStore;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    fileStore = _InMemoryExportStore();
  });

  tearDown(() => database.close());

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget page({
    Future<void> Function()? onAddCustomFood,
    Future<void> Function()? onImportFoodCsv,
    LoadProfileOverview? profileOverviewLoader,
  }) => MaterialApp(
    home: SettingsPage(
      // 本文件只关心食物库入口与导出行；备份组要显示就得把四件套给齐
      // （真实实现，跑不到的路径不会执行）。
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
      onAddCustomFood: onAddCustomFood,
      onImportFoodCsv: onImportFoodCsv,
      profileOverviewLoader: profileOverviewLoader,
    ),
  );

  testWidgets('「添加食物数据」行在，弹层里手动/导入两个动作各连各的回调（需求 55）', (tester) async {
    useTallViewport(tester);
    var manualCount = 0;
    var importCount = 0;
    await tester.pumpWidget(
      page(
        onAddCustomFood: () async => manualCount++,
        onImportFoodCsv: () async => importCount++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-food-data')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('food-data-sheet-body')), findsOneWidget);
    expect(find.byKey(const Key('food-data-sheet-manual')), findsOneWidget);
    expect(find.byKey(const Key('food-data-sheet-import')), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    // 手动 → 关弹层、只触发手动回调。
    await tester.tap(find.byKey(const Key('food-data-sheet-manual')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('food-data-sheet-body')), findsNothing);
    expect(manualCount, 1);
    expect(importCount, 0);

    // 再开一次走导入 → 只触发导入回调。
    await tester.tap(find.byKey(const Key('settings-food-data')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('food-data-sheet-import')));
    await tester.pumpAndSettle();
    expect(manualCount, 1);
    expect(importCount, 1);
  });

  testWidgets('两个回调都没接时不渲染入口行（不摆点了没反应的行）', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-food-data')), findsNothing);
    // T8 起「添加自定义食材」独立行已删除（动作收进「添加食物数据」弹层），
    // 所以这条恒为 findsNothing：不是「没接线所以藏」，是「本来就没有」。
    expect(find.byKey(const Key('settings-add-custom-food')), findsNothing);
  });

  testWidgets('弹层动作写库返回后，食材库计数就地重读（走查实测缺陷：导入后计数停在旧快照）', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      page(
        profileOverviewLoader: LoadProfileOverview(
          database: database,
          clock: FixedAppClock(DateTime.utc(2026, 10, 10, 4)),
        ),
        onImportFoodCsv: () async {
          // 站位真实导入的落库动作：写两条自建食物。
          final now = DateTime.utc(2026, 10, 10);
          for (final name in const ['燕麦片', '水煮鸡胸肉']) {
            await database
                .into(database.foods)
                .insert(
                  FoodsCompanion.insert(
                    id: 'import-$name',
                    name: name,
                    kcalPer100g: 100,
                    proteinPer100g: 10,
                    carbsPer100g: 10,
                    fatPer100g: 10,
                    source: 'user',
                    isUserCreated: const Value(true),
                    createdAt: now,
                    updatedAt: now,
                  ),
                );
          }
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('0 条（自建 0 条）'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-food-data')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('food-data-sheet-import')));
    await tester.pumpAndSettle();

    // 修复目标：不切 tab、不重进页面，计数就地跟上写库结果。
    expect(find.textContaining('2 条（自建 2 条）'), findsOneWidget);
    expect(find.textContaining('0 条（自建 0 条）'), findsNothing);
  });

  testWidgets('「导出食物数据」把全库导成带 BOM 的官方 9 列中文表头文件（需求 54 / ADR-036）', (
    tester,
  ) async {
    useTallViewport(tester);
    final now = DateTime.utc(2026, 10, 9);
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'seed-1',
            name: '鸡蛋',
            kcalPer100g: 144,
            proteinPer100g: 13.3,
            carbsPer100g: 2.8,
            fatPer100g: 8.8,
            category: const Value('protein'),
            source: 'seed-v5',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'user-1',
            name: '我的酸奶碗',
            brand: const Value('自家'),
            kcalPer100g: 90,
            proteinPer100g: 3.2,
            carbsPer100g: 12,
            fatPer100g: 2.5,
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backup-export-foods-csv')));
    await tester.pumpAndSettle();

    expect(fileStore.saved, hasLength(1));
    final bytes = fileStore.saved.single.bytes;
    // BOM 在最前（表格软件直开不乱码）。注意不能在解码后的字符串上验：
    // dart 的 utf8.decode 会把开头的 U+FEFF 吞掉，只在字节层面成立。
    expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    final body = utf8.decode(bytes.sublist(3));
    final lines = body.split('\r\n');
    expect(
      lines.first,
      '"食品ID","品牌","食物名称","别名","一级分类","热量(kcal/100g)","蛋白质(g/100g)",'
      '"碳水化合物(g/100g)","脂肪(g/100g)","自建/内置"',
    );
    // 一级分类 = 唯一分类（ADR-036）：导出枚举中文标签；食品ID 留空；
    // 「自建/内置」按落库身份出。
    expect(
      lines,
      contains('"","","鸡蛋","","蛋白质食物","144.0","13.3","2.8","8.8","内置"'),
    );
    expect(
      lines,
      contains('"","自家","我的酸奶碗","","","90.0","3.2","12.0","2.5","自建"'),
    );
  });
}

final class _InMemoryExportStore implements BackupFileStore {
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

final class _SavedFile {
  const _SavedFile(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}
