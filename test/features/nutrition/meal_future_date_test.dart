import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// docs/64 B-2（P0 插队）：`MealRepository._validateDate` 原先**只校验格式**，
/// 不拦未来日期；而体重仓储已有先例（`measurement_repository.dart:35`）。
/// ⇒ AI 的 `meal.create` 可以写未来日期的餐，污染「今天还剩多少」。
///
/// 判据：晚于**本机今天**的 `localDate` 一律拒绝且整笔不写；
/// 今天与过去（含补记窗口）照常接受——加固不能把正常记录挡掉。
/// 读路径（`watchForDate`）不受影响：查未来日期只是空列表，不该抛。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late MealRepository meals;
  final now = DateTime.utc(2026, 10, 26, 9);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    meals = MealRepository(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  MealDraft draftFor(String localDate) => MealDraft(
    localDate: localDate,
    slot: MealSlot.lunch,
    items: const [
      MealItemDraft(
        foodName: '米饭',
        grams: 200,
        nutrition: NutritionValues(
          kcal: 232,
          proteinGrams: 5.2,
          carbsGrams: 51.6,
          fatGrams: 0.6,
        ),
      ),
    ],
  );

  test('餐食不能写在未来日期（与体重同一口径）：抛 FormatException 且不落库', () async {
    await expectLater(
      meals.create(draftFor('2026-10-27')),
      throwsA(isA<FormatException>()),
    );
    final mealRows = await database.select(database.meals).get();
    final itemRows = await database.select(database.mealItems).get();
    expect(mealRows, isEmpty, reason: '拒绝必须是「整笔不写」，不是写一半');
    expect(itemRows, isEmpty, reason: '拒绝必须是「整笔不写」，不是写一半');
  });

  test('今天与过去 30 天都能写（补记窗口内）', () async {
    await meals.create(draftFor('2026-10-26'));
    await meals.create(draftFor('2026-10-25'));
    await meals.create(draftFor('2026-09-26'));
    final rows = await database.select(database.meals).get();
    expect(rows.map((row) => row.localDate).toSet(), {
      '2026-10-26',
      '2026-10-25',
      '2026-09-26',
    });
  });

  test('读未来日期只是空，不抛（守卫只拦写）', () async {
    final result = await meals.watchForDate('2026-10-27').first;
    expect(result, isEmpty);
  });
}

final class _SeqIds implements IdGenerator {
  int _next = 0;

  @override
  String next() => 'id-${_next++}';
}
