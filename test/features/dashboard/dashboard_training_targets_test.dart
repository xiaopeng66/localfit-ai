import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_training_targets.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/features/training/presentation/sections/training_target_indicator.dart';

/// 今日页训练达标单元（docs/21 §5.1 第 5 项）。
///
/// 用真库（内存 SQLite + 真实仓储）验证「已完成 / 计划」两个计数：
/// 今日按**计划动作**去重计数（同一动作多组只算 1 个），本周按
/// `TrainingStatsCalculator.weeklyCompletion` 的已到期训练日计数。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 2026-09-22 是周二（weekday == 2）。
  final now = DateTime(2026, 9, 22, 12);
  const today = '2026-09-22';

  late AppDatabase database;
  late WorkoutPlanRepository plans;
  late WorkoutSessionRepository sessions;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await const ExerciseSeedImporter().importIfNeeded(database);
    final ids = _IncrementingIdGenerator();
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
    sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile',
            activityLevel: 'moderate',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
  });

  tearDown(() => database.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardTrainingTargets(
            planRepository: plans,
            sessionRepository: sessions,
            localDate: today,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 建一份「周二 + 周四」两个训练日的计划（周二 2 个动作、周四 1 个）。
  Future<String> createPlan() => plans.create(
    const WorkoutPlanDraft(
      name: '减脂计划',
      days: [
        WorkoutPlanDayDraft(
          weekday: 2,
          entries: [
            PlannedExerciseDraft(
              exerciseId: 'ex-barbell-squat',
              targetSets: 3,
              targetReps: 8,
            ),
            PlannedExerciseDraft(
              exerciseId: 'ex-barbell-bench-press',
              targetSets: 3,
              targetReps: 10,
            ),
          ],
        ),
        WorkoutPlanDayDraft(
          weekday: 4,
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

  /// 取周二计划里某个动作的条目 id（记组次时要带上才算「按计划完成」）。
  Future<String> tuesdayEntryId(String planId, String exerciseId) async {
    final plan = await plans.getById(planId);
    return plan!.days
        .firstWhere((day) => day.weekday == 2)
        .entries
        .firstWhere((entry) => entry.exerciseId == exerciseId)
        .id;
  }

  testWidgets('没有计划时说明如何创建，不显示 0/0 的进度', (tester) async {
    await pump(tester);

    expect(find.textContaining('还没有训练计划'), findsOneWidget);
    expect(find.byType(TrainingTargetIndicator), findsNothing);
  });

  testWidgets('今日按计划动作去重计数：同一动作记多组仍算一个', (tester) async {
    final planId = await createPlan();
    final sessionId = await sessions.start(localDate: today, planId: planId);
    // 同一个计划动作记两组：只应计入 1 个动作。
    final squatEntryId = await tuesdayEntryId(planId, 'ex-barbell-squat');
    await sessions.logSet(
      sessionId,
      WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
        plannedExerciseId: squatEntryId,
      ),
    );
    await sessions.logSet(
      sessionId,
      WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
        plannedExerciseId: squatEntryId,
      ),
    );
    await sessions.finish(sessionId);

    await pump(tester);

    // 周二计划 2 个动作，只完成 1 个。
    expect(find.text('今日计划'), findsOneWidget);
    expect(find.text('1/2 个动作'), findsOneWidget);
    // 周二已到期，周四还没到：本周 1/1 天。
    expect(find.text('本周计划'), findsOneWidget);
    expect(find.text('1/1 天'), findsOneWidget);
  });

  testWidgets('未记录组次时今日为 0/N，不把计划算作已完成', (tester) async {
    await createPlan();

    await pump(tester);

    expect(find.text('0/2 个动作'), findsOneWidget);
    expect(find.text('0/1 天'), findsOneWidget);
  });

  testWidgets('计划里的动作在非计划日记录，不计入今日达标', (tester) async {
    final planId = await createPlan();
    final squatEntryId = await tuesdayEntryId(planId, 'ex-barbell-squat');
    // 昨天的会话（不属于今日达标）。
    final sessionId = await sessions.start(localDate: '2026-09-21');
    await sessions.logSet(
      sessionId,
      WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
        plannedExerciseId: squatEntryId,
      ),
    );
    await sessions.finish(sessionId);

    await pump(tester);

    expect(find.text('0/2 个动作'), findsOneWidget);
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'targets-id-${_value++}';
}
