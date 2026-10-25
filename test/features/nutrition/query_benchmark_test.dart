import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

/// 2 年数据量查询基准（docs/05 §2 口径：每日 8 个食物条目、每周 5 次训练）。
///
/// 桌面 in-memory SQLite 的绝对数值仅供参考，发布门槛以中档真机为准；
/// 这里同时断言宽松上限以捕获病态回归（如索引缺失退化、意外笛卡尔积）。
void main() {
  late AppDatabase database;
  late MealRepository mealRepository;
  late FoodRepository foodRepository;
  late WorkoutSessionRepository sessionRepository;

  setUpAll(() async {
    database = AppDatabase(NativeDatabase.memory());
    mealRepository = MealRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    );
    foodRepository = FoodRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    );
    sessionRepository = WorkoutSessionRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    );
    await _seedTwoYears(database);
  });

  tearDownAll(() => database.close());

  test('今日页：watchForDate 首查 + listRecent(50)', () async {
    var watch = Stopwatch()..start();
    final today = await mealRepository.watchForDate('2027-09-09').first;
    watch.stop();

    var recent = Stopwatch()..start();
    final recentMeals = await mealRepository.listRecent();
    recent.stop();

    //ignore: avoid_print
    print('watchForDate（3 餐 8 条目）: ${watch.elapsedMilliseconds} ms');
    //ignore: avoid_print
    print('listRecent(50)（50 餐）: ${recent.elapsedMilliseconds} ms');

    expect(today, hasLength(3));
    expect(today.expand((meal) => meal.items), hasLength(8));
    expect(recentMeals, hasLength(50));
    // 宽松回归护栏：桌面端正常 <20ms，超过 1s 说明索引/查询退化。
    expect(watch.elapsedMilliseconds, lessThan(1000));
    expect(recent.elapsedMilliseconds, lessThan(1000));
  });

  test('趋势：listDailyIntakeBetween 30 天 + 训练关联 listFinishedBetween', () async {
    var trend = Stopwatch()..start();
    final records = await mealRepository.listDailyIntakeBetween(
      '2027-08-11',
      '2027-09-09',
    );
    trend.stop();

    var sessions = Stopwatch()..start();
    final finished = await sessionRepository.listFinishedBetween(
      '2027-08-11',
      '2027-09-09',
    );
    sessions.stop();

    //ignore: avoid_print
    print('listDailyIntakeBetween(30 天): ${trend.elapsedMilliseconds} ms');
    //ignore: avoid_print
    print(
      'listFinishedBetween(30 天, ${finished.length} 会话): '
      '${sessions.elapsedMilliseconds} ms',
    );

    expect(records, isNotEmpty);
    expect(finished, hasLength(22)); // 30 天窗口内的周一至周五
    expect(trend.elapsedMilliseconds, lessThan(1000));
    expect(sessions.elapsedMilliseconds, lessThan(1000));
  });

  test('搜索本地食物首批结果', () async {
    var search = Stopwatch()..start();
    final results = await foodRepository.search('鸡胸', limit: 30);
    search.stop();

    //ignore: avoid_print
    print('food search（500 食物库）: ${search.elapsedMilliseconds} ms');
    expect(results, isNotEmpty);
    expect(search.elapsedMilliseconds, lessThan(500));
  });
}

Future<void> _seedTwoYears(AppDatabase database) async {
  // 730 天 × 3 餐/天 × ~2.7 条目/餐 = 每日 8 个食物条目（docs/05 §2）。
  const days = 730;
  final start = DateTime.utc(2025, 9, 10);
  final base = DateTime.utc(2025, 9, 10);
  var mealSeq = 0;

  await database.batch((batch) {
    // 500 个食物（种子规模）供搜索基准。
    for (var i = 0; i < 500; i++) {
      final ts = base.add(Duration(minutes: i));
      batch.insert(
        database.foods,
        FoodsCompanion.insert(
          id: 'food-$i',
          name: i == 0 ? '鸡胸肉' : '食物$i',
          kcalPer100g: 100 + i % 400,
          proteinPer100g: 10,
          carbsPer100g: 10,
          fatPer100g: 5,
          source: 'seed-bench',
          createdAt: ts,
          updatedAt: ts,
        ),
      );
    }

    // 20 个动作供训练组引用（会话装载走 exercises join）。
    for (var i = 0; i < 20; i++) {
      batch.insert(
        database.exercises,
        ExercisesCompanion.insert(
          id: 'exercise-$i',
          name: '动作$i',
          muscleGroup: 'chest',
          equipment: 'barbell',
          source: 'seed-bench',
          createdAt: base,
          updatedAt: base,
        ),
      );
    }

    for (var day = 0; day < days; day++) {
      final date = start.add(Duration(days: day));
      final localDate =
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      // 每周前 5 天一次训练会话（每周 5 次，docs/05 §2）。
      if (date.weekday <= DateTime.friday) {
        final startedAt = date.add(const Duration(hours: 19));
        batch.insert(
          database.workoutSessions,
          WorkoutSessionsCompanion.insert(
            id: 'session-$day',
            localDate: localDate,
            startedAt: startedAt,
            status: const Value('finished'),
            finishedAt: Value(startedAt.add(const Duration(hours: 1))),
            createdAt: startedAt,
            updatedAt: startedAt,
          ),
        );
        for (var set = 0; set < 15; set++) {
          batch.insert(
            database.workoutSets,
            WorkoutSetsCompanion.insert(
              id: 'set-$day-$set',
              sessionId: 'session-$day',
              exerciseId: 'exercise-${set % 20}',
              sortOrder: set,
              weightKg: 40.0 + set,
              reps: 8,
              completedAt: startedAt,
              createdAt: startedAt,
              updatedAt: startedAt,
            ),
          );
        }
      }
      // 3 餐，共 8 个条目（3+3+2）。
      const slots = ['breakfast', 'lunch', 'dinner'];
      const itemsPerSlot = [3, 3, 2];
      for (var slotIndex = 0; slotIndex < 3; slotIndex++) {
        final mealId = 'meal-${mealSeq++}';
        final eatenAt = date.add(Duration(hours: 8 + slotIndex * 5));
        batch.insert(
          database.meals,
          MealsCompanion.insert(
            id: mealId,
            localDate: localDate,
            slot: slots[slotIndex],
            eatenAt: eatenAt,
            source: 'manual',
            createdAt: eatenAt,
            updatedAt: eatenAt,
          ),
        );
        for (var item = 0; item < itemsPerSlot[slotIndex]; item++) {
          batch.insert(
            database.mealItems,
            MealItemsCompanion.insert(
              id: '$mealId-item-$item',
              mealId: mealId,
              foodNameSnapshot: '食物$item',
              grams: 100 + item * 10,
              kcalSnapshot: 120,
              proteinSnapshot: 8,
              carbsSnapshot: 15,
              fatSnapshot: 4,
              createdAt: eatenAt,
              updatedAt: eatenAt,
            ),
          );
        }
      }
    }
  });
}
