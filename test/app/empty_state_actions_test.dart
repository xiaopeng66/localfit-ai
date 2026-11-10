import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_meals_card.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/presentation/exercise_library_page.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';

import '../support/food_fixture.dart';

/// E-1（docs/64 阶段 3）：**每个空态都给一个能做的事**，且点了有效果
/// （不是空回调）。docs/64 的空态清单：
/// - 已有 action（既有 key，保持）：食堂「添加地点」（canteen-add-venue）、
///   训练计划空态（training-start-free-empty）、食物库空态（自带 action 支持）；
/// - 本轮补齐（本文件逐条钉）：今日页记一餐 / 菜单页两个空态 / 动作库新建 /
///   训练历史自由训练。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  final now = DateTime(2026, 10, 26, 12);

  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> end(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  // 【2026-10-31 用户：「删除今日界面的『记一餐』按钮，只显示记录」】
  // 原用例（点 `dashboard-empty-action` 触发记餐回调）随按钮一起退役；
  // 改写为反向断言：空态只陈述事实，不再有记餐按钮或空回调槽。记餐入口
  // 仍在今日页下一餐卡（`cta-log-next-meal`）与饮食页 FAB 上。
  testWidgets('今日页餐次卡空态：不再有「记一餐」按钮（只显示记录）', (tester) async {
    tester.view.physicalSize = const Size(390, 844 * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DashboardMealsCard(
              entries: const [],
              meals: const <MealRecord>[],
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.byKey(const Key('dashboard-meals-empty')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-empty-action')), findsNothing);
    expect(find.text('记一餐'), findsNothing);
    await end(tester);
  });

  testWidgets('菜单页（未接线）空态：「去食堂目录」点了就触发跳转回调', (tester) async {
    tester.view.physicalSize = const Size(390, 844 * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var openTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuDishList(
            repository: null,
            onOpenCanteen: () => openTaps++,
            searchService: const DishSearchService(),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(find.byKey(const Key('menu-empty-action')), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu-empty-action')));
    expect(openTaps, 1);
    await end(tester);
  });

  testWidgets('菜单页（库为空）空态：「让 AI 生成今日菜单」触发内联重配（不跳对话页）', (tester) async {
    tester.view.physicalSize = const Size(390, 844 * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dishes = DishLibraryRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now.toUtc()),
    );
    var swapTaps = 0;
    var askAiTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuDishList(
            repository: dishes,
            // 2026-11-10（用户）：空态按钮内联调「换一套」，不再走
            // onAskAiForSet 跳对话页。两条回调都注入，断言只有 swap 被点。
            onSwapSetWithAi: () async {
              swapTaps++;
              return null;
            },
            onAskAiForSet: () async {
              askAiTaps++;
              return true;
            },
            searchService: const DishSearchService(),
            now: now,
          ),
        ),
      ),
    );
    await settle(tester, 20);

    expect(find.byKey(const Key('menu-empty-action')), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu-empty-action')));
    expect(swapTaps, 1, reason: '空态按钮走内联 AI 重配');
    expect(askAiTaps, 0, reason: '不再跳 AI 对话页');
    await end(tester);
  });

  testWidgets('动作库搜不到时：「新建自定义动作」打开既有新建表单', (tester) async {
    tester.view.physicalSize = const Size(390, 844 * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await seedFoodFixture(database);
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    final exercises = ExerciseRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now.toUtc()),
    );
    await tester.pumpWidget(
      MaterialApp(home: ExerciseLibraryPage(repository: exercises)),
    );
    await settle(tester, 20);

    // 搜一个必然命不中的词，让网格落到空态。
    await tester.enterText(find.byType(TextField).first, '绝对不会存在的动作名');
    await settle(tester, 20);
    expect(
      find.byKey(const Key('exercise-library-empty-action')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('exercise-library-empty-action')));
    await settle(tester);
    // 有效果 = 真的打开了「新建动作」表单（与右上角 ➕ 同一条流程）。
    expect(find.byKey(const Key('training-exercise-name')), findsOneWidget);
    await end(tester);
  });

  testWidgets('训练历史空态：「开始一次自由训练」真的开出会话', (tester) async {
    tester.view.physicalSize = const Size(390, 844 * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await seedFoodFixture(database);
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    final clock = FixedAppClock(now.toUtc());
    final sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TrainingPage(
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
          workoutSessionRepository: sessions,
          now: now,
        ),
      ),
    );
    await settle(tester, 20);
    await tester.tap(find.byKey(const Key('training-segment-history')));
    await settle(tester);

    expect(
      find.byKey(const Key('training-history-empty-action')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('training-history-empty-action')));
    await settle(tester);

    expect(find.text('训练进行中'), findsOneWidget, reason: '点了要真的开弹层');
    expect(await sessions.getActive(), isNotNull, reason: '点了要真的开出会话');
    await end(tester);
  });
}
