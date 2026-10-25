import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/macro_bar.dart';
import 'package:localfit_ai/app/design/widgets/user_avatar.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/dashboard_page.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_next_meal_card.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

/// 阶段 2A：今日页按 Round7 A 变体 A 迁移（`design/round7/app.js:149-156`）。
///
/// 断言的是**有效层叠后的 A 值**（`styles.css → refinement.css → polish.css`）
/// 与结构/顺序：`energy → weight → dailyMetrics → nextMeal → meals → ai`。
/// 诚实规则不因换图失效：无数据照旧空态、不编示例值。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 13, 9);
  final localDate = formatLocalDate(now);
  late AppDatabase database;
  late MealRepository mealRepository;
  late MeasurementRepository measurementRepository;
  late WaterRepository waterRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(now.toUtc());
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

  Future<void> pump(
    WidgetTester tester, {
    bool withWater = true,
    void Function()? onOpenRecord,
    void Function(MealSlot? slot)? onLogMeal,
    bool wholePage = false,
  }) async {
    // `wholePage`：把视口拉高到能一次装下整页——`ListView` 只为可见区域
    // 建 element，靠下的卡片（下一餐/餐次/AI 入口）不这样就在树里找不到。
    tester.view.physicalSize = wholePage
        ? const Size(390, 3200)
        : const Size(390, 844);
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
          stepsRepository: null,
          onOpenAiWorkbench: () {},
          onOpenRecord: onOpenRecord ?? () {},
          onLogMeal: onLogMeal ?? (_) {},
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

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
            effectiveDate: '2026-10-01',
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

  /// 记一餐（默认今天 12:30 的一份 8 项 …）。
  Future<void> seedMeal({
    String? date,
    MealSlot slot = MealSlot.lunch,
    String foodName = '西兰花炒鸡丁',
    double grams = 150,
    double kcal = 250,
  }) async {
    await mealRepository.create(
      MealDraft(
        localDate: date ?? localDate,
        slot: slot,
        items: [
          MealItemDraft(
            foodName: foodName,
            grams: grams,
            nutrition: NutritionValues(
              kcal: kcal,
              proteinGrams: 20,
              carbsGrams: 15,
              fatGrams: 10,
            ),
          ),
        ],
      ),
    );
  }

  double top(WidgetTester tester, String key) =>
      tester.getTopLeft(find.byKey(Key(key))).dy;

  group('2A 问候头（A `.page-head`）', () {
    dashboardTest('问候在上、日期在下；头像 44 圆 + brand-soft 底', (tester) async {
      await pump(tester);

      // A `head()`：`<h1>` 在前、`<p class="page-date">` 在后。
      expect(
        top(tester, 'dashboard-greeting') < top(tester, 'dashboard-date-label'),
        isTrue,
        reason: 'A 的 page-head 是 h1 在上、page-date 在下',
      );

      final avatar = find.byKey(const Key('dashboard-avatar'));
      expect(tester.getSize(avatar), const Size(44, 44));
      final userAvatar = tester.widget<UserAvatar>(
        find.byType(UserAvatar).first,
      );
      expect(
        userAvatar.circle,
        isTrue,
        reason: 'A `.avatar{border-radius:50%}`',
      );
      expect(
        userAvatar.background,
        LfColors.brandSoft(Brightness.light),
        reason: 'A `.avatar{background:var(--brand-soft)}`',
      );
      expect(
        userAvatar.foreground,
        LfColors.mintText(Brightness.light),
        reason: 'A `.avatar{color:var(--brand-strong)}`',
      );
    });

    dashboardTest('剩余额度行不再挂在问候头（移入热量卡 foot）', (tester) async {
      await seedProfile();
      await pump(tester);

      final remaining = find.byKey(const Key('dashboard-remaining-line'));
      expect(remaining, findsOneWidget);
      expect(
        find.ancestor(
          of: remaining,
          matching: find.byKey(const Key('dashboard-calorie-ring')),
        ),
        findsOneWidget,
        reason: 'A 把「还可摄入 N kcal」放 `.energy-foot`',
      );
    });
  });

  group('2A 热量卡（A `.energy-summary`）', () {
    dashboardTest('标题=今日营养；环 120；中心为「已摄入 kcal」', (tester) async {
      await seedProfile();
      await seedMeal(kcal: 800);
      await pump(tester);

      expect(find.text('今日营养'), findsOneWidget);
      expect(find.text('已摄入 kcal'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('lf-calorie-ring'))),
        const Size(120, 120),
      );

      // foot：目标 + 还可摄入。
      // A：`.energy-foot` 左格 `'目标 '+format(goal)+' kcal'`，`format()`
      // 是 `toLocaleString` ⇒ 四位数起千分位。
      expect(find.text('目标 1,800 kcal'), findsOneWidget);
      expect(find.textContaining('还可摄入'), findsOneWidget);
    });

    dashboardTest('环内三段锚点保留（consumed/percent），target 落到 foot', (tester) async {
      await seedProfile();
      await seedMeal(kcal: 900);
      await pump(tester);

      final ring = find.byKey(const Key('dashboard-calorie-ring'));
      expect(
        find.descendant(
          of: ring,
          matching: find.byKey(const Key('dashboard-ring-consumed')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: ring,
          matching: find.byKey(const Key('dashboard-ring-percent')),
        ),
        findsOneWidget,
        reason: 'D6：N% 是现有可见事实，保留在环内（A 两行 + 本机第三行）',
      );
      expect(
        find.descendant(
          of: ring,
          matching: find.byKey(const Key('dashboard-ring-target')),
        ),
        findsOneWidget,
        reason: '「目标 1,800 kcal」= 原 -target 锚点新位置（foot）',
      );
    });

    dashboardTest('超目标：foot 说「超出」并给绝对数', (tester) async {
      await seedProfile();
      await seedMeal(kcal: 2000);
      await pump(tester);

      expect(find.textContaining('超出'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboard-remaining-line')))
            .textSpan!
            .toPlainText(),
        contains('200'),
      );
    });

    dashboardTest('宏量行按 A：5px 点、值 + 「/ 目标 g」、5px 轨', (tester) async {
      await seedProfile();
      await seedMeal(kcal: 800);
      await pump(tester);

      final protein = find.byKey(const Key('nutrition-macro-protein'));
      expect(protein, findsOneWidget);
      expect(
        tester.getSize(
          find.descendant(
            of: protein,
            matching: find.byKey(const Key('macro-bar-dot')),
          ),
        ),
        const Size(5, 5),
        reason: 'A `.macro-dot{width:5px;height:5px}`',
      );
      expect(
        tester
            .getSize(
              find.descendant(
                of: protein,
                matching: find.byKey(const Key('macro-bar-track')),
              ),
            )
            .height,
        5,
        reason: 'A 卡内轨道 `.data-track{height:5px}`（宽度随列宽）',
      );
      expect(find.textContaining('/ 60 g'), findsOneWidget);
    });
  });

  group('2A 页面顺序（A 变体 A）', () {
    dashboardTest('energy → weight → dailyMetrics → nextMeal → meals → ai', (
      tester,
    ) async {
      await seedProfile();
      await seedMeal();
      await pump(tester, wholePage: true);

      final order = [
        'dashboard-calorie-ring',
        'dashboard-weight-chart',
        'dashboard-stat-water',
        'dashboard-next-meal',
        'dashboard-meals-card',
        'cta-ai-workbench',
      ];
      final offsets = [for (final key in order) top(tester, key)];
      expect(
        offsets,
        orderedEquals([...offsets]..sort()),
        reason: 'A `todayPage()` 变体 A 的顺序（activity 卡见 D2，不新增）',
      );
      // 两格统计并排：水卡在左、步数卡在右同一行。
      expect(
        top(tester, 'dashboard-stat-water') ==
            top(tester, 'dashboard-stat-steps'),
        isTrue,
      );
    });
  });

  group('2A 饮水 / 步数（A `.metric-card`）', () {
    dashboardTest('水卡：14dp 内边距、≥183 高、值 22 档、目标行 + 「+ 250 ml」', (tester) async {
      await seedProfile();
      await waterRepository.add(localDate: localDate, amountMl: 750);
      await pump(tester);

      final card = find.byKey(const Key('dashboard-stat-water'));
      final rect = tester.getRect(card);
      // 2026-10-16 用户：「卡片高度需要调整，底下太空白了」——不再钉 A 的
      // `min-height:183px`；改成**内容自适应**：卡高恰好容下三行（标题/数值/
      // 进度条）+ 上下内衬，且不再有约 80dp 的空底。
      expect(rect.height, lessThan(183), reason: '高度由内容决定，不再撑到 A 的 183');
      expect(rect.height, greaterThanOrEqualTo(120), reason: '三行内容仍然要放得下');

      final value = tester.widget<Text>(
        find.byKey(const Key('dashboard-water-value')),
      );
      expect(
        value.style!.fontSize,
        22,
        reason: 'D7：24px 档复用 displayLarge（22），不新造 token',
      );
      // 2026-10-16 用户：「饮水与步数卡能不能都做成 250ml/1000ml 这种」
      // ——当前值与目标并进数值行；独立「目标 N ml」行与「+ 250 ml」按钮下线。
      // 值 = 大号当前值；目标段是小号 suffix（首拍帧发现整串 13 字在半宽卡里
      // 会被截成「750 / 2,...」⇒ 拆两段，一行仍读作「750 / 2,000 ml」）。
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
      expect(
        find.byKey(const Key('dashboard-water-goal')),
        findsNothing,
        reason: '目标已并入数值行，不再单占一行',
      );
      expect(find.byKey(const Key('dashboard-water-quick')), findsNothing);

      // 录入入口不能跟着按钮一起消失：整卡仍然是既有取量弹层的入口。
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('water-amount-submit')), findsOneWidget);
    });

    dashboardTest('未设目标：状态位写「未设目标」，不编目标数字', (tester) async {
      await pump(tester);
      expect(
        tester
            .widget<LfBadge>(find.byKey(const Key('dashboard-water-status')))
            .text,
        '未设目标',
      );
    });

    dashboardTest('步数卡仍然三种态说实话（未接线 = 没有传感器）', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('dashboard-stat-steps')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-steps-empty')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-steps-value')), findsNothing);
    });
  });

  group('2A 下一餐预算卡（A `.next-meal`）', () {
    dashboardTest('剩余额度 + 笔数 + 目标 + 「记录晚餐」', (tester) async {
      await seedProfile();
      await seedMeal(kcal: 800, slot: MealSlot.lunch);
      await seedMeal(kcal: 300, slot: MealSlot.breakfast);
      MealSlot? requested;
      await pump(
        tester,
        wholePage: true,
        onLogMeal: (slot) => requested = slot,
      );

      expect(find.text('下一餐，留给晚餐'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('dashboard-next-meal-remaining')),
            )
            .textSpan!
            .toPlainText(),
        contains('700'),
      );
      expect(find.textContaining('2 笔已记'), findsOneWidget);
      expect(find.text('目标 1,800'), findsOneWidget);
      // 键锚点（docs/21 §5）：卡片五处都要能被机械找到。
      expect(find.byKey(const Key('dashboard-next-meal-chip')), findsOneWidget);
      expect(find.byKey(const Key('dashboard-next-meal-note')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-next-meal-count')),
          matching: find.text('2 笔已记'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('dashboard-next-meal-goal')),
          matching: find.text('目标 1,800'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('cta-log-dinner')));
      expect(requested, MealSlot.dinner, reason: 'A `data-slot="晚餐"`');
    });

    dashboardTest('未设目标：不编剩余额度', (tester) async {
      await pump(tester, wholePage: true);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('dashboard-next-meal-remaining')),
            )
            .textSpan!
            .toPlainText(),
        '— kcal',
        reason: 'A：数值位写 —，单位小字照留（不编数字）',
      );
    });

    /// 本卡的 `budget-line`（值 + 注）直接挂卡，不走整页——整页在 390dp 上
    /// 拿不到 320dp 的窄宽，而这条兜底判据正是按 320dp 卡内宽（288dp）定的。
    Future<void> pumpBudgetLine(
      WidgetTester tester, {
      required double width,
      required double scale,
    }) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DashboardNextMealCard(
              consumedKcal: 1025,
              targetKcal: 2300,
              mealCount: 4,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('1.0× / 360dp：值与注仍是 A 的一行（不许提早竖排）', (tester) async {
      await pumpBudgetLine(tester, width: 360, scale: 1.0);

      final value = tester.getRect(
        find.byKey(const Key('dashboard-next-meal-remaining')),
      );
      final note = tester.getRect(
        find.byKey(const Key('dashboard-next-meal-note')),
      );
      expect(
        note.top,
        lessThan(value.bottom),
        reason: 'A 的 `.budget-line` 是两端一行；1.0× 下提前竖排属于过度降级',
      );
    });

    testWidgets('2.0× / 320dp：值与注竖排（放不下就折行扩高，不把「1,275」截成「1,2…」）', (
      tester,
    ) async {
      await pumpBudgetLine(tester, width: 320, scale: 2.0);

      final value = tester.getRect(
        find.byKey(const Key('dashboard-next-meal-remaining')),
      );
      final note = tester.getRect(
        find.byKey(const Key('dashboard-next-meal-note')),
      );
      // 旧件（值 `Expanded` + 注 `Flexible`）把一行劈两半：2.0× 下值只有
      // 124dp，`ellipsis` 静默把「1,275 kcal」裁成「1,2…」——整页渲染审看
      // 在 `today-dark-320-2.0.png` 抓到。竖排是**机制级见证**（值独占整行）；
      // 「数字完整」由同一变体的渲染图见证：测试字体（Ahem）每字一格宽、
      // 约真字形两倍，量宽度会把真机放得下的判成放不下。
      expect(
        note.top,
        greaterThanOrEqualTo(value.bottom - 0.5),
        reason: '2.0× 下两者必须各占一行（实测值 ${value.height} / 注 ${note.height}）',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('2A 餐次卡（A `.meals-card`）', () {
    dashboardTest('标题「今天吃了什么」+ 查看全部 + 行（2026-10-22：无记录饮食钮）', (tester) async {
      await seedProfile();
      await seedMeal(kcal: 520, slot: MealSlot.lunch, foodName: '西兰花炒鸡丁');
      var recordsOpened = 0;
      await pump(tester, wholePage: true, onOpenRecord: () => recordsOpened++);

      expect(find.text('今天吃了什么'), findsOneWidget);
      final row = find.byKey(const Key('dashboard-meal-row-lunch-0'));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('西兰花炒鸡丁')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.textContaining('520')),
        findsOneWidget,
      );

      // 「查看全部」→ 记录页（A 的 data-action="nutrition-records"）。
      await tester.tap(find.byKey(const Key('cta-view-all-meals')));
      expect(recordsOpened, 1);
      // 2026-10-22 用户：「今日吃了什么的卡片，不需要记录饮食的按钮」。
      expect(find.byKey(const Key('cta-log-meal')), findsNothing);
    });

    dashboardTest('行按餐位域序排（早餐→午餐→晚餐），不按存储串', (tester) async {
      await seedProfile();
      // 逆序落库：存储串序会把晚餐排到午餐前面（渲染审看抓到的真实缺陷）。
      await seedMeal(kcal: 412, slot: MealSlot.dinner);
      await seedMeal(kcal: 208, slot: MealSlot.breakfast);
      await seedMeal(kcal: 232, slot: MealSlot.lunch);
      await pump(tester, wholePage: true);

      // 行键是 `dashboard-meal-row-<slot>-<序号>`，序号随排序变，所以这里
      // 按树序（= 视觉自上下）取餐位串，而不是钉死某一行的序号。
      final rows = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'dashboard-meal-row-',
            ),
      );
      expect(
        tester
            .widgetList<Widget>(rows)
            .map((row) => (row.key! as ValueKey<String>).value.split('-')[3])
            .toList(),
        ['breakfast', 'lunch', 'dinner'],
      );
    });

    dashboardTest('空态：从第一餐开始；不显示 0/0 置信摘要', (tester) async {
      await seedProfile();
      await pump(tester, wholePage: true);

      expect(find.byKey(const Key('dashboard-meals-empty')), findsOneWidget);
      expect(find.text('从第一餐开始'), findsOneWidget);
      expect(find.byKey(const Key('confidence-summary')), findsNothing);
    });

    dashboardTest('行是静态行（A 的 mealRows 无 data-action）', (tester) async {
      await seedProfile();
      await seedMeal();
      await pump(tester, wholePage: true);

      final row = find.byKey(const Key('dashboard-meal-row-lunch-0'));
      expect(row, findsOneWidget);
      // 旧件 `DashboardMealTimeline` 的 `onTapRecorded` 参数在今日页从未接线
      // （实测点不动），A 的今日餐次行也是静态 div ⇒ 这里不产生触摸目标：
      // 编辑入口是「查看全部」→ 记录页的行。
      expect(
        find.descendant(of: row, matching: find.byType(InkWell)),
        findsNothing,
      );
    });
  });

  group('2A AI 入口线（A `.ai-entry-line`）', () {
    dashboardTest('平卡 + A 文案 + 原路由锚点', (tester) async {
      await pump(tester, wholePage: true);

      final entry = find.byKey(const Key('cta-ai-workbench'));
      expect(entry, findsOneWidget);
      expect(find.text('AI 创作'), findsOneWidget);
      expect(find.text('饮食与训练，从一个想法开始'), findsOneWidget);
      expect(tester.getSize(entry).height, greaterThanOrEqualTo(72));
    });
  });

  group('2A 体重卡（A `.weight-card`）', () {
    dashboardTest('标题「体重趋势」+ 最近记录 caption；无 kg 单位行', (tester) async {
      await seedProfile();
      await measurementRepository.saveManualWeight(
        localDate: localDate,
        weightKg: 65.4,
      );
      await pump(tester);

      expect(find.text('体重趋势'), findsOneWidget);
      expect(find.textContaining('最近记录'), findsOneWidget);
      expect(
        find.byKey(const Key('dashboard-weight-trend-value')),
        findsOneWidget,
      );
      // 2026-10-16 用户要求删掉周期注（本卡不再写「本周 · 周一至周日」）。
      expect(
        find.byKey(const Key('dashboard-weight-period-note')),
        findsNothing,
      );
      expect(find.byKey(const Key('dashboard-weight-hint')), findsOneWidget);
      expect(
        find.byKey(const Key('weight-bar-chart-unit')),
        findsNothing,
        reason: 'D8b：A 的图没有独立 kg 单位行（caption 已带 kg）',
      );
      expect(find.textContaining('本周 · 周一至周日'), findsNothing);
    });

    dashboardTest('柱色：今天 = brand，其余 = weight（A `--weight`）', (tester) async {
      await seedProfile();
      await measurementRepository.saveManualWeight(
        localDate: formatLocalDate(now.subtract(const Duration(days: 1))),
        weightKg: 66,
      );
      await measurementRepository.saveManualWeight(
        localDate: localDate,
        weightKg: 65.4,
      );
      await pump(tester);

      // 2026-10-13 是周二 ⇒ 本周七格（10-12…10-18）里今天在第 2 格
      // （index 1），昨天（周一）在第 1 格。
      final todayBar = tester.widget<DecoratedBox>(
        find.byKey(const Key('weight-bar-chart-bar-1')),
      );
      final otherBar = tester.widget<DecoratedBox>(
        find.byKey(const Key('weight-bar-chart-bar-0')),
      );
      final todayColor = (todayBar.decoration as BoxDecoration).color;
      final otherColor = (otherBar.decoration as BoxDecoration).color;
      expect(todayColor, LfColors.mint(Brightness.light).tone(500));
      expect(otherColor, LfColors.weightLight);
    });
  });

  group('2A 空/加载/错误态不变', () {
    dashboardTest('无仓储 → 占位页（既有诚实回退）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: DashboardPage(now: null)),
      );
      await tester.pumpAndSettle();
      // 占位页把标题画两处（顶栏 + 正文），只断言「有」。
      expect(find.text('今日'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  // MacroBar 的静态几何（A 卡内值）在本文件顶部断言处使用；这里保留一个
  // 显式常量核对，避免实现漂移后测试仍然通过。
  test('MacroBar 卡内几何常量 = A 有效值', () {
    expect(MacroBar.cardDotSize, 5);
    expect(MacroBar.cardTrackHeight, 5);
  });
}
