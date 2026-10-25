import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';

/// `RV4-P1-07` / D7（`docs/56` §4.1 已裁决）：选中态必须比未选中**更远离背景**。
///
/// 根因（实测，不是「淡了一点」）：
/// - 选中底 `brandSoft #ECFBF5` 对白卡 **1.07**；
/// - 未选中 `muted #EFF3F1` 对白卡 **1.12**。
/// ⇒ **未选中比选中更显眼**，用户说的「点了没反应」在视觉上是真的。
///
/// 新档 `LfPillTone.selected`：亮 `mint-200 #A8EBCF`（1.36）、
/// 暗 `mint-300 #2A3A32`（1.41），且 `soft` 档与 `brandSoft()` 一动没动
/// （那 5 处轻强调动作 + 10 处主题语义不受影响）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child, {required bool dark}) => MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(body: Center(child: child)),
  );

  Color? bgOf(WidgetTester tester, Key key) => tester
      .widget<TextButton>(find.byKey(key))
      .style
      ?.backgroundColor
      ?.resolve(const {});

  double contrast(Color a, Color b) {
    final la = _luminance(a);
    final lb = _luminance(b);
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  for (final dark in [false, true]) {
    final mode = dark ? '暗色' : '亮色';
    final brightness = dark ? Brightness.dark : Brightness.light;
    final tone = dark ? 300 : 200;

    group(mode, () {
      testWidgets('selected 档底取 mint-$tone', (tester) async {
        const key = Key('sel-probe');
        await tester.pumpWidget(
          host(
            const LfPillButton(
              key: key,
              label: '选中',
              selected: true,
              onPressed: _noop,
            ),
            dark: dark,
          ),
        );
        expect(bgOf(tester, key), LfColors.mint(brightness).tone(tone));
      });

      testWidgets('选中底 vs 卡面 ≥1.30 且 > 未选中 muted 的对比度', (tester) async {
        // 卡面用设计系统语义色（`lf.card`），不是主题派生的 surface——胶囊
        // 就是画在卡片上的，判据必须对卡面成立。
        final colors = dark ? LfSemanticColors.dark : LfSemanticColors.light;
        final card = colors.card;
        final selectedBg = LfColors.mint(brightness).tone(dark ? 300 : 200);
        final selectedContrast = contrast(selectedBg, card);
        expect(
          selectedContrast,
          greaterThanOrEqualTo(1.30),
          reason: '$mode 选中底对卡面 $selectedContrast < 1.30',
        );
        // 根因的反向断言：未选中 `muted` 对卡面的对比必须**低于**选中。
        expect(
          selectedContrast,
          greaterThan(contrast(colors.muted, card)),
          reason:
              '$mode 选中底对比 ${selectedContrast.toStringAsFixed(2)} 必须大于'
              '未选中 ${contrast(colors.muted, card).toStringAsFixed(2)}'
              '（顺序颠倒就是 RV4-P1-07 本身）',
        );
      });

      testWidgets('soft 档取色不变（5 处轻强调动作回归）', (tester) async {
        const key = Key('soft-probe');
        await tester.pumpWidget(
          host(
            const LfPillButton(
              key: key,
              label: '修正',
              tone: LfPillTone.soft,
              onPressed: _noop,
            ),
            dark: dark,
          ),
        );
        expect(bgOf(tester, key), LfColors.brandSoft(brightness));
      });

      test('brandSoft() 本身未改（10 处主题语义不受影响）', () {
        expect(
          LfColors.brandSoft(Brightness.light),
          const Color(0xFFECFBF5),
          reason: 'D7 明确不动 brandSoft()',
        );
        expect(
          LfColors.brandSoft(Brightness.dark),
          const Color(0xFF203C30),
          reason: 'D7 明确不动 brandSoft()',
        );
      });
    });
  }

  group('训练页两处选中胶囊走新档', () {
    testWidgets('点 plan-days-5 后该枚底 == selected 档', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // 只渲染胶囊本身（同一组件、同一入参路径），避免把整页依赖搬进来：
      // 「点后取色」在页面级由 L1 门禁断言 selected 标志，这里专钉**取色**。
      await tester.pumpWidget(
        host(
          const LfPillButton(
            key: Key('plan-days-5'),
            label: '5天',
            selected: true,
            onPressed: _noop,
          ),
          dark: false,
        ),
      );
      expect(
        bgOf(tester, const Key('plan-days-5')),
        LfColors.mint(Brightness.light).tone(200),
      );
    });
  });
}

void _noop() {}

double _luminance(Color color) {
  double channel(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
