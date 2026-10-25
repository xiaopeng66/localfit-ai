import 'dart:convert';

import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// Strict decoder for AI workout-plan schema v1. The whole draft is rejected
/// when any referenced exercise id is not part of the request's local library.
final class WorkoutPlanJsonDecoder {
  const WorkoutPlanJsonDecoder();

  static const maxDays = 7;
  static const maxExercisesPerDay = 12;
  static const maxNameLength = 60;
  static const maxWarnings = 10;
  static const maxSets = 20;
  static const maxReps = 100;
  static const maxWeightKg = 500;

  AiWorkoutPlanDraft decode(String content, AiWorkoutPlanRequest request) {
    final document = _decodeJson(content);
    if (document is! Map<Object?, Object?>) throw _invalid();
    if (document['schema_version'] != 1) throw _invalid();

    final name = document['name'];
    if (name is! String || name.trim().isEmpty || name.length > maxNameLength) {
      throw _invalid();
    }

    final knownIds = request.exercises.map((exercise) => exercise.id).toSet();
    final daysRaw = document['days'];
    if (daysRaw is! List || daysRaw.isEmpty || daysRaw.length > maxDays) {
      throw _invalid();
    }
    if (daysRaw.length != request.daysPerWeek) {
      throw _invalid();
    }
    final weekdays = <int>{};
    final days = <AiWorkoutPlanDayDraft>[];
    for (final dayRaw in daysRaw) {
      if (dayRaw is! Map<Object?, Object?>) throw _invalid();
      final weekday = dayRaw['weekday'];
      if (weekday is! int || weekday < 1 || weekday > 7) throw _invalid();
      if (!weekdays.add(weekday)) throw _invalid();
      final entriesRaw = dayRaw['exercises'];
      if (entriesRaw is! List ||
          entriesRaw.isEmpty ||
          entriesRaw.length > maxExercisesPerDay) {
        throw _invalid();
      }
      final entries = <PlannedExerciseDraft>[];
      for (final entryRaw in entriesRaw) {
        if (entryRaw is! Map<Object?, Object?>) throw _invalid();
        final exerciseId = entryRaw['exercise_id'];
        if (exerciseId is! String || !knownIds.contains(exerciseId)) {
          throw const FormatException('AI 草案引用了本地动作库中不存在的动作，已拒绝整份草案。');
        }
        final targetSets = entryRaw['target_sets'];
        final targetReps = entryRaw['target_reps'];
        if (targetSets is! int ||
            targetSets < 1 ||
            targetSets > maxSets ||
            targetReps is! int ||
            targetReps < 1 ||
            targetReps > maxReps) {
          throw _invalid();
        }
        final targetWeight = entryRaw['target_weight_kg'];
        double? targetWeightKg;
        if (targetWeight != null) {
          if (targetWeight is! num ||
              targetWeight < 0 ||
              targetWeight > maxWeightKg) {
            throw _invalid();
          }
          targetWeightKg = targetWeight.toDouble();
        }
        entries.add(
          PlannedExerciseDraft(
            exerciseId: exerciseId,
            targetSets: targetSets,
            targetReps: targetReps,
            targetWeightKg: targetWeightKg,
          ),
        );
      }
      days.add(AiWorkoutPlanDayDraft(weekday: weekday, entries: entries));
    }

    final warningsRaw = document['warnings'];
    final warnings = <String>[];
    if (warningsRaw is! List || warningsRaw.length > maxWarnings) {
      throw _invalid();
    }
    for (final warning in warningsRaw) {
      if (warning is! String || warning.isEmpty || warning.length > 200) {
        throw _invalid();
      }
      warnings.add(warning);
    }

    return AiWorkoutPlanDraft(
      name: name.trim(),
      days: days,
      warnings: List.unmodifiable(warnings),
    );
  }

  FormatException _invalid() =>
      const FormatException('AI 训练计划草案不符合 schema-v1，已拒绝。');

  Object? _decodeJson(String content) {
    try {
      return jsonDecode(content);
    } on FormatException {
      throw _invalid();
    }
  }
}
