import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';

/// `RV4-P2-11`（`docs/57` §3 / `docs/56` R8）：**食物库卡片直接显示品牌**。
///
/// 现状：2026-10-08 的「单行三件」改造把品牌行整条删掉（品牌退到详情弹层），
/// 但 `brand` 参数保留未用。列表里「米饭 × 4」（无品牌 / 叮咚 / 松屋 /
/// 千丰香米）长得几乎一样 ⇒ 只能点进去才分辨。
///
/// 修法（`docs/56` R8）：名称行改「主名 + ` · 品牌`」**内联**，同一行、
/// 不加行高（行高 56 由 40 图标 + 上下 8 决定）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );

  group('P2-11 ·  FoodCard 内联品牌', () {
    testWidgets('同名不同品牌两行渲染出不同品牌文本', (tester) async {
      await tester.pumpWidget(
        host(
          Column(
            children: [
              FoodCard(
                key: const Key('card-a'),
                id: 'a',
                name: '米饭',
                brand: '千丰香米',
                category: FoodCategory.staple,
                kcalPer100g: 338,
              ),
              FoodCard(
                key: const Key('card-b'),
                id: 'b',
                name: '米饭',
                brand: '叮咚',
                category: FoodCategory.staple,
                kcalPer100g: 156,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('food-card-brand-a')),
        findsOneWidget,
        reason: '品牌必须在卡面上（R8）',
      );
      expect(find.textContaining('千丰香米'), findsOneWidget);
      expect(find.textContaining('叮咚'), findsOneWidget);
    });

    testWidgets('品牌内联在同一行：行高不变（56 ± 0.5）', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 360,
            child: FoodCard(
              key: const Key('card-h'),
              id: 'h',
              name: '米饭',
              brand: '千丰香米',
              category: FoodCategory.staple,
              kcalPer100g: 338,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final withBrand = tester.getSize(find.byKey(const Key('card-h'))).height;

      await tester.pumpWidget(
        host(
          SizedBox(
            width: 360,
            child: FoodCard(
              key: const Key('card-n'),
              id: 'n',
              name: '米饭',
              category: FoodCategory.staple,
              kcalPer100g: 116,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final withoutBrand = tester
          .getSize(find.byKey(const Key('card-n')))
          .height;

      expect(
        withBrand,
        closeTo(withoutBrand, 0.5),
        reason: '品牌是内联补充，不得把行撑高（有品牌 $withBrand / 无 $withoutBrand）',
      );
    });

    testWidgets('品牌从名称里拆出来时也显示（词表内的品牌前缀）', (tester) async {
      // 用词表里真有的品牌前缀（`7-ELEVEN` 在 `kFoodBrandTokensAll` 中）。
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 360,
            child: FoodCard(
              key: const Key('card-split'),
              id: 's',
              name: '7-ELEVEN 御饭团',
              category: FoodCategory.staple,
              kcalPer100g: 200,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 名称拆出的品牌与数据列同样显示；落点是 `food-card-brand-<id>`。
      expect(find.byKey(const Key('food-card-brand-s')), findsOneWidget);
    });

    testWidgets('2.0× 字号下不溢出', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FoodCard(
              key: const Key('card-scale'),
              id: 'sc',
              name: '超长的食物名称需要省略',
              brand: '一个很长很长的品牌名字',
              category: FoodCategory.staple,
              kcalPer100g: 338,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('语义 label 含品牌（读屏能区分同名）', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 360,
            child: FoodCard(
              key: const Key('card-sem'),
              id: 'sem',
              name: '米饭',
              brand: '千丰香米',
              category: FoodCategory.staple,
              kcalPer100g: 338,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 语义 label 落在卡片内的语义节点上（`container: true`，不是根节点）。
      expect(
        find.bySemanticsLabel(RegExp('千丰香米')),
        findsOneWidget,
        reason: '读屏必须能读到品牌（否则同名食物分不清）',
      );
      handle.dispose();
    });
  });
}
