/// 食物目录 manifest 契约（docs/07 §5.3/5.8）。
///
/// ETL（`tool/food_catalog/manifest.py`）产出 JSON；应用侧在导入前用
/// [parseCatalogManifest] 校验。任何违规项都会收集进
/// [CatalogManifestFormatException.errors]，拒绝整个 manifest，
/// 不允许半套目录进入导入流程。
library;

final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// 允许再分发的许可证（SPDX id，小写）。不在清单内的来源不进入发布包。
const Set<String> allowedCatalogLicenses = {
  'odbl-1.0',
  'cc0-1.0',
  'cc-by-4.0',
  'cc-by-sa-3.0',
  'cc-by-sa-4.0',
  'public-domain',
};

/// manifest 解析失败；[errors] 收集全部违规项。
class CatalogManifestFormatException implements Exception {
  CatalogManifestFormatException(this.errors);

  final List<String> errors;

  @override
  String toString() =>
      'CatalogManifestFormatException(${errors.length} violations):\n'
      '${errors.join('\n')}';
}

class CatalogManifestSource {
  const CatalogManifestSource({
    required this.id,
    required this.name,
    required this.license,
    required this.attribution,
    required this.retrievedAt,
  });

  final String id;
  final String name;
  final String license;
  final String attribution;
  final DateTime retrievedAt;
}

class CatalogManifestShard {
  const CatalogManifestShard({
    required this.file,
    required this.kind,
    required this.rows,
    required this.sha256,
    required this.ftsRows,
    this.portionRows,
    this.revisionRows,
    this.evidenceRows,
  });

  /// 纯文件名（禁止路径分隔符），随包资产置于 assets/catalog/ 下。
  final String file;
  final String kind;
  final int rows;
  final String sha256;
  final int? ftsRows;

  /// docs/07 §5.5 的三个实体在这个分片里的行数（2.0-1j 起由 ETL 产出）。
  ///
  /// 可空是为了兼容 2.0-1j 之前的分片：那时分片里只有 `foods`/`aliases`/
  /// 空的 `portions`，导入器读到 null 就按「这个分片没有实体表」处理。
  final int? portionRows;
  final int? revisionRows;
  final int? evidenceRows;

  /// 这个分片是否申报了三个实体的行数（旧分片没有）。
  bool get hasOntologyCounts =>
      portionRows != null && revisionRows != null && evidenceRows != null;
}

class CatalogManifestQuality {
  const CatalogManifestQuality({
    required this.canonicalRows,
    required this.aliasRows,
    required this.duplicateIds,
    required this.macroCompleteRatio,
    required this.anomalyCount,
    required this.chineseNameCoverage,
    required this.missingLicenseCount,
    required this.ftsIndexRows,
    required this.ftsSha256,
    this.portionRows,
    this.revisionRows,
    this.evidenceRows,
  });

  final int canonicalRows;
  final int aliasRows;
  final int duplicateIds;
  final double macroCompleteRatio;
  final int anomalyCount;
  final double chineseNameCoverage;
  final int missingLicenseCount;
  final int ftsIndexRows;
  final String ftsSha256;

  /// docs/07 §5.5/§5 要求 manifest 报告的三类行数（2.0-1j 起 ETL 一定会写）。
  /// 旧 manifest 为 null。
  ///
  /// 注意：**没有生产消费者**。导入器判断「这个分片有没有实体表」是去分片库里
  /// 查 `sqlite_master`（见 `catalog_shard_importer._readOntology`），因为
  /// manifest 的数字可能与分片实际内容不符，而分片内容才是要读的东西。
  /// [hasOntologyCounts] 只被测试用来断言 ETL 确实申报了这三个数字。
  final int? portionRows;
  final int? revisionRows;
  final int? evidenceRows;

  bool get hasOntologyCounts =>
      portionRows != null && revisionRows != null && evidenceRows != null;
}

class CatalogManifest {
  const CatalogManifest({
    required this.manifestVersion,
    required this.catalogVersion,
    required this.generatedAt,
    required this.transformVersion,
    required this.sources,
    required this.shards,
    required this.quality,
  });

  static const int supportedManifestVersion = 1;

  final int manifestVersion;
  final String catalogVersion;
  final DateTime generatedAt;
  final String transformVersion;
  final List<CatalogManifestSource> sources;
  final List<CatalogManifestShard> shards;
  final CatalogManifestQuality quality;

  int get totalShards => shards.length;

  int get totalRows => shards.fold(0, (sum, shard) => sum + shard.rows);

  /// 随包分发的 core 分片（docs/07 §5.6「首次安装只导入 core shard」）。
  ///
  /// 约定是 manifest 里的**第一个**分片：ETL 先按发布优先级排序（中文名条目
  /// 优先、再按上游流行度、最后按 id）再顺序切分片，所以第一片就是最该随包的
  /// 那批。
  ///
  /// **注意：生产代码不读这个 getter。** `materializeBundledShards` 遍历
  /// `manifest.shards` 全部，靠 `assetLoader` 对未声明资产返回 null 来区分
  /// 「随包有」与「随包没有」——即真正的事实源是 `pubspec.yaml` 的 assets 声明。
  /// 这个 getter 服务于两处：`test/privacy/privacy_statement_audit_test.dart`
  /// 用它断言随包资产只有 manifest + 第一片（测试里是内联取的 `shards.first`），
  /// 以及 `test/features/nutrition/catalog_bundled_shard_test.dart` 的随包导入断言；
  /// ETL 侧由 `test_pipeline.py` 固定分片顺序。
  CatalogManifestShard get coreShard => shards.first;
}

/// 校验并解析 manifest 载荷（jsonDecode 的结果）。
///
/// 收集所有违规项后一次性抛出，方便上游定位整份 manifest 的问题。
CatalogManifest parseCatalogManifest(Object? payload) {
  final errors = <String>[];
  if (payload is! Map<Object?, Object?>) {
    throw CatalogManifestFormatException([
      'manifest payload must be a JSON object',
    ]);
  }
  final json = payload;

  final manifestVersion = _intOf(json['manifest_version']);
  if (manifestVersion == null ||
      manifestVersion != CatalogManifest.supportedManifestVersion) {
    errors.add('unsupported manifest_version: ${json['manifest_version']}');
  }

  final catalogVersion = _stringOf(json['catalog_version']);
  if (catalogVersion == null || catalogVersion.isEmpty) {
    errors.add('catalog_version must be non-empty');
  }

  final generatedAt = _instantOf(json['generated_at']);
  if (generatedAt == null) {
    errors.add('generated_at must be an ISO-8601 instant');
  }

  final transformVersion = _stringOf(json['transform_version']);
  if (transformVersion == null || transformVersion.isEmpty) {
    errors.add('transform_version must be non-empty');
  }

  final sources = <CatalogManifestSource>[];
  final rawSources = json['sources'];
  if (rawSources is! List<Object?> || rawSources.isEmpty) {
    errors.add('sources must list at least one source');
  } else {
    for (final raw in rawSources) {
      if (raw is! Map<Object?, Object?>) {
        errors.add('each source must be a JSON object');
        continue;
      }
      final id = _stringOf(raw['id']) ?? '';
      final name = _stringOf(raw['name']) ?? '';
      if (id.isEmpty) {
        errors.add('source id must be non-empty');
      }
      if (name.isEmpty) {
        errors.add('source name must be non-empty (id: $id)');
      }
      final license = _stringOf(raw['license'])?.toLowerCase();
      if (license == null || !allowedCatalogLicenses.contains(license)) {
        errors.add(
          'source license must be an allow-listed SPDX id: '
          '${id.isEmpty ? '<missing>' : id}',
        );
      }
      final retrievedAt = _instantOf(raw['retrieved_at']);
      if (retrievedAt == null) {
        errors.add(
          'source retrieved_at must be an ISO-8601 instant: '
          '${id.isEmpty ? '<missing>' : id}',
        );
      }
      sources.add(
        CatalogManifestSource(
          id: id,
          name: name,
          license: license ?? '',
          attribution: _stringOf(raw['attribution']) ?? '',
          retrievedAt: retrievedAt ?? DateTime.utc(1970),
        ),
      );
    }
  }

  final shards = <CatalogManifestShard>[];
  final seenShardFiles = <String>{};
  final rawShards = json['shards'];
  if (rawShards is! List<Object?> || rawShards.isEmpty) {
    errors.add('shards must list at least one shard');
  } else {
    for (final raw in rawShards) {
      if (raw is! Map<Object?, Object?>) {
        errors.add('each shard must be a JSON object');
        continue;
      }
      final file = _stringOf(raw['file']) ?? '';
      if (file.isEmpty) {
        errors.add('shard file must be non-empty');
      } else if (file.contains('/') ||
          file.contains('\\') ||
          file.contains('..')) {
        errors.add('shard file must be a bare file name: $file');
      } else if (!seenShardFiles.add(file)) {
        errors.add('duplicate shard file: $file');
      }
      final kind = _stringOf(raw['kind']);
      if (kind == null || kind.isEmpty) {
        errors.add('shard kind must be non-empty (file: $file)');
      }
      final rows = _intOf(raw['rows']);
      if (rows == null || rows < 0) {
        errors.add('shard rows must be a non-negative integer: $file');
      }
      final sha256 = _stringOf(raw['sha256']);
      if (sha256 == null || !_hex64.hasMatch(sha256)) {
        errors.add('shard sha256 must be 64 lowercase hex chars: $file');
      }
      final ftsRows = _intOf(raw['fts_rows']);
      if (ftsRows != null && ftsRows < 0) {
        errors.add('shard fts_rows must be non-negative: $file');
      }
      shards.add(
        CatalogManifestShard(
          file: file,
          kind: kind ?? '',
          rows: rows ?? 0,
          sha256: sha256 ?? '',
          ftsRows: ftsRows,
          portionRows: _optionalCount(raw, 'portion_rows', file, errors),
          revisionRows: _optionalCount(raw, 'revision_rows', file, errors),
          evidenceRows: _optionalCount(raw, 'evidence_rows', file, errors),
        ),
      );
    }
  }

  final quality = _parseQuality(json['quality'], errors);

  if (errors.isNotEmpty) {
    throw CatalogManifestFormatException(errors);
  }

  return CatalogManifest(
    manifestVersion: manifestVersion!,
    catalogVersion: catalogVersion!,
    generatedAt: generatedAt!,
    transformVersion: transformVersion!,
    sources: sources,
    shards: shards,
    quality: quality!,
  );
}

CatalogManifestQuality? _parseQuality(Object? raw, List<String> errors) {
  if (raw is! Map<Object?, Object?>) {
    errors.add('quality must be a JSON object');
    return null;
  }
  int nonNegative(String key) {
    final value = _intOf(raw[key]);
    if (value == null || value < 0) {
      errors.add('quality $key must be a non-negative integer');
      return 0;
    }
    return value;
  }

  final canonicalRows = nonNegative('canonical_rows');
  final aliasRows = nonNegative('alias_rows');
  final duplicateIds = nonNegative('duplicate_ids');
  final anomalyCount = nonNegative('anomaly_count');
  final missingLicenseCount = nonNegative('missing_license_count');
  final ftsIndexRows = nonNegative('fts_index_rows');

  if (duplicateIds != 0) {
    errors.add('quality duplicate_ids must be 0');
  }
  if (missingLicenseCount != 0) {
    errors.add('quality missing_license_count must be 0');
  }

  double ratio(String key) {
    final value = _doubleOf(raw[key]);
    if (value == null || value < 0 || value > 1) {
      errors.add('quality $key must be within [0,1]');
      return 0;
    }
    return value;
  }

  final macroCompleteRatio = ratio('macro_complete_ratio');
  final chineseNameCoverage = ratio('chinese_name_coverage');

  final ftsSha256 = _stringOf(raw['fts_sha256']);
  if (ftsSha256 == null || !_hex64.hasMatch(ftsSha256)) {
    errors.add('quality fts_sha256 must be 64 lowercase hex chars');
  }

  return CatalogManifestQuality(
    canonicalRows: canonicalRows,
    aliasRows: aliasRows,
    duplicateIds: duplicateIds,
    macroCompleteRatio: macroCompleteRatio,
    anomalyCount: anomalyCount,
    chineseNameCoverage: chineseNameCoverage,
    missingLicenseCount: missingLicenseCount,
    ftsIndexRows: ftsIndexRows,
    ftsSha256: ftsSha256 ?? '',
    portionRows: _optionalCount(raw, 'portion_rows', 'quality', errors),
    revisionRows: _optionalCount(raw, 'revision_rows', 'quality', errors),
    evidenceRows: _optionalCount(raw, 'evidence_rows', 'quality', errors),
  );
}

/// docs/07 §5.5/§5 的三类实体行数：**可以缺**（2.0-1j 之前产的 manifest 没有），
/// 但一旦写了就必须是非负整数——静默把 `-1` 或 `"12"` 当 0 会让「报告行数」
/// 变成摆设。
int? _optionalCount(
  Map<Object?, Object?> raw,
  String key,
  String where,
  List<String> errors,
) {
  final value = raw[key];
  if (value == null) return null;
  final parsed = _intOf(value);
  if (parsed == null || parsed < 0) {
    errors.add('$where $key must be a non-negative integer');
    return null;
  }
  return parsed;
}

String? _stringOf(Object? value) => value is String ? value : null;

int? _intOf(Object? value) => value is int ? value : null;

double? _doubleOf(Object? value) {
  if (value is int) return value.toDouble();
  if (value is double) return value;
  return null;
}

DateTime? _instantOf(Object? value) {
  if (value is! String) return null;
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    return null;
  }
}
