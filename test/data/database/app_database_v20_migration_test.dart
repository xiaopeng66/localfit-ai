import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// docs/29 §P4（D5 的 19→20 一次迁移，本包先落 AI 推理开关列；
/// 菜品图片与步数表后续走同一版）：
///  * v19 库的 `ai_provider_configs` 没有 `reasoning` 列 ⇒ addColumn 补上，
///    旧行保持 null＝「从未选过」，读取侧回落「关闭推理」；
///  * v1 库（`from < 2` 建表分支）一路升上来不抛错，新表一建就带全列
///    （下界守卫防 duplicate column）。
///
/// 旧行 protocol 为 null 的语义不受影响：迁移只加列、不改行。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v20-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('upgrades a populated v19 database to the current schema and adds reasoning', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV19Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    // ① 版本号走到当前 schema（见下断言）。
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    // 升到**当前** schema（单一事实源）：写死数字会在每次加版本时
    // 过期一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
    expect(version.data['user_version'], database.schemaVersion);

    // ② reasoning 列已补上。
    final columns = await database
        .customSelect('PRAGMA table_info(ai_provider_configs)')
        .get();
    expect(columns.map((row) => row.data['name']), contains('reasoning'));

    // ③ 旧行一字不动（protocol 为 null＝从未选过协议；reasoning 为 null＝
    //    从未选过推理档）。Drift 读出后按回落口径得到「关闭推理」。
    final row = await (database.select(
      database.aiProviderConfigs,
    )..where((config) => config.id.equals('default'))).getSingle();
    expect(row.baseUrl, 'https://old.example.com/v1/');
    expect(row.model, 'old-model');
    expect(row.protocol, isNull);
    expect(row.reasoning, isNull);
    expect(
      AiReasoningMode.fromStorage(row.reasoning),
      AiReasoningMode.disabled,
    );

    // ④ 新写入走完整语义：显式选「默认（由上游决定）」要能原样落库。
    await database
        .into(database.aiProviderConfigs)
        .insertOnConflictUpdate(
          AiProviderConfigsCompanion.insert(
            id: 'default',
            baseUrl: 'https://old.example.com/v1/',
            model: 'old-model',
            reasoning: Value(AiReasoningMode.providerDefault.storageValue),
          ),
        );
    final updated = await database
        .select(database.aiProviderConfigs)
        .getSingle();
    expect(
      AiReasoningMode.fromStorage(updated.reasoning),
      AiReasoningMode.providerDefault,
    );
  });

  test('upgrades a trimmed v1 database straight to the current schema without throwing', () async {
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

    // v1 库的这张表由 `from < 2` 分支用**当前**表定义建出：一建就带
    // reasoning 列，`from < 20` 的 addColumn 必须被下界守卫跳过——
    // 若守卫写错（如去掉 from >= 2），这里会 duplicate column 崩溃。
    final columns = await database
        .customSelect('PRAGMA table_info(ai_provider_configs)')
        .get();
    final names = columns.map((row) => row.data['name']).toList();
    expect(names.where((name) => name == 'reasoning'), hasLength(1));
  });
}

/// v19 线上库的相关部分：`ai_provider_configs` 一行（**没有** reasoning 列，
/// 与 v19 的表定义一致）。
void _createV19Database(String path) {
  final database = sqlite.sqlite3.open(path);
  try {
    database.execute('''
      CREATE TABLE ai_provider_configs (
        id TEXT NOT NULL PRIMARY KEY,
        base_url TEXT NOT NULL,
        model TEXT NOT NULL,
        protocol TEXT NULL
      );
      INSERT INTO ai_provider_configs
        VALUES ('default', 'https://old.example.com/v1/', 'old-model', NULL);
      PRAGMA user_version = 19;
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
