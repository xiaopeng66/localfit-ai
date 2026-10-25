import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

final class MealIntakeComparisonResult {
  const MealIntakeComparisonResult({
    required this.items,
    required this.warnings,
  });

  final List<MealItemDraft> items;
  final List<String> warnings;
}

abstract final class MealIntakeComparison {
  static MealIntakeComparisonResult compare({
    required List<MealItemDraft> before,
    required List<MealItemDraft> leftover,
  }) {
    final unmatchedLeftovers = List<MealItemDraft>.of(leftover);
    final items = <MealItemDraft>[];
    final warnings = <String>[];

    for (final beforeItem in before) {
      final leftoverIndex = unmatchedLeftovers.indexWhere(
        (leftoverItem) => _matches(beforeItem, leftoverItem),
      );
      if (leftoverIndex == -1) {
        items.add(beforeItem);
        continue;
      }

      final leftoverItem = unmatchedLeftovers.removeAt(leftoverIndex);
      final netGrams = beforeItem.grams - leftoverItem.grams;
      if (netGrams <= 0) {
        if (leftoverItem.grams > beforeItem.grams) {
          warnings.add('${beforeItem.foodName}的剩余量超过餐前量，净摄入按 0 克计算。');
        }
        continue;
      }

      final factor = netGrams / beforeItem.grams;
      items.add(
        MealItemDraft(
          foodId: beforeItem.foodId,
          foodName: beforeItem.foodName,
          grams: netGrams,
          nutrition: NutritionValues(
            kcal: beforeItem.nutrition.kcal * factor,
            proteinGrams: beforeItem.nutrition.proteinGrams * factor,
            carbsGrams: beforeItem.nutrition.carbsGrams * factor,
            fatGrams: beforeItem.nutrition.fatGrams * factor,
          ),
        ),
      );
    }

    return MealIntakeComparisonResult(items: items, warnings: warnings);
  }

  static bool _matches(MealItemDraft before, MealItemDraft leftover) {
    final beforeId = before.foodId;
    final leftoverId = leftover.foodId;
    if (beforeId != null && leftoverId != null) {
      return beforeId == leftoverId;
    }
    return _normalizedName(before.foodName) ==
        _normalizedName(leftover.foodName);
  }

  static String _normalizedName(String value) => value.trim().toLowerCase();
}
