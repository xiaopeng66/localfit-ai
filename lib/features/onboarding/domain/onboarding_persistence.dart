import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

final class OnboardingProfileDraft {
  const OnboardingProfileDraft({
    required this.profileId,
    required this.goalId,
    required this.targetId,
    required this.measurementId,
    required this.birthYear,
    required this.biologicalSex,
    required this.heightCm,
    required this.weightKg,
    required this.activityLevel,
    required this.goal,
    required this.targetWeightKg,
    required this.localDate,
    required this.nowUtc,
  });

  final String profileId;
  final String goalId;
  final String targetId;
  final String measurementId;
  final int birthYear;
  final BiologicalSex biologicalSex;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activityLevel;
  final HealthGoal goal;
  final double? targetWeightKg;
  final String localDate;
  final DateTime nowUtc;
}

extension OnboardingPersistence on AppDatabase {
  Future<void> saveOnboardingProfile({
    required OnboardingProfileDraft draft,
    required NutritionTarget target,
  }) {
    return transaction(() async {
      await into(profiles).insert(
        ProfilesCompanion.insert(
          id: draft.profileId,
          birthYear: Value(draft.birthYear),
          biologicalSex: Value(draft.biologicalSex.name),
          heightCm: Value(draft.heightCm),
          activityLevel: draft.activityLevel.name,
          createdAt: draft.nowUtc,
          updatedAt: draft.nowUtc,
        ),
      );
      await into(goals).insert(
        GoalsCompanion.insert(
          id: draft.goalId,
          profileId: draft.profileId,
          type: draft.goal.name,
          targetWeightKg: Value(draft.targetWeightKg),
          calorieMinKcal: target.calorieMinKcal.toDouble(),
          calorieMaxKcal: target.calorieMaxKcal.toDouble(),
          effectiveFrom: draft.nowUtc,
          createdAt: draft.nowUtc,
          updatedAt: draft.nowUtc,
        ),
      );
      await into(dailyTargets).insert(
        DailyTargetsCompanion.insert(
          id: draft.targetId,
          goalId: draft.goalId,
          effectiveDate: draft.localDate,
          calorieMinKcal: target.calorieMinKcal.toDouble(),
          calorieMaxKcal: target.calorieMaxKcal.toDouble(),
          proteinMinGrams: target.proteinMinGrams.toDouble(),
          proteinMaxGrams: target.proteinMaxGrams.toDouble(),
          carbsMinGrams: target.carbsMinGrams.toDouble(),
          carbsMaxGrams: target.carbsMaxGrams.toDouble(),
          fatMinGrams: target.fatMinGrams.toDouble(),
          fatMaxGrams: target.fatMaxGrams.toDouble(),
          createdAt: draft.nowUtc,
          updatedAt: draft.nowUtc,
        ),
      );
      await into(measurements).insert(
        MeasurementsCompanion.insert(
          id: draft.measurementId,
          profileId: draft.profileId,
          localDate: draft.localDate,
          weightKg: draft.weightKg,
          createdAt: draft.nowUtc,
          updatedAt: draft.nowUtc,
        ),
      );
    });
  }
}
