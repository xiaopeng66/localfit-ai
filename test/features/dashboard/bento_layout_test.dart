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
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

import '../../support/food_fixture.dart';

/// 今日页窄屏布局（docs/21 §5.1 / §5.8.3「文字缩放」）：
///
/// 本文件原为 bento 时代的 `bento_layout_test.dart`。bento 卡片（
/// `dashboard-plan-cell` / `dashboard-quick-cell` / `weight-bar-chart` …）
/// 已随 docs/22 阶段 B 从今日页删除，逐条比对后的去向是：
///
/// | 旧断言 | 去向 |
/// |---|---|
/// | 首页卡片齐全 / 顺序 | `dashboard_page_v2_test` 结构组 |
/// | 有目标时按真值渲染、餐食进时间线 | `dashboard_page_v2_test` 真值组 + `dashboard_page_test` |
/// | 体重趋势箭头方向 | `dashboard_page_v2_test` 倒序入参用例（含 ↑/↓ 双向） |
/// | 旧营养明细卡不渲染 | 反向：新设计**要**渲染三条 MacroBar（`dashboard_page_v2_test`） |
/// | bento 并排 / 单列 | 卡片形态已变，改为下列**窄屏不溢出**断言 |
/// | 快捷记录芯片 / 体重柱状图卡 | 随组件删除，收进二级入口（docs/22 阶段 H） |
///
/// 保留下来的是**只有本文件覆盖**的部分：窄屏下三块卡片的降级分支。
/// 生产代码在 `constraints.maxWidth < 300` 时把并排改成竖排（否则数字与
/// 状态文案会挤出边界），这条分支没有别的测试走过。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;
  late MeasurementRepository measurementRepository;
  final now = DateTime(2026, 9, 9, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    // 米饭等食材来自种子库；不导入就搜不到（firstWhere 会抛
    // 「Bad state: No element」而不是清晰的失败信息）。
    await seedFoodFixture(database);
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

  Widget app() => LocalFitApp(
    initialLocation: AppRoutes.dashboard,
    foodRepository: foodRepository,
    mealRepository: mealRepository,
    measurementRepository: measurementRepository,
    now: now,
  );

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  void useViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 三块卡片的降级分支都要有数据才会渲染出内容（否则测的是空态）。
  Future<void> seedProfileAndTargets() async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-narrow',
            activityLevel: 'moderate',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-narrow',
            profileId: 'profile-narrow',
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
            id: 'target-narrow',
            goalId: 'goal-narrow',
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
    // 体脂/肌肉量都给值：三格趋势都渲染出内容，才走得到并排/竖排分支。
    await measurementRepository.saveManualWeight(
      localDate: '2026-09-08',
      weightKg: 75,
    );
    await measurementRepository.saveManualWeight(
      localDate: '2026-09-09',
      weightKg: 74.5,
    );
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-narrow',
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
            id: 'item-narrow',
            mealId: 'meal-narrow',
            foodId: Value(rice.id),
            foodNameSnapshot: rice.name,
            grams: 200,
            kcalSnapshot: 232,
            proteinSnapshot: 5.2,
            carbsSnapshot: 51.8,
            fatSnapshot: 0.6,
            createdAt: DateTime.utc(2026, 9, 9, 12),
            updatedAt: DateTime.utc(2026, 9, 9, 12),
          ),
        );
  }

  testWidgets('320dp 窄屏：三块卡片的并排内容降为竖排，且不溢出', (tester) async {
    await seedProfileAndTargets();
    // 320dp 是设计支持的最窄宽度；页边距吃掉后内容只有 ~288dp，
    // 正好落进三处 `maxWidth < 300` 的降级分支。
    useViewport(tester, const Size(320, 1200));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 溢出会被 Flutter 报成 RenderFlex overflow 异常。
    expect(tester.takeException(), isNull);

    // 三块卡片都在（降级不是隐藏）。
    for (final key in [
      'dashboard-calorie-ring',
      'dashboard-weight-chart',
      'dashboard-stat-water',
    ]) {
      await tester.scrollUntilVisible(
        find.byKey(Key(key)),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(tester.takeException(), isNull);

    await unmountApp(tester);
  });

  testWidgets('320dp 窄屏：饮水/步数两格竖排（第二格在第一格下方）', (tester) async {
    await seedProfileAndTargets();
    useViewport(tester, const Size(320, 1200));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('dashboard-stat-water')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    final water = tester.getRect(find.byKey(const Key('dashboard-stat-water')));
    final steps = tester.getRect(find.byKey(const Key('dashboard-stat-steps')));

    // 竖排判据：步数卡顶边不低于饮水卡底边（并排时会几乎齐平）。
    expect(
      steps.top,
      greaterThanOrEqualTo(water.bottom - 1),
      reason: '窄屏下两格必须竖排，否则数字与状态文案会挤出边界',
    );

    await unmountApp(tester);
  });

  testWidgets('宽屏 400dp：体重柱图与左侧 y 轴都上屏（轴在柱左边）', (tester) async {
    // 原先这条钉的是「三格趋势并排（顶边齐平）」；三格已按用户要求
    // （docs/30 需求 2「下边的本周趋势三个小卡片不要了」）整段删除。
    // 改为钉柱图 + y 轴：宽屏下轴列仍必须在绘图区左侧。
    await seedProfileAndTargets();
    useViewport(tester, const Size(400, 1200));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('weight-bar-chart')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    final tick = tester.getRect(
      find.byKey(const Key('weight-bar-chart-tick-0')),
    );
    // 本周 fixture 是 09-08（二）与 09-09（三）⇒ 有值的格是 index 1 / 2；
    // index 0 是周一（空槽，没有柱 widget）。需求 41 起不许再点 `bar-0`。
    final bar = tester.getRect(find.byKey(const Key('weight-bar-chart-bar-2')));
    expect(
      tick.right,
      lessThanOrEqualTo(bar.left + 1),
      reason: '坐标轴在左边（宽屏也一样）',
    );

    await unmountApp(tester);
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'bento-id-${_value++}';
}
