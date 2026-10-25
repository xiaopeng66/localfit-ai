import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// foods 表列结构的两段迁移：Round 5 T11（docs/32 §4 T11 / 需求 75「按新结构重新
/// 导入」）schema 24 → 25 **加 15 列**；ADR-036（2026-10-21「存储格式定死」）
/// schema 29 → 30 把这 15 列与 `category_group` / `category_sub` 一起 **DROP**，
/// 分类只剩唯一指标 `category`（10 枚举，导入期翻译）。
///
/// 加减在同一条链上，失败模式不同（加法怕重复加 / 漏建表，减法怕误删），所以这里钉：
/// 1. **v24 老库**（有行、有值）升级后到 `schemaVersion`：17 个既有列一字不动、
///    15 个契约列已不在（加过又删掉，净结果为零）、行数据完好；
/// 2. **v29 库**（15 列里**有值**）升级到 30：列没了，**留下的列值一字不改**
///    （减法迁移最怕的就是把行一起搬丢 / 搬到错列）；
/// 3. **幂等**：升过的库再打开不抛（`ADD COLUMN` 第二次 duplicate column、
///    `DROP COLUMN` 第二次 no such column ⇒ 两条都按**列存在性**判断）；
/// 4. **裁剪库**（fixture 没建 `foods` 表）升级不抛错——先查表在不在；
/// 5. **半迁移库**（个别列已在、版本号停在 24）：照常升到当前 schema，不抛错；
/// 6. 新装即当前 schema：建表定义与迁移链两条路径终点一致。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-foods-columns-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// 契约里那 15 列（21 列 CSV 减掉表原有的 6 列）。schema 25 加上、schema 30 删掉。
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

  /// ADR-036 后 foods 的存储列（分类只有 `category` 一个指标）。
  const storedColumns = <String>[
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

  Future<List<String>> columnNames(AppDatabase database) async =>
      (await database.customSelect('PRAGMA table_info(foods)').get())
          .map((row) => row.data['name'] as String)
          .toList();

  test('v24 老库升级到当前 schema：17 个既有列一字不动、行数据完好、契约列净为零', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV24Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], database.schemaVersion);

    final names = await columnNames(database);
    expect(names, containsAll(storedColumns), reason: '存储列一个不少');
    expect(
      names,
      isNot(containsAll(droppedColumns)),
      reason: 'ADR-036 的 17 列（含 category_group / category_sub）不该还在',
    );

    final row = (await database.select(database.foods).get()).single;
    expect(row.id, 'f-v24');
    expect(row.name, '米饭');
    expect(row.kcalPer100g, 116);
    expect(row.category, 'staple');
    expect(row.isUserCreated, isTrue);
  });

  test('v29 库（15 列里有值）升级到 30：列删掉、留下的列值一字不改', () async {
    final file = File('${tempDir.path}${Platform.pathSeparator}v29.sqlite');
    _createV29Database(file.path);

    final before = _rawRow(file.path);
    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    final names = await columnNames(database);
    expect(
      names,
      isNot(containsAll(droppedColumns)),
      reason: '15 个契约列 + category_group / category_sub 都要没',
    );
    expect(names, containsAll(storedColumns));

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
    expect(names.where((name) => name == 'library_code'), isEmpty);
    expect(names, containsAll(storedColumns));
  });

  test('新装即当前 schema：食物库存储列集与迁移链终点一致', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final names = await columnNames(database);
    expect(names.toSet(), storedColumns.toSet());
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

/// 造一个 v29 形态的库（schema 25 加列后的全 21 列形态）：一行数据里 15 个契约列
/// **都有值**——升级后要么看这些值消失（列被删），要么看留下的列串了值。
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

/// 升级前把留下的列值读出来（升级后逐列对照，防「建新表 + 忘搬行」）。
Map<String, Object?> _rawRow(String path) {
  final db = sqlite.sqlite3.open(path);
  final row = db
      .select(
        'SELECT name, brand, category, kcal_per100g, protein_per100g, '
        'carbs_per100g, fat_per100g, default_serving_grams, source, created_at '
        'FROM foods',
      )
      .single;
  db.dispose();
  return row;
}
