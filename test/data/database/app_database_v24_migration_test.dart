import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// T8（docs/32 §4 T8 / §3 D10）：schema 23 → 24 —— **删列迁移**。
///
/// 本仓第二次减列（第一次是 docs/31 S2 的 v22）。减法迁移的失败模式比加法多，
/// 所以这里钉四件事：
/// 1. v23 老库（有 `manual_commute_minutes` 且**行里有值**）升级后：列没了、
///    其余列与行数据一字不动（删列最怕连带误伤）；
/// 2. **幂等**：已删的库再升一遍不抛（`DROP COLUMN` 没有 `IF EXISTS`，
///    所以实现必须按列存在性判断）；
/// 3. **裁剪库**（fixture 没建 `profiles` 表）升级不抛错——先查表在不在；
/// 4. 新装即当前 schema：表里没有这一列（表类已删，建表定义自然不含）。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v24-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('v23 老库升级：退役列删除，其余列与行数据一字不动', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV23Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], database.schemaVersion);

    final names =
        (await database.customSelect('PRAGMA table_info(profiles)').get())
            .map((row) => row.data['name'])
            .toList();
    expect(
      names,
      isNot(contains('manual_commute_minutes')),
      reason: 'D10：该列必须随纵切一起删掉',
    );
    expect(
      names,
      containsAll(<String>[
        'id',
        'birth_year',
        'biological_sex',
        'height_cm',
        'activity_level',
        'dietary_preferences_json',
        'allergen_avoidances_json',
        'pantry_coverage_enabled',
        'display_name',
        'avatar_path',
        'created_at',
        'updated_at',
      ]),
      reason: '删列不许误伤——身份列（v23 加的）与既有列都还在',
    );

    // 行数据（含老库里那一列的值）照旧读得出来：删的只是那一列。
    final row = (await database.select(database.profiles).get()).single;
    expect(row.id, 'p-v23');
    expect(row.heightCm, 172.5);
    expect(row.activityLevel, 'moderate');
    expect(row.displayName, '李雷');
  });

  test('迁移幂等：列已删的库再升级不抛错', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV23Database(file.path);

    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('SELECT 1');
    await first.close();

    // 第二次打开：`from` 已经是当前版本，迁移整体跳过；即便执行器被叫到，
    // 列存在性判断也不会第二次 DROP。
    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final names =
        (await second.customSelect('PRAGMA table_info(profiles)').get())
            .map((row) => row.data['name'])
            .toList();
    expect(names.where((n) => n == 'manual_commute_minutes'), isEmpty);
  });

  test('裁剪库（fixture 没有 profiles 表）：升级不抛错', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}trimmed.sqlite');
    final raw = sqlite.sqlite3.open(file.path);
    // 只造一张无关表 + 老版本号：迁移链要能一路走到底，且删列分支先查表在不在。
    raw.execute('CREATE TABLE unrelated (id TEXT NOT NULL PRIMARY KEY)');
    raw.execute('PRAGMA user_version = 23');
    raw.dispose();

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], database.schemaVersion);
  });

  test('半迁移库（profiles 在、退役列已缺，版本号仍 23）：升级不抛错', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}half.sqlite');
    // 这不是臆想的形态：fixture 裁剪、或上一轮 DROP 成功而版本号没落盘
    // （崩溃中断）都会长这样。`DROP COLUMN` 没有 `IF EXISTS`，所以实现必须
    // 按**列存在性**判断——这条就是那个判断的守卫测试（M4 变异实测：去掉它
    // 这条会以 `no such column` 变红）。
    _createV23Database(file.path, withRetiredColumn: false);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], database.schemaVersion);
    // 「跳过 DROP」不等于「跳过整个迁移」：行与资料列都还在。
    final row = (await database.select(database.profiles).get()).single;
    expect(row.id, 'p-v23');
    expect(row.displayName, '李雷');
  });

  test('新装即当前 schema：表定义里没有退役列', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final names =
        (await database.customSelect('PRAGMA table_info(profiles)').get())
            .map((row) => row.data['name'])
            .toList();
    expect(names, isNot(contains('manual_commute_minutes')));
  });
}

/// 造一个 v23 形态的库：profiles 含全部历史列与一行有值数据。
/// [withRetiredColumn] = false 仿「半迁移库」：版本号还停在 23，但退役列
/// 已经不在了（见上面那条守卫测试的注释）。
void _createV23Database(String path, {bool withRetiredColumn = true}) {
  final retiredColumn = withRetiredColumn
      ? 'manual_commute_minutes INTEGER,'
      : '';
  final insert = withRetiredColumn
      ? "INSERT INTO profiles (id, height_cm, activity_level, "
            "manual_commute_minutes, display_name, created_at, updated_at) "
            "VALUES ('p-v23', 172.5, 'moderate', 25, '李雷', 1, 1)"
      : "INSERT INTO profiles (id, height_cm, activity_level, "
            "display_name, created_at, updated_at) "
            "VALUES ('p-v23', 172.5, 'moderate', '李雷', 1, 1)";
  final db = sqlite.sqlite3.open(path);
  db.execute('''
    CREATE TABLE profiles (
      id TEXT NOT NULL PRIMARY KEY,
      birth_year INTEGER,
      biological_sex TEXT,
      height_cm REAL,
      activity_level TEXT NOT NULL,
      dietary_preferences_json TEXT NOT NULL DEFAULT '[]',
      allergen_avoidances_json TEXT NOT NULL DEFAULT '[]',
      planning_budget_minor_units INTEGER,
      planning_budget_currency TEXT,
      maximum_draft_declared_minutes INTEGER,
      pantry_coverage_enabled INTEGER NOT NULL DEFAULT 0,
      $retiredColumn
      display_name TEXT,
      avatar_path TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ''');
  db.execute(insert);
  db.execute('PRAGMA user_version = 23');
  db.dispose();
}
