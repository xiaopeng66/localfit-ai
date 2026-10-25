import 'dart:async';

import 'package:drift/drift.dart'
    show
        ApplyInterceptor,
        QueryExecutor,
        QueryInterceptor,
        Value,
        driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/chart_semantics.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/presentation/sections/training_hero.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_manual_page.dart';

const _offDayHint = '仅可开始今天的训练；其他训练日仍可查看和编辑。';
const _emptySessionHint = '这次训练对应的计划日没有可记录的动作。可取消返回或结束训练。';
const _squat = PlannedExerciseDraft(
  exerciseId: 'ex-barbell-squat',
  targetSets: 3,
  targetReps: 8,
);
const _bench = PlannedExerciseDraft(
  exerciseId: 'ex-barbell-bench-press',
  targetSets: 4,
  targetReps: 10,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  late _TrainingFixture f;
  setUp(() async {
    f = _TrainingFixture();
    await const ExerciseSeedImporter().importIfNeeded(f.database);
  });
  tearDown(() => f.database.close());

  // Restoring the Sunday -> Monday alias breaks both the highlighted column
  // and its accessible description; expectations are literal calendar facts.
  for (final (day, index, label) in const [
    (12, 0, '一'),
    (13, 1, '二'),
    (14, 2, '三'),
    (15, 3, '四'),
    (16, 4, '五'),
    (17, 5, '六'),
    (18, 6, '日'),
  ]) {
    testWidgets('calendar day $day uses Monday-first index $index', (
      tester,
    ) async {
      _viewport(tester);
      await tester.pumpWidget(f.page(now: DateTime(2026, 10, day)));
      await tester.pumpAndSettle();
      try {
        expect(_hero(tester).todayIndex, index);
        expect(_chartSummary(tester), '本周容量图：还没有训练记录；今天是周$label。');
      } finally {
        await _unmount(tester);
      }
    });
  }

  testWidgets('Sunday capacity stays separate from Monday capacity', (
    tester,
  ) async {
    _viewport(tester);
    f.clock.value = DateTime.utc(2026, 10, 12, 10);
    final monday = await f.sessions.start(localDate: '2026-10-12');
    f.clock.value = DateTime.utc(2026, 10, 12, 10, 20);
    await f.sessions.finish(monday);
    f.clock.value = DateTime.utc(2026, 10, 18, 10);
    final sunday = await f.sessions.start(localDate: '2026-10-18');
    f.clock.value = DateTime.utc(2026, 10, 18, 10, 45);
    await f.sessions.finish(sunday);
    await tester.pumpWidget(f.page(now: DateTime(2026, 10, 18)));
    await tester.pumpAndSettle();
    try {
      expect(_hero(tester).capacityMinutes, [20, 0, 0, 0, 0, 0, 45]);
      expect(_hero(tester).finishedCount, 2);
      expect(_hero(tester).totalDuration, const Duration(minutes: 65));
      expect(_chartSummary(tester), '本周容量图：周一 20 分钟、周日 45 分钟；今天是周日。');
    } finally {
      await _unmount(tester);
    }
  });

  // The same late bundled option must remain selectable after user-created
  // exercises take the catalogue beyond the old repository default of 500.
  for (final extraCount in [0, 205]) {
    testWidgets(
      'manual picker selects and saves late option with ${312 + extraCount} exercises',
      (tester) async {
        _viewport(tester);
        await f.database.transaction(() async {
          for (var i = 0; i < extraCount; i++) {
            await f.exercises.create(
              NewExercise(
                name: 'Custom ${i.toString().padLeft(3, '0')}',
                muscleGroup: MuscleGroup.legs,
                equipment: Equipment.barbell,
              ),
            );
          }
        });
        expect(
          await f.database.select(f.database.exercises).get(),
          hasLength(312 + extraCount),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: WorkoutPlanManualPage(
              exerciseRepository: f.exercises,
              workoutPlanRepository: f.plans,
            ),
          ),
        );
        await tester.pumpAndSettle();
        try {
          await tester.enterText(
            find.byKey(const Key('manual-plan-name')),
            'Complete catalogue',
          );
          await _tapKey(tester, 'manual-plan-weekday-2');
          await _tapKey(tester, 'manual-plan-day-add-2');
          final options = _select(tester, 'training-entry-exercise').options;
          final lateIndex = options.indexOf('ex-clean-shrug');
          expect(
            lateIndex,
            greaterThan(extraCount == 0 ? 200 : 500),
            reason: 'The final seeded exercise must not be cut off by a fixed query limit.',
          );
          await _tapKey(tester, 'training-entry-exercise');
          final lateOption = find.byKey(Key('lf-select-option-$lateIndex'));
          await tester.scrollUntilVisible(
            lateOption,
            300,
            scrollable: find.descendant(
              of: find.byKey(const Key('lf-select-options')),
              matching: find.byType(Scrollable),
            ),
            maxScrolls: 100,
          );
          await tester.tap(lateOption);
          await tester.pumpAndSettle();
          expect(
            _select(tester, 'training-entry-exercise').value,
            'ex-clean-shrug',
          );
          await _savePlannedEntry(tester);
          expect(find.text('高翻耸肩'), findsOneWidget);
          await _tapKey(tester, 'manual-plan-save');
          final plan = await f.plans.getById((await f.plans.list()).single.id);
          expect(plan!.days.single.entries.single.exerciseId, 'ex-clean-shrug');
        } finally {
          await _unmount(tester);
        }
      },
    );
  }

  for (final switchTabs in [false, true]) {
    testWidgets(
      'routed manual create refreshes training list, tab bounce $switchTabs',
      (tester) async {
        _viewport(tester);
        await tester.pumpWidget(
          LocalFitApp(
            initialLocation: AppRoutes.training,
            exerciseRepository: f.exercises,
            workoutPlanRepository: f.plans,
            workoutSessionRepository: f.sessions,
            now: DateTime(2026, 10, 13),
          ),
        );
        await tester.pumpAndSettle();
        try {
          expect(find.text('还没有本地训练计划。'), findsOneWidget);
          await _tapKey(tester, 'cta-new-plan');
          await _tapKey(tester, 'plan-mode-manual');
          expect(find.byType(WorkoutPlanManualPage), findsOneWidget);
          await tester.enterText(
            find.byKey(const Key('manual-plan-name')),
            'Saved through real route',
          );
          await _tapKey(tester, 'manual-plan-weekday-2');
          await _tapKey(tester, 'manual-plan-day-add-2');
          await _savePlannedEntry(tester);
          await _tapKey(tester, 'manual-plan-save');
          expect(find.byType(WorkoutPlanManualPage), findsNothing);
          expect(
            (await f.plans.list()).single.name,
            'Saved through real route',
          );
          if (switchTabs) {
            await _tapKey(tester, 'nav-settings');
            await _tapKey(tester, 'nav-training');
          }
          expect(find.text('Saved through real route'), findsOneWidget);
          expect(find.text('还没有本地训练计划。'), findsNothing);
        } finally {
          await _unmount(tester);
        }
      },
    );
  }

  testWidgets(
    'repository plan transactions refresh mounted list once without a route change',
    (tester) async {
      _viewport(tester);
      await tester.pumpWidget(f.page());
      await tester.pumpAndSettle();
      try {
        final before = f.queries.planLists;
        final id = await f.plans.create(
          _draft('External AI plan'),
          source: 'ai',
        );
        await tester.pumpAndSettle();
        expect(find.text('External AI plan'), findsOneWidget);
        expect(
          f.queries.planLists - before,
          1,
          reason: 'A committed multi-table transaction must invalidate once, not per row.',
        );
        await f.plans.addEntry(id, 1, _squat);
        await tester.pumpAndSettle();
        // 2026-10-16：星期**由徽章承担**（`周一` / 今天），标题只留计划名
        // ——同一个星期在标题和徽章各出现一次是重复，且 320dp + 2.0× 字号下
        // 后缀会被挤到第二行（训练页帧实看抓到）。
        expect(find.text('External AI plan'), findsNWidgets(2));
        // 星期由右侧徽章承担（2026-10-16）：星期一那张写「周一」；另一张若
        // 正好是今天，徽章写「今天」——两种写法都合法，断言用「合计恰好一个」。
        expect(find.text('周一'), findsOneWidget);
        expect(
          find.text('周二').evaluate().length + find.text('今天').evaluate().length,
          1,
        );
        expect(find.textContaining('· 周'), findsNothing);
        await f.plans.removePlan(id);
        await tester.pumpAndSettle();
        expect(find.text('还没有本地训练计划。'), findsOneWidget);
      } finally {
        await _unmount(tester);
      }
    },
  );

  testWidgets(
    'external day entry and exercise changes refresh without a parent revision bump',
    (tester) async {
      _viewport(tester);
      final id = await f.plans.create(_draft('External children'));
      final plan = (await f.plans.getById(id))!;
      await tester.pumpWidget(f.page());
      await tester.pumpAndSettle();
      try {
        await (f.database.update(f.database.workoutDays)
              ..where((row) => row.id.equals(plan.days.single.id)))
            .write(const WorkoutDaysCompanion(weekday: Value(3)));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TrainingPlanCard>(find.byType(TrainingPlanCard))
              .weekday,
          3,
        );
        await (f.database.update(f.database.plannedExercises)..where(
              (row) => row.id.equals(plan.days.single.entries.single.id),
            ))
            .write(const PlannedExercisesCompanion(targetReps: Value(99)));
        await tester.pumpAndSettle();
        expect(find.text('4 × 99 · 自重'), findsOneWidget);
        await (f.database.update(
          f.database.exercises,
        )..where((row) => row.id.equals('ex-barbell-bench-press'))).write(
          const ExercisesCompanion(name: Value('Restored exercise name')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Restored exercise name'), findsOneWidget);
      } finally {
        await _unmount(tester);
      }
    },
  );

  testWidgets(
    'real external backup restore refreshes a mounted training list',
    (tester) async {
      _viewport(tester);
      final id = await f.plans.create(_draft('Restored plan'));
      final backup = await ExportLocalFitData(f.database).exportJson();
      await f.plans.removePlan(id);
      await tester.pumpWidget(f.page());
      await tester.pumpAndSettle();
      try {
        expect(find.text('还没有本地训练计划。'), findsOneWidget);
        await RestoreLocalFitData(f.database).restore(backup);
        await tester.pumpAndSettle();
        expect(find.text('Restored plan'), findsOneWidget);
        expect(find.text('杠铃卧推'), findsOneWidget);
        expect(find.text('还没有本地训练计划。'), findsNothing);
      } finally {
        await _unmount(tester);
      }
    },
  );

  testWidgets(
    'external session and set writes refresh active banner and history',
    (tester) async {
      _viewport(tester);
      await tester.pumpWidget(f.page());
      await tester.pumpAndSettle();
      try {
        final id = await f.sessions.start(localDate: '2026-10-13');
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cta-continue-session')), findsOneWidget);
        // A set-only update is also relevant, independently of the session row.
        await f.database
            .into(f.database.workoutSets)
            .insert(
              WorkoutSetsCompanion.insert(
                id: 'external-set',
                sessionId: id,
                exerciseId: 'ex-barbell-squat',
                sortOrder: 0,
                weightKg: 20,
                reps: 5,
                completedAt: f.clock.nowUtc(),
                createdAt: f.clock.nowUtc(),
                updatedAt: f.clock.nowUtc(),
              ),
            );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TrainingActiveBanner>(find.byType(TrainingActiveBanner))
              .completedSets,
          1,
        );
        await f.sessions.finish(id);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('cta-continue-session')), findsNothing);
        expect(_hero(tester).finishedCount, 1);
        await _tapKey(tester, 'training-segment-history');
        expect(find.byKey(Key('training-history-$id')), findsOneWidget);
      } finally {
        await _unmount(tester);
      }
    },
  );

  testWidgets('view rebuilds and unrelated writes do not reload the snapshot', (
    tester,
  ) async {
    _viewport(tester);
    await f.plans.create(_draft('Stable snapshot'));
    await tester.pumpWidget(f.page());
    await tester.pumpAndSettle();
    try {
      final selects = f.queries.selects;
      await _tapKey(tester, 'training-segment-history');
      await _tapKey(tester, 'training-segment-plan');
      await _tapKey(tester, 'training-muscle-legs');
      await _tapKey(tester, 'training-muscle-all');
      await f.database
          .into(f.database.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'unrelated-setting',
              value: 'changed',
            ),
          );
      await tester.pumpAndSettle();
      expect(
        f.queries.selects,
        selects,
        reason: 'Rendering/filtering and unrelated tables must not start DB query loops.',
      );
      expect(find.text('Stable snapshot'), findsOneWidget);
    } finally {
      await _unmount(tester);
    }
  });

  testWidgets(
    'late old snapshot cannot replace a newer table-change snapshot',
    (tester) async {
      _viewport(tester);
      final id = await f.plans.create(_draft('Old snapshot'));
      final held = f.queries.holdNextPlanSelect(listOnly: true);
      await tester.pumpWidget(f.page());
      await tester.pump();
      try {
        expect(f.queries.holding, isTrue);
        await (f.database.update(f.database.workoutPlans)
              ..where((row) => row.id.equals(id)))
            .write(const WorkoutPlansCompanion(name: Value('Newest snapshot')));
        for (
          var frame = 0;
          frame < 20 && find.text('Newest snapshot').evaluate().isEmpty;
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(find.text('Newest snapshot'), findsOneWidget);
        held.complete();
        await tester.pumpAndSettle();
        expect(find.text('Newest snapshot'), findsOneWidget);
        expect(
          find.text('Old snapshot'),
          findsNothing,
          reason: 'An earlier DB response completing last must be discarded.',
        );
      } finally {
        if (!held.isCompleted) held.complete();
        await tester.pumpAndSettle();
        await _unmount(tester);
      }
    },
  );

  testWidgets(
    'repository replacement detaches old updates and disposal stops reads',
    (tester) async {
      _viewport(tester);
      final previousWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarning,
      );
      final replacement = _TrainingFixture();
      await tester.runAsync(() async {
        await const ExerciseSeedImporter().importIfNeeded(replacement.database);
      });
      await f.plans.create(_draft('Old repository'));
      await replacement.plans.create(_draft('Replacement repository'));
      try {
        await tester.pumpWidget(f.page());
        await tester.pumpAndSettle();
        await tester.pumpWidget(replacement.page());
        await tester.pumpAndSettle();
        expect(find.text('Replacement repository'), findsOneWidget);
        final count = replacement.queries.planLists;
        await f.plans.create(_draft('Detached change'));
        await tester.pumpAndSettle();
        expect(replacement.queries.planLists, count);
        expect(find.text('Detached change'), findsNothing);
        await replacement.plans.create(_draft('Attached change'));
        await tester.pumpAndSettle();
        expect(find.text('Attached change'), findsOneWidget);
        await _unmount(tester);
        final afterDispose = replacement.queries.planLists;
        await replacement.plans.create(_draft('After dispose'));
        await tester.pumpAndSettle();
        expect(replacement.queries.planLists, afterDispose);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        await replacement.database.close();
      }
    },
  );

  testWidgets('new local date invalidates the cached weekly window', (
    tester,
  ) async {
    _viewport(tester);
    final id = await f.sessions.start(localDate: '2026-10-18');
    await f.sessions.finish(id);
    await tester.pumpWidget(f.page(now: DateTime(2026, 10, 18)));
    await tester.pumpAndSettle();
    try {
      expect(_hero(tester).finishedCount, 1);
      await tester.pumpWidget(f.page(now: DateTime(2026, 10, 19)));
      await tester.pumpAndSettle();
      expect(_hero(tester).finishedCount, 0);
      expect(_hero(tester).todayIndex, 0);
    } finally {
      await _unmount(tester);
    }
  });

  for (final includeToday in [false, true]) {
    testWidgets(
      'off-day start is disabled with today row $includeToday and writes no session',
      (tester) async {
        _viewport(tester);
        await f.plans.create(
          _draft('Day boundary', monday: true, tuesday: includeToday),
        );
        await tester.pumpWidget(f.page());
        await tester.pumpAndSettle();
        try {
          await _openPlan(tester, 'Day boundary');
          final start = _dayStart('周一');
          expect(tester.widget<TextButton>(start).onPressed, isNull);
          expect(find.text(_offDayHint), findsOneWidget);
          await tester.tap(start);
          await tester.pumpAndSettle();
          expect(
            await f.database.select(f.database.workoutSessions).get(),
            isEmpty,
          );
          expect(
            find.byKey(const Key('training-plan-entry-add')),
            findsOneWidget,
          );
        } finally {
          await _unmount(tester);
        }
      },
    );
  }

  testWidgets('off-day entries remain addable and removable', (tester) async {
    _viewport(tester);
    final id = await f.plans.create(
      _draft('Editable off-day', monday: true, tuesday: false),
    );
    await tester.pumpWidget(f.page());
    await tester.pumpAndSettle();
    try {
      await _openPlan(tester, 'Editable off-day');
      await _tapKey(tester, 'training-plan-entry-add');
      await _savePlannedEntry(tester);
      final updated = (await f.plans.getById(id))!;
      expect(updated.days.single.weekday, 1);
      expect(updated.days.single.entries, hasLength(2));
      await _tapKey(
        tester,
        'training-entry-delete-${updated.days.single.entries.last.id}',
      );
      expect((await f.plans.getById(id))!.days.single.entries, hasLength(1));
      expect(
        await f.database.select(f.database.workoutSessions).get(),
        isEmpty,
      );
    } finally {
      await _unmount(tester);
    }
  });

  testWidgets(
    'today row starts today and records its own action, not another weekday',
    (tester) async {
      _viewport(tester);
      final planId = await f.plans.create(
        _draft('Distinct days', monday: true),
      );
      await tester.pumpWidget(f.page());
      await tester.pumpAndSettle();
      try {
        await _openPlan(tester, 'Distinct days');
        await tester.tap(_dayStart('周二'));
        await tester.pumpAndSettle();
        final active = (await f.sessions.getActive())!;
        expect(active.planId, planId);
        expect(active.localDate, '2026-10-13');
        await _tapKey(tester, 'training-set-log');
        expect(_select(tester, 'training-set-exercise').options, [
          'ex-barbell-bench-press',
        ]);
        await _saveSet(tester);
        expect(
          (await f.sessions.getActive())!.sets.single.exerciseId,
          'ex-barbell-bench-press',
        );
      } finally {
        await _unmount(tester);
      }
    },
  );

  testWidgets('stale open day sheet cannot start yesterday after midnight', (
    tester,
  ) async {
    _viewport(tester);
    await f.plans.create(_draft('Midnight plan', monday: true));
    final date = ValueNotifier(DateTime(2026, 10, 12, 23, 59));
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ValueListenableBuilder<DateTime>(
            valueListenable: date,
            builder: (_, now, _) => f.training(now: now),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openPlan(tester, 'Midnight plan');
      expect(tester.widget<TextButton>(_dayStart('周一')).onPressed, isNotNull);
      date.value = DateTime(2026, 10, 13);
      await tester.pumpAndSettle();
      await tester.tap(_dayStart('周一'));
      await tester.pumpAndSettle();
      expect(
        await f.database.select(f.database.workoutSessions).get(),
        isEmpty,
      );
      expect(find.textContaining('仅可开始今天的训练'), findsWidgets);
    } finally {
      await _unmount(tester);
      date.dispose();
    }
  });

  testWidgets(
    'date is checked again after asynchronous day validation before session write',
    (tester) async {
      _viewport(tester);
      await f.plans.create(_draft('Validation midnight', monday: true));
      final date = ValueNotifier(DateTime(2026, 10, 12, 23, 59));
      Completer<void>? held;
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: ValueListenableBuilder<DateTime>(
              valueListenable: date,
              builder: (_, now, _) => f.training(now: now),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _openPlan(tester, 'Validation midnight');
        held = f.queries.holdNextPlanSelect();
        await tester.tap(_dayStart('周一'));
        await tester.pump();
        expect(f.queries.holding, isTrue);
        date.value = DateTime(2026, 10, 13);
        await tester.pump();
        held.complete();
        await tester.pumpAndSettle();
        expect(
          await f.database.select(f.database.workoutSessions).get(),
          isEmpty,
          reason: 'Neither backdating Monday nor silently starting Tuesday is valid.',
        );
      } finally {
        if (held != null && !held.isCompleted) held.complete();
        await tester.pumpAndSettle();
        await _unmount(tester);
        date.dispose();
      }
    },
  );

  testWidgets('today row with no surviving planned actions cannot start', (
    tester,
  ) async {
    _viewport(tester);
    final id = await f.plans.create(_draft('Empty today'));
    final entry = (await f.plans.getById(id))!.days.single.entries.single;
    await (f.database.delete(
      f.database.plannedExercises,
    )..where((row) => row.id.equals(entry.id))).go();
    await tester.pumpWidget(f.page());
    await tester.pumpAndSettle();
    try {
      await _openPlan(tester, 'Empty today');
      expect(tester.widget<TextButton>(_dayStart('周二')).onPressed, isNull);
      expect(find.text('该训练日没有可记录的动作，请先添加动作。'), findsOneWidget);
      await tester.tap(_dayStart('周二'));
      await tester.pumpAndSettle();
      expect(
        await f.database.select(f.database.workoutSessions).get(),
        isEmpty,
      );
    } finally {
      await _unmount(tester);
    }
  });

  for (final deletePlan in [false, true]) {
    testWidgets(
      'stale today sheet rejects removed ${deletePlan ? 'plan' : 'actions'} before starting',
      (tester) async {
        _viewport(tester);
        final id = await f.plans.create(_draft('Stale today'));
        final entry = (await f.plans.getById(id))!.days.single.entries.single;
        await tester.pumpWidget(f.page());
        await tester.pumpAndSettle();
        try {
          await _openPlan(tester, 'Stale today');
          if (deletePlan) {
            await f.plans.removePlan(id);
          } else {
            await f.plans.removeEntry(entry.id);
          }
          await tester.pumpAndSettle();
          await tester.tap(_dayStart('周二'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            await f.database.select(f.database.workoutSessions).get(),
            isEmpty,
          );
          expect(find.textContaining('没有可记录的动作'), findsOneWidget);
        } finally {
          await _unmount(tester);
        }
      },
    );
  }

  testWidgets(
    'Monday active session resumes Tuesday using its stored Monday actions',
    (tester) async {
      _viewport(tester);
      final id = await f.plans.create(_draft('Resumable days', monday: true));
      final sessionId = await f.sessions.start(
        localDate: '2026-10-12',
        planId: id,
      );
      await tester.pumpWidget(f.page());
      await tester.pumpAndSettle();
      try {
        await _tapKey(tester, 'cta-continue-session');
        await _tapKey(tester, 'training-set-log');
        expect(_select(tester, 'training-set-exercise').options, [
          'ex-barbell-squat',
        ]);
        await _saveSet(tester);
        final active = (await f.sessions.getById(sessionId))!;
        expect(active.localDate, '2026-10-12');
        expect(active.sets.single.exerciseId, 'ex-barbell-squat');
        expect(
          await f.database.select(f.database.workoutSessions).get(),
          hasLength(1),
        );
      } finally {
        await _unmount(tester);
      }
    },
  );

  for (final unavailable in [
    'missing day',
    'empty day',
    'deleted day',
    'invalid date',
  ]) {
    testWidgets(
      'saved planned session with $unavailable disables picker and save but can cancel and finish',
      (tester) async {
        _viewport(tester);
        final id = await f.plans.create(
          _draft('Saved session', monday: unavailable != 'missing day'),
        );
        final sessionId = await f.sessions.start(
          localDate: '2026-10-12',
          planId: id,
        );
        if (unavailable == 'empty day' || unavailable == 'deleted day') {
          final entry = (await f.plans.getById(id))!.days.first.entries.single;
          if (unavailable == 'empty day') {
            await (f.database.delete(
              f.database.plannedExercises,
            )..where((row) => row.id.equals(entry.id))).go();
          } else {
            await f.plans.removeEntry(entry.id);
          }
        } else if (unavailable == 'invalid date') {
          await (f.database.update(
            f.database.workoutSessions,
          )..where((row) => row.id.equals(sessionId))).write(
            const WorkoutSessionsCompanion(localDate: Value('not-a-date')),
          );
        }
        await tester.pumpWidget(f.page());
        await tester.pumpAndSettle();
        try {
          await _tapKey(tester, 'cta-continue-session');
          await _tapKey(tester, 'training-set-log');
          final picker = _select(tester, 'training-set-exercise');
          expect(
            picker.options,
            isEmpty,
            reason: 'Never substitute Tuesday or the whole catalogue for missing Monday actions.',
          );
          expect(picker.value, isNull);
          expect(picker.enabled, isFalse);
          expect(
            tester
                .widget<FilledButton>(
                  find.byKey(const Key('training-set-save')),
                )
                .onPressed,
            isNull,
          );
          expect(find.text(_emptySessionHint), findsOneWidget);
          await _tapKey(tester, 'training-set-exercise');
          expect(tester.takeException(), isNull);
          expect(find.byKey(const Key('lf-select-options')), findsNothing);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('training-set-save')), findsNothing);
          await _tapKey(tester, 'training-session-finish');
          await _tapKey(tester, 'training-session-finish-confirm');
          await _tapKey(tester, 'training-summary-done');
          expect((await f.sessions.getById(sessionId))!.status, 'finished');
          expect(
            await f.database.select(f.database.workoutSets).get(),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester);
        }
      },
    );
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    testWidgets(
      '360dp disabled and empty states remain usable at text scale $scale',
      (tester) async {
        _viewport(tester, size: const Size(360, 900));
        final id = await f.plans.create(
          _draft('计划', monday: true, tuesday: false),
        );
        await tester.pumpWidget(f.page(textScale: scale));
        await tester.pumpAndSettle();
        try {
          await _openPlan(tester, '计划');
          expect(find.text(_offDayHint), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(
            tester.getRect(find.text(_offDayHint)).right,
            lessThanOrEqualTo(360),
          );
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          // A legacy Tuesday session referring to a Monday-only plan.
          await f.sessions.start(localDate: '2026-10-13', planId: id);
          await tester.pumpWidget(f.page(textScale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final key in [
            'cta-continue-session',
            'training-session-detail',
          ]) {
            final button = find.byKey(Key(key));
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            expect(button.hitTestable(), findsOneWidget);
            final bounds = tester.getRect(button);
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(360));
          }
          await _tapKey(tester, 'training-session-detail');
          expect(find.text('训练进行中'), findsOneWidget);
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          await _tapKey(tester, 'cta-continue-session');
          await _tapKey(tester, 'training-set-log');
          expect(find.text(_emptySessionHint), findsOneWidget);
          expect(_select(tester, 'training-set-exercise').enabled, isFalse);
          expect(tester.takeException(), isNull);
          expect(
            tester.getRect(find.text(_emptySessionHint)).right,
            lessThanOrEqualTo(360),
          );
          await tester.ensureVisible(find.text('取消'));
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('training-set-save')), findsNothing);
        } finally {
          await _unmount(tester);
        }
      },
    );
  }
}

WorkoutPlanDraft _draft(
  String name, {
  bool monday = false,
  bool tuesday = true,
}) => WorkoutPlanDraft(
  name: name,
  days: [
    if (monday) const WorkoutPlanDayDraft(weekday: 1, entries: [_squat]),
    if (tuesday) const WorkoutPlanDayDraft(weekday: 2, entries: [_bench]),
  ],
);

TrainingHero _hero(WidgetTester tester) =>
    tester.widget<TrainingHero>(find.byType(TrainingHero));
String _chartSummary(WidgetTester tester) => tester
    .widget<ChartSemantics>(
      find.descendant(
        of: find.byType(TrainingHero),
        matching: find.byType(ChartSemantics),
      ),
    )
    .summary;
LfSelectField<String> _select(WidgetTester tester, String key) => tester
    .widgetList<LfSelectField<String>>(find.byType(LfSelectField<String>))
    .singleWhere((field) => field.fieldKey == Key(key));

Finder _dayStart(String label) => find.descendant(
  of: find
      .ancestor(
        of: find.descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.text(label),
        ),
        matching: find.byType(Row),
      )
      .first,
  matching: find.byKey(const Key('training-session-start')),
);

void _viewport(WidgetTester tester, {Size size = const Size(900, 1800)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: _verticalScrollable(),
      maxScrolls: 20,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _verticalScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable &&
          axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
    )
    .first;

Future<void> _openPlan(WidgetTester tester, String name, {int nth = 0}) async {
  // 2026-10-16：计划卡标题不再补「· 周一」（星期由右侧徽章承担），于是同名
  // 多日计划会有多张卡都写着同一个计划名。定位改为「名字匹配的第 nth 张卡」
  // ——计划卡按星期升序排列，nth=0 就是该计划第一训练日那张（本文件里即周一）。
  final finder = find
      .ancestor(of: find.text(name), matching: find.byType(TrainingPlanCard))
      .at(nth);
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: _verticalScrollable(),
      maxScrolls: 20,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _savePlannedEntry(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('training-entry-sets')), '3');
  await tester.enterText(find.byKey(const Key('training-entry-reps')), '8');
  await _tapKey(tester, 'training-entry-save');
}

Future<void> _saveSet(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('training-set-weight')), '20');
  await tester.enterText(find.byKey(const Key('training-set-reps')), '8');
  await _tapKey(tester, 'training-set-save');
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

final class _TrainingFixture {
  _TrainingFixture() {
    database = AppDatabase(NativeDatabase.memory().interceptWith(queries));
    exercises = ExerciseRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
  }

  final queries = _QueryTiming();
  final ids = _Ids();
  final clock = _MutableClock(DateTime.utc(2026, 10, 13, 10));
  late final AppDatabase database;
  late final ExerciseRepository exercises;
  late final WorkoutPlanRepository plans;
  late final WorkoutSessionRepository sessions;

  TrainingPage training({DateTime? now}) => TrainingPage(
    exerciseRepository: exercises,
    workoutPlanRepository: plans,
    workoutSessionRepository: sessions,
    now: now ?? DateTime(2026, 10, 13),
  );

  Widget page({DateTime? now, double textScale = 1}) => MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: training(now: now),
  );
}

// Only response timing is controlled: every query and write still executes
// against real SQLite. Delaying a captured response models out-of-order I/O.
final class _QueryTiming extends QueryInterceptor {
  var selects = 0;
  var planLists = 0;
  var holding = false;
  Completer<void>? _next;
  bool _listOnly = false;

  Completer<void> holdNextPlanSelect({bool listOnly = false}) {
    holding = false;
    _listOnly = listOnly;
    return _next = Completer<void>();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    selects++;
    final isPlan = statement.contains('FROM "workout_plans"');
    final isList = isPlan && !statement.contains('WHERE');
    if (isList) planLists++;
    final hold = isPlan && (!_listOnly || isList) ? _next : null;
    if (hold != null) {
      _next = null;
      holding = true;
    }
    final rows = await super.runSelect(executor, statement, args);
    if (hold != null) await hold.future;
    return rows;
  }
}

final class _Ids implements IdGenerator {
  var _value = 0;
  @override
  String next() => 'training-regression-${_value++}';
}

final class _MutableClock implements AppClock {
  _MutableClock(this.value);
  DateTime value;
  @override
  DateTime nowUtc() => value.toUtc();
}
