import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 2.0-3 Menu v1：v11 → v12 迁移测试。
/// 用 sqlite3 原生 DDL 构造 v11 库（Menu v1 表不存在），打开 AppDatabase
/// 验证 9 张 Menu 表被创建、既有数据保留、CRUD 与级联删除行为。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v12-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'upgrades a populated v11 database to v12 with Menu v1 tables',
    () async {
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
      );
      _createV11Database(file.path);

      final database = AppDatabase(NativeDatabase(file));
      addTearDown(() async {
        await database.close();
      });

      // 既有数据保留。
      expect(
        (await database.select(database.foods).get()).single.id,
        'food-v11',
      );
      expect(
        (await database.select(database.mealItems).get())
            .single
            .foodNameSnapshot,
        '旧饭',
      );
      final version = await database
          .customSelect('PRAGMA user_version')
          .getSingle();
      // 终点是当前 schemaVersion（v18 → 19 只删表，见 docs/28 §6.5）。
      // 升到**当前** schema（单一事实源）：写死数字会在每次加版本时
      // 过期一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
      expect(version.data['user_version'], database.schemaVersion);

      // 9 张 Menu v1 表存在且为空。
      expect(await database.select(database.campusProfiles).get(), isEmpty);
      expect(await database.select(database.venues).get(), isEmpty);
      expect(await database.select(database.menuSources).get(), isEmpty);
      expect(await database.select(database.menuSnapshots).get(), isEmpty);
      expect(await database.select(database.menuServices).get(), isEmpty);
      expect(await database.select(database.menuItems).get(), isEmpty);
      expect(
        await database.select(database.menuItemFoodMatches).get(),
        isEmpty,
      );
      expect(
        await database.select(database.menuItemNutritionEvidence).get(),
        isEmpty,
      );
      expect(await database.select(database.menuImportJobs).get(), isEmpty);

      // CRUD + 级联：campus → venue → source → snapshot → service → item。
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
              sourceType: 'pasted_text',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.menuSnapshots)
          .insert(
            MenuSnapshotsCompanion.insert(
              id: 'snapshot-1',
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
              id: 'service-1',
              snapshotId: 'snapshot-1',
              name: '一楼窗口',
              openTime: '10:30',
              closeTime: '13:30',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.menuItems)
          .insert(
            MenuItemsCompanion.insert(
              id: 'item-1',
              serviceId: 'service-1',
              displayName: '鸡蛋炒饭',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.menuItemFoodMatches)
          .insert(
            MenuItemFoodMatchesCompanion.insert(
              id: 'match-1',
              menuItemId: 'item-1',
              foodId: 'food-v11',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.menuItemNutritionEvidence)
          .insert(
            MenuItemNutritionEvidenceCompanion.insert(
              id: 'evidence-1',
              menuItemId: 'item-1',
              grade: 'C',
              origin: 'ai_inferred',
              createdAt: now,
              updatedAt: now,
            ),
          );

      // 删除 campus 级联清空整条菜单链。
      await (database.delete(
        database.campusProfiles,
      )..where((row) => row.id.equals('campus-1'))).go();
      expect(await database.select(database.venues).get(), isEmpty);
      expect(await database.select(database.menuSources).get(), isEmpty);
      expect(await database.select(database.menuSnapshots).get(), isEmpty);
      expect(await database.select(database.menuServices).get(), isEmpty);
      expect(await database.select(database.menuItems).get(), isEmpty);
      expect(
        await database.select(database.menuItemFoodMatches).get(),
        isEmpty,
      );
      expect(
        await database.select(database.menuItemNutritionEvidence).get(),
        isEmpty,
      );

      // 既有数据仍未被菜单操作影响。
      expect(
        (await database.select(database.foods).get()).single.id,
        'food-v11',
      );
    },
  );

  test('menu import job survives snapshot cascade and tracks status', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV11Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(() async {
      await database.close();
    });

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
            sourceType: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuImportJobs)
        .insert(
          MenuImportJobsCompanion.insert(
            id: 'job-1',
            sourceId: 'source-1',
            status: 'completed',
            startedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

    // 删除 source 级联清 venue 链；import job 也随 source 级联删除
    //（sourceId FK cascade），与 food_import_jobs 的独立语义不同。
    await (database.delete(
      database.menuSources,
    )..where((row) => row.id.equals('source-1'))).go();
    expect(await database.select(database.menuImportJobs).get(), isEmpty);
  });
}

void _createV11Database(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
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
''');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    database.execute(
      "INSERT INTO foods (id, name, kcal_per100g, protein_per100g,"
      " carbs_per100g, fat_per100g, source, is_user_created, created_at,"
      " updated_at) VALUES"
      " ('food-v11', '米饭', 130, 2.7, 28, 0.3, 'seed', 0, $now, $now)",
    );
    database.execute(
      "INSERT INTO meals (id, local_date, slot, eaten_at, source, created_at,"
      " updated_at) VALUES ('meal-v11', '2026-09-15', 'lunch', $now,"
      " 'manual', $now, $now)",
    );
    database.execute(
      "INSERT INTO meal_items (id, meal_id, food_id, food_name_snapshot,"
      " grams, kcal_snapshot, protein_snapshot, carbs_snapshot, fat_snapshot,"
      " created_at, updated_at) VALUES"
      " ('item-v11', 'meal-v11', 'food-v11', '旧饭', 200, 260, 5.4, 56,"
      " 0.6, $now, $now)",
    );
    // v11 状态：Menu v1 表尚未存在。
    database.execute('PRAGMA user_version = 11');
  } finally {
    database.dispose();
  }
}
