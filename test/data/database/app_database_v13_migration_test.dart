import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 2.0-4a Planning v1：v12 → v13 迁移测试。
/// 用 sqlite3 原生 DDL 构造 v12 库（Planning v1 表不存在），打开
/// AppDatabase 验证 4 张 Planning 表被创建、既有数据保留、CRUD 与
/// 级联删除行为。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v13-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'upgrades a populated v12 database to v13 with Planning v1 tables',
    () async {
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV12Database(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
      });

      // 既有数据保留（v12 修复库里有 foods 行）。
      expect(
        (await database.select(database.foods).get()).single.id,
        'food-v12',
      );
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      // 终点是当前 schemaVersion（v18 → 19 只删表，见 docs/28 §6.5）。
      // 升到**当前** schema（单一事实源）：写死数字会在每次加版本时
      // 过期一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
      expect(version.data['user_version'], database.schemaVersion);

      // 4 张 Planning v1 表存在且为空。
      expect(
        await database.select(database.availabilityWindows).get(),
        isEmpty,
      );
      expect(await database.select(database.dailyPlans).get(), isEmpty);
      expect(await database.select(database.dailyPlanSlots).get(), isEmpty);
      expect(
        await database.select(database.dailyPlanCandidates).get(),
        isEmpty,
      );

      // v15：营养证据补了每 100g 代表值四列；v12 的「只有区间」历史行
      // 迁移后四个代表值仍为 null（读取侧按无营养处理，不取中点）。
      final evidence =
          (await database.select(database.menuItemNutritionEvidence).get())
              .single;
      expect(evidence.id, 'ev-v12');
      expect(evidence.kcalMin, 500);
      expect(evidence.kcalMax, 700);
      expect(evidence.kcalPer100g, isNull);
      expect(evidence.proteinPer100g, isNull);
      expect(evidence.carbsPer100g, isNull);
      expect(evidence.fatPer100g, isNull);

      // CRUD + 级联：plan → slot → candidate。
      final now = DateTime.now().toUtc();
      await database
          .into(database.dailyPlans)
          .insert(
            DailyPlansCompanion.insert(
              id: 'plan-1',
              localDate: '2026-09-15',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.dailyPlanSlots)
          .insert(
            DailyPlanSlotsCompanion.insert(
              id: 'slot-1',
              planId: 'plan-1',
              slot: 'lunch',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.dailyPlanCandidates)
          .insert(
            DailyPlanCandidatesCompanion.insert(
              id: 'cand-1',
              slotId: 'slot-1',
              kind: 'menu_item',
              refId: 'item-1',
              displayName: '鸡蛋炒饭',
              createdAt: now,
              updatedAt: now,
            ),
          );
      expect(
        (await database.select(database.dailyPlanCandidates).get()).single.id,
        'cand-1',
      );

      // 删除 plan 级联清空 slot 与 candidate。
      await (database.delete(
        database.dailyPlans,
      )..where((p) => p.id.equals('plan-1'))).go();
      expect(await database.select(database.dailyPlans).get(), isEmpty);
      expect(await database.select(database.dailyPlanSlots).get(), isEmpty);
      expect(
        await database.select(database.dailyPlanCandidates).get(),
        isEmpty,
      );
    },
  );

  test('availability windows CRUD', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV12Database(file.path);
    final database = AppDatabase(NativeDatabase(file));
    addTearDown(() async {
      await database.close();
    });

    final now = DateTime.now().toUtc();
    await database
        .into(database.availabilityWindows)
        .insert(
          AvailabilityWindowsCompanion.insert(
            id: 'win-1',
            startMinute: 11 * 60,
            endMinute: 13 * 60,
            kind: 'dining',
            localDate: const Value('2026-09-15'),
            label: const Value('午休'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final row = await database.select(database.availabilityWindows).getSingle();
    expect(row.startMinute, 660);
    expect(row.kind, 'dining');
    expect(row.weekdays, '');
  });
}

/// 原生 DDL 构造 v12 库：Foods/Meals/MealItems（v11 形状）+ Menu v1
/// 九表（占位最小列）。Planning v1 表由迁移创建。
void _createV12Database(String path) {
  final database = sqlite.sqlite3.open(path);
  database.execute('PRAGMA user_version = 12');
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
  updated_at INTEGER NOT NULL,
  state TEXT NOT NULL DEFAULT 'verified',
  locale TEXT NULL,
  category TEXT NULL,
  source_version INTEGER NULL,
  license_status TEXT NOT NULL DEFAULT 'unknown'
);
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
  meal_id TEXT NOT NULL REFERENCES meals(id),
  food_id TEXT NULL,
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
CREATE TABLE menu_snapshots (
  id TEXT NOT NULL PRIMARY KEY,
  source_id TEXT NOT NULL,
  venue_id TEXT NOT NULL,
  business_date TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  raw_content_path TEXT NULL,
  raw_content_hash TEXT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  imported_at INTEGER NOT NULL,
  expires_at INTEGER NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
-- v12 形状的营养证据表：只有区间列，没有 v15 的每 100g 代表值四列。
CREATE TABLE menu_item_nutrition_evidence (
  id TEXT NOT NULL PRIMARY KEY,
  menu_item_id TEXT NOT NULL REFERENCES menu_items (id) ON DELETE CASCADE,
  grade TEXT NOT NULL,
  origin TEXT NOT NULL,
  kcal_min REAL NULL,
  kcal_max REAL NULL,
  source_text TEXT NULL,
  confidence REAL NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE menu_items (
  id TEXT NOT NULL PRIMARY KEY,
  service_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  database.execute(
    "INSERT INTO foods (id, name, kcal_per100g, protein_per100g,"
    " carbs_per100g, fat_per100g, source, is_user_created, created_at,"
    " updated_at) VALUES"
    " ('food-v12', '米饭', 130, 2.7, 28, 0.3, 'seed', 0, $now, $now)",
  );
  // 一条「只有区间、没有代表值」的历史营养证据：迁移后四个代表值列必须
  // 是 null（读取侧按「无营养」处理，绝不拿区间中点冒充事实）。
  database.execute(
    "INSERT INTO menu_items (id, service_id, display_name, created_at,"
    " updated_at) VALUES ('item-v12', 'svc-v12', '鸡蛋炒饭', $now, $now)",
  );
  database.execute(
    "INSERT INTO menu_item_nutrition_evidence (id, menu_item_id, grade,"
    " origin, kcal_min, kcal_max, created_at, updated_at) VALUES"
    " ('ev-v12', 'item-v12', 'C', 'estimated_range', 500, 700, $now, $now)",
  );
  database.dispose();
}
