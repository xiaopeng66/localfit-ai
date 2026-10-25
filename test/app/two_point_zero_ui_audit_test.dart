import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_celebration.dart';
import 'package:localfit_ai/app/design/widgets/count_up_text.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_workbench/presentation/ai_workbench_page.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_page.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/meal_record_card.dart';

/// 2.0-6i-4：2.0 新界面的可访问性巡检（docs/07 §9.3 最后一条）——
/// 亮暗色、大字号、窄屏、无障碍与减弱动画。
///
/// 溢出用 `RenderFlex overflowed` 作为机器可测信号（沿用
/// `narrow_layout_audit_test.dart` 的做法）；语义用 `tooltip`/文字标签，
/// 不用颜色单独表达状态；减弱动画下入场动画直通。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FixedAppClock clock;
  late CanteenRepository canteens;

  /// 巡检用的「当天」：本地当天中午。
  ///
  /// 菜单 tab 的 `_todayIso()` 走真实本地时间，所以这里不能用写死的日期，
  /// 否则跨天跑就会把种子快照判成过期（巡检变成空态的假绿）。
  late DateTime noonLocal;
  late String todayIso;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final localNow = DateTime.now();
    noonLocal = DateTime(localNow.year, localNow.month, localNow.day, 12);
    todayIso = formatLocalDate(noonLocal);
    clock = FixedAppClock(noonLocal.toUtc());
    canteens = CanteenRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    final ts = DateTime.now().toUtc();
    await database
        .into(database.campusProfiles)
        .insert(
          CampusProfilesCompanion.insert(
            id: 'campus-1',
            name: '示范大学',
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    await database
        .into(database.venues)
        .insert(
          VenuesCompanion.insert(
            id: 'venue-1',
            campusId: 'campus-1',
            name: '东区食堂',
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    // 自建食堂目录（3.0）：地点 → 窗口 → 菜品，全部走仓库写路径建，
    // 这样巡检覆盖的是真实接线（内部 catalog 快照由仓库自己建立）。
    final windowId = await canteens.createWindow(
      venueId: 'venue-1',
      name: '一楼窗口',
      openTime: '10:30',
      closeTime: '13:30',
    );
    final dishId = await canteens.createDish(windowId: windowId, name: '鸡胸肉饭');
    await canteens.recordNutrition(
      dishId: dishId,
      kcalPer100g: 165,
      proteinPer100g: 31,
      carbsPer100g: 0,
      fatPer100g: 3.6,
      grade: 'B',
      confidence: 0.9,
    );
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'food-a',
            name: '鸡胸肉',
            kcalPer100g: 165,
            proteinPer100g: 31,
            carbsPer100g: 0,
            fatPer100g: 3.6,
            source: 'seed',
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    await database
        .into(database.menuItemFoodMatches)
        .insert(
          MenuItemFoodMatchesCompanion.insert(
            id: 'match-a',
            menuItemId: dishId,
            foodId: 'food-a',
            matchStatus: const Value('confirmed'),
            confidence: const Value(0.95),
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    // 一顿真实餐食：记录 tab 的餐食卡与减弱动画检查都要有内容。
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-1',
            localDate: todayIso,
            slot: 'breakfast',
            eatenAt: noonLocal.toUtc(),
            source: 'manual',
            createdAt: ts,
            updatedAt: ts,
          ),
        );
    await database
        .into(database.mealItems)
        .insert(
          MealItemsCompanion.insert(
            id: 'mi-1',
            mealId: 'meal-1',
            foodId: const Value('food-a'),
            foodNameSnapshot: '鸡胸肉',
            grams: 120,
            kcalSnapshot: 198,
            proteinSnapshot: 37.2,
            carbsSnapshot: 0,
            fatSnapshot: 4.3,
            createdAt: ts,
            updatedAt: ts,
          ),
        );
  });

  tearDown(() => database.close());

  late List<String> overflows;

  /// 当前巡检的显示条件（由 [useViewport] 设定，pump 辅助方法读取）。
  var auditDark = false;

  /// 收集 `RenderFlex overflowed`；测试体必须用 [runAudit] 包裹。
  /// 断言时带上定位信息（溢出的 Row/Column 及其父链摘要）。
  Future<void> runAudit(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('RenderFlex overflowed')) {
        overflows.add(
          message
              .split('\n')
              .where((line) => line.trim().isNotEmpty)
              .take(12)
              .join('\n'),
        );
        return;
      }
      previous?.call(details);
    };
    try {
      await body();
    } finally {
      FlutterError.onError = previous;
    }
    expect(overflows, isEmpty, reason: overflows.join('\n---\n'));
  }

  Future<void> settle(WidgetTester tester) => tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 15),
  );

  /// 2.0 巡检的最小视口（窄屏）与显示条件（大字号 / 暗色 / 减弱动画）。
  void useViewport(
    WidgetTester tester, {
    Size size = const Size(320, 640),
    double textScale = 1.0,
    bool darkTheme = false,
    bool reducedMotion = false,
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: reducedMotion);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    auditDark = darkTheme;
  }

  Future<FoodRepository> foods() async => FoodRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: clock,
  );

  Future<MealRepository> meals() async => MealRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: clock,
  );

  /// 菜品库仓储：菜单页的唯一主来源（docs/21 §5.3）。接上它菜单 tab 才走
  /// 生产路径（空库 → 空态），而不是「未接线」的降级占位。
  DishLibraryRepository dishLibrary() => DishLibraryRepository(
    database: database,
    idGenerator: const UuidV7Generator(),
    clock: clock,
  );

  /// 饮食页：`tab` 为 null 时停在「记录」tab（主卡 + 周条 + 餐食卡）；
  /// 传 [NutritionTab.menu] 时切到「菜单」tab（2.0-6c 的新鲜度条 + 窗口分组）。
  Future<void> pumpNutrition(WidgetTester tester, {NutritionTab? tab}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: auditDark ? AppTheme.dark() : AppTheme.light(),
        home: NutritionPage(
          repository: await foods(),
          mealRepository: await meals(),
          dishLibraryRepository: dishLibrary(),
          canteenRepository: tab == null ? null : canteens,
          now: noonLocal,
        ),
      ),
    );
    await settle(tester);
    if (tab != null) {
      // 320dp+1.5× 时胶囊可能被截断，find.text 命中不到；改用稳定 Key。
      //
      // 【T6c 期间实测】切 tab 后再 `pumpAndSettle` 在**暗色**下会挂住
      // （drift stream + 胶囊动画组合，直到框架 10 分钟兜底）；切 tab 只是
      // 换 body，用有限 pump 就够（300ms 覆盖胶囊过渡）。
      await tester.tap(find.byKey(Key('nutrition-tab-menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('窄屏 320dp + 大字号 1.5×：饮食页不溢出', (tester) async {
    useViewport(tester, textScale: 1.5);
    await runAudit(tester, () async {
      await pumpNutrition(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  /// AI 工作台：打开**画廊**（docs/32 §4 T6c 后不再有草案卡/详情页）。
  Future<void> pumpWorkbenchGallery(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: auditDark ? AppTheme.dark() : AppTheme.light(),
        home: const AiWorkbenchPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('窄屏 320dp + 大字号 1.5×：AI 工作台任务卡不溢出', (tester) async {
    useViewport(tester, textScale: 1.5);
    await runAudit(tester, () async {
      await pumpWorkbenchGallery(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('窄屏 320dp + 大字号 1.5×：菜单 tab 不溢出', (tester) async {
    useViewport(tester, textScale: 1.5);
    await runAudit(tester, () async {
      await pumpNutrition(tester, tab: NutritionTab.menu);
      // 菜单页主来源是菜品库（docs/21 §5.3）；食堂窗口目录已收进二级入口，
      // 首屏是 hero + 胶囊行 + 菜品卡。这里断言 hero 与空态都在，
      // 说明结构真的渲染出来了而不是被挤成 0 高（2.0-6i-4 的假绿教训）。
      expect(find.byKey(const Key('nutrition-menu-hero')), findsOneWidget);
      expect(find.text('菜品库还是空的。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('暗色：状态仍靠文字表达（记录页，不只用颜色）', (tester) async {
    useViewport(tester, size: const Size(400, 900), darkTheme: true);

    await pumpNutrition(tester);
    expect(find.text('记录'), findsWidgets);
    // 2026-10-24（`docs/56` R4）：记录页的「下一餐详情」入口整族退役 →
    // 本用例原来钉的「首屏有那一行入口」改为**反向**断言（不得出现），
    // 「状态靠文字不靠颜色」这条判据本身不变。
    expect(find.text('下一餐详情'), findsNothing, reason: 'R4：入口已退役');
    expect(find.textContaining('未记录已吃'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('暗色：菜单 tab 空态仍靠文字表达（不只用颜色）', (tester) async {
    useViewport(tester, size: const Size(400, 900), darkTheme: true);

    // 【写法说明】原先是同一条用例里连续两次 `pumpNutrition`（先记录页再
    // 菜单 tab）；T6c 期间实测：第二次在**暗色**下会挂到框架 10 分钟兜底
    // 超时（同一用例内 drift stream 未随组件销毁而静止）。拆成两条独立
    // 用例（本文件其余暗色用例也都是「一条用例只 pump 一次」），语义不变。
    await pumpNutrition(tester, tab: NutritionTab.menu);
    // 菜单 tab 的空态同样是文字，不靠颜色表达「没有菜品」。
    expect(find.byKey(const Key('nutrition-menu-hero')), findsOneWidget);
    expect(find.text('菜品库还是空的。'), findsOneWidget);
    expect(find.text('在食堂目录里自建菜品，或让 AI 生成今日菜单。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('2.0 界面的图标按钮都有 tooltip（读屏可定位）', (tester) async {
    useViewport(tester, size: const Size(400, 900));

    final missing = <String>[];
    void auditIconButtons(String where) {
      for (final button in tester.widgetList<IconButton>(
        find.byType(IconButton),
      )) {
        final tooltip = button.tooltip;
        if (tooltip == null || tooltip.isEmpty) {
          missing.add('$where: ${button.icon.toString()}');
        }
      }
    }

    await pumpNutrition(tester);
    auditIconButtons('饮食页(记录)');
    await tester.pumpWidget(const SizedBox.shrink());

    await pumpNutrition(tester, tab: NutritionTab.menu);
    auditIconButtons('饮食页(菜单)');
    await tester.pumpWidget(const SizedBox.shrink());

    await pumpWorkbenchGallery(tester);
    auditIconButtons('AI 工作台');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));

    expect(missing, isEmpty, reason: '以下图标按钮缺少 tooltip：${missing.join('、')}');
  });

  testWidgets('减弱动画：入场动画直通，不跑装饰动效', (tester) async {
    useViewport(tester, size: const Size(400, 900), reducedMotion: true);
    await pumpNutrition(tester);

    // 餐食卡直接呈现：没有装饰性的透明度/位移包裹层。
    expect(find.byType(MealRecordCard), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(MealRecordCard),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );

    // 对照：未开启减弱动画时存在入场透明度层。
    await tester.pumpWidget(const SizedBox.shrink());
    useViewport(tester, size: const Size(400, 900));
    await pumpNutrition(tester);
    expect(
      find.ancestor(
        of: find.byType(MealRecordCard),
        matching: find.byType(Opacity),
      ),
      findsWidgets,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  // ---- UI-E 全量回归（docs/21 §8.3）：暗色/高对比 token 映射、大字体 2.0×、
  // 减弱动画（新增动效退化）、语义标签、关键卡 golden。----

  test('Token 映射（docs/21 §2.8）：暗/高对比成组注入；按钮提档、描边、44dp 触达', () {
    // 暗/亮语义与组件扩展按亮度成组注入（identity 断言：漏注入会回落亮色）。
    expect(
      AppTheme.dark().extension<LfSemanticColors>(),
      same(LfSemanticColors.dark),
    );
    expect(
      AppTheme.dark().extension<LfComponentColors>(),
      same(LfComponentColors.dark),
    );
    expect(
      AppTheme.light(highContrast: true).extension<LfSemanticColors>(),
      same(LfSemanticColors.light),
    );
    // 暗色主色已提亮到 mint-400；暗色高对比不再提（已到顶）。
    expect(AppTheme.dark().colorScheme.primary, LfSemanticColors.dark.primary);
    expect(
      AppTheme.dark(highContrast: true).colorScheme.primary,
      LfSemanticColors.dark.primary,
    );
    // 高对比（亮色）：Round7 A 下**不再加深品牌底**（按钮字是深墨
    // `--lf-primary-foreground`，加深会跌破 4.5），高对比只靠 2dp 描边表达；
    // 输入框 A 常态就有 1dp `--border` 描边，高对比加粗到 2dp `--fg`。
    Color? elevatedButton(bool highContrast) =>
        AppTheme.light(highContrast: highContrast)
            .elevatedButtonTheme
            .style
            ?.backgroundColor
            ?.resolve(const {});
    expect(elevatedButton(false), LfSemanticColors.light.primary);
    expect(elevatedButton(true), LfSemanticColors.light.primary);
    expect(
      AppTheme.light().inputDecorationTheme.enabledBorder?.borderSide.style,
      BorderStyle.solid,
    );
    expect(
      AppTheme.light().inputDecorationTheme.enabledBorder?.borderSide.color,
      LfSemanticColors.light.border,
    );
    final highContrastBorder = AppTheme.light(highContrast: true)
        .inputDecorationTheme
        .enabledBorder
        ?.borderSide;
    expect(highContrastBorder?.style, BorderStyle.solid);
    expect(highContrastBorder?.width, 2);
    expect(highContrastBorder?.color, LfSemanticColors.light.foreground);
    // 主按钮触达 ≥44dp（A 有效值 `.btn{min-height:44px}`）。
    final minSize = AppTheme.light().elevatedButtonTheme.style?.minimumSize
        ?.resolve(const {});
    expect(minSize?.height, greaterThanOrEqualTo(LfDimens.minTouchTarget));
    // 聚焦外发光（Round7 A）：聚焦描边 2dp，颜色取 `--brand-strong`
    // （`refinement.css:9` `:focus-visible{outline:2px solid var(--brand-strong)}`）。
    expect(
      AppTheme.light().inputDecorationTheme.focusedBorder?.borderSide.width,
      2.0,
    );
    expect(
      AppTheme.light().inputDecorationTheme.focusedBorder?.borderSide.color,
      LfColors.mintText(Brightness.light),
    );
    expect(
      AppTheme.light(highContrast: true)
          .inputDecorationTheme
          .focusedBorder
          ?.borderSide
          .color,
      // 高对比不再单独提一档 ring：A 的 focus 色就是 `--brand-strong`，
      // 它已经是深墨字下对比最高的一档（再加深会同色于前景字）。
      LfColors.mintText(Brightness.light),
    );
    expect(
      AppTheme.dark().inputDecorationTheme.focusedBorder?.borderSide.color,
      LfColors.mintText(Brightness.dark),
    );
  });

  // 【测试退役】「暗色：决策卡走查」随 R4 整族退役删除（`docs/56` R4 /
  // `docs/58` §5 台账）：断言的**对象**（记录页入口 + 决策卡 + 证据徽标）
  // 已被产品删除。暗色可读性由同文件其余暗色用例与 `token_contrast_test`
  // 继续覆盖；入口不存在的反向断言在
  // `test/features/nutrition/record_tab_no_next_meal_entry_test.dart`。

  testWidgets('窄屏 320dp + 大字号 2.0×：饮食页不溢出', (tester) async {
    useViewport(tester, textScale: 2.0);
    await runAudit(tester, () async {
      await pumpNutrition(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('窄屏 320dp + 大字号 2.0×：AI 工作台任务卡不溢出', (tester) async {
    useViewport(tester, textScale: 2.0);
    await runAudit(tester, () async {
      await pumpWorkbenchGallery(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  testWidgets('减弱动画：count-up 直显新值（docs/21 §2.9 退化规则）', (tester) async {
    useViewport(tester, size: const Size(400, 900), reducedMotion: true);
    String format(double value) => '${value.round()} kcal';
    Widget host(double value) => MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: CountUpText(value: value, format: format),
          ),
        ),
      ),
    );
    await tester.pumpWidget(host(100));
    expect(find.text('100 kcal'), findsOneWidget);
    await tester.pumpWidget(host(210));
    // 退化直显：不跑 800ms 滚动，立即就是新值。
    expect(find.text('210 kcal'), findsOneWidget);
  });

  testWidgets('减弱动画：庆祝爆发不渲染（直接结束，guard 已消费）', (tester) async {
    useViewport(tester, size: const Size(400, 900), reducedMotion: true);
    AppCelebrationGuard.resetForTest();
    addTearDown(AppCelebrationGuard.resetForTest);
    BuildContext? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const Scaffold(body: Center(child: Text('触发')));
          },
        ),
      ),
    );
    final fired = showAppCelebration(captured!);
    await tester.pumpAndSettle();
    expect(fired, isTrue);
    expect(find.byKey(const Key('app-celebration-painter')), findsNothing);
  });

  testWidgets('TalkBack：关键确认有语义标签（不只看按钮文本）', (tester) async {
    useViewport(tester, size: const Size(400, 900));
    await pumpNutrition(tester);
    // 2026-10-22：「确认加入计划」按钮退场。换一条同类关键确认——
    // 记录页「记录一餐」FAB（`nutrition-record-fab`）必须带「记录一餐」语义。
    await tester.scrollUntilVisible(
      find.byKey(const Key('nutrition-record-fab')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // FAB 的语义由 Tooltip(message: '记录一餐') 提供：断言 tooltip 存在
    // 且挂在 FAB 子树里（读屏读到的就是这个 message）。
    expect(
      find.descendant(
        of: find.byKey(const Key('nutrition-record-fab')),
        matching: find.byWidgetPredicate(
          (widget) => widget is Tooltip && widget.message == '记录一餐',
        ),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  // 【测试退役】`golden：NextMealDecisionCard xxl 重点卡基线` 随卡整族退役
  // 删除（`docs/56` R4 / `docs/58` §5 台账）。golden 图
  // `goldens/next_meal_decision_card_2_0.png` 保留在仓库（不删历史基线），
  // 但不再有断言引用它。
}

/// 巡检要打开的饮食页 tab（只覆盖 2.0 新增的「菜单」）。
enum NutritionTab {
  menu('菜单');

  const NutritionTab(this.chipLabel);

  final String chipLabel;
}
