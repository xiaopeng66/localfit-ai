/// 记忆注入的 query-aware 选择（docs/39 §6.4 / docs/41 §5）：
/// 相关性门控 + MMR + 三档预算 + 置顶/重要性/近期排序。
///
/// **没有向量也能工作**：相关性 = 与当前消息的 bigram 重叠（关键词路）。
/// 门控条件是「所有候选与消息的最大相关度 < 阈值」⇒ 只注入置顶 + 高重要性，
/// 不硬塞噪声。向量可用时把 [MemoryRelevanceScorer] 换成语义实现即可
/// （接口不变）。
library;

import 'dart:math' as math;

import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/retrieval/application/ranking.dart';
import 'package:localfit_ai/features/retrieval/domain/query_understanding.dart';

/// 语义路的相关性门控（docs/39 §6.4 的 `max cosine < 0.35`）。
///
/// 与 [kMemoryRelevanceGate] 分开：那个数字是**关键词路**的「完全无关」
/// 近似（bigram 重叠率），语义路的 cosine 是另一种量纲，用一个阈值硬套
/// 会让门控在两路之间松紧不一。
const double kMemoryVectorGate = 0.35;

/// 相关度打分器接口（默认关键词实现；向量可用时换成语义实现）。
abstract class MemoryRelevanceScorer {
  const MemoryRelevanceScorer();

  /// 返回 0–1 的相关度。
  double score(AiMemory memory, UnderstoodQuery query);

  /// 门控阈值：小于它就认为「与所有记忆都不相关」。
  double get gate => kMemoryRelevanceGate;
}

/// 关键词相关度：消息 bigram 与记忆文本/标签的重叠率。
final class KeywordMemoryScorer extends MemoryRelevanceScorer {
  const KeywordMemoryScorer();

  @override
  double score(AiMemory memory, UnderstoodQuery query) {
    final queryGrams = <String>{
      ...bigramsOf(query.original),
      for (final keyword in query.expanded) ...bigramsOf(keyword),
    };
    if (queryGrams.isEmpty) return 0;
    final memoryGrams = <String>{
      ...bigramsOf(memory.text),
      for (final tag in memory.tags) ...bigramsOf(tag),
    };
    if (memoryGrams.isEmpty) return 0;
    final hits = queryGrams.intersection(memoryGrams).length;
    return hits / math.max(queryGrams.length, 1);
  }
}

/// 语义相关度：与当前消息的余弦相似度（两侧都已 L2 归一）。
///
/// 负余弦按 0 处理（方向相反 = 不相关，不是「负相关」）。
final class VectorMemoryScorer extends MemoryRelevanceScorer {
  const VectorMemoryScorer({required this.queryVector, required this.vectors});

  final List<double> queryVector;
  final Map<String, List<double>> vectors;

  @override
  double get gate => kMemoryVectorGate;

  @override
  double score(AiMemory memory, UnderstoodQuery query) {
    final vector = vectors[memory.id];
    if (vector == null) return 0;
    final n = math.min(queryVector.length, vector.length);
    var dot = 0.0;
    for (var i = 0; i < n; i++) {
      dot += queryVector[i] * vector[i];
    }
    return dot < 0 ? 0 : dot;
  }
}

/// 一次记忆选择的结果（含调试信息与 D11 的注入 id）。
final class MemorySelection {
  const MemorySelection({
    required this.memories,
    required this.injectedIds,
    required this.charCount,
    required this.gated,
    required this.maxRelevance,
  });

  final List<AiMemory> memories;

  /// 本轮注入的记忆 id（对话气泡「本轮参考了 N 条记忆」用）。
  final List<String> injectedIds;
  final int charCount;

  /// 是否触发了相关性门控（只注入置顶 + 高重要性）。
  final bool gated;
  final double maxRelevance;
}

/// 相关性门控阈值（docs/39 §6.4：max cosine < 0.35 关闭语义路；
/// 关键词实现下用同一数字作为「完全无关」的近似）。
const double kMemoryRelevanceGate = 0.15;

/// 高重要性的兜底门槛（门控触发时仍注入 ≥ 此值的条目）。
const int kMemoryHighImportance = 80;

/// 门控触发时，**领域兜底**最多注入几条。
///
/// 【为什么需要领域兜底（2026-10-24）】原实现门控时只留置顶 + 高重要性
/// （≥80），而记忆默认 importance 是 50 —— 于是「用户存了口味偏好和忌口、
/// 问『今天吃什么』」时字面零重叠 ⇒ 分数 0 ⇒ 门控 ⇒ **一条都注入不进去**。
///
/// 这是判据错误：**记忆的价值恰恰在于用户不会重复说**。要求这句话与记忆
/// 字面相关才能想起来，等于要求用户每次复述一遍。
///
/// 但也不能反过来永远全量注入（那是噪音，会稀释注意力）。所以门控触发时
/// 按**这句话的意图领域**兜底：问吃的就带出饮食域记忆，问训练就带训练域。
const int kMemoryGatedDomainFallback = 4;

/// 这句话的意图领域（按关键词粗判；判不出返回空集 = 不做领域兜底）。
///
/// 刻意用**窄词表**：宁可判不出（退回原有的置顶兜底），也不要乱归类
/// 把无关记忆塞给用户。
Set<AiMemoryDomain> memoryDomainsInQuery(UnderstoodQuery query) {
  final text = query.original;
  if (text.trim().isEmpty) return const {};
  final out = <AiMemoryDomain>{};
  bool any(List<String> words) => words.any(text.contains);

  if (any(const [
    '吃',
    '喝',
    '餐',
    '饭',
    '菜',
    '食',
    '口味',
    '忌口',
    '过敏',
    '营养',
    '卡路里',
    '热量',
    '蛋白',
    '碳水',
    '脂肪',
    '减脂',
    '增肌',
    '早餐',
    '午餐',
    '晚餐',
    '加餐',
    '夜宵',
    '零食',
    '外卖',
    '食堂',
    '菜单',
  ])) {
    out.add(AiMemoryDomain.nutrition);
  }
  if (any(const [
    '练',
    '训练',
    '健身',
    '运动',
    '深蹲',
    '硬拉',
    '卧推',
    '跑步',
    '有氧',
    '力量',
    '组数',
    '次数',
    '器械',
    '杠铃',
    '哑铃',
    '肌肉',
    '动作',
    '计划',
  ])) {
    out.add(AiMemoryDomain.training);
  }
  if (any(const ['睡', '作息', '起床', '熬夜', '几点', '早睡', '午休'])) {
    out.add(AiMemoryDomain.schedule);
  }
  // 提到食堂/菜单同时也算食堂域（记忆里可能记的是「常去哪个窗口」）。
  if (any(const ['食堂', '窗口', '几楼', '餐厅'])) {
    out.add(AiMemoryDomain.canteen);
  }
  return out;
}

/// 选出本轮要注入的记忆。
///
/// 排序：置顶 > 相关度 > 重要性 > 近期（同 RRF 之后的 boost 语义）。
MemorySelection selectMemoriesForInjection({
  required List<AiMemory> memories,
  required String userMessage,
  MemoryBudget budget = MemoryBudget.standard,
  MemoryRelevanceScorer scorer = const KeywordMemoryScorer(),
  double lambda = 0.7,

  /// 会话级临时记忆（G20）：只在本次对话生效，排最前、不落库。
  List<AiMemory> sessionMemories = const [],
}) {
  final active = [
    // 临时记忆优先（它们描述的是"当前处境"，比长期偏好更该被模型看见）。
    for (final memory in sessionMemories)
      if (memory.isActive) memory,
    for (final memory in memories)
      if (memory.isActive && !memory.isSuperseded) memory,
  ];
  if (active.isEmpty) {
    return const MemorySelection(
      memories: [],
      injectedIds: [],
      charCount: 0,
      gated: false,
      maxRelevance: 0,
    );
  }
  final query = understandQuery(userMessage);
  final relevance = {
    for (final memory in active) memory.id: scorer.score(memory, query),
  };
  final maxRelevance = relevance.values.fold<double>(0, math.max);
  final gated = maxRelevance < scorer.gate && query.original.isNotEmpty;

  // 候选集：门控时留「置顶 + 高重要性 + **领域相符**」；否则全量按相关度排序。
  //
  // 2026-10-24：加上领域兜底。原实现只有前两类，而默认 importance=50，
  // 等于「字面没重叠就一条都不给」——记忆系统实际不工作（实测：问
  // 「今天吃什么」时口味偏好与忌口 0 条注入）。
  final queryDomains = gated
      ? memoryDomainsInQuery(query)
      : const <AiMemoryDomain>{};
  final candidates = gated
      ? _gatedCandidates(active, queryDomains, relevance)
      : [...active];
  if (gated && candidates.isEmpty) {
    return const MemorySelection(
      memories: [],
      injectedIds: [],
      charCount: 0,
      gated: true,
      maxRelevance: 0,
    );
  }

  // 排序：先按（置顶, 相关度档, 重要性, 近期）形成名次表，再用 RRF 融合
  // ——与检索层同一套融合语义，调试面板能解释「为什么是这几条」。
  final pinnedRanking = [
    for (final memory
        in (candidates.toList()..sort((a, b) {
          final byPinned = (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0);
          if (byPinned != 0) return byPinned;
          return b.updatedAt.compareTo(a.updatedAt);
        })))
      memory.id,
  ];
  final relevanceRanking = [
    for (final memory
        in (candidates.toList()..sort(
          (a, b) => (relevance[b.id] ?? 0).compareTo(relevance[a.id] ?? 0),
        )))
      memory.id,
  ];
  final importanceRanking = [
    for (final memory
        in (candidates.toList()
          ..sort((a, b) => b.importance.compareTo(a.importance))))
      memory.id,
  ];
  final fused = reciprocalRankFusion({
    if (gated)
      'pinned': pinnedRanking
    else ...{
      'pinned': pinnedRanking,
      'relevance': relevanceRanking,
      'importance': importanceRanking,
    },
  }, limit: candidates.length);

  // MMR 去近义冗余（没有向量时用文本重叠）。
  final byId = {for (final memory in candidates) memory.id: memory};
  final ordered = maximalMarginalRelevance(
    candidates: fused,
    similarity: (a, b) =>
        textOverlapSimilarity(byId[a]?.text ?? '', byId[b]?.text ?? ''),
    limit: budget.maxItems,
    lambda: lambda,
  );

  final selected = <AiMemory>[];
  var chars = 0;
  for (final id in ordered) {
    final memory = byId[id];
    if (memory == null) continue;
    final line = _line(memory);
    if (chars + line.length > budget.maxChars) break;
    selected.add(memory);
    chars += line.length + 1;
  }
  return MemorySelection(
    memories: selected,
    injectedIds: [for (final memory in selected) memory.id],
    charCount: chars,
    gated: gated,
    maxRelevance: maxRelevance,
  );
}

/// 门控触发时的候选集：置顶 + 高重要性 + **领域兜底（有上限）**。
///
/// 领域兜底**按重要性/近期排序后截断**到 [kMemoryGatedDomainFallback] 条：
/// 用户存了 50 条饮食记忆时，不能因为「这句话在问吃的」就全塞进去。
/// 领域兜底的排序：**先看有没有沾边，再看重要性**。
///
/// 2026-10-24 实测（`memory_recall_effectiveness_test` 场景 6）：只用
/// 「重要性 + 近期」排序时，30 条同等 importance 的噪音会把真正相关的
/// 那条挤掉（兜底只取 4 条）。所以先按**相关度**分档，再按重要性、近期：
/// 字面沾边的那条（哪怕分数只有 0.05）永远排在 30 条零相关之前。
List<AiMemory> _gatedCandidates(
  List<AiMemory> active,
  Set<AiMemoryDomain> queryDomains,
  Map<String, double> relevance,
) {
  final always = <AiMemory>[];
  final domainMatched = <AiMemory>[];
  for (final memory in active) {
    if (memory.pinned || memory.importance >= kMemoryHighImportance) {
      always.add(memory);
    } else if (queryDomains.contains(memory.domain)) {
      domainMatched.add(memory);
    }
  }
  domainMatched.sort((a, b) {
    // ① 字面沾边（bigram 命中）优先——有就是有，没有就是 0。
    final byRelevance = (relevance[b.id] ?? 0).compareTo(relevance[a.id] ?? 0);
    if (byRelevance != 0) return byRelevance;
    // ② **领域信号强度**：记忆文本命中本域词表越多，越可能是这条问题
    //    真正想要的（「我喜欢清淡口味」命中 2 个饮食词 vs 「这是第 0 条
    //    无关小事」命中 0 个）。
    //
    //    2026-10-24 实测：只按相关度+重要性排时，30 条同等 importance
    //    的噪音把真正那条挤出兜底名额（兜底只取 4 条）。弱相关信号必须
    //    参与排序，否则「有相关记忆」与「一堆无关记忆」无法区分。
    final bySignal = _domainSignal(b).compareTo(_domainSignal(a));
    if (bySignal != 0) return bySignal;
    final byImportance = b.importance.compareTo(a.importance);
    if (byImportance != 0) return byImportance;
    return b.updatedAt.compareTo(a.updatedAt);
  });
  return [...always, ...domainMatched.take(kMemoryGatedDomainFallback)];
}

/// 一条记忆「像不像本域内容」的弱信号：文本 + 标签命中本域词表的次数。
///
/// 只用于**同域内的排序**（不参与门控判定），所以不需要精确——它要回答的
/// 只是「这条和其它条比，谁更像本域的东西」。
int _domainSignal(AiMemory memory) {
  final haystack = '${memory.text} ${memory.tags.join(' ')}';
  final words = _domainLexicon[memory.domain];
  if (words == null) return 0;
  var hits = 0;
  for (final word in words) {
    if (haystack.contains(word)) hits++;
  }
  return hits;
}

/// 各领域的高频词（**只用于同域排序的弱信号**，不用于判定相关性）。
const Map<AiMemoryDomain, List<String>> _domainLexicon = {
  AiMemoryDomain.nutrition: [
    '吃',
    '喝',
    '饭',
    '菜',
    '食',
    '口味',
    '忌口',
    '过敏',
    '营养',
    '热量',
    '蛋白',
    '碳水',
    '脂肪',
    '餐',
    '清淡',
    '辣',
    '甜',
    '咸',
    '油',
    '素',
  ],
  AiMemoryDomain.training: [
    '练',
    '训练',
    '健身',
    '运动',
    '深蹲',
    '硬拉',
    '卧推',
    '跑',
    '有氧',
    '力量',
    '组',
    '次数',
    '器械',
    '肌肉',
    '动作',
    '计划',
    '器械',
  ],
  AiMemoryDomain.schedule: ['睡', '作息', '起床', '熬夜', '早睡', '午休', '点'],
  AiMemoryDomain.canteen: ['食堂', '窗口', '几楼', '餐厅', '档口'],
  AiMemoryDomain.general: [],
};

String _line(AiMemory memory) =>
    '- [${memory.kind.label}] ${memory.text}（${memory.domain.label}）';
