import 'package:localfit_ai/features/nutrition/domain/food_category.dart';

final class FoodRecord {
  const FoodRecord({
    required this.id,
    required this.name,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.isUserCreated,
    this.brand,
    this.defaultServingGrams,
    this.category,
  });

  final String id;
  final String name;
  final String? brand;
  final double? defaultServingGrams;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final bool isUserCreated;

  /// 种类（docs/31 S5 需求 51/53）：落库为枚举 id，读出时经
  /// [FoodCategory.tryFromId] 反查；未知 id / 从未回填的行是 null。
  final FoodCategory? category;
  // 过敏原 / 饮食标签的 `constraintFacts` 字段随 schema 22 删除
  // （docs/31 S2，需求 50）。食物侧不再声明任何过敏事实。
}

final class NewFood {
  const NewFood({
    required this.name,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.brand,
    this.defaultServingGrams,
    this.category,
    this.aliases,
  });

  final String name;
  final String? brand;
  final double? defaultServingGrams;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;

  /// 种类：null = 调用方不知道（AI 草稿 / 扫描候选），落库留空——
  /// 不替用户猜「其他」（猜错没法从数据上分辨）。
  final FoodCategory? category;

  /// 别名（ADR-037）：null = **不动**（AI 改营养、扫描候选这类调用不碰别名）；
  /// `[]` = 清空（编辑弹层提交空列表的语义）；非空 = 用这批替换。
  final List<String>? aliases;
}
