import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/nutrition/application/nutrition_math.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 把一道菜/一条供应记成一餐（docs/21 §5.3 `cta-add-meal-<n>`）。
///
/// **单位与快照**（docs/67 §4.2、§4.3）：
/// * 菜品 id 就是食堂供应 id（菜单页的候选来自 `supplyDishCandidates`）——
///   这里先按供应解析，用 `NutritionMath.fromSupply` 换算，并写全快照：
///   `sourceType = menu_item`、`sourceId/supplyId = 供应`、`servings`、
///   `servingGrams`、`nutritionRevisionId`；
/// * 调用方给了克数 ⇒ 按**明确克数**记（`servings = null`），不再乘份数；
/// * 份量未知 ⇒ 抛 [ServingGramsUnknown]（要求填本次实际克数），
///   **绝不补 100g**；
/// * 没有供应（纯旧菜品库调用）⇒ 走 [NutritionMath.fromLegacyDish]，
///   同样要求可信每份克数。
///
/// **日期口径**：写入日期由调用方给（页面当前选中的日期），不由本类取
/// `now`——用户在翻看上周时点「加入」，那笔记录必须落到他正在看的那天。
final class AddDishToMeal {
  const AddDishToMeal({
    required this.mealRepository,
    required this.clock,
    this.supplyCatalog,
  });

  final MealRepository mealRepository;
  final AppClock clock;

  /// 供应读取口（docs/67 §6.4）。null = 未接线：只走旧菜品路径（只读兼容）。
  final SupplyCatalogRepository? supplyCatalog;

  /// 记入 [localDate] 的 [dish.mealSlot] 餐次；给了 [slotOverride] 就用
  /// 调用方指定的餐次（用户刚说的是哪一餐，比库里记的餐次更可信）。
  ///
  /// 返回新建的 meal id（调用方据此提示/跳转）。
  Future<String> run({
    required DishRecord dish,
    required String localDate,
    MealSlot? slotOverride,
    double? grams,
  }) async {
    final slot = slotOverride ?? MealSlot.fromStoredValue(dish.mealSlot);
    final supply = await supplyCatalog?.getById(dish.id);

    if (supply != null) {
      if (!supply.isAnalyzable) {
        throw NutritionIncomplete(supply.displayName);
      }
      final draft = grams == null
          ? NutritionMath.fromSupply(
              supplyId: supply.id,
              displayName: supply.displayName,
              kcalPer100g: supply.kcalPer100g!,
              proteinPer100g: supply.proteinPer100g!,
              carbsPer100g: supply.carbsPer100g!,
              fatPer100g: supply.fatPer100g!,
              servings: 1,
              servingGrams: supply.servingGrams,
              foodId: supply.foodId,
              revisionId: supply.revisionId,
              servingGramsStatus: supply.servingGramsStatus,
            )
          : NutritionMath.fromMasterAtGrams(
              foodId: supply.foodId ?? '',
              name: supply.displayName,
              kcalPer100g: supply.kcalPer100g!,
              proteinPer100g: supply.proteinPer100g!,
              carbsPer100g: supply.carbsPer100g!,
              fatPer100g: supply.fatPer100g!,
              grams: grams,
              revisionId: supply.revisionId,
              sourceType: 'menu_item',
              sourceId: supply.id,
              supplyId: supply.id,
              servingGrams: supply.servingGrams,
            );
      return mealRepository.create(
        MealDraft(localDate: localDate, slot: slot, items: [draft]),
        source: 'menu_item',
      );
    }

    // 旧菜品库（只读兼容）：份量不可信就不能按克解释，要求补全。
    final draft = NutritionMath.fromLegacyDish(
      dish,
      grams ?? dish.servingGrams ?? 0,
    );
    return mealRepository.create(
      MealDraft(localDate: localDate, slot: slot, items: [draft]),
      source: 'dish_library',
    );
  }
}
