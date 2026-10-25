import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

import '../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;
  final now = DateTime.utc(2026, 9, 9, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    final ids = _IncrementingIdGenerator();
    foods = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now),
    );
    meals = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  test(
    'saves scaled snapshots and aggregates only the requested date',
    () async {
      final rice = (await foods.search('米饭'))
          .firstWhere((food) => food.name == '米饭');
      final egg = (await foods.search('鸡蛋'))
          .firstWhere((food) => food.name == '鸡蛋');
      await meals.saveManualMeal(
        ManualMealDraft(
          localDate: '2026-09-09',
          slot: MealSlot.lunch,
          items: [
            ManualMealItemDraft(food: rice, grams: 200),
            ManualMealItemDraft(food: egg, grams: 50),
          ],
        ),
      );
      await meals.saveManualMeal(
        ManualMealDraft(
          localDate: '2026-09-08',
          slot: MealSlot.dinner,
          items: [ManualMealItemDraft(food: rice, grams: 100)],
        ),
      );

      final summary = await meals.watchNutritionForDate('2026-09-09').first;
      expect(
        summary.consumed.kcal,
        closeTo(rice.kcalPer100g * 2 + egg.kcalPer100g * .5, .001),
      );
      expect(
        summary.consumed.proteinGrams,
        closeTo(rice.proteinPer100g * 2 + egg.proteinPer100g * .5, .001),
      );
      final rows = await database.select(database.mealItems).get();
      expect(rows.first.foodNameSnapshot, rice.name);
      expect(rows.first.grams, 200);
    },
  );

  test('当天餐次按餐位域序返回（早餐→午餐→晚餐→加餐），不按存储串', () async {
    final rice = (await foods.search('米饭'))
        .firstWhere((food) => food.name == '米饭');
    // 逆序记录：存储串序 `breakfast < dinner < lunch < snack` 会把晚餐排到
    // 午餐前面（round7 2A 整页渲染逐张审看抓到的真实缺陷：今日页
    // 「今天吃了什么」渲染成 早餐 / 晚餐 / 午餐）。
    for (final slot in [
      MealSlot.dinner,
      MealSlot.snack,
      MealSlot.breakfast,
      MealSlot.lunch,
    ]) {
      await meals.saveManualMeal(
        ManualMealDraft(
          localDate: '2026-09-09',
          slot: slot,
          items: [ManualMealItemDraft(food: rice, grams: 100)],
        ),
      );
    }

    final rows = await meals.watchForDate('2026-09-09').first;
    expect(rows.map((meal) => meal.slot).toList(), [
      MealSlot.breakfast,
      MealSlot.lunch,
      MealSlot.dinner,
      MealSlot.snack,
    ], reason: '域顺序的事实源是 MealSlot.values（枚举声明序），不是 storedValue 的字符串序');
  });

  test('saved totals remain stable after the source food changes', () async {
    final rice = (await foods.search('米饭'))
        .firstWhere((food) => food.name == '米饭');
    await meals.saveManualMeal(
      ManualMealDraft(
        localDate: '2026-09-09',
        slot: MealSlot.lunch,
        items: [ManualMealItemDraft(food: rice, grams: 100)],
      ),
    );
    await (database.update(database.foods)
          ..where((row) => row.id.equals(rice.id)))
        .write(const FoodsCompanion(kcalPer100g: Value(999)));

    final summary = await meals.watchNutritionForDate('2026-09-09').first;
    expect(summary.consumed.kcal, rice.kcalPer100g);
  });

  test('selects the latest target effective for the date', () async {
    await insertTarget(database, now, 'old', '2026-01-01', 1800, 2000);
    await insertTarget(database, now, 'current', '2026-09-01', 2000, 2200);
    await insertTarget(database, now, 'future', '2026-10-01', 2500, 2700);

    final summary = await meals.watchNutritionForDate('2026-09-09').first;
    expect(summary.target!.calorieMinKcal, 2000);
    expect(summary.target!.calorieMaxKcal, 2200);
  });

  test('rejects invalid items without writing a meal', () async {
    final rice = (await foods.search('米饭'))
        .firstWhere((food) => food.name == '米饭');
    for (final grams in [0.0, -1.0, double.nan, double.infinity]) {
      await expectLater(
        meals.saveManualMeal(
          ManualMealDraft(
            localDate: '2026-09-09',
            slot: MealSlot.lunch,
            items: [ManualMealItemDraft(food: rice, grams: grams)],
          ),
        ),
        throwsFormatException,
      );
    }
    expect(await database.select(database.meals).get(), isEmpty);
    expect(await database.select(database.mealItems).get(), isEmpty);
  });

  test('rejects an empty meal', () async {
    await expectLater(
      meals.saveManualMeal(
        const ManualMealDraft(
          localDate: '2026-09-09',
          slot: MealSlot.snack,
          items: [],
        ),
      ),
      throwsFormatException,
    );
  });

  test('lists, updates, deletes and restores a meal aggregate', () async {
    final rice = (await foods.search('米饭'))
        .firstWhere((food) => food.name == '米饭');
    final id = await meals.create(
      MealDraft(
        localDate: '2026-09-09',
        slot: MealSlot.lunch,
        notes: '原备注',
        items: [MealItemDraft.fromFood(rice, 100)],
      ),
    );
    final created = (await meals.watchForDate('2026-09-09').first).single;
    expect(created.id, id);
    expect(created.notes, '原备注');

    await meals.update(
      id,
      MealDraft(
        localDate: '2026-09-10',
        slot: MealSlot.dinner,
        notes: '更新备注',
        items: [created.items.single.scaledTo(200)],
      ),
    );
    expect(await meals.watchForDate('2026-09-09').first, isEmpty);
    final updated = (await meals.watchForDate('2026-09-10').first).single;
    expect(updated.slot, MealSlot.dinner);
    expect(updated.items.single.grams, 200);
    expect(updated.nutrition.kcal, closeTo(created.nutrition.kcal * 2, .001));

    final deleted = await meals.delete(id);
    expect(deleted == null, isFalse);
    expect(await meals.watchForDate('2026-09-10').first, isEmpty);
    await meals.restore(deleted!);
    final restored = (await meals.watchForDate('2026-09-10').first).single;
    expect(restored.id, id);
    expect(restored.items.single.id, deleted.items.single.id);
    expect(restored.nutrition.kcal, deleted.nutrition.kcal);
  });

  test('reuses snapshots with fresh ids after the food changes', () async {
    final rice = (await foods.search('米饭'))
        .firstWhere((food) => food.name == '米饭');
    final sourceId = await meals.create(
      MealDraft(
        localDate: '2026-09-08',
        slot: MealSlot.lunch,
        items: [MealItemDraft.fromFood(rice, 150)],
      ),
    );
    final source = (await meals.watchForDate('2026-09-08').first).single;
    await (database.update(database.foods)
          ..where((row) => row.id.equals(rice.id)))
        .write(const FoodsCompanion(kcalPer100g: Value(999)));

    final reusedId = await meals.reuse(sourceId, localDate: '2026-09-09');
    final reused = (await meals.watchForDate('2026-09-09').first).single;
    expect(reused.id, isNot(source.id));
    expect(reused.id, reusedId);
    expect(reused.items.single.id, isNot(source.items.single.id));
    expect(reused.nutrition.kcal, source.nutrition.kcal);
    expect(reused.source, 'history_reuse');
  });

  test('rejects impossible calendar dates', () async {
    final rice = (await foods.search('米饭'))
        .firstWhere((food) => food.name == '米饭');
    await expectLater(
      meals.create(
        MealDraft(
          localDate: '2026-02-30',
          slot: MealSlot.lunch,
          items: [MealItemDraft.fromFood(rice, 100)],
        ),
      ),
      throwsFormatException,
    );
    expect(await database.select(database.meals).get(), isEmpty);
  });
}

Future<void> insertTarget(
  AppDatabase database,
  DateTime now,
  String suffix,
  String date,
  double min,
  double max,
) async {
  await database
      .into(database.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: 'profile-$suffix',
          activityLevel: 'lightlyActive',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.goals)
      .insert(
        GoalsCompanion.insert(
          id: 'goal-$suffix',
          profileId: 'profile-$suffix',
          type: 'maintain',
          calorieMinKcal: min,
          calorieMaxKcal: max,
          effectiveFrom: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.dailyTargets)
      .insert(
        DailyTargetsCompanion.insert(
          id: 'target-$suffix',
          goalId: 'goal-$suffix',
          effectiveDate: date,
          calorieMinKcal: min,
          calorieMaxKcal: max,
          proteinMinGrams: 100,
          proteinMaxGrams: 140,
          carbsMinGrams: 200,
          carbsMaxGrams: 260,
          fatMinGrams: 50,
          fatMaxGrams: 70,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}
