@Tags(['capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_quick_stats_row.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_create_page.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

import 'package:flutter/services.dart';

import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_slot_grouping.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import 'support/food_fixture.dart';
import 'support/round7_render.dart';

/// 第三轮 · 第二批（版式类）的**取帧件**：动手前先看实图，别凭代码猜。
///
/// 覆盖两条「待实帧确认」的项（docs/60 §0 表格的 10 / 12）：
/// * 10 饮水/步数卡**内容**高度对齐（外层已有 `IntrinsicHeight`，偏心可能在
///   内层两行的基线）；
/// * 12 训练计划天数按钮文字**水平居中**（代码是 `LfPillButton('$d天')` 放在
///   `Expanded` 里，是否真偏心要看图）。
///
/// 同时给 13a/13b（右下浮动按钮）与 18（食物库品牌下一行）留取帧位——
/// 它们同样是版式类，改完要能出图对照。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required String frame,
    double width = 412,
    double scale = 1.0,
    double height = 900,
    bool wrapInScaffold = true,
  }) async {
    // `physicalSize` 是**物理像素**：dpr 2 时必须 ×2，否则逻辑宽只有一半
    // （第一版就是这么把 412 变成 206 的——两格被迫降级成单列）。
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(scale),
        ),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            // 整页件（自带 Scaffold）不能再套一层滚动：它的列表在无界高度里
            // 会抛布局断言（第一版就是这么红的）。
            home: wrapInScaffold
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
    await captureRound7(tester, frame);
  }

  late AppDatabase database;
  final now = DateTime(2026, 10, 25, 10);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
  });

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  testWidgets('10：饮水/步数两格并排（两卡都**有数据**时的内容行对齐）', (tester) async {
    // 两卡都「有数据」才是这条要看的场景：空态下步数卡多一行说明
    // （「这台设备没有计步传感器」），对齐与否看不出真实差异。
    const channel = MethodChannel('localfit/steps');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') {
            return <Object?, Object?>{
              'status': 'ok',
              'counter': 8432,
              'atMs': 1,
            };
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    final now = DateTime(2026, 10, 25, 10);
    final steps = StepsRepository(
      database: database,
      channel: StepsChannel(),
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(
      tester,
      DashboardQuickStatsRow(
        water: WaterSummary(
          consumedMl: 1250,
          targetMl: 2000,
          records: [
            WaterIntakeRecord(
              id: 'w1',
              localDate: '2026-10-25',
              amountMl: 1250,
              recordedAt: DateTime.utc(2026, 10, 25, 2),
              createdAt: DateTime.utc(2026, 10, 25, 2),
              updatedAt: DateTime.utc(2026, 10, 25, 2),
            ),
          ],
        ),
        stepsRepository: steps,
        localDate: '2026-10-25',
      ),
      frame: 'round3-10-quick-stats-412-1.0',
      height: 320,
    );
    // 收尾顺序（`ai_memory_page_test.dart` 同一条教训）：先卸页面取消 drift
    // 流订阅 → pump 一拍让零延迟计时器跑掉 → 再关库。顺序反了会留 pending
    // timer，用例挂到 10 分钟超时。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await database.close();
  });

  testWidgets('13a/13b：两页右下浮动按钮（真装配整页帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(412 * 2, 900 * 2);
    final ids = _Ids();
    final clock = FixedAppClock(now);
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    for (final (route, name, sentinel) in const [
      (
        AppRoutes.nutrition,
        'round3-13a-canteen-fab-412-1.0',
        'nutrition-tab-menu',
      ),
      (AppRoutes.training, 'round3-13b-training-fabs-412-1.0', 'cta-new-plan'),
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(
        RepaintBoundary(
          key: round7Boundary,
          child: LocalFitApp(
            initialLocation: route,
            foodRepository: FoodRepository(
              database: database,
              idGenerator: ids,
              clock: clock,
            ),
            mealRepository: MealRepository(
              database: database,
              idGenerator: ids,
              clock: clock,
            ),
            canteenRepository: CanteenRepository(
              database: database,
              idGenerator: ids,
              clock: clock,
            ),
            dishLibraryRepository: DishLibraryRepository(
              database: database,
              idGenerator: ids,
              clock: clock,
            ),
            exerciseRepository: ExerciseRepository(
              database: database,
              idGenerator: ids,
              clock: clock,
            ),
            workoutPlanRepository: WorkoutPlanRepository(
              database: database,
              idGenerator: ids,
              clock: clock,
            ),
            workoutSessionRepository: WorkoutSessionRepository(
              database: database,
              idGenerator: ids,
              clock: clock,
            ),
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (route == AppRoutes.nutrition) {
        await tester.tap(find.byKey(const Key('nutrition-tab-menu')));
        await tester.pumpAndSettle();
      }
      await shot(tester, name, Key(sentinel));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('20a/20b：记录页同名餐次合并成一张卡（只显示热量、不显示时间）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 两条午餐记录（12:00 / 13:00）：合并后应当是**一张卡**、食物在一起、
    // 卡头只有「午餐」没有时刻、底行只有来源徽标 + 备注 + 管理菜单。
    final ids = _Ids();
    final foods = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now),
    );
    for (final (name, kcal) in const [
      ('红烧肉盖浇饭', 156.0),
      ('凉拌黄瓜', 45.0),
      ('紫菜蛋花汤', 22.0),
    ]) {
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'cap-food-${name.hashCode.abs()}',
              name: name,
              kcalPer100g: kcal,
              proteinPer100g: 8,
              carbsPer100g: 20,
              fatPer100g: 5,
              source: 'seed',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    final meals = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now),
    );
    for (final (hour, name, grams, notes) in const [
      (12, '红烧肉盖浇饭', 250.0, '食堂二楼'),
      (13, '凉拌黄瓜', 120.0, null),
    ]) {
      final food = (await foods.search(name)).first;
      final at = DateTime(2026, 10, 25, hour);
      final repo = MealRepository(
        database: database,
        idGenerator: ids,
        clock: FixedAppClock(at),
      );
      await repo.create(
        MealDraft(
          localDate: '2026-10-25',
          slot: MealSlot.lunch,
          items: [MealItemDraft.fromFood(food, grams)],
          notes: notes,
        ),
        source: 'manual',
      );
    }
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(412, 900)),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: NutritionRecordSlotGrouping(
                  repository: meals,
                  localDate: '2026-10-25',
                  now: now,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await shot(
      tester,
      'round3-20-merged-meal-card-412-1.0',
      const Key('nutrition-record-slot-lunch'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('12：训练计划天数按钮（文字是否居中）', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await seedFoodFixture(database);
    final now = DateTime(2026, 10, 25, 10);
    final exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    final plans = WorkoutPlanRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(
      tester,
      WorkoutPlanCreatePage(
        exerciseRepository: exercises,
        workoutPlanRepository: plans,
        workoutPlanProvider: const _NeverCalledProvider(),
        loadWorkoutPlanDisclosure: LoadWorkoutPlanDisclosure(
          configurationReader: const _StubConfigReader(),
        ),
        now: now,
      ),
      frame: 'round3-12-plan-days-412-1.0',
      height: 1400,
      wrapInScaffold: false,
    );
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'r3-${_value++}';
}

/// 帧捕获不得调用真实 AI：只走到「披露」为止，生成入口被调用就是用例写错了。
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

final class _StubConfigReader implements AiProviderConfigurationReader {
  const _StubConfigReader();

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => null;
}
