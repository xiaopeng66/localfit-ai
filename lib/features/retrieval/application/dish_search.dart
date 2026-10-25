/// 菜品/食堂菜的统一检索（docs/39 §6 / docs/40 §7）：关键词 + 标签 + 槽位，
/// RRF 融合 + boost +（可选）MMR。
///
/// **向量路按 P0 结论关闭**（质量 +89% 但 p95 延迟未稳定 <15ms，见
/// docs/evidence/2026-10-18-p0-eval.md）——本服务把向量路留成可插拔的
/// 可选输入：`semanticRanking` 非空时参与 RRF，否则只有关键词/标签两路。
library;

import 'dart:math' as math;

import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/retrieval/application/feedback_store.dart';
import 'package:localfit_ai/features/retrieval/application/ranking.dart';
import 'package:localfit_ai/features/retrieval/application/taste_profile.dart';
import 'package:localfit_ai/features/retrieval/domain/query_understanding.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';

/// 一条检索命中（菜品库 / 食堂菜统一形状）。
final class FoodHit {
  const FoodHit({
    required this.id,
    required this.name,
    required this.kind,
    required this.score,
    this.tags = const [],
    this.kcal = 0,
    this.window,
    this.availability,
    this.reasons = const [],
    this.sourceBadge,
  });

  final String id;
  final String name;

  /// `dish`（菜品库）| `menuItem`（食堂菜）。
  final String kind;

  final double score;
  final List<String> tags;
  final double kcal;

  /// 食堂菜的窗口（「今日有」的可用性来自窗口/菜单状态）。
  final String? window;
  final String? availability;

  /// 「为什么推荐」：命中的关键词/标签/槽位（docs/39 §8 搜索 UI）。
  final List<String> reasons;

  /// 来源徽标文案（食物/菜品/食堂菜…）。
  final String? sourceBadge;
}

/// 检索调试信息（docs/39 G21：关键词/阈值/各路命中数/候选分数）。
final class RetrievalDebugInfo {
  const RetrievalDebugInfo({
    required this.keywords,
    required this.expanded,
    required this.slots,
    required this.negations,
    required this.routeHits,
    required this.candidateCount,
    required this.mode,
    required this.topScores,
    required this.semanticEnabled,
  });

  final List<String> keywords;
  final List<String> expanded;
  final List<String> slots;
  final List<String> negations;

  /// 每一路的命中数（关键词/标签/语义）。
  final Map<String, int> routeHits;
  final int candidateCount;
  final RetrievalMode mode;

  /// 前几条的分数（解释排序用）。
  final List<({String id, double score})> topScores;

  /// 本轮是否真的跑了语义路（P0 结论：默认关）。
  final bool semanticEnabled;
}

/// 检索结果（含调试信息）。
final class RetrievalResult {
  const RetrievalResult({required this.hits, required this.debug});
  final List<FoodHit> hits;
  final RetrievalDebugInfo debug;
}

/// 菜品检索服务。纯本地、无网络、无 AI 调用。
///
/// 不是 `final class`：菜单页与 AI 短名单的测试会注入计数/脚本化实现来钉
/// 防抖次数与段级缓存（行为仍由 [search] 的默认实现给）。
class DishSearchService {
  const DishSearchService();

  /// 检索。
  ///
  /// [semanticRanking] 是可选的语义名次（id 列表）——P0 默认关（传 null）。
  /// [todayMenuItemIds] 非空时，食堂菜只保留今日在菜单上的（可用性硬过滤）。
  RetrievalResult search({
    required String query,
    required List<DishRecord> dishes,
    List<CanteenDish> canteenDishes = const [],
    List<String>? semanticRanking,
    Set<String>? todayMenuItemIds,
    RetrievalMode mode = RetrievalMode.balanced,
    String? targetSlot,
    Set<String> recentlyEatenNames = const {},

    /// 口味画像（满 N 餐前 `active=false`，此时不参与排序）。
    TasteProfile? taste,

    /// 口味**向量**画像（docs/43 B9）：与 [taste] 取较大者，**不叠加**。
    TasteVectorProfile? tasteVector,

    /// 菜品 id → 向量（口味向量的相似度来源）；缺省 = 无向量，只看标签画像。
    Map<String, List<double>> dishVectors = const {},

    /// 软排除（只扣分，不排除）。
    SoftExclusionRules exclusions = SoftExclusionRules.empty,

    /// 推荐反馈（显式点赞/换一个；样本不足时不生效）。
    FeedbackStore? feedback,
    int limit = 50,
  }) {
    final understood = understandQuery(query);
    final keywordRoute = <String, double>{};
    final tagRoute = <String, double>{};
    final reasons = <String, List<String>>{};

    void consider(
      String id,
      String name,
      List<String> tags, {
      double slotBoost = 0,
    }) {
      final haystack = '$name ${tags.join(' ')}';
      var keywordScore = 0.0;
      for (final gram in bigramsOf(name)) {
        if (understood.original.contains(gram)) keywordScore += 1.0;
      }
      for (final keyword in [...understood.keywords, ...understood.expanded]) {
        if (keyword.isEmpty) continue;
        if (haystack.contains(keyword)) keywordScore += 1.2;
      }
      // 否定词只做软惩罚（不硬过滤）。
      for (final negation in understood.negations) {
        if (name.contains(negation)) keywordScore -= 0.6;
      }
      if (keywordScore != 0) {
        keywordRoute[id] = keywordScore;
        (reasons[id] ??= []).add('关键词');
      }
      var tagScore = 0.0;
      for (final tag in tags) {
        for (final keyword in understood.keywords) {
          if (tag.contains(keyword) || keyword.contains(tag)) tagScore += 1.0;
        }
        for (final expanded in understood.expanded) {
          if (tag.contains(expanded) || expanded.contains(tag)) {
            tagScore += 0.8;
          }
        }
      }
      if (slotBoost > 0) {
        tagScore += slotBoost;
        (reasons[id] ??= []).add('餐次');
      }
      if (tagScore != 0) {
        tagRoute[id] = tagScore;
        (reasons[id] ??= []).add('标签');
      }
    }

    for (final dish in dishes) {
      consider(dish.id, dish.name, _dishTags(dish.name));
    }
    for (final dish in canteenDishes) {
      if (todayMenuItemIds != null && !todayMenuItemIds.contains(dish.id)) {
        continue;
      }
      consider(
        dish.id,
        dish.name,
        dish.tags,
        slotBoost: targetSlot != null && dish.tags.contains(targetSlot) ? 1 : 0,
      );
    }

    List<String> ranked(Map<String, double> scores) => [
      for (final entry
          in (scores.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value))))
        entry.key,
    ];

    final keywordRanking = ranked(keywordRoute);
    final tagRanking = ranked(tagRoute);
    final semantic = semanticRanking ?? const <String>[];
    // 「为什么命中」的第三路（docs/39 §8 搜索 UI）：只有真的参与了 RRF 才标。
    for (final id in semantic) {
      final list = reasons[id] ??= <String>[];
      if (!list.contains('语义')) list.add('语义');
    }
    final fused = reciprocalRankFusion(
      {
        'keyword': keywordRanking,
        'tags': tagRanking,
        if (semantic.isNotEmpty) 'semantic': semantic,
      },
      weights: {
        'keyword': mode.keywordWeight,
        'tags': mode.tagWeight,
        if (semantic.isNotEmpty) 'semantic': mode.semanticWeight,
      },
      limit: math.max(limit * 4, 200),
    );

    // 名称与 id 索引（命中 id → 展示信息）。
    final byId =
        <
          String,
          ({
            String name,
            List<String> tags,
            double kcal,
            String? window,
            String kind,
            String? badge,
          })
        >{};
    for (final dish in dishes) {
      byId[dish.id] = (
        name: dish.name,
        tags: _dishTags(dish.name),
        kcal: dish.kcal,
        window: dish.servingWindow,
        kind: 'dish',
        badge: '菜品',
      );
    }
    for (final dish in canteenDishes) {
      byId[dish.id] = (
        name: dish.name,
        tags: dish.tags,
        kcal: dish.kcalPer100g ?? 0,
        window: null,
        kind: 'menuItem',
        badge: '食堂菜',
      );
    }

    final hits = <FoodHit>[];
    for (final candidate in fused) {
      final info = byId[candidate.id];
      if (info == null) continue;
      final excluded = exclusions.matches(name: info.name, window: info.window);
      // 口味：标签画像与口味向量**取较大者，不叠加**（docs/43 B9）。
      final tagAffinity =
          taste?.affinityOf(name: info.name, tags: info.tags) ?? 0;
      final vectorAffinity =
          tasteVector?.affinityOf(dishVectors[candidate.id]) ?? 0;
      final affinity = math.max(tagAffinity, vectorAffinity);
      final boosted =
          applyBoosts(
            candidate.score,
            inTargetSlot: targetSlot != null && info.tags.contains(targetSlot),
            recentlyEaten: recentlyEatenNames.contains(info.name),
            tasteSimilarity: affinity,
          ) *
          (excluded ? 0.5 : 1.0) *
          (feedback?.multiplierFor(info.name) ?? 1.0);
      hits.add(
        FoodHit(
          id: candidate.id,
          name: info.name,
          kind: info.kind,
          score: boosted,
          tags: info.tags,
          kcal: info.kcal,
          window: info.window,
          reasons: reasons[candidate.id] ?? const [],
          sourceBadge: info.badge,
        ),
      );
      if (hits.length >= limit) break;
    }
    hits.sort((a, b) => b.score.compareTo(a.score));

    return RetrievalResult(
      hits: hits,
      debug: RetrievalDebugInfo(
        keywords: understood.keywords,
        expanded: understood.expanded,
        slots: understood.slots.toList(),
        negations: understood.negations.toList(),
        routeHits: {
          'keyword': keywordRoute.length,
          'tags': tagRoute.length,
          'semantic': semantic.length,
        },
        candidateCount: fused.length,
        mode: mode,
        topScores: [
          for (final hit in hits.take(5)) (id: hit.id, score: hit.score),
        ],
        semanticEnabled: semantic.isNotEmpty,
      ),
    );
  }

  /// 菜品库的结构化标签目前由菜名与供应时段推断（P2 只给食堂菜落了
  /// `tags_json`；菜品库的标签在 P4 的批量打标里补）。这里按菜名给最小集，
  /// 不编造：只认名字里明确的烹饪/口味/餐次词。
  List<String> _dishTags(String name) {
    final tags = <String>[];
    const rules = {
      '辣': ['辣', '麻', '剁椒'],
      '清淡': ['清蒸', '清炒', '白灼', '水煮'],
      '汤': ['汤'],
      '面食': ['面', '米线', '粉'],
      '饭食': ['饭', '盖饭', '炒饭'],
      '油炸': ['炸', '煎'],
      '蒸': ['蒸'],
    };
    for (final entry in rules.entries) {
      if (entry.value.any(name.contains)) tags.add(entry.key);
    }
    return tags;
  }
}

/// AI 短名单（docs/39 §8）：top N 按窗口分组，附标签与营养；
/// 保证多样性（至少各 1 个 veg/protein/staple——没有分类数据时按标签近似）。
List<FoodHit> buildAiShortlist(List<FoodHit> hits, {int limit = 30}) {
  final selected = <FoodHit>[];
  final seenWindows = <String>{};
  for (final hit in hits) {
    if (selected.length >= limit) break;
    // 每个窗口最多 6 条，避免一个窗口刷满短名单。
    final window = hit.window ?? '';
    final count = selected.where((h) => (h.window ?? '') == window).length;
    if (count >= 6) continue;
    selected.add(hit);
    seenWindows.add(window);
  }
  return selected;
}

/// 这句话是否在问「吃什么 / 推荐菜」（docs/43 A2 的注入门控）。
///
/// 只做**字面意图词**判断，不调模型：目的是避免每轮都往 system 里塞 30 条
/// 候选（token 与首字延迟都受不了）。命中才注入；漏判的代价是这一轮模型
/// 看不到短名单（仍可用快照里的菜品库段），不会出错。
bool hasDishRecommendationIntent(String message) {
  final text = message.trim();
  if (text.isEmpty) return false;
  const intents = [
    '吃',
    '推荐',
    '来点',
    '想吃',
    '吃什么',
    '食堂',
    '午餐',
    '晚餐',
    '早餐',
    '加餐',
    '菜',
    '饭',
  ];
  return intents.any(text.contains);
}
