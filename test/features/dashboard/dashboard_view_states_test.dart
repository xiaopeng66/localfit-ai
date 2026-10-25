import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_calorie_card.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';

/// 阶段 2 验收（docs/21 §5.1）：
///
/// - 「无目标、无记录、超标、查询错误均可达」——本条是阶段 2 的验收原话，
///   四态此前没有端到端断言。
/// - 「饮水/步数统计……若没有 domain/table，先显示明确『暂无记录』，不得用
///   HTML 示例数值冒充事实」——本地确实没有这两张表，所以断言必须是
///   「写暂无记录」且「不得出现 HTML 的示例数值」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;
  final now = DateTime(2026, 9, 17, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final ids = _Ids();
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
  });

  tearDown(() => database.close());

  Widget app({MealRepository? meals}) => LocalFitApp(
    initialLocation: AppRoutes.dashboard,
    foodRepository: foodRepository,
    mealRepository: meals ?? mealRepository,
    now: now,
  );

  Future<void> pumpDashboard(
    WidgetTester tester, {
    MealRepository? meals,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(meals: meals));
    await tester.pumpAndSettle();
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> scrollToQuickStats(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('dashboard-stat-water')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// 种一份目标（calorieMax 由调用方给，便于造「超标」态）。
  ///
  /// 必须先有 profiles 行：goals.profile_id 是外键，跳过它会
  /// SqliteException(787) FOREIGN KEY constraint failed。
  Future<void> seedTarget({required double calorieMax}) async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-stage2',
            activityLevel: 'moderate',
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-stage2',
            profileId: 'profile-stage2',
            type: 'lose_fat',
            calorieMinKcal: calorieMax - 500,
            calorieMaxKcal: calorieMax,
            effectiveFrom: DateTime.utc(2026, 9, 1),
            createdAt: DateTime.utc(2026, 9, 1),
            updatedAt: DateTime.utc(2026, 9, 1),
          ),
        );
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 'target-stage2',
            goalId: 'goal-stage2',
            effectiveDate: '2026-09-01',
            calorieMinKcal: calorieMax - 500,
            calorieMaxKcal: calorieMax,
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
  }

  /// 直接写一条餐食（带营养快照），用于造「超标」态。
  Future<void> seedMeal({required double kcal}) async {
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-stage2',
            localDate: '2026-09-17',
            slot: 'lunch',
            eatenAt: now.toUtc(),
            source: 'manual',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    await database
        .into(database.mealItems)
        .insert(
          MealItemsCompanion.insert(
            id: 'item-stage2',
            mealId: 'meal-stage2',
            foodNameSnapshot: '测试餐',
            grams: 100,
            kcalSnapshot: kcal,
            proteinSnapshot: 10,
            carbsSnapshot: 10,
            fatSnapshot: 10,
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
  }

  group('阶段 2 验收：四态可达', () {
    testWidgets('无目标：明确写「尚未设定目标」，不显示任何剩余额度', (tester) async {
      await pumpDashboard(tester);

      // 正向锚点：环本身必须存在，否则下面两条「不显示 X」在环根本没渲染时
      // 也会通过（那会让整组断言变成空转）。
      expect(find.byKey(const Key('dashboard-calorie-ring')), findsOneWidget);
      // docs/21 §5.1 空态表：无目标 → 靶标位置写「尚未设定目标」。
      expect(find.text('尚未设定目标'), findsWidgets);
      expect(find.byKey(const Key('dashboard-ring-status')), findsOneWidget);
      expect(find.text('未设目标'), findsWidgets, reason: '环上的状态徽标必须如实写「未设目标」');
      // 旧文案「还可吃 N kcal」属于已删除的半圆环；Round7 A 用
      // 「还可摄入 / 超出 N kcal」，无目标时两者都不许出现。
      expect(find.textContaining('还可吃'), findsNothing, reason: '半圆件已删，旧措辞不许复活');
      expect(
        find.textContaining('还可摄入'),
        findsNothing,
        reason: '没有目标就没有「还可摄入多少」可言',
      );
      expect(find.textContaining('超出 '), findsNothing);

      await unmountApp(tester);
    });

    testWidgets('无记录：显示 0 摄入但不报错，且不显示超标', (tester) async {
      await seedTarget(calorieMax: 2000);
      await pumpDashboard(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('dashboard-calorie-ring')), findsOneWidget);
      expect(find.text('0'), findsWidgets, reason: '无记录就是 0 摄入');
      expect(find.textContaining('超出 '), findsNothing);
      // 有目标、无摄入 → 剩余等于整个目标，说成 A 的「还可摄入 N kcal」。
      expect(
        find.textContaining('还可摄入 2,000 kcal', findRichText: true),
        findsWidgets,
        reason: '有目标、无摄入时应显示剩余额度（2000 − 0 = 2000）',
      );
      expect(find.textContaining('还可吃'), findsNothing, reason: '旧半圆环的措辞已随组件删除');

      await unmountApp(tester);
    });

    testWidgets('超标：显示「超出 N kcal」与溢出量', (tester) async {
      await seedTarget(calorieMax: 2000);
      await seedMeal(kcal: 2400);
      await pumpDashboard(tester);

      expect(find.byKey(const Key('dashboard-calorie-ring')), findsOneWidget);
      // 2400 - 2000 = 400，超标态必须可见且带正确的溢出量。
      expect(
        find.textContaining('超出 400 kcal', findRichText: true),
        findsOneWidget,
        reason: '2400 - 2000 = 400，超标态必须可见',
      );
      expect(find.textContaining('还可摄入'), findsNothing);
      // 状态徽标既是文案通道也是**颜色**通道：阶段 2B D20 起超目标换 honey 档
      // （A `app.js:125` 的 `pill warning`）。恒 mint 会让「超了」和「额度充足」
      // 同色——只断言文字在不在，抓不住档位被换回（两者都不改变布局）。
      final badge = tester.widget<LfBadge>(
        find.byKey(const Key('dashboard-ring-status')),
      );
      expect(badge.text, '已超目标', reason: '环上的状态徽标也要跟着变成「已超目标」');
      expect(
        badge.variant,
        LfBadgeVariant.honey,
        reason: '超目标 ⇒ warning 档（honey 底）',
      );
      expect(
        badge.icon,
        isNull,
        reason: 'A 的状态 pill 没有前置图标（2B D20 删掉了自绘件加的火苗）',
      );

      await unmountApp(tester);
    });

    testWidgets('查询错误：给出可重试文案，不渲染任何数值', (tester) async {
      // 用一个真会失败的库，而不是打桩：把聚合查询要读的表删掉，drift 在
      // prepare 阶段就抛 SqliteException，StreamBuilder 必须落到 hasError。
      //
      // 注意别用「先 close 再查」来造错——drift 的 DatabaseConnectionUser
      // 会在下次操作时自动重新打开已关闭的库，那样只会拿到正常数据（探针
      // 实测：closed 库仍 emit 出 DailyNutritionSummary）。
      final broken = AppDatabase(NativeDatabase.memory());
      addTearDown(broken.close);
      await broken.customStatement('DROP TABLE meal_items');
      final brokenMeals = MealRepository(
        database: broken,
        idGenerator: _Ids(),
        clock: FixedAppClock(now.toUtc()),
      );

      await pumpDashboard(tester, meals: brokenMeals);

      expect(find.text('今日营养数据加载失败，请重试。'), findsOneWidget);
      expect(
        find.textContaining('还可吃'),
        findsNothing,
        reason: '查询失败时不得回退成 0 摄入的假事实',
      );
      expect(find.textContaining('超过目标'), findsNothing);
      expect(find.byKey(const Key('dashboard-calorie-ring')), findsNothing);

      await unmountApp(tester);
    });
  });

  group('阶段 2 验收：饮水/步数不编造事实', () {
    testWidgets('两格都写「暂无记录」，且不出现 HTML 示例数值', (tester) async {
      await seedTarget(calorieMax: 2000);
      await pumpDashboard(tester);
      await scrollToQuickStats(tester);

      expect(find.byKey(const Key('dashboard-stat-water')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-stat-steps')), findsOneWidget);
      expect(find.text('饮水'), findsOneWidget);
      expect(find.text('步数'), findsOneWidget);
      // 饮水卡（无记录）与步数卡都写「暂无记录」。
      expect(find.text('暂无记录'), findsWidgets);
      expect(find.byKey(const Key('dashboard-steps-empty')), findsOneWidget);

      // HTML 原型里的示例值一个都不许出现（docs/21 §5.1 阶段 2 明确禁止冒充）。
      for (final fake in ['1.5', '2.0 L', '6,602', '6602', '还差 1.4k']) {
        expect(
          find.textContaining(fake),
          findsNothing,
          reason: 'HTML 示例值「$fake」不得当作事实渲染',
        );
      }

      await unmountApp(tester);
    });

    // 旧断言「饮水卡不显示目标行」的前提已被 schema 17 推翻：当时本地**没有**
    // 任何饮水 domain/table（见 docs/21 §5.1 阶段 2 原文），而 `WaterIntakes`
    // 与饮水仓储现已落地，规范也把 `DailyTargets.waterTargetMl` 明确列为饮水卡
    // 的目标来源。所以现在的诚实规则是：**有目标就按真值算达标率，没有目标行
    // 就写「未设目标」**，两者都不许编数字。
    testWidgets('无目标行时饮水卡写「未设目标」，且不出现任何容量读数', (tester) async {
      await pumpDashboard(tester);
      await scrollToQuickStats(tester);

      // 无 records、无 DailyTargets 行 → 计数位「暂无记录」、徽标「未设目标」。
      expect(find.byKey(const Key('dashboard-stat-water')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-stat-water')),
          matching: find.text('未设目标'),
        ),
        findsOneWidget,
        reason: '没有目标行时必须显式说明未设目标，而不是编一个 2.0 L 出来',
      );
      // 只在本卡范围内断言：热度环卡也有「尚未设定目标」/「未设目标」文案。
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-stat-water')),
          matching: find.textContaining('L'),
        ),
        findsNothing,
        reason: '没有记录也没有目标时，不得出现任何容量读数（含单位）',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-stat-water')),
          matching: find.textContaining('达标'),
        ),
        findsNothing,
        reason: '没有目标就没有达标率可言',
      );

      await unmountApp(tester);
    });
  });

  // 旧半圆环的「超目标切换 error 色」断言（旧 design_widgets_test）随旧件一起
  // 删除：新环不给 error 色，超目标改由状态徽标文字表达。分级函数是纯函数，
  // 四个分支在这里逐条锁住（「已超目标」的端到端渲染见上方超标用例）。
  group('DashboardCalorieCard.statusLabel 分级', () {
    test('未设目标 / 已超目标 / 接近上限 / 额度充足', () {
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 1200, targetKcal: null),
        '未设目标',
      );
      // 0 目标与 null 同档：没有可用的目标就不分级。
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 500, targetKcal: 0),
        '未设目标',
      );
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 2101, targetKcal: 2100),
        '已超目标',
      );
      // 恰好落在目标上不算超（> 1.0 才算），90% 起算「接近上限」。
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 2100, targetKcal: 2100),
        '接近上限',
      );
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 1890, targetKcal: 2100),
        '接近上限',
      );
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 1889, targetKcal: 2100),
        '额度充足',
      );
    });
  });
}

final class _Ids implements IdGenerator {
  int _v = 0;

  @override
  String next() => 'stage2-${_v++}';
}
