import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 记餐营养的**唯一换算入口**（docs/67 §4.1）。
///
/// ```text
/// 摄入营养 = 每100g营养 × 实际食用克数 ÷ 100
/// 实际食用克数 = 份数 × 该供应每份克数
/// ```
///
/// 任何仍然自己写 `kcal * grams / 100` 的地方都会和这里漂移——所以手动编辑器、
/// 食堂供应记餐、AI `meal.create`、推荐应用和历史餐编辑全部走这里。
/// 边界（未知/估计份量、旧口径）在这一层拒绝，而不是让每个调用方各判一次。
final class NutritionMath {
  const NutritionMath._();

  /// 主食物 + 明确克数。
  static MealItemDraft fromFood(FoodRecord food, double grams) =>
      fromMasterAtGrams(
        foodId: food.id,
        name: food.name,
        kcalPer100g: food.kcalPer100g,
        proteinPer100g: food.proteinPer100g,
        carbsPer100g: food.carbsPer100g,
        fatPer100g: food.fatPer100g,
        grams: grams,
      );

  /// 主食物（每 100g 事实）+ 明确克数。
  ///
  /// [revisionId] 是当时的生效修订；写进快照后，主库以后改营养也不重算这一餐。
  static MealItemDraft fromMasterAtGrams({
    required String foodId,
    required String name,
    required double kcalPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    required double grams,
    String? revisionId,
    String sourceType = 'food',
    String? sourceId,
    String? supplyId,
    double? servings,
    double? servingGrams,
  }) {
    _requireGrams(grams);
    _requireComplete(
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
      name: name,
    );
    return MealItemDraft(
      foodId: foodId,
      foodName: name,
      grams: grams,
      nutrition: NutritionValues(
        kcal: nutritionForGrams(per100g: kcalPer100g, grams: grams),
        proteinGrams: nutritionForGrams(per100g: proteinPer100g, grams: grams),
        carbsGrams: nutritionForGrams(per100g: carbsPer100g, grams: grams),
        fatGrams: nutritionForGrams(per100g: fatPer100g, grams: grams),
      ),
      sourceType: sourceType,
      sourceId: sourceId ?? foodId,
      nutritionRevisionId: revisionId,
      supplyId: supplyId,
      servings: servings,
      servingGrams: servingGrams,
    );
  }

  /// 食堂供应 + 份数：克数由**该供应自己的**每份克数解析，不借用别的窗口。
  ///
  /// 份量未知时抛 [ServingGramsUnknown]——调用方要么让用户填本次实际克数
  /// （改用 [fromMasterAtGrams]），要么先补供应的每份克数。绝不默认 100g。
  static MealItemDraft fromSupply({
    required String supplyId,
    required String displayName,
    required double kcalPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    required double servings,
    required double? servingGrams,
    String? foodId,
    String? revisionId,
    ServingGramsStatus servingGramsStatus = ServingGramsStatus.known,
  }) {
    if (!servings.isFinite || servings <= 0) {
      throw ArgumentError.value(servings, 'servings', '份数必须是有限正数');
    }
    if (servingGramsStatus == ServingGramsStatus.unknown ||
        servingGrams == null) {
      throw ServingGramsUnknown(displayName);
    }
    if (!servingGrams.isFinite || servingGrams <= 0) {
      throw ServingGramsUnknown(displayName);
    }
    final grams = servings * servingGrams;
    _requireGrams(grams);
    _requireComplete(
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
      name: displayName,
    );
    return MealItemDraft(
      foodId: foodId,
      foodName: displayName,
      grams: grams,
      nutrition: NutritionValues(
        kcal: nutritionForGrams(per100g: kcalPer100g, grams: grams),
        proteinGrams: nutritionForGrams(per100g: proteinPer100g, grams: grams),
        carbsGrams: nutritionForGrams(per100g: carbsPer100g, grams: grams),
        fatGrams: nutritionForGrams(per100g: fatPer100g, grams: grams),
      ),
      sourceType: 'menu_item',
      sourceId: supplyId,
      supplyId: supplyId,
      nutritionRevisionId: revisionId,
      servings: servings,
      servingGrams: servingGrams,
    );
  }

  /// 旧菜品库（每份口径）——**只在每份克数可信时**才允许按克换算。
  ///
  /// 旧每份营养不是每 100g；份量未知/假设的行没有可靠克数解释，必须去
  /// 补全或重新分析，不能拿 100g 顶替（A11）。
  static MealItemDraft fromLegacyDish(DishRecord dish, double grams) {
    final servingGrams = dish.servingGrams;
    if (dish.basisAssumed ||
        servingGrams == null ||
        !servingGrams.isFinite ||
        servingGrams <= 0) {
      throw ServingGramsUnknown(dish.name);
    }
    _requireGrams(grams);
    return MealItemDraft(
      foodName: dish.name,
      grams: grams,
      nutrition: dish.nutritionForGrams(grams),
      sourceType: 'dish',
      sourceId: dish.id,
      servings: null,
      servingGrams: servingGrams,
    );
  }

  /// 解析"份数 / 克数"二选一输入，得到实际克数。
  ///
  /// 两个都没给 → 返回 null（界面要求用户补一个，不默认 100g）。
  static double? resolveGrams({
    double? servings,
    double? grams,
    required double? servingGrams,
  }) {
    if (grams != null && grams.isFinite && grams > 0) return grams;
    if (servings != null && servings.isFinite && servings > 0) {
      if (servingGrams == null || !servingGrams.isFinite || servingGrams <= 0) {
        return null;
      }
      return servings * servingGrams;
    }
    return null;
  }

  static void _requireGrams(double grams) {
    if (!grams.isFinite || grams <= 0) {
      throw ArgumentError.value(grams, 'grams', '克数必须是有限正数');
    }
    if (grams > NutritionLimits.maxGrams) {
      throw ArgumentError.value(grams, 'grams', '克数超出上限');
    }
  }

  static void _requireComplete({
    required double kcalPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    required String name,
  }) {
    if (!isCompleteNutrition(
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
    )) {
      throw NutritionIncomplete(name);
    }
  }
}

/// 份量未知——按份记餐被拦截。**这不是可以吞掉的异常**：它是"必须问用户"
/// 的信号（填本次实际克数，或先补该供应的每份克数）。
final class ServingGramsUnknown implements FormatException {
  const ServingGramsUnknown(this.name);

  final String name;

  String get userMessage =>
      '「$name」还没有可信的每份克数。请填写这次实际吃了多少克，'
      '或先补上这道菜一份多少克。';

  /// 实现 [FormatException]：这些是"用户可读的输入/数据不满足契约"，
  /// 让既有的 `on FormatException` 分支统一上屏，不再每个调用点各判一次。
  @override
  String get message => userMessage;

  @override
  Object? get source => null;

  @override
  int? get offset => null;

  @override
  String toString() => userMessage;
}

/// 营养四项不全——不能参与计算，也不填零。
final class NutritionIncomplete implements FormatException {
  const NutritionIncomplete(this.name);

  final String name;

  String get userMessage => '「$name」的营养还不完整，先补齐或重新分析。';

  @override
  String get message => userMessage;

  @override
  Object? get source => null;

  @override
  int? get offset => null;

  @override
  String toString() => userMessage;
}
