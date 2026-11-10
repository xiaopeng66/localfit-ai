import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// foods 的列迁移链：v25 增加导入契约列，v30 按 ADR-036 退役导入列与
/// 分类中间列，v31 按 docs/68 增加生效修订指针、变体、做法与归档身份。
///
/// 这里验证加减都能到达当前 schema：
/// 1. v24 / v29 有值旧库的既有列与行完整保留，所有退役列逐项消失；
/// 2. v31 新身份列在未提供来源关系时为 null，不伪造修订、变体或归档；
/// 3. 重开和半迁移库幂等，缺少 foods 的裁剪库也能升级；
/// 4. 新装与两种迁移路径的列名、类型、非空、默认值及主键语义一致。
///
/// 这些是专测 foods DDL 的裁剪库，不含 food_nutrition_revisions；完整旧库的
/// baseline 修订与历史快照保全由 app_database_v11_migration_test 覆盖。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-foods-columns-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// schema 25 加入、schema 30 退役的导入字段。
  const contractColumns = <String>[
    'library_code',
    'category_sub',
    'cuisine',
    'food_kind',
    'data_basis',
    'food_state',
    'source_code',
    'source_food_code',
    'original_name',
    'original_category',
    'source_note',
    'source_url',
    'recipe_summary',
    'source_nature',
  ];
  const droppedColumns = <String>[...contractColumns, 'category_group'];

  /// ADR-036 保留的历史列，迁移前后每一列的原值都必须保全。
  const legacyColumns = <String>[
    'id',
    'name',
    'brand',
    'default_serving_grams',
    'kcal_per100g',
    'protein_per100g',
    'carbs_per100g',
    'fat_per100g',
    'source',
    'is_user_created',
    'created_at',
    'updated_at',
    'state',
    'locale',
    'category',
    'source_version',
    'license_status',
  ];
  const identityColumns = <String>[
    'current_revision_id',
    'variant_of_food_id',
    'cooking_note',
    'archived_at',
  ];
  const storedColumns = <String>[...legacyColumns, ...identityColumns];

  Future<List<String>> columnNames(AppDatabase database) async =>
      (await database.customSelect('PRAGMA table_info(foods)').get())
          .map((row) => row.data['name'] as String)
          .toList();

  Future<Map<String, Map<String, Object?>>> readColumnDefinitionsAndClose(
    AppDatabase database,
  ) async {
    try {
      return {
        for (final row
            in await database.customSelect('PRAGMA table_info(foods)').get())
          row.data['name'] as String: {
            for (final key in ['type', 'notnull', 'dflt_value', 'pk'])
              key: row.data[key],
          },
      };
    } finally {
      await database.close();
    }
  }

  Future<void> expectFoodDataPreserved(
    AppDatabase database,
    Map<String, Object?> before,
  ) async {
    final row =
        (await database.customSelect('SELECT * FROM foods').get()).single;
    expect(
      {for (final name in legacyColumns) name: row.data[name]},
      {for (final name in legacyColumns) name: before[name]},
      reason: '删除导入列和增加身份列均不得改写既有营养、来源或审计值',
    );
    for (final name in identityColumns) {
      expect(row.data[name], isNull, reason: '$name 不得从无来源的裁剪夹具中编造');
    }
  }

  test('v24 老库升级到当前 schema：旧列值保全、退役列消失、新身份不编造', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV24Database(file.path);
    final before = _rawRow(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], database.schemaVersion);

    final names = await columnNames(database);
    expect(names.toSet(), storedColumns.toSet(), reason: '当前存储列应完整且无多余');
    for (final name in droppedColumns) {
      expect(names, isNot(contains(name)), reason: '$name 应按 ADR-036 退役');
    }
    await expectFoodDataPreserved(database, before);

    final row = (await database.select(database.foods).get()).single;
    expect(row.id, 'f-v24');
    expect(row.name, '米饭');
    expect(row.kcalPer100g, 116);
    expect(row.category, 'staple');
    expect(row.isUserCreated, isTrue);
  });

  test('v29 库（退役列有值）升级到当前版：旧值保全、退役列消失', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}v29.sqlite');
    _createV29Database(file.path);

    final before = _rawRow(file.path);
    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    final names = await columnNames(database);
    for (final name in droppedColumns) {
      expect(names, isNot(contains(name)), reason: '$name 应按 ADR-036 退役');
    }
    expect(names.toSet(), storedColumns.toSet());
    await expectFoodDataPreserved(database, before);

    final row = (await database.select(database.foods).get()).single;
    expect(row.name, before['name']);
    expect(row.brand, before['brand']);
    expect(row.category, before['category']);
    expect(row.kcalPer100g, before['kcal_per100g']);
    expect(row.proteinPer100g, before['protein_per100g']);
    expect(row.carbsPer100g, before['carbs_per100g']);
    expect(row.fatPer100g, before['fat_per100g']);
    expect(row.defaultServingGrams, before['default_serving_grams']);
    expect(row.source, before['source']);
    expect(row.isUserCreated, isTrue);
    expect(
      row.createdAt.millisecondsSinceEpoch,
      (before['created_at']! as int) * 1000,
      reason: '审计列不许被减法迁移碰',
    );
    // 行数也没变（DROP COLUMN 不许是「建新表 + 忘搬行」）。
    expect(await database.select(database.foods).get(), hasLength(1));
  });

  test('减法迁移幂等：升过的库再打开不抛错（DROP 第二次会 no such column）', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}v29-once.sqlite',
    );
    _createV29Database(file.path);

    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('SELECT 1');
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final names = await columnNames(second);
    expect(names.where((name) => name == 'category_sub'), isEmpty);
    expect(names.where((name) => name == 'category'), hasLength(1));
  });

  test('迁移幂等：列已加的库再打开不抛错', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV24Database(file.path);

    final first = AppDatabase(NativeDatabase(file));
    await first.customStatement('SELECT 1');
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    final names = await columnNames(second);
    expect(names.where((name) => name == 'library_code'), isEmpty);
  });

  test('裁剪库（fixture 没有 foods 表）：升级不抛错', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}trimmed.sqlite');
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('CREATE TABLE unrelated (id TEXT NOT NULL PRIMARY KEY)');
    raw.execute('PRAGMA user_version = 24');
    raw.dispose();

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], database.schemaVersion);
  });

  test('半迁移库（部分列已在、版本号仍 24）：照常升到当前 schema，不抛错', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}half.sqlite');
    _createV24Database(file.path, preAddedColumns: const ['library_code']);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    final names = await columnNames(database);
    expect(names.toSet(), storedColumns.toSet());
    for (final name in droppedColumns) {
      expect(names, isNot(contains(name)), reason: '$name 应按 ADR-036 退役');
    }
  });

  test('新装与 v24/v29 迁移后的 foods 列定义语义一致', () async {
    final freshDefinitions = await readColumnDefinitionsAndClose(
      AppDatabase(NativeDatabase.memory()),
    );
    expect(freshDefinitions.keys.toSet(), storedColumns.toSet());

    final v24File = File(
      '${tempDir.path}${Platform.pathSeparator}compare-v24.sqlite',
    );
    final v29File = File(
      '${tempDir.path}${Platform.pathSeparator}compare-v29.sqlite',
    );
    _createV24Database(v24File.path);
    _createV29Database(v29File.path);
    for (final file in [v24File, v29File]) {
      expect(
        await readColumnDefinitionsAndClose(AppDatabase(NativeDatabase(file))),
        freshDefinitions,
        reason: '${file.path} 应与新装库保持相同列语义（忽略物理列序号）',
      );
    }
  });
}

/// 造一个 v24 形态的库：foods 含当时全部 17 列与一行有值数据。
/// [preAddedColumns] 仿「半迁移库」：版本号还停在 24，但个别契约列已经在
/// （崩在 `PRAGMA user_version` 落盘前 / fixture 手工裁剪都会长这样）。
void _createV24Database(
  String path, {
  List<String> preAddedColumns = const [],
}) {
  final columns = <String>[
    'id TEXT NOT NULL PRIMARY KEY',
    'name TEXT NOT NULL',
    'brand TEXT',
    'default_serving_grams REAL',
    'kcal_per100g REAL NOT NULL',
    'protein_per100g REAL NOT NULL',
    'carbs_per100g REAL NOT NULL',
    'fat_per100g REAL NOT NULL',
    'source TEXT NOT NULL',
    'is_user_created INTEGER NOT NULL DEFAULT 0',
    'created_at INTEGER NOT NULL',
    'updated_at INTEGER NOT NULL',
    "state TEXT NOT NULL DEFAULT 'verified'",
    'locale TEXT',
    'category TEXT',
    'source_version INTEGER',
    "license_status TEXT NOT NULL DEFAULT 'unknown'",
    for (final column in preAddedColumns) '$column TEXT',
  ];
  final db = sqlite.sqlite3.open(path);
  db.execute('CREATE TABLE foods (${columns.join(', ')});');
  db.execute(
    "INSERT INTO foods (id, name, kcal_per100g, protein_per100g, "
    "carbs_per100g, fat_per100g, source, is_user_created, created_at, "
    "updated_at, category) "
    "VALUES ('f-v24', '米饭', 116, 2.6, 25.9, 0.3, 'user', 1, 1, 1, 'staple')",
  );
  db.execute('PRAGMA user_version = 24');
  db.dispose();
}

/// 造一个 v29 形态的库：一行数据里待退役的导入与分类中间列都有值。
/// 升级后逐项检查列消失，并检查留下的全部历史列没有串值。
/// 审计列按 drift 的落库单位写（int **秒**；读出来才是 `DateTime`）。
void _createV29Database(String path) {
  final db = sqlite.sqlite3.open(path);
  db.execute('''
CREATE TABLE foods (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  brand TEXT,
  default_serving_grams REAL,
  kcal_per100g REAL NOT NULL,
  protein_per100g REAL NOT NULL,
  carbs_per100g REAL NOT NULL,
  fat_per100g REAL NOT NULL,
  source TEXT NOT NULL,
  is_user_created INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  state TEXT NOT NULL DEFAULT 'verified',
  locale TEXT,
  category TEXT,
  source_version INTEGER,
  license_status TEXT NOT NULL DEFAULT 'unknown',
  library_code TEXT,
  category_group TEXT,
  category_sub TEXT,
  cuisine TEXT,
  food_kind TEXT,
  data_basis TEXT,
  food_state TEXT,
  source_code TEXT,
  source_food_code TEXT,
  original_name TEXT,
  original_category TEXT,
  source_note TEXT,
  source_url TEXT,
  recipe_summary TEXT,
  source_nature TEXT
);
''');
  db.execute(
    "INSERT INTO foods (id, name, brand, default_serving_grams, kcal_per100g, "
    "protein_per100g, carbs_per100g, fat_per100g, source, is_user_created, "
    "created_at, updated_at, category, library_code, category_group, "
    "category_sub, cuisine, food_kind, data_basis, food_state, source_code, "
    "source_food_code, original_name, original_category, source_note, "
    "source_url, recipe_summary, source_nature) "
    "VALUES ('f-v29', '样例食物', '样例品牌', 150, 612, 24.5, 78, 20.1, 'user', "
    "1, 1760000000, 1760000000, 'prepared', 'F-2001', '菜肴及快餐', "
    "'盖浇饭', '川菜', '预包装', '100g可食部', '熟', 'SRC-9', 'SF-9', "
    "'原样名称', '原样分类', '数据说明文本', 'https://example.com/2001', "
    "'配方摘要文本', '实测')",
  );
  db.execute('PRAGMA user_version = 29');
  db.dispose();
}

/// 升级前读取原始行（含全部审计 / 来源字段），按原存储单位逐列比较。
Map<String, Object?> _rawRow(String path) {
  final db = sqlite.sqlite3.open(path);
  try {
    return Map<String, Object?>.from(db.select('SELECT * FROM foods').single);
  } finally {
    db.dispose();
  }
}
