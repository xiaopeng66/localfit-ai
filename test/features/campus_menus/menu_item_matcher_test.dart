import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_item_matcher.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 2.0-3d：菜单项 → 本地 food top-K 匹配 + 用户确认状态机。
void main() {
  late AppDatabase database;
  late Directory tempDir;
  late String shardPath;
  late String menuItemId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('localfit-matcher-');
    final now = DateTime.now().toUtc();
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
    await database
        .into(database.menuSources)
        .insert(
          MenuSourcesCompanion.insert(
            id: 'source-1',
            venueId: 'venue-1',
            sourceType: 'paste_text',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuSnapshots)
        .insert(
          MenuSnapshotsCompanion.insert(
            id: 'snap-1',
            sourceId: 'source-1',
            venueId: 'venue-1',
            businessDate: '2026-09-15',
            contentHash: 'a' * 64,
            importedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuServices)
        .insert(
          MenuServicesCompanion.insert(
            id: 'svc-1',
            snapshotId: 'snap-1',
            name: '一楼窗口',
            openTime: '10:30',
            closeTime: '13:30',
            createdAt: now,
            updatedAt: now,
          ),
        );

    Future<String> insertItem(String displayName) async {
      final id = 'item-${database.menuItems.hashCode}-$displayName';
      await database
          .into(database.menuItems)
          .insert(
            MenuItemsCompanion.insert(
              id: id,
              serviceId: 'svc-1',
              displayName: displayName,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return id;
    }

    menuItemId = await insertItem('宫保鸡丁');

    // 主库：用户自建 + 精确别名（模拟用户目录层）。
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'user-1',
            name: '宫保鸡丁（自记录）',
            kcalPer100g: 180,
            proteinPer100g: 12,
            carbsPer100g: 10,
            fatPer100g: 9,
            source: 'user',
            state: const Value('user_created'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.foodAliases)
        .insert(
          FoodAliasesCompanion.insert(
            id: 'alias-1',
            foodId: 'user-1',
            normalizedText: '宫保鸡丁',
            aliasType: 'manual',
            source: 'user',
            createdAt: now,
          ),
        );

    // 主库目录行：verified/estimated 已由 CatalogShardImporter 切换进
    // 主库 foods；incomplete/stale 只留在分片（docs/07 §5.6 边界）。
    // menu_item_food_matches.food_id 外键指向主库 foods，因此建议候选
    // 必须是主库行——分片仅提供检索打分。
    Future<void> mainFood(
      String id,
      String name,
      String state, {
      double kcal = 120,
    }) async {
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: id,
              name: name,
              kcalPer100g: kcal,
              proteinPer100g: 10,
              carbsPer100g: 10,
              fatPer100g: 5,
              source: 'openfoodfacts',
              state: Value(state),
              licenseStatus: const Value('allowed'),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    await mainFood('off-1', '宫保鸡丁', 'verified', kcal: 150);
    await mainFood('off-2', '宫保豆腐', 'estimated', kcal: 110);

    // 分片：与 ETL SHARD_SCHEMA 同形（含 food_search FTS5），只承载
    // 检索；incomplete/stale 行故意留在分片不进主库。
    shardPath = '${tempDir.path}${Platform.pathSeparator}foods-core-000.sqlite';
    final shardDb = sqlite.sqlite3.open(shardPath);
    shardDb.execute('''
CREATE TABLE foods (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  state TEXT NOT NULL,
  locale TEXT,
  category TEXT,
  brand TEXT,
  kcal_per100g REAL,
  protein_per100g REAL,
  carbs_per100g REAL,
  fat_per100g REAL,
  source_id TEXT NOT NULL,
  source_version TEXT,
  license_status TEXT NOT NULL
);
CREATE TABLE aliases (
  food_id TEXT NOT NULL REFERENCES foods(id),
  normalized_text TEXT NOT NULL,
  language TEXT,
  alias_type TEXT,
  confidence REAL NOT NULL DEFAULT 1.0
);
CREATE VIRTUAL TABLE food_search USING fts5(food_id UNINDEXED, text, brand, category);
''');
    void shardFood(String id, String name, String state, {double kcal = 120}) {
      shardDb.execute(
        "INSERT INTO foods (id, name, state, locale, category, brand,"
        " kcal_per100g, protein_per100g, carbs_per100g, fat_per100g,"
        " source_id, license_status) VALUES ('$id', '$name', '$state', 'zh',"
        " NULL, NULL, $kcal, 10, 10, 5, 'openfoodfacts', 'allowed')",
      );
      final spaced = name.split('').join(' ');
      shardDb.execute(
        "INSERT INTO food_search (food_id, text, brand, category)"
        " VALUES ('$id', '$spaced', '', '')",
      );
    }

    shardFood('off-1', '宫保鸡丁', 'verified', kcal: 150);
    shardFood('off-2', '宫保豆腐', 'estimated', kcal: 110);
    shardFood('off-3', '面包', 'incomplete');
    shardFood('off-4', '旧数据', 'stale');
    shardDb.dispose();
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  MenuItemMatcher buildMatcher({int topK = 5}) =>
      MenuItemMatcher(database: database, shardPaths: [shardPath], topK: topK);

  group('menu item matcher suggestions', () {
    test('ranks exact local alias first, dedupes shard hits, '
        'excludes incomplete/stale, writes suggested rows', () async {
      final matcher = buildMatcher(topK: 5);
      final suggestions = await matcher.suggestMatches(menuItemId);

      // 精确别名命中排第一；incomplete/stale 不出现。
      expect(suggestions.first.foodId, 'user-1');
      expect(suggestions.first.confidence, greaterThan(0.9));
      final ids = suggestions.map((s) => s.foodId).toSet();
      // 精确名命中（主库 verified 行）在建议中。
      expect(ids, contains('off-1'));
      expect(ids, isNot(contains('off-3')));
      expect(ids, isNot(contains('off-4')));

      // 建议落库且状态 suggested。
      final rows = await database.select(database.menuItemFoodMatches).get();
      expect(rows.map((r) => r.foodId), unorderedEquals(ids));
      expect(rows.every((r) => r.matchStatus == 'suggested'), isTrue);

      // 菜单项仍 unresolved（等待用户确认）。
      final item = await (database.select(
        database.menuItems,
      )..where((i) => i.id.equals(menuItemId))).getSingle();
      expect(item.itemStatus, 'unresolved');
    });

    test(
      'partial query reaches shard FTS hits with decayed confidence',
      () async {
        final now = DateTime.now().toUtc();
        await database
            .into(database.menuItems)
            .insert(
              MenuItemsCompanion.insert(
                id: 'item-partial',
                serviceId: 'svc-1',
                displayName: '宫保',
                createdAt: now,
                updatedAt: now,
              ),
            );
        final matcher = buildMatcher(topK: 5);
        final suggestions = await matcher.suggestMatches('item-partial');

        final ids = suggestions.map((s) => s.foodId).toSet();
        // 分片 FTS 命中：verified 主库行 verified/estimated 都可建议。
        expect(ids, contains('off-1'));
        expect(ids, contains('off-2'));
        expect(ids, isNot(contains('off-3')));
        // 分片命中置信度按名次衰减但高于下限。
        for (final s in suggestions) {
          expect(s.confidence, inInclusiveRange(0.3, 0.9));
        }
      },
    );

    test('respects topK cap and clamps above maxTopK', () async {
      final matcher = buildMatcher(topK: 2);
      final suggestions = await matcher.suggestMatches(menuItemId);
      expect(suggestions.length, 2);

      final rows = await database.select(database.menuItemFoodMatches).get();
      expect(rows.length, 2);
    });

    test(
      're-suggesting replaces suggested rows but keeps user decisions',
      () async {
        final matcher = buildMatcher(topK: 5);
        final first = await matcher.suggestMatches(menuItemId);
        // 用户确认一条、拒绝一条。
        final rows = await database.select(database.menuItemFoodMatches).get();
        final byFood = {for (final r in rows) r.foodId: r.id};
        await matcher.confirmMatch(byFood[first.first.foodId]!);
        await matcher.rejectMatch(byFood[first.last.foodId]!);

        await matcher.suggestMatches(menuItemId);

        final after = await database.select(database.menuItemFoodMatches).get();
        final statuses = {for (final r in after) r.foodId: r.matchStatus};
        // 用户决策保留。
        expect(statuses[first.first.foodId], 'confirmed');
        expect(statuses[first.last.foodId], 'rejected');
        // 其余为 suggested，不重复。
        expect(after.length, first.length);
      },
    );

    test('unknown menu item is rejected without writing rows', () async {
      final matcher = buildMatcher();
      await expectLater(
        matcher.suggestMatches('no-such-item'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        await database.select(database.menuItemFoodMatches).get(),
        isEmpty,
      );
    });

    test(
      'item with no candidates stays unresolved with no match rows',
      () async {
        final now = DateTime.now().toUtc();
        await database
            .into(database.menuItems)
            .insert(
              MenuItemsCompanion.insert(
                id: 'item-weird',
                serviceId: 'svc-1',
                displayName: '完全无关的菜名xyzq',
                createdAt: now,
                updatedAt: now,
              ),
            );
        final matcher = buildMatcher();
        final suggestions = await matcher.suggestMatches('item-weird');
        expect(suggestions, isEmpty);
        expect(
          await database.select(database.menuItemFoodMatches).get(),
          isEmpty,
        );
        final item = await (database.select(
          database.menuItems,
        )..where((i) => i.id.equals('item-weird'))).getSingle();
        expect(item.itemStatus, 'unresolved');
      },
    );
  });

  group('menu item matcher confirm/reject', () {
    test('confirmMatch marks the row confirmed and the item matched', () async {
      final matcher = buildMatcher();
      final suggestions = await matcher.suggestMatches(menuItemId);
      final rows = await database.select(database.menuItemFoodMatches).get();
      final target = rows.singleWhere(
        (r) => r.foodId == suggestions.first.foodId,
      );

      await matcher.confirmMatch(target.id);

      final confirmed = await (database.select(
        database.menuItemFoodMatches,
      )..where((r) => r.id.equals(target.id))).getSingle();
      expect(confirmed.matchStatus, 'confirmed');
      final item = await (database.select(
        database.menuItems,
      )..where((i) => i.id.equals(menuItemId))).getSingle();
      expect(item.itemStatus, 'matched');
    });

    test('confirmMatch 是原子的：菜单项状态写失败时匹配行必须回滚', () async {
      final matcher = buildMatcher();
      final suggestions = await matcher.suggestMatches(menuItemId);
      final rows = await database.select(database.menuItemFoodMatches).get();
      final target = rows.singleWhere(
        (r) => r.foodId == suggestions.first.foodId,
      );

      // 匹配行 confirmed + 菜单项 matched 是同一件事的两半：只落前一半的话
      // 界面会把已确认的菜显示成「待匹配」。
      await expectLater(
        database.runWithInterceptor(
          () => matcher.confirmMatch(target.id),
          interceptor: _FailingWriteOn('menu_items'),
        ),
        throwsA(isA<StateError>()),
      );

      final after = await (database.select(
        database.menuItemFoodMatches,
      )..where((r) => r.id.equals(target.id))).getSingle();
      expect(after.matchStatus, 'suggested');
    });

    test('rejectMatch marks the row rejected; item returns to unresolved '
        'when no confirmed match remains', () async {
      final matcher = buildMatcher();
      final suggestions = await matcher.suggestMatches(menuItemId);
      final rows = await database.select(database.menuItemFoodMatches).get();
      final target = rows.singleWhere(
        (r) => r.foodId == suggestions.first.foodId,
      );

      await matcher.confirmMatch(target.id);
      await matcher.rejectMatch(target.id);

      final rejected = await (database.select(
        database.menuItemFoodMatches,
      )..where((r) => r.id.equals(target.id))).getSingle();
      expect(rejected.matchStatus, 'rejected');
      final item = await (database.select(
        database.menuItems,
      )..where((i) => i.id.equals(menuItemId))).getSingle();
      expect(item.itemStatus, 'unresolved');
    });

    test('rejecting one match keeps the item matched while another stays '
        'confirmed', () async {
      final matcher = buildMatcher(topK: 5);
      final suggestions = await matcher.suggestMatches(menuItemId);
      expect(suggestions.length, greaterThanOrEqualTo(2));
      final rows = await database.select(database.menuItemFoodMatches).get();
      final byFood = {for (final r in rows) r.foodId: r.id};
      final keep = byFood[suggestions[0].foodId]!;
      final drop = byFood[suggestions[1].foodId]!;

      await matcher.confirmMatch(keep);
      await matcher.confirmMatch(drop);
      await matcher.rejectMatch(drop);

      final item = await (database.select(
        database.menuItems,
      )..where((i) => i.id.equals(menuItemId))).getSingle();
      expect(item.itemStatus, 'matched');
      final statuses = await database
          .select(database.menuItemFoodMatches)
          .get();
      expect(
        statuses.singleWhere((r) => r.id == keep).matchStatus,
        'confirmed',
      );
      expect(statuses.singleWhere((r) => r.id == drop).matchStatus, 'rejected');
    });

    test('confirmMatch on a rejected row re-confirms it', () async {
      final matcher = buildMatcher();
      final suggestions = await matcher.suggestMatches(menuItemId);
      final rows = await database.select(database.menuItemFoodMatches).get();
      final target = rows.singleWhere(
        (r) => r.foodId == suggestions.first.foodId,
      );

      await matcher.rejectMatch(target.id);
      await matcher.confirmMatch(target.id);

      final row = await (database.select(
        database.menuItemFoodMatches,
      )..where((r) => r.id.equals(target.id))).getSingle();
      expect(row.matchStatus, 'confirmed');
    });
  });
}

/// 让针对某张表的写操作（INSERT/UPDATE/DELETE）抛错，用来验证多表写路径
/// 的原子性：注入第二笔写失败，看第一笔是否回滚。
final class _FailingWriteOn extends QueryInterceptor {
  _FailingWriteOn(this.tableName);

  final String tableName;

  void _failIfTarget(String statement) {
    if (statement.contains(tableName)) {
      throw StateError('injected write failure on $tableName');
    }
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _failIfTarget(statement);
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _failIfTarget(statement);
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _failIfTarget(statement);
    return super.runDelete(executor, statement, args);
  }
}
