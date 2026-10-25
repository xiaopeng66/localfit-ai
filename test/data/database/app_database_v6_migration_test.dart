import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test(
    'upgrades a populated v5 database and drops the recipe tables',
    () async {
      final directory = await Directory.systemTemp.createTemp('localfit-v5-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV5Database(file.path);
      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      final profile = await database.select(database.profiles).getSingle();
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();

      // 升到**当前** schema（单一事实源）：写死数字会在每次加版本时
      // 过期一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
      expect(version.data['user_version'], database.schemaVersion);
      expect(await database.select(database.exercises).get(), isEmpty);
      expect(await database.select(database.workoutPlans).get(), isEmpty);
      expect(await database.select(database.workoutDays).get(), isEmpty);
      expect(await database.select(database.plannedExercises).get(), isEmpty);
      expect(await database.select(database.workoutSessions).get(), isEmpty);
      expect(await database.select(database.workoutSets).get(), isEmpty);
      expect(profile.id, 'profile-v5');
      // v5 那四个 planning 列保留为惰性空列（docs/28 §6.7「保留不动」）。
      expect(profile.planningBudgetMinorUnits, isNull);
      expect(profile.planningBudgetCurrency, isNull);
      expect(profile.maximumDraftDeclaredMinutes, isNull);
      expect(profile.pantryCoverageEnabled, isFalse);
      // 除删表外其余数据原样保留：档案、食物、以及 v5 时代写入的食谱行所属
      // 表被删掉，但 foods 不受影响。
      expect((await database.select(database.foods).getSingle()).id, 'food-v5');
      // v5 库里的 recipes / recipe_items / meal_plan_entries 各有一行（含
      // `recipe_id` 外键引用），v19 的 DROP 必须把它们连表带行一起清掉；
      // 价格/库存两张表在 v5 库中从未建过（原先由已删除的 `from < 6` 建），
      // 裸 DROP 会在这里抛 `no such table` —— 这条断言就是 `IF EXISTS` 的
      // 回归守卫（docs/28 §6.5/§6.7）。
      final dropped = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
            "('recipes', 'recipe_items', 'meal_plan_entries', "
            "'food_price_facts', 'pantry_stocks')",
          )
          .get();
      expect(dropped, isEmpty, reason: 'v19 迁移必须 DROP 掉食谱/计划/价格/库存五张表');
    },
  );
}

void _createV5Database(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
    const timestamp = 1780000000000;
    database.execute('''
      PRAGMA foreign_keys = ON;
      CREATE TABLE profiles (
        id TEXT NOT NULL PRIMARY KEY,
        birth_year INTEGER NULL,
        biological_sex TEXT NULL,
        height_cm REAL NULL,
        activity_level TEXT NOT NULL,
        dietary_preferences_json TEXT NOT NULL DEFAULT '[]',
        allergen_avoidances_json TEXT NOT NULL DEFAULT '[]',
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
        constraint_knowledge TEXT NOT NULL DEFAULT 'unknown',
        dietary_labels_json TEXT NOT NULL DEFAULT '[]',
        allergens_json TEXT NOT NULL DEFAULT '[]',
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
      -- v5 真实 schema 含这些表；v10 索引迁移需要在它们之上建索引。
      CREATE TABLE recipe_items (
        id TEXT NOT NULL PRIMARY KEY,
        recipe_id TEXT NOT NULL REFERENCES recipes(id),
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
      CREATE TABLE meal_plan_entries (
        id TEXT NOT NULL PRIMARY KEY,
        local_date TEXT NOT NULL,
        slot TEXT NOT NULL,
        recipe_id TEXT NOT NULL REFERENCES recipes(id),
        recipe_name_snapshot TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        servings REAL NOT NULL,
        kcal_snapshot REAL NOT NULL,
        protein_snapshot REAL NOT NULL,
        carbs_snapshot REAL NOT NULL,
        fat_snapshot REAL NOT NULL,
        revision INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      INSERT INTO profiles VALUES ('profile-v5', NULL, NULL, NULL, 'moderate', '[]', '[]', $timestamp, $timestamp);
      INSERT INTO foods VALUES ('food-v5', '米饭', NULL, NULL, 116, 2.6, 25.9, 0.3, 'test', 0, 'unknown', '[]', '[]', $timestamp, $timestamp);
      INSERT INTO recipes VALUES ('recipe-v5', '迁移食谱', 1, 100, NULL, 1, $timestamp, $timestamp);
      INSERT INTO meal_plan_entries VALUES ('plan-v5', '2026-09-10', 'lunch', 'recipe-v5', '迁移食谱', 0, 1, 116, 2.6, 25.9, 0.3, 1, $timestamp, $timestamp);
      PRAGMA user_version = 5;
    ''');
  } finally {
    database.dispose();
  }
}
