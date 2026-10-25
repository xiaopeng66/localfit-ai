import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/onboarding/domain/onboarding_persistence.dart';

final class OnboardingInput {
  const OnboardingInput({
    required this.age,
    required this.biologicalSex,
    required this.heightCm,
    required this.weightKg,
    required this.activityLevel,
    required this.goal,
    this.targetWeightKg,
    this.isPregnantOrBreastfeeding = false,
    this.hasChronicCondition = false,
    this.hasEatingDisorderRisk = false,
  });

  final int age;
  final BiologicalSex biologicalSex;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activityLevel;
  final HealthGoal goal;
  final double? targetWeightKg;
  final bool isPregnantOrBreastfeeding;
  final bool hasChronicCondition;
  final bool hasEatingDisorderRisk;
}

final class OnboardingSafetyException implements Exception {
  const OnboardingSafetyException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class CompleteOnboarding {
  const CompleteOnboarding({
    required this.database,
    required this.idGenerator,
    required this.clock,
    this.calculator = const NutritionTargetCalculator(),
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;
  final NutritionTargetCalculator calculator;

  Future<NutritionTarget> call(OnboardingInput input) async {
    validateOnboardingSafety(input);
    final targetInput = NutritionTargetInput(
      age: input.age,
      biologicalSex: input.biologicalSex,
      heightCm: input.heightCm,
      weightKg: input.weightKg,
      activityLevel: input.activityLevel,
      goal: input.goal,
    );
    final target = calculator.calculate(targetInput);
    final nowUtc = clock.nowUtc();
    final localNow = nowUtc.toLocal();

    await database.saveOnboardingProfile(
      draft: OnboardingProfileDraft(
        profileId: idGenerator.next(),
        goalId: idGenerator.next(),
        targetId: idGenerator.next(),
        measurementId: idGenerator.next(),
        birthYear: localNow.year - input.age,
        biologicalSex: input.biologicalSex,
        heightCm: input.heightCm,
        weightKg: input.weightKg,
        activityLevel: input.activityLevel,
        goal: input.goal,
        targetWeightKg: input.targetWeightKg,
        localDate: _localDate(localNow),
        nowUtc: nowUtc,
      ),
      target: target,
    );
    return target;
  }

  String _localDate(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)}';
  }
}

void validateOnboardingSafety(OnboardingInput input) {
  if (input.age < 18) {
    throw const OnboardingSafetyException(
      '未成年人需要由监护人与医生或注册营养师共同评估，LocalFit AI 不会自动生成营养目标。',
    );
  }
  final target = input.targetWeightKg;
  if (target != null && (!target.isFinite || target < 35 || target > 300)) {
    throw const FormatException('目标体重必须在 35–300 kg 之间。');
  }
  if (input.isPregnantOrBreastfeeding ||
      input.hasChronicCondition ||
      input.hasEatingDisorderRisk) {
    throw const OnboardingSafetyException(
      '当前情况需要个体化评估，请先咨询医生或注册营养师；LocalFit AI 不会自动生成减脂或增肌目标。',
    );
  }

  final heightMeters = input.heightCm / 100;
  final currentBmi = input.weightKg / (heightMeters * heightMeters);
  final unsafeCurrentGoal =
      !currentBmi.isFinite ||
      (currentBmi < 18.5 && input.goal == HealthGoal.loseFat) ||
      (currentBmi > 40 && input.goal != HealthGoal.maintain);
  if (unsafeCurrentGoal) {
    throw const OnboardingSafetyException('当前体重与所选目标需要专业评估，请先咨询医生或注册营养师。');
  }
  if (target == null) return;

  final targetBmi = target / (heightMeters * heightMeters);
  final directionConflict =
      (input.goal == HealthGoal.loseFat && target >= input.weightKg) ||
      (input.goal == HealthGoal.gainMuscle && target <= input.weightKg) ||
      (input.goal == HealthGoal.maintain &&
          (target - input.weightKg).abs() > input.weightKg * 0.05);
  if (!targetBmi.isFinite ||
      targetBmi < 18.5 ||
      targetBmi > 40 ||
      directionConflict) {
    throw const OnboardingSafetyException(
      '目标体重可能不适合当前身高或与所选目标冲突，请先咨询医生或注册营养师后再设定。',
    );
  }
}
