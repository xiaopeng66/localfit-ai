import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_detail_source.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 2.0-1j：目录条目在导入之前也要能看到份量/修订/证据。目录搜索命中的行
/// 来自分片文件（不是主库），所以详情要从分片读；旧分片没有这三张表时
/// 返回空实体而不是报错或编造。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-shard-detail-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String shardPath(String name) =>
      '${tempDir.path}${Platform.pathSeparator}$name';

  const foodsSchema = '''
CREATE TABLE foods (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  state TEXT NOT NULL,
  locale TEXT,
  category TEXT,
  brand TEXT,
  kcal_per100g REAL,
  protein_per100g REAL,
  carbs_per100g REAL,
  fat_per100g REAL,
  source_id TEXT NOT NULL,
  license_status TEXT NOT NULL
);
''';

  const entitiesSchema = '''
CREATE TABLE portions (
  id TEXT NOT NULL PRIMARY KEY,
  food_id TEXT NOT NULL,
  name TEXT NOT NULL,
  grams REAL NOT NULL,
  locale TEXT,
  source TEXT
);
CREATE TABLE revisions (
  id TEXT NOT NULL PRIMARY KEY,
  food_id TEXT NOT NULL,
  revision_number INTEGER NOT NULL,
  kcal_per100g REAL, protein_per100g REAL, carbs_per100g REAL, fat_per100g REAL,
  source_evidence_id TEXT,
  quality_status TEXT NOT NULL,
  valid_from TEXT
);
CREATE TABLE evidence (
  id TEXT NOT NULL PRIMARY KEY,
  source_id TEXT NOT NULL,
  license TEXT NOT NULL,
  attribution TEXT,
  retrieved_at TEXT NOT NULL,
  transform_version TEXT NOT NULL,
  quality_status TEXT NOT NULL,
  record_hash TEXT NOT NULL
);
''';

  /// 建一个分片文件；[entities] 为 false 时只建 2.0-1j 之前的表。
  void buildShard(
    String path, {
    required Map<String, String> foods,
    bool entities = true,
    List<String> portions = const [],
    List<String> revisions = const [],
    List<String> evidence = const [],
  }) {
    final db = sqlite.sqlite3.open(path);
    try {
      db.execute(foodsSchema);
      if (entities) db.execute(entitiesSchema);
      for (final entry in foods.entries) {
        db.execute(
          'INSERT INTO foods (id, name, state, locale, category, brand,'
          ' kcal_per100g, protein_per100g, carbs_per100g, fat_per100g,'
          " source_id, license_status) VALUES (?, ?, 'verified', 'zh',"
          " 'grain', NULL, 116, 2.6, 25.9, 0.3, 'openfoodfacts', 'allowed')",
          [entry.key, entry.value],
        );
      }
      for (final statement in portions) {
        db.execute('INSERT INTO portions $statement');
      }
      for (final statement in revisions) {
        db.execute('INSERT INTO revisions $statement');
      }
      for (final statement in evidence) {
        db.execute('INSERT INTO evidence $statement');
      }
    } finally {
      db.dispose();
    }
  }

  test('reads portions ordered by grams, latest revision and its evidence', () async {
    final path = shardPath('foods-core-000.sqlite');
    buildShard(
      path,
      foods: {'off:1': '蒸米饭'},
      portions: [
        "(id, food_id, name, grams, locale, source) VALUES"
            " ('off:1:portion:2', 'off:1', '一碗', 150, 'zh-CN', 'openfoodfacts')",
        "(id, food_id, name, grams, locale, source) VALUES"
            " ('off:1:portion:1', 'off:1', '一勺', 30, 'zh-CN', 'openfoodfacts')",
      ],
      evidence: [
        "(id, source_id, license, attribution, retrieved_at, transform_version,"
            " quality_status, record_hash) VALUES ('off:1:ev', 'openfoodfacts',"
            " 'odbl-1.0', 'Open Food Facts, ODbL', '2026-09-15T20:45:07Z',"
            " '2.0-1j', 'ok', '${'a' * 64}')",
      ],
      revisions: [
        "(id, food_id, revision_number, kcal_per100g, protein_per100g,"
            " carbs_per100g, fat_per100g, source_evidence_id, quality_status,"
            " valid_from) VALUES ('off:1:rev:1', 'off:1', 1, 116, 2.6, 25.9,"
            " 0.3, 'off:1:ev', 'ok', '2026-09-15T20:45:07Z')",
        "(id, food_id, revision_number, kcal_per100g, protein_per100g,"
            " carbs_per100g, fat_per100g, source_evidence_id, quality_status,"
            " valid_from) VALUES ('off:1:rev:2', 'off:1', 2, 118, 2.7, 26.0,"
            " 0.3, 'off:1:ev', 'ok', '2026-09-16T01:00:00Z')",
      ],
    );

    final detail = await CatalogShardDetailSource(shardPaths: [path])
        .load('off:1');

    expect(detail, isNotNull);
    expect(detail!.name, '蒸米饭');
    expect(detail.source, 'openfoodfacts');
    expect(detail.state, 'verified');
    expect(detail.isUserCreated, isFalse);
    expect(detail.portions.map((portion) => portion.name).toList(), [
      '一勺',
      '一碗',
    ]);
    expect(detail.latestRevision!.revisionNumber, 2);
    expect(detail.latestRevision!.kcalPer100g, 118);
    expect(detail.evidence!.license, 'odbl-1.0');
    expect(detail.evidence!.attribution, 'Open Food Facts, ODbL');
    expect(detail.evidence!.retrievedAt, DateTime.utc(2026, 9, 15, 20, 45, 7));
    // 分片没有主表的默认份量列：详情不指认「默认份量」，等导入后才有。
    expect(detail.defaultServingGrams, isNull);
    expect(detail.defaultPortion, isNull);
  });

  test(
    'a legacy shard without the three tables reads as empty entities',
    () async {
      final path = shardPath('foods-000.sqlite');
      buildShard(path, foods: {'off:2': '旧分片米饭'}, entities: false);

      final detail = await CatalogShardDetailSource(shardPaths: [path])
          .load('off:2');

      expect(detail, isNotNull);
      expect(detail!.name, '旧分片米饭');
      expect(detail.portions, isEmpty);
      expect(detail.latestRevision, isNull);
      expect(detail.evidence, isNull);
    },
  );

  test(
    'searches every shard and returns null when no shard has the id',
    () async {
      final first = shardPath('foods-000.sqlite');
      final second = shardPath('foods-001.sqlite');
      buildShard(first, foods: {'off:1': '第一片'});
      buildShard(second, foods: {'off:3': '第二片'});

      final source = CatalogShardDetailSource(shardPaths: [first, second]);
      expect((await source.load('off:3'))!.name, '第二片');
      expect(await source.load('off:missing'), isNull);
    },
  );

  test(
    'a revision without evidence column value stays evidence-free',
    () async {
      final path = shardPath('foods-000.sqlite');
      buildShard(
        path,
        foods: {'off:4': '没有证据'},
        revisions: [
          "(id, food_id, revision_number, quality_status, valid_from) VALUES"
              " ('off:4:rev:1', 'off:4', 1, 'ok', NULL)",
        ],
      );

      final detail = await CatalogShardDetailSource(shardPaths: [path])
          .load('off:4');

      expect(detail!.latestRevision!.sourceEvidenceId, isNull);
      expect(detail.latestRevision!.isMacroComplete, isFalse);
      expect(detail.evidence, isNull);
    },
  );

  test('an unparseable timestamp fails loudly instead of hiding the evidence', () async {
    final path = shardPath('foods-000.sqlite');
    buildShard(
      path,
      foods: {'off:5': '坏时间戳'},
      evidence: [
        "(id, source_id, license, attribution, retrieved_at, transform_version,"
            " quality_status, record_hash) VALUES ('off:5:ev', 'openfoodfacts',"
            " 'odbl-1.0', NULL, 'not-a-date', '2.0-1j', 'ok', '${'b' * 64}')",
      ],
      revisions: [
        "(id, food_id, revision_number, source_evidence_id, quality_status)"
            " VALUES ('off:5:rev:1', 'off:5', 1, 'off:5:ev', 'ok')",
      ],
    );

    // 静默把坏证据当成「没有证据」会让用户以为这条数据没有出处。
    await expectLater(
      CatalogShardDetailSource(shardPaths: [path]).load('off:5'),
      throwsA(isA<FormatException>()),
    );
  });
}
