import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

import '../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps Phase 1 data after host SQLite close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'localfit-restart-flow-',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}localfit-test.sqlite',
    );
    final ids = _Ids();
    final now = DateTime.utc(2026, 9, 10, 12);
    final clock = FixedAppClock(now);
    final localNow = now.toLocal();
    final localDate =
        '${localNow.year.toString().padLeft(4, '0')}-'
        '${localNow.month.toString().padLeft(2, '0')}-'
        '${localNow.day.toString().padLeft(2, '0')}';
    AppDatabase? database;

    try {
      database = AppDatabase(NativeDatabase(file));
      await seedFoodFixture(database);
      await CompleteOnboarding(
        database: database,
        idGenerator: ids,
        clock: clock,
      )(
        const OnboardingInput(
          age: 30,
          biologicalSex: BiologicalSex.male,
          heightCm: 175,
          weightKg: 75,
          activityLevel: ActivityLevel.moderatelyActive,
          goal: HealthGoal.loseFat,
          targetWeightKg: 68,
        ),
      );
      final foodRepository = FoodRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final mealRepository = MealRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final measurementRepository = MeasurementRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final food = await foodRepository.create(
        const NewFood(
          name: '离线燕麦杯',
          defaultServingGrams: 80,
          kcalPer100g: 150,
          proteinPer100g: 8,
          carbsPer100g: 20,
          fatPer100g: 4,
        ),
      );
      await mealRepository.create(
        MealDraft(
          localDate: localDate,
          slot: MealSlot.breakfast,
          notes: '宿主机持久化测试',
          items: [MealItemDraft.fromFood(food, 80)],
        ),
      );
      await measurementRepository.saveManualWeight(
        localDate: localDate,
        weightKg: 74.5,
        notes: '重启前',
      );
      await database.close();
      database = null;

      database = AppDatabase(NativeDatabase(file));
      final reopenedMeals = MealRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final reopenedMeasurements = MeasurementRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );
      final reopenedFoods = FoodRepository(
        database: database,
        idGenerator: ids,
        clock: clock,
      );

      expect(await database.hasProfile(), isTrue);
      expect(await database.select(database.goals).get(), hasLength(1));
      expect(await database.select(database.dailyTargets).get(), hasLength(1));
      expect(
        (await reopenedFoods.search('离线燕麦杯')).single.isUserCreated,
        isTrue,
      );
      final meal = (await reopenedMeals.watchForDate(localDate).first).single;
      expect(meal.notes, '宿主机持久化测试');
      expect(meal.items.single.foodName, '离线燕麦杯');
      expect(meal.items.single.grams, 80);
      expect(meal.nutrition.kcal, 120);
      final nutrition = await reopenedMeals
          .watchNutritionForDate(localDate)
          .first;
      expect(nutrition.consumed.kcal, 120);
      expect(nutrition.consumed.proteinGrams, 6.4);
      expect(nutrition.target, isNotNull);
      final weight = await reopenedMeasurements
          .watchWeightOverview(endLocalDate: localDate)
          .first;
      expect(weight.latest!.weightKg, 74.5);
      expect(weight.sevenDayAverageKg, 74.5);
      expect(weight.sampleDays, 1);

      final foodCount = (await database.select(database.foods).get()).length;
      await seedFoodFixture(database);
      expect((await database.select(database.foods).get()).length, foodCount);
    } finally {
      await database?.close();
      await directory.delete(recursive: true);
    }
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'restart-${_value++}';
}
