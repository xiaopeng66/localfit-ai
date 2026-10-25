import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_food_kcal_ring.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_detail.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_category_icon.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_detail_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/new_food_dialog.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';

/// Round7 阶段 3 · 3-2d 的结构判据（A `app.js:369` `showFood()` 与
/// `app.js:375` `foodEditForm()`；设计决策 D46–D52）。
///
/// 这里钉的是 **A 的形态**：hero（52 R16 `--bg` 图标块 + 20 标题 + 12 muted
/// meta）、营养面板（r16 + 1px `--border` + `--bg` + 内衬 18 + 环列 56 + 间距 24）、
/// 环心 14（A 14 w700，仓内 600）、宏量行（点 7 / 标签 12 / 值 14 w600 右端）、
/// 口径注居中、行动行（1px `--track` 上边线 + 两钮 46 高 + 图标）与表单的
/// 2×2 数字网格 + 注。
///
/// **不重复钉**既有契约（对齐算式、封闭文案、加载/失败/消失三态、必填校验、
/// 保存失败不关窗、粘贴拆品牌）——那些在 `food_detail_sheet_test.dart` /
/// `new_food_dialog_test.dart` / `round5_food_detail_drag_test.dart` 里继续生效，
/// 本文件只加新事实。
void main() {
  const catalogItem = FoodLibraryItem(
    id: 'off:1001',
    name: '蒸米饭',
    source: 'catalog',
    state: 'verified',
    canJoinPlan: true,
    brand: '金龙鱼',
    category: 'staple',
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbsPer100g: 25.9,
    fatPer100g: 0.3,
  );

  const userCreated = FoodLibraryItem(
    id: 'user:1',
    name: '自制鸡肉沙拉',
    source: 'main',
    state: 'user_created',
    canJoinPlan: true,
    isUserCreated: true,
    brand: '自家',
    category: 'protein',
    kcalPer100g: 120,
    proteinPer100g: 12,
    carbsPer100g: 6,
    fatPer100g: 5,
  );

  FoodDetail detail(FoodLibraryItem item) => FoodDetail(
    foodId: item.id,
    name: item.name,
    state: item.state,
    source: 'openfoodfacts',
    licenseStatus: 'allowed',
    isUserCreated: item.isUserCreated,
    // 裁决 ①（2026-10-15）：详情与列表卡同一来源（夹具直接照抄行上的判据）。
    canJoinPlan: item.canJoinPlan,
    kcalPer100g: item.kcalPer100g ?? 0,
    proteinPer100g: item.proteinPer100g ?? 0,
    carbsPer100g: item.carbsPer100g ?? 0,
    fatPer100g: item.fatPer100g ?? 0,
  );

  Future<void> pumpSheet(
    WidgetTester tester, {
    FoodLibraryItem item = catalogItem,
    Future<void> Function()? onEdit,
    Future<void> Function()? onDelete,
    Size size = const Size(360, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodDetailSheet(
            item: item,
            load: () async => detail(item),
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  LfSemanticColors tokens(WidgetTester tester, Finder finder) =>
      tester.element(finder).lf;

  /// 宏量行的彩点（`_MacroDotItem` 的圆形 `Container`）。
  Finder dotFinder() => find
      .descendant(
        of: find.byType(MacroDotRows),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      )
      .first;

  group('详情 hero（D46：A `.food-detail-hero`）', () {
    testWidgets('52×52 R16 `--bg` 图标块 + 20px w600 标题，按行的同一判据取分类', (
      tester,
    ) async {
      await pumpSheet(tester);

      final hero = find.byKey(const Key('food-detail-hero'));
      expect(hero, findsOneWidget, reason: 'hero 是 A 的第一件（图标 + 标题 + meta）');

      // 分类判据与列表行同一处：同一个 name/rawCategory 必须得出同一分类。
      final expected = FoodCategory.classify(
        name: catalogItem.name,
        rawCategory: catalogItem.category,
      );
      expect(expected, FoodCategory.staple, reason: '夹具前提：蒸米饭 → 主食');
      final icon = tester.widget<FoodCategoryIcon>(
        find.descendant(of: hero, matching: find.byType(FoodCategoryIcon)),
      );
      expect(icon.category, expected, reason: 'hero 图标与行图标是同一判据的分类');
      expect(icon.size, 52, reason: 'A `.food-detail-icon` 52×52');
      expect(
        icon.padding,
        const EdgeInsets.all(6),
        reason: 'A `.food-detail-icon img{40×40}` ⇒ 内衬 (52−40)/2 = 6',
      );
      expect(
        icon.background,
        tokens(tester, hero).background,
        reason: 'A polish 把 `.food-detail-icon` 的底定成 `--bg`',
      );
      final blockR = tester.getRect(
        find.descendant(of: hero, matching: find.byType(DecoratedBox)).first,
      );
      expect(blockR.width, 52);
      expect(blockR.height, 52);

      // 圆角 16（A `border-radius:16px`）——现状是共享件的 12，这一条会先红。
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: hero, matching: find.byType(DecoratedBox)).first,
      );
      expect(
        (box.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(LfDimens.radiusLg),
        reason: 'A `.food-detail-icon` r16（不是列表行的 r12）',
      );

      // 标题 20px w600（A 20 w650；仓内字重只到 600）。
      final title = tester.widget<Text>(find.text('蒸米饭'));
      expect(title.style?.fontSize, 20, reason: 'A `.food-detail-title` 20px');
      expect(title.style?.fontWeight, FontWeight.w600);

      // 图标对文字块垂直居中（A `align-items:center`）。
      final meta = tester.getRect(find.byKey(const Key('food-detail-meta')));
      expect(
        blockR.center.dy,
        closeTo((tester.getRect(find.text('蒸米饭')).top + meta.bottom) / 2, 0.5),
        reason: 'A 的 hero 是 align-items:center：图标心 = 文字块心',
      );
    });

    testWidgets('meta 行：品牌 12 muted + 徽标同排，间距 6、距标题 7，且不再写分类', (tester) async {
      await pumpSheet(tester);

      final meta = find.byKey(const Key('food-detail-meta'));
      expect(meta, findsOneWidget);
      // ADR-036（2026-10-21 用户「种类在顶部进行筛选」）：分类**不在**详情里
      // 变成一行文字——它是列表的筛选维度，由搜索行下面的
      // `food-library-category-row` 承担。分类的图形仍留在 hero 图标块上。
      expect(
        find.byKey(const Key('food-detail-category')),
        findsNothing,
        reason: '详情弹层不再写分类（种类只由顶部筛选与 hero 图标表达）',
      );
      expect(find.text('主食'), findsNothing);
      // 品牌仍是裸品牌名的独立文本：两处既有判据按精确值断言「品牌从哪一列来」。
      final brand = find.byKey(const Key('food-detail-brand'));
      expect(tester.widget<Text>(brand).data, '金龙鱼');
      expect(find.byType(LfBadge), findsOneWidget);
      expect(find.text('内置'), findsOneWidget);

      final brandStyle = tester.widget<Text>(brand).style!;
      expect(brandStyle.fontSize, 12, reason: 'A `.food-detail-meta` 12px');
      expect(
        brandStyle.color,
        tokens(tester, meta).mutedForeground,
        reason: 'A 的 meta 是 `--muted` 色',
      );
      // 两件同排：间距 6（A `gap:6px`），且在同一行（垂直中心一致）。
      final brandRect = tester.getRect(brand);
      final badge = tester.getRect(find.byType(LfBadge));
      expect(badge.left - brandRect.right, closeTo(6, 0.5));
      expect((badge.center.dy - brandRect.center.dy).abs(), lessThan(0.5));
      // meta 距标题 7（A `margin-top:7px`）。
      expect(
        tester.getRect(meta).top - tester.getRect(find.text('蒸米饭')).bottom,
        closeTo(7, 0.5),
      );
    });
  });

  group('营养面板（D47：A `.food-nutrition-panel`）', () {
    testWidgets('r16 + 1px `--border` + `--bg` + 内衬 18 + 环与宏量间距 24，且无卡阴影', (
      tester,
    ) async {
      await pumpSheet(tester);

      final panel = find.byKey(const Key('food-detail-panel'));
      expect(panel, findsOneWidget);
      final container = tester.widget<Container>(panel);
      final t = tokens(tester, panel);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, t.background, reason: 'A 的面板底是 `--bg`');
      expect(decoration.borderRadius, BorderRadius.circular(LfDimens.radiusLg));
      final side = (decoration.border! as Border).top;
      expect(side.width, 1);
      expect(side.color, t.border, reason: 'A 的面板是 1px `--border` 实描边');
      expect(
        decoration.boxShadow ?? const <BoxShadow>[],
        isEmpty,
        reason: 'A 的面板不是卡：没有阴影（`lfCardDecoration` 在浅色下会画一条）',
      );
      expect(
        container.padding,
        const EdgeInsets.all(18),
        reason: 'A `.food-nutrition-panel{padding:18px}`',
      );

      // 环与三行块都在面板里，间距 24（A `gap:24px`）。
      final ring = tester.getRect(find.byType(LfFoodKcalRing));
      final rows = tester.getRect(find.byType(MacroDotRows));
      final panelRect = tester.getRect(panel);
      expect(panelRect.contains(ring.center), isTrue);
      expect(panelRect.contains(rows.center), isTrue);
      expect(
        rows.left - ring.right,
        closeTo(24, 0.5),
        reason: 'A 的 grid gap 24',
      );
    });

    testWidgets('环心 14px w600；宏量行：点 7、标签 12 muted、值 14 w600 右端、点距 8', (
      tester,
    ) async {
      await pumpSheet(tester);

      final value = tester.widget<Text>(
        find.byKey(const Key('food-detail-ring-kcal')),
      );
      expect(
        value.style?.fontSize,
        14,
        reason: 'A `.detail-density .data-ring-center b` 14px',
      );
      expect(value.style?.fontWeight, FontWeight.w600);

      final dot = tester.getRect(dotFinder());
      expect(
        dot.width,
        7,
        reason: 'A `.food-macro-stack .macro-dot` width 7px',
      );
      expect(dot.height, 7);

      final label = tester.getRect(find.text('蛋白质'));
      expect(label.left - dot.right, closeTo(8, 0.5), reason: 'A 的行内 gap 8');
      final labelStyle = tester.widget<Text>(find.text('蛋白质')).style!;
      expect(labelStyle.fontSize, 12, reason: 'A 的宏量名是 12px');
      expect(
        labelStyle.color,
        tokens(tester, find.text('蛋白质')).mutedForeground,
      );

      final grams = tester.widget<Text>(find.text('2.6g'));
      expect(grams.style?.fontSize, 14, reason: 'A 的宏量值是 14px w650 → 仓内 600');
      expect(grams.style?.fontWeight, FontWeight.w600);
      final rows = tester.getRect(find.byType(MacroDotRows));
      expect(
        tester.getRect(find.text('2.6g')).right,
        closeTo(rows.right, 0.5),
        reason: 'A 的 grid 第三列是 auto ⇒ 值贴右端',
      );
    });
  });

  group('标题、口径注与行动行（D48/D49/D50）', () {
    testWidgets('弹层首行是「食物详情」，在 hero 之上（A `openSheet` 的第一参）', (tester) async {
      await pumpSheet(tester);

      final title = find.text('食物详情');
      expect(title, findsOneWidget);
      expect(
        tester.getRect(title).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('food-detail-hero'))).top,
        ),
        reason: '弹层标题在内容之上',
      );
    });

    testWidgets('口径注居中，句子仍是共享单源（D48）', (tester) async {
      await pumpSheet(tester);

      final note = tester.widget<Text>(
        find.byKey(const Key('food-density-scale-note')),
      );
      expect(
        note.textAlign,
        TextAlign.center,
        reason: 'A `.food-density-note{text-align:center}`',
      );
      expect(note.data, contains('kcal/100g'), reason: '句子与列表头同一份（D39 单源）');
      // 居中的是多行里的每一行：文字块横跨内容宽，而不是收缩到内容再居中。
      expect(
        tester.getRect(find.byKey(const Key('food-detail-ring-label'))).width,
        greaterThan(200),
        reason: '注横跨整宽、文字在块内居中',
      );
    });

    testWidgets('行动行：1px `--track` 上边线 + 两钮 46 高、等宽、带图标（D49）', (tester) async {
      await pumpSheet(
        tester,
        item: userCreated,
        onEdit: () async {},
        onDelete: () async {},
      );

      final actions = find.byKey(const Key('food-detail-actions'));
      expect(actions, findsOneWidget);
      final container = tester.widget<Container>(actions);
      final decoration = container.decoration! as BoxDecoration;
      final top = decoration.border!.top;
      expect(
        top.width,
        1,
        reason: 'A `.food-detail-actions{border-top:1px solid var(--track)}`',
      );
      expect(top.color, tester.element(actions).lfc.ringTrack);
      expect(container.padding, const EdgeInsets.fromLTRB(0, 12, 0, 2));

      final edit = tester.getRect(find.byKey(const Key('food-detail-edit')));
      final remove = tester.getRect(
        find.byKey(const Key('food-detail-delete')),
      );
      expect(edit.height, closeTo(46, 0.5), reason: 'A 的两钮 min-height 46');
      expect(remove.height, closeTo(46, 0.5));
      expect(
        (edit.width - remove.width).abs(),
        lessThan(0.5),
        reason: 'A 的两钮 flex:1（等宽）',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('food-detail-edit')),
          matching: find.byIcon(Icons.edit_outlined),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('food-detail-delete')),
          matching: find.byIcon(Icons.delete_outline),
        ),
        findsOneWidget,
      );
    });
  });

  group('新建/编辑表单（D51：A `.form-grid` + 表单注）', () {
    Future<void> openDialog(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    NewFoodDialog.show(context, onSubmit: (_) async => null),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('四个数字字段落 2×2 网格（热量/蛋白质同行，碳水/脂肪同行）', (tester) async {
      await openDialog(tester);

      final kcal = tester.getRect(find.byKey(const Key('new-food-每 100g 热量')));
      final protein = tester.getRect(
        find.byKey(const Key('new-food-每 100g 蛋白质')),
      );
      final carbs = tester.getRect(find.byKey(const Key('new-food-每 100g 碳水')));
      final fat = tester.getRect(find.byKey(const Key('new-food-每 100g 脂肪')));

      expect(kcal.top, closeTo(protein.top, 0.5), reason: 'A `.form-grid` 两列');
      expect(protein.left, greaterThan(kcal.right), reason: '蛋白质在右列');
      expect(carbs.top, greaterThan(kcal.bottom), reason: '碳水在第二行');
      expect(carbs.top, closeTo(fat.top, 0.5));
      expect(fat.left, greaterThan(carbs.right));
    });

    testWidgets('表单注只写成立的事实（每 100g / 0 按无数据 / 不改历史）', (tester) async {
      await openDialog(tester);

      final note = find.byKey(const Key('new-food-note'));
      expect(note, findsOneWidget);
      expect(
        tester.widget<Text>(note).data,
        '以上均为每 100g。热量为 0 按无数据展示；改动不会回写已经记过的餐次。',
        reason: 'A 的注里「留空表示未知」与本仓必填校验矛盾，不搬（D51）',
      );
      expect(find.textContaining('留空表示未知'), findsNothing);
    });
  });
}
