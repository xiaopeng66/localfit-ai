import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show NutritionValues;

/// 菜品库 `sourceType` 的取值集合（`DishRecord.sourceType` 的合法值）。
///
/// 单一事实源：写入方（食堂自动同步、AI 建菜、导入）与读取方（来源徽标、
/// 按来源删除）都读这里，避免两处字符串漂移成「写入写了 canteen、删除按
/// menu_item 找」这种静默不匹配。
const String kCanteenSourceType = 'canteen';

/// 菜品库条目（docs/21 §7.2 `DishLibrary`）。
///
/// 「饮食·菜单」页的**唯一主来源**（docs/21 §5.3 数据源裁决）：用户自建
/// （校园三级结构 + AI 营养分析）与 AI 生成（`daily-menu-plan`）两条路径
/// 都写到这里，这样「本周热门」「营养师点评」才有稳定载体。
///
/// 不得把 `MenuItems`（菜单原始条目）直接渲染成菜品卡——那张表的语义是
/// 「菜单上印着的名字」，证据等级低且可能没有营养值。
final class DishRecord {
  const DishRecord({
    required this.id,
    required this.name,
    required this.mealSlot,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.imagePath,
    this.servingWindow,
    this.isHot = false,
    this.fiberG,
    this.sodiumMg,
    this.vitaminDMcg,
    this.comment,
    this.servingGrams,
    this.basisAssumed = false,
    this.sourceType,
    this.sourceId,
    this.sourceUpdatedAt,
    this.userEdited = false,
  });

  final String id;
  final String name;

  /// 本地图片路径；null → 渲染渐变占位（**不伪造菜品照片**，docs/21 §6.1）。
  final String? imagePath;

  /// 早餐 / 午餐 / 晚餐 / 加餐。
  final String mealSlot;

  /// 供应时段（校园窗口语义，如 `06:30-09:30`）；非食堂菜为 null。
  final String? servingWindow;
  final bool isHot;
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// 微量营养素：null = 无数据 → **不渲染该行**（docs/21 §6.2 裁决 10）。
  final double? fiberG;
  final double? sodiumMg;
  final double? vitaminDMcg;

  /// 来源标记（`manual` / `ai_estimate` / …）。
  final String source;

  /// 营养师点评；null/空 → **不渲染该块**（docs/21 §6.1）。
  final String? comment;

  // ── schema 28（docs/40 §2.1）：份量口径与来源 ────────────────────────
  /// 一份多少克；null = 未知。
  final double? servingGrams;

  /// 份量是否为假设值（历史回填 100 的行都是 true → UI 标「按 100g 估算」）。
  final bool basisAssumed;

  /// `canteen` | `food` | `manual` | `imported`。
  final String? sourceType;

  /// menuItemId / foodId（**不加外键**，来源删除后悬空）。
  final String? sourceId;

  /// 来源最后一次营养变更时间（「有更新」提示用）。
  final DateTime? sourceUpdatedAt;

  /// 用户手改过营养/份量：同步只提示、不覆盖。
  final bool userEdited;

  /// 每 100g 热量（由每份值还原；份量未知时按 100g 假设，与
  /// `basisAssumed` 同一口径——「营养只有每 100g 一个事实源」）。
  double get kcalPer100g {
    final grams = servingGrams ?? 100;
    if (grams <= 0) return kcal;
    return kcal / grams * 100;
  }

  /// 按克数换算这一份的热量（docs/40 §2.2 的不变量）。
  double kcalForGrams(double grams) => kcalPer100g * grams / 100;

  final DateTime createdAt;
  final DateTime updatedAt;

  NutritionValues get nutrition => NutritionValues(
    kcal: kcal,
    proteinGrams: proteinG,
    carbsGrams: carbsG,
    fatGrams: fatG,
  );

  /// 该菜占当日目标的比例（0..1）；无目标或目标非正时为 null。
  ///
  /// 返回 null 时进度条**不渲染**：分母不存在时画任何长度都是编事实。
  double? targetProgress(double? dailyTargetKcal) {
    if (dailyTargetKcal == null || dailyTargetKcal <= 0) return null;
    return (kcal / dailyTargetKcal).clamp(0.0, 1.0);
  }
}

/// 菜品库仓储（docs/21 §7.2）。增删改 + 按餐次/热门查询。
final class DishLibraryFilter {
  const DishLibraryFilter({this.mealSlot, this.hotOnly = false});

  final String? mealSlot;
  final bool hotOnly;
}

/// 校验入库前的菜品数值。
///
/// 上限取「每 100g 纯油脂也到不了 900kcal」的物理边界：越界说明填的是
/// 每份/每餐总量而不是每 100g，拒绝而不是猜（与 `dish-nutrition.v1` 同口径）。
void validateDishNutrition({
  required String name,
  required double kcal,
  required double proteinG,
  required double carbsG,
  required double fatG,
  double? fiberG,
  double? sodiumMg,
  double? vitaminDMcg,
}) {
  if (name.trim().isEmpty) {
    throw const FormatException('菜名不能为空。');
  }
  if (!kcal.isFinite || kcal < 0 || kcal > 900) {
    throw const FormatException('热量必须在 0–900 kcal 之间。');
  }
  for (final (label, value) in [
    ('蛋白质', proteinG),
    ('碳水', carbsG),
    ('脂肪', fatG),
  ]) {
    if (!value.isFinite || value < 0 || value > 100) {
      throw FormatException('$label必须在 0–100 g 之间。');
    }
  }
  if (fiberG != null && (!fiberG.isFinite || fiberG < 0 || fiberG > 100)) {
    throw const FormatException('膳食纤维必须在 0–100 g 之间。');
  }
  if (sodiumMg != null &&
      (!sodiumMg.isFinite || sodiumMg < 0 || sodiumMg > 20000)) {
    throw const FormatException('钠必须在 0–20000 mg 之间。');
  }
  if (vitaminDMcg != null &&
      (!vitaminDMcg.isFinite || vitaminDMcg < 0 || vitaminDMcg > 200)) {
    throw const FormatException('维生素 D 必须在 0–200 µg 之间。');
  }
}

/// 校验供应时段（`HH:MM-HH:MM`）；空串按「无时段」处理。
void validateServingWindow(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return;
  final match = RegExp(r'^(\d{2}):(\d{2})-(\d{2}):(\d{2})$').firstMatch(text);
  if (match == null) {
    throw const FormatException('供应时段格式应为 06:30-09:30。');
  }
  int minutes(String hh, String mm) {
    final hour = int.parse(hh);
    final minute = int.parse(mm);
    if (hour > 23 || minute > 59) {
      throw const FormatException('供应时段里的小时或分钟超出范围。');
    }
    return hour * 60 + minute;
  }

  final start = minutes(match.group(1)!, match.group(2)!);
  final end = minutes(match.group(3)!, match.group(4)!);
  if (end <= start) {
    throw const FormatException('供应时段的结束时间必须晚于开始时间。');
  }
}
