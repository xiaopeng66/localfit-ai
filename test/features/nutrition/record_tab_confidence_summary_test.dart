import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/record_tab.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// 记录页的置信摘要（docs/22 裁决 ② + 阶段 I 补漏；阶段 2B 步骤 4 改位置）。
///
/// 置信摘要（已确认 N 项 · 估算 M 项）在设计稿的今日页里没有位置，重建后
/// 一度没有任何可达入口；本文件盯住它的接入：数据走选中日的餐食流，
/// 空列表时整条不渲染。
///
/// **位置**：阶段 2B 步骤 4 起按 A 的 `.source-summary` 挪到**页级一行**
/// ——热量卡之下、趋势卡之上（`padding:4px 0`，不是卡片），不再挂在
/// `nutrition-record-analysis` 卡尾（卡尾 `footer` 槽位随之退场）。
void main() {
  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;

  final now = DateTime(2026, 9, 9, 12);
  const today = '2026-09-09';

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final ids = _IncrementingIdGenerator();
    foods = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
    meals = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
  });

  tearDown(() => database.close());

  Future<void> seedFood() async {
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'food-rice',
            name: '米饭',
            kcalPer100g: 116,
            proteinPer100g: 2.6,
            carbsPer100g: 25.9,
            fatPer100g: 0.3,
            source: 'seed',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
  }

  /// 真趋势（记录页据此渲染分析卡；摘要另有自己的餐食流）。
  IntakeTrend trendOf(List<DailyIntakeRecord> records) =>
      const TrendCalculator().calculate(records: records, goal: null);

  /// 档案 + 目标：给热量卡与分析卡一个真实分母（趋势卡的「达标 N/7」
  /// 徽标已在 2B 步骤 4 按 D13 退役，达标天数由分析卡承载）。
  Future<void> seedTarget() async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'p1',
            activityLevel: 'moderate',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'g1',
            profileId: 'p1',
            type: 'loseFat',
            calorieMinKcal: 1500,
            calorieMaxKcal: 1800,
            effectiveFrom: now.toUtc(),
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 't1',
            goalId: 'g1',
            effectiveDate: '2026-09-01',
            calorieMinKcal: 1500,
            calorieMaxKcal: 1800,
            proteinMinGrams: 50,
            proteinMaxGrams: 60,
            carbsMinGrams: 180,
            carbsMaxGrams: 200,
            fatMinGrams: 40,
            fatMaxGrams: 50,
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
  }

  Future<void> pumpTab(WidgetTester tester, IntakeTrend trend) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordTab(
            mealRepository: meals,
            selectedDate: DateTime(2026, 9, 9),
            now: now,
            onSelectDate: (_) {},
            onEditMeal: (_) {},
            onDeleteMeal: (_) {},
            // 生产装配（`nutrition_page._recordBody`）恒接这个回调；本夹具
            // 一并对齐，否则槽位加号（A 仅今天渲染）在测试里根本不存在，
            // §5.2 的 Key 覆盖会漏掉它。
            onAddToSlot: (_) {},
            loadTrend: (days, endDate) async => trend,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 分析卡在长页底部（懒加载 sliver）：不滚过去它根本不会构建。
  Future<void> scrollToAnalysis(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('nutrition-record-analysis')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// 排掉 drift StreamBuilder dispose 时 schedule 的「0 时延」close timer。
  Future<void> drainStream(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('混合来源：manual 1 项 + ai_scan 2 项 → 页级摘要写「已确认 1 · 估算 2」', (
    tester,
  ) async {
    await seedFood();
    final rice = (await foods.search('米饭')).first;
    await meals.create(
      MealDraft(
        localDate: today,
        slot: MealSlot.lunch,
        items: [MealItemDraft.fromFood(rice, 100)],
      ),
    );
    await meals.create(
      MealDraft(
        localDate: today,
        slot: MealSlot.dinner,
        items: [
          MealItemDraft.fromFood(rice, 80),
          MealItemDraft.fromFood(rice, 60),
        ],
      ),
      source: 'ai_scan',
    );

    await pumpTab(
      tester,
      trendOf(const [
        DailyIntakeRecord(
          localDate: today,
          kcal: 278.4,
          proteinGrams: 6.24,
          carbsGrams: 62.16,
          fatGrams: 0.72,
        ),
      ]),
    );
    // A 的 source-summary 在热量卡之下，首屏即可见——不必滚到底部。
    expect(
      find.byKey(const Key('confidence-summary')),
      findsOneWidget,
      reason: '置信摘要必须能从记录页到达（阶段 I 补漏接线）',
    );
    expect(find.text('已确认 1 项 / 估算 2 项'), findsOneWidget);
    // 位置：热量卡之下（A `.source-summary`），且**不在**分析卡里（卡尾退场）。
    expect(
      tester.getRect(find.byKey(const Key('confidence-summary'))).top,
      greaterThan(
        tester.getRect(find.byKey(const Key('nutrition-record-energy'))).bottom,
      ),
    );
    await scrollToAnalysis(tester);
    expect(find.byKey(const Key('nutrition-record-analysis')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('nutrition-record-analysis')),
        matching: find.byKey(const Key('confidence-summary')),
      ),
      findsNothing,
      reason: '摘要已挪到页级一行，分析卡尾不再挂它',
    );
    await drainStream(tester);
  });

  testWidgets('当天没有餐食：分析卡在，摘要整条不渲染（不显示 0/0 空转行）', (tester) async {
    await pumpTab(tester, trendOf(const []));

    expect(find.byKey(const Key('confidence-summary')), findsNothing);
    await scrollToAnalysis(tester);
    expect(find.byKey(const Key('nutrition-record-analysis')), findsOneWidget);
    await drainStream(tester);
  });

  // ---- docs/21 §5.2 Key 表覆盖（阶段 I-4：Key 是设计契约）----
  testWidgets('docs/21 §5.2 Key 覆盖：页首卡四段 / 摘要行 / 趋势卡 / 餐卡都能定位', (tester) async {
    await seedFood();
    await seedTarget();
    final rice = (await foods.search('米饭')).first;
    await meals.create(
      MealDraft(
        localDate: today,
        slot: MealSlot.lunch,
        items: [MealItemDraft.fromFood(rice, 100)],
      ),
    );
    await pumpTab(
      tester,
      trendOf(const [
        DailyIntakeRecord(
          localDate: today,
          kcal: 278.4,
          proteinGrams: 6.24,
          carbsGrams: 62.16,
          fatGrams: 0.72,
        ),
      ]),
    );

    // 首屏四段：页首热量卡 + 已摄入 / 目标 / 剩余（阶段 2B D10 起 4 个锚点
    // 分别落在卡体、环心两段与脚注剩余行上，旧的 `nutrition-record-hero*` 退役）。
    for (final key in [
      'nutrition-record-energy',
      'nutrition-record-energy-consumed',
      'nutrition-record-energy-target',
      'nutrition-record-energy-remaining',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }

    // 摘要行与页首卡同屏（A 的 source-summary 紧跟热量卡）。
    expect(find.byKey(const Key('confidence-summary')), findsOneWidget);

    // 趋势卡 / 槽位分组卡都在页首卡之下（懒加载 sliver）：真滚过去才构建。
    final missing = <String>[];
    for (final key in [
      'nutrition-record-trend-chart',
      'nutrition-record-trend-tracked',
      'nutrition-record-trend-plot',
      // 2026-10-14（步骤 5，D12）：跨槽位全局序号的
      // `nutrition-record-meal-card-<i>` 退役，餐卡的稳定锚点回到 `meal-<id>`
      // （编辑/删除/多选都按它定位）；槽位分组自己的锚点是四张槽位卡。
      'nutrition-record-slot-breakfast',
      'nutrition-record-slot-lunch',
      'nutrition-record-slot-dinner',
      'nutrition-record-slot-snack',
      'nutrition-record-slot-lunch-total',
      'nutrition-record-slot-lunch-add',
    ]) {
      var found = find.byKey(Key(key)).evaluate().isNotEmpty;
      for (var i = 0; i < 12 && !found; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await tester.pump();
        found = find.byKey(Key(key)).evaluate().isNotEmpty;
      }
      if (!found) missing.add(key);
    }
    expect(missing, isEmpty, reason: '未在记录页找到：${missing.join('、')}');
    // 目标真的落到趋势卡上（不是停在「尚未设定目标」——那是 value 变了但
    // 兄弟卡没重建的陈旧渲染缺陷，本断言是它的哨兵）：上界 = max(2200, 1800,
    // 峰值) = 2200，目标虚线标签写真实目标值。
    // 2026-10-22 纵轴改四档：不可见的**尺寸锚文本**与 Positioned 刻度各有一
    // 份「2,200」⇒ 用「至少一份」口径（单独文件已逐字钉过）。
    expect(find.text('2,200'), findsWidgets);
    expect(find.text('目标 1,800'), findsOneWidget);
    expect(find.text('1 天有记录'), findsOneWidget);
    // 退役项：A 的趋势卡只有标题 + `N 天有记录`，副标题与达标徽标都不在了
    // （D13——达标天数留在分析卡）。
    expect(find.byKey(const Key('nutrition-record-trend-goal')), findsNothing);
    expect(find.textContaining('摄入 vs 目标'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('nutrition-record-trend-chart')),
        matching: find.textContaining('达标'),
      ),
      findsNothing,
    );
    await drainStream(tester);
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'conf-${_value++}';
}
