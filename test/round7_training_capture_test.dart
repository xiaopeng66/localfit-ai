import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/training/presentation/exercise_library_page.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_create_page.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// Round7 阶段 4 的渲染矩阵（训练页）。
///
/// 9 帧：计划态浅/深 360-1.0、计划态浅 320-2.0×、计划态深 430-1.5×、
/// 历史态浅 360-1.0、进行中（会话横幅 + 会话详情弹层）浅 360-1.0、
/// 计划详情弹层浅 360-1.0、模式弹层（FAB）浅 360-1.0、空态浅 360-1.0。
///
/// A 的形态见 `app.js:209-268`（近 7 天三段统计 + week-bars + tabs + 会话条 +
/// session-progress + plan-card（plan-days/today 行）+ 空态 + create rows +
/// history rows + list-link 动作库 + volume-panel）。帧用于对账与深浅/窄屏/
/// 大字审看。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ExerciseRepository exercises;
  late WorkoutPlanRepository plans;
  late WorkoutSessionRepository sessions;
  final now = DateTime(2026, 10, 14, 19); // 周三

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids('ex'),
      clock: FixedAppClock(now),
    );
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: _Ids('plan'),
      clock: FixedAppClock(now),
    );
    sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: _Ids('session'),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  Future<void> seedPlanAndHistory() async {
    // 真实种子动作 id（assets/seed/exercises.v3.json）：计划的 entry 必须指向
    // 库里存在的动作，否则仓库校验会拒（`_validateDraft`）。
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '推拉腿 · 三练',
        days: [
          WorkoutPlanDayDraft(
            weekday: 1,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-bench-press',
                targetSets: 4,
                targetReps: 8,
                targetWeightKg: 60,
              ),
              PlannedExerciseDraft(
                exerciseId: 'ex-dumbbell-bench-press',
                targetSets: 3,
                targetReps: 12,
                targetWeightKg: 12,
              ),
            ],
          ),
          WorkoutPlanDayDraft(
            weekday: 3,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-lat-pulldown',
                targetSets: 4,
                targetReps: 10,
                targetWeightKg: 45,
              ),
            ],
          ),
          WorkoutPlanDayDraft(
            weekday: 5,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 5,
                targetReps: 5,
                targetWeightKg: 80,
              ),
            ],
          ),
        ],
      ),
    );
    // 历史：两次已完成（本周），供容量图/周统计/历史行有真数。
    final first = await sessions.start(localDate: '2026-10-12', planId: planId);
    await sessions.logSet(
      first,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-bench-press',
        weightKg: 60,
        reps: 8,
        rpe: 7,
      ),
    );
    await sessions.logSet(
      first,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-bench-press',
        weightKg: 62.5,
        reps: 8,
        rpe: 8,
      ),
    );
    await sessions.finish(first);
    final second = await sessions.start(
      localDate: '2026-10-14',
      planId: planId,
    );
    await sessions.logSet(
      second,
      const WorkoutSetDraft(
        exerciseId: 'ex-lat-pulldown',
        weightKg: 45,
        reps: 10,
        rpe: 7,
      ),
    );
    await sessions.finish(second);
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    required bool dark,
    required double width,
    required double height,
    required double scale,
    bool withOnboardingSheet = false,
    bool withAiPlan = false,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: round7CaptureTheme(dark ? AppTheme.dark() : AppTheme.light()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: TrainingPage(
            exerciseRepository: exercises,
            workoutPlanRepository: plans,
            workoutSessionRepository: sessions,
            // AI 计划抽屉的入口要求三项依赖齐全（`training_page.dart:388`）；
            // 只在需要那张帧时给。
            workoutPlanProvider: withAiPlan
                ? const _NeverCalledProvider()
                : null,
            loadWorkoutPlanDisclosure: withAiPlan
                ? LoadWorkoutPlanDisclosure(
                    configurationReader: const _StubConfigReader(),
                  )
                : null,
            onOpenWorkoutPlanManual: () {},
            now: now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  testWidgets('训练页：计划 / 历史 / 进行中 / 弹层 / 空态（9 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await seedPlanAndHistory();

    // 计划态（含容量图与计划卡）浅/深 360-1.0
    await pumpPage(tester, dark: false, width: 360, height: 900, scale: 1);
    await shot(
      tester,
      'training-plan-light-360-1.0',
      const Key('training-hero'),
    );

    await pumpPage(tester, dark: true, width: 360, height: 900, scale: 1);
    await shot(
      tester,
      'training-plan-dark-360-1.0',
      const Key('training-hero'),
    );

    // 320 + 2.0×
    await pumpPage(tester, dark: false, width: 320, height: 900, scale: 2);
    await shot(
      tester,
      'training-plan-light-320-2.0',
      const Key('training-hero'),
    );

    // 320 + 2.0× 且把第一张计划卡滚进帧（Round7 逐页对账批次 3：新加的
    // 周安排日签行是「七枚圆签」——最窄 × 最大字的组合必须单独留证）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('training-plan-card-1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await shot(
      tester,
      'training-plan-card-320-2.0',
      const Key('training-plan-weekdays-1'),
    );

    // 430 + 1.5× 深色
    await pumpPage(tester, dark: true, width: 430, height: 1000, scale: 1.5);
    await shot(
      tester,
      'training-plan-dark-430-1.5',
      const Key('training-hero'),
    );

    // 「训练统计」弹层（Round7 裁决 R2：容量口径说明句 + 肌群 kg 值）。
    // 二级入口行在历史分段之上，切回计划分段再点。
    await tester.tap(find.byKey(const Key('training-segment-plan')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('training-stats')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-stats')));
    await tester.pumpAndSettle();
    await shot(
      tester,
      'training-stats-sheet-light-360-1.0',
      const Key('training-trend-note'),
    );
    await tester.tapAt(const Offset(180, 40));
    await tester.pumpAndSettle();

    // 历史分段
    await pumpPage(tester, dark: false, width: 360, height: 900, scale: 1);
    await tester.tap(find.byKey(const Key('training-segment-history')));
    await tester.pumpAndSettle();
    await shot(
      tester,
      'training-history-light-360-1.0',
      const Key('training-segment-history'),
    );

    // 「训练回顾」弹层（Round7 逐页对账批次 4：A `app.js:559` 的只读回顾）
    await tester.tap(find.textContaining('2026-10-14').first);
    await tester.pumpAndSettle();
    await shot(
      tester,
      'training-review-sheet-light-360-1.0',
      const Key('training-review-sheet'),
    );
    await tester.tapAt(const Offset(180, 40)); // 点弹层外关闭
    await tester.pumpAndSettle();

    // 模式弹层（FAB）
    await pumpPage(tester, dark: false, width: 360, height: 900, scale: 1);
    await tester.tap(find.byKey(const Key('cta-new-plan')));
    await tester.pumpAndSettle();
    await shot(
      tester,
      'training-mode-sheet-light-360-1.0',
      const Key('plan-mode-manual'),
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });

  testWidgets('AI 计划抽屉：请求表单（无重复天数标签）与一披露行（2 帧 × 浅深）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    // 2026-10-23 用户：「删『AI 生成训练计划』按钮，功能转移到 ➕；改成先选/
    // 填目标关键词，再由 AI 从动作库选动作」。页内那张 AI 抽屉退役 → 这里
    // 改为直接渲染 FAB 模式弹层里「AI 生成」的目标页 `/workout-plan-create`。
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 900);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      await tester.pumpWidget(
        RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(
              dark ? AppTheme.dark() : AppTheme.light(),
            ),
            home: WorkoutPlanCreatePage(
              exerciseRepository: exercises,
              workoutPlanRepository: plans,
              workoutPlanProvider: const _NeverCalledProvider(),
              loadWorkoutPlanDisclosure: LoadWorkoutPlanDisclosure(
                configurationReader: const _StubConfigReader(),
              ),
              now: now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('plan-create-goal')), findsOneWidget);
      expect(find.byKey(const Key('plan-goal-keyword-增肌')), findsOneWidget);
      expect(
        find.byKey(const Key('plan-create-exercise-hint')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: '训练-ai-form-$theme');
      await captureRound7(tester, 'training-ai-form-$theme-360-1.0');

      // 目标关键词填进目标 → 进披露（披露只剩一行：发给谁 + 发什么）。
      await tester.tap(find.byKey(const Key('plan-goal-keyword-增肌')));
      await tester.pump();
      await tester.tap(find.text('下一步：查看披露'));
      await tester.pumpAndSettle();
      expect(find.textContaining('api.example.com'), findsOneWidget);
      expect(find.textContaining('不会发送'), findsNothing);
      expect(tester.takeException(), isNull, reason: '训练-ai-disclosure-$theme');
      await captureRound7(tester, 'training-ai-disclosure-$theme-360-1.0');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets('训练页：会话进行中 + 会话详情（2 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await seedPlanAndHistory();
    // 起一个进行中的会话（横幅 + 会话详情）。
    final activeId = await sessions.start(localDate: '2026-10-14');
    await sessions.logSet(
      activeId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-bench-press',
        weightKg: 60,
        reps: 8,
        rpe: 7,
      ),
    );

    await pumpPage(tester, dark: false, width: 360, height: 900, scale: 1);
    await shot(
      tester,
      'training-active-light-360-1.0',
      const Key('training-active-banner'),
    );

    // 会话详情由横幅里的「继续训练」打开（两个入口同一弹层）。
    await tester.tap(find.byKey(const Key('cta-continue-session')));
    await tester.pumpAndSettle();
    await shot(
      tester,
      'training-session-sheet-light-360-1.0',
      const Key('training-session-finish'),
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });

  testWidgets('训练页：空态（1 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    await pumpPage(tester, dark: false, width: 360, height: 900, scale: 1);
    await shot(
      tester,
      'training-empty-light-360-1.0',
      const Key('cta-new-plan'),
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });

  testWidgets('动作库页：网格 / 肌群筛选 / 详情弹层（4 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    for (final (dark, width, height, scale, name) in [
      (false, 360.0, 900.0, 1.0, 'library-light-360-1.0'),
      (true, 360.0, 900.0, 1.0, 'library-dark-360-1.0'),
      (false, 320.0, 900.0, 2.0, 'library-light-320-2.0'),
    ]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, height);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(
              dark ? AppTheme.dark() : AppTheme.light(),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: ExerciseLibraryPage(repository: exercises),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$name：布局溢出');
      expect(find.byKey(const Key('training-exercise-search')), findsOneWidget);
      await captureRound7(tester, name);
    }

    // 详情弹层（点第一张卡片）
    tester.view.physicalSize = const Size(360, 900);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: round7CaptureTheme(AppTheme.light()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: ExerciseLibraryPage(repository: exercises),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 打开详情的既有做法（照抄 `exercise_library_page_test` 的两步：
    // 搜索筛出目标 ⇒ 用**网格自己的** Scrollable 滚到卡片可见，再点卡片键）。
    await tester.enterText(
      find.byKey(const Key('training-exercise-search')),
      '深蹲',
    );
    await tester.pump(ExerciseLibraryPage.searchDebounce);
    await tester.pumpAndSettle();
    const cardKey = Key('training-exercise-ex-barbell-squat');
    await tester.scrollUntilVisible(
      find.byKey(cardKey),
      200,
      scrollable: find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(cardKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('同肌群替代动作'), findsOneWidget, reason: '动作详情弹层');
    await captureRound7(tester, 'library-detail-light-360-1.0');

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

final class _Ids implements IdGenerator {
  _Ids(this._prefix);

  final String _prefix;
  int _value = 0;

  @override
  String next() => '$_prefix-${_value++}';
}

/// 帧捕获不得调用真实 AI：本用例只走到「披露」为止，生成入口一旦被调用就是
/// 用例写错了（如实抛，不静默返回假草案）。
final class _NeverCalledProvider implements WorkoutPlanProvider {
  const _NeverCalledProvider();

  @override
  Future<AiWorkoutPlanDraft> generate(
    AiWorkoutPlanRequest request, {
    WorkoutPlanCancellationToken? cancellationToken,
  }) {
    throw StateError('帧捕获用例不得生成训练计划（会真的发请求）');
  }
}

/// 固定配置读取器：披露行需要「目的地主机 · 模型」两个事实，这里给固定值。
final class _StubConfigReader implements AiProviderConfigurationReader {
  const _StubConfigReader();

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      const AiProviderConfiguration(
        baseUrl: 'https://api.example.com/v1',
        model: 'glm-4-air',
      );
}
