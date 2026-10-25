/// Rule-free aggregation of daily intake records into an honest trend view:
/// averages use only tracked days, and goal achievement is only reported
/// when an active calorie goal exists.
///
/// 2026-10-23：`goalDaysMet` 按「未超上限」（`kcal <= max`）计，与
/// `buildCalorieTrendBars.hitCount` 同一口径；`CalorieRange.minKcal` 仍保留，
/// 供「低于下限」的单独提示使用，不参与达标判定。
final class TrendCalculator {
  const TrendCalculator();

  IntakeTrend calculate({
    required List<DailyIntakeRecord> records,
    required CalorieRange? goal,
  }) {
    final tracked = records.length;
    if (tracked == 0) {
      return IntakeTrend(
        trackedDays: 0,
        averageKcal: null,
        averageMacros: null,
        goalDaysMet: null,
      );
    }
    double average(double Function(DailyIntakeRecord record) select) =>
        records.fold<double>(0, (sum, record) => sum + select(record)) /
        tracked;
    return IntakeTrend(
      trackedDays: tracked,
      averageKcal: average((record) => record.kcal),
      averageMacros: MacroAverages(
        proteinGrams: average((record) => record.proteinGrams),
        carbsGrams: average((record) => record.carbsGrams),
        fatGrams: average((record) => record.fatGrams),
      ),
      goalDaysMet: goal == null
          ? null
          : records.where((record) => record.kcal <= goal.maxKcal).length,
      records: records,
    );
  }
}

final class DailyIntakeRecord {
  const DailyIntakeRecord({
    required this.localDate,
    required this.kcal,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  final String localDate;
  final double kcal;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
}

final class CalorieRange {
  const CalorieRange({required this.minKcal, required this.maxKcal});

  final double minKcal;
  final double maxKcal;
}

final class MacroAverages {
  const MacroAverages({
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
}

final class IntakeTrend {
  const IntakeTrend({
    required this.trackedDays,
    required this.averageKcal,
    required this.averageMacros,
    required this.goalDaysMet,
    this.records = const [],
  });

  final int trackedDays;
  final double? averageKcal;
  final MacroAverages? averageMacros;
  final int? goalDaysMet;

  /// 窗口内逐日明细（按 localDate 升序），供上层做训练日关联等二次聚合。
  final List<DailyIntakeRecord> records;
}
