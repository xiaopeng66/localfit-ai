import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_calorie_card.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_greeting_header.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_meals_card.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';

/// 今日页（docs/21 §5.1 `今日.html`）。
///
/// 视觉断言按新设计重写（docs/22 阶段 B）；**诚实规则的单测优先**：
/// 无数据一律空态，设计稿示例值（1248 / 69.4kg / 6,602 步 …）绝不出现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 23, 9);
  final localDate = formatLocalDate(now);
  late AppDatabase database;
  late MealRepository mealRepository;
  late MeasurementRepository measurementRepository;
  late WaterRepository waterRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    const clock = FixedAppClockValue();
    mealRepository = MealRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    measurementRepository = MeasurementRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    waterRepository = WaterRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
  });

  tearDown(() => database.close());

  /// 挂载今日页。
  Future<void> pump(WidgetTester tester, {bool withWater = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: DashboardPage(
          mealRepository: mealRepository,
          measurementRepository: measurementRepository,
          waterRepository: withWater ? waterRepository : null,
          onOpenAiWorkbench: () {},
          onOpenRecord: () {},
          onLogMeal: (_) {},
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 挂载型用例的统一收尾（与 `dashboard_view_states_test` 同法）。
  ///
  /// drift 在查询流取消时排一个 0ms 定时器；必须**在测试体内**卸载再放行一次
  /// 真实时长，否则收尾的 pending-timer 检查先于 `addTearDown` 执行而误报红。
  void dashboardTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  /// 建一份档案 + 目标（多数用例都需要目标才能算进度）。
  Future<void> seedProfile() async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'p1',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
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
            effectiveFrom: now,
            createdAt: now,
            updatedAt: now,
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
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  group('结构（docs/21 §5.1 结构树）', () {
    dashboardTest('无 AppBar：日期/问候直接贴顶', (tester) async {
      await pump(tester);

      expect(find.byType(AppBar), findsNothing);
      expect(find.byKey(const Key('dashboard-date-label')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-greeting')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-avatar')), findsOneWidget);
    });

    dashboardTest('五块卡片按顺序齐全', (tester) async {
      await pump(tester);

      for (final key in [
        'dashboard-calorie-ring',
        'dashboard-weight-chart',
        'dashboard-stat-water',
        'dashboard-next-meal',
        'dashboard-meals-card',
        'cta-ai-workbench',
      ]) {
        // 页面可滚，靠后的卡要先滚进来。
        await tester.scrollUntilVisible(
          find.byKey(Key(key)),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
    });

    dashboardTest('日期格式为「9月23日 周三」', (tester) async {
      await pump(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('dashboard-date-label'))).data,
        '9月23日 周三',
      );
    });

    dashboardTest('问候按时段切换（早/午/晚）', (tester) async {
      expect(DashboardGreetingHeader.greetingFor(8), '早安');
      expect(DashboardGreetingHeader.greetingFor(11), '午安');
      expect(DashboardGreetingHeader.greetingFor(17), '午安');
      expect(DashboardGreetingHeader.greetingFor(18), '晚安');
    });

    dashboardTest('无档案时头像显示 Fit，有姓名时显示首字', (tester) async {
      expect(DashboardGreetingHeader.avatarInitial(null), 'Fit');
      expect(DashboardGreetingHeader.avatarInitial('   '), 'Fit');
      expect(DashboardGreetingHeader.avatarInitial('小林'), '小');
      expect(DashboardGreetingHeader.avatarInitial('  阿宝 '), '阿');
    });
  });

  group('诚实规则（docs/21 §6.1：示例值绝不冒充事实）', () {
    dashboardTest('无目标时显示「尚未设定目标」，不编 1800', (tester) async {
      await pump(tester);

      expect(find.text('尚未设定目标'), findsWidgets);
      expect(find.textContaining('1800'), findsNothing);
    });

    dashboardTest('无体重数据显示空态与记录入口', (tester) async {
      await seedProfile();
      await pump(tester);

      expect(find.byKey(const Key('dashboard-weight-empty')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-weight-record')), findsOneWidget);
      // 设计稿示例值 69.4 / 18.2 / 31.5 一个都不许出现。
      expect(find.textContaining('69.4'), findsNothing);
      expect(find.textContaining('18.2'), findsNothing);
      expect(find.textContaining('31.5'), findsNothing);
    });

    dashboardTest('无记录的摄入是 0，且宏量占比显示「暂无记录」', (tester) async {
      await seedProfile();
      await pump(tester);

      expect(find.text('0'), findsWidgets);
      expect(find.text('暂无记录'), findsWidgets);
      // 设计稿的 30%/50%/20% 组合不许伪造。
      expect(find.textContaining('50%'), findsNothing);
    });

    dashboardTest('步数卡恒为「暂无记录」，不显示隐含目标 1.4k', (tester) async {
      await pump(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('dashboard-stat-steps')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('dashboard-steps-empty')), findsOneWidget);
      expect(find.textContaining('1.4k'), findsNothing);
      expect(find.textContaining('6,602'), findsNothing);
    });

    dashboardTest('无饮水记录时饮水卡显示「暂无记录」', (tester) async {
      await seedProfile();
      await pump(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('dashboard-stat-water')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('暂无记录'), findsWidgets);
      expect(find.textContaining('1.5'), findsNothing);
    });

    dashboardTest('无记录时餐次卡显示空态（2026-10-22：记录饮食按钮退场）', (tester) async {
      await seedProfile();
      await pump(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('dashboard-meals-card')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // Round7 A：空态 = `.empty-state`（图标块 + 「从第一餐开始」+ 说明）。
      // 2026-10-22 用户：「今日吃了什么卡片不需要记录饮食的按钮」⇒ 按钮退场；
      // 记餐入口仍在下一餐卡（cta-log-dinner）与饮食页 FAB。
      expect(find.byKey(const Key('dashboard-meals-empty')), findsOneWidget);
      expect(find.text('从第一餐开始'), findsOneWidget);
      expect(find.byKey(const Key('cta-log-meal')), findsNothing);
    });

    dashboardTest('未接线饮水仓储时不崩，仍走空态', (tester) async {
      await pump(tester, withWater: false);

      await tester.scrollUntilVisible(
        find.byKey(const Key('dashboard-stat-water')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('dashboard-stat-water')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('真实数据驱动（本地库真值）', () {
    dashboardTest('圆环与剩余行按真值渲染', (tester) async {
      await seedProfile();
      await _recordMeal(mealRepository, localDate, kcal: 1248);
      await pump(tester);

      // 已摄入 1,248 / 目标 1,800 → 剩余 552（A `format()` ⇒ 千分位）。
      expect(find.text('1,248'), findsOneWidget);
      // 剩余行是 Text.rich（数字单独上色），plain text 是整行，按整行匹配。
      expect(
        find.textContaining('还可摄入 552 kcal', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('69%'), findsOneWidget);
    });

    dashboardTest('超出目标时剩余行改成「超出 N kcal」', (tester) async {
      await seedProfile();
      await _recordMeal(mealRepository, localDate, kcal: 2000);
      await pump(tester);

      // A `.energy-foot` 右格：`'超出 <b>N</b> kcal'`（1800 − 2000 ⇒ 200）。
      expect(
        find.textContaining('超出 200 kcal', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('还可摄入'), findsNothing);
    });

    dashboardTest('体重柱图在有 2 条以上记录时渲染（柱 + 左侧 y 轴）', (tester) async {
      await seedProfile();
      await measurementRepository.saveManualWeight(
        localDate: '2026-09-22',
        weightKg: 70.0,
      );
      await measurementRepository.saveManualWeight(
        localDate: '2026-09-23',
        weightKg: 69.4,
      );
      await pump(tester);

      expect(find.byKey(const Key('weight-bar-chart')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-weight-empty')), findsNothing);
      expect(find.textContaining('69.4'), findsWidgets);
    });

    // docs/30 需求 2：「不需要统计体脂率和肌肉量了」。体脂率/肌肉量仍在
    // `Measurements` 落库（数据层不动），但体重卡不再统计显示它们。
    // 这条钉的是「不再出现」——否则删了三格又被谁加回来没人拦。
    dashboardTest('体脂率/肌肉量不再上屏（数据层仍落库）', (tester) async {
      await seedProfile();
      await measurementRepository.saveManualWeight(
        localDate: '2026-09-22',
        weightKg: 70.0,
      );
      await measurementRepository.saveManualWeight(
        localDate: '2026-09-23',
        weightKg: 69.4,
      );
      await pump(tester);

      // 体脂率的数值与标签都不该出现在卡里。
      expect(find.textContaining('18.2'), findsNothing);
      expect(find.textContaining('体脂'), findsNothing);
      expect(find.textContaining('肌肉'), findsNothing);
      expect(find.byKey(const Key('dashboard-trend-bodyfat')), findsNothing);
      expect(find.byKey(const Key('dashboard-trend-muscle')), findsNothing);
      expect(find.byKey(const Key('dashboard-trend-weight')), findsNothing);
      // 但体重本身照常显示（删的是两格统计，不是整卡）。
      expect(find.textContaining('69.4'), findsWidgets);
    });

    // 旧口径「1 点画不出折线 → 走空态」被推翻：柱图天然支持单柱，
    // 于是「还没有体重记录」只在**真的 0 条记录**时出现，不再谎报。
    dashboardTest('只记录一次体重也画一根柱，不谎报「还没有体重记录」', (tester) async {
      await seedProfile();
      await measurementRepository.saveManualWeight(
        localDate: '2026-09-23',
        weightKg: 69.4,
      );
      await pump(tester);

      expect(find.byKey(const Key('weight-bar-chart')), findsOneWidget);
      // 2026-09-23 是**周三** ⇒ 本周七格（09-21 一…09-27 日）里柱在第 3 格
      // （index 2）。需求 41 起第 0 格是周一，不再是「第一根柱」。
      expect(find.byKey(const Key('weight-bar-chart-bar-2')), findsOneWidget);
      expect(find.byKey(const Key('weight-bar-chart-bar-0')), findsNothing);
      expect(find.byKey(const Key('dashboard-weight-empty')), findsNothing);
      // 数值仍要显示：只有一条也是真数据。
      expect(find.textContaining('69.4'), findsWidgets);
    });

    // ── T7（docs/32 §4 T7 / §3 D9）：今日页头像与问候语接入身份 ────────────
    dashboardTest('今日页头像显昵称首字、问候语带昵称（未接线时回退「Fit」）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: DashboardPage(
            mealRepository: mealRepository,
            measurementRepository: measurementRepository,
            waterRepository: waterRepository,
            onOpenAiWorkbench: () {},
            onOpenRecord: () {},
            onLogMeal: (_) {},
            // docs/32 §3 D9：路由注入身份事实。
            identity: const IdentityProfile(displayName: '李雷'),
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboard-avatar-initial')))
            .data,
        '李',
        reason: 'D9：今日页头像显示昵称首字',
      );
      expect(find.textContaining('，李雷'), findsOneWidget, reason: '问候语带昵称');
    });

    // 回归：`watchWeightOverview` 按 `localDate DESC` 返回，卡片若默认
    // 「末条即最新」会显示最旧的一条、柱序也会整个倒过来
    // （上一版 weight_card 踩过同一个坑）。
    dashboardTest('倒序入参下仍取最新一天的值与正确的增减方向', (tester) async {
      await seedProfile();
      // 乱序写入，制造「存储顺序 ≠ 时间顺序」。
      await measurementRepository.saveManualWeight(
        localDate: '2026-09-21',
        weightKg: 71.0,
      );
      await measurementRepository.saveManualWeight(
        localDate: '2026-09-23',
        weightKg: 69.4,
      );
      await measurementRepository.saveManualWeight(
        localDate: '2026-09-22',
        weightKg: 70.2,
      );
      await pump(tester);

      // 卡头 caption 取 09-23（最新），不是最早那条 71.0。
      // Round7 A：值是 `Text.rich`（`值 + kg` 两段），文本从 `textSpan` 取。
      final subtitle = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('dashboard-weight-chart')),
              matching: find.byType(Text),
            ),
          )
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join('|');
      expect(subtitle, contains('69.4'));
      expect(subtitle, isNot(contains('71.0')));

      // 体重 71.0 → 69.4 是下降，增减行必须是 ↓ 而不是 ↑。
      expect(subtitle, contains('↓'));
      expect(subtitle, isNot(contains('↑')));
    });

    dashboardTest('饮水卡按真值显示已喝量与达标百分比', (tester) async {
      await seedProfile();
      await waterRepository.add(localDate: localDate, amountMl: 250);
      await waterRepository.add(localDate: localDate, amountMl: 500);
      await pump(tester);

      await tester.scrollUntilVisible(
        find.byKey(const Key('dashboard-stat-water')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // 750 / 2000 = 37.5% → 38%；状态徽标写「达标 38%」。
      // 2026-10-16 用户要求「250ml/1000ml 这种」：当前值与目标并进**数值行**
      // （Round7 A 曾把「目标 N ml」单列一行，按本轮用户指令改回一行式）。
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboard-water-value')))
            .data,
        '750',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('dashboard-water-target-inline')),
            )
            .data,
        '/ 2,000 ml',
      );
      expect(find.byKey(const Key('dashboard-water-goal')), findsNothing);
      expect(find.text('达标 38%'), findsOneWidget);
    });
  });

  group('MacroBar / 趋势取色（纯函数）', () {
    test('宏量占比按 4/4/9 计算且三数之和恒为 100', () {
      final ratios = DashboardCalorieCard.macroRatios(
        const NutritionValues(
          kcal: 1000,
          proteinGrams: 30,
          carbsGrams: 100,
          fatGrams: 20,
        ),
      )!;
      // 120 / 400 / 180 kcal → 17% / 57% / 26%（脂肪取余数）。
      expect(ratios.$1, 17);
      expect(ratios.$2, 57);
      expect(ratios.$3, 26);
      expect(ratios.$1 + ratios.$2 + ratios.$3, 100);
    });

    test('全 0 摄入没有占比可言 → null（显示占位）', () {
      expect(DashboardCalorieCard.macroRatios(NutritionValues.zero), isNull);
    });

    test('占比之和在任何输入下都是 100（四舍五入不留缺口）', () {
      for (final protein in [0.0, 1.0, 12.34, 55.5, 199.0]) {
        for (final carbs in [0.0, 3.0, 77.7, 150.0, 300.0]) {
          for (final fat in [0.0, 5.6, 33.3, 88.0, 120.0]) {
            final ratios = DashboardCalorieCard.macroRatios(
              NutritionValues(
                kcal: 0,
                proteinGrams: protein,
                carbsGrams: carbs,
                fatGrams: fat,
              ),
            );
            if (ratios == null) continue;
            expect(
              ratios.$1 + ratios.$2 + ratios.$3,
              100,
              reason: '$protein/$carbs/$fat',
            );
          }
        }
      }
    });

    test('状态徽标只按摄入比分级，不推断身体状态', () {
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 500, targetKcal: 1800),
        '额度充足',
      );
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 1700, targetKcal: 1800),
        '接近上限',
      );
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 1900, targetKcal: 1800),
        '已超目标',
      );
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 0, targetKcal: null),
        '未设目标',
      );
      expect(
        DashboardCalorieCard.statusLabel(consumedKcal: 0, targetKcal: 0),
        '未设目标',
      );
    });
  });

  group('时间线合成（buildMealTimeline）', () {
    test('按就餐时刻升序排列', () {
      // 计划态（PlannedTimelineEntry / plans: 参数）随周计划整族下线，
      // buildMealTimeline 现在只组装当天已记录的餐。
      final entries = buildMealTimeline(
        meals: [
          _meal(localDate, MealSlot.dinner, eatenAt: DateTime(2026, 9, 23, 19)),
          _meal(
            localDate,
            MealSlot.breakfast,
            eatenAt: DateTime(2026, 9, 23, 8),
          ),
          _meal(localDate, MealSlot.lunch, eatenAt: DateTime(2026, 9, 23, 12)),
        ],
      );

      expect(entries.map((e) => e.slot), [
        MealSlot.breakfast,
        MealSlot.lunch,
        MealSlot.dinner,
      ]);
    });

    test('已记录条目的菜品行用顿号连接', () {
      final entry = RecordedTimelineEntry(
        _meal(localDate, MealSlot.lunch, dishNames: const ['鸡胸沙拉', '糙米饭']),
      );
      expect(entry.dishLabel, '鸡胸沙拉 · 糙米饭');
    });

    test('无菜品明细时如实写「暂无菜品明细」而不是空串', () {
      final entry = RecordedTimelineEntry(_meal(localDate, MealSlot.snack));
      expect(entry.dishLabel, '暂无菜品明细');
    });
  });

  group('WaterSummary 派生值', () {
    test('无目标时百分比/进度/剩余都为占位', () {
      const summary = WaterSummary(
        consumedMl: 500,
        targetMl: null,
        records: [],
      );
      expect(summary.percent, isNull);
      expect(summary.progress, 0);
      expect(summary.remainingMl, isNull);
      expect(summary.targetLitersLabel, '--');
    });

    test('目标为 0 或负数时同样按未设目标处理（不除零）', () {
      for (final target in [0.0, -100.0]) {
        final summary = WaterSummary(
          consumedMl: 500,
          targetMl: target,
          records: const [],
        );
        expect(summary.percent, isNull);
        expect(summary.progress, 0);
      }
    });

    test('达标后剩余为 null，进度封顶 1', () {
      const summary = WaterSummary(
        consumedMl: 2500,
        targetMl: 2000,
        records: [],
      );
      expect(summary.percent, 125);
      expect(summary.progress, 1.0);
      expect(summary.remainingMl, isNull);
    });
  });

  group('加水校验（脏数据不进统计）', () {
    test('非正数与非有限值被拒', () {
      for (final value in [0.0, -1.0, double.nan, double.infinity]) {
        expect(
          () => validateWaterAmountMl(value),
          throwsA(isA<FormatException>()),
          reason: '$value',
        );
      }
    });

    test('超过 5000ml 被拒（几乎必是把 L 当 ml 填）', () {
      expect(
        () => validateWaterAmountMl(5001),
        throwsA(isA<FormatException>()),
      );
      expect(validateWaterAmountMl(5000), 5000);
    });

    test('快捷值本身都合法', () {
      for (final amount in waterQuickAmountsMl) {
        expect(validateWaterAmountMl(amount), amount);
      }
    });
  });

  // ---- docs/21 §5.1 Key 表覆盖（阶段 I-4：Key 是设计契约，不是实现细节）----
  group('docs/21 §5.1 Key 覆盖', () {
    dashboardTest('圆环中心三段文字 + 三条宏量 + 宏量占比行都可定位', (tester) async {
      await seedProfile();
      await _recordMeal(mealRepository, localDate, kcal: 640);
      await pump(tester);

      for (final key in [
        'dashboard-calorie-ring',
        'dashboard-ring-consumed',
        'dashboard-ring-percent',
        'dashboard-ring-target',
        'dashboard-ring-status',
        'nutrition-macro-protein',
        'nutrition-macro-carbs',
        'nutrition-macro-fat',
        'dashboard-macro-ratios',
      ]) {
        await tester.scrollUntilVisible(
          find.byKey(Key(key)),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      // 三段文字的内容确实是「已摄入 / 目标 / 百分比」，不是三个空锚点。
      final consumed = tester.widget<Text>(
        find.byKey(const Key('dashboard-ring-consumed')),
      );
      final target = tester.widget<Text>(
        find.byKey(const Key('dashboard-ring-target')),
      );
      final percent = tester.widget<Text>(
        find.byKey(const Key('dashboard-ring-percent')),
      );
      expect(consumed.data, '640');
      // D6：`dashboard-ring-target` 的锚点搬到卡片 foot，文案随 A 的
      // `.energy-foot` 左格（含千分位）。
      expect(target.data, '目标 1,800 kcal');
      expect(percent.data, '36%');
    });
  });
}

/// 固定时钟：用例的日期是构造出来的，不依赖真实时间。
class FixedAppClockValue implements AppClock {
  const FixedAppClockValue();

  static final _value = DateTime.utc(2026, 9, 23, 1);

  @override
  DateTime nowUtc() => _value;
}

/// 构造一条已记录餐（供 `buildMealTimeline` / `RecordedTimelineEntry` 用例使用）。
///
/// T7 期间块搬移误删，按其调用点契约重建：`localDate` + `slot` 必有，
/// `eatenAt` / `dishNames` 可选（后者逐项生成 `MealItemRecord`，供
/// `dishLabel` 的顿号连接断言用）。
MealRecord _meal(
  String localDate,
  MealSlot slot, {
  DateTime? eatenAt,
  List<String> dishNames = const [],
}) {
  final at = eatenAt ?? DateTime(2026, 9, 23, 12);
  return MealRecord(
    id: '$localDate-${slot.name}',
    localDate: localDate,
    slot: slot,
    eatenAt: at,
    source: 'manual',
    createdAt: at,
    updatedAt: at,
    items: [
      for (var i = 0; i < dishNames.length; i++)
        MealItemRecord(
          id: '$localDate-${slot.name}-$i',
          foodName: dishNames[i],
          grams: 100,
          nutrition: NutritionValues.zero,
          createdAt: at,
          updatedAt: at,
        ),
    ],
  );
}

Future<void> _recordMeal(
  MealRepository repository,
  String localDate, {
  required double kcal,
  MealSlot slot = MealSlot.lunch,
}) async {
  await repository.create(
    MealDraft(
      localDate: localDate,
      slot: slot,
      items: [
        MealItemDraft(
          foodName: '测试餐',
          grams: 100,
          nutrition: NutritionValues(
            kcal: kcal,
            proteinGrams: 30,
            carbsGrams: 100,
            fatGrams: 20,
          ),
        ),
      ],
    ),
  );
}
