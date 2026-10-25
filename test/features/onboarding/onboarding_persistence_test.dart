import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/onboarding/domain/onboarding_persistence.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test(
    'saves profile, goal, daily target and initial weight atomically',
    () async {
      const calculator = NutritionTargetCalculator();
      const input = NutritionTargetInput(
        age: 30,
        biologicalSex: BiologicalSex.male,
        heightCm: 175,
        weightKg: 75,
        activityLevel: ActivityLevel.moderatelyActive,
        goal: HealthGoal.loseFat,
      );
      final target = calculator.calculate(input);
      final now = DateTime.utc(2026, 9, 9);

      await database.saveOnboardingProfile(
        draft: OnboardingProfileDraft(
          profileId: 'profile-1',
          goalId: 'goal-1',
          targetId: 'target-1',
          measurementId: 'measurement-1',
          birthYear: 1996,
          biologicalSex: input.biologicalSex,
          heightCm: input.heightCm,
          weightKg: input.weightKg,
          activityLevel: input.activityLevel,
          goal: input.goal,
          targetWeightKg: 68,
          localDate: '2026-09-09',
          nowUtc: now,
        ),
        target: target,
      );

      expect(
        (await database.select(database.profiles).getSingle()).id,
        'profile-1',
      );
      expect(
        (await database.select(database.goals).getSingle()).type,
        'loseFat',
      );
      expect(
        (await database.select(database.dailyTargets).getSingle())
            .proteinMaxGrams,
        target.proteinMaxGrams,
      );
      expect(
        (await database.select(database.measurements).getSingle()).weightKg,
        75,
      );
    },
  );
}
