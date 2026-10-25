import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';

import '../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late WorkoutPlanRepository plans;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: _Ids('plan'),
      clock: FixedAppClock(DateTime.utc(2026, 9, 12, 10)),
    );
  });

  tearDown(() => database.close());

  Future<String> seedPlan() {
    return plans.create(
      const WorkoutPlanDraft(
        name: '三分化基础',
        days: [
          WorkoutPlanDayDraft(
            weekday: 1,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
              ),
              PlannedExerciseDraft(
                exerciseId: 'ex-leg-press',
                targetSets: 3,
                targetReps: 12,
                targetWeightKg: 60,
              ),
            ],
          ),
          WorkoutPlanDayDraft(
            weekday: 3,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-bench-press',
                targetSets: 4,
                targetReps: 10,
              ),
            ],
          ),
        ],
      ),
    );
  }

  test('creates a plan with days and joined exercise names', () async {
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '全身入门',
        days: [
          WorkoutPlanDayDraft(
            weekday: 1,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 3,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );

    final plan = (await plans.getById(planId))!;
    expect(plan.name, '全身入门');
    expect(plan.status, 'active');
    expect(plan.revision, 1);
    expect(plan.days.single.weekday, 1);
    expect(plan.days.single.entries.single.exerciseName, '杠铃深蹲');
    expect(plan.days.single.entries.single.equipment, Equipment.barbell);
    expect(plan.days.single.entries.single.targetSets, 3);
    expect(plan.days.single.entries.single.targetWeightKg, isNull);
  });

  test('rejects invalid plan shapes without writing', () async {
    const squat = PlannedExerciseDraft(
      exerciseId: 'ex-barbell-squat',
      targetSets: 3,
      targetReps: 8,
    );

    for (final invalid in <WorkoutPlanDraft>[
      const WorkoutPlanDraft(
        name: '  ',
        days: [
          WorkoutPlanDayDraft(weekday: 1, entries: [squat]),
        ],
      ),
      const WorkoutPlanDraft(
        name: '空天',
        days: [WorkoutPlanDayDraft(weekday: 1, entries: [])],
      ),
      const WorkoutPlanDraft(
        name: '重复日',
        days: [
          WorkoutPlanDayDraft(weekday: 2, entries: [squat]),
          WorkoutPlanDayDraft(weekday: 2, entries: [squat]),
        ],
      ),
      const WorkoutPlanDraft(
        name: '未知动作',
        days: [
          WorkoutPlanDayDraft(
            weekday: 1,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-missing',
                targetSets: 1,
                targetReps: 1,
              ),
            ],
          ),
        ],
      ),
      const WorkoutPlanDraft(
        name: '零组',
        days: [
          WorkoutPlanDayDraft(
            weekday: 1,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 0,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
      const WorkoutPlanDraft(
        name: '负重量',
        days: [
          WorkoutPlanDayDraft(
            weekday: 1,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 1,
                targetReps: 1,
                targetWeightKg: -1,
              ),
            ],
          ),
        ],
      ),
    ]) {
      await expectLater(
        plans.create(invalid),
        throwsFormatException,
        reason: invalid.name,
      );
    }
    expect(await database.select(database.workoutPlans).get(), isEmpty);
    expect(await database.select(database.workoutDays).get(), isEmpty);
    expect(await database.select(database.plannedExercises).get(), isEmpty);
  });

  test('rolls back the whole plan when a later entry insert fails', () async {
    await database
        .into(database.workoutPlans)
        .insert(
          WorkoutPlansCompanion.insert(
            id: 'plan-pre',
            name: '预置计划',
            source: 'manual',
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
    await database
        .into(database.workoutDays)
        .insert(
          WorkoutDaysCompanion.insert(
            id: 'plan-pre-day',
            planId: 'plan-pre',
            weekday: 1,
            sortOrder: 1,
          ),
        );
    await database
        .into(database.plannedExercises)
        .insert(
          PlannedExercisesCompanion.insert(
            id: 'plan-2',
            dayId: 'plan-pre-day',
            exerciseId: 'ex-plank',
            sortOrder: 0,
            targetSets: 1,
            targetReps: 1,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );

    await expectLater(
      plans.create(
        const WorkoutPlanDraft(
          name: '回滚计划',
          days: [
            WorkoutPlanDayDraft(
              weekday: 1,
              entries: [
                PlannedExerciseDraft(
                  exerciseId: 'ex-plank',
                  targetSets: 1,
                  targetReps: 1,
                ),
              ],
            ),
            WorkoutPlanDayDraft(
              weekday: 2,
              entries: [
                PlannedExerciseDraft(
                  exerciseId: 'ex-crunch',
                  targetSets: 1,
                  targetReps: 1,
                ),
              ],
            ),
          ],
        ),
      ),
      throwsA(isA<Exception>()),
    );
    expect(
      (await database.select(database.workoutPlans).get()).map((row) => row.id),
      ['plan-pre'],
    );
    expect(
      (await database.select(database.workoutDays).get()).map((row) => row.id),
      ['plan-pre-day'],
    );
    expect(
      (await database.select(database.plannedExercises).get()).single.id,
      'plan-2',
    );
  });

  test('adds entries with per-day sort order and bumps the revision', () async {
    final planId = await seedPlan();

    await plans.addEntry(
      planId,
      1,
      const PlannedExerciseDraft(
        exerciseId: 'ex-crunch',
        targetSets: 3,
        targetReps: 15,
      ),
    );

    final plan = (await plans.getById(planId))!;
    expect(plan.revision, 2);
    final monday = plan.days.singleWhere((day) => day.weekday == 1);
    expect(monday.entries.map((entry) => entry.sortOrder), [0, 1, 2]);
    expect(monday.entries.last.exerciseName, '卷腹');
  });

  test('creates the day lazily when adding to a missing weekday', () async {
    final planId = await seedPlan();

    await plans.addEntry(
      planId,
      5,
      const PlannedExerciseDraft(
        exerciseId: 'ex-plank',
        targetSets: 2,
        targetReps: 60,
      ),
    );

    final plan = (await plans.getById(planId))!;
    expect(plan.days.map((day) => day.weekday), [1, 3, 5]);
  });

  test(
    'removes an entry, drops empty days, and cascades plan deletion',
    () async {
      final planId = await seedPlan();
      final plan = (await plans.getById(planId))!;
      final fridayEntry = plan.days
          .singleWhere((day) => day.weekday == 3)
          .entries
          .single;

      expect(await plans.removeEntry(fridayEntry.id), isTrue);
      expect((await plans.getById(planId))!.days.map((day) => day.weekday), [
        1,
      ]);
      expect(await plans.removeEntry(fridayEntry.id), isFalse);

      expect(await plans.removePlan(planId), isTrue);
      expect(await plans.getById(planId), isNull);
      expect(await database.select(database.workoutDays).get(), isEmpty);
      expect(await database.select(database.plannedExercises).get(), isEmpty);
    },
  );

  test('lists plan summaries newest first', () async {
    final firstId = await seedPlan();
    final secondId = await plans.create(
      const WorkoutPlanDraft(
        name: '第二轮',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-burpee',
                targetSets: 3,
                targetReps: 20,
              ),
            ],
          ),
        ],
      ),
    );

    final summaries = await plans.list();
    expect(summaries.map((summary) => summary.id), [secondId, firstId]);
    expect(summaries.first.name, '第二轮');
    expect(summaries.first.entryCount, 1);
    expect(summaries.last.entryCount, 3);
  });

  test('rejects a weekday outside 1..7', () async {
    await expectLater(
      plans.addEntry(
        'plan-x',
        8,
        const PlannedExerciseDraft(
          exerciseId: 'ex-plank',
          targetSets: 1,
          targetReps: 30,
        ),
      ),
      throwsFormatException,
    );
  });
}

final class _Ids implements IdGenerator {
  _Ids(this._prefix);

  final String _prefix;
  int _value = 0;

  @override
  String next() => '$_prefix-${_value++}';
}
