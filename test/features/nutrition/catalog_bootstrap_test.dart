import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_bootstrap.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_manifest.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_importer.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_source.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

final _sha256 = Sha256();

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

/// docs/07 §5.6「首次安装只导入 core shard」的随包引导测试。
///
/// 随包资产用内存假实现（`assetLoader`），所以这里量的是**落地与导入逻辑**；
/// 真实随包分片（`assets/catalog/foods-core-000.sqlite`）由
/// `test/features/nutrition/catalog_bundled_shard_test.dart` 覆盖。
void main() {
  late Directory tempDir;
  late AppDatabase database;
  late Uint8List coreBytes;
  late Uint8List restBytes;

  Uint8List makeShard(String tag, List<(String, String)> rows) {
    final path = '${tempDir.path}${Platform.pathSeparator}src-$tag.sqlite';
    final db = sqlite.sqlite3.open(path);
    try {
      db.execute(_shardSchema);
      final stmt = db.prepare(
        'INSERT INTO foods (id, name, state, locale, category, brand,'
        ' kcal_per100g, protein_per100g, carbs_per100g, fat_per100g,'
        ' source_id, source_version, license_status)'
        ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      try {
        for (final (id, name) in rows) {
          stmt.execute([
            id,
            name,
            'verified',
            'en',
            'cereals',
            'Generic',
            130.0,
            2.7,
            28.0,
            0.3,
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
    final bytes = File(path).readAsBytesSync();
    File(path).deleteSync();
    return bytes;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-bootstrap-');
    database = AppDatabase(NativeDatabase.memory());
    coreBytes = makeShard('core', [('off:1', 'Rice'), ('off:2', 'Oats')]);
    restBytes = makeShard('rest', [('off:3', 'Bread'), ('off:4', 'Milk')]);
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<String> sha(Uint8List bytes) async {
    final digest = await _sha256.hash(bytes);
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<Map<String, Object?>> manifestJson() async => {
    'manifest_version': CatalogManifest.supportedManifestVersion,
    'catalog_version': '2026.09-test',
    'generated_at': '2026-09-15T00:00:00Z',
    'transform_version': 'etl-1',
    'sources': [
      {
        'id': 'openfoodfacts',
        'name': 'Open Food Facts',
        'license': 'odbl-1.0',
        'attribution': '(c) OFF contributors',
        'retrieved_at': '2026-09-14T00:00:00Z',
      },
    ],
    'shards': [
      {
        'file': 'foods-core-000.sqlite',
        'kind': 'core',
        'rows': 2,
        'sha256': await sha(coreBytes),
        'fts_rows': 2,
      },
      {
        'file': 'foods-core-001.sqlite',
        'kind': 'core',
        'rows': 2,
        'sha256': await sha(restBytes),
        'fts_rows': 2,
      },
    ],
    'quality': {
      'canonical_rows': 4,
      'alias_rows': 4,
      'duplicate_ids': 0,
      'macro_complete_ratio': 1,
      'anomaly_count': 0,
      'chinese_name_coverage': 0,
      'missing_license_count': 0,
      'fts_index_rows': 4,
      'fts_sha256': 'a' * 64,
    },
  };

  /// 只有 core 分片随包：`foods-core-001.sqlite` 的资产不存在。
  CatalogAssetLoader loaderFor(
    Map<String, Object?> manifest, {
    Set<String> bundledShards = const {'foods-core-000.sqlite'},
    Uint8List? overrideCore,
  }) {
    return (String key) async {
      if (key == CatalogShardSource.defaultManifestAsset) {
        return Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
      }
      for (final shard in bundledShards) {
        if (key == '${CatalogShardSource.defaultAssetDirectory}/$shard') {
          return shard == 'foods-core-000.sqlite' && overrideCore != null
              ? overrideCore
              : (shard == 'foods-core-000.sqlite' ? coreBytes : restBytes);
        }
      }
      return null;
    };
  }

  CatalogBootstrap bootstrapWith(CatalogAssetLoader loader) {
    final source = CatalogShardSource(
      supportDir: tempDir.path,
      assetLoader: loader,
    );
    return CatalogBootstrap(
      source: source,
      importer: CatalogShardImporter(database: database),
    );
  }

  group('随包目录引导（docs/07 §5.6）', () {
    test('首装复制随包 core 分片并导入，其余分片如实列为缺失', () async {
      final manifest = await manifestJson();
      final bootstrap = bootstrapWith(loaderFor(manifest));

      final result = await bootstrap.run();

      expect(result.catalogVersion, '2026.09-test');
      expect(result.importedRows, 2, reason: '首装只导入随包的 core 分片');
      expect(result.importedShards, 1);
      expect(result.totalShards, 2);
      expect(result.missingShards, ['foods-core-001.sqlite']);
      expect(result.isComplete, isFalse);
      expect(
        File(
          '${tempDir.path}${Platform.pathSeparator}catalog'
          '${Platform.pathSeparator}foods-core-000.sqlite',
        ).existsSync(),
        isTrue,
        reason: '落盘后搜索链路（按目录取 .sqlite）才看得到它',
      );
      expect(
        (await database.select(database.foods).get()).map((f) => f.id),
        containsAll(['off:1', 'off:2']),
      );
    });

    test('第二次启动复用已落盘的分片，不重复导入也不重复复制', () async {
      final manifest = await manifestJson();
      final first = bootstrapWith(loaderFor(manifest));
      await first.run();

      var coreAssetLoads = 0;
      final second = bootstrapWith((key) async {
        if (key.endsWith('foods-core-000.sqlite')) coreAssetLoads += 1;
        return loaderFor(manifest)(key);
      });
      final result = await second.run();

      expect(result.skippedEntirely, isTrue);
      expect(result.importedRows, 0);
      expect(result.missingShards, ['foods-core-001.sqlite']);
      expect(coreAssetLoads, 0, reason: '落盘标记命中就不该再把随包分片读一遍（12 MiB 级）');
    });

    test('用户把其余分片放进支持目录后，主动导入能补齐', () async {
      final manifest = await manifestJson();
      await bootstrapWith(loaderFor(manifest)).run();

      final restPath =
          '${tempDir.path}${Platform.pathSeparator}catalog'
          '${Platform.pathSeparator}foods-core-001.sqlite';
      File(restPath).writeAsBytesSync(restBytes);

      final result = await bootstrapWith(loaderFor(manifest)).run();

      // 本地分片集合变了（多了 core-001），幂等键随之变化，于是重走一遍；
      // core-000 的行已在主库里，按「不覆盖既有行」跳过，只真的新增 2 行。
      expect(result.importedShards, 2);
      expect(result.importedRows, 2);
      expect(result.missingShards, isEmpty);
      expect(result.isComplete, isTrue);
      expect(
        (await database.select(database.foods).get()).map((f) => f.id),
        containsAll(['off:1', 'off:2', 'off:3', 'off:4']),
      );
    });

    test('目录版本变了（sha256 不同）时重新复制，不拿旧副本去导入', () async {
      final manifest = await manifestJson();
      await bootstrapWith(loaderFor(manifest)).run();

      final newCore = makeShard('v2', [('off:9', 'Millet')]);
      final nextManifest = await manifestJson();
      (nextManifest['shards']! as List)[0] = {
        'file': 'foods-core-000.sqlite',
        'kind': 'core',
        'rows': 1,
        'sha256': await sha(newCore),
        'fts_rows': 1,
      };

      final result = await bootstrapWith(
        loaderFor(nextManifest, overrideCore: newCore),
      ).run();

      expect(result.failure, isNull, reason: '旧副本会被换掉，不该以 hash 不符失败');
      expect(
        File(
          '${tempDir.path}${Platform.pathSeparator}catalog'
          '${Platform.pathSeparator}foods-core-000.sqlite',
        ).readAsBytesSync(),
        newCore,
      );
      expect(
        (await database.select(database.foods).get()).map((f) => f.id),
        contains('off:9'),
      );
    });

    test('本地分片被改坏时拒绝导入并把可行动原因写进结果', () async {
      final manifest = await manifestJson();
      final bootstrap = bootstrapWith(loaderFor(manifest));
      await bootstrap.prepare();

      final corrupted = Uint8List.fromList(coreBytes);
      corrupted[corrupted.length - 1] ^= 0xFF;
      File(
        '${tempDir.path}${Platform.pathSeparator}catalog'
        '${Platform.pathSeparator}foods-core-000.sqlite',
      ).writeAsBytesSync(corrupted);

      final result = await bootstrap.importAvailable();

      expect(result.failure, contains('校验和'));
      expect(await database.select(database.foods).get(), isEmpty);
      final jobs = await database.select(database.foodImportJobs).get();
      expect(jobs.single.status, 'failed');
    });

    test('随包没有目录时不当作错误，也不写任何行', () async {
      final bootstrap = bootstrapWith((key) async => null);

      final result = await bootstrap.run();

      expect(result.hasCatalog, isFalse);
      expect(result.failure, isNull);
      expect(await database.select(database.foods).get(), isEmpty);
      expect(await database.select(database.foodImportJobs).get(), isEmpty);
    });

    test('准备阶段撞上空间不足时，说的是空间不足而不是类型名', () async {
      // 设备上的触发点是写 `.bundled-shards.json` 失败（满盘时留下 0 字节
      // 的 .tmp），上屏的是「随包目录准备失败（FileSystemException）……可在
      // 「我的 → 食物目录」重新扫描。」——用户看到类型名，而且盘满时
      // 「重新扫描」必然再失败一次。单测没法把真实分区填满，所以这里注入
      // 同形状的 ENOSPC，钉住分类。
      final bootstrap = bootstrapWith(
        (key) async => throw const FileSystemException(
          'write failed',
          null,
          OSError('No space left on device', 28),
        ),
      );

      final result = await bootstrap.run();

      expect(result.hasCatalog, isFalse);
      expect(result.failure, contains('空间'));
      expect(result.failure, isNot(contains('FileSystemException')));
      expect(await database.select(database.foods).get(), isEmpty);
    });

    test('准备阶段失败后，「重新扫描」会真的重试准备而不是只回读失败', () async {
      // 2026-09-19 API 35 实测：满盘时 prepare() 失败，卡片给用户的指引是
      // 「可在「我的 → 食物目录」重新扫描」——但那个按钮只调
      // importAvailable()，而它在 manifest == null 时直接回读缓存的
      // prepareFailure，一次都没重试。用户清完空间按指引点下去，看到的还是
      // 同一句失败：这条恢复路径是死的（docs/07 §5.6 要求「提供恢复」）。
      final manifest = await manifestJson();
      var healthy = false;
      final source = CatalogShardSource(
        supportDir: tempDir.path,
        assetLoader: (key) async {
          if (!healthy) throw StateError('asset unavailable');
          return loaderFor(manifest)(key);
        },
      );
      final bootstrap = CatalogBootstrap(
        source: source,
        importer: CatalogShardImporter(database: database),
      );

      final first = await bootstrap.run();
      expect(first.hasCatalog, isFalse);
      expect(first.failure, contains('随包'));

      // 用户清理空间（这里等价于资产重新可读）后按卡片指引重扫。
      healthy = true;
      final second = await bootstrap.importAvailable();

      expect(
        second.failure,
        isNull,
        reason: '重扫必须真的重试 prepare()，否则卡片上的恢复指引是死胡同',
      );
      expect(second.catalogVersion, '2026.09-test');
      expect(second.importedShards, 1);
    });

    test('准备阶段撞上空间不足时，说的是空间不足而不是类型名', () async {
      // 与上面同一条 catch 分支。设备上的触发点是写 `.bundled-shards.json`
      // 失败（满盘时留下 0 字节的 .tmp）；单测没法把真实分区填满，所以这里
      // 注入同形状的 ENOSPC 错误，钉住分类：上屏要说「空间不足」，
      // 不能让用户对着一个类型名猜。
      final bootstrap = bootstrapWith(
        (key) async => throw const FileSystemException(
          'write failed',
          null,
          OSError('No space left on device', 28),
        ),
      );

      final result = await bootstrap.run();

      expect(result.hasCatalog, isFalse);
      expect(result.failure, contains('空间'));
      expect(result.failure, isNot(contains('FileSystemException')));
      expect(await database.select(database.foods).get(), isEmpty);
    });

    test('随包 manifest 坏掉时不抛异常，但如实记为准备失败', () async {
      // prepare() 在首帧之前跑，这里抛出去就是起不来——文档承诺的是「任何失败
      // 都不上抛」，所以坏 manifest 只能是降级，不能是崩溃；但也不能把它说成
      // 「本次构建没有随包目录数据」，那是另一回事（设置页要如实反映）。
      final bootstrap = bootstrapWith(
        (key) async => Uint8List.fromList(utf8.encode('{ not json')),
      );

      final result = await bootstrap.run();

      expect(result.hasCatalog, isFalse);
      expect(result.failure, isA<String>());
      expect(result.failure, contains('随包'));
      expect(result.isComplete, isFalse);
      expect(await database.select(database.foods).get(), isEmpty);
    });

    test('随包资产读不出来时，原因进导入结果而不是静默当成没有目录', () async {
      // 低存储/包损坏：assetLoader 直接抛（真机 2.0-7f 场景）。
      final bootstrap = bootstrapWith(
        (key) async => throw StateError('asset unavailable'),
      );

      final result = await bootstrap.run();

      // 启动路径依旧不抛异常（目录只是可降级能力）。
      expect(result.hasCatalog, isFalse);
      expect(result.failure, isA<String>());
      expect(result.failure, contains('随包'));
      expect(result.isComplete, isFalse);
      // 准备失败时不写任何行，也不留 job。
      expect(await database.select(database.foods).get(), isEmpty);
      expect(await database.select(database.foodImportJobs).get(), isEmpty);
    });

    test('分类之外的异常（驱动/文件系统）也被收成可行动失败', () async {
      final manifest = await manifestJson();
      final source = CatalogShardSource(
        supportDir: tempDir.path,
        assetLoader: loaderFor(manifest),
      );
      final bootstrap = CatalogBootstrap(
        source: source,
        // 注入一个抛非 SqliteException 的分片连接：2026-09-16 真机上漏出去的
        // 就是这一类异常（界面全无提示、目录静默为空）。
        importer: CatalogShardImporter(
          database: database,
          openShard: (_) => throw StateError('boom'),
        ),
      );
      await bootstrap.prepare();

      final result = await bootstrap.importAvailable();

      expect(result.failure, isA<String>());
      // O-1（2026-09-19 裁定）：用户可见文案不再插异常类型名——类型名对
      // 用户不可行动，还把「类型名=预期文案」钉成契约（BUG-17 的温床）。
      // 保留的是可行动指引；原始 message（可能含本机路径）依旧不进来。
      expect(result.failure, contains('目录导入遇到意外错误'));
      // docs/28 §5.6：恢复入口从「我的 → 食物目录」搬进了食材库那一行的
      // 「导入扩展食物目录」——指路的文案必须跟着换，否则用户按指引找不到。
      expect(result.failure, contains('「我的 → 食材库 → 导入扩展食物目录」'));
      expect(result.failure, isNot(contains('StateError')));
      expect(result.failure, isNot(contains('Exception')));
      expect(await database.select(database.foods).get(), isEmpty);
    });

    test('磁盘写满时上屏的是「剩余空间不足」，不是不可读的类型名', () async {
      // 2026-09-19 API 35 模拟器实测：满盘时导入抛的是 drift 包装后的
      // `DriftRemoteException`，此前落进通用兜底、卡片显示
      // 「目录导入遇到意外错误（DriftRemoteException）」——用户看到的是一个
      // 类型名，不是「清理空间后重试」。这里钉住端到端文案。
      //
      // 分片行必须大到「写进主库时需要新页」：`max_page_count` 压到当前页数
      // 后，小行仍能塞进已有页，只有需要新页的写才会 SQLITE_FULL(13)。
      final bigCore = makeShard('bigcore', [('off:1', 'x' * 200000)]);
      final manifest = await manifestJson();
      // 覆盖 manifest 里 core 分片的行数与校验和，让它与这份大分片一致。
      (manifest['shards']! as List)[0] = {
        'file': 'foods-core-000.sqlite',
        'kind': 'core',
        'rows': 1,
        'sha256': await sha(bigCore),
        'fts_rows': 1,
      };

      final source = CatalogShardSource(
        supportDir: tempDir.path,
        assetLoader: loaderFor(manifest, overrideCore: bigCore),
      );

      // 需要文件库才能造出 SQLITE_FULL(13)（内存库没有「页写不下」这回事）。
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

      final bootstrap = CatalogBootstrap(
        source: source,
        importer: CatalogShardImporter(
          database: fullDb,
          remainingDiskBytes: () => 1 << 40,
        ),
      );
      await bootstrap.prepare();

      final result = await bootstrap.importAvailable();

      expect(result.failure, contains('剩余空间不足'));
      expect(result.failure, isNot(contains('DriftRemoteException')));
      expect(await fullDb.select(fullDb.foods).get(), isEmpty);
    });

    test('满到第一条写就失败时，上屏的同样是「剩余空间不足」', () async {
      // 与上一条的区别在**失败点**：上一条是写分片行时撞满盘，这一条是
      // 建 job 行（本次导入的第一条写）就撞满盘。2026-09-19 API 35 实测：
      // /data 只剩 44MB 时导入卡在 job insert，用户看到的仍是
      // 「意外错误（DriftRemoteException）」。两条路径都要落在同一句话术上。
      final manifest = await manifestJson();
      final source = CatalogShardSource(
        supportDir: tempDir.path,
        assetLoader: loaderFor(manifest),
      );

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
      // 用同形状的 job 行把表填满（不删行，避免留下可复用空闲页）。
      for (var i = 0; i < 5000; i++) {
        try {
          await fullDb.customStatement(
            'INSERT INTO food_import_jobs'
            ' (id, catalog_version, status, total_shards, manifest_hash,'
            ' started_at, created_at, updated_at)'
            " VALUES ('seed$i', 202609, 'completed', 5, '${'a' * 64}', 0, 0, 0)",
          );
        } catch (_) {
          break;
        }
      }

      final bootstrap = CatalogBootstrap(
        source: source,
        importer: CatalogShardImporter(
          database: fullDb,
          remainingDiskBytes: () => 1 << 40,
        ),
      );
      await bootstrap.prepare();

      final result = await bootstrap.importAvailable();

      expect(result.failure, contains('剩余空间不足'));
      expect(result.failure, isNot(contains('DriftRemoteException')));
      expect(await fullDb.select(fullDb.foods).get(), isEmpty);
    });
  });
}
