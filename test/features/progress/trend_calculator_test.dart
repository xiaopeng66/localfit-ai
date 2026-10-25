import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

void main() {
  const calculator = TrendCalculator();

  test('averages intake and macros over tracked days only', () {
    final trend = calculator.calculate(
      records: const [
        DailyIntakeRecord(
          localDate: '2026-09-08',
          kcal: 1800,
          proteinGrams: 90,
          carbsGrams: 200,
          fatGrams: 50,
        ),
        DailyIntakeRecord(
          localDate: '2026-09-09',
          kcal: 2200,
          proteinGrams: 110,
          carbsGrams: 240,
          fatGrams: 70,
        ),
      ],
      goal: null,
    );

    expect(trend.trackedDays, 2);
    expect(trend.averageKcal, 2000);
    expect(trend.averageMacros!.proteinGrams, 100);
    expect(trend.averageMacros!.carbsGrams, 220);
    expect(trend.averageMacros!.fatGrams, 60);
    expect(trend.goalDaysMet, isNull);
    expect(trend.records, hasLength(2));
    expect(trend.records.first.localDate, '2026-09-08');
  });

  test('empty range reports null macros without crashing', () {
    final trend = calculator.calculate(records: const [], goal: null);

    expect(trend.averageMacros, isNull);
    expect(trend.records, isEmpty);
  });

  test('counts goal-met days within the active calorie range', () {
    final trend = calculator.calculate(
      records: const [
        DailyIntakeRecord(
          localDate: '2026-09-08',
          kcal: 1700,
          proteinGrams: 90,
          carbsGrams: 200,
          fatGrams: 50,
        ),
        DailyIntakeRecord(
          localDate: '2026-09-09',
          kcal: 1900,
          proteinGrams: 110,
          carbsGrams: 240,
          fatGrams: 70,
        ),
        DailyIntakeRecord(
          localDate: '2026-09-10',
          kcal: 2600,
          proteinGrams: 110,
          carbsGrams: 240,
          fatGrams: 70,
        ),
      ],
      goal: const CalorieRange(minKcal: 1600, maxKcal: 2000),
    );

    expect(trend.trackedDays, 3);
    expect(trend.goalDaysMet, 2);
  });

  test('below-min days still count as met (not exceeding the max)', () {
    // 2026-10-23：达标按「未超上限」判定，与分析卡 hitCount 同一口径。
    final trend = calculator.calculate(
      records: const [
        DailyIntakeRecord(
          localDate: '2026-09-08',
          kcal: 1000,
          proteinGrams: 60,
          carbsGrams: 120,
          fatGrams: 30,
        ),
        DailyIntakeRecord(
          localDate: '2026-09-09',
          kcal: 1900,
          proteinGrams: 110,
          carbsGrams: 240,
          fatGrams: 70,
        ),
        DailyIntakeRecord(
          localDate: '2026-09-10',
          kcal: 2100,
          proteinGrams: 110,
          carbsGrams: 240,
          fatGrams: 70,
        ),
      ],
      goal: const CalorieRange(minKcal: 1600, maxKcal: 2000),
    );

    expect(trend.goalDaysMet, 2);
  });

  test('handles an empty range as untracked', () {
    final trend = calculator.calculate(records: const [], goal: null);

    expect(trend.trackedDays, 0);
    expect(trend.averageKcal, isNull);
    expect(trend.goalDaysMet, isNull);
  });
}
