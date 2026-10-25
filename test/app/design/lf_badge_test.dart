import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/dashed_border.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';

Widget host(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? AppTheme.dark() : AppTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

/// 徽章根节点上的装饰（dashed 档是 `CustomPaint`，没有 `DecoratedBox`）。
BoxDecoration? decorationOf(WidgetTester tester) {
  for (final box in tester.widgetList<DecoratedBox>(
    find.descendant(
      of: find.byType(LfBadge),
      matching: find.byType(DecoratedBox),
    ),
  )) {
    final decoration = box.decoration;
    if (decoration is BoxDecoration) return decoration;
  }
  return null;
}

TextStyle? textStyleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style;

void main() {
  final lfLight = LfSemanticColors.light;
  final mintLight = LfColors.mint(Brightness.light);
  final mintDark = LfColors.mint(Brightness.dark);

  group('LfBadge 形态（docs/21 §3.9）：8 圆角 / px-2 py-1 / 11 w500', () {
    testWidgets('neutral：muted 底 + mutedForeground 字', (tester) async {
      await tester.pumpWidget(host(const LfBadge.neutral('周')));
      final deco = decorationOf(tester)!;
      expect(deco.color, lfLight.muted);
      expect(deco.borderRadius, BorderRadius.circular(LfDimens.radiusSm));
      expect(LfDimens.radiusSm, 8);
      final style = textStyleOf(tester, '周')!;
      expect(style.color, lfLight.mutedForeground);
      expect(style.fontSize, LfText.label.fontSize);
      expect(style.fontWeight, LfText.label.fontWeight);
    });

    testWidgets('内边距 px-2 py-1（8 / 4）', (tester) async {
      await tester.pumpWidget(host(const LfBadge.neutral('周')));
      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(LfBadge),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(
        padding.padding,
        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      );
    });

    testWidgets('mint：浅品牌底 + 品牌字（亮 mint-100 / mint-700）', (tester) async {
      await tester.pumpWidget(host(const LfBadge.mint('燃脂中')));
      expect(decorationOf(tester)!.color, mintLight.tone(100));
      expect(
        textStyleOf(tester, '燃脂中')!.color,
        LfColors.mintText(Brightness.light),
      );
    });

    testWidgets('mint 暗色：暗色 ramp 100 档 + 提亮字', (tester) async {
      await tester.pumpWidget(host(const LfBadge.mint('燃脂中'), dark: true));
      expect(decorationOf(tester)!.color, mintDark.tone(100));
      expect(
        textStyleOf(tester, '燃脂中')!.color,
        LfColors.mintText(Brightness.dark),
      );
      expect(decorationOf(tester)!.color, isNot(mintDark.tone(50)));
    });

    testWidgets('honey：carbs100 底 + cardForeground 字', (tester) async {
      await tester.pumpWidget(host(const LfBadge.honey('本周热门')));
      expect(decorationOf(tester)!.color, lfLight.carbs100);
      expect(textStyleOf(tester, '本周热门')!.color, lfLight.cardForeground);
    });

    testWidgets('dashed：透明底 + mint-300 虚线 + 8 圆角，无 DecoratedBox 底色', (
      tester,
    ) async {
      await tester.pumpWidget(host(const LfBadge.dashed('晚餐 · 计划')));
      expect(decorationOf(tester), isNull);
      final paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(LfBadge),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final painter = paint.foregroundPainter! as DashedBorderPainter;
      expect(painter.color, mintLight.tone(300));
      expect(painter.radius, LfDimens.radiusSm);
      expect(
        textStyleOf(tester, '晚餐 · 计划')!.color,
        LfColors.mintText(Brightness.light),
      );
    });

    testWidgets('图标：16dp + 与文字间距 4dp', (tester) async {
      await tester.pumpWidget(
        host(const LfBadge.mint('燃脂中', icon: Icons.local_fire_department)),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, LfDimens.iconSm);
      expect(icon.color, LfColors.mintText(Brightness.light));
      // Icon 自己内部也会建一个 SizedBox，所以按宽度找那 4dp 的间距盒，
      // 不能取「第一个」。
      final gaps = tester.widgetList<SizedBox>(
        find.descendant(
          of: find.byType(LfBadge),
          matching: find.byType(SizedBox),
        ),
      );
      expect(gaps.any((g) => g.width == LfDimens.spaceXSmall), isTrue);
    });

    testWidgets('outlinedBrand：mint-300 实线边 + 品牌字 + 透明底（与 dashed 同源色）', (
      tester,
    ) async {
      await tester.pumpWidget(host(const LfBadge.outlinedBrand('Diatosta')));
      final deco = decorationOf(tester)!;
      expect(deco.color, isNull, reason: '描边档必须透明底，否则与实底档分不开');
      final border = deco.border! as Border;
      expect(border.top.color, mintLight.tone(300));
      expect(border.top.width, 1);
      expect(deco.borderRadius, BorderRadius.circular(LfDimens.radiusSm));
      expect(
        textStyleOf(tester, 'Diatosta')!.color,
        LfColors.mintText(Brightness.light),
      );
    });

    testWidgets('outlinedBrand 暗色：暗 ramp 300 档描边 + 提亮字', (tester) async {
      await tester.pumpWidget(
        host(const LfBadge.outlinedBrand('Diatosta'), dark: true),
      );
      final border = decorationOf(tester)!.border! as Border;
      expect(border.top.color, mintDark.tone(300));
      expect(
        textStyleOf(tester, 'Diatosta')!.color,
        LfColors.mintText(Brightness.dark),
      );
    });

    testWidgets('outlinedBrand 与实底档逐像素同高同内缩：1px 边从内边距里让出（8/4 总量）', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              LfBadge.outlinedBrand('品牌'),
              SizedBox(width: 8),
              LfBadge.neutral('内置'),
              SizedBox(width: 8),
              LfBadge.mint('自建'),
            ],
          ),
        ),
      );
      // 同一段文字、同一字号：三档外框尺寸必须一致，否则同一条底行上会错位。
      final sizes = [
        for (var i = 0; i < 3; i++) tester.getSize(find.byType(LfBadge).at(i)),
      ];
      expect(sizes[0].height, sizes[1].height);
      expect(sizes[0].height, sizes[2].height);
      // 文字到外框的间距也要一致：描边档把 1px 边让进内边距（7+1 / 3+1），
      // 视觉内缩与实底档同为 8 / 4。三档都是 2 个汉字，宽度相同。
      const labels = ['品牌', '内置', '自建'];
      for (var i = 0; i < 3; i++) {
        final badge = tester.getTopLeft(find.byType(LfBadge).at(i));
        final text = tester.getTopLeft(find.text(labels[i]));
        expect(text.dx - badge.dx, closeTo(8, 0.01), reason: '第 $i 档横向内缩');
        expect(text.dy - badge.dy, closeTo(4, 0.01), reason: '第 $i 档纵向内缩');
      }
    });

    testWidgets('默认构造与 .neutral 同形态', (tester) async {
      await tester.pumpWidget(host(const LfBadge('每 100g')));
      expect(decorationOf(tester)!.color, lfLight.muted);
      expect(textStyleOf(tester, '每 100g')!.color, lfLight.mutedForeground);
    });
  });
}
