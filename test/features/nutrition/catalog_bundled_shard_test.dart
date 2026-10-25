import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_bootstrap.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_importer.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_source.dart';

/// **真实随包产物**的首次安装导入（docs/07 §5.6）。
///
/// 与 `catalog_bootstrap_test.dart` 的分工：那个文件用内存假分片量逻辑，这个
/// 文件用 `tool/food_catalog/run_full_etl.sh` 真正打进包里的
/// `assets/catalog/catalog.manifest.json` + `foods-core-000.sqlite`，让「装完就能
/// 搜到食物」这条承诺在**同一个产物**上被验证一次——包括 sha256 校验、行数、
/// 中文条目是否真的落在随包分片里。
///
/// 目录还没构建时（干净检出）标记跳过，不假装通过。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase database;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-bundled-');
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  test('随包 core 分片装完即导入，且能按中文与英文搜到', () async {
    final source = CatalogShardSource(
      supportDir: tempDir.path,
      assetLoader: _rootBundleLoader,
    );
    final manifest = await source.loadBundledManifest();
    if (manifest == null) {
      markTestSkipped('随包目录不存在：先跑 tool/food_catalog/run_full_etl.sh');
      return;
    }

    // 随包的就是 manifest 的第一个分片（CatalogManifest.coreShard 的约定）。
    expect(manifest.coreShard.file, 'foods-core-000.sqlite');
    expect(manifest.coreShard.rows, greaterThanOrEqualTo(5000));
    expect(manifest.totalShards, greaterThan(1), reason: '其余分片按需分发');

    final bootstrap = CatalogBootstrap(
      source: source,
      importer: CatalogShardImporter(database: database),
    );
    final result = await bootstrap.run();

    expect(result.failure, isNull);
    expect(result.importedRows, manifest.coreShard.rows);
    expect(
      result.missingShards,
      hasLength(manifest.totalShards - 1),
      reason: '其余分片这次本就不在本地',
    );
    expect(
      await database.select(database.foods).get(),
      hasLength(manifest.coreShard.rows),
    );

    // 搜索链路按目录取分片：落盘后立即可搜（中英文都要命中，中文条目是
    // 发布时按「中文名优先」排到最前面的那一批）。
    final service = CatalogSearchService(
      shardPaths: [source.shardPath(manifest.coreShard.file)],
    );
    expect(service.search('rice').items, isNotEmpty);
    expect(
      service.search('牛奶').items,
      isNotEmpty,
      reason: '中文条目必须落在随包分片里，否则装完搜不到中文食物',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<Uint8List?> _rootBundleLoader(String key) async {
  try {
    final data = await rootBundle.load(key);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } on FlutterError {
    return null;
  }
}
