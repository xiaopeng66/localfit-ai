import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/training/data/workout_plan_json_decoder.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

void main() {
  const decoder = WorkoutPlanJsonDecoder();

  AiWorkoutPlanRequest request() => const AiWorkoutPlanRequest(
    daysPerWeek: 2,
    goalText: '增肌',
    exercises: [
      ExerciseOption(id: 'ex-barbell-squat', name: '杠铃深蹲'),
      ExerciseOption(id: 'ex-bench', name: '杠铃卧推'),
      ExerciseOption(id: 'ex-plank', name: '平板支撑'),
    ],
  );

  String validJson() =>
      '{"schema_version":1,"name":"AI 三分化","days":['
      '{"weekday":1,"exercises":[{"exercise_id":"ex-barbell-squat","target_sets":4,"target_reps":8,"target_weight_kg":60}]},'
      '{"weekday":3,"exercises":[{"exercise_id":"ex-plank","target_sets":3,"target_reps":60}]}],'
      '"warnings":["为未核验草案"]}';

  test('decodes a valid draft with local exercise ids only', () {
    final draft = decoder.decode(validJson(), request());

    expect(draft.name, 'AI 三分化');
    expect(draft.days, hasLength(2));
    expect(draft.days.first.weekday, 1);
    expect(draft.days.first.entries.single.exerciseId, 'ex-barbell-squat');
    expect(draft.days.first.entries.single.targetWeightKg, 60);
    expect(draft.warnings.single, '为未核验草案');
  });

  test('rejects an exercise id outside the local library', () {
    final json = validJson().replaceFirst('ex-plank', 'ex-unknown');

    expect(
      () => decoder.decode(json, request()),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('不存在的动作'),
        ),
      ),
    );
  });

  for (final (label, json) in <(String, String)>[
    ('missing schema version', '{"name":"x","days":[],"warnings":[]}'),
    (
      'wrong day count',
      '{"schema_version":1,"name":"x","days":[{"weekday":1,"exercises":[{"exercise_id":"ex-plank","target_sets":1,"target_reps":1}]}],"warnings":[]}',
    ),
    (
      'duplicate weekday',
      '{"schema_version":1,"name":"x","days":[{"weekday":2,"exercises":[{"exercise_id":"ex-plank","target_sets":1,"target_reps":1}]},{"weekday":2,"exercises":[{"exercise_id":"ex-plank","target_sets":1,"target_reps":1}]}],"warnings":[]}',
    ),
    (
      'zero sets',
      '{"schema_version":1,"name":"x","days":[{"weekday":1,"exercises":[{"exercise_id":"ex-plank","target_sets":0,"target_reps":1}]}],"warnings":[]}',
    ),
    (
      'negative weight',
      '{"schema_version":1,"name":"x","days":[{"weekday":1,"exercises":[{"exercise_id":"ex-plank","target_sets":1,"target_reps":1,"target_weight_kg":-2}]}],"warnings":[]}',
    ),
    ('empty name', '{"schema_version":1,"name":" ","days":[],"warnings":[]}'),
  ]) {
    test('rejects $label', () {
      expect(() => decoder.decode(json, request()), throwsFormatException);
    });
  }
}
