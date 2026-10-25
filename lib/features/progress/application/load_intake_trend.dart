import 'package:drift/drift.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// Loads the honest intake trend for the last [days] local days, using the
/// latest active goal (if any) for goal-achievement reporting.
final class LoadIntakeTrend {
  const LoadIntakeTrend({
    required this.database,
    required this.mealRepository,
    required this.clock,
  });

  final AppDatabase database;
  final MealRepository mealRepository;
  final AppClock clock;

  /// [endDate] 缺省取时钟当天。显式传入是为了让**同一页面的多个消费者**
  /// 共用同一个窗口——趋势柱图与营养分析卡各取一次 `now` 时，跨零点那一下
  /// 会让两张卡差一天。
  Future<IntakeTrend> run({required int days, DateTime? endDate}) async {
    final today = endDate ?? clock.nowUtc().toLocal();
    final end = DateTime(today.year, today.month, today.day);
    final start = end.subtract(Duration(days: days - 1));
    final records = await mealRepository.listDailyIntakeBetween(
      _format(start),
      _format(end),
    );
    final goal = await _activeCalorieGoal();
    return const TrendCalculator().calculate(
      records: records
          .map(
            (record) => DailyIntakeRecord(
              localDate: record.localDate,
              kcal: record.nutrition.kcal,
              proteinGrams: record.nutrition.proteinGrams,
              carbsGrams: record.nutrition.carbsGrams,
              fatGrams: record.nutrition.fatGrams,
            ),
          )
          .toList(growable: false),
      goal: goal,
    );
  }

  Future<CalorieRange?> _activeCalorieGoal() async {
    final row =
        await (database.select(database.goals)
              ..where((goal) => goal.status.equals('active'))
              ..orderBy([(goal) => OrderingTerm.desc(goal.effectiveFrom)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return CalorieRange(
      minKcal: row.calorieMinKcal,
      maxKcal: row.calorieMaxKcal,
    );
  }

  String _format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
