import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

import '../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;
  late MeasurementRepository measurementRepository;
  final now = DateTime(2026, 9, 9, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    final ids = _IncrementingIdGenerator();
    foodRepository = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
    mealRepository = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
    measurementRepository = MeasurementRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
  });

  tearDown(() => database.close());

  testWidgets('records a meal and refreshes today nutrition', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.nutrition,
        foodRepository: foodRepository,
        mealRepository: mealRepository,
        now: now,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('记录一餐'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('meal-entry-by-food')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('meal-food-search')), '米饭');
    await tester.pumpAndSettle();
    await tester.tap(find.text('米饭').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('meal-grams-item-1')), '200');
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    expect(find.text('餐食已保存到本机。'), findsOneWidget);
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();

    // 新今日页（Round7 A）：摄入量是圆环中心值；午餐出现在今日餐次卡的
    // 行里（Key `dashboard-meal-row-<slot>-<i>`）；剩余额度行搬进热量卡
    // foot（`dashboard-remaining-line` 锚点保留）。
    // Round7 A 的 `.energy-summary` 标题就是「今日营养」（`app.js:128`：
    // 今天 = 今日营养 / 历史 = 当日营养），旧版无标题的形态已不在。
    expect(find.text('今日营养'), findsOneWidget);
    // 232 现在同时出现在**两处**：圆环中心值（`dashboard-ring-consumed`）与
    // 新餐次卡的行值——纯文本 finder 会命中 2 个（round7 2A 实测），所以
    // 两处各锚 Key 断一次，谁也不许消失。
    expect(
      tester
          .widget<Text>(find.byKey(const Key('dashboard-ring-consumed')))
          .data,
      '232',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('dashboard-meal-row-lunch-0')),
        matching: find.text('232'),
      ),
      findsOneWidget,
      reason: '餐次行值 = meal.nutrition.kcal（A 的 `.meal-kcal` 14 w600）',
    );
    expect(
      find.byKey(const Key('dashboard-meal-row-lunch-0')),
      findsOneWidget,
      reason: '刚记录的午餐必须出现在今日餐次卡里',
    );
    // 这份夹具**不建 profile**（没有热量目标），所以 foot 只有「尚未设定目标 /
    // 设置目标后查看进度」——剩余额度行在有目标时才存在（A 的 `remaining`
    // 为 null 分支），旧断言在这一档夹具里恒不成立。有目标的剩余行由
    // round7_dashboard_today_test 与 food_scan_save_flow_test 钉住。
    expect(find.byKey(const Key('dashboard-remaining-line')), findsNothing);
    expect(find.text('设置目标后查看进度'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('records weight and refreshes seven-day overview', (
    tester,
  ) async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile',
            activityLevel: 'lightlyActive',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    await measurementRepository.saveManualWeight(
      localDate: '2026-09-08',
      weightKg: 75,
    );
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      LocalFitApp(
        mealRepository: mealRepository,
        measurementRepository: measurementRepository,
        now: now,
      ),
    );
    await tester.pumpAndSettle();
    // 新今日页（docs/21 §5.1）：体重卡副标题直接写最新值与周变化；
    // 旧的「7 日平均：X kg」与 `weight-bar-chart` 属于已删除的柱状图卡。
    expect(find.textContaining('75.0 kg'), findsWidgets);

    // 入口是卡头 §3.8 的 B6 文字按钮（`dashboard-weight-add`）。
    //
    // 原先点的是空态那颗 `dashboard-weight-record`。2026-10-08 R2 之后
    // 「1 条记录」不再算空态（建档时已落一条体重，柱图天然支持单柱），
    // 于是空态入口不存在——这条测试要的是「能打开录入弹层并保存」，
    // 换成卡头那颗同样走 `WeightEntryDialog` 的按钮，断言目标不变。
    await tester.tap(find.byKey(const Key('dashboard-weight-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('weight-input')), '20');
    await tester.tap(find.byKey(const Key('weight-save')));
    await tester.pump();
    expect(find.text('体重必须在 35–300 kg 之间'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('weight-input')), '74');
    await tester.tap(find.byKey(const Key('weight-save')));
    await tester.pumpAndSettle();

    // 新写入的 74.0 必须出现在卡上（真值驱动，不是缓存）。
    expect(find.textContaining('74.0'), findsWidgets);
    expect(find.text('体重已保存到本机。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  // 旧的 `trend-card` / `nutritional-trend-card` 属于 bento 时代的卡片：
  // 前者（营养分析）按 docs/22 阶段 H 收进饮食·记录页的二级入口
  // （组件测试迁到 nutrition_analysis_section_test），后者在阶段 I-2b 随
  // 旧件删除；`dashboard-training-targets` 收进训练页入口，其组件测试仍在
  // dashboard_training_targets_test 跑。本用例断言新今日页对同一批真值的
  // 反映：有记录的餐出现在时间线上、剩余行按目标算。
  testWidgets('今日页反映真值：已记录的餐上时间线，剩余行按目标算', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ids = _IncrementingIdGenerator();
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'goal-profile',
            activityLevel: 'moderate',
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            // id 与下面 dailyTargets.goalId 必须一致：两边各调一次
            // `ids.next()` 会得到不同值，直接撞外键 787。
            id: 'goal-trend',
            profileId: 'goal-profile',
            type: 'lose_fat',
            calorieMinKcal: 1500,
            calorieMaxKcal: 2000,
            effectiveFrom: DateTime.utc(2026, 9, 1),
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: ids.next(),
            goalId: 'goal-trend',
            effectiveDate: '2026-09-01',
            calorieMinKcal: 1500,
            calorieMaxKcal: 2000,
            proteinMinGrams: 100,
            proteinMaxGrams: 140,
            carbsMinGrams: 200,
            carbsMaxGrams: 260,
            fatMinGrams: 50,
            fatMaxGrams: 70,
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-trend',
            localDate: '2026-09-09',
            slot: 'lunch',
            eatenAt: DateTime.utc(2026, 9, 9, 12),
            source: 'manual',
            createdAt: DateTime.utc(2026, 9, 9, 12),
            updatedAt: DateTime.utc(2026, 9, 9, 12),
          ),
        );
    final rice = (await foodRepository.search('米饭'))
        .firstWhere((food) => food.name == '米饭');
    await database
        .into(database.mealItems)
        .insert(
          MealItemsCompanion.insert(
            id: 'item-trend',
            mealId: 'meal-trend',
            foodId: Value(rice.id),
            foodNameSnapshot: rice.name,
            grams: 1300,
            kcalSnapshot: 1508,
            proteinSnapshot: 5.2,
            carbsSnapshot: 51.8,
            fatSnapshot: 0.6,
            createdAt: DateTime.utc(2026, 9, 9, 12),
            updatedAt: DateTime.utc(2026, 9, 9, 12),
          ),
        );

    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.dashboard,
        foodRepository: foodRepository,
        mealRepository: mealRepository,
        now: now,
      ),
    );
    await tester.pumpAndSettle();

    // 真值：1508 kcal 摄入 / 2000 目标 → 剩余 492；午餐在餐次卡里。
    // 1,508 同时是环心值与餐次行值（同 `232` 那条用例的处境），锚 Key 断。
    expect(
      tester
          .widget<Text>(find.byKey(const Key('dashboard-ring-consumed')))
          .data,
      '1,508',
      reason: 'A `format()` ⇒ 千分位',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('dashboard-meal-row-lunch-0')),
        matching: find.text('1,508'),
      ),
      findsOneWidget,
      reason: '餐次行值同走千分位口径',
    );
    expect(
      find.textContaining('还可摄入 492 kcal', findRichText: true),
      findsOneWidget,
      reason: '2000 - 1508 = 492，剩余行必须按真值算',
    );
    expect(
      find.byKey(const Key('dashboard-meal-row-lunch-0')),
      findsOneWidget,
      reason: '已记录的午餐必须出现在今日餐次卡里',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'widget-id-${_value++}';
}
