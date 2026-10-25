import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';

void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 9, 9);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test(
    'saves a confirmed meal and its nutrition snapshot atomically',
    () async {
      await database.saveConfirmedMeal(
        meal: MealsCompanion.insert(
          id: 'meal-1',
          localDate: '2026-09-09',
          slot: 'lunch',
          eatenAt: now,
          source: 'manual',
          createdAt: now,
          updatedAt: now,
        ),
        items: [
          MealItemsCompanion.insert(
            id: 'item-1',
            mealId: 'meal-1',
            foodNameSnapshot: '米饭',
            grams: 180,
            kcalSnapshot: 209,
            proteinSnapshot: 4.7,
            carbsSnapshot: 46.5,
            fatSnapshot: 0.5,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );

      final mealRows = await database.select(database.meals).get();
      final itemRows = await database.select(database.mealItems).get();

      expect(mealRows.single.id, 'meal-1');
      expect(itemRows.single.foodNameSnapshot, '米饭');
      expect(itemRows.single.kcalSnapshot, 209);
    },
  );

  test('rolls back the meal if an item insert fails', () async {
    await expectLater(
      database.saveConfirmedMeal(
        meal: MealsCompanion.insert(
          id: 'meal-rollback',
          localDate: '2026-09-09',
          slot: 'dinner',
          eatenAt: now,
          source: 'manual',
          createdAt: now,
          updatedAt: now,
        ),
        items: [
          MealItemsCompanion.insert(
            id: 'item-bad',
            mealId: 'missing-meal',
            foodNameSnapshot: '无效条目',
            grams: 1,
            kcalSnapshot: 1,
            proteinSnapshot: 0,
            carbsSnapshot: 0,
            fatSnapshot: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
      throwsA(isA<Exception>()),
    );

    expect(await database.select(database.meals).get(), isEmpty);
    expect(await database.select(database.mealItems).get(), isEmpty);
  });

  test('file database fails closed when SQLCipher is unavailable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'localfit-db-test-',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}localfit.sqlite',
    );
    final key = Uint8List.fromList(List.filled(32, 7));
    final encrypted = AppDatabase.openFile(file: file, key: key);

    await expectLater(
      encrypted.customSelect('SELECT count(*) FROM profiles').getSingle(),
      throwsA(
        predicate(
          (error) =>
              error.toString().contains('SQLCipher library is unavailable'),
          'an error explaining that SQLCipher is unavailable',
        ),
      ),
    );

    await encrypted.close();
    await directory.delete(recursive: true);
  });

  test('deleting a meal cascades to its items', () async {
    await database.saveConfirmedMeal(
      meal: MealsCompanion.insert(
        id: 'meal-delete',
        localDate: '2026-09-09',
        slot: 'breakfast',
        eatenAt: now,
        source: 'manual',
        createdAt: now,
        updatedAt: now,
      ),
      items: [
        MealItemsCompanion.insert(
          id: 'item-delete',
          mealId: 'meal-delete',
          foodNameSnapshot: '鸡蛋',
          grams: 50,
          kcalSnapshot: 72,
          proteinSnapshot: 6.5,
          carbsSnapshot: 0.5,
          fatSnapshot: 5,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    await (database.delete(
      database.meals,
    )..where((row) => row.id.equals('meal-delete'))).go();

    expect(await database.select(database.mealItems).get(), isEmpty);
  });
}
