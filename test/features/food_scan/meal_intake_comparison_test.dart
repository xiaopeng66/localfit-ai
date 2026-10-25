import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/application/meal_intake_comparison.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

void main() {
  test('subtracts leftover grams and rescales nutrition', () {
    const before = MealItemDraft(
      foodId: 'rice',
      foodName: '米饭',
      grams: 200,
      nutrition: NutritionValues(
        kcal: 232,
        proteinGrams: 4,
        carbsGrams: 40,
        fatGrams: 2,
      ),
    );
    const leftover = MealItemDraft(
      foodId: 'rice',
      foodName: '米饭',
      grams: 50,
      nutrition: NutritionValues(
        kcal: 58,
        proteinGrams: 1,
        carbsGrams: 10,
        fatGrams: 0.5,
      ),
    );

    final result = MealIntakeComparison.compare(
      before: [before],
      leftover: [leftover],
    );

    expect(result.items, hasLength(1));
    expect(result.items.single.foodId, 'rice');
    expect(result.items.single.grams, 150);
    expect(result.items.single.nutrition.kcal, 174);
    expect(result.items.single.nutrition.proteinGrams, 3);
    expect(result.items.single.nutrition.carbsGrams, 30);
    expect(result.items.single.nutrition.fatGrams, 1.5);
  });

  test('keeps before items that are absent from leftover photo', () {
    const rice = MealItemDraft(
      foodId: 'rice',
      foodName: '米饭',
      grams: 180,
      nutrition: NutritionValues(
        kcal: 208.8,
        proteinGrams: 3.6,
        carbsGrams: 36,
        fatGrams: 1.8,
      ),
    );

    final result = MealIntakeComparison.compare(
      before: [rice],
      leftover: const [],
    );

    expect(result.items, [rice]);
    expect(result.warnings, isEmpty);
  });

  test('drops fully uneaten items from net intake', () {
    const item = MealItemDraft(
      foodId: 'rice',
      foodName: '米饭',
      grams: 180,
      nutrition: NutritionValues(
        kcal: 208.8,
        proteinGrams: 3.6,
        carbsGrams: 36,
        fatGrams: 1.8,
      ),
    );

    final result = MealIntakeComparison.compare(
      before: [item],
      leftover: [item],
    );

    expect(result.items, isEmpty);
  });

  test('clamps leftover above before to zero and reports warning', () {
    const before = MealItemDraft(
      foodId: 'rice',
      foodName: '米饭',
      grams: 100,
      nutrition: NutritionValues(
        kcal: 116,
        proteinGrams: 2,
        carbsGrams: 20,
        fatGrams: 1,
      ),
    );
    const leftover = MealItemDraft(
      foodId: 'rice',
      foodName: '米饭',
      grams: 120,
      nutrition: NutritionValues(
        kcal: 139.2,
        proteinGrams: 2.4,
        carbsGrams: 24,
        fatGrams: 1.2,
      ),
    );

    final result = MealIntakeComparison.compare(
      before: [before],
      leftover: [leftover],
    );

    expect(result.items, isEmpty);
    expect(result.warnings.single, contains('剩余量超过餐前量'));
  });

  test('matches items by normalized name when food id is unavailable', () {
    const before = MealItemDraft(
      foodName: '  番茄炒蛋 ',
      grams: 200,
      nutrition: NutritionValues(
        kcal: 300,
        proteinGrams: 20,
        carbsGrams: 10,
        fatGrams: 20,
      ),
    );
    const leftover = MealItemDraft(
      foodName: '番茄炒蛋',
      grams: 80,
      nutrition: NutritionValues(
        kcal: 120,
        proteinGrams: 8,
        carbsGrams: 4,
        fatGrams: 8,
      ),
    );

    final result = MealIntakeComparison.compare(
      before: [before],
      leftover: [leftover],
    );

    expect(result.items.single.grams, 120);
    expect(result.items.single.nutrition.kcal, 180);
  });
}
