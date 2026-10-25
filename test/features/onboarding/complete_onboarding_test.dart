import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

void main() {
  late AppDatabase database;
  late CompleteOnboarding complete;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    complete = CompleteOnboarding(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 9, 10)),
    );
  });

  tearDown(() => database.close());

  OnboardingInput input({
    int age = 30,
    double heightCm = 165,
    double weightKg = 75,
    HealthGoal goal = HealthGoal.loseFat,
    double? targetWeightKg = 68,
    bool pregnancy = false,
    bool chronic = false,
    bool eatingRisk = false,
  }) => OnboardingInput(
    age: age,
    biologicalSex: BiologicalSex.female,
    heightCm: heightCm,
    weightKg: weightKg,
    activityLevel: ActivityLevel.lightlyActive,
    goal: goal,
    targetWeightKg: targetWeightKg,
    isPregnantOrBreastfeeding: pregnancy,
    hasChronicCondition: chronic,
    hasEatingDisorderRisk: eatingRisk,
  );

  test('blocks health risks before writing any profile data', () async {
    for (final risky in [
      input(pregnancy: true),
      input(chronic: true),
      input(eatingRisk: true),
    ]) {
      await expectLater(
        complete(risky),
        throwsA(isA<OnboardingSafetyException>()),
      );
    }
    expect(await database.select(database.profiles).get(), isEmpty);
    expect(await database.select(database.goals).get(), isEmpty);
    expect(await database.select(database.dailyTargets).get(), isEmpty);
    expect(await database.select(database.measurements).get(), isEmpty);
  });

  test('blocks unsafe or goal-conflicting target weights', () async {
    for (final unsafe in [
      input(targetWeightKg: 45),
      input(targetWeightKg: 80),
      input(goal: HealthGoal.gainMuscle, targetWeightKg: 70),
      input(goal: HealthGoal.maintain, targetWeightKg: 65),
    ]) {
      await expectLater(
        complete(unsafe),
        throwsA(isA<OnboardingSafetyException>()),
      );
    }
    expect(await database.select(database.profiles).get(), isEmpty);
  });

  test('blocks unsafe current BMI even when target is omitted', () async {
    for (final unsafe in [
      input(heightCm: 180, weightKg: 55, targetWeightKg: null),
      input(
        heightCm: 150,
        weightKg: 95,
        goal: HealthGoal.gainMuscle,
        targetWeightKg: null,
      ),
      input(age: 17, targetWeightKg: null),
    ]) {
      await expectLater(
        complete(unsafe),
        throwsA(isA<OnboardingSafetyException>()),
      );
    }
    expect(await database.select(database.profiles).get(), isEmpty);
  });

  test('blocks plans below the adult minimum calorie boundary', () async {
    final unsafe = input(
      age: 100,
      heightCm: 150,
      weightKg: 42,
      goal: HealthGoal.maintain,
      targetWeightKg: null,
    );
    await expectLater(complete(unsafe), throwsFormatException);
    expect(await database.select(database.profiles).get(), isEmpty);
  });

  test('rejects invalid target values before writing data', () async {
    for (final target in [34.9, 300.1, double.nan, double.infinity]) {
      await expectLater(
        complete(input(targetWeightKg: target)),
        throwsFormatException,
      );
    }
    expect(await database.select(database.profiles).get(), isEmpty);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'onboarding-${_value++}';
}
