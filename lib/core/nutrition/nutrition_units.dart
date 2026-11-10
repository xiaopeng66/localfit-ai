/// 营养单位与口径的**唯一词表**（docs/67 §3、§4）。
///
/// 这一段放在 `lib/core` 而不是某个 feature 里，是因为数据层（迁移与备份
/// 恢复）、营养域和食堂域都要说同一套口径词；任何一处自己另造字符串常量，
/// 单位就会在两套代码里悄悄漂移。
library;

/// 一组营养数值记录时用的口径。
enum NutritionBasis {
  /// 每 100g（主库唯一口径）。
  per100g('per100g'),

  /// 每一份（旧菜品库/食堂历史口径）。
  perServing('perServing');

  const NutritionBasis(this.storedValue);

  final String storedValue;

  static NutritionBasis? tryParse(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    for (final basis in NutritionBasis.values) {
      if (basis.storedValue == value) return basis;
    }
    return null;
  }
}

/// 食堂供应"每份多少克"的可信度。
///
/// 只存了一个数字不等于知道份量：历史行回填的 100g 属于 [unknown] 的前身，
/// 从来没有称过的数字属于 [estimated]。界面必须把这三档分开说。
enum ServingGramsStatus {
  /// 有可信依据（称重/用户本次填写/标签）。
  known('known'),

  /// 有数字但只是估计（AI 估算、历史未验证数字）。
  estimated('estimated'),

  /// 没有数字。
  unknown('unknown');

  const ServingGramsStatus(this.storedValue);

  final String storedValue;

  static ServingGramsStatus fromStored(String? raw) {
    for (final status in ServingGramsStatus.values) {
      if (status.storedValue == raw) return status;
    }
    return ServingGramsStatus.unknown;
  }
}

/// 每份克数的来源。
enum ServingGramsSource {
  /// 现场称重。
  weighed('weighed'),

  /// 用户在本次流程里填写。
  userInput('user_input'),

  /// 包装/菜单标签。
  label('label'),

  /// AI 估算。
  aiEstimate('ai_estimate'),

  /// 历史库里的数字（schema 31 之前写入，没有可信依据）。
  legacyUnverified('legacy_unverified'),

  /// 历史库里的未知份量（schema 28 曾用 100g 占位）。
  legacyUnknown('legacy_unknown');

  const ServingGramsSource(this.storedValue);

  final String storedValue;

  static ServingGramsSource fromStored(String? raw) {
    for (final source in ServingGramsSource.values) {
      if (source.storedValue == raw) return source;
    }
    return ServingGramsSource.legacyUnknown;
  }

  /// 这一来源是否构成"可信每份重量"（docs/67 §4.1）。
  ///
  /// 只有称重、用户本次填写和标签算可信依据：AI 估算和历史未验证数字都不行。
  /// 这条判定同时供旧数据归一（能不能换算）和自动推荐（能不能按份预算）使用。
  bool get isTrustedBasis =>
      this == ServingGramsSource.weighed ||
      this == ServingGramsSource.userInput ||
      this == ServingGramsSource.label;
}

/// 业务上限（与现有校验保持一致，不靠提示词单独负责）。
abstract final class NutritionLimits {
  /// 单次食用克数上限（`meal.create` 的 items[].grams 同源）。
  static const double maxGrams = 5000;

  /// 每份克数上限。
  static const double maxServingGrams = 2000;

  /// 每 100g 热量上限。
  static const double maxKcalPer100g = 1000;

  /// 每 100g 单一宏量上限。
  static const double maxMacroPer100g = 100;

  /// 份数上限。
  static const double maxServings = 50;
}

/// `营养 = 每100g × 克数 ÷ 100`（docs/67 §4.1 的唯一公式）。
double nutritionForGrams({required double per100g, required double grams}) {
  if (!grams.isFinite || grams <= 0) {
    throw ArgumentError.value(grams, 'grams', '克数必须是有限正数');
  }
  return per100g * grams / 100;
}

/// 每份营养 → 每 100g：`每份 × 100 ÷ 每份克数`。
///
/// **[servingGrams] 必须是可信依据**；调用方负责先判定来源，未知或假设份量
/// 不允许走到这里（docs/67 §4.1、§7.2 E 类）。
double? per100gFromPerServing({
  required double perServing,
  required double? servingGrams,
}) {
  if (servingGrams == null || !servingGrams.isFinite || servingGrams <= 0) {
    return null;
  }
  final value = perServing * 100 / servingGrams;
  return value.isFinite ? value : null;
}

/// 每 100g 营养 → 每份：`每100g × 每份克数 ÷ 100`。
double? perServingFromPer100g({
  required double per100g,
  required double? servingGrams,
}) {
  if (servingGrams == null || !servingGrams.isFinite || servingGrams <= 0) {
    return null;
  }
  final value = per100g * servingGrams / 100;
  return value.isFinite ? value : null;
}

/// 有限且非负。
bool isFiniteNonNegative(double? value) =>
    value != null && value.isFinite && value >= 0;

/// 四项齐全且合法——"可计算营养"的定义。
bool isCompleteNutrition({
  required double? kcalPer100g,
  required double? proteinPer100g,
  required double? carbsPer100g,
  required double? fatPer100g,
}) =>
    isFiniteNonNegative(kcalPer100g) &&
    isFiniteNonNegative(proteinPer100g) &&
    isFiniteNonNegative(carbsPer100g) &&
    isFiniteNonNegative(fatPer100g);

/// 显示层舍入：四舍五入到 [digits] 位小数。计算层保留全精度。
double roundForDisplay(double value, {int digits = 1}) {
  final factor = _pow10(digits);
  return (value * factor).roundToDouble() / factor;
}

double _pow10(int digits) {
  var factor = 1.0;
  for (var i = 0; i < digits; i++) {
    factor *= 10;
  }
  return factor;
}
