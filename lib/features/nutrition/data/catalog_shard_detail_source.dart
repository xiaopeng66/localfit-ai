import 'dart:io';

import 'package:localfit_ai/features/nutrition/domain/food_detail.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 目录分片的详情读取（2.0-1j）。
///
/// 目录搜索命中的条目**还没有导入主库**（导入过的会在主库被搜到、显示成
/// 「主库」），所以份量/修订/证据要从分片文件本身读——ETL 已经把这三个实体
/// 写进分片了（`tool/food_catalog/etl_pipeline.py` 的 SHARD_SCHEMA），用户在
/// 导入之前就能看到份量与来源依据。
///
/// 2.0-1j 之前的分片只有 `foods`/`aliases`/`food_search`：那时读不到实体，
/// 返回空列表而不是报错。
final class CatalogShardDetailSource {
  CatalogShardDetailSource({required List<String> shardPaths})
    : _shardPaths = List.of(shardPaths);

  final List<String> _shardPaths;

  /// 按分片顺序找这个 food id；都没有就返回 null（不再回主库，路由由调用方做）。
  ///
  /// 路径列表是启动时扫出来的：文件之后被删掉/换掉是可能的，缺文件就跳过，
  /// 不能让它变成「详情打不开」——下面的回主库分支会接手。
  Future<FoodDetail?> load(String foodId) async {
    for (final path in _shardPaths) {
      if (!File(path).existsSync()) continue;
      final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
      try {
        final detail = _read(db, foodId);
        if (detail != null) return detail;
      } finally {
        db.dispose();
      }
    }
    return null;
  }

  FoodDetail? _read(sqlite.Database db, String foodId) {
    final rows = db.select(
      'SELECT id, name, state, locale, category, brand, kcal_per100g,'
      ' protein_per100g, carbs_per100g, fat_per100g, source_id, license_status'
      ' FROM foods WHERE id = ?',
      [foodId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;

    // 表在不在，一次问清楚：旧分片没有这三张表。
    final present = db
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((table) => table['name'] as String)
        .toSet();
    final hasEntities =
        present.contains('portions') &&
        present.contains('revisions') &&
        present.contains('evidence');

    final portions = <FoodPortionOption>[];
    FoodRevisionRecord? latestRevision;
    FoodEvidenceRecord? evidence;
    if (hasEntities) {
      final portionRows = db.select(
        'SELECT id, name, grams, locale, source FROM portions WHERE food_id = ?'
        ' ORDER BY grams ASC, name ASC, id ASC',
        [foodId],
      );
      for (final portion in portionRows) {
        portions.add(
          FoodPortionOption(
            id: portion['id'] as String,
            name: portion['name'] as String,
            grams: (portion['grams'] as num).toDouble(),
            locale: portion['locale'] as String? ?? 'zh-CN',
            source: portion['source'] as String? ?? 'unknown',
          ),
        );
      }

      final revisionRows = db.select(
        'SELECT id, revision_number, kcal_per100g, protein_per100g,'
        ' carbs_per100g, fat_per100g, source_evidence_id, quality_status,'
        ' valid_from FROM revisions WHERE food_id = ?'
        ' ORDER BY revision_number DESC, id DESC LIMIT 1',
        [foodId],
      );
      if (revisionRows.isNotEmpty) {
        final revision = revisionRows.first;
        final evidenceId = revision['source_evidence_id'] as String?;
        latestRevision = FoodRevisionRecord(
          id: revision['id'] as String,
          revisionNumber: (revision['revision_number'] as num).toInt(),
          kcalPer100g: (revision['kcal_per100g'] as num?)?.toDouble(),
          proteinGPer100g: (revision['protein_per100g'] as num?)?.toDouble(),
          carbsGPer100g: (revision['carbs_per100g'] as num?)?.toDouble(),
          fatGPer100g: (revision['fat_per100g'] as num?)?.toDouble(),
          sourceEvidenceId: evidenceId,
          qualityStatus: revision['quality_status'] as String,
          validFrom: _optionalInstant(
            revision['valid_from'],
            'revision.${revision['id']}',
          ),
        );
        if (evidenceId != null) {
          final evidenceRows = db.select(
            'SELECT id, source_id, license, attribution, retrieved_at,'
            ' transform_version, quality_status, record_hash FROM evidence'
            ' WHERE id = ?',
            [evidenceId],
          );
          if (evidenceRows.isNotEmpty) {
            final row2 = evidenceRows.first;
            evidence = FoodEvidenceRecord(
              id: row2['id'] as String,
              sourceId: row2['source_id'] as String,
              license: row2['license'] as String,
              attribution: row2['attribution'] as String?,
              retrievedAt: _instant(
                row2['retrieved_at'],
                'evidence.${row2['id']}',
              ),
              transformVersion: row2['transform_version'] as String,
              qualityStatus: row2['quality_status'] as String,
              recordHash: row2['record_hash'] as String,
            );
          }
        }
      }
    }

    return FoodDetail(
      foodId: row['id'] as String,
      name: row['name'] as String,
      brand: row['brand'] as String?,
      category: row['category'] as String?,
      state: row['state'] as String,
      source: row['source_id'] as String,
      licenseStatus: row['license_status'] as String,
      // 分片只有目录条目：这里没有用户自建行，也没有主表的默认份量列。
      isUserCreated: false,
      // 目录侧按上游**质量档**判（裁决 ①：与 `CatalogSearchRow.canJoinPlan`
      // 同一规则——`incomplete` 可搜索但不可加入确认计划，docs/07 §9.3）。
      canJoinPlan:
          (row['state'] as String) == 'verified' ||
          (row['state'] as String) == 'estimated',
      kcalPer100g: (row['kcal_per100g'] as num?)?.toDouble() ?? 0,
      proteinPer100g: (row['protein_per100g'] as num?)?.toDouble() ?? 0,
      carbsPer100g: (row['carbs_per100g'] as num?)?.toDouble() ?? 0,
      fatPer100g: (row['fat_per100g'] as num?)?.toDouble() ?? 0,
      portions: portions,
      latestRevision: latestRevision,
      evidence: evidence,
    );
  }

  /// ETL 写的是 `%Y-%m-%dT%H:%M:%SZ`。解析不了说明分片坏了：抛出去让调用方
  /// 显示失败，而不是悄悄把证据藏起来说「没有证据」。
  DateTime _instant(Object? value, String where) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw FormatException('分片时间戳无法解析（$where）：$value');
    }
    return parsed.toUtc();
  }

  DateTime? _optionalInstant(Object? value, String where) =>
      value == null ? null : _instant(value, where);
}
