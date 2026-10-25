import 'dart:convert';

import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';

/// top-K 本地 AI 投影（docs/07 §5.7 末段）。
///
/// AI 图片/菜单匹配只发送本地检索得到的 top-K 候选的 id、名称与必要
/// 营养元数据，绝不发送完整目录；不可参与计算的行（incomplete/stale/
/// user_created）在投影前被过滤。
final class CatalogAiProjection {
  const CatalogAiProjection._();

  static const int maxTopK = 20;

  /// 过滤并截断候选。K 上限 [maxTopK]，下限 1。
  static List<CatalogSearchResult> projectCandidates(
    List<CatalogSearchResult> candidates, {
    required int topK,
  }) {
    final effectiveTopK = topK < 1 ? 1 : (topK > maxTopK ? maxTopK : topK);
    return candidates
        .where((c) => c.state == 'verified' || c.state == 'estimated')
        .take(effectiveTopK)
        .toList();
  }

  /// 投影为紧凑 JSON（发给 Provider 的 payload 片段）。
  static String toJsonPayload(
    List<CatalogSearchResult> candidates, {
    required int topK,
  }) {
    final projected = projectCandidates(candidates, topK: topK);
    return jsonEncode({
      'top_k': topK < 1 ? 1 : (topK > maxTopK ? maxTopK : topK),
      'candidates': [
        for (final c in projected)
          {
            'id': c.id,
            'name': c.name,
            'state': c.state,
            'brand': c.brand,
            'category': c.category,
            'kcal_per100g': c.kcalPer100g,
            'protein_per100g': c.proteinPer100g,
          },
      ],
    });
  }
}
