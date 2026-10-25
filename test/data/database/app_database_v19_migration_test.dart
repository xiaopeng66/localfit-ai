import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// docs/28 §6.5 / §6.9：schema 18 → 19，食谱 / 周计划 / 食物价格 / 库存
/// 四族（五张表）整族下线。
///
/// 两条断言的用意不同，缺一不可：
///  * **v18 → v19**：删表要连行一起清掉（D9 的既定后果，不可逆），
///    且其余数据一字不动；
///  * **v1 → v19**：老库里从来没有这几张表——`recipes` 族原先由**已删除**的
///    `from < 3` / `from < 4` 分支建，价格/库存在 v5 库里也还没有
///    （由**已删除**的 `from < 6` 那两行建）。迁移链必须能一路走完不抛错，
///    这就是 `DROP TABLE IF EXISTS` 的守卫红证：把 `IF EXISTS` 去掉，
///    这条用例会以 `no such table: recipes` 失败。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v19-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('upgrades a populated v18 database to the current schema and drops the five tables', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV18Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    // ① 五张表连表带行一起没了（v18 fixture 每张都写了一行）。
    final dropped = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
          "('recipes', 'recipe_items', 'meal_plan_entries', "
          "'food_price_facts', 'pantry_stocks')",
        )
        .get();
    expect(dropped, isEmpty, reason: 'v19 迁移必须 DROP 掉五张表');

    // ② 版本号走到当前 schema（见下断言）。
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    // 升到**当前** schema（单一事实源）：写死数字会在每次加版本时
    // 过期一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
    expect(version.data['user_version'], database.schemaVersion);

    // ③ 其余数据一字不动：档案、食物、餐次与餐次条目照旧，
    //    连价格/库存曾经外键引用的那条食物也在。
    //
    //    这里用裸 SQL 数行数而不是 drift 的 select：fixture 是**最小复现**
    //    （只建这张断言要用到的列，仓库惯例），drift 的行映射需要完整列集。
    final survivors = await database
        .customSelect(
          'SELECT '
          '(SELECT COUNT(*) FROM profiles) AS profiles, '
          '(SELECT COUNT(*) FROM foods) AS foods, '
          '(SELECT COUNT(*) FROM meals) AS meals, '
          '(SELECT COUNT(*) FROM meal_items) AS meal_items',
        )
        .getSingle();
    expect(survivors.read<int>('profiles'), 1);
    expect(survivors.read<int>('foods'), 1);
    expect(survivors.read<int>('meals'), 1);
    expect(survivors.read<int>('meal_items'), 1);
  });

  test(
    'upgrades a trimmed v1 database straight to v19 without throwing',
    () async {
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createTrimmedV1Database(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(database.close);

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      // 升到**当前** schema（单一事实源）：写死数字会在每次加版本时
      // 过期一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
      expect(version.data['user_version'], database.schemaVersion);
      final dropped = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
            "('recipes', 'recipe_items', 'meal_plan_entries', "
            "'food_price_facts', 'pantry_stocks')",
          )
          .get();
      expect(dropped, isEmpty);
      // 老库的档案还在（裸 SQL：fixture 是最小复现，见上一条用例的说明）。
      final profiles = await database
          .customSelect('SELECT COUNT(*) AS c FROM profiles')
          .getSingle();
      expect(profiles.read<int>('c'), 1);
    },
  );
}

/// v18 线上库的**相关**部分：五张将被删的表各一行，外加要证明"没被动过"的
/// 幸存表（档案 / 食物 / 餐次 / 餐次条目）。
///
/// 列定义取自删表前的 `tables.dart`（含两个 `@TableIndex` 的索引列），
/// 与 `app_database_migration_test.dart` 里 v6 fixture 的 DDL 同源。
/// from = 18 ⇒ 迁移链里只有 `from < 19` 那一段会跑，其余分支不触碰这些表。
void _createV18Database(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
    const timestamp = 1780000000000;
    database.execute('''
      CREATE TABLE profiles (
        id TEXT NOT NULL PRIMARY KEY,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE foods (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE meals (
        id TEXT NOT NULL PRIMARY KEY,
        local_date TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE meal_items (
        id TEXT NOT NULL PRIMARY KEY,
        meal_id TEXT NOT NULL REFERENCES meals(id),
        food_id TEXT NULL REFERENCES foods(id),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE recipes (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        servings REAL NOT NULL,
        finished_weight_grams REAL NOT NULL,
        notes TEXT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE recipe_items (
        id TEXT NOT NULL PRIMARY KEY,
        recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        food_id TEXT NOT NULL REFERENCES foods(id),
        grams REAL NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE meal_plan_entries (
        id TEXT NOT NULL PRIMARY KEY,
        local_date TEXT NOT NULL,
        recipe_id TEXT NOT NULL REFERENCES recipes(id),
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE food_price_facts (
        food_id TEXT NOT NULL PRIMARY KEY REFERENCES foods(id) ON DELETE CASCADE,
        minor_units_per_100g INTEGER NOT NULL,
        currency TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE pantry_stocks (
        food_id TEXT NOT NULL PRIMARY KEY REFERENCES foods(id) ON DELETE CASCADE,
        available_grams REAL NOT NULL,
        updated_at INTEGER NOT NULL
      );
      INSERT INTO profiles VALUES ('profile-1', $timestamp, $timestamp);
      INSERT INTO foods VALUES ('food-1', '米饭', $timestamp, $timestamp);
      INSERT INTO meals VALUES ('meal-1', '2026-10-03', $timestamp, $timestamp);
      INSERT INTO meal_items VALUES ('item-1', 'meal-1', 'food-1', $timestamp, $timestamp);
      INSERT INTO recipes VALUES ('recipe-1', '旧食谱', 1, 100, NULL, 1, $timestamp, $timestamp);
      INSERT INTO recipe_items VALUES ('recipe-item-1', 'recipe-1', 'food-1', 150, $timestamp, $timestamp);
      INSERT INTO meal_plan_entries VALUES ('plan-1', '2026-10-03', 'recipe-1', $timestamp, $timestamp);
      INSERT INTO food_price_facts VALUES ('food-1', 850, 'CNY', $timestamp);
      INSERT INTO pantry_stocks VALUES ('food-1', 250, $timestamp);
      PRAGMA user_version = 18;
    ''');
  } finally {
    database.dispose();
  }
}

/// 裁剪过的 v1 库：只建迁移链会触碰到的表（仓库惯例；参见
/// `app_database_migration_test.dart` 的 `_createV1Database`）。
///
/// **刻意不建** recipes / recipe_items / meal_plan_entries /
/// food_price_facts / pantry_stocks —— v1 时代它们还不存在。
void _createTrimmedV1Database(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
    const timestamp = 1780000000000;
    database.execute('''
      CREATE TABLE profiles (
        id TEXT NOT NULL PRIMARY KEY,
        birth_year INTEGER NULL,
        biological_sex TEXT NULL,
        height_cm REAL NULL,
        activity_level TEXT NOT NULL,
        dietary_preferences_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE foods (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        kcal_per100g REAL NOT NULL,
        protein_per100g REAL NOT NULL,
        carbs_per100g REAL NOT NULL,
        fat_per100g REAL NOT NULL,
        source TEXT NOT NULL,
        is_user_created INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE measurements (
        id TEXT NOT NULL PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id),
        local_date TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE meals (
        id TEXT NOT NULL PRIMARY KEY,
        local_date TEXT NOT NULL,
        slot TEXT NOT NULL,
        eaten_at INTEGER NOT NULL,
        source TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE meal_items (
        id TEXT NOT NULL PRIMARY KEY,
        meal_id TEXT NOT NULL REFERENCES meals(id) ON DELETE CASCADE,
        food_id TEXT NULL REFERENCES foods(id),
        food_name_snapshot TEXT NOT NULL,
        grams REAL NOT NULL,
        kcal_snapshot REAL NOT NULL,
        protein_snapshot REAL NOT NULL,
        carbs_snapshot REAL NOT NULL,
        fat_snapshot REAL NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      INSERT INTO profiles VALUES ('profile-v1', 1990, 'female', 165, 'moderate', '[]', $timestamp, $timestamp);
      INSERT INTO foods VALUES ('food-v1', '米饭', 116.0, 2.6, 25.9, 0.3, 'seed-v1', 0, $timestamp, $timestamp);
      INSERT INTO measurements VALUES ('measurement-v1', 'profile-v1', '2026-09-10', 70, $timestamp, $timestamp);
      INSERT INTO meals VALUES ('meal-v1', '2026-09-10', 'lunch', $timestamp, 'manual', $timestamp, $timestamp);
      INSERT INTO meal_items VALUES ('item-v1', 'meal-v1', 'food-v1', '米饭', 180, 209, 4.7, 46.5, 0.5, $timestamp, $timestamp);
      PRAGMA user_version = 1;
    ''');
  } finally {
    database.dispose();
  }
}
