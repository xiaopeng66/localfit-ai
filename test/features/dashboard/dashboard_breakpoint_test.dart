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

/// 今日页三块卡片的**并排/竖排判据**（docs/27 §6，用户 2026-10-03 报告）。
///
/// 报告的现象：机型 360dp 宽（1440px @ dpr 4.0）下，热量卡的圆环被挪到宏量
/// 条**上方**并居中，而这与设计稿（`ui设计/pages/今日.html`）不符——设计稿
/// **没有任何断点**：圆环恒在左、宏量条恒在右；320/360/376/430px 四个宽度
/// 的无头渲染都是并排（`E:/AI/Zcode/tmp/cal-stack.png` 为证）。
///
/// 根因：旧判据是常量 `constraints.maxWidth < 300`。360dp 手机页面左右各
/// 16dp、卡片内边距各 16dp ⇒ 卡片内宽 = 360 − 32 − 32 = **296dp**，恰好
/// `< 300` 成立 ⇒ 主流手机一律被降级成竖排。本文件把判据钉在**行为**上：
///
///  * 360dp（用户机型）三块卡片必须并排（设计稿形态）；
///  * 320dp + 1.0× 仍并排（无头渲染证明设计稿在 320px 也并排）；
///  * 320dp + 2.0× 字号才允许竖排（真实放不下，是退化而非默认）。
///
/// 竖排本身是必要的兜底（否则大字号下溢出），所以两个方向都要断言，不能只
/// 断言并排——只测一个方向的话，把实现改成「永远竖排」或「永远并排」都能骗
/// 过其中一半。
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

  /// 视口 + 系统字号。`devicePixelRatio` 固定 1，物理尺寸即逻辑尺寸。
  void useViewport(WidgetTester tester, Size size, {double scale = 1}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// 三块卡片都要有数据才渲染出内容（空态测不到布局分支）。
  Future<void> seedAll() async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'p',
            activityLevel: 'moderate',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'g',
            profileId: 'p',
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
            id: 't',
            goalId: 'g',
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
    // 三条宏量有真值 → MacroBar 的「N / M g」串取最长形态（判据的输入）。
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'm',
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
            id: 'i',
            mealId: 'm',
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
    // 体重两点成线 + 体脂/肌肉量都有值，三格趋势才都渲染出内容。
    await measurementRepository.saveManualWeight(
      localDate: '2026-09-08',
      weightKg: 75,
    );
    await measurementRepository.saveManualWeight(
      localDate: '2026-09-09',
      weightKg: 74.5,
    );
  }

  /// 热量卡：圆环与第一条宏量条是否**并排**。
  ///
  /// 判据用几何「水平错开」而不是 `maxWidth`：竖排时两者左边缘几乎对齐且垂
  /// 直分离；并排时宏量条的左边缘在圆环右边缘之后。这个判据对实现方式（Row
  /// 还是别的容器）不敏感。
  Future<void> scrollToCalorieCard(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('dashboard-calorie-ring')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> assertCalorieSideBySide(
    WidgetTester tester, {
    required bool sideBySide,
    required String why,
  }) async {
    await scrollToCalorieCard(tester);
    final ring = tester.getRect(find.byKey(const Key('lf-calorie-ring')));
    final protein = tester.getRect(
      find.byKey(const Key('nutrition-macro-protein')),
    );
    if (sideBySide) {
      expect(
        protein.left,
        greaterThanOrEqualTo(ring.right - 1),
        reason: '并排时宏量条必须在圆环右侧（$why）',
      );
      // 并排时两者纵向必须有重叠（否则是「宏量条在下方」的竖排）。
      expect(
        protein.top,
        lessThan(ring.bottom),
        reason: '并排时宏量条顶边应在圆环底边之上（$why）',
      );
    } else {
      expect(
        protein.top,
        greaterThanOrEqualTo(ring.bottom - 1),
        reason: '竖排时宏量条必须整体在圆环下方（$why）',
      );
    }
  }

  /// 体重柱图 + 左侧 y 轴：两个部件都在、且**轴列在绘图区左侧**
  /// （docs/30 §2 D3 需求 2「左边要有坐标」）。
  Future<void> assertWeightBarsWithAxis(
    WidgetTester tester, {
    required String why,
  }) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('weight-bar-chart')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // 四档刻度都在（顶 / 上中 / 下中 / 底）。
    for (var i = 0; i < 4; i++) {
      expect(
        find.byKey(Key('weight-bar-chart-tick-$i')),
        findsOneWidget,
        reason: 'y 轴四档刻度必须上屏（$why）',
      );
    }
    // 单位只写一次：A 起 `kg` 由卡片 caption 承担（`dashboard-weight-trend-value`
    // 的 ` kg` 小字），图内不再有独立单位行（D8b 退场，`weight-bar-chart-unit`）。
    expect(
      tester
          .widget<Text>(find.byKey(const Key('dashboard-weight-trend-value')))
          .textSpan!
          .toPlainText(),
      endsWith(' kg'),
      reason: '单位必须在卡片里写一次（$why）',
    );
    expect(
      find.byKey(const Key('weight-bar-chart-unit')),
      findsNothing,
      reason: 'A 的图内没有单位行（kg 只在 caption）',
    );

    // 轴列必须在柱（绘图区）左侧：拿第 0 档刻度与一根**真实存在**的柱比左右。
    // 本周 fixture 是 09-08（二）/ 09-09（三）⇒ 用 index 2；index 0 是周一，
    // 需求 41 起是空槽（没有柱 widget，点它等于找不到 widget 而报错）。
    final tick = tester.getRect(
      find.byKey(const Key('weight-bar-chart-tick-0')),
    );
    final bar = tester.getRect(find.byKey(const Key('weight-bar-chart-bar-2')));
    expect(
      tick.right,
      lessThanOrEqualTo(bar.left + 1),
      reason: '坐标轴在左边（刻度必须整体位于柱的左侧，$why）',
    );
  }

  testWidgets('360dp（用户机型）：三块卡片都按设计稿并排', (tester) async {
    await seedAll();
    useViewport(tester, const Size(360, 1400));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // ① 热量卡：设计稿是圆环在左 + 宏量条在右。
    await assertCalorieSideBySide(
      tester,
      sideBySide: true,
      why: '设计稿（今日.html）无断点，360dp 是最常见手机宽度',
    );

    // ② 体重图：docs/32 §3 D2 —— 柱状图 + 左侧 y 轴 **4 档**刻度。
    // （原先这里钉的是「趋势三格顶边齐平」；三格已按用户要求整段删除。）
    await assertWeightBarsWithAxis(tester, why: '360dp 是用户机型，柱图与轴列必须都上屏');

    // ③ 饮水 / 步数两格：设计稿 `grid-cols-2` 并排（顶边齐平）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('dashboard-stat-steps')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final water = tester.getRect(find.byKey(const Key('dashboard-stat-water')));
    final steps = tester.getRect(find.byKey(const Key('dashboard-stat-steps')));
    expect((steps.top - water.top).abs(), lessThan(1), reason: '设计稿两格并排（顶边齐平）');
    expect(steps.left, greaterThan(water.right - 1));
    expect(tester.takeException(), isNull);

    await unmountApp(tester);
  });

  testWidgets('热量卡右列：占比行与宏量条左边缘对齐', (tester) async {
    // 设计稿右列整体左对齐（`flex-1 space-y-2.5` 内的块都从同一起始边开始）。
    // 实测抓过一个缺陷：右列 Column 默认 center 对齐，占比行走到了中间、
    // 与宏量条错开——这里把它钉死。
    await seedAll();
    useViewport(tester, const Size(360, 1400));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Round7 A 起 `.macro-ratios` 不再是「右列里的一块」，而是`.energy-foot`
    // 之后的**整卡宽一行**（`refinement.css:5`），所以它对齐的是卡片内容左缘
    // ——与卡标题同一条线。要钉住的原缺陷不变（别飘到中间去）：任何居中/缩进
    // 都会让它的左缘离开标题左缘。
    await scrollToCalorieCard(tester);
    final title = tester.getRect(find.text('今日营养'));
    final ratio = tester.getRect(
      find.byKey(const Key('dashboard-macro-ratios')),
    );
    expect(
      (ratio.left - title.left).abs(),
      lessThan(1),
      reason: '占比行必须与卡片内容左缘对齐（A 的整卡宽一行）',
    );
    // 正向哨兵：它确实在宏量列**之下**（A 顺序 main → foot → ratios）。
    final protein = tester.getRect(
      find.byKey(const Key('nutrition-macro-protein')),
    );
    expect(ratio.top, greaterThan(protein.top));

    await unmountApp(tester);
  });

  testWidgets('320dp：三块卡片退化为竖排（设计稿在该宽度会裁字，必须兜底）', (tester) async {
    await seedAll();
    useViewport(tester, const Size(320, 1400));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 320px 下设计稿**自身**会把「156 / 200 g」裁掉（无头渲染实证：
    // E:/AI/Zcode/tmp/cal-320-2x.png），说明 320px 不是设计支持的宽度；
    // 实现必须在此时退化，否则数值会被裁掉或溢出。
    await assertCalorieSideBySide(
      tester,
      sideBySide: false,
      why: '320dp 下并排会裁掉数值，竖排是正确兜底',
    );

    // 体重图在 320dp 下同样上屏（柱图随宽度自适应，没有竖排/并排之分）。
    await assertWeightBarsWithAxis(tester, why: '320dp 兜底宽度也要能画柱图');
    expect(tester.takeException(), isNull);

    await unmountApp(tester);
  });

  testWidgets('320dp + 2.0× 字号：仍是竖排且不溢出', (tester) async {
    await seedAll();
    useViewport(tester, const Size(320, 1400), scale: 2);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 大字下并排放不下（实测判据的结论），必须退化为竖排兜底。
    await assertCalorieSideBySide(
      tester,
      sideBySide: false,
      why: '320dp + 2.0× 下并排会溢出，竖排是正确的兜底',
    );

    // 大字下柱图仍在（轴列文字是 micro 档，2.0× 也放得进 30dp 轴列）。
    await assertWeightBarsWithAxis(tester, why: '2.0× 字号下柱图与轴列都不能溢出');

    // 溢出会被 Flutter 报成 RenderFlex overflow 异常。
    expect(tester.takeException(), isNull);

    await unmountApp(tester);
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'breakpoint-id-${_value++}';
}
