import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';

import '../../support/food_fixture.dart';

/// A-4（docs/64）：训练**可删一组 / 删整次**。
///
/// 现状证据：`WorkoutSessionRepository` 只有 start / logSet / finish /
/// listFinished*——**没有删除**；训练弹层只有「记录一组 / 结束训练」，
/// 历史只有只读的「训练回顾」。记多了一组、开错了会话都只能留着。
///
/// 级联：`WorkoutSets.sessionId` 是 `onDelete: cascade`，但 `deleteSession`
/// 仍**显式**删组（级联依赖 pragma，显式删除在 pragma 被关掉时也不留孤儿）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 活动横幅的呼吸点是无限动画（animate-pulse），pumpAndSettle 等不完
  // （docs/64 附录 E 第一条坑）。
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  late AppDatabase database;
  late ExerciseRepository exercises;
  late WorkoutPlanRepository plans;
  late WorkoutSessionRepository sessions;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    final clock = FixedAppClock(DateTime.utc(2026, 9, 12, 10));
    exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids('ex-user'),
      clock: clock,
    );
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

  tearDown(() async {
    await database.close();
  });

  Widget page({DateTime? now}) => MaterialApp(
    home: TrainingPage(
      exerciseRepository: exercises,
      workoutPlanRepository: plans,
      workoutSessionRepository: sessions,
      now: now,
    ),
  );

  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 开一次自由训练并记一组；返回 (sessionId, setId)。
  Future<(String, String)> seedSessionWithSet() async {
    final sessionId = await sessions.start(localDate: '2026-09-12');
    final setId = await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );
    return (sessionId, setId);
  }

  test('deleteSet：删掉一组；会话的 completedSetCount 减少', () async {
    final (sessionId, setId) = await seedSessionWithSet();
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 10,
      ),
    );
    expect((await sessions.getById(sessionId))!.completedSetCount, 2);

    expect(await sessions.deleteSet(setId), isTrue);
    final after = await sessions.getById(sessionId);
    expect(after!.sets, hasLength(1));
    expect(after.completedSetCount, 1);
    expect(after.sets.map((set) => set.id), isNot(contains(setId)));

    expect(
      await sessions.deleteSet(setId),
      isFalse,
      reason: '已删的 id 再删返回 false',
    );
  });

  test('deleteSession：删整次（含组次级联）；统计/历史里不再出现', () async {
    final (sessionId, _) = await seedSessionWithSet();
    await sessions.finish(sessionId);
    expect(await sessions.listAllFinished(), hasLength(1));

    expect(await sessions.deleteSession(sessionId), isTrue);

    expect(await sessions.getById(sessionId), isNull);
    expect(await sessions.listAllFinished(), isEmpty, reason: '历史里必须消失');
    expect(
      await database.select(database.workoutSets).get(),
      isEmpty,
      reason: '组次必须一起删（不留孤儿）',
    );
  });

  testWidgets('训练弹层：长按某组 → 删除这一组（确认）', (tester) async {
    tallViewport(tester);
    final (sessionId, setId) = await seedSessionWithSet();
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12, 9)));
    await tester.pumpAndSettle();

    // 进行中会话的入口：横幅上的「查看详情」。
    await tester.tap(find.byKey(const Key('training-session-detail')));
    await tester.pumpAndSettle();
    expect(find.text('训练进行中'), findsOneWidget);

    await tester.longPress(find.byKey(Key('training-logged-set-$setId')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('training-set-delete-confirm')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('training-set-delete-confirm')));
    await tester.pumpAndSettle();

    expect(
      (await sessions.getById(sessionId))!.sets,
      isEmpty,
      reason: '确认后这一组必须真的删掉',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('训练回顾：底部「删除这次训练」→ 历史行消失 + 周统计回退', (tester) async {
    tallViewport(tester);
    final (sessionId, _) = await seedSessionWithSet();
    await sessions.finish(sessionId);
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12, 9)));
    await tester.pumpAndSettle();

    // 切到「训练历史」段（会话卡）。
    await tester.tap(find.byKey(const Key('training-segment-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('training-history-$sessionId')), findsOneWidget);

    await tester.tap(find.byKey(Key('training-history-$sessionId')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('training-review-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-review-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-review-delete-confirm')));
    await tester.pumpAndSettle();

    expect(await sessions.listAllFinished(), isEmpty, reason: '历史里必须消失');
    expect(
      find.byKey(Key('training-history-$sessionId')),
      findsNothing,
      reason: '历史行要跟着重读',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _Ids implements IdGenerator {
  _Ids(this.prefix);

  final String prefix;
  int _next = 0;

  @override
  String next() => '$prefix-${_next++}';
}
