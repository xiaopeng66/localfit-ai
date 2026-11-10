@Tags(['capture'])
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_meals_card.dart';
import 'package:localfit_ai/features/nutrition/application/swap_daily_set_with_ai.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';
import 'package:localfit_ai/features/settings/application/data_self_check.dart';
import 'package:localfit_ai/features/settings/presentation/data_self_check_page.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/presentation/exercise_library_page.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// 阶段 3（docs/64 D-1/D-2 + E-1）取帧件：自检页两态 + 空态动作。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  final now = DateTime(2026, 10, 26, 12);
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
  });

  tearDown(() => database.close());

  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> shot(WidgetTester tester, String name, Key? sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    if (sentinel != null) {
      expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    }
    await captureRound7(tester, name);
  }

  Future<void> pumpSurface(
    WidgetTester tester,
    Widget child, {
    double height = 1100,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(412 * 2, height * 2);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(412, height)),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            home: Scaffold(body: child),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('D-1 数据自检：有脏数据 / 无问题两态', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    // 有脏数据：孤儿引用 + 坏日期 + 过期手动步数 + 已备份。
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    await database.customStatement('PRAGMA foreign_keys = OFF');
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-orphan',
            localDate: '2026-10-20',
            slot: 'lunch',
            source: 'manual',
            eatenAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.mealItems)
        .insert(
          MealItemsCompanion.insert(
            id: 'item-orphan',
            mealId: 'meal-orphan',
            foodId: const Value('deleted-food'),
            foodNameSnapshot: '某种食物',
            grams: 100,
            kcalSnapshot: 100,
            proteinSnapshot: 5,
            carbsSnapshot: 20,
            fatSnapshot: 2,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-bad-date',
            localDate: '2026/10/01',
            slot: 'lunch',
            source: 'manual',
            eatenAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.stepsDaily)
        .insert(
          StepsDailyCompanion.insert(
            id: 'steps-old',
            localDate: '2026-09-01',
            steps: 3000,
            source: 'manual',
            recordedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'last_backup_at_ms',
            value: '${now.millisecondsSinceEpoch}',
          ),
        );
    final dirtyCheck = DataSelfCheck(
      database: database,
      clock: FixedAppClock(now.toUtc()),
    );
    await pumpSurface(
      tester,
      // 生产里该页进 AppSheet（壳自带 16dp 内衬）；取帧同衬，不然内容贴边。
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DataSelfCheckPage(selfCheck: dirtyCheck),
        ),
      ),
    );
    await settle(tester, 20);
    await shot(
      tester,
      'fix2-data-self-check',
      const Key('data-self-check-sheet'),
    );

    // 清库重开 → 无问题态（诚实说「没有发现问题」）。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.delete(database.mealItems).go();
    await database.delete(database.meals).go();
    await database.delete(database.stepsDaily).go();
    final cleanCheck = DataSelfCheck(
      database: database,
      clock: FixedAppClock(now.toUtc()),
    );
    await pumpSurface(
      tester,
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DataSelfCheckPage(selfCheck: cleanCheck),
        ),
      ),
    );
    await settle(tester, 20);
    await shot(
      tester,
      'fix2-data-self-check-clean',
      const Key('data-self-check-clean'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  // 【2026-10-31 用户：「删除今日界面的『记一餐』按钮，只显示记录」】
  // 取帧对象从 `dashboard-empty-action`（已退役）改为空态块本身：这张帧
  // 现在的用途是记录「卡里只剩事实陈述」的样子。
  testWidgets('E-1 空态动作：今日页记一餐（按钮已退役，仅留空态）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      const SingleChildScrollView(
        child: DashboardMealsCard(entries: [], meals: []),
      ),
    );
    await shot(
      tester,
      'fix2-empty-dashboard-meals',
      const Key('dashboard-meals-empty'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('E-1 空态动作：菜单页（库为空）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final dishes = DishLibraryRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now.toUtc()),
    );
    var aiRequests = 0;
    var canteenOpens = 0;
    await pumpSurface(
      tester,
      MenuDishList(
        repository: dishes,
        // 空态生成已改为原地换套；无供应是可解释的失败，不跳聊天或写摄入。
        onSwapSetWithAi: () async {
          aiRequests++;
          return const MenuSetSwapResult.unavailable(
            MenuSetSwapUnavailableReason.noSupply,
          );
        },
        onOpenCanteen: () => canteenOpens++,
        searchService: const DishSearchService(),
        now: now,
      ),
      height: 1200,
    );
    await settle(tester, 20);
    const aiAction = Key('menu-empty-action');
    const canteenAction = Key('menu-empty-action-canteen');
    expect(aiRequests, 0);
    expect(canteenOpens, 0);
    await shot(tester, 'fix2-empty-menu-ai', aiAction);

    await tester.tap(find.byKey(aiAction));
    await settle(tester);
    expect(aiRequests, 1, reason: '空态按钮必须调用当前内联生成入口');
    expect(canteenOpens, 0, reason: '生成失败不应自动跳转目录');
    expect(find.textContaining('食堂目录还没有供应'), findsOneWidget);
    expect(find.textContaining('没有可计算的本地候选'), findsOneWidget);
    expect(find.textContaining('重排一整套'), findsNothing);
    await shot(tester, 'fix2-empty-menu-ai-no-supply', aiAction);

    await tester.tap(find.byKey(canteenAction));
    await settle(tester);
    expect(canteenOpens, 1, reason: '无供应后仍可主动前往食堂目录补资料');
    expect(aiRequests, 1, reason: '目录入口不能误触发 AI 生成');
    expect(await database.select(database.meals).get(), isEmpty);
    expect(await database.select(database.mealItems).get(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('E-1 空态动作：动作库新建', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    final exercises = ExerciseRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now.toUtc()),
    );
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(412 * 2, 1100 * 2);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: const Size(412, 1100)),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            home: ExerciseLibraryPage(repository: exercises),
          ),
        ),
      ),
    );
    await settle(tester, 20);
    await tester.enterText(find.byType(TextField).first, '绝对没有的动作');
    await settle(tester, 20);
    await shot(
      tester,
      'fix2-empty-exercise-create',
      const Key('exercise-library-empty-action'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('E-1 空态动作：训练历史自由训练', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    final clock = FixedAppClock(now.toUtc());
    await pumpSurface(
      tester,
      TrainingPage(
        exerciseRepository: ExerciseRepository(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: clock,
        ),
        workoutPlanRepository: WorkoutPlanRepository(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: clock,
        ),
        workoutSessionRepository: WorkoutSessionRepository(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: clock,
        ),
        now: now,
      ),
      height: 1200,
    );
    await tester.tap(find.byKey(const Key('training-segment-history')));
    await settle(tester, 20);
    await shot(
      tester,
      'fix2-empty-training-history',
      const Key('training-history-empty-action'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
