import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 2.0-1 schema v11 migration tests: the food-catalog tables must appear,
/// existing foods must get a correct backfilled `state`, and all pre-v11
/// data must survive the upgrade.
void main() {
  test(
    'upgrades a populated v10 database to v11 with catalog tables',
    () async {
      final directory = await Directory.systemTemp.createTemp('localfit-v11-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV10Database(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      // 终点是当前 schemaVersion（v18 → 19 只删表，见 docs/28 §6.5）。
      // 升到**当前** schema（单一事实源）：写死数字会在每次加版本时
      // 过期一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
      expect(version.data['user_version'], database.schemaVersion);

      // 旧行保留且回填 state：用户自建 → user_created，种子 → verified。
      final foods = await database.select(database.foods).get();
      expect(foods, hasLength(2));
      final states = {for (final food in foods) food.id: food.state};
      expect(states['food-seed'], 'verified');
      expect(states['food-user'], 'user_created');
      // 新列默认值。
      expect(foods.every((food) => food.licenseStatus == 'unknown'), isTrue);
      expect(foods.every((food) => food.locale == null), isTrue);

      // 新目录表存在且为空。
      expect(await database.select(database.foodAliases).get(), isEmpty);
      expect(
        await database.select(database.foodNutritionRevisions).get(),
        isEmpty,
      );
      expect(await database.select(database.foodPortions).get(), isEmpty);
      expect(await database.select(database.foodEvidence).get(), isEmpty);
      expect(await database.select(database.foodImportJobs).get(), isEmpty);

      // 既有数据不受影响：meals/meal_items 快照保留。
      expect(
        (await database.select(database.meals).get()).single.id,
        'meal-v10',
      );
      expect(
        (await database.select(database.mealItems).get()).single.kcalSnapshot,
        100,
      );
    },
  );

  test('v11 catalog tables accept rows and cascade on food deletion', () async {
    final directory = await Directory.systemTemp.createTemp('localfit-v11b-');
    final file = File(
      '${directory.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV10Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(() async {
      await database.close();
      await directory.delete(recursive: true);
    });

    final now = DateTime.utc(2026, 9, 15);
    await database
        .into(database.foodAliases)
        .insert(
          FoodAliasesCompanion.insert(
            id: 'alias-1',
            foodId: 'food-seed',
            normalizedText: 'rice',
            aliasType: 'translation',
            source: 'test',
            createdAt: now,
          ),
        );
    await database
        .into(database.foodNutritionRevisions)
        .insert(
          FoodNutritionRevisionsCompanion.insert(
            id: 'rev-1',
            foodId: 'food-seed',
            revisionNumber: 2,
            createdAt: now,
          ),
        );
    await database
        .into(database.foodPortions)
        .insert(
          FoodPortionsCompanion.insert(
            id: 'portion-1',
            foodId: 'food-seed',
            name: '一碗',
            grams: 200,
            source: 'test',
            createdAt: now,
          ),
        );
    await database
        .into(database.foodEvidence)
        .insert(
          FoodEvidenceCompanion.insert(
            id: 'ev-1',
            sourceId: 'openfoodfacts',
            license: 'ODbL',
            retrievedAt: now,
            transformVersion: 't1',
            qualityStatus: 'ok',
            recordHash: 'deadbeef',
            createdAt: now,
          ),
        );
    await database
        .into(database.foodImportJobs)
        .insert(
          FoodImportJobsCompanion.insert(
            id: 'job-1',
            catalogVersion: 1,
            status: 'completed',
            totalShards: 3,
            manifestHash: 'abc',
            startedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

    // 删除 canonical food 级联删除 alias/revision/portion。
    // food-seed 被 meal_items 快照引用（外键阻止删除），先删无引用的
    // food-user 验证无级联影响，再删 food-seed 前清掉引用行。
    await (database.delete(
      database.foods,
    )..where((row) => row.id.equals('food-user'))).go();
    expect(await database.select(database.foods).get(), hasLength(1));
    await database.delete(database.mealItems).go();
    await (database.delete(
      database.foods,
    )..where((row) => row.id.equals('food-seed'))).go();
    expect(await database.select(database.foodAliases).get(), isEmpty);
    expect(
      await database.select(database.foodNutritionRevisions).get(),
      isEmpty,
    );
    expect(await database.select(database.foodPortions).get(), isEmpty);
    // evidence 与 import job 与食物无外键，独立保留。
    expect(await database.select(database.foodEvidence).get(), hasLength(1));
    expect(await database.select(database.foodImportJobs).get(), hasLength(1));
  });
}

void _createV10Database(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
    const timestamp = 1780000000000;
    database.execute(
      'CREATE TABLE ai_provider_configs (id TEXT NOT NULL PRIMARY KEY)',
    );
    database.execute('''
      CREATE TABLE profiles (
        id TEXT NOT NULL PRIMARY KEY,
        birth_year INTEGER NULL,
        biological_sex TEXT NULL,
        height_cm REAL NULL,
        activity_level TEXT NOT NULL,
        dietary_preferences_json TEXT NOT NULL DEFAULT '[]',
        allergen_avoidances_json TEXT NOT NULL DEFAULT '[]',
        planning_budget_minor_units INTEGER NULL,
        planning_budget_currency TEXT NULL,
        maximum_draft_declared_minutes INTEGER NULL,
        pantry_coverage_enabled INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    database.execute('''
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
        constraint_knowledge TEXT NOT NULL DEFAULT 'unknown',
        dietary_labels_json TEXT NOT NULL DEFAULT '[]',
        allergens_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE meals (
        id TEXT NOT NULL PRIMARY KEY,
        local_date TEXT NOT NULL,
        slot TEXT NOT NULL,
        eaten_at INTEGER NOT NULL,
        notes TEXT NULL,
        source TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE meal_items (
        id TEXT NOT NULL PRIMARY KEY,
        meal_id TEXT NOT NULL REFERENCES meals (id) ON DELETE CASCADE,
        food_id TEXT NULL REFERENCES foods (id),
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
      )
    ''');
    // 剩余 v10 表只需要存在（空表）以让迁移通过。
    for (final ddl in const [
      'CREATE TABLE goals (id TEXT NOT NULL PRIMARY KEY, profile_id TEXT NOT NULL REFERENCES profiles (id), type TEXT NOT NULL, target_weight_kg REAL NULL, calorie_min_kcal REAL NOT NULL, calorie_max_kcal REAL NOT NULL, effective_from INTEGER NOT NULL, status TEXT NOT NULL DEFAULT \'active\', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE daily_targets (id TEXT NOT NULL PRIMARY KEY, goal_id TEXT NOT NULL REFERENCES goals (id), effective_date TEXT NOT NULL, calorie_min_kcal REAL NOT NULL, calorie_max_kcal REAL NOT NULL, protein_min_grams REAL NOT NULL, protein_max_grams REAL NOT NULL, carbs_min_grams REAL NOT NULL, carbs_max_grams REAL NOT NULL, fat_min_grams REAL NOT NULL, fat_max_grams REAL NOT NULL, water_target_ml REAL NOT NULL DEFAULT 2000, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE measurements (id TEXT NOT NULL PRIMARY KEY, profile_id TEXT NOT NULL REFERENCES profiles (id), local_date TEXT NOT NULL, weight_kg REAL NOT NULL, body_fat_percent REAL NULL, source TEXT NOT NULL DEFAULT \'manual\', notes TEXT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE food_price_facts (food_id TEXT NOT NULL PRIMARY KEY REFERENCES foods (id) ON DELETE CASCADE, minor_units_per_100g INTEGER NOT NULL, currency TEXT NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE pantry_stocks (food_id TEXT NOT NULL PRIMARY KEY REFERENCES foods (id) ON DELETE CASCADE, available_grams REAL NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE exercises (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, muscle_group TEXT NOT NULL, equipment TEXT NOT NULL, source TEXT NOT NULL, is_user_created INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE workout_plans (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, status TEXT NOT NULL DEFAULT \'active\', source TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE workout_days (id TEXT NOT NULL PRIMARY KEY, plan_id TEXT NOT NULL REFERENCES workout_plans (id) ON DELETE CASCADE, weekday INTEGER NOT NULL, sort_order INTEGER NOT NULL)',
      'CREATE TABLE planned_exercises (id TEXT NOT NULL PRIMARY KEY, day_id TEXT NOT NULL REFERENCES workout_days (id) ON DELETE CASCADE, exercise_id TEXT NOT NULL REFERENCES exercises (id), sort_order INTEGER NOT NULL, target_sets INTEGER NOT NULL, target_reps INTEGER NOT NULL, target_weight_kg REAL NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE workout_sessions (id TEXT NOT NULL PRIMARY KEY, plan_id TEXT NULL REFERENCES workout_plans (id) ON DELETE SET NULL, local_date TEXT NOT NULL, started_at INTEGER NOT NULL, finished_at INTEGER NULL, status TEXT NOT NULL DEFAULT \'active\', created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE workout_sets (id TEXT NOT NULL PRIMARY KEY, session_id TEXT NOT NULL REFERENCES workout_sessions (id) ON DELETE CASCADE, planned_exercise_id TEXT NULL REFERENCES planned_exercises (id) ON DELETE SET NULL, exercise_id TEXT NOT NULL REFERENCES exercises (id), sort_order INTEGER NOT NULL, weight_kg REAL NOT NULL, reps INTEGER NOT NULL, rpe REAL NULL, completed_at INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE recipes (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, servings REAL NOT NULL, finished_weight_grams REAL NOT NULL, notes TEXT NULL, revision INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE recipe_items (id TEXT NOT NULL PRIMARY KEY, recipe_id TEXT NOT NULL REFERENCES recipes (id) ON DELETE CASCADE, food_id TEXT NOT NULL REFERENCES foods (id), food_name_snapshot TEXT NOT NULL, sort_order INTEGER NOT NULL, grams REAL NOT NULL, kcal_snapshot REAL NOT NULL, protein_snapshot REAL NOT NULL, carbs_snapshot REAL NOT NULL, fat_snapshot REAL NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
      'CREATE TABLE meal_plan_entries (id TEXT NOT NULL PRIMARY KEY, local_date TEXT NOT NULL, slot TEXT NOT NULL, recipe_id TEXT NOT NULL REFERENCES recipes (id), recipe_name_snapshot TEXT NOT NULL, sort_order INTEGER NOT NULL, servings REAL NOT NULL, kcal_snapshot REAL NOT NULL, protein_snapshot REAL NOT NULL, carbs_snapshot REAL NOT NULL, fat_snapshot REAL NOT NULL, revision INTEGER NOT NULL DEFAULT 1, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)',
    ]) {
      database.execute(ddl);
    }

    database.execute(
      "INSERT INTO ai_provider_configs (id) VALUES ('config-v10')",
    );
    database.execute(
      "INSERT INTO profiles (id, activity_level, created_at, updated_at) VALUES ('profile-v10', 'moderate', $timestamp, $timestamp)",
    );
    database.execute(
      "INSERT INTO foods (id, name, kcal_per100g, protein_per100g, carbs_per100g, fat_per100g, source, is_user_created, created_at, updated_at) VALUES ('food-seed', '米饭', 116, 2.6, 25.9, 0.3, 'seed-v3', 0, $timestamp, $timestamp)",
    );
    database.execute(
      "INSERT INTO foods (id, name, kcal_per100g, protein_per100g, carbs_per100g, fat_per100g, source, is_user_created, created_at, updated_at) VALUES ('food-user', '我的私房菜', 200, 10, 20, 5, 'user', 1, $timestamp, $timestamp)",
    );
    database.execute(
      "INSERT INTO meals (id, local_date, slot, eaten_at, source, created_at, updated_at) VALUES ('meal-v10', '2026-09-10', 'lunch', $timestamp, 'manual', $timestamp, $timestamp)",
    );
    database.execute(
      "INSERT INTO meal_items (id, meal_id, food_id, food_name_snapshot, grams, kcal_snapshot, protein_snapshot, carbs_snapshot, fat_snapshot, created_at, updated_at) VALUES ('item-v10', 'meal-v10', 'food-seed', '米饭', 100, 100, 2.6, 25.9, 0.3, $timestamp, $timestamp)",
    );
    database.execute('PRAGMA user_version = 10');
  } finally {
    database.dispose();
  }
}
