import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_detail_source.dart';
import 'package:localfit_ai/features/nutrition/data/food_detail_loader.dart';
import 'package:localfit_ai/features/nutrition/data/food_detail_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 2.0-1j 详情路由：搜索结果里「目录」行只在分片里，「主库」行在 SQLCipher
/// 主库里；已导入的目录条目会以主库身份出现，分片被换掉时也要还能读到。
void main() {
  late AppDatabase database;
  late Directory tempDir;
  late String shardPath;

  final now = DateTime.utc(2026, 9, 16, 8);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    tempDir = Directory.systemTemp.createTempSync('localfit-detail-loader-');
    shardPath = '${tempDir.path}${Platform.pathSeparator}foods-core-000.sqlite';
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  /// 分片里放一条带份量/证据的目录条目。
  void writeShardWith(String foodId, String name, {String portion = '一碗'}) {
    final db = sqlite.sqlite3.open(shardPath);
    try {
      db.execute('''
CREATE TABLE foods (
  id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, state TEXT NOT NULL,
  locale TEXT, category TEXT, brand TEXT, kcal_per100g REAL,
  protein_per100g REAL, carbs_per100g REAL, fat_per100g REAL,
  source_id TEXT NOT NULL, license_status TEXT NOT NULL);
CREATE TABLE portions (
  id TEXT NOT NULL PRIMARY KEY, food_id TEXT NOT NULL, name TEXT NOT NULL,
  grams REAL NOT NULL, locale TEXT, source TEXT);
CREATE TABLE revisions (
  id TEXT NOT NULL PRIMARY KEY, food_id TEXT NOT NULL,
  revision_number INTEGER NOT NULL, kcal_per100g REAL, protein_per100g REAL,
  carbs_per100g REAL, fat_per100g REAL, source_evidence_id TEXT,
  quality_status TEXT NOT NULL, valid_from TEXT);
CREATE TABLE evidence (
  id TEXT NOT NULL PRIMARY KEY, source_id TEXT NOT NULL, license TEXT NOT NULL,
  attribution TEXT, retrieved_at TEXT NOT NULL,
  transform_version TEXT NOT NULL, quality_status TEXT NOT NULL,
  record_hash TEXT NOT NULL);
''');
      db.execute(
        "INSERT INTO foods VALUES ('$foodId', '$name', 'verified', 'zh', NULL,"
        " NULL, 116, 2.6, 25.9, 0.3, 'openfoodfacts', 'allowed')",
      );
      db.execute(
        "INSERT INTO portions VALUES ('$foodId:portion:1', '$foodId',"
        " '$portion', 150, 'zh-CN', 'openfoodfacts')",
      );
      db.execute(
        "INSERT INTO revisions VALUES ('$foodId:rev:1', '$foodId', 1, 116,"
        " 2.6, 25.9, 0.3, '$foodId:ev', 'ok', '2026-09-15T20:45:07Z')",
      );
      db.execute(
        "INSERT INTO evidence VALUES ('$foodId:ev', 'openfoodfacts',"
        " 'odbl-1.0', NULL, '2026-09-15T20:45:07Z', '2.0-1j', 'ok',"
        " '${'a' * 64}')",
      );
    } finally {
      db.dispose();
    }
  }

  Future<void> importIntoMain(String foodId, String name) => database
      .into(database.foods)
      .insert(
        FoodsCompanion.insert(
          id: foodId,
          name: name,
          kcalPer100g: 116,
          proteinPer100g: 2.6,
          carbsPer100g: 25.9,
          fatPer100g: 0.3,
          source: 'openfoodfacts',
          state: const Value('verified'),
          licenseStatus: const Value('allowed'),
          createdAt: now,
          updatedAt: now,
        ),
      );

  FoodDetailLoader loader({bool withShards = true}) => FoodDetailLoader(
    databaseDetails: FoodDetailRepository(database: database),
    shardDetails: withShards
        ? CatalogShardDetailSource(shardPaths: [shardPath])
        : null,
  );

  test('catalog rows come from the shard (with portions)', () async {
    writeShardWith('off:1', '分片蒸米饭');
    await importIntoMain('off:2', '主库米饭');

    final detail = await loader().load('off:1', source: 'catalog');

    expect(detail!.name, '分片蒸米饭');
    expect(detail.portions.single.grams, 150);
    expect(detail.evidence!.license, 'odbl-1.0');
  });

  test(
    'main rows come from the database even when a shard has the id',
    () async {
      writeShardWith('off:3', '分片里的名字');
      await importIntoMain('off:3', '主库里的名字');

      final detail = await loader().load('off:3', source: 'main');

      expect(detail!.name, '主库里的名字');
      expect(detail.portions, isEmpty);
    },
  );

  test('a catalog row already imported falls back to the database', () async {
    // 分片文件被用户换掉/删掉，但条目早就导入过：不能因此显示「找不到」。
    await importIntoMain('off:4', '已导入米饭');

    final detail = await loader().load('off:4', source: 'catalog');

    expect(detail!.name, '已导入米饭');
  });

  test('a deleted shard file does not break the loader', () async {
    writeShardWith('off:7', '分片米饭');
    await importIntoMain('off:8', '主库米饭');
    File(shardPath).deleteSync();

    // 路径列表是启动时扫出来的：文件没了要跳过，不能抛异常。
    expect((await loader().load('off:8', source: 'catalog'))!.name, '主库米饭');
    expect(await loader().load('off:7', source: 'catalog'), isNull);
  });

  test('without shard paths the loader is database-only', () async {
    await importIntoMain('off:5', '无分片米饭');

    final detail = await loader(withShards: false)
        .load('off:5', source: 'catalog');

    expect(detail!.name, '无分片米饭');
  });

  test('unknown ids return null through every route', () async {
    writeShardWith('off:6', '分片米饭');

    expect(await loader().load('off:missing', source: 'catalog'), isNull);
    expect(await loader().load('off:missing', source: 'main'), isNull);
  });
}
