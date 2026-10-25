import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

void main() {
  const calculator = NutritionTargetCalculator();

  test('calculates a bounded fat-loss target for an adult', () {
    final target = calculator.calculate(
      const NutritionTargetInput(
        age: 30,
        biologicalSex: BiologicalSex.male,
        heightCm: 175,
        weightKg: 75,
        activityLevel: ActivityLevel.moderatelyActive,
        goal: HealthGoal.loseFat,
      ),
    );

    expect(target.bmrKcal, 1699);
    expect(target.tdeeKcal, 2633);
    expect(target.calorieMinKcal, 2126);
    expect(target.calorieMaxKcal, 2350);
    expect(target.proteinMinGrams, 120);
    expect(target.proteinMaxGrams, 150);
    expect(target.calorieMinKcal, lessThan(target.calorieMaxKcal));
    expect(target.carbsMinGrams, lessThan(target.carbsMaxGrams));
  });

  test('maintenance centers the calorie range on TDEE', () {
    final target = calculator.calculate(
      const NutritionTargetInput(
        age: 40,
        biologicalSex: BiologicalSex.female,
        heightCm: 165,
        weightKg: 60,
        activityLevel: ActivityLevel.lightlyActive,
        goal: HealthGoal.maintain,
      ),
    );

    expect(target.calorieMinKcal, closeTo(target.tdeeKcal * 0.95, 1));
    expect(target.calorieMaxKcal, closeTo(target.tdeeKcal * 1.05, 1));
  });

  test('rejects unsupported minor profiles', () {
    expect(
      () => calculator.calculate(
        const NutritionTargetInput(
          age: 17,
          biologicalSex: BiologicalSex.female,
          heightCm: 165,
          weightKg: 55,
          activityLevel: ActivityLevel.sedentary,
          goal: HealthGoal.loseFat,
        ),
      ),
      throwsFormatException,
    );
  });

  test('rejects out-of-range and non-finite measurements', () {
    for (final values in [
      (100.0, 75.0),
      (175.0, 500.0),
      (double.nan, 75.0),
      (175.0, double.infinity),
    ]) {
      expect(
        () => calculator.calculate(
          NutritionTargetInput(
            age: 30,
            biologicalSex: BiologicalSex.male,
            heightCm: values.$1,
            weightKg: values.$2,
            activityLevel: ActivityLevel.sedentary,
            goal: HealthGoal.gainMuscle,
          ),
        ),
        throwsFormatException,
      );
    }
  });
}
