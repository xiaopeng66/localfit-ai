import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';

import '../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late WorkoutPlanRepository plans;
  late WorkoutSessionRepository sessions;
  late _SteppingClock clock;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    clock = _SteppingClock(DateTime.utc(2026, 9, 12, 10));
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: _Ids('plan'),
      clock: clock,
    );
    sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: _Ids('session'),
      clock: clock,
    );
  });

  tearDown(() => database.close());

  Future<String> seedPlan() => plans.create(
    const WorkoutPlanDraft(
      name: '下肢日',
      days: [
        WorkoutPlanDayDraft(
          weekday: 6,
          entries: [
            PlannedExerciseDraft(
              exerciseId: 'ex-barbell-squat',
              targetSets: 4,
              targetReps: 8,
              targetWeightKg: 60,
            ),
          ],
        ),
      ],
    ),
  );

  test('starts an active session and reloads it as resumable', () async {
    final planId = await seedPlan();
    final sessionId = await sessions.start(
      localDate: '2026-09-12',
      planId: planId,
    );

    final active = await sessions.getActive();
    expect(active, isNotNull);
    expect(active!.id, sessionId);
    expect(active.status, 'active');
    expect(active.planId, planId);
    expect(active.localDate, '2026-09-12');
    expect(active.sets, isEmpty);
    expect(
      (await sessions.getActive())!.startedAt.isAtSameMomentAs(clock.nowUtc()),
      isTrue,
    );
  });

  test('rejects a second active session without writing', () async {
    await sessions.start(localDate: '2026-09-12');

    await expectLater(
      sessions.start(localDate: '2026-09-12'),
      throwsStateError,
    );
    expect(await database.select(database.workoutSessions).get(), hasLength(1));
  });

  test('start 的日期口径与兄弟仓库对齐：只接受真实 ISO 本地日（P3）', () async {
    // 原先只查空串：`2026-2-3`、`not-a-date` 之类脏文本会直接落库，
    // 读取侧（周统计）要为它兜底。现在与 parseLocalDate/isValidIsoLocalDate
    // 同一判据，非 ISO / 假日历日期一律「训练日期无效。」且不写库。
    for (final badDate in ['2026-2-3', 'not-a-date', '2026-02-31', '   ']) {
      await expectLater(
        sessions.start(localDate: badDate),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            '训练日期无效。',
          ),
        ),
        reason: '$badDate 应被拒绝',
      );
    }
    expect(await database.select(database.workoutSessions).get(), isEmpty);
  });

  test('logs sets with sequential order and joined exercise names', () async {
    final sessionId = await sessions.start(localDate: '2026-09-12');

    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );
    clock.elapsed(const Duration(minutes: 2));
    await sessions.logSet(
      sessionId,
      WorkoutSetDraft(
        exerciseId: 'ex-leg-press',
        weightKg: 80,
        reps: 10,
        rpe: 7.5,
      ),
    );

    final session = (await sessions.getById(sessionId))!;
    expect(session.sets.map((set) => set.sortOrder), [0, 1]);
    expect(session.sets.map((set) => set.exerciseName), ['杠铃深蹲', '腿举']);
    expect(session.sets.last.rpe, 7.5);
    expect(
      session.sets.last.completedAt.isAtSameMomentAs(clock.nowUtc()),
      isTrue,
    );
  });

  test('rejects invalid set data without writing', () async {
    final sessionId = await sessions.start(localDate: '2026-09-12');

    for (final invalid in <WorkoutSetDraft>[
      const WorkoutSetDraft(exerciseId: 'ex-missing', weightKg: 60, reps: 8),
      const WorkoutSetDraft(exerciseId: 'ex-plank', weightKg: -1, reps: 8),
      const WorkoutSetDraft(exerciseId: 'ex-plank', weightKg: 0, reps: 0),
      WorkoutSetDraft(exerciseId: 'ex-plank', weightKg: 20, reps: 10, rpe: 11),
    ]) {
      await expectLater(
        sessions.logSet(sessionId, invalid),
        throwsFormatException,
      );
    }
    expect(await database.select(database.workoutSets).get(), isEmpty);
  });

  test('finishes a session and clears the resumable state', () async {
    final sessionId = await sessions.start(localDate: '2026-09-12');
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(exerciseId: 'ex-plank', weightKg: 0, reps: 60),
    );

    clock.elapsed(const Duration(minutes: 30));
    await sessions.finish(sessionId);

    expect(await sessions.getActive(), isNull);
    final finished = (await sessions.getById(sessionId))!;
    expect(finished.status, 'finished');
    expect(finished.finishedAt!.isAtSameMomentAs(clock.nowUtc()), isTrue);
    await expectLater(sessions.finish(sessionId), throwsStateError);
  });

  test('lists finished sessions between local dates for stats', () async {
    final inWeek = await sessions.start(localDate: '2026-09-09');
    await sessions.logSet(
      inWeek,
      const WorkoutSetDraft(exerciseId: 'ex-plank', weightKg: 0, reps: 60),
    );
    await sessions.finish(inWeek);
    final outOfWeek = await sessions.start(localDate: '2026-09-01');
    await sessions.finish(outOfWeek);

    final finished = await sessions.listFinishedBetween(
      '2026-09-07',
      '2026-09-13',
    );

    expect(finished.map((session) => session.id), [inWeek]);
    expect(finished.single.status, 'finished');
    expect(finished.single.totalVolumeKg, 0);
  });

  test('rejects logging sets into a finished session', () async {
    final sessionId = await sessions.start(localDate: '2026-09-12');
    await sessions.finish(sessionId);

    await expectLater(
      sessions.logSet(
        sessionId,
        const WorkoutSetDraft(exerciseId: 'ex-plank', weightKg: 0, reps: 30),
      ),
      throwsStateError,
    );
    expect(await database.select(database.workoutSets).get(), isEmpty);
  });

  test('keeps sessions usable when their plan is deleted', () async {
    final planId = await seedPlan();
    final sessionId = await sessions.start(
      localDate: '2026-09-12',
      planId: planId,
    );
    final plan = (await plans.getById(planId))!;
    final entry = plan.days.single.entries.single;

    await sessions.logSet(
      sessionId,
      WorkoutSetDraft(
        plannedExerciseId: entry.id,
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );
    await plans.removePlan(planId);

    final session = (await sessions.getById(sessionId))!;
    expect(session.sets.single.plannedExerciseId, isNull);
    expect(session.sets.single.exerciseName, '杠铃深蹲');
  });
}

final class _Ids implements IdGenerator {
  _Ids(this._prefix);

  final String _prefix;
  int _value = 0;

  @override
  String next() => '$_prefix-${_value++}';
}

final class _SteppingClock implements AppClock {
  _SteppingClock(DateTime value) : value = value.toUtc();

  DateTime value;

  @override
  DateTime nowUtc() => value.toUtc();

  void elapsed(Duration duration) {
    value = value.add(duration);
  }
}
