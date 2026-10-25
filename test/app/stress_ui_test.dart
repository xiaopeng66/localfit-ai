import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/lf_bottom_nav.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

import '../support/food_fixture.dart';

/// 暴力测试（docs/22 阶段 J 收尾）：把「大字号 × 窄屏 × 极端安全区 ×
/// 双击风暴 × 极端数据」五个维度叠在同一套真实装配上巡检。
///
/// 溢出判据沿用 `narrow_layout_audit_test.dart` / `two_point_zero_ui_audit_test.dart`
/// 的机器可测信号（`RenderFlex overflowed`），末尾统一断言，一次拿到完整
/// 清单而不是停在第一个问题。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 巡检用「当天」（与注入给 App 的 [now] 一致）。
  const localDate = '2026-09-13';

  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    // 建档：体重/餐食落库都要求有本地档案，缺档案时保存会走失败分支，
    // 那样「双击是否写两次」就测不到了（假绿）。
    //
    // 时钟必须钉在巡检日（`localDate = 2026-09-13`，与注入 App 的 `now` 同一天）：
    // 建档同时写 `dailyTargets` 行（按建档当天的 localDate），用真钟会写到**真实
    // 今天**，于是今日页（2026-09-13）读不到目标 ⇒ 热量环没有百分比那一行、
    // foot 走「尚未设定目标」分支，2.0× 内孔用例的「三段文字」只剩两段
    // （round7 2A 实测：`dashboard-ring-percent` findsNothing）。
    await CompleteOnboarding(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(DateTime(2026, 9, 13, 12)),
    )(
      const OnboardingInput(
        age: 30,
        biologicalSex: BiologicalSex.male,
        heightCm: 175,
        weightKg: 75,
        activityLevel: ActivityLevel.moderatelyActive,
        goal: HealthGoal.loseFat,
        targetWeightKg: 68,
      ),
    );
    const ids = UuidV7Generator();
    const clock = SystemAppClock();
    foodRepository = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
    mealRepository = MealRepository(
      database: database,
      idGenerator: ids,
      clock: clock,
    );
  });

  tearDown(() => database.close());

  Widget app(String location) => LocalFitApp(
    initialLocation: location,
    foodRepository: foodRepository,
    mealRepository: mealRepository,
    measurementRepository: MeasurementRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    exerciseRepository: ExerciseRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    workoutPlanRepository: WorkoutPlanRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    workoutSessionRepository: WorkoutSessionRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    ),
    profileIdentityRepository: ProfileIdentityRepository(database: database),
    now: DateTime(2026, 9, 13),
  );

  void useViewport(
    WidgetTester tester, {
    double textScale = 1.0,
    Size size = const Size(320, 640),
    double top = 0,
    double bottom = 0,
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    if (top != 0 || bottom != 0) {
      tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
      tester.view.viewPadding = FakeViewPadding(top: top, bottom: bottom);
    }
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
  }

  /// 持续动画（骨架屏呼吸、转圈）会让 pumpAndSettle 永不收敛，限时兜底。
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 15),
    );
  }

  late List<String> overflows;
  final List<String> stepReports = <String>[];
  void Function(FlutterErrorDetails)? originalHandler;

  void startAudit() {
    overflows = <String>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('RenderFlex overflowed')) {
        overflows.add(message.split('\n').first);
        return;
      }
      previousHandler?.call(details);
    };
    originalHandler = previousHandler;
  }

  void finishAudit(String step) {
    for (var i = 0; i < overflows.length; i++) {
      overflows[i] = '[$step] ${overflows[i]}';
    }
    stepReports.addAll(overflows);
    overflows.clear();
  }

  Future<void> runAudit(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    stepReports.clear();
    try {
      await body();
    } finally {
      FlutterError.onError = originalHandler;
    }
    expect(stepReports, isEmpty, reason: stepReports.join('\n'));
  }

  Future<void> scrollThroughPage(WidgetTester tester) async {
    await tester.dragFrom(const Offset(160, 400), const Offset(0, -1200));
    await settle(tester);
    await tester.dragFrom(const Offset(160, 400), const Offset(0, 1200));
    await settle(tester);
  }

  Future<void> tapSlot(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(Key(LfBottomNav.slotKeys[index])));
    await settle(tester);
  }

  /// 饮食页 chips 是横向 ListView；窄屏/大字号下先把目标 chip 拖进视口。
  Future<void> openChip(WidgetTester tester, String label) async {
    final chip = find.text(label);
    if (!tester.any(chip)) {
      fail('未找到 chip：$label');
    }
    final rect = tester.getRect(chip);
    if (rect.right > tester.view.physicalSize.width || rect.left < 0) {
      final view = find.ancestor(
        of: find.text('记录'),
        matching: find.byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
        ),
      );
      await tester.dragUntilVisible(chip, view, const Offset(-100, 0));
      await settle(tester);
    }
    await tester.tap(chip);
    await settle(tester);
  }

  void dismissSnackBar(WidgetTester tester) {
    final messenger = tester.state<ScaffoldMessengerState>(
      find.byType(ScaffoldMessenger).first,
    );
    messenger.removeCurrentSnackBar();
    messenger.clearSnackBars();
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  // ── 1. 大字号 × 窄屏：逐页溢出巡检 ──────────────────────────────────────

  for (final scale in const [1.3, 1.5, 2.0]) {
    testWidgets('大字号 $scale× + 320dp：四大主页与饮食 chips 无溢出', (tester) async {
      useViewport(tester, textScale: scale);
      startAudit();
      await runAudit(tester, () async {
        await tester.pumpWidget(app(AppRoutes.dashboard));
        await settle(tester);
        await scrollThroughPage(tester);
        finishAudit('今日');

        await tapSlot(tester, 3);
        await scrollThroughPage(tester);
        finishAudit('训练');

        await tapSlot(tester, 2);
        await scrollThroughPage(tester);
        finishAudit('AI 对话');

        await tapSlot(tester, 4);
        await scrollThroughPage(tester);
        finishAudit('我的');

        await tapSlot(tester, 1);
        await scrollThroughPage(tester);
        finishAudit('饮食·记录');

        // 「计划」「食谱」两个 tab 随食谱计划整族下线（docs/28 §6.1）。
        for (final chip in const ['菜单', '食物库']) {
          await openChip(tester, chip);
          await scrollThroughPage(tester);
          finishAudit('饮食·$chip');
        }
        await unmountApp(tester);
      });
    });
  }

  // ── 2. 极端安全区（超大状态栏 + 超大手势带）────────────────────────────

  testWidgets('极端安全区（状态栏 160dp + 手势带 96dp）：四个主页面无溢出且底栏贴底', (tester) async {
    useViewport(tester, textScale: 1.3, top: 160, bottom: 96);
    startAudit();
    await runAudit(tester, () async {
      await tester.pumpWidget(app(AppRoutes.dashboard));
      await settle(tester);
      await scrollThroughPage(tester);
      // 底栏契约：栏高 = 64dp 栏体 + 手势带，且毛玻璃铺到屏幕物理底边
      // （与 system_inset_test 同一不变量，这里用手势带 96dp 加压）。
      final screenBottom = tester.getRect(find.byType(Scaffold).first).bottom;
      final bar = tester.getRect(find.byKey(const Key('lf-bottom-nav')));
      expect(bar.bottom, screenBottom, reason: '手势带里必须仍是栏体');
      expect(bar.height, 64 + 96, reason: '栏高 = 栏体 + 手势带');
      finishAudit('今日');

      for (final slot in const [3, 2, 4, 1]) {
        await tapSlot(tester, slot);
        await scrollThroughPage(tester);
        finishAudit('槽位 $slot');
      }
      await unmountApp(tester);
    });
  });

  testWidgets('零安全区 + 2.0× 字号：栏高仍是 64dp，不凭空多留白', (tester) async {
    useViewport(tester, textScale: 2.0);
    await tester.pumpWidget(app(AppRoutes.dashboard));
    await settle(tester);
    expect(
      tester.getRect(find.byKey(const Key('lf-bottom-nav'))).height,
      64,
      reason: '无手势带时栏高必须恰好 64dp',
    );
    await unmountApp(tester);
  });

  // ── 3. 双击风暴：保存类按钮连点两次 ────────────────────────────────────

  testWidgets('双击「保存体重」：只落一次库，且第二次弹层不得把下层路由一并弹掉', (tester) async {
    useViewport(tester);
    await tester.pumpWidget(app(AppRoutes.dashboard));
    await settle(tester);

    // 悬浮层会截获命中链（与 narrow_layout_audit 同一夹具限制），直接调回调。
    //
    // 【按新结构重新定位】入口 2026-10-09（docs/31 需求 44）起是 `LfIconButton`
    // （纯图标圆钮）。它的 `onPressed` 落在**内部那颗 `InkWell`** 上——外层
    // 44dp 命中盒只是 `SizedBox`+`Center`，自己不带回调。所以取回调要往
    // 子树里找第一个 `InkWell`，不能再当成 `TextButton` 取 `.onPressed`
    // （那是 B6 时代的写法）。
    //
    // 这里只取回调，断言的是「双击只落一次库、第二次 pop 不弹掉今日页」
    // 这条行为，与按钮类型无关。
    //
    // 2026-10-08 R2：建档已落一条体重，柱图支持单柱 ⇒「1 条记录」不再走空态，
    // 空态那颗 `dashboard-weight-record` 不存在了。改用卡头那颗
    // `dashboard-weight-add`（同一个 `WeightEntryDialog`）。
    final entry = tester
        .widget<InkWell>(
          find
              .descendant(
                of: find.byKey(const Key('dashboard-weight-add')),
                matching: find.byType(InkWell),
              )
              .first,
        )
        .onTap!;
    entry();
    await settle(tester);
    await tester.enterText(find.byKey(const Key('weight-input')), '62.5');
    await settle(tester);

    final save = find.byKey(const Key('weight-save'));
    // 真·双击：两次 tap 之间不 pump，第二击与第一击落在同一帧的同一按钮上。
    //
    // 第二击**故意允许落空**（`warnIfMissed: false`）：第一击已经 `pop`，
    // 弹层路由进入退场动画时 `ModalRoute` 会给内容套上 `IgnorePointer`，
    // 于是第二次点击被框架挡在门外——这正是"双击只保存一次"的实现机理，
    // 断言要锁的也正是这个结果（两击都不该写两次、都不该多弹一层）。
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await settle(tester);
    dismissSnackBar(tester);

    final rows = await database.select(database.measurements).get();
    expect(
      rows.where((row) => row.localDate == localDate).length,
      1,
      reason: '双击保存后当天体重测量只能有一行',
    );
    expect(
      find.byKey(const Key('dashboard-weight-add')),
      findsOneWidget,
      reason: '第二次 pop 不得把今日页也弹掉（否则用户看到空白/回到上级）',
    );
    await unmountApp(tester);
  });

  testWidgets('双击「保存餐食」：只落一次库，且仍停在饮食页', (tester) async {
    useViewport(tester);
    await tester.pumpWidget(app(AppRoutes.nutrition));
    await settle(tester);

    await tester.tap(find.byTooltip('记录一餐'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('meal-entry-by-food')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('meal-food-search')), '米饭');
    await settle(tester);
    await tester.tap(find.text('米饭').last);
    await settle(tester);

    final save = find.byKey(const Key('meal-save'));
    // 同「保存体重」：第二击被退场动画的 `IgnorePointer` 挡住，属预期。
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await settle(tester);
    dismissSnackBar(tester);

    final meals = await mealRepository.listRecent();
    expect(
      meals.where((meal) => meal.localDate == localDate).length,
      1,
      reason: '双击保存后当天餐食只能有一条',
    );
    expect(find.byTooltip('记录一餐'), findsOneWidget, reason: '第二次 pop 不得把饮食页也弹掉');
    await unmountApp(tester);
  });

  // ── 4. 事件风暴：连续快速切槽位 ───────────────────────────────────────

  testWidgets('事件风暴：底栏槽位连点 25 次不抛异常，且落在最后一次点击的页', (tester) async {
    useViewport(tester);
    await tester.pumpWidget(app(AppRoutes.dashboard));
    await settle(tester);

    // 不 settle 连点：模拟用户手速极快的来回切换。
    for (var i = 0; i < 5; i++) {
      for (final slot in const [1, 4, 0, 3, 2]) {
        await tester.tap(find.byKey(Key(LfBottomNav.slotKeys[slot])));
      }
    }
    await settle(tester);

    // 最后一次落点是 AI 对话槽（index 2）。这一轮装配没有 AI 会话服务，
    // 该分支渲染的是「AI 助手」未配置占位页，所以按槽位选中态 + 页内文案
    // 两路断言（`AiConversationPage` 只在接线后才存在）。
    final nav = tester.widget<LfBottomNav>(find.byType(LfBottomNav));
    expect(nav.currentIndex, 2, reason: '风暴之后底栏选中态应是最后一次点击的槽位');
    expect(find.text('AI 助手'), findsOneWidget, reason: '风暴之后应停在 AI 对话页');
    await unmountApp(tester);
  });

  // ── 5. 极端数据：超长名称 + 巨额营养值 ────────────────────────────────

  testWidgets('极端数据：120 字食物名 + 99990 kcal 的餐食在记录页不溢出且原样显示', (tester) async {
    final longName = '超长食物名称压力测试' * 12; // 120 字
    await mealRepository.create(
      MealDraft(
        localDate: localDate,
        slot: MealSlot.lunch,
        items: [
          MealItemDraft(
            foodName: longName,
            grams: 9999,
            nutrition: const NutritionValues(
              kcal: 99990,
              proteinGrams: 9999,
              carbsGrams: 9999,
              fatGrams: 9999,
            ),
          ),
        ],
      ),
    );

    useViewport(tester);
    startAudit();
    await runAudit(tester, () async {
      await tester.pumpWidget(app(AppRoutes.nutrition));
      await settle(tester);
      await scrollThroughPage(tester);
      finishAudit('饮食·记录（极端数据）');
    });

    // 餐食行在滚动回顶部后可能已被懒列表回收，断言前先滚到它。
    await tester.scrollUntilVisible(
      find.textContaining('超长食物名称压力测试'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    // 数据必须原样交给界面（截断只能由渲染层做，不能改数据）——菜品行是
    // 「名称 + 克数」一个 Text，所以按前缀找。
    expect(find.textContaining('超长食物名称压力测试'), findsOneWidget);
    expect(find.textContaining('9999g'), findsWidgets, reason: '极端克数也要原样显示');
    await unmountApp(tester);
  });

  // ── 6. 固定几何件在大字号下的退化（本轮修掉的两个 2.0× 溢出）──────────

  testWidgets('热量圆环中心三段文字：1.0× 与 2.0× 都整体落在圆环内孔里', (tester) async {
    for (final scale in const [1.0, 2.0]) {
      useViewport(tester, textScale: scale);
      await tester.pumpWidget(app(AppRoutes.dashboard));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('lf-calorie-ring')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);

      final ring = tester.getRect(find.byKey(const Key('lf-calorie-ring')));
      expect(ring.width, LfDimens.calorieRingSize, reason: '圆环几何是设计稿定死的');
      expect(ring.height, LfDimens.calorieRingSize);
      // 判据取**内孔**（描边内缘围出的空洞）而不是 120dp 外框：只断言
      // 「不出外框」时，被缩到外框宽的文字会压在轨道描边上却依然全绿——
      // 真机 2.0× 截图放大后抓到过这一次漏判（`/ N kcal` 两头压在环上）。
      final hole = Rect.fromCenter(
        center: ring.center,
        width: LfDimens.calorieRingInnerSize,
        height: LfDimens.calorieRingInnerSize,
      );
      // D6：目标值的锚点已搬去卡片 foot（`dashboard-ring-target`），
      // 环内只剩值 / 固定标签 / 百分比——内孔约束只对**环内**这几处成立。
      for (final key in const [
        'dashboard-ring-consumed',
        'dashboard-ring-percent',
      ]) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(
          rect.left,
          greaterThanOrEqualTo(hole.left - 0.5),
          reason: '$scale× 下 $key 不得压到圆环左侧描边',
        );
        expect(
          rect.right,
          lessThanOrEqualTo(hole.right + 0.5),
          reason: '$scale× 下 $key 不得压到圆环右侧描边',
        );
        expect(
          rect.top,
          greaterThanOrEqualTo(hole.top - 0.5),
          reason: '$scale× 下 $key 不得压到圆环上侧描边',
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(hole.bottom + 0.5),
          reason: '$scale× 下 $key 不得压到圆环下侧描边',
        );
      }
      // 反向哨兵：目标值不许悄悄回到环里（D6 的搬运必须是真的）。
      expect(
        find.descendant(
          of: find.byKey(const Key('lf-calorie-ring')),
          matching: find.byKey(const Key('dashboard-ring-target')),
        ),
        findsNothing,
        reason: '目标值的锚点在卡片 foot，不在环内（D6）',
      );
      expect(find.byKey(const Key('dashboard-ring-target')), findsOneWidget);
      await unmountApp(tester);
    }
  });
  testWidgets('菜单段头汇总行：按内容自然宽排、窄屏大字不越界也不压扁', (tester) async {
    // 2026-10-14（Round7 阶段 3 步骤 1，D25）：原 hero 的两列统计（`Flexible` +
    // 1px 分隔线 + `IntrinsicHeight`）随 hero 卡退场，改 A `.quiet-label` 汇总行
    // ——「已安排 N 餐 · 预计 X kcal」两段文字 + 一枚间隔点，`Wrap` 排布。
    // 这条回归的**意图不变**（这是它存在的理由，不是它的实现）：
    //  ① 每段按内容自然宽排（不得被拉伸成等分宽，那会让「已安排 0 餐」与
    //     「预计 1248 kcal」看起来同样重要）；
    //  ② 320dp × 大字下不越界、也不被压扁到内容放不下（下限 = min(自然宽, 段头宽)）。
    final plannedKey = const Key('nutrition-menu-hero-planned');
    final kcalKey = const Key('nutrition-menu-hero-kcal');

    for (final scale in const [1.0, 2.0]) {
      // ① 宽屏基准：两段都不会被挤，量到的就是内容自然宽。
      useViewport(tester, textScale: scale, size: const Size(1200, 800));
      await tester.pumpWidget(app(AppRoutes.nutrition));
      await settle(tester);
      await openChip(tester, '菜单');
      await settle(tester);

      final natural = tester.getRect(find.byKey(plannedKey)).width;
      // 基准自检：宽屏下量到的必须是**内容自然宽**。若把 `Wrap` 换成会给子项
      // 分配满宽的容器（等分/`Expanded`），宽屏这侧也会被拉伸，基准就跟着
      // 漂移——那时越界断言全成了空转（旧回归的变异实测踩到过这一点）。
      final wideText = tester.widget<Text>(find.byKey(plannedKey));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(child: Text(wideText.data!, style: wideText.style)),
          ),
        ),
      );
      final standalone = tester.getSize(find.text(wideText.data!)).width;
      expect(
        natural,
        closeTo(standalone, 1.5), // 环境字体的度量残差 <2%
        reason: '宽屏基准必须等于内容自然宽（不得是被拉伸的等分宽）',
      );
      await unmountApp(tester);

      // ② 窄屏 320dp：越界与「是否被压扁」的双向断言。
      useViewport(tester, textScale: scale);
      await tester.pumpWidget(app(AppRoutes.nutrition));
      await settle(tester);
      await openChip(tester, '菜单');
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(plannedKey),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);

      expect(tester.takeException(), isNull, reason: '$scale× 下段头不得溢出');
      final header = tester.getRect(
        find.byKey(const Key('nutrition-menu-hero')),
      );
      final rects = <String, Rect>{
        '已安排段': tester.getRect(find.byKey(plannedKey)),
        '预计段': tester.getRect(find.byKey(kcalKey)),
        '段标题': tester.getRect(find.text('每日菜品推荐')),
        'pill': tester.getRect(find.text('本地已分析菜品')),
      };
      for (final entry in rects.entries) {
        expect(
          entry.value.left,
          greaterThanOrEqualTo(header.left - 0.5),
          reason: '$scale× 下「${entry.key}」不得越出段头左边界',
        );
        expect(
          entry.value.right,
          lessThanOrEqualTo(header.right + 0.5),
          reason: '$scale× 下「${entry.key}」不得越出段头右边界',
        );
      }
      final plannedWidth = rects['已安排段']!.width;
      expect(
        plannedWidth,
        lessThanOrEqualTo(natural + 0.5),
        reason: '$scale× 下这一段不得被拉长（不许被摊成整行宽）',
      );
      final floor = natural < header.width ? natural : header.width;
      expect(
        plannedWidth,
        greaterThanOrEqualTo(floor - 0.5),
        reason: '$scale× 下这一段不得被压扁到内容放不下（下限 = min(自然宽, 段头宽)）',
      );
      if (scale == 1.0) {
        // 1.0× 下两段本来放得下：汇总行必须是单行（A 的 quiet-label 一行两段）。
        final planned = rects['已安排段']!;
        final kcal = rects['预计段']!;
        expect(
          kcal.top,
          lessThan(planned.bottom),
          reason: '1.0× 下汇总行必须是一行（两段纵向有重叠）',
        );
        expect(
          tester.getSize(find.byKey(plannedKey)).height,
          closeTo(12 * 1.4, 1.0), // LfText.caption 字号 × 行高
          reason: '1.0× 下汇总行必须是单行高',
        );
      }
      await unmountApp(tester);
    }
  });
}
