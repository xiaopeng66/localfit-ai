import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_manifest.dart';

/// 跨边界契约测试：把 **ETL 真正产出的 manifest** 喂给应用侧的
/// [parseCatalogManifest]。
///
/// 为什么需要它：应用侧与 ETL 是两个语言、两套测试。2.0-1 的 ETL fixture
/// 测试检查了 manifest 的字段，Dart 侧测试用的是手写的 manifest，两边都绿——
/// 但 `quality.fts_sha256` 在 ETL 里**从未被赋值**（一直是空串），而 Dart
/// 契约要求它是 64 位小写十六进制：真实全量 ETL 产出的包会被应用整包拒绝，
/// 50k 导入根本起不来。只有「拿真实产物过一遍对面的解析器」才能抓到这一类。
///
/// 刷新 fixture（ETL 的 manifest 形状变了就重跑一次并替换文件）：
///
/// ```bash
/// cd tool/food_catalog
/// C:/ProgramData/miniconda3/python.exe build_catalog.py \
///   --input sources/openfoodfacts-products.jsonl.gz \
///   --out ../../build/catalog_smoke --catalog-version smoke \
///   --retrieved-at 2026-09-16T00:00:00Z --limit 20000 --shard-rows 5000
/// C:/ProgramData/miniconda3/python.exe accept_catalog.py --dir ../../build/catalog_smoke \
///   --min-canonical 0
/// cp ../../build/catalog_smoke/catalog.manifest.json \
///   ../../test/fixtures/etl_catalog_manifest.smoke.json
/// ```
///
/// fixture（catalog_version `smoke`、4 个 core 分片）是 20k 行前缀的真实产出，
/// 不是手写样例。
///
/// 2.0-1h 更新：ETL 改为**只发布四项宏量齐全的条目**（docs/07 §10：不完整
/// 条目只能作搜索参考且不得超过 5%，而 OFF 全量实测只有 ~80% 完整），因此
/// fixture 从 5 分片/canonical 17577（含 incomplete）变为 4 分片/canonical
/// 17040，`macro_complete_ratio` 变成 1.0。
void main() {
  final fixture = File(
    '${Directory.current.path}/test/fixtures/etl_catalog_manifest.smoke.json',
  );

  test('ETL 产出的 manifest 能通过应用侧解析（零违规项）', () {
    expect(
      fixture.existsSync(),
      isTrue,
      reason: 'fixture 丢了：${fixture.path}（刷新命令见本文件顶部注释）',
    );
    final raw = jsonDecode(fixture.readAsStringSync()) as Map<String, Object?>;

    // 不吞异常：违规项要连同内容一起看到，才能判断是契约漂移还是 fixture 过期。
    final manifest = parseCatalogManifest(raw);

    expect(manifest.manifestVersion, 1);
    expect(manifest.sources, hasLength(1));
    expect(manifest.sources.single.license, 'odbl-1.0');
    expect(manifest.sources.single.attribution, isNotEmpty);
    expect(manifest.shards, hasLength(4));
    expect(manifest.shards.every((shard) => shard.sha256.length == 64), isTrue);
    expect(manifest.shards.every((shard) => shard.rows > 0), isTrue);
    expect(manifest.shards.every((shard) => shard.kind == 'core'), isTrue);

    // 每一项都是应用侧真会读的字段（不是装饰性的）。
    expect(manifest.quality.canonicalRows, 17040);
    expect(manifest.quality.aliasRows, greaterThan(0));
    expect(manifest.quality.duplicateIds, 0);
    expect(manifest.quality.missingLicenseCount, 0);
    // 发布目录里的每一条都能参与本地营养计算（docs/07 §10 的 ≥95% 门槛）；
    // 不完整候选在 ETL 阶段就不发布，只有这类包才允许进 App。
    expect(manifest.quality.macroCompleteRatio, 1.0);
    expect(manifest.quality.ftsIndexRows, greaterThan(0));
    expect(
      manifest.quality.ftsSha256,
      '75a430278f3469c4ddefb06d32b3f0abc1ff9df481c0f8795266e5fabac00a33',
    );
    // 分片行数之和 == canonical（分片是唯一数据来源，不能对不上）。
    expect(
      manifest.shards.fold<int>(0, (sum, shard) => sum + shard.rows),
      manifest.quality.canonicalRows,
    );

    // 2.0-1j：docs/07 §5.5 的三个实体由 ETL 产出并写进 manifest。数字之间要能
    // 互相对账（每条 canonical 一条修订、一条证据；份量只有一部分食物有），
    // 否则应用侧读到的「份量/依据」就跟发布目录对不上。
    expect(manifest.quality.hasOntologyCounts, isTrue);
    expect(manifest.quality.revisionRows, manifest.quality.canonicalRows);
    expect(manifest.quality.evidenceRows, manifest.quality.canonicalRows);
    expect(manifest.quality.portionRows, greaterThan(0));
    expect(
      manifest.quality.portionRows,
      lessThan(manifest.quality.canonicalRows),
      reason: 'OFF 只有一部分条目自称克数份量，全都有的份量反而说明在编',
    );
    for (final shard in manifest.shards) {
      expect(shard.hasOntologyCounts, isTrue, reason: '${shard.file} 缺实体行数');
      // 分片自包含：修订/证据与条目一一对应。
      expect(shard.revisionRows, shard.rows, reason: shard.file);
      expect(shard.evidenceRows, shard.rows, reason: shard.file);
      expect(
        shard.portionRows!,
        lessThanOrEqualTo(shard.rows),
        reason: shard.file,
      );
    }
    expect(
      manifest.shards.fold<int>(0, (sum, shard) => sum + shard.portionRows!),
      manifest.quality.portionRows,
    );
    expect(
      manifest.shards.fold<int>(0, (sum, shard) => sum + shard.revisionRows!),
      manifest.quality.revisionRows,
    );
    expect(
      manifest.shards.fold<int>(0, (sum, shard) => sum + shard.evidenceRows!),
      manifest.quality.evidenceRows,
    );
  });
}
