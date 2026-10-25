import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/training/application/progression_advisor.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';

WorkoutSetRecord setRecord(
  String exerciseId,
  String exerciseName,
  Equipment equipment,
  double weightKg,
  int reps, {
  double? rpe,
}) => WorkoutSetRecord(
  id: 'set-$exerciseId-$weightKg-$reps-${rpe ?? ''}',
  sessionId: 'session-current',
  plannedExerciseId: null,
  exerciseId: exerciseId,
  exerciseName: exerciseName,
  equipment: equipment,
  sortOrder: 0,
  weightKg: weightKg,
  reps: reps,
  rpe: rpe,
  completedAt: DateTime.utc(2026, 9, 12, 18),
);

WorkoutSessionRecord session({
  required String id,
  String status = 'finished',
  required List<WorkoutSetRecord> sets,
}) => WorkoutSessionRecord(
  id: id,
  planId: null,
  localDate: '2026-09-12',
  startedAt: DateTime.utc(2026, 9, 12, 17),
  finishedAt: status == 'finished' ? DateTime.utc(2026, 9, 12, 18) : null,
  status: status,
  sets: sets,
);

void main() {
  const advisor = ProgressionAdvisor();

  test('reports no history when the exercise has no previous best', () {
    final current = session(
      id: 'session-current',
      sets: [setRecord('ex-squat', '杠铃深蹲', Equipment.barbell, 60, 8)],
    );

    final suggestions = advisor.advise(
      session: current,
      previousSessions: const [],
    );

    expect(suggestions.single.action, ProgressionAction.noHistory);
    expect(suggestions.single.exerciseName, '杠铃深蹲');
    expect(suggestions.single.suggestedWeightKg, isNull);
  });

  test(
    'suggests a small increase when the best set improved without strain',
    () {
      final current = session(
        id: 'session-current',
        sets: [
          setRecord('ex-squat', '杠铃深蹲', Equipment.barbell, 62.5, 8, rpe: 7),
          setRecord('ex-press', '哑铃推举', Equipment.dumbbell, 20, 10),
        ],
      );
      final history = [
        session(
          id: 'session-old',
          sets: [
            setRecord('ex-squat', '杠铃深蹲', Equipment.barbell, 60, 8),
            setRecord('ex-press', '哑铃推举', Equipment.dumbbell, 20, 9),
          ],
        ),
      ];

      final suggestions = advisor.advise(
        session: current,
        previousSessions: history,
      );

      final squat = suggestions.singleWhere((s) => s.exerciseId == 'ex-squat');
      expect(squat.action, ProgressionAction.increase);
      expect(squat.suggestedWeightKg, 65);
      final press = suggestions.singleWhere((s) => s.exerciseId == 'ex-press');
      expect(press.action, ProgressionAction.increase);
      expect(press.suggestedWeightKg, 22);
    },
  );

  test('suggests holding weight when the top set reached RPE 10', () {
    final current = session(
      id: 'session-current',
      sets: [setRecord('ex-squat', '杠铃深蹲', Equipment.barbell, 70, 5, rpe: 10)],
    );
    final history = [
      session(
        id: 'session-old',
        sets: [setRecord('ex-squat', '杠铃深蹲', Equipment.barbell, 60, 8)],
      ),
    ];

    final suggestions = advisor.advise(
      session: current,
      previousSessions: history,
    );

    expect(suggestions.single.action, ProgressionAction.hold);
    expect(suggestions.single.suggestedWeightKg, isNull);
  });

  test('suggests holding or reducing when performance regressed', () {
    final current = session(
      id: 'session-current',
      sets: [setRecord('ex-squat', '杠铃深蹲', Equipment.barbell, 60, 6)],
    );
    final history = [
      session(
        id: 'session-old',
        sets: [setRecord('ex-squat', '杠铃深蹲', Equipment.barbell, 60, 8)],
      ),
    ];

    final suggestions = advisor.advise(
      session: current,
      previousSessions: history,
    );

    expect(suggestions.single.action, ProgressionAction.hold);
    expect(suggestions.single.suggestedWeightKg, isNull);
  });

  test('suggests repetitions for bodyweight exercises', () {
    final current = session(
      id: 'session-current',
      sets: [setRecord('ex-push-up', '俯卧撑', Equipment.bodyweight, 0, 15)],
    );
    final history = [
      session(
        id: 'session-old',
        sets: [setRecord('ex-push-up', '俯卧撑', Equipment.bodyweight, 0, 12)],
      ),
    ];

    final suggestions = advisor.advise(
      session: current,
      previousSessions: history,
    );

    expect(suggestions.single.action, ProgressionAction.increase);
    expect(suggestions.single.suggestedWeightKg, isNull);
  });

  test('ignores active sessions as history', () {
    final current = session(
      id: 'session-current',
      sets: [setRecord('ex-squat', '杠铃深蹲', Equipment.barbell, 60, 8)],
    );
    final activeHistory = [
      session(
        id: 'session-active',
        status: 'active',
        sets: [setRecord('ex-squat', '杠铃深蹲', Equipment.barbell, 100, 10)],
      ),
    ];

    final suggestions = advisor.advise(
      session: current,
      previousSessions: activeHistory,
    );

    expect(suggestions.single.action, ProgressionAction.noHistory);
  });
}
