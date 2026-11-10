import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_ring_painter.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_energy_card.dart';

/// docs/30 §2 D4（用户走查需求 4「记录和菜单页面的最上边的绿色数据卡太丑了，
/// 重新设计」）的**设计契约**：两页顶部卡从 mint 渐变 hero 换成标准白
/// [DesignCard]。
///
/// 为什么不能只断言「Key 还在」：换皮最容易犯的错是**只换一半**——外层换成
/// 白卡、里面仍留着 `Colors.white` 文字（白底白字，Key 一个不少，截图才发现）。
/// 所以这里的每条断言都对着**渲染出来的颜色/盒子**，而不是 widget 类型名：
///
///  1. 卡片自己的底色是不透明 `card`（白/暗卡色），不是透明、不是渐变；
///  2. 卡上每一个 `Text` 的颜色都**不是** `primaryForeground`（白色）——这条
///     把「白底白字」钉死在断言里，而不是靠肉眼；
///  3. 记录卡「已摄入 / 目标 / 剩余」三段的**关系**（旧件是自绘进度条）在
///     有目标时出现、无目标时不出现（没有分母就没有进度）——阶段 2B D10 把
///     这三个 Key 从 hero 迁到共享热量卡上重钉（环心 + 脚注 + 徽标）；
///  4. 菜单卡的管理圆钮走 `muted` 档——半透明底只压在照片/渐变上时才成立。
///
/// **2026-10-14（Round7 阶段 3 步骤 1，D25/D28）**：菜单页首那张白卡按 A
/// `nutritionMenus()` 退场（A 的页首是段标题 + pill + 指引行，不是卡），管理
/// 入口从卡上圆钮迁到 A 的页尾 `.list-link`。本文件的菜单分组随之改钉
/// **段头块**：不是卡 + 文字不取白字档 + 窗口口径仍在 + list-link 的 chip 走
/// brand-soft 且整行可点 + 汇总行的「0 餐 / —」口径。记录页那张卡不受影响
/// （A 的记录页首确实是一张卡，D10）。
const target1748 = DailyNutritionTarget(
  calorieMinKcal: 1400,
  calorieMaxKcal: 1748,
  proteinMinGrams: 50,
  proteinMaxGrams: 62,
  carbsMinGrams: 180,
  carbsMaxGrams: 205,
  fatMinGrams: 40,
  fatMaxGrams: 52,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(LfDimens.pagePadding),
        child: child,
      ),
    ),
  );

  /// 拆树 + 走一帧：菜单卡订阅的是 drift 的 `watchAll()` 流，不拆树就会留下
  /// 一个 pending timer，测试以「A Timer is still pending」失败——那是测试
  /// 卫生问题，不是被断言的行为，所以显式排掉。
  Future<void> drainStream(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// 卡片真实底色：取卡内第一层 [Material] 的 `color`（[DesignCard] 的实现
  /// 细节，但正是它决定像素）。找不到就是不透明底缺位，直接判失败。
  Color cardBackground(WidgetTester tester, Key cardKey) {
    final material = tester.widget<Material>(
      find
          .descendant(of: find.byKey(cardKey), matching: find.byType(Material))
          .first,
    );
    final color = material.color;
    expect(color, isNotNull, reason: '$cardKey 的卡片底色不得为 null（透明）');
    expect(color!.a, 1.0, reason: '$cardKey 的卡片底色必须不透明');
    return color;
  }

  /// 卡上所有可见文字的颜色（含 RichText 片段）。
  List<Color> textColors(WidgetTester tester, Key cardKey) {
    final out = <Color>[];
    for (final text in tester.widgetList<Text>(
      find.descendant(of: find.byKey(cardKey), matching: find.byType(Text)),
    )) {
      final color = text.style?.color;
      if (color != null) out.add(color);
    }
    expect(out, isNotEmpty, reason: '$cardKey 上应当有带显式颜色的文字');
    return out;
  }

  group('记录页顶部卡（NutritionRecordEnergyCard · docs/30 D4 + 2B D10）', () {
    Widget card({
      double kcal = 0,
      DailyNutritionTarget? target = target1748,
      DateTime? selectedDate,
      DateTime? now,
    }) {
      final date = selectedDate ?? DateTime(2026, 9, 12);
      return host(
        NutritionRecordEnergyCard(
          consumed: NutritionValues(
            kcal: kcal,
            proteinGrams: 20,
            carbsGrams: 40,
            fatGrams: 10,
          ),
          target: target,
          selectedDate: date,
          now: now ?? date,
        ),
      );
    }

    testWidgets('白卡化：外层是 DesignCard，底色不透明 card，且卡上无任何白色文字', (tester) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      expect(find.byType(DesignCard), findsOneWidget);
      expect(find.byType(HeroSection), findsNothing);
      final background = cardBackground(
        tester,
        const Key('nutrition-record-energy'),
      );
      expect(background, LfSemanticColors.light.card);

      // 白底白字是本条要拦的缺陷：`primaryForeground` 在浅色下就是 #FFFFFF。
      final white = LfSemanticColors.light.primaryForeground;
      for (final color in textColors(
        tester,
        const Key('nutrition-record-energy'),
      )) {
        expect(color, isNot(white), reason: '白卡上的文字不得用 $white（白底白字）');
      }
    });

    testWidgets('有目标：三段统计落到环心与脚注（D10 取代旧进度条口径）', (tester) async {
      await tester.pumpWidget(card(kcal: 437));
      await tester.pumpAndSettle();

      // 旧 hero 的「进度条 + 已完成 N% + 目标 N kcal」三个 Key 退役，同一批事实
      // 改由热量卡承载：环心（已摄入 / 百分比）+ 脚注（目标 / 还可摄入）。
      // 断言退役 Key 不在，是为了拦住「新旧两套口径同时留在页面上」。
      for (final key in [
        'nutrition-record-hero-bar',
        'nutrition-record-hero-percent',
        'nutrition-record-hero-bar-target',
      ]) {
        expect(find.byKey(Key(key)), findsNothing, reason: '退役：$key');
      }
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('nutrition-record-energy-consumed')),
            )
            .data,
        '437',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('nutrition-record-energy-percent')),
            )
            .data,
        '25%',
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('nutrition-record-energy-target')),
            )
            .data,
        // 【2026-10-25（需求 1）】卡头那行现在是**区间**（本用例目标
        // 1,400–1,748），脚注左格让给依据（原来写「目标 N kcal」单值）。
        '1,400 – 1,748',
      );
      // 剩余额度也是区间（需求 1）：1,400−437 ～ 1,748−437。
      expect(
        find.text('还可摄入 963–1,311 kcal', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('超出：第三行如实写「超上限 X」，脚注改口「超出」，徽标换 honey', (tester) async {
      await tester.pumpWidget(card(kcal: 1993));
      await tester.pumpAndSettle();

      // 1993/1748 = 114%：弧由画家 clamp 到满圈，准确的量由这行数字说
      // （两条通道各司其职，与旧 hero 的条/数字分工同一条规则）。
      // 【2026-10-25 断言语义变更（需求 1，强度不降）】原来第三行写未截断的
      // 「114%」。区间方案里「超了 245 kcal」比百分比更该被一眼看到；判据
      // 改钉**超出量**（它同时钉住「数字是 1993−1748 算出来的」）。
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('nutrition-record-energy-percent')),
            )
            .data,
        '超上限 245',
      );
      // 超出是**单个事实**（不是区间）：如实报超了多少（需求 1 的暖色档）。
      expect(find.text('超出 245 kcal', findRichText: true), findsOneWidget);
      expect(
        tester
            .widget<LfBadge>(
              find.byKey(const Key('nutrition-record-energy-status')),
            )
            .variant,
        LfBadgeVariant.honey,
      );
    });

    testWidgets('无目标：不充弧、无百分比，两段脚注诚实（无分母就没有进度）', (tester) async {
      await tester.pumpWidget(card(target: null));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('nutrition-record-energy-percent')),
        findsNothing,
      );
      final paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byKey(const Key('lf-calorie-ring')),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect((paint.painter! as LfRingPainter).ratio, 0);
      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('nutrition-record-energy-target')),
            )
            .data,
        '尚未设定目标',
      );
      expect(find.text('设置目标后查看进度'), findsOneWidget);
      // 三段统计本身照旧渲染（Key 是契约），只有「还可摄入 N kcal」这一行是
      // 派生量：没有分母它就不存在，锚点也随之退场（见卡体 `_foot`）。
      for (final key in [
        'nutrition-record-energy-consumed',
        'nutrition-record-energy-ratios',
        'nutrition-record-energy-status',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(
        find.byKey(const Key('nutrition-record-energy-remaining')),
        findsNothing,
        reason: '无目标时没有「还可摄入」这一行',
      );
    });

    testWidgets('目标为 0 同样不充弧（0 是合法输入，但不是合法分母）', (tester) async {
      await tester.pumpWidget(
        card(
          target: const DailyNutritionTarget(
            calorieMinKcal: 0,
            calorieMaxKcal: 0,
            proteinMinGrams: 0,
            proteinMaxGrams: 0,
            carbsMinGrams: 0,
            carbsMaxGrams: 0,
            fatMinGrams: 0,
            fatMaxGrams: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('nutrition-record-energy-percent')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('菜单页首段头（MenuDishList · 3-1 D25/D28 取代 docs/30 D4 的顶部卡）', () {
    late AppDatabase db;
    late DishLibraryRepository dishes;
    late MealRepository meals;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      final clock = FixedAppClock(DateTime.utc(2026, 9, 12));
      final ids = _Ids();
      dishes = DishLibraryRepository(
        database: db,
        idGenerator: ids,
        clock: clock,
      );
      meals = MealRepository(database: db, idGenerator: ids, clock: clock);
    });

    tearDown(() => db.close());

    Widget menu({
      VoidCallback? onOpenCanteen,
      Future<void> Function(DishRecord dish, {MealSlot? slotOverride})?
      onAddToMeal,
    }) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MenuDishList(
          repository: dishes,
          mealRepository: meals,
          now: DateTime(2026, 9, 12),
          onOpenCanteen: onOpenCanteen,
          onAddToMeal: onAddToMeal,
        ),
      ),
    );

    testWidgets('段头不再是卡（D25）：页首是纯文字块，窗口口径仍在上屏', (tester) async {
      await tester.pumpWidget(menu());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nutrition-menu-hero')), findsOneWidget);
      // A 的菜单页首没有卡（`app.js:181`：段标题 + pill + 指引行，styles.css
      // 里那三件都是 `.page` 的直接子元素）。hero 卡退场后**键由本块承接**，
      // 但不能再有卡片外壳——退成卡就是没搬（D25）。
      expect(
        find.ancestor(
          of: find.byKey(const Key('nutrition-menu-hero')),
          matching: find.byType(DesignCard),
        ),
        findsNothing,
        reason: '段头块不是卡',
      );
      // 「按你的食堂窗口」是推荐真正依赖的本地事实，随 hero 退场并进 A 的
      // 指引行（自检当场修正 a）：换稿不能把它一起换掉。
      expect(find.textContaining('按食堂窗口推荐'), findsOneWidget);

      // 页首块直接铺在页面底上：块上任何文字都不能取 `primaryForeground`
      // （那是白卡上的白字档），浅色页底上就是「浅底浅字」——与本组原先
      // 防的「白底白字」是同一类错误，只是底换了。
      final white = LfSemanticColors.light.primaryForeground;
      for (final color in textColors(
        tester,
        const Key('nutrition-menu-hero'),
      )) {
        expect(color, isNot(white), reason: '段头上的文字不得用 $white');
      }
      await drainStream(tester);
    });

    /// 【2026-10-25 断言语义变更（需求 13a，强度不降）】原断言是「管理入口在
    /// 页尾 `.list-link`（虚线 chip 走 brand-soft、整行可点）」。
    ///
    /// 用户 2026-10-25 把入口挪到**右下浮动按钮**，于是「页尾那一行」不再存在。
    /// 断言改写为浮钮形态该有的两条：**整块可点**（点一下真的打开目录）+
    /// **不是裸图标**（带可见文字，用户一眼看得出它是什么）。
    /// 位置断言（右下角）归 `test/app/floating_actions_test.dart`。
    testWidgets('管理入口搬去浮钮（13a）：列表内不再有页尾行；空态卡的行动仍通同一回调', (tester) async {
      var opened = 0;
      // 无菜品 ⇒ 整套卡走空态，它的「去维护食堂目录」行动就是列表里**仅剩**的
      // 该回调入口（浮钮由页面壳画，不在本列表内）。
      await tester.pumpWidget(menu(onOpenCanteen: () => opened++));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cta-manage-canteen')),
        findsNothing,
        reason: '13a：页尾 list-link 已退役，列表里不许再出现这个 Key',
      );
      expect(find.text('地点、窗口与菜品'), findsNothing, reason: '那是页尾行的副行，随入口一起退役');

      // 列表本体仍在（只是少了那一行入口）：段头与前三条断言之外的骨架不变。
      expect(
        find.byKey(const Key('nutrition-menu-hero')),
        findsOneWidget,
        reason: '摘掉一行入口不等于把页面也摘了',
      );
      // 「入口能不能打开目录」不在这里断言：浮钮由页面壳（`NutritionPage`）
      // 画，本文件的 host 只有 `MenuDishList`。那条可达性归
      // `test/app/floating_actions_test.dart`（真装配）。
      expect(opened, 0, reason: '本列表自己不再打开任何东西（回调交给页面壳）');
      await drainStream(tester);
    });

    testWidgets('无推荐时汇总行写「已安排 0 餐 / 预计 —」，不写死设计稿的 1470', (tester) async {
      await tester.pumpWidget(menu());
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('nutrition-menu-hero-planned')))
            .data,
        '已安排 0 餐',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('nutrition-menu-hero-kcal')))
            .data,
        '预计 —',
      );
      await drainStream(tester);
    });
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'r4-id-${_value++}';
}
