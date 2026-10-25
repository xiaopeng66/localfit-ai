import 'package:localfit_ai/core/time/local_date.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';

final class WorkoutSetDraft {
  const WorkoutSetDraft({
    this.plannedExerciseId,
    required this.exerciseId,
    required this.weightKg,
    required this.reps,
    this.rpe,
  });

  final String? plannedExerciseId;
  final String exerciseId;
  final double weightKg;
  final int reps;
  final double? rpe;
}

final class WorkoutSetRecord {
  const WorkoutSetRecord({
    required this.id,
    required this.sessionId,
    required this.plannedExerciseId,
    required this.exerciseId,
    required this.exerciseName,
    required this.equipment,
    required this.sortOrder,
    required this.weightKg,
    required this.reps,
    required this.rpe,
    required this.completedAt,
  });

  final String id;
  final String sessionId;
  final String? plannedExerciseId;
  final String exerciseId;
  final String exerciseName;
  final Equipment equipment;
  final int sortOrder;
  final double weightKg;
  final int reps;
  final double? rpe;
  final DateTime completedAt;
}

final class WorkoutSessionRecord {
  const WorkoutSessionRecord({
    required this.id,
    required this.planId,
    required this.localDate,
    required this.startedAt,
    required this.finishedAt,
    required this.status,
    required this.sets,
  });

  final String id;
  final String? planId;
  final String localDate;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String status;
  final List<WorkoutSetRecord> sets;

  bool get isActive => status == 'active';

  double get totalVolumeKg =>
      sets.fold(0, (total, set) => total + set.weightKg * set.reps);

  int get completedSetCount => sets.length;
}

/// Remaining seconds on a rest countdown, computed from wall-clock timestamps
/// so the value stays correct after the app resumes from the background.
int restSecondsRemaining(DateTime restEnd, DateTime now) {
  final remaining = restEnd.difference(now).inSeconds;
  return remaining < 0 ? 0 : remaining;
}

/// Weekday (1 = Monday) of a stored `YYYY-MM-DD` date, or null when the text
/// is not a valid calendar date.
///
/// `local_date` columns carry no format constraint, and restoring a backup
/// validates only the JSON shape, never field values (docs/11 §3-F), so a
/// malformed date can reach the database. Read paths run during `build`:
/// throwing there blanks the whole page on every visit, so they degrade to
/// "no weekday" instead.
///
/// 日期合法性判断来自共享的 [isValidIsoLocalDate]（core/time 单一事实源，
/// 恢复侧校验用同一份判据，两边不许漂移）。
int? weekdayOfLocalDate(String localDate) {
  if (!isValidIsoLocalDate(localDate)) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(localDate)!;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  return DateTime(year, month, day).weekday;
}
