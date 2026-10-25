import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_manifest.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_importer.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

final _sha256 = Sha256();

/// 分片文件布局与 ETL（tool/food_catalog/etl_pipeline.py SHARD_SCHEMA）同形：
/// 测试直接用 sqlite3 构造，不依赖 Python。fixture 不建主键——重复 ID 的
/// 拒绝是应用侧导入器（staging 无主键 + 显式检查）的职责，损坏分片测试
/// 需要能造出带重复 ID 的行。
const _shardSchema = '''
CREATE TABLE foods (
  id TEXT NOT NULL,
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
  source_version TEXT,
  license_status TEXT NOT NULL
);
''';

void main() {
  late Directory tempDir;
  late AppDatabase database;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-import-');
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  String shardPath(String file) =>
      '${tempDir.path}${Platform.pathSeparator}$file';

  Future<File> writeShard(String name, List<Map<String, Object?>> rows) async {
    final db = sqlite.sqlite3.open(shardPath(name));
    try {
      db.execute(_shardSchema);
      final stmt = db.prepare(
        'INSERT INTO foods (id, name, state, locale, category, brand,'
        ' kcal_per100g, protein_per100g, carbs_per100g, fat_per100g,'
        ' source_id, source_version, license_status)'
        ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      try {
        for (final row in rows) {
          stmt.execute([
            row['id'],
            row['name'],
            row['state'],
            row['locale'],
            row['category'],
            row['brand'],
            row['kcal'],
            row['protein'],
            row['carbs'],
            row['fat'],
            'openfoodfacts',
            '20260914',
            'allowed',
          ]);
        }
      } finally {
        stmt.dispose();
      }
    } finally {
      db.dispose();
    }
    return File(shardPath(name));
  }

  Future<CatalogManifestShard> shardMeta(
    String file,
    int rows, {
    int? portionRows,
    int? revisionRows,
    int? evidenceRows,
  }) async {
    final bytes = await File(shardPath(file)).readAsBytes();
    final digest = await _sha256.hash(bytes);
    return CatalogManifestShard(
      file: file,
      kind: file.contains('-core-') ? 'core' : 'brand',
      rows: rows,
      sha256: digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      ftsRows: rows,
      portionRows: portionRows,
      revisionRows: revisionRows,
      evidenceRows: evidenceRows,
    );
  }

  CatalogManifest manifestFor(List<CatalogManifestShard> shards) =>
      CatalogManifest(
        manifestVersion: CatalogManifest.supportedManifestVersion,
        catalogVersion: '2026.09-test',
        generatedAt: DateTime.utc(2026, 9, 15),
        transformVersion: 'etl-1',
        sources: [
          CatalogManifestSource(
            id: 'openfoodfacts',
            name: 'Open Food Facts',
            license: 'odbl-1.0',
            attribution: '(c) OFF contributors',
            retrievedAt: DateTime.utc(2026, 9, 14),
          ),
        ],
        shards: shards,
        quality: const CatalogManifestQuality(
          canonicalRows: 0,
          aliasRows: 0,
          duplicateIds: 0,
          macroCompleteRatio: 1,
          anomalyCount: 0,
          chineseNameCoverage: 0,
          missingLicenseCount: 0,
          ftsIndexRows: 0,
          ftsSha256: '0',
        ),
      );

  Map<String, Object?> row(
    String id, {
    String name = 'Rice',
    double kcal = 130,
    double protein = 2.7,
    double carbs = 28,
    double fat = 0.3,
    String state = 'verified',
    String locale = 'en',
    String category = 'cereals',
    String brand = 'Generic',
  }) => {
    'id': id,
    'name': name,
    'state': state,
    'locale': locale,
    'category': category,
    'brand': brand,
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
  };

  /// 带 docs/07 §5.5 三个实体的分片行：默认每个食物一条修订 + 一条来源证据，
  /// 份量按 [portionGrams] 给（传 null 表示「上游没自称克数」）。
  Map<String, Object?> ontologyRow(String id, {String name = 'Rice'}) =>
      row(id, name: name);

  Future<File> writeOntologyShard(
    String name,
    List<Map<String, Object?>> rows, {
    double? portionGrams = 30,
    Set<String>? portionsFor,
  }) async {
    final db = sqlite.sqlite3.open(shardPath(name));
    try {
      db.execute(_shardSchema);
      db.execute('''
CREATE TABLE revisions (
  id TEXT NOT NULL PRIMARY KEY,
  food_id TEXT NOT NULL,
  revision_number INTEGER NOT NULL,
  kcal_per100g REAL,
  protein_per100g REAL,
  carbs_per100g REAL,
  fat_per100g REAL,
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
CREATE TABLE portions (
  id TEXT NOT NULL PRIMARY KEY,
  food_id TEXT NOT NULL,
  name TEXT NOT NULL,
  grams REAL NOT NULL,
  locale TEXT,
  source TEXT
);
''');
      final foodStmt = db.prepare(
        'INSERT INTO foods (id, name, state, locale, category, brand,'
        ' kcal_per100g, protein_per100g, carbs_per100g, fat_per100g,'
        ' source_id, source_version, license_status)'
        ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      final evidenceStmt = db.prepare(
        'INSERT INTO evidence (id, source_id, license, attribution,'
        ' retrieved_at, transform_version, quality_status, record_hash)'
        ' VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      );
      final revisionStmt = db.prepare(
        'INSERT INTO revisions (id, food_id, revision_number, kcal_per100g,'
        ' protein_per100g, carbs_per100g, fat_per100g, source_evidence_id,'
        ' quality_status, valid_from) VALUES (?,?,?,?,?,?,?,?,?,?)',
      );
      final portionStmt = db.prepare(
        'INSERT INTO portions (id, food_id, name, grams, locale, source)'
        ' VALUES (?,?,?,?,?,?)',
      );
      try {
        for (final row in rows) {
          final id = row['id'] as String;
          foodStmt.execute([
            id,
            row['name'],
            row['state'],
            row['locale'],
            row['category'],
            row['brand'],
            row['kcal'],
            row['protein'],
            row['carbs'],
            row['fat'],
            'openfoodfacts',
            '20260915',
            'allowed',
          ]);
          evidenceStmt.execute([
            '$id:ev',
            'openfoodfacts',
            'odbl-1.0',
            '(c) Open Food Facts contributors (ODbL)',
            '2026-09-15T20:45:07Z',
            'etl-1',
            row['state'],
            'a' * 64,
          ]);
          revisionStmt.execute([
            '$id:rev:1',
            id,
            1,
            row['kcal'],
            row['protein'],
            row['carbs'],
            row['fat'],
            '$id:ev',
            row['state'],
            '2026-09-15T20:45:07Z',
          ]);
          if (portionGrams != null &&
              (portionsFor == null || portionsFor.contains(id))) {
            portionStmt.execute([
              '$id:portion:1',
              id,
              '30 g (30 g)',
              portionGrams,
              row['locale'],
              'openfoodfacts',
            ]);
          }
        }
      } finally {
        foodStmt.dispose();
        evidenceStmt.dispose();
        revisionStmt.dispose();
        portionStmt.dispose();
      }
    } finally {
      db.dispose();
    }
    return File(shardPath(name));
  }

  group('catalog shard importer', () {
    test(
      'imports the three §5.5 entities alongside the foods they belong to',
      () async {
        await writeOntologyShard(
          'foods-core-000.sqlite',
          [
            ontologyRow('off:1', name: 'Steamed Rice'),
            ontologyRow('off:2', name: 'Boiled Noodles'),
          ],
          portionsFor: {'off:1'},
        );
        final meta = await shardMeta(
          'foods-core-000.sqlite',
          2,
          portionRows: 1,
          revisionRows: 2,
          evidenceRows: 2,
        );

        final report = await CatalogShardImporter(database: database)
            .importCatalog(
              manifest: manifestFor([meta]),
              shards: [ShardInput(meta: meta, path: shardPath(meta.file))],
            );

        expect(report.importedRows, 2);
        expect(report.revisionRows, 2);
        expect(report.evidenceRows, 2);
        // 只有 off:1 有自称克数的份量；off:2 是「1 cup」所以 ETL 不产出。
        expect(report.portionRows, 1);

        final evidence = await database.select(database.foodEvidence).get();
        expect(evidence, hasLength(2));
        final riceEvidence = evidence.firstWhere((e) => e.id == 'off:1:ev');
        expect(riceEvidence.sourceId, 'openfoodfacts');
        expect(riceEvidence.license, 'odbl-1.0');
        expect(riceEvidence.transformVersion, 'etl-1');
        expect(riceEvidence.qualityStatus, 'verified');
        expect(riceEvidence.recordHash, 'a' * 64);
        // 分片里的时间是 ISO-8601 UTC 文本；drift 取回来是本地时间，比较瞬间值。
        expect(
          riceEvidence.retrievedAt.toUtc(),
          DateTime.utc(2026, 9, 15, 20, 45, 7),
        );

        final revisions = await database
            .select(database.foodNutritionRevisions)
            .get();
        expect(revisions, hasLength(2));
        final riceRevision = revisions.firstWhere((r) => r.foodId == 'off:1');
        expect(riceRevision.revisionNumber, 1);
        expect(riceRevision.kcalPer100g, 130);
        expect(riceRevision.proteinGPer100g, 2.7);
        expect(riceRevision.sourceEvidenceId, 'off:1:ev');
        expect(riceRevision.qualityStatus, 'verified');
        expect(
          riceRevision.validFrom!.toUtc(),
          DateTime.utc(2026, 9, 15, 20, 45, 7),
        );

        final portions = await database.select(database.foodPortions).get();
        expect(portions, hasLength(1));
        expect(portions.single.foodId, 'off:1');
        expect(portions.single.name, '30 g (30 g)');
        expect(portions.single.grams, 30);
        expect(portions.single.source, 'openfoodfacts');
      },
    );

    test('imports a legacy shard that has no ontology tables', () async {
      // 2.0-1j 之前的发布物只有 foods/aliases/空的 portions：导入器要能照常
      // 吃下去（用户支持目录里可能留着旧分片），只是实体行数为 0。
      await writeShard('foods-core-000.sqlite', [row('off:1')]);
      final meta = await shardMeta('foods-core-000.sqlite', 1);

      final report = await CatalogShardImporter(database: database)
          .importCatalog(
            manifest: manifestFor([meta]),
            shards: [ShardInput(meta: meta, path: shardPath(meta.file))],
          );

      expect(report.importedRows, 1);
      expect(report.portionRows, 0);
      expect(report.revisionRows, 0);
      expect(report.evidenceRows, 0);
      expect(await database.select(database.foodEvidence).get(), isEmpty);
      expect(
        await database.select(database.foodNutritionRevisions).get(),
        isEmpty,
      );
    });

    test('新导入开始前，把上次中断留下的 importing 孤儿行标成 interrupted', () async {
      // 进程被杀/断电时导入 job 停在 importing，原先永远没人收尾——
      // 「importing = 正在进行」的语义就坏了（docs/11 P3）。新导入的
      // 第一笔写之前先把孤儿行归档为 interrupted。
      await writeShard('foods-core-000.sqlite', [row('off:1')]);
      final meta = await shardMeta('foods-core-000.sqlite', 1);
      final ts = DateTime.now().toUtc();
      await database
          .into(database.foodImportJobs)
          .insert(
            FoodImportJobsCompanion.insert(
              id: 'orphan-1',
              catalogVersion: 202609,
              status: 'importing',
              totalShards: 5,
              manifestHash: 'b' * 64,
              startedAt: ts,
              createdAt: ts,
              updatedAt: ts,
            ),
          );

      await CatalogShardImporter(database: database).importCatalog(
        manifest: manifestFor([meta]),
        shards: [ShardInput(meta: meta, path: shardPath(meta.file))],
      );

      final jobs = await database.select(database.foodImportJobs).get();
      expect(jobs, hasLength(2));
      // 孤儿行归档，不再冒充「正在进行」。
      expect(
        jobs.firstWhere((job) => job.id == 'orphan-1').status,
        'interrupted',
      );
      // 本次导入的 job 走完自己的生命周期。
      expect(
        jobs.firstWhere((job) => job.id != 'orphan-1').status,
        'completed',
      );
    });

    test(
      'fails when the shard declares ontology rows it does not have',
      () async {
        // manifest 说这个分片有 2 条份量、实际 1 条 → 产物坏了，不能静默导入。
        await writeOntologyShard('foods-core-000.sqlite', [
          ontologyRow('off:1'),
        ]);
        final meta = await shardMeta(
          'foods-core-000.sqlite',
          1,
          portionRows: 2,
          revisionRows: 1,
          evidenceRows: 1,
        );

        await expectLater(
          CatalogShardImporter(database: database).importCatalog(
            manifest: manifestFor([meta]),
            shards: [ShardInput(meta: meta, path: shardPath(meta.file))],
          ),
          throwsA(
            isA<CatalogImportException>().having(
              (e) => e.kind,
              'kind',
              CatalogImportFailureKind.rowCountMismatch,
            ),
          ),
        );
        expect(await database.select(database.foods).get(), isEmpty);
        expect(await _stagingTableCount(database), 0);
      },
    );

    test('rejects a portion whose grams are not a sane weight', () async {
      // 12kg 的「一份」是上游脏数据（把整包重量写进了份量）。
      await writeOntologyShard('foods-core-000.sqlite', [
        ontologyRow('off:1'),
      ], portionGrams: 12000);
      final meta = await shardMeta(
        'foods-core-000.sqlite',
        1,
        portionRows: 1,
        revisionRows: 1,
        evidenceRows: 1,
      );

      await expectLater(
        CatalogShardImporter(database: database).importCatalog(
          manifest: manifestFor([meta]),
          shards: [ShardInput(meta: meta, path: shardPath(meta.file))],
        ),
        throwsA(
          isA<CatalogImportException>().having(
            (e) => e.kind,
            'kind',
            CatalogImportFailureKind.invalidRow,
          ),
        ),
      );
      expect(await database.select(database.foods).get(), isEmpty);
      expect(await database.select(database.foodPortions).get(), isEmpty);
    });

    test('does not write entities for rows it refused to import', () async {
      // 已存在的 id 会被跳过（用户自建/编辑行不被覆盖），它的份量与证据
      // 也不能进来——否则主库会出现挂在旧行上的新份量。
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'off:1',
              name: 'Old Rice',
              kcalPer100g: 130,
              proteinPer100g: 2.7,
              carbsPer100g: 28,
              fatPer100g: 0.3,
              source: 'user',
              createdAt: DateTime.utc(2026, 9, 1),
              updatedAt: DateTime.utc(2026, 9, 1),
            ),
          );
      await writeOntologyShard('foods-core-000.sqlite', [ontologyRow('off:1')]);
      final meta = await shardMeta(
        'foods-core-000.sqlite',
        1,
        portionRows: 1,
        revisionRows: 1,
        evidenceRows: 1,
      );

      final report = await CatalogShardImporter(database: database)
          .importCatalog(
            manifest: manifestFor([meta]),
            shards: [ShardInput(meta: meta, path: shardPath(meta.file))],
          );

      expect(report.importedRows, 0);
      expect(report.skippedExistingRows, 1);
      expect(report.portionRows, 0);
      expect(report.revisionRows, 0);
      expect(report.evidenceRows, 0);
      expect(await database.select(database.foodPortions).get(), isEmpty);
      expect(await database.select(database.foodEvidence).get(), isEmpty);
    });

    test(
      'imports verified rows across shards and records a completed job',
      () async {
        await writeShard('foods-core-000.sqlite', [
          row('off:1', name: 'Steamed Rice'),
          row('off:2', name: 'Boiled Noodles'),
        ]);
        await writeShard('foods-brand-000.sqlite', [
          row('off:3', name: 'Instant Noodles', brand: 'ACME'),
        ]);
        final core = await shardMeta('foods-core-000.sqlite', 2);
        final brand = await shardMeta('foods-brand-000.sqlite', 1);

        final importer = CatalogShardImporter(database: database);
        final report = await importer.importCatalog(
          manifest: manifestFor([core, brand]),
          shards: [
            ShardInput(meta: core, path: shardPath(core.file)),
            ShardInput(meta: brand, path: shardPath(brand.file)),
          ],
        );

        expect(report.importedRows, 3);
        expect(report.importedShards, 2);

        final foods = await database.select(database.foods).get();
        expect(foods, hasLength(3));
        final rice = foods.firstWhere((f) => f.id == 'off:1');
        expect(rice.state, 'verified');
        expect(rice.licenseStatus, 'allowed');
        expect(rice.locale, 'en');
        expect(rice.category, 'cereals');
        expect(rice.source, 'openfoodfacts');

        final jobs = await database.select(database.foodImportJobs).get();
        expect(jobs, hasLength(1));
        expect(jobs.single.status, 'completed');
        expect(jobs.single.totalShards, 2);
        expect(jobs.single.importedShards, 2);
        expect(jobs.single.errorCount, 0);
        expect(jobs.single.manifestHash, hasLength(64));

        // 导入完成后不留 staging 残表。
        expect(await _stagingTableCount(database), 0);
      },
    );

    test('is idempotent for the same manifest hash', () async {
      await writeShard('foods-core-000.sqlite', [row('off:1')]);
      final core = await shardMeta('foods-core-000.sqlite', 1);
      final importer = CatalogShardImporter(database: database);
      final shards = [ShardInput(meta: core, path: shardPath(core.file))];

      await importer.importCatalog(
        manifest: manifestFor([core]),
        shards: shards,
      );
      final second = await importer.importCatalog(
        manifest: manifestFor([core]),
        shards: shards,
      );

      expect(second.skippedEntirely, isTrue);
      expect(await database.select(database.foods).get(), hasLength(1));
    });

    test('imports the remaining shards after a core-only import', () async {
      // docs/07 §5.6：首次安装只导入随包 core 分片，其他分片由用户之后主动导入。
      // 幂等键因此只能看**本次给出的分片集合**，不能看整个 manifest——否则
      // 首装那次会把同一 manifest 的 job 记成 completed，后面再想导入其余
      // 分片就被整包跳过，永远补不上。
      await writeShard('foods-core-000.sqlite', [row('off:1')]);
      await writeShard('foods-core-001.sqlite', [row('off:2')]);
      await writeShard('foods-core-002.sqlite', [row('off:3')]);
      final core = await shardMeta('foods-core-000.sqlite', 1);
      final rest = [
        await shardMeta('foods-core-001.sqlite', 1),
        await shardMeta('foods-core-002.sqlite', 1),
      ];
      final manifest = manifestFor([core, ...rest]);

      final first = await CatalogShardImporter(database: database)
          .importCatalog(
            manifest: manifest,
            shards: [ShardInput(meta: core, path: shardPath(core.file))],
          );
      expect(first.importedRows, 1);
      expect(first.importedShards, 1);

      // 用户后来把其余分片放进支持目录并触发导入。
      final second = await CatalogShardImporter(database: database)
          .importCatalog(
            manifest: manifest,
            shards: [
              for (final meta in rest)
                ShardInput(meta: meta, path: shardPath(meta.file)),
            ],
          );
      expect(second.skippedEntirely, isFalse, reason: '整包哈希幂等会漏掉这次导入');
      expect(second.importedShards, 2);
      expect(
        (await database.select(database.foods).get()).map((f) => f.id),
        containsAll(['off:1', 'off:2', 'off:3']),
      );

      // 同一批分片再导一次仍然是幂等的。
      final third = await CatalogShardImporter(database: database)
          .importCatalog(
            manifest: manifest,
            shards: [
              for (final meta in rest)
                ShardInput(meta: meta, path: shardPath(meta.file)),
            ],
          );
      expect(third.skippedEntirely, isTrue);
    });

    test('fails and keeps the old catalog when shard bytes disagree', () async {
      await writeShard('foods-core-000.sqlite', [row('off:1')]);
      final realBytes = await File(shardPath('foods-core-000.sqlite'))
          .readAsBytes();
      final tamperedDigest = await _sha256.hash([...realBytes, 0x00]);
      final badMeta = CatalogManifestShard(
        file: 'foods-core-000.sqlite',
        kind: 'core',
        rows: 1,
        sha256: tamperedDigest.bytes
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
        ftsRows: 1,
      );

      final importer = CatalogShardImporter(database: database);
      await expectLater(
        importer.importCatalog(
          manifest: manifestFor([badMeta]),
          shards: [ShardInput(meta: badMeta, path: shardPath(badMeta.file))],
        ),
        throwsA(isA<CatalogImportException>()),
      );

      expect(await database.select(database.foods).get(), isEmpty);
      final job = (await database.select(database.foodImportJobs).get()).single;
      expect(job.status, 'failed');
      expect(job.errorCount, 1);
      expect(await _stagingTableCount(database), 0);
    });

    test('fails and rolls back when the shard row count disagrees', () async {
      await writeShard('foods-core-000.sqlite', [row('off:1'), row('off:2')]);
      // manifest 只声明 1 行。
      final core = await shardMeta('foods-core-000.sqlite', 1);

      final importer = CatalogShardImporter(database: database);
      await expectLater(
        importer.importCatalog(
          manifest: manifestFor([core]),
          shards: [ShardInput(meta: core, path: shardPath(core.file))],
        ),
        throwsA(isA<CatalogImportException>()),
      );

      expect(await database.select(database.foods).get(), isEmpty);
      expect(
        (await database.select(database.foodImportJobs).get()).single.status,
        'failed',
      );
    });

    test('rejects a shard row with an out-of-range nutrition value', () async {
      await writeShard('foods-core-000.sqlite', [row('off:1', kcal: -5)]);
      final core = await shardMeta('foods-core-000.sqlite', 1);

      final importer = CatalogShardImporter(database: database);
      await expectLater(
        importer.importCatalog(
          manifest: manifestFor([core]),
          shards: [ShardInput(meta: core, path: shardPath(core.file))],
        ),
        throwsA(isA<CatalogImportException>()),
      );
      expect(await database.select(database.foods).get(), isEmpty);
    });

    test('rejects a shard containing duplicate ids', () async {
      await writeShard('foods-core-000.sqlite', [
        row('off:1', name: 'A'),
        row('off:1', name: 'B'),
      ]);
      final core = await shardMeta('foods-core-000.sqlite', 2);

      final importer = CatalogShardImporter(database: database);
      await expectLater(
        importer.importCatalog(
          manifest: manifestFor([core]),
          shards: [ShardInput(meta: core, path: shardPath(core.file))],
        ),
        throwsA(isA<CatalogImportException>()),
      );
      expect(await database.select(database.foods).get(), isEmpty);
    });

    test('keeps existing rows when ids collide', () async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'off:1',
              name: 'User Edited Rice',
              kcalPer100g: 111,
              proteinPer100g: 1,
              carbsPer100g: 2,
              fatPer100g: 3,
              source: 'user',
              isUserCreated: const Value(true),
              state: const Value('user_created'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await writeShard('foods-core-000.sqlite', [row('off:1')]);
      final core = await shardMeta('foods-core-000.sqlite', 1);

      final importer = CatalogShardImporter(database: database);
      final report = await importer.importCatalog(
        manifest: manifestFor([core]),
        shards: [ShardInput(meta: core, path: shardPath(core.file))],
      );

      expect(report.importedRows, 0);
      expect(report.skippedExistingRows, 1);
      final food = (await database.select(database.foods).get()).single;
      expect(food.name, 'User Edited Rice');
      expect(food.state, 'user_created');
    });

    test('skips incomplete rows instead of importing them', () async {
      await writeShard('foods-core-000.sqlite', [
        row('off:1'),
        row(
          'off:9',
          name: 'Partial',
          kcal: 60,
          protein: 3.5,
          carbs: 0,
          fat: 0,
          state: 'incomplete',
        ),
      ]);
      final core = await shardMeta('foods-core-000.sqlite', 2);

      final importer = CatalogShardImporter(database: database);
      final report = await importer.importCatalog(
        manifest: manifestFor([core]),
        shards: [ShardInput(meta: core, path: shardPath(core.file))],
      );

      // incomplete 行留在分片搜索层（1e FTS 接入），不进主库 foods。
      expect(report.importedRows, 1);
      expect(report.incompleteSkippedRows, 1);
      final foods = await database.select(database.foods).get();
      expect(foods.map((f) => f.id), ['off:1']);
    });

    test('resumes an interrupted import and re-imports from scratch', () async {
      await writeShard('foods-core-000.sqlite', [row('off:1')]);
      await writeShard('foods-brand-000.sqlite', [row('off:3')]);
      final core = await shardMeta('foods-core-000.sqlite', 1);
      final brand = await shardMeta('foods-brand-000.sqlite', 1);

      // 模拟中断：job 记录 importing 且只完成 1/2 分片，foods 仍为空。
      final now = DateTime.now().toUtc();
      await database
          .into(database.foodImportJobs)
          .insert(
            FoodImportJobsCompanion.insert(
              id: 'job-interrupted',
              catalogVersion: 20260914,
              status: 'importing',
              totalShards: 2,
              importedShards: const Value(1),
              manifestHash: 'b' * 64,
              startedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final importer = CatalogShardImporter(database: database);
      final report = await importer.importCatalog(
        manifest: manifestFor([core, brand]),
        shards: [
          ShardInput(meta: core, path: shardPath(core.file)),
          ShardInput(meta: brand, path: shardPath(brand.file)),
        ],
      );

      // 中断的 job 不匹配新 manifest hash → 重新完整导入。
      expect(report.resumed, isFalse);
      expect(report.skippedEntirely, isFalse);
      final foods = await database.select(database.foods).get();
      expect(foods.map((f) => f.id), containsAll(['off:1', 'off:3']));
      final jobs = await database.select(database.foodImportJobs).get();
      expect(jobs, hasLength(2));
      expect(
        jobs.firstWhere((j) => j.id != 'job-interrupted').status,
        'completed',
      );
    });

    test('磁盘写满（SQLITE_FULL）按空间不足归类，而不是通用失败', () async {
      // 2026-09-19 API 35 模拟器实测：磁盘满时 SQLite 报 SQLITE_FULL(13)，
      // drift 把它从**后台 isolate** 包成 DriftRemoteException 上抛（探针
      // 实测形态 `DriftRemoteException{remoteCause: SqliteException(13)}`）。
      // 不归类的话，设置页只能显示「意外错误（DriftRemoteException）」，
      // 用户拿不到「清理空间后重试」这条唯一可行动的指引，而且 job 会被
      // 标成 failed——docs/07 §5.6 要求空间不足时保持可续跑。
      //
      // 真实形态：文件库 + 后台 isolate，写入需要新页时报 SQLITE_FULL(13)
      // （探针实测：`PRAGMA max_page_count = page_count` 后，小行可能仍塞进
      // 现有页，必须让行大到需要新页）。
      await writeShard('foods-core-000.sqlite', [
        row('off:1', name: 'x' * 200000),
      ]);
      final core = await shardMeta('foods-core-000.sqlite', 1);

      // 本用例要的是文件库（内存库没有「页写不下」这回事），先关掉
      // setUp 的内存库，免得 drift 报「同一进程建了多个 AppDatabase」。
      await database.close();
      final fullDb = AppDatabase(
        NativeDatabase.createInBackground(
          File('${tempDir.path}${Platform.pathSeparator}full.sqlite'),
        ),
      );
      addTearDown(fullDb.close);
      await fullDb.customStatement('SELECT 1');
      await fullDb.customStatement('VACUUM');
      final pages = (await fullDb
          .customSelect('PRAGMA page_count')
          .getSingle()
          .then((row) => row.data.values.first as int));
      await fullDb.customStatement('PRAGMA max_page_count = $pages');

      final importer = CatalogShardImporter(
        database: fullDb,
        // 前置探测故意放行：让失败只能来自写库那一刻，证明兜底分类有效。
        remainingDiskBytes: () => 1 << 40,
      );

      await expectLater(
        importer.importCatalog(
          manifest: manifestFor([core]),
          shards: [ShardInput(meta: core, path: shardPath(core.file))],
        ),
        throwsA(
          isA<CatalogImportException>().having(
            (e) => e.kind,
            'kind',
            CatalogImportFailureKind.insufficientSpace,
          ),
        ),
      );

      expect(await fullDb.select(fullDb.foods).get(), isEmpty);
      final job = await fullDb.select(fullDb.foodImportJobs).get();
      expect(
        job.single.status,
        'importing',
        reason: '空间不足要保持可续跑（docs/07 §5.6），不是 failed',
      );
    });

    test('第一条写（job insert）就撞上满盘时，同样按空间不足归类', () async {
      // 2026-09-19 API 35 实测：磁盘真满（/data 只剩 44MB）时，导入**第一条
      // 写**——建 job 行——就会失败，而不是等到写分片行。job insert 在
      // `importCatalog` 的 try 之外，所以只在分片写入处做兜底分类是不够的：
      // 探针实测这条路径抛的同样是
      // `DriftRemoteException{remoteCause: SqliteException(13)}`。
      //
      // 用户看到的话术差别就是「清理空间后重试」这条唯一可行动的指引有没有。
      await writeShard('foods-core-000.sqlite', [row('off:1')]);
      final core = await shardMeta('foods-core-000.sqlite', 1);

      await database.close();
      final fullDb = AppDatabase(
        NativeDatabase.createInBackground(
          File('${tempDir.path}${Platform.pathSeparator}jobfull.sqlite'),
        ),
      );
      addTearDown(fullDb.close);
      await fullDb.customStatement('SELECT 1');
      await fullDb.customStatement('VACUUM');
      final pages = (await fullDb
          .customSelect('PRAGMA page_count')
          .getSingle()
          .then((row) => row.data.values.first as int));
      await fullDb.customStatement('PRAGMA max_page_count = $pages');

      // 用同形状的 job 行把表填到写不下（不删行，避免留下可复用的空闲页）。
      var filled = 0;
      for (var i = 0; i < 5000; i++) {
        try {
          await fullDb.customStatement(
            'INSERT INTO food_import_jobs'
            ' (id, catalog_version, status, total_shards, manifest_hash,'
            ' started_at, created_at, updated_at)'
            " VALUES ('seed$i', 202609, 'completed', 5, '${'a' * 64}', 0, 0, 0)",
          );
          filled += 1;
        } catch (_) {
          break;
        }
      }
      expect(filled, greaterThan(0), reason: '探针要先把库填满，否则用例不成立');

      final importer = CatalogShardImporter(
        database: fullDb,
        // 前置探测故意放行：让失败只能来自写库那一刻。
        remainingDiskBytes: () => 1 << 40,
      );

      await expectLater(
        importer.importCatalog(
          manifest: manifestFor([core]),
          shards: [ShardInput(meta: core, path: shardPath(core.file))],
        ),
        throwsA(
          isA<CatalogImportException>().having(
            (e) => e.kind,
            'kind',
            CatalogImportFailureKind.insufficientSpace,
          ),
        ),
      );

      expect(await fullDb.select(fullDb.foods).get(), isEmpty);
    });

    test('stops before a shard when disk space is insufficient', () async {
      await writeShard('foods-core-000.sqlite', [row('off:1')]);
      final core = await shardMeta('foods-core-000.sqlite', 1);

      final importer = CatalogShardImporter(
        database: database,
        remainingDiskBytes: () => 1,
      );
      await expectLater(
        importer.importCatalog(
          manifest: manifestFor([core]),
          shards: [ShardInput(meta: core, path: shardPath(core.file))],
        ),
        throwsA(
          isA<CatalogImportException>().having(
            (e) => e.kind,
            'kind',
            CatalogImportFailureKind.insufficientSpace,
          ),
        ),
      );

      expect(await database.select(database.foods).get(), isEmpty);
      final job = await database.select(database.foodImportJobs).get();
      expect(job.single.status, 'importing');
      expect(job.single.importedShards, 0);
    });

    test(
      'catalog re-import keeps historical meal snapshots byte-identical',
      () async {
        // 历史 meal_item 引用 off:1，快照了当时的营养。
        final now = DateTime.now().toUtc();
        await database
            .into(database.foods)
            .insert(
              FoodsCompanion.insert(
                id: 'off:1',
                name: 'Old Rice',
                kcalPer100g: 130,
                proteinPer100g: 2.7,
                carbsPer100g: 28,
                fatPer100g: 0.3,
                source: 'openfoodfacts',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await database
            .into(database.meals)
            .insert(
              MealsCompanion.insert(
                id: 'meal-1',
                localDate: '2026-09-15',
                slot: 'lunch',
                eatenAt: now,
                source: 'manual',
                createdAt: now,
                updatedAt: now,
              ),
            );
        await database
            .into(database.mealItems)
            .insert(
              MealItemsCompanion.insert(
                id: 'item-1',
                mealId: 'meal-1',
                foodId: const Value('off:1'),
                foodNameSnapshot: 'Old Rice',
                grams: 200,
                kcalSnapshot: 260,
                proteinSnapshot: 5.4,
                carbsSnapshot: 56,
                fatSnapshot: 0.6,
                createdAt: now,
                updatedAt: now,
              ),
            );

        // 新目录版本声称 off:1 有不同营养值（范围内）。
        await writeShard('foods-core-000.sqlite', [
          row('off:1', name: 'New Rice', kcal: 145),
        ]);
        final core = await shardMeta('foods-core-000.sqlite', 1);

        final importer = CatalogShardImporter(database: database);
        await importer.importCatalog(
          manifest: manifestFor([core]),
          shards: [ShardInput(meta: core, path: shardPath(core.file))],
        );

        // 快照不变性（docs/07 §5.5：目录升级不能改变历史营养）。
        final item = (await database.select(database.mealItems).get()).single;
        expect(item.kcalSnapshot, 260);
        expect(item.foodNameSnapshot, 'Old Rice');
        // foods 行本身也保留旧值（用户可见目录不被静默覆盖）。
        final food = (await database.select(database.foods).get()).single;
        expect(food.name, 'Old Rice');
        expect(food.kcalPer100g, 130);
      },
    );
  });

  group('真机缺陷回归：分片用独立只读连接读，不在主库连接上 ATTACH', () {
    test('主库连接上不出现附着库，分片连接是只读的', () async {
      // 2026-09-16 API 35 真机复现：主库是 SQLCipher，`ATTACH` 明文分片会把
      // 主库密钥套到分片上 → `SqliteException(26) file is not a database`。
      await writeShard('foods-core-000.sqlite', [row('off:1')]);
      final meta = await shardMeta('foods-core-000.sqlite', 1);

      final opened = <String>[];
      final importer = CatalogShardImporter(
        database: database,
        openShard: (path) {
          opened.add(path);
          final shardDb = openCatalogShardReadOnly(path);
          expect(
            () => shardDb.execute('CREATE TABLE probe (x INTEGER)'),
            throwsA(isA<sqlite.SqliteException>()),
            reason: '分片连接必须是只读的（readOnly）',
          );
          return shardDb;
        },
      );
      await importer.importCatalog(
        manifest: manifestFor([meta]),
        shards: [ShardInput(meta: meta, path: shardPath(meta.file))],
      );

      // 每个分片恰好开一条独立连接；主库连接上没有多出 shard_src 之类的
      // 附着库——ATTACH 一旦发生，真机导入就会失败，这里把它钉成回归项。
      expect(opened, [shardPath('foods-core-000.sqlite')]);
      final attached = await database
          .customSelect('PRAGMA database_list')
          .get();
      expect(attached.map((row) => row.data['name']).toList(), [
        'main',
      ], reason: '导入器不得在主库连接上 ATTACH 分片');
      expect(await _stagingTableCount(database), 0);
    });

    test('分片不是 SQLite 时归为 unreadableShard，不漏出驱动异常', () async {
      await File(shardPath('foods-core-000.sqlite'))
          .writeAsBytes(List<int>.filled(4096, 7));
      final meta = await shardMeta('foods-core-000.sqlite', 1);

      await expectLater(
        CatalogShardImporter(database: database).importCatalog(
          manifest: manifestFor([meta]),
          shards: [ShardInput(meta: meta, path: shardPath(meta.file))],
        ),
        throwsA(
          isA<CatalogImportException>().having(
            (e) => e.kind,
            'kind',
            CatalogImportFailureKind.unreadableShard,
          ),
        ),
      );
      final jobs = await database.select(database.foodImportJobs).get();
      expect(jobs.single.status, 'failed');
      expect(await database.select(database.foods).get(), isEmpty);
      expect(await _stagingTableCount(database), 0);
    });
  });
}

Future<int> _stagingTableCount(AppDatabase database) async {
  final rows = await database
      .customSelect(
        "SELECT COUNT(*) AS c FROM sqlite_master WHERE type='table' AND"
        " name LIKE 'staging_catalog_%'",
      )
      .getSingle();
  return rows.data['c'] as int;
}
