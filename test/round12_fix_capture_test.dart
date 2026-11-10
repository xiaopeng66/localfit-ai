@Tags(['capture'])
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/app/design/widgets/lf_energy_card.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_quick_stats_row.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/domain/nutrition_target_override.dart';
import 'package:localfit_ai/features/nutrition/presentation/custom_meal_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_entry_chooser_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_target_sheet.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/presentation/steps_permission_sheet.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// **2026-10-26 四项修复的取帧件**：自由训练入口 / 步数（刚开始读取 + 手动
/// 记录）/ 自定义一顿 / 手动营养目标。逐张自己看过才算数。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 训练页的活动横幅 / 容量图是**无限动画**（animate-pulse），`pumpAndSettle`
  // 永远等不完（`training_page_test.dart` 里记着同一条教训）。全文件按「系统
  // 开启减弱动画」跑：装饰动效退化为瞬时，帧内容不变。
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  final now = DateTime(2026, 10, 26, 12);
  late AppDatabase database;

  const stepsChannel = MethodChannel('localfit/steps');

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    // 步数卡：原生通道给一个「有传感器、累计 5000」的读数。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(stepsChannel, (call) async {
          switch (call.method) {
            case 'read':
              return <Object?, Object?>{
                'status': 'ok',
                'counter': 5000,
                'atMs': 1,
              };
            case 'requestPermission':
              return <Object?, Object?>{'status': 'granted'};
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(stepsChannel, null);
  });

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  Future<void> pumpSurface(
    WidgetTester tester,
    Widget child, {
    double width = 412,
    double height = 900,
    bool wrapScaffold = true,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, height)),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            home: wrapScaffold
                ? Scaffold(
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: child,
                    ),
                  )
                : child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // ── 1. 自由训练：没有计划时的入口 ──────────────────────────────────────
  testWidgets('修复·自由训练入口（没有计划也能记录）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    // 动作种子导入有**真实异步 I/O**：在 fake_async 的测试体里直接 await 会
    // 挂死（实测 5 分钟 "did not complete"），必须走 `runAsync`。
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    await pumpSurface(
      tester,
      TrainingPage(
        exerciseRepository: ExerciseRepository(
          database: database,
          idGenerator: _Ids('ex'),
          clock: FixedAppClock(now.toUtc()),
        ),
        workoutPlanRepository: WorkoutPlanRepository(
          database: database,
          idGenerator: _Ids('plan'),
          clock: FixedAppClock(now.toUtc()),
        ),
        workoutSessionRepository: WorkoutSessionRepository(
          database: database,
          idGenerator: _Ids('session'),
          clock: FixedAppClock(now.toUtc()),
        ),
        now: now,
      ),
      height: 1100,
      wrapScaffold: false,
    );
    // 滚到底把空态（含新按钮）带进画面。
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await tester.pumpAndSettle();
    await shot(
      tester,
      'fix-free-training-entry',
      const Key('training-start-free-empty'),
    );
    await unmount(tester);
  });

  testWidgets('修复·自由训练入口（有计划但今天不是训练日）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    final plans = WorkoutPlanRepository(
      database: database,
      idGenerator: _Ids('plan'),
      clock: FixedAppClock(now.toUtc()),
    );
    // 2026-10-26 是周一（weekday 1）；计划只排周四 ⇒ 今天不是计划日。
    await plans.create(
      const WorkoutPlanDraft(
        name: '推日',
        days: [
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
    await pumpSurface(
      tester,
      TrainingPage(
        exerciseRepository: ExerciseRepository(
          database: database,
          idGenerator: _Ids('ex'),
          clock: FixedAppClock(now.toUtc()),
        ),
        workoutPlanRepository: plans,
        workoutSessionRepository: WorkoutSessionRepository(
          database: database,
          idGenerator: _Ids('session'),
          clock: FixedAppClock(now.toUtc()),
        ),
        now: now,
      ),
      height: 1100,
      wrapScaffold: false,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    await shot(
      tester,
      'fix-free-training-restday',
      const Key('training-free-session'),
    );
    await unmount(tester);
  });

  // ── 2. 步数：刚开始读取（不写 0）+ 手动记录弹层 ────────────────────────
  testWidgets('修复·步数卡（刚开始读取，不显示 0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final repository = StepsRepository(
      database: database,
      channel: StepsChannel(),
      idGenerator: _Ids('steps'),
      clock: FixedAppClock(now.toUtc()),
    );
    await pumpSurface(
      tester,
      DashboardQuickStatsRow(
        water: WaterSummary.empty,
        stepsRepository: repository,
        localDate: '2026-10-26',
      ),
      height: 260,
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpAndSettle();
    await shot(tester, 'fix-steps-starting', const Key('dashboard-stat-steps'));
    await unmount(tester);
  });

  testWidgets('修复·步数弹层（手动记录 + 重新读取）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final repository = StepsRepository(
      database: database,
      channel: StepsChannel(),
      idGenerator: _Ids('steps'),
      clock: FixedAppClock(now.toUtc()),
    );
    await pumpSurface(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showStepsPermissionSheet(
                context,
                repository,
                localDate: '2026-10-26',
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
      height: 900,
      wrapScaffold: false,
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await shot(
      tester,
      'fix-steps-manual-sheet',
      const Key('steps-manual-entry'),
    );
    await unmount(tester);
  });

  // ── 3. 自定义一顿 ──────────────────────────────────────────────────────
  testWidgets('修复·记餐入口三项（含自定义）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(tester, const MealRecordEntryChooser(), height: 460);
    await shot(
      tester,
      'fix-meal-entry-chooser',
      const Key('meal-entry-by-custom'),
    );
    await unmount(tester);
  });

  testWidgets('修复·自定义一顿弹层', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      CustomMealSheet(
        localDate: '2026-10-26',
        initialSlot: MealSlot.lunch,
        onSubmit: (_) async => null,
      ),
      height: 900,
    );
    await shot(tester, 'fix-custom-meal-sheet', const Key('custom-meal-sheet'));
    await unmount(tester);
  });

  // ── 4. 手动营养目标 ───────────────────────────────────────────────────
  testWidgets('修复·营养目标弹层（四行区间）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      NutritionTargetSheet(
        effectiveDate: '2026-10-26',
        current: NutritionTargetOverride(
          effectiveDate: '2026-10-26',
          calorieMinKcal: 1760,
          calorieMaxKcal: 1950,
          proteinMinGrams: 96,
          proteinMaxGrams: 120,
          carbsMinGrams: 161,
          carbsMaxGrams: 270,
          fatMinGrams: 42,
          fatMaxGrams: 60,
        ).toTarget(),
        onSave: (_) async => null,
        onRestore: () {},
      ),
      height: 900,
    );
    await shot(tester, 'fix-nutrition-target-sheet', const Key('target-save'));
    await unmount(tester);
  });

  testWidgets('修复·热量卡调整目标图标钮（说明行已撤）+ 可点', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final meals = MealRepository(
      database: database,
      idGenerator: _Ids('meal'),
      clock: FixedAppClock(now.toUtc()),
    );
    await meals.saveManualTarget(
      NutritionTargetOverride(
        effectiveDate: '2026-10-26',
        calorieMinKcal: 1760,
        calorieMaxKcal: 1950,
        proteinMinGrams: 96,
        proteinMaxGrams: 120,
        carbsMinGrams: 161,
        carbsMaxGrams: 270,
        fatMinGrams: 42,
        fatMaxGrams: 60,
      ),
    );
    final summary = await meals.watchNutritionForDate('2026-10-26').first;
    await pumpSurface(
      tester,
      SizedBox(
        width: 380,
        child: LfEnergyCard(
          consumed: const NutritionValues(
            kcal: 1200,
            proteinGrams: 60,
            carbsGrams: 120,
            fatGrams: 40,
          ),
          target: summary.target,
          title: '今日营养',
          cardKey: const Key('harness-energy'),
          keyPrefix: 'harness',
          remainingKey: const Key('harness-remaining'),
          statusKey: const Key('harness-status'),
          onEditTarget: () {},
        ),
      ),
      height: 480,
    );
    await shot(
      tester,
      // 【2026-10-28 改名】说明行撤下后，帧内容从「手动设定文字」变为
      // 「调整目标图标钮 + 还可摄入一行」；哨兵（编辑目标图标钮）不变。
      'fix-energy-edit-target-entry',
      const Key('harness-edit-target'),
    );
    await unmount(tester);
  });
}

final class _Ids implements IdGenerator {
  _Ids(this._prefix);
  final String _prefix;
  int _value = 0;

  @override
  String next() => '$_prefix-${_value++}';
}
