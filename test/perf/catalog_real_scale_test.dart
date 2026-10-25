import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_manifest.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_importer.dart';

/// 真实目录的 50k/100k 导入与搜索实测（docs/07 §10「完成 50k/100k 搜索、
/// 导入和内存性能测试」）。
///
/// 依赖 `assets/catalog`（由 `tool/food_catalog/run_full_etl.sh` 产出，几百 MB），
/// 因此**默认跳过**，显式运行：
///
/// ```bash
/// cd E:/AI/Zcode/localfit-ai
/// export LOCALFIT_CATALOG_PERF=1
/// E:/AI/toolchains/flutter/bin/flutter.bat test test/perf/catalog_real_scale_test.dart
/// ```
///
/// 这里量的是**进程内**耗时（真机 P95 < 200ms 的门槛仍需
/// `docs/09-release-and-device-checklist.md` A/B 的真机复测）；本文件的用处是
/// 在真数据上暴露随分片数增长的退化——`CatalogSearchService` 每次查询都会
/// 打开**每一个**分片文件，OFF 全量有几十个分片，这类问题只有真分片能量出来。
void main() {
  final catalogDir = Directory('${Directory.current.path}/assets/catalog');
  final manifestFile = File('${catalogDir.path}/catalog.manifest.json');

  String? skipReason() {
    if (Platform.environment['LOCALFIT_CATALOG_PERF'] != '1') {
      return '真实目录性能实测：设 LOCALFIT_CATALOG_PERF=1 后显式运行本文件';
    }
    if (!manifestFile.existsSync()) {
      return 'assets/catalog 未就位（先跑 tool/food_catalog/run_full_etl.sh）';
    }
    return null;
  }

  final reason = skipReason();

  late CatalogManifest manifest;
  late List<CatalogManifestShard> shardsBySize;

  setUpAll(() {
    if (reason != null) return;
    final raw =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
    manifest = parseCatalogManifest(raw);
    shardsBySize = List.of(manifest.shards);
  });

  List<CatalogManifestShard> takeUntil(int minRows) {
    final picked = <CatalogManifestShard>[];
    var rows = 0;
    for (final shard in shardsBySize) {
      picked.add(shard);
      rows += shard.rows;
      if (rows >= minRows) break;
    }
    return picked;
  }

  String shardPath(String file) =>
      '${catalogDir.path}${Platform.pathSeparator}$file';

  test(
    '真实分片导入：各规模的行数、耗时与内存',
    () async {
      // 同一进程里连着跑两个规模会让第二次测量背着第一次的堆和页缓存，
      // 所以允许只跑一个规模（默认两个都跑）。要贴进 evidence 的独立数字用
      // `LOCALFIT_CATALOG_PERF_CASES=100k` 单独跑一次。
      final selected = Platform.environment['LOCALFIT_CATALOG_PERF_CASES'];
      final allCases = <String, int>{'50k': 50000, '100k': 100000};
      final cases = <String, int>{
        for (final entry in allCases.entries)
          if (selected == null || selected == 'both' || selected == entry.key)
            entry.key: entry.value,
      };
      expect(
        cases,
        isNotEmpty,
        reason: 'LOCALFIT_CATALOG_PERF_CASES 只认 50k/100k/both',
      );
      final measured = <String>[];

      for (final entry in cases.entries) {
        final picked = takeUntil(entry.value);
        final expectedRows = picked.fold<int>(0, (sum, s) => sum + s.rows);
        final database = AppDatabase(NativeDatabase.memory());
        try {
          final rssBefore = ProcessInfo.currentRss;
          final stopwatch = Stopwatch()..start();
          final report = await CatalogShardImporter(database: database)
              .importCatalog(
                manifest: manifest,
                shards: [
                  for (final meta in picked)
                    ShardInput(meta: meta, path: shardPath(meta.file)),
                ],
              );
          stopwatch.stop();
          final rssAfter = ProcessInfo.currentRss;

          expect(
            report.importedRows,
            expectedRows,
            reason: '${entry.key}: 导入行数必须等于所选分片的 manifest 行数之和',
          );
          expect(report.incompleteSkippedRows, 0, reason: '发布目录里没有不完整行');
          expect(report.skippedEntirely, isFalse);

          measured.add(
            '${entry.key}: ${picked.length} 分片 / ${report.importedRows} 行 / '
            '${stopwatch.elapsedMilliseconds} ms / '
            '${(report.importedRows / (stopwatch.elapsedMilliseconds / 1000)).toStringAsFixed(0)} 行每秒 / '
            'RSS ${rssBefore ~/ 1048576}→${rssAfter ~/ 1048576} MiB',
          );
        } finally {
          await database.close();
        }
      }

      // 打印成可直接贴进 evidence 的一行一条。
      for (final line in measured) {
        // ignore: avoid_print
        print('[catalog-perf] $line');
      }
    },
    skip: reason,
    timeout: const Timeout(Duration(minutes: 15)),
  );

  test(
    '真实分片搜索：50k 子集与全量分片数的 P50/P95（进程内）',
    () async {
      final queries = [
        'rice',
        'chicken',
        'yogurt',
        'milk',
        'cheese',
        'bread',
        'coca',
        'oil',
        'water',
        'apple',
        '面包',
        '牛奶',
        '鸡肉',
        '米',
      ];

      Future<String> measure(
        String label,
        List<CatalogManifestShard> subset,
      ) async {
        final service = CatalogSearchService(
          shardPaths: [for (final meta in subset) shardPath(meta.file)],
        );
        // 预热（打开文件、OS 页缓存），不计入统计。
        service.search('rice');
        final samples = <int>[];
        var hits = 0;
        for (final query in queries) {
          for (var i = 0; i < 3; i++) {
            final stopwatch = Stopwatch()..start();
            final page = service.search(query);
            stopwatch.stop();
            samples.add(stopwatch.elapsedMicroseconds);
            hits += page.items.length;
          }
        }
        samples.sort();
        final p50 = samples[samples.length ~/ 2] / 1000;
        final p95 = samples[(samples.length * 95) ~/ 100] / 1000;
        return '$label: ${subset.length} 分片 / ${samples.length} 次查询 / '
            'P50 ${p50.toStringAsFixed(1)} ms / P95 ${p95.toStringAsFixed(1)} ms / '
            '命中 $hits 条';
      }

      final lines = <String>[
        await measure('50k 子集', takeUntil(50000)),
        await measure('全量分片', shardsBySize),
      ];
      for (final line in lines) {
        // ignore: avoid_print
        print('[catalog-perf] $line');
      }

      // 进程内门槛（真机门槛见 docs/09）：全量分片下 P95 不得超过 200 ms，
      // 否则「每查询打开所有分片」这条路径在真机上一定过不了。
      final service = CatalogSearchService(
        shardPaths: [for (final meta in shardsBySize) shardPath(meta.file)],
      );
      service.search('rice');
      final samples = <int>[];
      for (var i = 0; i < 10; i++) {
        final stopwatch = Stopwatch()..start();
        service.search('chicken');
        stopwatch.stop();
        samples.add(stopwatch.elapsedMicroseconds);
      }
      samples.sort();
      final p95 = samples[(samples.length * 95) ~/ 100] / 1000;
      expect(
        p95,
        lessThan(200),
        reason: '全量 ${shardsBySize.length} 分片下进程内 P95=$p95 ms，已超过真机门槛 200 ms',
      );
    },
    skip: reason,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
