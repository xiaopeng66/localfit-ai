import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';

final class TrainingStatsCalculator {
  const TrainingStatsCalculator();

  /// Total volume (kg lifted) across finished sessions only.
  double weeklyVolumeKg(Iterable<WorkoutSessionRecord> sessions) => sessions
      .where((session) => session.status == 'finished')
      .fold(0, (total, session) => total + session.totalVolumeKg);

  /// The heaviest finished set per exercise; ties are broken by repetitions.
  /// Ordered from heaviest record to lightest.
  List<PersonalRecord> personalRecords(
    Iterable<WorkoutSessionRecord> sessions,
  ) {
    final bestByExercise = <String, PersonalRecord>{};
    for (final session in sessions) {
      if (session.status != 'finished') continue;
      for (final set in session.sets) {
        final current = bestByExercise[set.exerciseId];
        final isBetter =
            current == null ||
            set.weightKg > current.weightKg ||
            (set.weightKg == current.weightKg && set.reps > current.reps);
        if (isBetter) {
          bestByExercise[set.exerciseId] = PersonalRecord(
            exerciseId: set.exerciseId,
            exerciseName: set.exerciseName,
            weightKg: set.weightKg,
            reps: set.reps,
            achievedAt: set.completedAt,
          );
        }
      }
    }
    final records = bestByExercise.values.toList(growable: false)
      ..sort((a, b) => b.weightKg.compareTo(a.weightKg));
    return records;
  }

  /// Completion of a plan's scheduled weekdays inside the week starting at
  /// [weekStart]. Weekdays after [today] are not yet due. Returns null when no
  /// scheduled day has come due in that week.
  WeeklyCompletion? weeklyCompletion({
    required String planId,
    required List<int> planWeekdays,
    required DateTime weekStart,
    required DateTime today,
    required List<WorkoutSessionRecord> finishedSessions,
  }) {
    final monday = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final todayDate = DateTime(today.year, today.month, today.day);
    final completedDates = {
      for (final session in finishedSessions)
        if (session.status == 'finished' &&
            session.planId == planId &&
            planWeekdays.contains(weekdayOfLocalDate(session.localDate)))
          session.localDate,
    };
    var scheduledDays = 0;
    var completedDays = 0;
    for (var offset = 0; offset < 7; offset++) {
      final date = monday.add(Duration(days: offset));
      if (!planWeekdays.contains(date.weekday)) continue;
      if (date.isAfter(todayDate)) continue;
      scheduledDays++;
      if (completedDates.contains(_format(date))) completedDays++;
    }
    if (scheduledDays == 0) return null;
    return WeeklyCompletion(
      scheduledDays: scheduledDays,
      completedDays: completedDays,
    );
  }

  /// 训练趋势 (training trend): weekly volume over the last [weeks] weeks.
  ///
  /// 返回**按时间升序**的列表（index 0 = 最早的周，末位 = 本周），趋势图
  /// 从左到右读才成立。空输入 → 全零。
  ///
  /// 分桶按「距 [endOfLatestWeek] 的周数差」而不是年的第几周：后者在跨年
  /// 时会把第 1 周排到第 52 周前面，图表会突然断崖。周起点固定为周一。
  List<double> trainingTrendWeeklyVolume({
    required Iterable<WorkoutSessionRecord> sessions,
    required DateTime endOfLatestWeek,
    required int weeks,
  }) {
    final result = List<double>.filled(weeks, 0.0);
    if (weeks <= 0 || sessions.isEmpty) return result;

    // 本周周一的零点：所有分桶都以它为零点。
    final endDate = DateTime(
      endOfLatestWeek.year,
      endOfLatestWeek.month,
      endOfLatestWeek.day,
    );
    final latestMonday = endDate.subtract(Duration(days: endDate.weekday - 1));

    for (final session in sessions) {
      if (session.status != 'finished') continue;
      final parsed = _parseLocalDate(session.localDate);
      if (parsed == null) continue;
      final monday = parsed.subtract(Duration(days: parsed.weekday - 1));
      final weeksAgo = latestMonday.difference(monday).inDays ~/ 7;
      // 超出窗口（含未来日期）的记录不参与，也不折进边缘那周。
      if (weeksAgo < 0 || weeksAgo >= weeks) continue;
      var weeklyVolume = 0.0;
      for (final set in session.sets) {
        weeklyVolume += set.weightKg * set.reps;
      }
      // weeksAgo = 0 是本周 → 落在末位；越早的记录 index 越小。
      result[weeks - 1 - weeksAgo] += weeklyVolume;
    }
    return result;
  }

  /// 按星期几（1=周一 .. 7=周日）统计已结束训练的组数。
  ///
  /// 用于训练页周容量柱状图（匹配 HTML 的 weekly capacity bar chart）。
  /// 返回 Map<星期, setCount>，未打卡的日期不在 map 中。
  /// 使用 weekday 作为 key 而非字符串日期：调用方只需按
  /// 1..7 索引到柱子，无需再做日期解析。
  Map<int, int> weekdayDistribution(Iterable<WorkoutSessionRecord> sessions) {
    final counts = <int, int>{};
    for (final session in sessions) {
      if (session.status != 'finished') continue;
      final parsed = _parseLocalDate(session.localDate);
      if (parsed == null) continue;
      final weekday = parsed.weekday;
      counts[weekday] = (counts[weekday] ?? 0) + session.sets.length;
    }
    return counts;
  }

  /// 肌群分布 (muscle group distribution): total volume per MuscleGroup.
  Map<MuscleGroup, double> muscleGroupDistribution({
    required Iterable<WorkoutSessionRecord> sessions,
    required Iterable<ExerciseRecord> exercises,
  }) {
    final exerciseMap = {for (final e in exercises) e.id: e};
    final distribution = <MuscleGroup, double>{};
    for (final session in sessions) {
      if (session.status != 'finished') continue;
      for (final set in session.sets) {
        final exercise = exerciseMap[set.exerciseId];
        if (exercise == null) continue;
        final volume = set.weightKg * set.reps;
        distribution[exercise.muscleGroup] =
            (distribution[exercise.muscleGroup] ?? 0) + volume;
      }
    }
    return distribution;
  }

  /// 常用动作 (most-used exercises): top N by set count.
  List<MostUsedExercise> mostUsedExercises({
    required Iterable<WorkoutSessionRecord> sessions,
    required int limit,
  }) {
    final counts = <String, MostUsedExerciseEntry>{};
    for (final session in sessions) {
      if (session.status != 'finished') continue;
      for (final set in session.sets) {
        final entry = counts.putIfAbsent(
          set.exerciseId,
          () => MostUsedExerciseEntry(
            exerciseId: set.exerciseId,
            exerciseName: set.exerciseName,
            setCount: 0,
            volume: 0.0,
          ),
        );
        entry.setCount++;
        entry.volume += set.weightKg * set.reps;
      }
    }
    final sorted = counts.values.toList()
      ..sort((a, b) => b.setCount.compareTo(a.setCount));
    final result = <MostUsedExercise>[];
    for (var i = 0; i < sorted.length && i < limit; i++) {
      final entry = sorted[i];
      result.add(
        MostUsedExercise(
          exerciseId: entry.exerciseId,
          exerciseName: entry.exerciseName,
          setCount: entry.setCount,
          volume: entry.volume,
        ),
      );
    }
    return result;
  }

  DateTime? _parseLocalDate(String dateStr) {
    final match = _localDatePattern.firstMatch(dateStr);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    return DateTime(year, month, day);
  }

  String _format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// `YYYY-MM-DD` 形状检查。放在顶层：`RegExp` 不是常量表达式，做成字段会
/// 让 `TrainingStatsCalculator` 失去 const 构造，连带打断全仓十几处
/// `const TrainingStatsCalculator()` 调用点。
final RegExp _localDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

final class PersonalRecord {
  const PersonalRecord({
    required this.exerciseId,
    required this.exerciseName,
    required this.weightKg,
    required this.reps,
    required this.achievedAt,
  });

  final String exerciseId;
  final String exerciseName;
  final double weightKg;
  final int reps;
  final DateTime achievedAt;
}

final class WeeklyCompletion {
  const WeeklyCompletion({
    required this.scheduledDays,
    required this.completedDays,
  });

  final int scheduledDays;
  final int completedDays;

  double get ratio => completedDays / scheduledDays;
}

class MostUsedExerciseEntry {
  final String exerciseId;
  final String exerciseName;
  int setCount;
  double volume;

  MostUsedExerciseEntry({
    required this.exerciseId,
    required this.exerciseName,
    required this.setCount,
    required this.volume,
  });
}

class MostUsedExercise {
  final String exerciseId;
  final String exerciseName;
  final int setCount;
  final double volume;

  MostUsedExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.setCount,
    required this.volume,
  });
}
