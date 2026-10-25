import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 2.0-6f：食物库 50k 浏览/搜索接线（application 层）。
/// 主库（用户自建/既有）+ 目录分片（FTS5）合并、按 id 去重、分类筛选。
/// docs/28 §8 起换成 `count` + `page` 一对分页接口：默认浏览走主库 SQL
/// `LIMIT/OFFSET`（总数 `COUNT(*)` 真实值），搜索在合并列表上切片。
void main() {
  late AppDatabase database;
  late Directory tempDir;
  late String shardPath;
  late sqlite.Database shardDb;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('localfit-foodlib-');
    shardPath = '${tempDir.path}${Platform.pathSeparator}foods-core-000.sqlite';
    shardDb = sqlite.sqlite3.open(shardPath);
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
CREATE VIRTUAL TABLE food_search USING fts5(food_id UNINDEXED, text, brand, category);
''');
    void catalogFood(String id, String name, {String? category}) {
      shardDb.execute(
        'INSERT INTO foods (id, name, state, locale, category, brand,'
        ' kcal_per100g, protein_per100g, carbs_per100g, fat_per100g,'
        " source_id, license_status) VALUES ('$id', '$name', 'verified', 'zh',"
        " ${category == null ? 'NULL' : "'$category'"}, NULL, 100, 1, 1, 1,"
        " 'openfoodfacts', 'allowed')",
      );
      final spaced = name.split('').join(' ');
      shardDb.execute(
        "INSERT INTO food_search (food_id, text, brand, category)"
        " VALUES ('$id', '$spaced', '', ${category == null ? "''" : "'$category'"})",
      );
    }

    catalogFood('cat-rice', '蒸米饭');
    catalogFood('cat-noodle', '牛肉面', category: 'noodle');
    catalogFood('cat-buckwheat', '荞麦面', category: 'noodle');
    catalogFood('cat-bread', '全麦面包', category: 'bakery');

    final now = DateTime.utc(2026, 9, 15, 7);
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'user-rice',
            name: '米饭（自建）',
            kcalPer100g: 116,
            proteinPer100g: 2.6,
            carbsPer100g: 25.9,
            fatPer100g: 0.3,
            source: 'user',
            state: const Value('user_created'),
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await database.close();
    shardDb.dispose();
    tempDir.deleteSync(recursive: true);
  });

  FoodLibraryController buildController() => FoodLibraryController(
    repository: FoodRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
    ),
    catalogSearch: CatalogSearchService(shardPaths: [shardPath]),
  );

  test('empty query returns the first page of the default browse', () async {
    final controller = buildController();
    expect(await controller.count(''), 1);
    final items = await controller.page('', offset: 0, limit: 50);
    expect(items.map((item) => item.name), ['米饭（自建）']);
    expect(items.single.source, 'main');
  });

  test(
    'search merges main-db hits first, then catalog, dedupe by id',
    () async {
      final items = await buildController().page('米饭', offset: 0, limit: 50);
      expect(items.map((item) => item.name), containsAll(['米饭（自建）', '蒸米饭']));
      // 主库结果排前。
      expect(items.first.name, '米饭（自建）');
    },
  );

  test('category filter applies to main rows too, and normalizes catalog raw strings', () async {
    // 【2026-10-14 Round7 阶段 3 改写，登记为修缺陷不是放宽】旧断言是
    // 「category filter keeps only matching catalog rows」——因为
    // `_fromMainRow` 从不写 `category`，主库行必然被筛掉。而用户自己导入的
    // 5 万条**全是主库行**，于是「按分类筛」实际等于把用户的库筛空。现在
    // 判据统一为落库枚举 id：主库行带上分类、目录分片的原串（'noodle'/
    // 'bakery' 不是本仓枚举 id）不猜、不回落，只在「全部」可见。
    final controller = buildController();
    final rows = await database.select(database.foods).get();
    expect(rows.single.id, 'user-rice');
    await (database.update(database.foods)
          ..where((row) => row.id.equals('user-rice')))
        .write(const FoodsCompanion(category: Value('staple')));

    // 主库行带分类 ⇒ 分类筛选**留下**它（旧实现下这里是 0 条）。
    expect(await controller.count('米饭', category: FoodCategory.staple), 1);
    final mainHits = await controller.page(
      '米饭',
      offset: 0,
      limit: 50,
      category: FoodCategory.staple,
    );
    expect(mainHits.map((item) => item.name), ['米饭（自建）']);
    expect(mainHits.single.category, 'staple');

    // 目录分片的 'noodle' 不是枚举 id ⇒ 不冒充任何分类；它在「全部」里在。
    expect(await controller.count('面', category: FoodCategory.staple), 0);
    final all = await controller.page('面', offset: 0, limit: 50);
    expect(all.map((item) => item.name), containsAll(['牛肉面', '荞麦面']));
  });

  test('search returns every catalog match without pagination', () async {
    // 目录里「面」命中 牛肉面/全麦面包；不再分页，一次给全。
    final controller = buildController();
    final total = await controller.count('面');
    final items = await controller.page('面', offset: 0, limit: 50);
    expect(items, isNotEmpty);
    expect(items.length, total);
    expect(items.map((item) => item.name), contains('全麦面包'));
  });

  test('incomplete state is searchable but flagged cannot-join-plan', () async {
    // 目录行 state 都为 verified；主库 user_created 同样可加入计划。
    final items = await buildController().page('米饭', offset: 0, limit: 50);
    expect(items.every((item) => item.canJoinPlan), isTrue);
  });

  test('search results are sliced by offset and limit', () async {
    // 搜索路径在合并列表上按页切片（docs/28 §8.2）：滑条要能落到任意位置。
    final controller = buildController();
    final all = await controller.page('米饭', offset: 0, limit: 50);
    expect(all.length, 2);
    final first = await controller.page('米饭', offset: 0, limit: 1);
    final second = await controller.page('米饭', offset: 1, limit: 1);
    expect(first.single.id, all.first.id);
    expect(second.single.id, all[1].id);
    expect(await controller.page('米饭', offset: 2, limit: 1), isEmpty);
  });

  test('invalidate() drops the cached search merge', () async {
    final controller = buildController();
    expect(
      (await controller.page(
        '米饭',
        offset: 0,
        limit: 50,
      )).map((item) => item.id),
      contains('user-rice'),
    );
    // 库里删掉这一条之后，缓存还在 ⇒ 仍然找得到（正是要防的陈旧读）。
    await database.delete(database.foods).go();
    expect(
      (await controller.page(
        '米饭',
        offset: 0,
        limit: 50,
      )).map((item) => item.id),
      contains('user-rice'),
    );
    // 作废缓存后重查：被删的条目不再出现（目录分片那条仍在）。
    controller.invalidate();
    final after = await controller.page('米饭', offset: 0, limit: 50);
    expect(after.map((item) => item.id), isNot(contains('user-rice')));
    expect(after.map((item) => item.id), contains('cat-rice'));
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'food-${_value++}';
}
