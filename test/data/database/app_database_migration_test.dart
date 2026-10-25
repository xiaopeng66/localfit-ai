import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'upgrades a populated v1 database to the current schema without secrets',
    () async {
      final directory = await Directory.systemTemp.createTemp('localfit-v1-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV1Database(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      final profiles = await database.select(database.profiles).get();
      final goals = await database.select(database.goals).get();
      final targets = await database.select(database.dailyTargets).get();
      final measurements = await database.select(database.measurements).get();
      final foods = await database.select(database.foods).get();
      final meals = await database.select(database.meals).get();
      final items = await database.select(database.mealItems).get();
      final configs = await database.select(database.aiProviderConfigs).get();
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      final configColumns = await database
          .customSelect('PRAGMA table_info(ai_provider_configs)')
          .get();

      expect(profiles.single.id, 'profile-v1');
      expect(goals.single.profileId, 'profile-v1');
      expect(targets.single.goalId, 'goal-v1');
      expect(measurements.single.profileId, 'profile-v1');
      expect(foods.single.id, 'food-v1');
      expect(meals.single.id, 'meal-v1');
      expect(items.single.mealId, 'meal-v1');
      expect(items.single.foodId, 'food-v1');
      expect(configs, isEmpty);
      // profiles 侧的过敏回避**仍在**（docs/31 §2 D5：只删食物侧）。
      expect(profiles.single.allergenAvoidancesJson, '[]');
      // 食物侧三列随 schema 22 删除（docs/31 S2，需求 50）：v1 老库一路
      // 升到当前 schema 后，这三列**必须不在**——这条断的是「所有起点
      // 的库走完迁移链都到达同一个终点形状」。
      final foodColumns = await database
          .customSelect('PRAGMA table_info(foods)')
          .get();
      final foodNames = foodColumns.map((row) => row.data['name']).toList();
      expect(foodNames, isNot(contains('constraint_knowledge')));
      expect(foodNames, isNot(contains('dietary_labels_json')));
      expect(foodNames, isNot(contains('allergens_json')));
      // 升到**当前** schema（单一事实源）：写死数字会在每次加版本时
      // 过期一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
      expect(version.data['user_version'], database.schemaVersion);
      expect(await database.select(database.exercises).get(), isEmpty);
      expect(await database.select(database.workoutPlans).get(), isEmpty);
      expect(await database.select(database.workoutDays).get(), isEmpty);
      expect(await database.select(database.plannedExercises).get(), isEmpty);
      expect(await database.select(database.workoutSessions).get(), isEmpty);
      expect(await database.select(database.workoutSets).get(), isEmpty);
      expect(profiles.single.planningBudgetMinorUnits, isNull);
      expect(profiles.single.planningBudgetCurrency, isNull);
      expect(profiles.single.maximumDraftDeclaredMinutes, isNull);
      expect(profiles.single.pantryCoverageEnabled, isFalse);
      // v1 库从来没有过 recipes 族与价格/库存表，v19 迁移也必须把它当"没有"，
      // 而不是撞 `no such table`（docs/28 §6.5 的 `IF EXISTS` 守卫）。
      await _expectDroppedTablesAbsent(database);
      expect(
        configColumns.map((row) => row.data['name']),
        // protocol 是 v18 新增列、reasoning 是 v20 新增列：v1 库的这张表由
        // `from < 2` 分支用**当前**表定义建出，所以它一建就带这两列
        // （迁移路径不同、结果一致）。
        unorderedEquals(['id', 'base_url', 'model', 'protocol', 'reasoning']),
      );
    },
  );

  test(
    'upgrades a populated v2 database to the current schema and keeps its data',
    () async {
      final directory = await Directory.systemTemp.createTemp('localfit-v2-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV2Database(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      expect(
        (await database.select(database.profiles).get()).single.id,
        'profile-v1',
      );
      expect(
        (await database.select(database.meals).get()).single.id,
        'meal-v1',
      );
      expect(
        (await database.select(database.mealItems).get()).single.id,
        'item-v1',
      );
      expect(
        (await database.select(database.aiProviderConfigs).get()).single.id,
        'config-v2',
      );
      expect(await database.select(database.exercises).get(), isEmpty);
      expect(await database.select(database.workoutPlans).get(), isEmpty);
      expect(await database.select(database.workoutDays).get(), isEmpty);
      expect(await database.select(database.plannedExercises).get(), isEmpty);
      expect(await database.select(database.workoutSessions).get(), isEmpty);
      expect(await database.select(database.workoutSets).get(), isEmpty);
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .data['user_version'],
        database.schemaVersion,
      );
      await _expectDroppedTablesAbsent(database);
    },
  );

  test('upgrades a populated v3 database to the current schema and drops the recipe tables', () async {
    final directory = await Directory.systemTemp.createTemp('localfit-v3-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV3Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    expect(
      (await database.select(database.aiProviderConfigs).get()).single.id,
      'config-v2',
    );
    // v3 库里真实存在 recipes / recipe_items 两行（见 _createV3Database），
    // v19 的 DROP 必须把它们连表带行一起清掉（docs/28 §6.5 第 6 条：不可逆）。
    await _expectDroppedTablesAbsent(database);
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .data['user_version'],
      database.schemaVersion,
    );
    expect(await database.select(database.exercises).get(), isEmpty);
    expect(await database.select(database.workoutPlans).get(), isEmpty);
    expect(await database.select(database.workoutDays).get(), isEmpty);
    expect(await database.select(database.plannedExercises).get(), isEmpty);
    expect(await database.select(database.workoutSessions).get(), isEmpty);
    expect(await database.select(database.workoutSets).get(), isEmpty);
    // 其余数据（v1 fixture 的档案 / 餐次）在删表后原样保留。
    expect(
      (await database.select(database.profiles).get()).single.id,
      'profile-v1',
    );
    expect((await database.select(database.meals).get()).single.id, 'meal-v1');
  });
}

/// 被 docs/28 的 W4 整族删掉的五张表：升到 v19 后必须一张都不存在。
///
/// 这条断言同时充当 `IF EXISTS` 守卫的回归：v1/v2 老库里没有 recipes 族
/// （那两张表原先由已删除的 `from < 3` / `from < 4` 分支建），若迁移链写成
/// 裸 `DROP TABLE recipes`，老库升级会在这里抛 `no such table`。
Future<void> _expectDroppedTablesAbsent(AppDatabase database) async {
  final rows = await database
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
        "('recipes', 'recipe_items', 'meal_plan_entries', "
        "'food_price_facts', 'pantry_stocks')",
      )
      .get();
  expect(rows, isEmpty, reason: 'v19 迁移必须 DROP 掉食谱/计划/价格/库存五张表');
}

void _createV3Database(String path) {
  _createV2Database(path);
  final database = sqlite.sqlite3.open(path);
  try {
    const timestamp = 1780000000000;
    database.execute('''
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
        food_name_snapshot TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        grams REAL NOT NULL,
        kcal_snapshot REAL NOT NULL,
        protein_snapshot REAL NOT NULL,
        carbs_snapshot REAL NOT NULL,
        fat_snapshot REAL NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      INSERT INTO recipes VALUES ('recipe-v3', '旧食谱', 1, 100, NULL, 1, $timestamp, $timestamp);
      INSERT INTO recipe_items VALUES ('recipe-item-v3', 'recipe-v3', 'food-v1', '米饭', 0, 100, 116, 2.6, 25.9, 0.3, $timestamp, $timestamp);
      PRAGMA user_version = 3;
    ''');
  } finally {
    database.dispose();
  }
}

void _createV2Database(String path) {
  _createV1Database(path);
  final database = sqlite.sqlite3.open(path);
  try {
    database.execute('''
      CREATE TABLE ai_provider_configs (
        id TEXT NOT NULL PRIMARY KEY,
        base_url TEXT NOT NULL,
        model TEXT NOT NULL
      );
      INSERT INTO ai_provider_configs VALUES ('config-v2', 'https://example.invalid/v1', 'local-model');
      PRAGMA user_version = 2;
    ''');
  } finally {
    database.dispose();
  }
}

void _createV1Database(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
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
      CREATE TABLE goals (
        id TEXT NOT NULL PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id),
        type TEXT NOT NULL,
        target_weight_kg REAL NULL,
        calorie_min_kcal REAL NOT NULL,
        calorie_max_kcal REAL NOT NULL,
        effective_from INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE daily_targets (
        id TEXT NOT NULL PRIMARY KEY,
        goal_id TEXT NOT NULL REFERENCES goals(id),
        effective_date TEXT NOT NULL,
        calorie_min_kcal REAL NOT NULL,
        calorie_max_kcal REAL NOT NULL,
        protein_min_grams REAL NOT NULL,
        protein_max_grams REAL NOT NULL,
        carbs_min_grams REAL NOT NULL,
        carbs_max_grams REAL NOT NULL,
        fat_min_grams REAL NOT NULL,
        fat_max_grams REAL NOT NULL,
        water_target_ml REAL NOT NULL DEFAULT 2000,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE measurements (
        id TEXT NOT NULL PRIMARY KEY,
        profile_id TEXT NOT NULL REFERENCES profiles(id),
        local_date TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        body_fat_percent REAL NULL,
        source TEXT NOT NULL DEFAULT 'manual',
        notes TEXT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE foods (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT NULL,
        default_serving_grams REAL NULL,
        kcal_per100g REAL NOT NULL,
        protein_per100g REAL NOT NULL,
        carbs_per100g REAL NOT NULL,
        fat_per100g REAL NOT NULL,
        source TEXT NOT NULL,
        is_user_created INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE meals (
        id TEXT NOT NULL PRIMARY KEY,
        local_date TEXT NOT NULL,
        slot TEXT NOT NULL,
        eaten_at INTEGER NOT NULL,
        notes TEXT NULL,
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
        cooking_method TEXT NULL,
        estimate_min_grams REAL NULL,
        estimate_max_grams REAL NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      PRAGMA user_version = 1;
    ''');
    const timestamp = 1780000000000;
    database.execute(
      "INSERT INTO profiles VALUES ('profile-v1', 1990, 'female', 165, 'moderate', '[]', $timestamp, $timestamp);",
    );
    database.execute(
      "INSERT INTO goals VALUES ('goal-v1', 'profile-v1', 'lose_fat', NULL, 1600, 1800, $timestamp, 'active', $timestamp, $timestamp);",
    );
    database.execute(
      "INSERT INTO daily_targets VALUES ('target-v1', 'goal-v1', '2026-09-10', 1600, 1800, 100, 120, 150, 200, 45, 60, 2000, $timestamp, $timestamp);",
    );
    database.execute(
      "INSERT INTO measurements VALUES ('measurement-v1', 'profile-v1', '2026-09-10', 70, NULL, 'manual', NULL, $timestamp, $timestamp);",
    );
    database.execute(
      "INSERT INTO foods VALUES ('food-v1', '米饭', NULL, NULL, 116.0, 2.6, 25.9, 0.3, 'seed-v1', 0, $timestamp, $timestamp);",
    );
    database.execute(
      "INSERT INTO meals VALUES ('meal-v1', '2026-09-10', 'lunch', $timestamp, NULL, 'manual', $timestamp, $timestamp);",
    );
    database.execute(
      "INSERT INTO meal_items VALUES ('item-v1', 'meal-v1', 'food-v1', '米饭', 180, 209, 4.7, 46.5, 0.5, NULL, NULL, NULL, $timestamp, $timestamp);",
    );
  } finally {
    database.dispose();
  }
}
