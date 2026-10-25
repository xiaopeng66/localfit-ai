/// 检索融合与排序（docs/39 §6.2）：RRF、boost、MMR、三档预算。
///
/// 为什么不用加权和：向量分、关键词分、重要性、近期是四种量纲，加权和要调参
/// 且易被单一信号支配。RRF 只看名次：`score = Σ 1/(60 + rank_i)`，再叠加
/// 少量 boost（置顶/重要性/口味/近期）。MMR 去近义冗余。
library;

import 'dart:math' as math;

/// RRF 常数（docs/39 §6.2 的 60）。
const int kRrfK = 60;

/// 一条候选在若干名次表里的融合结果。
final class FusedCandidate {
  const FusedCandidate({
    required this.id,
    required this.score,
    required this.routeRanks,
  });

  final String id;
  final double score;

  /// 每一路（keywords/tags/…）里的名次（有命中才有）；调试面板用它解释分数。
  final Map<String, int> routeRanks;
}

/// Reciprocal Rank Fusion：`Σ 1/(k + rank)`（rank 从 1 起）。
///
/// * [rankings]：每路一个有序 id 列表（名次即下标）；
/// * [weights]：可选每路权重（默认 1；**只用于可解释的轻微加权**，不做手调）。
List<FusedCandidate> reciprocalRankFusion(
  Map<String, List<String>> rankings, {
  Map<String, double> weights = const {},
  int limit = 200,
}) {
  final scores = <String, double>{};
  final ranks = <String, Map<String, int>>{};
  for (final entry in rankings.entries) {
    final weight = weights[entry.key] ?? 1.0;
    final route = entry.key;
    for (var index = 0; index < entry.value.length; index++) {
      final id = entry.value[index];
      scores[id] = (scores[id] ?? 0) + weight / (kRrfK + index + 1);
      (ranks[id] ??= {})[route] = index + 1;
    }
  }
  final out = [
    for (final entry in scores.entries)
      FusedCandidate(
        id: entry.key,
        score: entry.value,
        routeRanks: ranks[entry.key] ?? const {},
      ),
  ]..sort((a, b) => b.score.compareTo(a.score));
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// 乘法 boost（1.0 = 中性）。所有 boost 都**有上界**，避免把某一路信号
/// 放大成事实（例如置顶最多 ×1.15）。
double applyBoosts(
  double score, {
  bool pinned = false,
  double importance = 50,
  bool inTargetSlot = false,
  bool recentlyEaten = false,
  double tasteSimilarity = 0,
  bool domainMatch = false,
}) {
  var value = score;
  if (pinned) value *= 1.15;
  // importance 0–100 → 0.9–1.1。
  value *= 0.9 + (importance.clamp(0, 100) / 100) * 0.2;
  if (inTargetSlot) value *= 1.05;
  if (domainMatch) value *= 1.05;
  if (tasteSimilarity > 0) value *= 1 + tasteSimilarity.clamp(0, 1) * 0.05;
  // 软惩罚：近期吃过（默认 3 天）只扣分，不排除（docs/39 §6.1）。
  if (recentlyEaten) value *= 0.85;
  return value;
}

/// MMR（最大边际相关）去冗余：在相关性与多样性之间平衡（λ=0.7）。
///
/// [similarity] 返回两个 id 的相似度（0–1）；没有向量时用「文本重叠率」
/// 作为相似度（同一套接口，换实现不改调用方）。
List<String> maximalMarginalRelevance({
  required List<FusedCandidate> candidates,
  required double Function(String a, String b) similarity,
  int limit = 24,
  double lambda = 0.7,
}) {
  if (candidates.isEmpty || limit <= 0) return const [];
  // 归一到 0–1 便于与相似度同量纲比较。
  final maxScore = candidates.first.score;
  final minScore = candidates.last.score;
  final span = math.max(maxScore - minScore, 1e-9);
  double relevance(FusedCandidate c) => (c.score - minScore) / span;
  final selected = <FusedCandidate>[candidates.first];
  final remaining = [...candidates.skip(1)];
  while (selected.length < limit && remaining.isNotEmpty) {
    var bestIndex = 0;
    var bestValue = double.negativeInfinity;
    for (var i = 0; i < remaining.length; i++) {
      var maxSimilarity = 0.0;
      for (final chosen in selected) {
        maxSimilarity = math.max(
          maxSimilarity,
          similarity(chosen.id, remaining[i].id),
        );
      }
      final value =
          lambda * relevance(remaining[i]) - (1 - lambda) * maxSimilarity;
      if (value > bestValue) {
        bestValue = value;
        bestIndex = i;
      }
    }
    selected.add(remaining.removeAt(bestIndex));
  }
  return [for (final candidate in selected) candidate.id];
}

/// 记忆注入的三档预算（docs/41 D4）：紧凑 / 标准 / 更多。
enum MemoryBudget {
  compact('紧凑', 1500, 12),
  standard('标准', 3000, 24),
  more('更多', 6000, 48);

  const MemoryBudget(this.label, this.maxChars, this.maxItems);
  final String label;
  final int maxChars;
  final int maxItems;
}

/// 文本重叠相似度（MMR 在没有向量时的实现）：两边 bigram 的 Jaccard。
double textOverlapSimilarity(String a, String b) {
  Set<String> grams(String value) {
    final text = value.replaceAll(RegExp(r'\s+'), '');
    if (text.isEmpty) return const {};
    if (text.length <= 2) return {text};
    return {
      for (var i = 0; i + 2 <= text.length; i++) text.substring(i, i + 2),
    };
  }

  final left = grams(a);
  final right = grams(b);
  if (left.isEmpty || right.isEmpty) return 0;
  final intersection = left.intersection(right).length;
  final union = left.union(right).length;
  return union == 0 ? 0 : intersection / union;
}

/// 检索模式（docs/39 §6 / G21 调试面板的「搜索模拟」）。
enum RetrievalMode {
  balanced('均衡', 1, 1, 1),
  keywordFirst('关键词优先', 4, 1, 0.5),
  semanticFirst('语义优先', 0.5, 1, 4);

  const RetrievalMode(
    this.label,
    this.keywordWeight,
    this.tagWeight,
    this.semanticWeight,
  );

  final String label;
  final double keywordWeight;
  final double tagWeight;
  final double semanticWeight;
}
