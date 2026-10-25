import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 2.0-6i-2 的 `manual_commute_minutes`：v13 → v14 曾是**加法**迁移（补列、
/// 旧行保持 null = 未填写）；Round 5 T8（schema 24）随整条纵切又把它**删掉**
/// （docs/32 §3 D10）。
///
/// 本测试因此钉的是**迁移链走到底**：一个 v13 老库升到当前 schema 后，
/// ① 档案行与既有列一字不动；② v14 补过的那一列**已经不存在**——两段迁移
/// （加、删）都真的跑过。链条中途的形状不在这里断言（那是各版本分支的事）。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v14-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('upgrades a populated v13 database to the current schema', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV13Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(() async {
      await database.close();
    });

    // ① 老档案保留，既有列一字不动（v13 没有昵称列 → null，不编造）。
    final profile = (await database.select(database.profiles).get()).single;
    expect(profile.id, 'profile-v13');
    expect(profile.activityLevel, 'moderate');
    expect(profile.displayName, isNull);

    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    // 终点是当前 schemaVersion（单一事实源）：写死数字会在每次加版本时过期
    // 一片（docs/29 §P7 一次就点了 12 处），这里只断言迁移链走到底。
    expect(version.data['user_version'], database.schemaVersion);

    // ② 退役列不存在：v14 补过、v24 删掉——加与删两段都走到了。
    final retired = await database
        .customSelect(
          "SELECT 1 FROM pragma_table_info('profiles') "
          "WHERE name = 'manual_commute_minutes'",
        )
        .getSingleOrNull();
    expect(retired, isNull, reason: 'T8 之后 manual_commute_minutes 不该再存在');

    // ③ 库仍然可用（删列没有把表弄坏）：写读一条既有列。
    await (database.update(database.profiles)
          ..where((row) => row.id.equals('profile-v13')))
        .write(const ProfilesCompanion(activityLevel: Value('active')));
    expect(
      (await database.select(database.profiles).get()).single.activityLevel,
      'active',
    );
  });
}

void _createV13Database(String path) {
  final database = sqlite.sqlite3.open(path);
  database.execute('PRAGMA user_version = 13');
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
);
-- v13 库里的营养证据表仍是 v12 形状（无每 100g 代表值四列），
-- 迁移到 v15 时这四列会被补上。
CREATE TABLE menu_item_nutrition_evidence (
  id TEXT NOT NULL PRIMARY KEY,
  menu_item_id TEXT NOT NULL,
  grade TEXT NOT NULL,
  origin TEXT NOT NULL,
  kcal_min REAL NULL,
  kcal_max REAL NULL,
  source_text TEXT NULL,
  confidence REAL NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
  database.execute(
    "INSERT INTO profiles (id, activity_level, created_at, updated_at) "
    "VALUES ('profile-v13', 'moderate', 1757000000, 1757000000)",
  );
  database.dispose();
}
