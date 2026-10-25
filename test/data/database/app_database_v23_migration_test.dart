import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// T7（docs/32 §4 T7 / §3 D9）：schema 22 → 23 一次迁移。
///
/// **范围修订（2026-10-12，见 docs/32 §3 D9 的修订段）**：D9 原写「+2 列与
/// 删 `manualCommuteMinutes` 合并为一次迁移」；但实测该列在 67 个文件里被
/// 引用（含 drift 生成代码），而 T7 排在 T8 之前 ⇒ 先删列会让全仓编译失败、
/// 违反「每包独立过门禁 EXIT=0」。故 **T7 = schema 23（仅 +2 列）**，
/// **T8 = schema 23→24（删 `manual_commute_minutes`，与代码删除同包）**。
/// 终点 schema 一致。
///
/// 本文件钉三件事：
/// 1. v22 老库升级到当前 schema 后，`display_name` / `avatar_path` **存在且为 null**
///    （老数据没有昵称/头像 → 不编造）；
/// 2. **其余列一字不动**（加法迁移的失败模式是漏加或误伤）——唯一下线的是
///    T8 的退役列 `manual_commute_minutes`（本文件 fixture 的 v22 形态里
///    有它，升级后必须没了）；
/// 3. **幂等**：列已在的库再跑一遍不抛错（按列存在性判断）。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v23-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('v22 老库升级：+display_name/+avatar_path 且为 null，其余资料列不动', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV22Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    // ① 版本走到当前 schema（不写死 23：下一次加版本时这条不该过期）。
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], database.schemaVersion);

    // ② 两个新列在，且老行为 null（未填 ≠ 空串）。
    final columns = await database
        .customSelect('PRAGMA table_info(profiles)')
        .get();
    final names = columns.map((row) => row.data['name']).toList();
    expect(names, contains('display_name'), reason: 'D9：昵称列必须加上');
    expect(names, contains('avatar_path'), reason: 'D9：头像路径列必须加上');
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
        'created_at',
        'updated_at',
      ]),
      reason: '加法迁移不许误伤既有列',
    );
    // T8（schema 23→24）：退役列随纵切一起下线，升级后不该再存在。
    expect(
      names,
      isNot(contains('manual_commute_minutes')),
      reason: 'T8 之后该列必须已经被 DROP 掉（fixture 里 v22 形态是有它的）',
    );

    final row = (await database.select(database.profiles).get()).single;
    expect(row.displayName, isNull, reason: '老库没有昵称 → null，不编造');
    expect(row.avatarPath, isNull, reason: '老库没有头像 → null，不编造');
    // 既有身体数据一字不动。
    expect(row.heightCm, 172.5);
    expect(row.biologicalSex, 'male');
    expect(row.birthYear, 1998);
    expect(row.activityLevel, 'moderate');
  });

  test('迁移幂等：列已存在的库再升级不抛错', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('SELECT 1');
    await first.close();

    // 第二次打开：迁移按列存在性判断，已是当前版本时不应抛。
    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final columns = await second
        .customSelect('PRAGMA table_info(profiles)')
        .get();
    final names = columns.map((row) => row.data['name']).toList();
    expect(names.where((n) => n == 'display_name').length, 1);
    expect(names.where((n) => n == 'avatar_path').length, 1);
  });

  test('新装即当前 schema：昵称/头像列存在且可写读', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'p-1',
            activityLevel: 'moderate',
            createdAt: DateTime(2026, 10, 12),
            updatedAt: DateTime(2026, 10, 12),
            displayName: const Value('李雷'),
            avatarPath: const Value('/docs/avatar/a.jpg'),
          ),
        );
    final row = (await database.select(database.profiles).get()).single;
    expect(row.displayName, '李雷');
    expect(row.avatarPath, '/docs/avatar/a.jpg');
  });
}

/// 造一个 v22 形态的库（只有 profiles 表 + 一行老数据，含 schema 22 的列集）。
void _createV22Database(String path) {
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
      manual_commute_minutes INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
  ''');
  db.execute('''
    INSERT INTO profiles (
      id, birth_year, biological_sex, height_cm, activity_level,
      created_at, updated_at
    ) VALUES ('p-old', 1998, 'male', 172.5, 'moderate', 1, 1);
  ''');
  db.execute('PRAGMA user_version = 22');
  db.dispose();
}
