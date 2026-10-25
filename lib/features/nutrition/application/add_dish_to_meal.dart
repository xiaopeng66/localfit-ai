import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 把菜品库的一道菜记成一餐（docs/21 §5.3 `cta-add-meal-<n>`）。
///
/// 两条容易做错的边界：
///
///  1. **份量未知**。`DishLibrary` 的营养是「每份」口径，但表里没有份量列
///     ——所以这里记一笔 `grams = 0` 的条目？不行：`MealRepository._validate`
///     会拒（且 0g 的条目在餐卡上显示成「0g」是明确的错）。做法是把克数记为
///     100 并把营养按整份填入 `nutrition`——条目营养是**独立存储**的
///     （`MealItemDraft.nutrition` 与 grams 解耦），所以克数只用于份量展示。
///     这里如实标 `100g / 整份`：不假装知道这盘菜有多少克。
///
///  2. **日期口径**。写入日期由调用方给（页面当前选中的日期），不由本类取
///     `now`——用户在翻看上周时点「加入」，那笔记录必须落到他正在看的那天。
final class AddDishToMeal {
  const AddDishToMeal({required this.mealRepository, required this.clock});

  final MealRepository mealRepository;
  final AppClock clock;

  /// 份量未知时的兜底克数（`basisAssumed` 的同一口径）。
  static const double assumedServingGrams = 100;

  /// 记入 [localDate] 的 [dish.mealSlot] 餐次；给了 [slotOverride] 就用
  /// 调用方指定的餐次（今日页「记录晚餐」→ 按菜品记录：用户刚说的是哪一餐，
  /// 比菜品库里记的餐次更可信）。
  ///
  /// **份量口径（schema 28）**：`dish.servingGrams` 是「一份」的克数，
  /// 条目营养按 `grams / servingGrams` 缩放——不再固定 100 克、也不再
  /// 假设「一份 = 100g」。份量未知（历史行 `basisAssumed`）时按 100g
  /// 记、并在备注里写明「按 100g 估算」。
  ///
  /// 返回新建的 meal id（调用方据此提示/跳转）。
  Future<String> run({
    required DishRecord dish,
    required String localDate,
    MealSlot? slotOverride,
    double? grams,
  }) {
    final servingGrams = dish.servingGrams ?? assumedServingGrams;
    final recordedGrams = grams ?? servingGrams;
    final scale = servingGrams <= 0 ? 1.0 : recordedGrams / servingGrams;
    return mealRepository.create(
      MealDraft(
        localDate: localDate,
        slot: slotOverride ?? MealSlot.fromStoredValue(dish.mealSlot),
        items: [
          MealItemDraft(
            foodName: dish.name,
            grams: recordedGrams,
            // 每份值 × (克数 / 一份克数)：唯一事实源仍是 per100g，见
            // `DishRecord.kcalPer100g`。
            nutrition: NutritionValues(
              kcal: dish.kcal * scale,
              proteinGrams: dish.proteinG * scale,
              carbsGrams: dish.carbsG * scale,
              fatGrams: dish.fatG * scale,
            ),
            sourceType: 'dish',
            sourceId: dish.id,
          ),
        ],
        notes: _noteFor(dish),
      ),
      source: 'dish_library',
    );
  }

  /// 备注里带上证据等级与来源，便于事后核查这笔记录从哪来；份量是假设值
  /// 时明写「按 100g 估算」（docs/41 D8：不假装知道份量）。
  static String _noteFor(DishRecord dish) {
    final window = dish.servingWindow;
    final parts = [
      '来自菜品库',
      if (window != null) '供应时段 $window',
      '来源 ${dish.source}',
      if (dish.basisAssumed) '按 100g 估算',
    ];
    return parts.join(' · ');
  }
}
