import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_manifest.dart';

void main() {
  // 与 docs/07 §5.3/5.8 对齐的最小合法 manifest fixture。
  Map<String, Object> validManifest() => {
    'manifest_version': 1,
    'catalog_version': '2026.09-test',
    'generated_at': '2026-09-15T00:00:00Z',
    'transform_version': 'etl-1',
    'sources': [
      {
        'id': 'openfoodfacts',
        'name': 'Open Food Facts',
        'license': 'odbl-1.0',
        'attribution': '© Open Food Facts contributors (ODbL)',
        'retrieved_at': '2026-09-14T00:00:00Z',
      },
    ],
    'shards': [
      {
        'file': 'foods-core-000.sqlite',
        'kind': 'core',
        'rows': 20000,
        'sha256': 'a' * 64,
        'fts_rows': 21000,
        'portion_rows': 8000,
        'revision_rows': 20000,
        'evidence_rows': 20000,
      },
      {
        'file': 'foods-brand-000.sqlite',
        'kind': 'brand',
        'rows': 30000,
        'sha256': 'b' * 64,
        'fts_rows': 31000,
        'portion_rows': 4000,
        'revision_rows': 30000,
        'evidence_rows': 30000,
      },
    ],
    'quality': {
      'canonical_rows': 50000,
      'alias_rows': 61000,
      'portion_rows': 12000,
      'revision_rows': 50000,
      'evidence_rows': 50000,
      'duplicate_ids': 0,
      'macro_complete_ratio': 0.96,
      'anomaly_count': 0,
      'chinese_name_coverage': 0.21,
      'missing_license_count': 0,
      'fts_index_rows': 52000,
      'fts_sha256': 'c' * 64,
    },
  };

  group('catalog manifest parser', () {
    test('parses a valid manifest with typed sources, shards, and quality', () {
      final manifest = parseCatalogManifest(validManifest());

      expect(manifest.manifestVersion, 1);
      expect(manifest.catalogVersion, '2026.09-test');
      expect(manifest.transformVersion, 'etl-1');
      expect(manifest.generatedAt, DateTime.utc(2026, 9, 15));
      expect(manifest.sources.single.id, 'openfoodfacts');
      expect(manifest.sources.single.license, 'odbl-1.0');
      expect(manifest.sources.single.retrievedAt, DateTime.utc(2026, 9, 14));
      expect(manifest.shards, hasLength(2));
      expect(manifest.shards[0].file, 'foods-core-000.sqlite');
      expect(manifest.shards[0].kind, 'core');
      expect(manifest.shards[0].rows, 20000);
      expect(manifest.shards[0].sha256, 'a' * 64);
      expect(manifest.shards[0].ftsRows, 21000);
      expect(manifest.shards[1].kind, 'brand');
      expect(manifest.quality.canonicalRows, 50000);
      expect(manifest.quality.macroCompleteRatio, closeTo(0.96, 1e-9));
      expect(manifest.totalShards, 2);
      expect(manifest.totalRows, 50000);
    });

    test('parses the §5.5 entity counts on shards and quality', () {
      // docs/07 §5.5/§5 要求 manifest 报告 portions / revisions / evidence 行数；
      // 分片级计数是导入器对账「拷进来的行数」用的。
      final manifest = parseCatalogManifest(validManifest());

      expect(manifest.quality.portionRows, 12000);
      expect(manifest.quality.revisionRows, 50000);
      expect(manifest.quality.evidenceRows, 50000);
      expect(manifest.quality.hasOntologyCounts, isTrue);
      expect(manifest.shards[0].portionRows, 8000);
      expect(manifest.shards[0].revisionRows, 20000);
      expect(manifest.shards[0].evidenceRows, 20000);
      expect(manifest.shards[1].evidenceRows, 30000);
    });

    test('accepts a pre-2.0-1j manifest without entity counts', () {
      // 旧 manifest 没有这三个字段：解析要照常通过（分片里也没有那些表），
      // 只是 hasOntologyCounts 为 false，导入器按「没有实体表」处理。
      final payload = validManifest();
      (payload['quality']! as Map<String, Object>)
        ..remove('portion_rows')
        ..remove('revision_rows')
        ..remove('evidence_rows');
      for (final shard in payload['shards']! as List<Object?>) {
        (shard! as Map<String, Object>)
          ..remove('portion_rows')
          ..remove('revision_rows')
          ..remove('evidence_rows');
      }

      final manifest = parseCatalogManifest(payload);

      expect(manifest.quality.portionRows, isNull);
      expect(manifest.quality.hasOntologyCounts, isFalse);
      expect(manifest.shards[0].portionRows, isNull);
    });

    test('rejects entity counts that are not non-negative integers', () {
      // 「报告行数」不能是摆设：写了就必须是合法数字，不能静默当 0。
      final payload = validManifest();
      (payload['quality']! as Map<String, Object>)['portion_rows'] = -1;
      final firstShard =
          (payload['shards']! as List<Object?>).first! as Map<String, Object>;
      firstShard['evidence_rows'] = '12';

      expect(
        () => parseCatalogManifest(payload),
        throwsA(
          isA<CatalogManifestFormatException>().having(
            (e) => e.errors,
            'errors',
            allOf(
              contains('quality portion_rows must be a non-negative integer'),
              contains(
                'foods-core-000.sqlite evidence_rows must be a non-negative integer',
              ),
            ),
          ),
        ),
      );
    });

    test('collects every violation instead of failing on the first', () {
      final payload = validManifest()
        ..['manifest_version'] = 99
        ..['catalog_version'] = '';
      (payload['sources'] as List<Object?>).clear();
      (payload['shards'] as List<Object?>).clear();
      try {
        parseCatalogManifest(payload);
        fail('expected CatalogManifestFormatException');
      } on CatalogManifestFormatException catch (e) {
        expect(e.errors, contains('unsupported manifest_version: 99'));
        expect(e.errors, contains('catalog_version must be non-empty'));
        expect(e.errors, contains('sources must list at least one source'));
        expect(e.errors, contains('shards must list at least one shard'));
        expect(e.errors.length, greaterThanOrEqualTo(4));
      }
    });

    test('rejects a non-map payload', () {
      expect(
        () => parseCatalogManifest(<String>['nope']),
        throwsA(
          isA<CatalogManifestFormatException>().having(
            (e) => e.errors,
            'errors',
            contains('manifest payload must be a JSON object'),
          ),
        ),
      );
    });

    test('rejects a shard file with path traversal or absolute path', () {
      final payload = validManifest();
      (payload['shards'] as List<Object?>)[0] = {
        'file': '../../evil.sqlite',
        'kind': 'core',
        'rows': 1,
        'sha256': 'a' * 64,
      };
      expect(
        () => parseCatalogManifest(payload),
        throwsA(
          isA<CatalogManifestFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains('shard file must be a bare file name: ../../evil.sqlite'),
          ),
        ),
      );
    });

    test('rejects a shard hash that is not 64 lowercase hex chars', () {
      final payload = validManifest();
      (payload['shards'] as List<Object?>)[0] = {
        'file': 'foods-core-000.sqlite',
        'kind': 'core',
        'rows': 1,
        'sha256': 'A' * 64,
      };
      expect(
        () => parseCatalogManifest(payload),
        throwsA(
          isA<CatalogManifestFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains(
              'shard sha256 must be 64 lowercase hex chars: '
              'foods-core-000.sqlite',
            ),
          ),
        ),
      );
    });

    test('rejects duplicate shard file names', () {
      final payload = validManifest();
      (payload['shards'] as List<Object?>).add({
        'file': 'foods-core-000.sqlite',
        'kind': 'brand',
        'rows': 5,
        'sha256': 'b' * 64,
      });
      expect(
        () => parseCatalogManifest(payload),
        throwsA(
          isA<CatalogManifestFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains('duplicate shard file: foods-core-000.sqlite'),
          ),
        ),
      );
    });

    test('rejects negative or non-integer shard rows', () {
      final payload = validManifest();
      (payload['shards'] as List<Object?>)[0] = {
        'file': 'foods-core-000.sqlite',
        'kind': 'core',
        'rows': -1,
        'sha256': 'a' * 64,
      };
      expect(
        () => parseCatalogManifest(payload),
        throwsA(
          isA<CatalogManifestFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains(
              'shard rows must be a non-negative integer: '
              'foods-core-000.sqlite',
            ),
          ),
        ),
      );
    });

    test('rejects a source whose license is missing or not allow-listed', () {
      final payload = validManifest();
      (payload['sources'] as List<Object?>)[0] = {
        'id': 'mystery-source',
        'name': 'Mystery',
        'license': 'unknown',
        'attribution': '',
        'retrieved_at': '2026-09-14T00:00:00Z',
      };
      expect(
        () => parseCatalogManifest(payload),
        throwsA(
          isA<CatalogManifestFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains(
              'source license must be an allow-listed SPDX id: '
              'mystery-source',
            ),
          ),
        ),
      );
    });

    test('rejects a source with an unparseable retrieved_at', () {
      final payload = validManifest();
      (payload['sources'] as List<Object?>)[0] = {
        'id': 'openfoodfacts',
        'name': 'Open Food Facts',
        'license': 'odbl-1.0',
        'attribution': 'x',
        'retrieved_at': 'last tuesday',
      };
      expect(
        () => parseCatalogManifest(payload),
        throwsA(
          isA<CatalogManifestFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains(
              'source retrieved_at must be an ISO-8601 instant: '
              'openfoodfacts',
            ),
          ),
        ),
      );
    });

    test('rejects duplicate ids or ratio out of range in quality report', () {
      final payload = validManifest();
      (payload['quality'] as Map<String, Object?>)['duplicate_ids'] = 3;
      (payload['quality'] as Map<String, Object?>)['macro_complete_ratio'] =
          1.5;
      expect(
        () => parseCatalogManifest(payload),
        throwsA(
          isA<CatalogManifestFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            allOf(
              contains('quality duplicate_ids must be 0'),
              contains('quality macro_complete_ratio must be within [0,1]'),
            ),
          ),
        ),
      );
    });

    test('rejects a quality report missing the fts hash', () {
      final payload = validManifest();
      (payload['quality'] as Map<String, Object?>).remove('fts_sha256');
      expect(
        () => parseCatalogManifest(payload),
        throwsA(
          isA<CatalogManifestFormatException>().having(
            (e) => e.errors.join(';'),
            'errors',
            contains('quality fts_sha256 must be 64 lowercase hex chars'),
          ),
        ),
      );
    });
  });
}
