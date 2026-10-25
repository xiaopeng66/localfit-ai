import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';

enum ProgressionAction { increase, hold, deload, noHistory }

final class ProgressionSuggestion {
  const ProgressionSuggestion({
    required this.exerciseId,
    required this.exerciseName,
    required this.action,
    required this.message,
    this.suggestedWeightKg,
  });

  final String exerciseId;
  final String exerciseName;
  final ProgressionAction action;
  final String message;
  final double? suggestedWeightKg;
}

/// Rule-based, conservative progression hints derived only from local
/// finished-session history. Suggestions are informational and never
/// instructions; pain feedback always takes precedence via the safety flow.
final class ProgressionAdvisor {
  const ProgressionAdvisor();

  static const _incrementByEquipment = {
    Equipment.barbell: 2.5,
    Equipment.dumbbell: 2.0,
    Equipment.machine: 5.0,
    Equipment.cable: 5.0,
    Equipment.other: 0.0,
  };

  List<ProgressionSuggestion> advise({
    required WorkoutSessionRecord session,
    required List<WorkoutSessionRecord> previousSessions,
  }) {
    final history = previousSessions
        .where((candidate) => candidate.status == 'finished')
        .toList(growable: false);
    final bestByExercise = <String, WorkoutSetRecord>{};
    for (final candidate in history) {
      for (final set in candidate.sets) {
        final current = bestByExercise[set.exerciseId];
        final isBetter =
            current == null ||
            set.weightKg > current.weightKg ||
            (set.weightKg == current.weightKg && set.reps > current.reps);
        if (isBetter) bestByExercise[set.exerciseId] = set;
      }
    }

    final byExercise = <String, List<WorkoutSetRecord>>{};
    for (final set in session.sets) {
      byExercise.putIfAbsent(set.exerciseId, () => []).add(set);
    }

    final suggestions = <ProgressionSuggestion>[];
    for (final entry in byExercise.entries) {
      final sets = entry.value;
      final best = _bestSet(sets);
      if (best == null) continue;
      final previous = bestByExercise[entry.key];
      if (previous == null) {
        suggestions.add(
          ProgressionSuggestion(
            exerciseId: entry.key,
            exerciseName: best.exerciseName,
            action: ProgressionAction.noHistory,
            message: '暂无历史对比，建议先保持当前负荷完成 2 次训练再评估。',
          ),
        );
        continue;
      }
      final improved =
          best.weightKg > previous.weightKg ||
          (best.weightKg == previous.weightKg && best.reps > previous.reps);
      final nearFailure = sets.any((set) => set.rpe != null && set.rpe! >= 9.5);
      final regressed =
          best.weightKg < previous.weightKg ||
          (best.weightKg == previous.weightKg && best.reps < previous.reps);
      suggestions.add(
        _suggest(
          exerciseId: entry.key,
          best: best,
          previous: previous,
          improved: improved,
          regressed: regressed,
          nearFailure: nearFailure,
        ),
      );
    }
    return suggestions;
  }

  ProgressionSuggestion _suggest({
    required String exerciseId,
    required WorkoutSetRecord best,
    required WorkoutSetRecord previous,
    required bool improved,
    required bool regressed,
    required bool nearFailure,
  }) {
    if (best.equipment == Equipment.bodyweight) {
      if (improved && !nearFailure) {
        return ProgressionSuggestion(
          exerciseId: exerciseId,
          exerciseName: best.exerciseName,
          action: ProgressionAction.increase,
          message: '自重表现稳定，可尝试每组增加 1 次或放慢动作节奏。',
        );
      }
      return ProgressionSuggestion(
        exerciseId: exerciseId,
        exerciseName: best.exerciseName,
        action: ProgressionAction.hold,
        message: '建议保持当前次数，稳定后再增加。',
      );
    }
    final increment = _incrementByEquipment[best.equipment] ?? 0.0;
    if (improved && !nearFailure && increment > 0) {
      final suggested = best.weightKg + increment;
      return ProgressionSuggestion(
        exerciseId: exerciseId,
        exerciseName: best.exerciseName,
        action: ProgressionAction.increase,
        suggestedWeightKg: suggested,
        message: '表现稳定，下次可尝试 ${_weightText(suggested)}kg；如无把握保持即可。',
      );
    }
    if (improved && nearFailure) {
      return ProgressionSuggestion(
        exerciseId: exerciseId,
        exerciseName: best.exerciseName,
        action: ProgressionAction.hold,
        message: '重量已有提升但接近力竭，建议保持当前重量巩固。',
      );
    }
    if (regressed) {
      return ProgressionSuggestion(
        exerciseId: exerciseId,
        exerciseName: best.exerciseName,
        action: ProgressionAction.hold,
        message: '本次表现未超过上次，建议保持或小幅降低重量，优先恢复状态。',
      );
    }
    return ProgressionSuggestion(
      exerciseId: exerciseId,
      exerciseName: best.exerciseName,
      action: ProgressionAction.hold,
      message: '与上次持平，保持当前负荷即可。',
    );
  }

  WorkoutSetRecord? _bestSet(List<WorkoutSetRecord> sets) {
    WorkoutSetRecord? best;
    for (final set in sets) {
      final isBetter =
          best == null ||
          set.weightKg > best.weightKg ||
          (set.weightKg == best.weightKg && set.reps > best.reps);
      if (isBetter) best = set;
    }
    return best;
  }

  String _weightText(double weight) =>
      weight == weight.roundToDouble() ? weight.toStringAsFixed(1) : '$weight';
}
