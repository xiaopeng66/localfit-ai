import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/training/data/workout_plan_json_decoder.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// Field-level numeric edge tests for the frozen workout-plan.v1 decoder.
/// Field semantics: sets/reps are minInclusive(1); weight is optional
/// minInclusive(0)/maxInclusive(500); weekday is 1..7.
void main() {
  const decoder = WorkoutPlanJsonDecoder();

  // Static boundary constants of the frozen v1 contract.
  const maxSets = WorkoutPlanJsonDecoder.maxSets;
  const maxReps = WorkoutPlanJsonDecoder.maxReps;
  const maxWeightKg = WorkoutPlanJsonDecoder.maxWeightKg;
  const maxNameLength = WorkoutPlanJsonDecoder.maxNameLength;
  const maxExercisesPerDay = WorkoutPlanJsonDecoder.maxExercisesPerDay;
  const maxWarnings = WorkoutPlanJsonDecoder.maxWarnings;

  AiWorkoutPlanRequest request() => const AiWorkoutPlanRequest(
    daysPerWeek: 1,
    goalText: '增肌',
    exercises: [ExerciseOption(id: 'ex-plank', name: '平板支撑')],
  );

  String plan({
    String sets = '3',
    String reps = '12',
    String? weight,
    String weekday = '1',
  }) {
    final weightText = weight == null ? '' : ',"target_weight_kg":$weight';
    return '{"schema_version":1,"name":"计划","days":[{"weekday":$weekday,"exercises":[{"exercise_id":"ex-plank","target_sets":$sets,"target_reps":$reps$weightText}]}],"warnings":[]}';
  }

  group('numeric field edges', () {
    test('accepts the minimum sets and reps (minInclusive 1)', () {
      final draft = decoder.decode(plan(sets: '1', reps: '1'), request());
      expect(draft.days.single.entries.single.targetSets, 1);
      expect(draft.days.single.entries.single.targetReps, 1);
    });

    test('accepts the exact maxima', () {
      final draft = decoder.decode(
        plan(sets: '$maxSets', reps: '$maxReps'),
        request(),
      );
      expect(draft.days.single.entries.single.targetSets, maxSets);
      expect(draft.days.single.entries.single.targetReps, maxReps);
    });

    for (final (label, document) in [
      ('zero sets', plan(sets: '0')),
      ('negative sets', plan(sets: '-1')),
      ('zero reps', plan(reps: '0')),
      ('reps beyond max', plan(reps: '${maxReps + 1}')),
      ('sets beyond max', plan(sets: '${maxSets + 1}')),
      ('float sets', plan(sets: '3.0')),
      ('string sets', plan(sets: '"3"')),
      ('NaN reps', plan(reps: 'NaN')),
      ('Infinity reps', plan(reps: 'Infinity')),
      ('negative weight', plan(weight: '-0.5')),
      ('weight beyond max', plan(weight: '${maxWeightKg + 1}')),
      ('NaN weight', plan(weight: 'NaN')),
      ('Infinity weight', plan(weight: 'Infinity')),
      ('string weight', plan(weight: '"60"')),
      ('weekday zero', plan(weekday: '0')),
      ('weekday eight', plan(weekday: '8')),
    ]) {
      test('rejects $label', () {
        expect(
          () => decoder.decode(document, request()),
          throwsFormatException,
        );
      });
    }

    test('accepts optional weight of exactly 0 and at the maximum', () {
      final zero = decoder.decode(plan(weight: '0'), request());
      expect(zero.days.single.entries.single.targetWeightKg, 0);

      final atMax = decoder.decode(plan(weight: '$maxWeightKg'), request());
      expect(atMax.days.single.entries.single.targetWeightKg, maxWeightKg);
    });

    test('accepts a missing optional weight as null', () {
      final draft = decoder.decode(plan(), request());
      expect(draft.days.single.entries.single.targetWeightKg, isNull);
    });
  });

  group('text and array edges', () {
    test('accepts a name at exactly the maximum length', () {
      final atMax = '练' * maxNameLength;
      final document =
          '{"schema_version":1,"name":"$atMax","days":[{"weekday":1,"exercises":[{"exercise_id":"ex-plank","target_sets":1,"target_reps":1}]}],"warnings":[]}';
      final draft = decoder.decode(document, request());
      expect(draft.name, atMax);
    });

    test('rejects an empty name', () {
      final document =
          '{"schema_version":1,"name":" ","days":[{"weekday":1,"exercises":[{"exercise_id":"ex-plank","target_sets":1,"target_reps":1}]}],"warnings":[]}';
      expect(() => decoder.decode(document, request()), throwsFormatException);
    });

    test('rejects exercise entries beyond the per-day limit', () {
      final entries = List.filled(
        maxExercisesPerDay + 1,
        '{"exercise_id":"ex-plank","target_sets":1,"target_reps":1}',
      ).join(',');
      final document =
          '{"schema_version":1,"name":"计划","days":[{"weekday":1,"exercises":[$entries]}],"warnings":[]}';
      expect(() => decoder.decode(document, request()), throwsFormatException);
    });

    test('rejects warnings beyond the limit or over-long warnings', () {
      final tooMany = List.filled(maxWarnings + 1, '"x"').join(',');
      final count =
          '{"schema_version":1,"name":"计划","days":[{"weekday":1,"exercises":[{"exercise_id":"ex-plank","target_sets":1,"target_reps":1}]}],"warnings":[$tooMany]}';
      expect(() => decoder.decode(count, request()), throwsFormatException);

      final tooLong =
          '{"schema_version":1,"name":"计划","days":[{"weekday":1,"exercises":[{"exercise_id":"ex-plank","target_sets":1,"target_reps":1}]}],"warnings":["${'长' * 201}"]}';
      expect(() => decoder.decode(tooLong, request()), throwsFormatException);
    });
  });
}
