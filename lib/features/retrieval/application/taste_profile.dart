/// 个人口味画像（docs/39 §8 / docs/41 P4）：**满 N 餐前不参与排序**。
///
/// 实现口径（无向量时）：近期餐记录里出现过的菜名/标签做**指数衰减**计数，
/// 得到「偏好标签」集合；命中偏好标签的候选加一个**很小的**加成
/// （`applyBoosts` 的 `tasteSimilarity`，最多 +5%），不做硬过滤。
///
/// 为什么不用菜品向量：P0 评测结论是向量不作默认路径（延迟门槛未过）。
/// 本类的输入是「标签」，与向量无关；将来启用向量时换实现即可。
library;

import 'dart:math' as math;

import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 一条历史餐记录的口味输入（从 `MealRecord` 投影，页面/仓储侧构造）。
final class TasteSample {
  const TasteSample({
    required this.dishName,
    required this.eatenAt,
    this.tags = const [],
  });

  final String dishName;
  final DateTime eatenAt;
  final List<String> tags;
}

/// 口味画像结果。
final class TasteProfile {
  const TasteProfile({
    required this.tagWeights,
    required this.sampleCount,
    required this.active,
  });

  /// 标签 → 权重（0–1，归一化后的相对偏好）。
  final Map<String, double> tagWeights;

  /// 参与统计的餐次数。
  final int sampleCount;

  /// 是否已满门槛（false = 冷启动，调用方**不得**据此排序）。
  final bool active;

  /// 命中给定标签/名称的相似度（0–1），供检索 boost 使用。
  double affinityOf({required String name, List<String> tags = const []}) {
    if (!active || tagWeights.isEmpty) return 0;
    var best = 0.0;
    for (final entry in tagWeights.entries) {
      final tag = entry.key;
      if (tags.any((value) => value.contains(tag) || tag.contains(value))) {
        best = math.max(best, entry.value);
      }
      if (name.contains(tag)) best = math.max(best, entry.value * 0.8);
    }
    return best.clamp(0.0, 1.0);
  }
}

/// 冷启动门槛（docs/41 P4「满 N 餐前不参与」）。
const int kTasteWarmupMeals = 10;

/// 衰减半衰期（天）：两周前的饮食对今天的偏好影响减半。
const double kTasteHalfLifeDays = 14;

/// 从历史样本构建画像。
TasteProfile buildTasteProfile({
  required List<TasteSample> samples,
  required DateTime now,
  int warmupMeals = kTasteWarmupMeals,
}) {
  if (samples.length < warmupMeals) {
    return TasteProfile(
      tagWeights: const {},
      sampleCount: samples.length,
      active: false,
    );
  }
  final weights = <String, double>{};
  for (final sample in samples) {
    final days = now.difference(sample.eatenAt).inMinutes / (60 * 24);
    final decay = math.pow(0.5, math.max(days, 0) / kTasteHalfLifeDays);
    for (final tag in sample.tags) {
      weights[tag] = (weights[tag] ?? 0) + 1.0 * decay;
    }
  }
  if (weights.isEmpty) {
    return TasteProfile(
      tagWeights: const {},
      sampleCount: samples.length,
      active: false,
    );
  }
  final maxWeight = weights.values.reduce(math.max);
  final normalized = {
    for (final entry in weights.entries)
      entry.key: maxWeight <= 0 ? 0.0 : entry.value / maxWeight,
  };
  return TasteProfile(
    tagWeights: normalized,
    sampleCount: samples.length,
    active: true,
  );
}

/// 软排除（docs/41 P4 G8）：不喜欢的菜/窗口——**只扣分，不排除**。
///
/// 存储是 `app_settings` 里的 JSON 数组（不新增表；docs/41 §11 没登记
/// 排除表）。值为归一化后的菜名或窗口名。
final class SoftExclusionRules {
  const SoftExclusionRules({
    this.dishNames = const {},
    this.windows = const {},
  });

  static const empty = SoftExclusionRules();

  final Set<String> dishNames;
  final Set<String> windows;

  bool get isEmpty => dishNames.isEmpty && windows.isEmpty;

  /// 命中扣分（×0.5），而不是过滤。
  bool matches({required String name, String? window}) {
    final normalizedName = _normalize(name);
    if (dishNames.any((value) => normalizedName.contains(value))) return true;
    final normalizedWindow = _normalize(window ?? '');
    if (normalizedWindow.isEmpty) return false;
    return windows.any((value) => normalizedWindow.contains(value));
  }

  String encode() =>
      '{"dishes":${_jsonList(dishNames)},"windows":${_jsonList(windows)}}';

  static SoftExclusionRules decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    try {
      final text = raw.trim();
      // 极简解析：避免为一个两键对象引入第二套 JSON 依赖。
      final dishes = _parseList(text, 'dishes');
      final windows = _parseList(text, 'windows');
      return SoftExclusionRules(
        dishNames: {for (final value in dishes) _normalize(value)},
        windows: {for (final value in windows) _normalize(value)},
      );
    } on FormatException {
      return empty;
    }
  }

  static String _jsonList(Set<String> values) =>
      '[${values.map((v) => '"${v.replaceAll('"', r'\"')}"').join(',')}]';

  static List<String> _parseList(String text, String key) {
    final match = RegExp('"$key"\\s*:\\s*\\[([^\\]]*)\\]').firstMatch(text);
    if (match == null) return const [];
    return [
      for (final part in match.group(1)!.split(','))
        if (part.trim().isNotEmpty)
          part.trim().replaceAll(RegExp(r'^"|"$'), '').replaceAll(r'\"', '"'),
    ];
  }
}

String _normalize(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s\u3000]+'), '');

/// `app_settings` 里软排除规则的键。
const String kSoftExclusionKey = 'retrieval_soft_exclusions';

// ── 口味向量（docs/43 B9 / docs/39 §8）────────────────────────────────

/// 参与口味向量计算的最大历史天数（docs/43 B9：近 30 天）。
const int kTasteVectorWindowDays = 30;

/// 口味向量的软 boost 上限（×1.05，与标签画像同量级；**不叠加**）。
const double kTasteVectorBoost = 1.05;

/// 一条菜品向量样本（由餐记录 → 菜品 → 向量投影）。
final class TasteVectorSample {
  const TasteVectorSample({required this.eatenAt, required this.vector});

  final DateTime eatenAt;
  final List<double> vector;
}

/// 口味向量画像（docs/39 §8）：近期吃过菜品向量的指数衰减质心。
///
/// 纪律：
/// * **<10 餐不参与**（冷启动，与标签画像同一门槛）；
/// * 权重 `0.5^(ageDays/14)`（半衰期 14 天）；
/// * 加权平均后 **L2 归一**（与菜品向量同尺度，直接点积即余弦）；
/// * 只用于**软排序**，绝不硬过滤（docs/43 B9）。
final class TasteVectorProfile {
  const TasteVectorProfile({
    required this.vector,
    required this.sampleCount,
    required this.active,
  });

  static const TasteVectorProfile inactive = TasteVectorProfile(
    vector: null,
    sampleCount: 0,
    active: false,
  );

  /// 质心（已 L2 归一）；null = 冷启动/无样本。
  final List<double>? vector;
  final int sampleCount;
  final bool active;

  /// 与菜品向量的余弦（0–1 截断）；不活跃返回 0。
  double affinityOf(List<double>? dishVector) {
    final centroid = vector;
    if (!active || centroid == null || dishVector == null) return 0;
    final n = math.min(centroid.length, dishVector.length);
    var dot = 0.0;
    for (var i = 0; i < n; i++) {
      dot += centroid[i] * dishVector[i];
    }
    return dot.clamp(0.0, 1.0);
  }
}

/// 从餐记录投影样本（docs/43 B9 的输入口径）：
/// **只看近 [windowDays] 天、`sourceType='dish'` 且有 `sourceId` 的条目**。
///
/// 食物库/扫描/手动条目**不算口味**（它们不是「我常点的菜」）；来源菜品已
/// 删除（`dishVectors` 缺失）的条目也跳过——没有向量就没法参与质心。
/// 【`RV4-P3-02` 复核结论：**保留**】生产代码零调用，仅
/// `test/features/retrieval/taste_vector_test.dart` 用它验证向量拼接规则。
/// 保留理由：它是那份测试的输入构造器，删掉会让「口味向量怎么从餐食里长出来」
/// 失去唯一的可执行说明（不是「可能有用的死代码」，是测试夹具的公开入口）。
List<TasteVectorSample> tasteVectorSamplesFromMeals({
  required Iterable<MealRecord> meals,
  required Map<String, List<double>> dishVectors,
  required DateTime now,
  int windowDays = kTasteVectorWindowDays,
}) {
  final out = <TasteVectorSample>[];
  for (final meal in meals) {
    if (now.difference(meal.eatenAt).inDays > windowDays) continue;
    for (final item in meal.items) {
      if (item.sourceType != 'dish') continue;
      final sourceId = item.sourceId;
      if (sourceId == null) continue;
      final vector = dishVectors[sourceId];
      if (vector == null || vector.isEmpty) continue;
      out.add(TasteVectorSample(eatenAt: meal.eatenAt, vector: vector));
    }
  }
  return out;
}

/// 构建口味向量。
///
/// [samples] 只应包含 **近 30 天、来源为 dish** 的餐记录投影（页面/仓储侧
/// 负责筛选：这里不再猜来源，避免把食物库或扫描记录算进「口味」）。
TasteVectorProfile buildTasteVectorProfile({
  required List<TasteVectorSample> samples,
  required DateTime now,
  int warmupMeals = kTasteWarmupMeals,
}) {
  final usable = [
    for (final sample in samples)
      if (sample.vector.isNotEmpty &&
          now.difference(sample.eatenAt).inDays <= kTasteVectorWindowDays)
        sample,
  ];
  if (usable.length < warmupMeals) {
    return TasteVectorProfile(
      vector: null,
      sampleCount: usable.length,
      active: false,
    );
  }
  final dim = usable.first.vector.length;
  final centroid = List<double>.filled(dim, 0.0);
  var totalWeight = 0.0;
  for (final sample in usable) {
    final days = now.difference(sample.eatenAt).inMinutes / (60 * 24);
    final weight = math.pow(0.5, math.max(days, 0) / kTasteHalfLifeDays);
    totalWeight += weight;
    final n = math.min(dim, sample.vector.length);
    for (var i = 0; i < n; i++) {
      centroid[i] += sample.vector[i] * weight;
    }
  }
  if (totalWeight <= 0) {
    return TasteVectorProfile(
      vector: null,
      sampleCount: usable.length,
      active: false,
    );
  }
  for (var i = 0; i < dim; i++) {
    centroid[i] /= totalWeight;
  }
  var sumSq = 0.0;
  for (final value in centroid) {
    sumSq += value * value;
  }
  final norm = math.sqrt(sumSq);
  if (norm <= 1e-9) {
    return TasteVectorProfile(
      vector: null,
      sampleCount: usable.length,
      active: false,
    );
  }
  return TasteVectorProfile(
    vector: [for (final value in centroid) value / norm],
    sampleCount: usable.length,
    active: true,
  );
}
