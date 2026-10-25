import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_food_kcal_ring.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_editor_dialog.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_category_icon.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_search_tab.dart';

import '../../support/food_fixture.dart';

/// 2026-10-03 用户走查两项重设计的**设计契约**（不只是「Key 还在」）：
///
///  1. 「食物库的界面也很丑，食物卡片的表现形式不直观」→ 食物卡必须把热量
///     做成主指标、宏量做成彩点、来源降为徽标；
///  2. 「食物添加界面的弹窗卡片太丑了」→ 「记录一餐」弹层的餐次/搜索框/
///     已添加项/合计四处必须是主题内的语言，且改克数要能看到营养跟着变。
///
/// 每条断言都对应一个**可被单独改回旧实现的点**（热量降级成小字、彩点换成
/// 单色、餐次换回 Dropdown、搜索框换回 M3 `SearchBar`、已添加项不显示
/// 换算后营养），所以它们是隔离变异下会变红的断言，而不是「组件存在」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(width: 360, child: child),
      ),
    ),
  );

  group('食物行（FoodCard，A `.food-row`）', () {
    Widget card({
      String name = '米饭',
      double? kcal = 116,
      double? protein = 2.6,
      double? carbs = 25.9,
      double? fat = 0.3,
      String? brand,
      bool isUserCreated = false,
      bool canJoinPlan = true,
    }) => host(
      FoodCard(
        id: 'seed-fc-1',
        name: name,
        category: FoodCategory.classify(name: name),
        brand: brand,
        isUserCreated: isUserCreated,
        kcalPer100g: kcal,
        proteinPer100g: protein,
        carbsPer100g: carbs,
        fatPer100g: fat,
        canJoinPlan: canJoinPlan,
      ),
    );

    /// 卡内所有 6dp 圆形彩点（宏量指示）。单行化后卡上**一枚都不该有**——
    /// 宏量退到详情弹层（那里的彩点颜色/顺序由 `food_detail_sheet_test.dart` 钉）。
    List<Color?> dotColors(WidgetTester tester) => tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(FoodCard),
            matching: find.byType(Container),
          ),
        )
        .where(
          (c) => (c.decoration as BoxDecoration?)?.shape == BoxShape.circle,
        )
        .map((c) => (c.decoration! as BoxDecoration).color)
        .toList();

    testWidgets('单行三件：图标 + 名称 + 36dp 环，三件共一条水平中线', (tester) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      final icon = tester.getRect(find.byType(FoodCategoryIcon));
      final name = tester.getRect(
        find.byKey(const Key('food-card-name-seed-fc-1')),
      );
      final ring = tester.getRect(find.byType(LfFoodKcalRing));
      // 需求 1「都在一行」：三件的纵向区间互相重叠（任何一件掉到下一行都会
      // 让重叠失败），且沿同一条中线。
      expect(icon.center.dy, closeTo(ring.center.dy, 0.5), reason: '图标心=环心');
      expect(name.center.dy, closeTo(ring.center.dy, 0.5), reason: '名称心=环心');
      // 顺序：图标 → 名称 → 环（环在最右，扫一列卡时图形竖向对齐可比）。
      expect(icon.right, lessThanOrEqualTo(name.left));
      expect(name.right, lessThanOrEqualTo(ring.left));
    });

    testWidgets('环收到 36dp 小档（需求 1「再小一点的热量圆环」）', (tester) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      final ring = tester.widget<LfFoodKcalRing>(find.byType(LfFoodKcalRing));
      expect(ring.size, LfDimens.foodKcalRingSmallSize);
      expect(ring.stroke, LfDimens.foodKcalRingSmallStroke);
      expect(
        LfDimens.foodKcalRingSmallSize,
        lessThan(LfDimens.foodKcalRingSize),
        reason: '小档必须真的比原 44dp 卡档小，否则「再小一点」没落实',
      );
      // 环里的数字还在（图形化热量，N13）：116/1000 ⇒ 环里写 116。
      expect(
        find.byKey(const Key('food-card-ring-seed-fc-1-kcal')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(LfFoodKcalRing),
          matching: find.text('116'),
        ),
        findsOneWidget,
      );
      // 旧形态（「116 kcal」一行文字）必须消失——否则就是两套热量表达并存。
      expect(find.text('116 kcal'), findsNothing);
    });

    testWidgets('行高由图标 40dp 决定：环不再顶高行（36 < 40）', (tester) async {
      // 需求 1「卡片缩短上下宽度」的可判定形式：行高 = max(图标 40, 环 36,
      // 名称行高) + 上下内边距 8×2。环比图标大时行高会被环顶到 44+ ⇒ 这一条
      // 就是「环必须比图标小」的理由，改回 44 会在这里红。
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      final rowRect = tester.getRect(find.byType(FoodCard));
      final iconRect = tester.getRect(find.byType(FoodCategoryIcon));
      expect(
        rowRect.height,
        closeTo(iconRect.height + LfDimens.spaceSmall * 2, 0.5),
        reason: '行高 = 图标 40 + 上下各 8；行高由最高的那一件决定',
      );
      expect(
        tester.getRect(find.byType(LfFoodKcalRing)).height,
        lessThan(iconRect.height),
        reason: '环必须比图标矮，否则行高改由环决定（44 档就会这样）',
      );
    });

    testWidgets('环的口径不再逐卡重复：卡上没有 kcal/100g（退到列表头一句）', (tester) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      // 单行卡里没有第二行可以放口径行；`FoodDensityScaleNote` 由列表头渲染
      // （`food_library_view` / `food_search_tab`），不在卡内。
      expect(find.text('kcal/100g'), findsNothing);
      expect(find.text('每 100g'), findsNothing);
      expect(find.byType(FoodDensityScaleNote), findsNothing);
      expect(find.text('无热量数据'), findsNothing);
      // 环的语义仍把口径说全（读屏不依赖视觉那一行）。
      expect(
        tester.getSemantics(find.byType(LfFoodKcalRing)).label,
        '每 100 克 116 千卡，约为能量密度满刻度的 12%',
        reason: '刻度是能量密度 0–1000（常量单源），不是「相对每日目标」',
      );
    });

    testWidgets('行内衬上下同 8、左右为 0（A `.food-row{padding:8px 0}`，左右 12 由列表卡给）', (
      tester,
    ) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      // Round7 阶段 3（D36）：行不再是自己的卡，横向内衬交给列表卡
      // （A `.food-list{padding:0 12px}`），行自己只留上下 8。
      final padding = tester
          .widget<Padding>(
            find
                .descendant(
                  of: find.byType(FoodCard),
                  matching: find.byType(Padding),
                )
                .first,
          )
          .padding;
      expect(
        padding,
        const EdgeInsets.symmetric(vertical: LfDimens.spaceSmall),
      );

      // 几何复核（不靠常量名猜）：行高 = 最高的那一件（图标 40）⇒ 图标顶边距
      // 行顶就是内边距 8；环比图标矮，居中后自己再多 (40−36)/2 = 2dp。
      final rowRect = tester.getRect(find.byType(FoodCard));
      final iconRect = tester.getRect(find.byType(FoodCategoryIcon));
      expect(iconRect.top - rowRect.top, closeTo(8, 0.5));
      expect(rowRect.bottom - iconRect.bottom, closeTo(8, 0.5));
      final ringRect = tester.getRect(find.byType(LfFoodKcalRing));
      expect(ringRect.top - rowRect.top, closeTo(10, 0.5));
    });

    testWidgets('行内三段间距：图标→名称 10、名称→警告 6、名称区→环 14', (tester) async {
      // A 的 `.food-row{gap:10px}` 是行内统一段距；名称区里 `.food-main{gap:6px}`
      // 复用它自己那一档；环前面另有 `.food-density{margin-left:4px}`（10+4=14）。
      await tester.pumpWidget(card(canJoinPlan: false));
      await tester.pumpAndSettle();

      final nameAreaFinder = find.byType(Expanded);
      expect(nameAreaFinder, findsOneWidget, reason: '行里只有名称区一枚 Expanded');
      final nameArea = tester.getRect(nameAreaFinder);
      final icon = tester.getRect(find.byType(FoodCategoryIcon));
      final name = tester.getRect(
        find.byKey(const Key('food-card-name-seed-fc-1')),
      );
      final warning = tester.getRect(
        find.byKey(const Key('food-card-incomplete-seed-fc-1')),
      );
      final ring = tester.getRect(find.byType(LfFoodKcalRing));

      expect(
        nameArea.left - icon.right,
        closeTo(LfDimens.spaceSmallPlus, 0.5),
        reason: '图标→名称 10（A `.food-row{gap:10px}`）',
      );
      expect(name.left, closeTo(nameArea.left, 0.5), reason: '名称区从段距之后起');
      expect(
        warning.left - name.right,
        closeTo(LfDimens.spaceTiny, 0.5),
        reason: '名称→警告 6（A `.food-main{gap:6px}`）',
      );
      expect(
        ring.left - nameArea.right,
        closeTo(LfDimens.spaceSmallPlus + LfDimens.spaceXSmall, 0.5),
        reason: '名称区→环 14（A `gap:10px` + `.food-density{margin-left:4px}`）',
      );
    });

    testWidgets(
      '分类图标块 40×40 R12 `--bg` 底，图形充满整块（A `.food-symbol` + polish 覆盖）',
      (tester) async {
        await tester.pumpWidget(card());
        await tester.pumpAndSettle();

        expect(
          tester.getSize(find.byType(FoodCategoryIcon)),
          const Size.square(LfDimens.foodCardIconSize),
        );
        final chip =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: find.byType(FoodCategoryIcon),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(
          chip.color,
          LfSemanticColors.light.background,
          reason: 'A polish 把 `.food-symbol` 的底从 brand-soft 改成 `--bg`',
        );
        expect(chip.borderRadius, BorderRadius.circular(LfDimens.radiusMd));
        expect(
          tester.getSize(find.byType(SvgPicture)),
          const Size.square(LfDimens.foodCardIconSize),
          reason: 'A 的 `img{width:40px;height:40px}`：图形充满整块，不再内衬 10',
        );
      },
    );

    testWidgets('环心数字 10px（A `.food-density .data-ring-center b`）', (
      tester,
    ) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      final value = tester.widget<Text>(
        find.byKey(const Key('food-card-ring-seed-fc-1-kcal')),
      );
      expect(value.style?.fontSize, 10);
      expect(
        value.style?.fontWeight,
        FontWeight.w600,
        reason: 'A 写 650，本仓字重表只有 400/500/600/700 四档，取最近的 600',
      );
    });

    testWidgets('行不是卡：自己不套卡面（卡面由列表给）', (tester) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      expect(
        find.byType(DesignCard),
        findsNothing,
        reason: 'A 的行住在 `.card.food-list` 里，行自己不带卡面（否则是卡中卡）',
      );
    });

    testWidgets('名称清洗在卡内做，卡上只留产品名（N11 的清洗规则，落点改到单行卡）', (tester) async {
      await tester.pumpWidget(card(name: '7-ELEVEN 7-11御饭团'));
      await tester.pumpAndSettle();

      // 名称里只剩产品名（`-` 仍按 `normalizeFoodName` 的既有规则换成空格）。
      final name = find.text('7 11御饭团');
      expect(name, findsOneWidget);
      // 【语义变更】`RV4-P2-11`（`docs/56` R8）之后**品牌重新上卡面**（内联
      // 在名称右边、不追加行高）。原来这里断言「卡上不再出现品牌」——那正是
      // 本批要改掉的行为（同名食物在列表里分不清）。
      // 判据变成「名称里**不再带**品牌前缀，品牌单独出现在品牌位」。
      expect(
        find.byKey(const Key('food-card-brand-seed-fc-1')),
        findsOneWidget,
        reason: '品牌以独立文本出现在卡面（R8）',
      );
    });

    testWidgets('括号式名字同样在卡内清洗', (tester) async {
      await tester.pumpWidget(card(name: '(Beretta) Prosciutto Cotto火腿片'));
      await tester.pumpAndSettle();

      expect(find.text('Prosciutto Cotto火腿片'), findsOneWidget);
      expect(find.text('Beretta'), findsNothing, reason: '品牌前缀已拆掉');
    });

    testWidgets('数据层的品牌列现在进卡面（内联，不追加行高）——`RV4-P2-11`', (tester) async {
      await tester.pumpWidget(card(name: '7-ELEVEN 7-11御饭团', brand: '统一'));
      await tester.pumpAndSettle();

      // 【语义变更】R8 要的就是「品牌上卡面」：`brand` 列优先于名称里拆出的
      // 品牌，所以这里显示「统一」（而不是 `7-ELEVEN`）。
      expect(find.textContaining('统一'), findsOneWidget);
      // 名称仍只有产品名（前缀照旧被拆掉）。
      expect(find.text('7 11御饭团'), findsOneWidget);
    });

    testWidgets('自建 / 内置徽标不进卡面（退到详情弹层），卡上无任何 LfBadge', (tester) async {
      await tester.pumpWidget(card(isUserCreated: true));
      await tester.pumpAndSettle();
      expect(find.byType(LfBadge), findsNothing);
      expect(find.text('自建'), findsNothing);

      await tester.pumpWidget(card());
      await tester.pumpAndSettle();
      expect(find.byType(LfBadge), findsNothing);
      expect(find.text('内置'), findsNothing);
    });

    testWidgets('营养不完整：名称后内联 16dp 警告图标 + 语义标签（不是只靠颜色）', (tester) async {
      await tester.pumpWidget(card(canJoinPlan: false));
      await tester.pumpAndSettle();

      // 整行文字退场后，「能搜到不等于能进计划」这件事改由图标 + 语义承担
      // （docs/07 §9.3）。图标必须真的在，且语义标签把理由说全。
      final icon = find.byKey(const Key('food-card-incomplete-seed-fc-1'));
      expect(icon, findsOneWidget);
      expect(tester.widget<Icon>(icon).size, LfDimens.iconSm);
      expect(
        tester.widget<Icon>(icon).icon,
        Icons.info_outline,
        reason: '形状随 A（`.food-warning` 用 info 图标，原来是 error_outline）',
      );
      // 语义标签必须真的能被读屏念出来：它所在的节点是**合并后**的节点（图标
      // 的分类名与产品名都在同一个节点里），所以用 `contains` 判「这句话在不在
      // 读屏会播报的那串里」，而不是判节点标签恰好等于它。
      expect(tester.getSemantics(icon).label, contains('营养不完整，不可加入计划'));
      // 声明处也钉一遍：`Semantics` 那件组件自己的 label 就是这句话（防止将来
      // 把 label 挪到别处、靠合并节点里的巧合字符串继续绿）。
      expect(
        tester
            .widget<Semantics>(
              find.ancestor(of: icon, matching: find.byType(Semantics)).first,
            )
            .properties
            .label,
        '营养不完整，不可加入计划',
      );
      // 紧贴名称之后（不是贴右边缘与环挤在一起）。
      final nameRect = tester.getRect(
        find.byKey(const Key('food-card-name-seed-fc-1')),
      );
      final iconRect = tester.getRect(icon);
      expect(iconRect.left, greaterThanOrEqualTo(nameRect.right));
      expect(
        iconRect.right,
        lessThan(tester.getRect(find.byType(LfFoodKcalRing)).left),
        reason: '警告图标在名称与环之间，不占用环的位置',
      );
      // 不加卡高：仍是单行卡（行高由图标 40 决定）。
      final cardRect = tester.getRect(find.byType(FoodCard));
      final catIcon = tester.getRect(find.byType(FoodCategoryIcon));
      expect(
        cardRect.height,
        closeTo(catIcon.height + LfDimens.spaceSmall * 2, 0.5),
        reason: '警告图标不占独立行、不加卡高（原型仍是单行）',
      );
    });

    testWidgets('有营养数据时卡上不出现警告图标（不误报）', (tester) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('food-card-incomplete-seed-fc-1')),
        findsNothing,
      );
    });

    testWidgets('单行化后宏量与品牌都不在卡上：一枚彩点都没有', (tester) async {
      await tester.pumpWidget(card());
      await tester.pumpAndSettle();

      expect(dotColors(tester), isEmpty);
      expect(find.byType(MacroDotLine), findsNothing);
      expect(find.byType(MacroDotRows), findsNothing);
      expect(find.textContaining('蛋白质'), findsNothing);
      expect(find.textContaining('碳水'), findsNothing);
      expect(find.textContaining('脂肪'), findsNothing);
    });
  });

  group('两条数据路径共用同一张食物卡', () {
    late AppDatabase database;
    late FoodRepository repository;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await seedFoodFixture(database);
      repository = FoodRepository(
        database: database,
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
      );
    });

    tearDown(() => database.close());

    testWidgets('仓库直搜（无目录 controller）也渲染 FoodCard，不再是 ListTile', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        host(
          FoodSearchTab(
            repository: repository,
            query: '米饭',
            revision: 0,
            onQueryChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FoodCard), findsWidgets);
      expect(find.byType(ListTile), findsNothing);
    });
  });

  group('「记录一餐」弹层', () {
    late AppDatabase database;
    late FoodRepository repository;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await seedFoodFixture(database);
      repository = FoodRepository(
        database: database,
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
      );
    });

    tearDown(() => database.close());

    Future<void> pumpEditor(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          MealEditorDialog(foodRepository: repository, localDate: '2026-09-09'),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// 搜「米饭」并把第一个结果加进来（结果行的名称与搜索框文本同名，
    /// 取 `.last` 即列表里的那一行）。
    Future<void> addRice(WidgetTester tester) async {
      await tester.enterText(find.byKey(const Key('meal-food-search')), '米饭');
      await tester.pumpAndSettle();
      await tester.tap(find.text('米饭').last);
      await tester.pumpAndSettle();
    }

    /// 克数输入框。**不按 `meal-grams-item-N` 定位**：条目 id 来自
    /// `_EditableItem` 的静态计数器，同一个测试文件里前面的用例加过食物后
    /// 就不是 item-1 了。弹层里每个条目恰好一个 `TextFormField`（搜索框与
    /// 备注都是 `TextField`），所以按类型定位恰好唯一且与顺序无关。
    Finder gramsField() => find.byType(TextFormField);

    /// 某个文本所在胶囊的底色（`Material.color`）。
    Color pillColor(WidgetTester tester, String label) {
      final material = tester.widget<Material>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Material))
            .first,
      );
      return material.color!;
    }

    testWidgets('餐次是一排可点胶囊，不再是下拉菜单', (tester) async {
      await pumpEditor(tester);

      expect(
        find.byType(DropdownButtonFormField<MealSlot>),
        findsNothing,
        reason: '四个餐次是固定集合，用胶囊一眼看全并一键切换',
      );
      expect(find.byKey(const Key('meal-slot')), findsOneWidget);
      for (final slot in MealSlot.values) {
        expect(find.text(slot.label), findsOneWidget);
      }

      // 默认午餐选中：选中是 primary 实底，未选是 muted 底。
      expect(pillColor(tester, '午餐'), LfSemanticColors.light.primary);
      expect(pillColor(tester, '早餐'), LfSemanticColors.light.muted);

      await tester.tap(find.text('早餐'));
      await tester.pumpAndSettle();
      expect(pillColor(tester, '早餐'), LfSemanticColors.light.primary);
      expect(pillColor(tester, '午餐'), LfSemanticColors.light.muted);
    });

    testWidgets('搜索框是主题内的输入框，不再是 M3 SearchBar', (tester) async {
      await pumpEditor(tester);

      expect(
        find.byType(SearchBar),
        findsNothing,
        reason: '主题没有 searchBarTheme，M3 SearchBar 会落地成另一套外观',
      );
      expect(find.byKey(const Key('meal-food-search')), findsOneWidget);
      expect(find.text('搜索并添加食物'), findsOneWidget);
    });

    testWidgets('空查询的结果提示不占一大块空白（合计卡才不会被挤出可视区）', (tester) async {
      await pumpEditor(tester);

      expect(find.text('输入名称搜索本地食物'), findsOneWidget);
      final searchBottom = tester
          .getRect(find.byKey(const Key('meal-food-search')))
          .bottom;
      final addedTop = tester.getRect(find.text('已添加')).top;
      // 固定 168dp 结果区时这里约 190dp；零高度提示时约 52dp。
      expect(
        addedTop - searchBottom,
        lessThan(90),
        reason: '空查询时结果区不该预留列表高度，否则合计卡被切在滚动区之外',
      );
    });

    testWidgets('已添加项显示按当前克数换算的热量与宏量，改克数跟着变', (tester) async {
      await pumpEditor(tester);
      await addRice(tester);

      // 米饭 116 kcal/100g，默认份量 100g。
      expect(find.text('米饭'), findsOneWidget);
      expect(find.text('116 kcal'), findsNWidgets(2), reason: '条目卡 + 合计卡');
      expect(find.text('蛋白质 2.6g'), findsNWidgets(2));
      expect(find.text('按当前克数'), findsOneWidget);

      await tester.enterText(gramsField(), '200');
      await tester.pumpAndSettle();

      expect(find.text('232 kcal'), findsNWidgets(2));
      expect(find.text('蛋白质 5.2g'), findsNWidgets(2));
      expect(find.text('碳水 51.8g'), findsNWidgets(2));
      expect(find.text('116 kcal'), findsNothing);
    });

    testWidgets('合计卡是三色点 + kcal 大字，不是一行灰字', (tester) async {
      await pumpEditor(tester);

      expect(find.text('合计'), findsOneWidget);
      // 还没有食物时合计为 0，但卡片与彩点行已经在位（不是缺一块）。
      expect(find.byType(MacroDotLine), findsOneWidget);

      await addRice(tester);
      expect(find.byType(MacroDotLine), findsNWidgets(2), reason: '条目卡 + 合计卡');
    });

    testWidgets('改克数不得重建搜索 future（结果区不被打回加载态）', (tester) async {
      await pumpEditor(tester);
      await addRice(tester);

      // 换一个查询并等它出结果，此时结果区是一份已完成的 future。
      // 结果区只有 168dp 高（懒构建），断言用行内独有的热量口径文本而不是
      // 食物名——名称在搜索框里也有一份，且名单里排在后面的行不会被构建。
      await tester.enterText(find.byKey(const Key('meal-food-search')), '鸡蛋');
      await tester.pumpAndSettle();
      expect(find.text('139 kcal / 100g'), findsOneWidget);

      Future<List<FoodRecord>>? currentFuture() => tester
          .widget<FutureBuilder<List<FoodRecord>>>(
            find.byType(FutureBuilder<List<FoodRecord>>),
          )
          .future;
      final before = currentFuture();
      expect(before, isNotNull);

      // 改克数触发 setState：搜索 future 必须还是同一个对象，否则每敲一个
      // 数字都会新建 future、结果区闪一次加载态。
      await tester.enterText(gramsField(), '150');
      await tester.pump();
      expect(identical(currentFuture(), before), isTrue);
      expect(find.text('139 kcal / 100g'), findsOneWidget);
    });

    testWidgets('同名食物（不同品牌）在结果行里必须可区分', (tester) async {
      // RV2-P1-01：真实库 23,916 条里「米饭」有四条（116 / 156 / 181 / 338
      // kcal，分属无品牌 / 叮咚 / 松屋 / 千丰香米）。结果行只印名称 + 热量时
      // 四条长得几乎一样，用户点错就记错营养——把品牌印进结果行。
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'branded-rice',
              name: '米饭',
              brand: const Value('千丰香米'),
              kcalPer100g: 338,
              proteinPer100g: 7.4,
              carbsPer100g: 75.2,
              fatPer100g: 0.8,
              source: 'user',
              isUserCreated: const Value(true),
              createdAt: DateTime.utc(2026, 9, 9),
              updatedAt: DateTime.utc(2026, 9, 9),
            ),
          );
      await pumpEditor(tester);

      await tester.enterText(find.byKey(const Key('meal-food-search')), '米饭');
      await tester.pumpAndSettle();

      expect(
        find.textContaining('千丰香米'),
        findsWidgets,
        reason: '同名不同品牌的行必须把品牌印出来，否则点错就记错营养',
      );
      expect(
        find.bySemanticsLabel('添加 米饭（千丰香米）'),
        findsOneWidget,
        reason: '读屏也要能区分同名的两条',
      );
    });

    testWidgets('两条错误文案原样保留（内联在按钮上方）', (tester) async {
      await pumpEditor(tester);

      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();
      expect(find.text('请至少添加一种食物。'), findsOneWidget);

      await addRice(tester);
      await tester.enterText(gramsField(), '0');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();
      expect(find.text('食物克数必须是大于零的数值。'), findsOneWidget);
    });
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'design-id-${_value++}';
}
