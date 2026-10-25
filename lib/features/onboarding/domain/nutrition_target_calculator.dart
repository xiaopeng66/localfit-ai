enum BiologicalSex { female, male }

enum ActivityLevel {
  sedentary(1.2),
  lightlyActive(1.375),
  moderatelyActive(1.55),
  veryActive(1.725);

  const ActivityLevel(this.multiplier);

  final double multiplier;
}

enum HealthGoal { loseFat, maintain, gainMuscle }

final class NutritionTargetInput {
  const NutritionTargetInput({
    required this.age,
    required this.biologicalSex,
    required this.heightCm,
    required this.weightKg,
    required this.activityLevel,
    required this.goal,
  });

  final int age;
  final BiologicalSex biologicalSex;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activityLevel;
  final HealthGoal goal;
}

final class NutritionTarget {
  const NutritionTarget({
    required this.bmrKcal,
    required this.tdeeKcal,
    required this.calorieMinKcal,
    required this.calorieMaxKcal,
    required this.proteinMinGrams,
    required this.proteinMaxGrams,
    required this.carbsMinGrams,
    required this.carbsMaxGrams,
    required this.fatMinGrams,
    required this.fatMaxGrams,
  });

  final int bmrKcal;
  final int tdeeKcal;
  final int calorieMinKcal;
  final int calorieMaxKcal;
  final int proteinMinGrams;
  final int proteinMaxGrams;
  final int carbsMinGrams;
  final int carbsMaxGrams;
  final int fatMinGrams;
  final int fatMaxGrams;
}

final class NutritionTargetCalculator {
  const NutritionTargetCalculator();

  NutritionTarget calculate(NutritionTargetInput input) {
    _validate(input);

    final sexAdjustment = switch (input.biologicalSex) {
      BiologicalSex.male => 5,
      BiologicalSex.female => -161,
    };
    final bmr =
        10 * input.weightKg +
        6.25 * input.heightCm -
        5 * input.age +
        sexAdjustment;
    final tdee = bmr * input.activityLevel.multiplier;
    final calorieCenter = switch (input.goal) {
      HealthGoal.loseFat => tdee * 0.85,
      HealthGoal.maintain => tdee,
      HealthGoal.gainMuscle => tdee * 1.08,
    };
    final minimumCalories = switch (input.biologicalSex) {
      BiologicalSex.female => 1200.0,
      BiologicalSex.male => 1500.0,
    };
    if (calorieCenter * 0.95 < minimumCalories) {
      throw const FormatException('无法在成人最低热量安全边界内生成目标，请咨询医生或注册营养师。');
    }
    final proteinRange = switch (input.goal) {
      HealthGoal.loseFat => (1.6, 2.0),
      HealthGoal.maintain => (1.4, 1.8),
      HealthGoal.gainMuscle => (1.6, 2.2),
    };
    final fatMin = input.weightKg * 0.7;
    final fatMax = input.weightKg * 1.0;
    final proteinMin = input.weightKg * proteinRange.$1;
    final proteinMax = input.weightKg * proteinRange.$2;
    final carbsMin = _remainingCarbs(calorieCenter * 0.95, proteinMax, fatMax);
    final carbsMax = _remainingCarbs(calorieCenter * 1.05, proteinMin, fatMin);

    return NutritionTarget(
      bmrKcal: bmr.round(),
      tdeeKcal: tdee.round(),
      calorieMinKcal: (calorieCenter * 0.95).round(),
      calorieMaxKcal: (calorieCenter * 1.05).round(),
      proteinMinGrams: proteinMin.round(),
      proteinMaxGrams: proteinMax.round(),
      carbsMinGrams: carbsMin.round(),
      carbsMaxGrams: carbsMax.round(),
      fatMinGrams: fatMin.round(),
      fatMaxGrams: fatMax.round(),
    );
  }

  double _remainingCarbs(double calories, double protein, double fat) {
    final remaining = calories - protein * 4 - fat * 9;
    return (remaining / 4).clamp(0, double.infinity);
  }

  void _validate(NutritionTargetInput input) {
    if (input.age < 18 || input.age > 100) {
      throw const FormatException('仅支持 18–100 岁成人；未成年人请咨询医生或注册营养师。');
    }
    if (!input.heightCm.isFinite ||
        input.heightCm < 120 ||
        input.heightCm > 230) {
      throw const FormatException('身高必须在 120–230 cm 之间。');
    }
    if (!input.weightKg.isFinite ||
        input.weightKg < 35 ||
        input.weightKg > 300) {
      throw const FormatException('体重必须在 35–300 kg 之间。');
    }
  }
}
