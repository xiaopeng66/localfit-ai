import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_file_importer.dart';
import 'package:localfit_ai/features/campus_menus/data/file_menu_raw_content_store.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_tab_controller.dart';

/// 2.0-6c：菜单 tab 控制器（application 层；页面无 SQL）。
/// load() = markExpired → 选校园/食堂 → active 快照 → 服务/条目分组；
/// importFrom() = find-or-create 手动导入 source → MenuFileImporter。
void main() {
  late AppDatabase database;
  late Directory tempDir;
  final now = DateTime.utc(2026, 9, 15, 8);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('menu-tab-test');
    await database
        .into(database.campusProfiles)
        .insert(
          CampusProfilesCompanion.insert(
            id: 'campus-1',
            name: '示范大学',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.venues)
        .insert(
          VenuesCompanion.insert(
            id: 'venue-1',
            campusId: 'campus-1',
            name: '东区食堂',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  String writeMenuFile(String content, {String name = 'menu.txt'}) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name')
      ..writeAsStringSync(content);
    return file.path;
  }

  test('no venue configured yields actionable hint state', () async {
    await (database.delete(database.venues)).go();
    final controller = MenuTabController(database: database);
    final state = await controller.load(now: now);
    expect(state.venueName, isNull);
    expect(state.snapshot, isNull);
    expect(state.services, isEmpty);
  });

  test('venue without snapshot renders empty active state', () async {
    final controller = MenuTabController(database: database);
    final state = await controller.load(now: now);
    expect(state.campusName, '示范大学');
    expect(state.venueName, '东区食堂');
    expect(state.snapshot, isNull);
    expect(state.services, isEmpty);
  });

  test(
    'after import: active snapshot with grouped services and items',
    () async {
      final controller = MenuTabController(
        database: database,
        rawContentStore: FileMenuRawContentStore(tempDir.path),
      );
      final path = writeMenuFile('''
# 一楼窗口 10:30-13:30
鸡蛋炒饭 800
番茄炒蛋 600
''');
      await controller.importFrom(path, now: now);
      final state = await controller.load(now: now);

      expect(state.snapshot, isNotNull);
      expect(state.snapshot!.venueId, 'venue-1');
      expect(state.services, hasLength(1));
      final service = state.services.single;
      expect(service.name, '一楼窗口');
      expect(service.openCloseText, '10:30–13:30');
      expect(
        service.items.map((item) => item.displayName),
        containsAll(['鸡蛋炒饭', '番茄炒蛋']),
      );
      // 未匹配条目：D 级 + 待确认（文字，不只用颜色）。
      final item = service.items.first;
      expect(item.evidenceGrade, 'D');
      expect(item.itemStatus, 'unresolved');
      expect(item.matchedFoodName, isNull);

      // docs/07 §6.1/§6.3：菜单要能看到「来源」，来源行记录类型与许可证。
      expect(state.sourceType, 'file_txt_csv_json');
      expect(state.license, 'user-file');
      final source = (await database.select(database.menuSources).get()).single;
      expect(source.license, 'user-file');
    },
  );

  test('跨 UTC 日界：导入写的业务日期与查询用的是同一个本地日', () async {
    // docs/11 §3-D：业务日期是「本地日」口径。注入时刻取 UTC 前一天晚上
    // （本地已是次日凌晨）——导入侧若按 UTC 字段拼日期，写下的
    // businessDate 会是 09-14，而 load() 按本地日查 09-15，刚导入的菜单
    // 立刻「查不到」（跨零点后菜单 tab 空白）。既有用例全用同 UTC 日的
    // 时刻，所以这个边界从来没被测到。
    final boundary = DateTime.utc(2026, 9, 14, 20); // 本地 UTC+8 → 09-15 04:00
    expect(boundary.toLocal().day, 15, reason: '这条用例的前提是本地日与 UTC 日不同');
    final controller = MenuTabController(
      database: database,
      rawContentStore: FileMenuRawContentStore(tempDir.path),
    );
    final path = writeMenuFile('''
# 一楼窗口 10:30-13:30
鸡蛋炒饭 800
''');
    await controller.importFrom(path, now: boundary);
    final state = await controller.load(now: boundary);

    expect(state.snapshot, isNotNull, reason: '导入后必须立刻可见');
    expect(state.services.single.items.single.displayName, '鸡蛋炒饭');
  });

  test(
    're-import same content stays idempotent (skip, one active snapshot)',
    () async {
      final controller = MenuTabController(
        database: database,
        rawContentStore: FileMenuRawContentStore(tempDir.path),
      );
      final path = writeMenuFile('''
# 一楼窗口 10:30-13:30
鸡蛋炒饭 800
''');
      await controller.importFrom(path, now: now);
      final result = await controller.importFrom(path, now: now);
      // 重复内容 hash 幂等：不产生新快照。
      expect(result.snapshotId, isNull);
      expect(result.duplicateOf, isNotNull);
      final state = await controller.load(now: now);
      final activeRows = await (database.select(
        database.menuSnapshots,
      )..where((row) => row.status.equals('active'))).get();
      expect(activeRows, hasLength(1));
      expect(state.services.single.items, hasLength(1));
    },
  );

  test('failed import keeps old snapshot and surfaces message', () async {
    final controller = MenuTabController(
      database: database,
      rawContentStore: FileMenuRawContentStore(tempDir.path),
    );
    await controller.importFrom(
      writeMenuFile('# 一楼窗口 10:30-13:30\n鸡蛋炒饭 800\n'),
      now: now,
    );
    expect(
      () => controller.importFrom(
        writeMenuFile('not a menu at all', name: 'bad.txt'),
        now: now,
      ),
      throwsA(isA<MenuFileImportException>()),
    );
    final state = await controller.load(now: now);
    expect(state.snapshot, isNotNull);
    expect(state.services.single.items, hasLength(1));
  });

  group('matching (2.0-6d)', () {
    test('load marks unresolved items and exposes match candidates', () async {
      // 主库种子：鸡蛋炒饭（精确名）。
      final controller = MenuTabController(
        database: database,
        rawContentStore: FileMenuRawContentStore(tempDir.path),
      );
      await controller.importFrom(
        writeMenuFile('# 一楼窗口 10:30-13:30\n鸡蛋炒饭 800\n番茄炒蛋 600\n'),
        now: now,
      );
      // 建 food（verified）供匹配。
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'food-egg-rice',
              name: '鸡蛋炒饭',
              kcalPer100g: 180,
              proteinPer100g: 12,
              carbsPer100g: 25,
              fatPer100g: 5,
              source: 'user',
              state: const Value('verified'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final state = await controller.load(now: now);
      final item = state.services.single.items.firstWhere(
        (element) => element.displayName == '鸡蛋炒饭',
      );
      expect(item.matchedFoodName, isNull);
      expect(item.itemStatus, 'unresolved');
    });

    test(
      'suggest + confirm flow: item becomes matched with food name',
      () async {
        final controller = MenuTabController(
          database: database,
          rawContentStore: FileMenuRawContentStore(tempDir.path),
        );
        await controller.importFrom(
          writeMenuFile('# 一楼窗口 10:30-13:30\n鸡蛋炒饭 800\n'),
          now: now,
        );
        await database
            .into(database.foods)
            .insert(
              FoodsCompanion.insert(
                id: 'food-egg-rice',
                name: '鸡蛋炒饭',
                kcalPer100g: 180,
                proteinPer100g: 12,
                carbsPer100g: 25,
                fatPer100g: 5,
                source: 'user',
                state: const Value('verified'),
                createdAt: now,
                updatedAt: now,
              ),
            );

        final state = await controller.load(now: now);
        final item = state.services.single.items.single;
        // 给该条目生成建议（本地主库精确命中）。
        await controller.suggestFor(item.id);
        final suggestions = await controller.suggestionsFor(item.id);
        expect(suggestions.map((s) => s.foodName), contains('鸡蛋炒饭'));

        // 确认第一条建议 → matched + matchedFoodName。
        await controller.confirmSuggestion(item.id, suggestions.first.foodId);
        final reloaded = await controller.load(now: now);
        final matchedItem = reloaded.services.single.items.single;
        expect(matchedItem.matchedFoodName, '鸡蛋炒饭');
        expect(matchedItem.itemStatus, 'matched');
      },
    );

    test('reject flow: item falls back to unresolved', () async {
      final controller = MenuTabController(
        database: database,
        rawContentStore: FileMenuRawContentStore(tempDir.path),
      );
      await controller.importFrom(
        writeMenuFile('# 一楼窗口 10:30-13:30\n鸡蛋炒饭 800\n'),
        now: now,
      );
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'food-egg-rice',
              name: '鸡蛋炒饭',
              kcalPer100g: 180,
              proteinPer100g: 12,
              carbsPer100g: 25,
              fatPer100g: 5,
              source: 'user',
              state: const Value('verified'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final state = await controller.load(now: now);
      final item = state.services.single.items.single;
      await controller.suggestFor(item.id);
      await controller.confirmSuggestion(item.id, 'food-egg-rice');
      // 拒绝唯一 confirmed 行 → 回 unresolved。
      await controller.rejectConfirmed(item.id);
      final reloaded = await controller.load(now: now);
      final rejected = reloaded.services.single.items.single;
      expect(rejected.matchedFoodName, isNull);
      expect(rejected.itemStatus, 'unresolved');
    });
  });
}
