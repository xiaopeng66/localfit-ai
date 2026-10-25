// 2026-10-14 Round7 A：仅更新视觉期望，保留行为、无障碍与性能约束。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_button_states.dart';
import 'package:localfit_ai/app/design/widgets/dashed_border.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';

void _noop() {}

/// 主题化宿主：§3.8 的实心档位由 `app_theme` 给出（共享件不自己设色），
/// 因此九型的形态断言必须挂在真主题下。
Widget host(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? AppTheme.dark() : AppTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

String _lbl(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text).first).data!;

Color? _bg(WidgetTester tester, Key key) => tester
    .widget<TextButton>(find.byKey(key))
    .style
    ?.backgroundColor
    ?.resolve(const {});

Color? _fg(WidgetTester tester, Key key) => tester
    .widget<TextButton>(find.byKey(key))
    .style
    ?.foregroundColor
    ?.resolve(const {});

/// B5/B9 的虚线画笔（`CustomPaint` 在按钮子树里不是唯一——Material 还会插一个
/// 画形状边框的 `_ShapeBorderPaint`，所以按 foregroundPainter 类型挑）。
Finder dashedPaintFinder(Key key) => find.descendant(
  of: find.byKey(key),
  matching: find.byWidgetPredicate(
    (w) => w is CustomPaint && w.foregroundPainter is DashedBorderPainter,
  ),
);

void main() {
  group('B1 LfPrimaryButton（实心 / 12 圆角 / h44 / 无阴影）', () {
    const key = Key('b1');

    testWidgets('几何：最小高 44、12 圆角、触达 ≥44', (tester) async {
      await tester.pumpWidget(
        host(const LfPrimaryButton(key: key, label: '保存', onPressed: _noop)),
      );
      final style = tester.widget<FilledButton>(find.byKey(key)).style!;
      expect(style.minimumSize!.resolve(const {})!.height, 44);
      expect(
        (style.shape!.resolve(const {}) as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(LfDimens.radiusMd),
      );
      expect(style.elevation!.resolve(const {}), 0);
      // padded 触达膨胀把命中盒撑到 48（§3.8 硬规则 ≥44）。
      expect(
        tester.getSize(find.byKey(key)).height,
        greaterThanOrEqualTo(LfDimens.minTouchTarget),
      );
    });

    testWidgets('配色单一来源：自己不设背景，从主题读实心品牌色', (tester) async {
      await tester.pumpWidget(
        host(const LfPrimaryButton(key: key, label: '保存', onPressed: _noop)),
      );
      final style = tester.widget<FilledButton>(find.byKey(key)).style!;
      // 显式不设 ⇒ styleFrom 得到 null 属性，落主题 filledButtonTheme。
      expect(style.backgroundColor?.resolve(const {}), isNull);
      expect(
        lfSolidButtonFill(tester.element(find.byKey(key))),
        LfSemanticColors.light.primary,
      );
      // 字色 = primaryForeground。
      final text = tester.widget<Text>(find.byType(Text).first);
      expect(text.style!.color, LfSemanticColors.light.primaryForeground);
      expect(text.style!.fontSize, LfText.bodyStrong.fontSize);
    });

    testWidgets('disabled：onPressed 为 null 时走 muted 底（不是实心档）', (tester) async {
      await tester.pumpWidget(
        host(const LfPrimaryButton(key: key, label: '保存')),
      );
      expect(tester.widget<FilledButton>(find.byKey(key)).onPressed, isNull);
      // 主题的禁用档（共享件不覆写背景，因此禁用色也来自主题）。
      final fill = AppTheme.light().filledButtonTheme.style!.backgroundColor!
          .resolve(const {WidgetState.disabled});
      expect(fill, LfSemanticColors.light.muted);
      final text = tester.widget<Text>(find.text('保存'));
      expect(text.style!.color, LfSemanticColors.light.mutedForeground);
    });

    testWidgets('busy：显示三点跳动、隐藏文案、点击被吞', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(
          LfPrimaryButton(
            key: key,
            label: '保存',
            busy: true,
            onPressed: () => tapped = true,
          ),
        ),
      );
      expect(find.byType(AppButtonDotsLoader), findsOneWidget);
      expect(find.text('保存'), findsNothing);
      expect(tester.widget<FilledButton>(find.byKey(key)).onPressed, isNull);
      await tester.tap(find.byKey(key), warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets('语义：内层原生按钮即提供 button:true + 标签（不重复包 Semantics）', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const LfPrimaryButton(key: key, label: '保存', onPressed: _noop)),
      );
      expect(find.byKey(key), findsOneWidget);
      final node = tester.getSemantics(find.byKey(key));
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.label, contains('保存'));
    });

    testWidgets('expand：撑满可用宽度', (tester) async {
      await tester.pumpWidget(
        host(
          const LfPrimaryButton(
            key: key,
            label: '保存',
            onPressed: _noop,
            expand: true,
          ),
        ),
      );
      // 默认视口 800 宽；Size.fromHeight 拉满。
      expect(tester.getSize(find.byKey(key)).width, 800);
    });
  });

  group('B1e LfPrimaryButton.emphasized（A：与实心档同面容，无渐变/彩色阴影）', () {
    const key = Key('b1e');

    testWidgets('按钮不自己设背景，也不在按钮外画渐变或阴影', (tester) async {
      await tester.pumpWidget(
        host(
          const LfPrimaryButton.emphasized(
            key: key,
            label: '生成',
            onPressed: _noop,
          ),
        ),
      );
      final style = tester.widget<FilledButton>(find.byKey(key)).style!;
      // A 的 `.btn.primary` 只有品牌实心底（`refinement.css:2`）：不设值 ⇒
      // 与 B1 同走主题 filledButtonTheme。
      expect(style.backgroundColor?.resolve(const {}), isNull);
      expect(
        lfSolidButtonFill(tester.element(find.byKey(key))),
        LfSemanticColors.light.primary,
      );
      final decos = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.byKey(key),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>();
      expect(
        decos.where((d) => d.gradient != null),
        isEmpty,
        reason: 'A 的有效主 CTA 是纯品牌实心，无渐变',
      );
      expect(
        decos.expand((d) => d.boxShadow ?? const <BoxShadow>[]),
        isEmpty,
        reason: 'A 的按钮不带彩色阴影',
      );
      // 不能误用别的彩色阴影（拍照确认 40% / FAB 40%）。
      expect(
        decos.any(
          (d) => listEquals(
            d.boxShadow,
            LfShadows.scanConfirmCta(LfSemanticColors.light.primary),
          ),
        ),
        isFalse,
      );
    });

    testWidgets('禁用：实心档回落 muted 底 + mutedForeground 字，仍无阴影', (tester) async {
      const off = Key('b1e-off');
      await tester.pumpWidget(
        host(const LfPrimaryButton.emphasized(key: off, label: '生成')),
      );
      final theme = AppTheme.light();
      expect(tester.widget<FilledButton>(find.byKey(off)).onPressed, isNull);
      expect(
        theme.filledButtonTheme.style!.backgroundColor!.resolve(const {
          WidgetState.disabled,
        }),
        LfSemanticColors.light.muted,
      );
      expect(
        tester.widget<Text>(find.text('生成')).style!.color,
        LfSemanticColors.light.mutedForeground,
      );
      final shadows = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.byKey(off),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .expand((d) => d.boxShadow ?? const <BoxShadow>[]);
      expect(shadows, isEmpty, reason: '禁用态同样不得绘制阴影');
    });
  });

  group('B2 LfConfirmButton（12 圆角 / h48 / 无阴影）', () {
    const key = Key('b2');

    testWidgets('几何与阴影：RoundedRectangleBorder R12、h48、expand 拉满宽', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const LfConfirmButton(key: key, label: '确认', onPressed: _noop)),
      );
      final style = tester.widget<FilledButton>(find.byKey(key)).style!;
      expect(style.shape!.resolve(const {}), isA<RoundedRectangleBorder>());
      expect(
        (style.shape!.resolve(const {}) as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(LfDimens.radiusMd),
      );
      expect(style.minimumSize!.resolve(const {})!.height, 48);
      expect(style.elevation!.resolve(const {}), 0);
      expect(tester.getSize(find.byKey(key)).width, 800);
      final shadows = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.byKey(key),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.boxShadow);
      expect(
        shadows.every((s) => s == null || s.isEmpty),
        isTrue,
        reason: 'B2 确认按钮所有阴影列表必须为空或 null',
      );
      expect(
        shadows.any(
          (s) => listEquals(
            s,
            LfShadows.aiPrimaryCta(LfSemanticColors.light.primary),
          ),
        ),
        isFalse,
      );
    });

    testWidgets('expand:false 只按内容宽（不拉满）', (tester) async {
      await tester.pumpWidget(
        host(
          const LfConfirmButton(
            key: key,
            label: '确认',
            onPressed: _noop,
            expand: false,
          ),
        ),
      );
      expect(tester.getSize(find.byKey(key)).width, lessThan(800));
    });

    testWidgets('禁用（onPressed:null）：h48 保留且无阴影', (tester) async {
      // 禁用态保留确认按钮高度，文字回落 mutedForeground。
      await tester.pumpWidget(
        host(const LfConfirmButton(key: key, label: '确认')),
      );
      expect(tester.widget<FilledButton>(find.byKey(key)).onPressed, isNull);
      final style = tester.widget<FilledButton>(find.byKey(key)).style!;
      expect(style.minimumSize!.resolve(const {})!.height, 48);
      final text = tester.widget<Text>(find.text('确认'));
      expect(text.style!.color, LfSemanticColors.light.mutedForeground);
      final shadows = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.byKey(key),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .map((d) => d.boxShadow)
          .toList();
      expect(
        shadows.any((s) => s != null && s.isNotEmpty),
        isFalse,
        reason: '禁用态同样不得绘制任何阴影',
      );
    });
  });

  group('B3 LfPillButton（full 圆角 / h32 / 三档）', () {
    testWidgets('几何：StadiumBorder + h32 + 12 号字', (tester) async {
      await tester.pumpWidget(
        host(
          const LfPillButton(key: Key('p'), label: '加入早餐', onPressed: _noop),
        ),
      );
      final style = tester
          .widget<TextButton>(find.byKey(const Key('p')))
          .style!;
      expect(style.shape!.resolve(const {}), isA<StadiumBorder>());
      expect(style.minimumSize!.resolve(const {})!.height, 32);
      expect(
        style.textStyle!.resolve(const {})!.fontSize,
        LfText.captionStrong.fontSize,
      );
      // 触达仍 ≥44（padded 膨胀；B3 是内联动作，视觉小但命中不小）。
      expect(
        tester.getSize(find.byKey(const Key('p'))).height,
        greaterThanOrEqualTo(LfDimens.minTouchTarget),
      );
    });

    testWidgets('三档取色：solid 读主题实心档 / muted / soft 浅品牌底+品牌字', (tester) async {
      const kSolid = Key('p-solid');
      const kMuted = Key('p-muted');
      const kSoft = Key('p-soft');
      await tester.pumpWidget(
        host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              LfPillButton(
                key: kSolid,
                label: 'A',
                tone: LfPillTone.solid,
                onPressed: _noop,
              ),
              LfPillButton(
                key: kMuted,
                label: 'B',
                tone: LfPillTone.muted,
                onPressed: _noop,
              ),
              LfPillButton(
                key: kSoft,
                label: 'C',
                tone: LfPillTone.soft,
                onPressed: _noop,
              ),
            ],
          ),
        ),
      );
      expect(_bg(tester, kSolid), LfSemanticColors.light.primary);
      expect(_fg(tester, kSolid), LfSemanticColors.light.primaryForeground);
      expect(_bg(tester, kMuted), LfSemanticColors.light.muted);
      expect(_fg(tester, kMuted), LfSemanticColors.light.mutedForeground);
      expect(_bg(tester, kSoft), LfColors.brandSoft(Brightness.light));
      expect(_fg(tester, kSoft), LfColors.mintText(Brightness.light));
    });

    testWidgets('暗色 soft：浅品牌底取 brandSoft（不是页面底色）', (tester) async {
      const key = Key('p-dark');
      await tester.pumpWidget(
        host(
          const LfPillButton(
            key: key,
            label: 'C',
            tone: LfPillTone.soft,
            onPressed: _noop,
          ),
          dark: true,
        ),
      );
      final mintDark = LfColors.mint(Brightness.dark);
      expect(_bg(tester, key), LfColors.brandSoft(Brightness.dark));
      expect(_fg(tester, key), LfColors.mintText(Brightness.dark));
      // 兜底：不能等于暗色页面底色（那样等于没有底）。
      expect(_bg(tester, key), isNot(mintDark.tone(50)));
    });

    // 【语义变更，不是删断言换绿】`RV4-P1-07` / D7（2026-10-24）：
    // 选中档从 `soft` 改为**新档 `selected`**。原断言「selected 提升到 soft 档」
    // 钉的是一个**错误行为**——`soft` 底 `#ECFBF5` 对白卡 1.07:1，比未选中
    // `muted` 的 1.12:1 更接近背景，选中比常态更不显眼。断言的**对象语义变了**
    // （soft → selected），所以这里改写为断言新档取色 + 对比度顺序，而不是删掉。
    testWidgets('selected 提升到 selected 档（muted 未被显式指定时）', (tester) async {
      const key = Key('p-sel');
      await tester.pumpWidget(
        host(
          const LfPillButton(
            key: key,
            label: 'D',
            selected: true,
            onPressed: _noop,
          ),
        ),
      );
      final mintLight = LfColors.mint(Brightness.light);
      expect(_bg(tester, key), mintLight.tone(200));
      expect(_fg(tester, key), mintLight.tone(900));
      // 反向断言（根因本身）：选中底**不得**再等于 `brandSoft`。
      expect(
        _bg(tester, key),
        isNot(LfColors.brandSoft(Brightness.light)),
        reason: 'D7 之后选中不再走 soft 档——soft 只服务「轻强调动作」',
      );
    });

    testWidgets('soft 档取色不变（5 处轻强调动作回归钉住）', (tester) async {
      const key = Key('p-soft');
      await tester.pumpWidget(
        host(
          const LfPillButton(
            key: key,
            label: 'E',
            tone: LfPillTone.soft,
            onPressed: _noop,
          ),
        ),
      );
      expect(_bg(tester, key), LfColors.brandSoft(Brightness.light));
      expect(_fg(tester, key), LfColors.mintText(Brightness.light));
    });

    testWidgets('显式传 soft + selected 时尊重调用方（不被选中档覆盖）', (tester) async {
      const key = Key('p-explicit-soft');
      await tester.pumpWidget(
        host(
          const LfPillButton(
            key: key,
            label: 'F',
            tone: LfPillTone.soft,
            selected: true,
            onPressed: _noop,
          ),
        ),
      );
      expect(
        _bg(tester, key),
        LfColors.brandSoft(Brightness.light),
        reason: '只有 tone==muted（默认）时才自动升级；显式 tone 是本意',
      );
    });

    testWidgets('overlay 档 = card@90% + foreground（压在照片上的带字胶囊）', (
      tester,
    ) async {
      // `拍照识餐.html:327` 的「重新拍摄」：card/90% 底 + foreground 字。
      // 与 LfCircleIconButton 的 overlay 变体同一套「浮在图上」取色。
      const key = Key('p-overlay');
      await tester.pumpWidget(
        host(
          const LfPillButton(
            key: key,
            label: '重新拍摄',
            tone: LfPillTone.overlay,
            onPressed: _noop,
          ),
        ),
      );
      expect(
        _bg(tester, key),
        LfSemanticColors.light.card.withValues(alpha: 0.9),
      );
      expect(_fg(tester, key), LfSemanticColors.light.foreground);
    });
  });

  group('B5 LfDashedButton（虚线胶囊 / h28 可视 + ≥44 触达）', () {
    const key = Key('b5');

    testWidgets('虚线画在 28 高的可视胶囊上，触达靠外层膨胀到 48', (tester) async {
      await tester.pumpWidget(
        host(
          const LfDashedButton(
            key: key,
            label: '添加菜品',
            icon: Icons.add,
            onPressed: _noop,
          ),
        ),
      );
      final style = tester.widget<TextButton>(find.byKey(key)).style!;
      // 内边距全在子内容里，按钮本体不占位。
      expect(style.padding!.resolve(const {}), EdgeInsets.zero);
      expect(style.minimumSize!.resolve(const {}), Size.zero);
      expect(style.shape!.resolve(const {}), isA<StadiumBorder>());

      final paintFinder = dashedPaintFinder(key);
      final painter =
          tester.widget<CustomPaint>(paintFinder).foregroundPainter!
              as DashedBorderPainter;
      expect(painter.color, LfColors.mintLight.tone(300));
      expect(painter.radius, 14); // 28 / 2
      expect(tester.getSize(paintFinder).height, 28);
      // 按钮外框（膨胀区）≥44。
      expect(
        tester.getSize(find.byKey(key)).height,
        greaterThanOrEqualTo(LfDimens.minTouchTarget),
      );
    });

    testWidgets('去掉图标时只渲染文案（microStrong 字号）', (tester) async {
      await tester.pumpWidget(
        host(const LfDashedButton(key: key, label: '添加', onPressed: _noop)),
      );
      expect(find.byIcon(Icons.add), findsNothing);
      expect(_lbl(tester), '添加');
      final text = tester.widget<Text>(find.text('添加'));
      expect(text.style!.fontSize, LfText.microStrong.fontSize);
      expect(text.style!.color, LfColors.mintText(Brightness.light));
    });

    testWidgets('文案带主题字体族（不许在 Material 按钮里丢掉族）', (tester) async {
      // 2026-10-16（食堂目录捕获面抓到）：`Text` 落在 `TextButton` 里时，
      // 按钮自带的 `DefaultTextStyle` **替换**环境那层（主题 bodyMedium 的
      // Roboto），只留按钮样式自己声明的字段。本仓其它按钮的文案都经
      // `_lfButtonLabel` 显式 merge `textTheme.bodyMedium`，只有 B5 是直接
      // `Text(style: LfText.microStrong)` ——族因此变成 null，在 flutter_tester
      // 里落到 Ahem/FlutterTest，CJK 整串渲染成豆腐块（真机上靠平台兜底看不出，
      // 但「按钮文案带主题族」是本仓的一致性契约）。
      await tester.pumpWidget(
        host(const LfDashedButton(key: key, label: '添加菜品', onPressed: _noop)),
      );
      final context = tester.element(find.byKey(key));
      final themeFamily = Theme.of(context).textTheme.bodyMedium!.fontFamily;
      expect(themeFamily, isNotNull, reason: '前提：主题给 bodyMedium 指定了族');
      final text = tester.widget<Text>(find.text('添加菜品'));
      expect(
        text.style!.fontFamily,
        themeFamily,
        reason: 'B5 文案必须带上主题字体族（与其它按钮同一条契约）',
      );
      // 字号/字重仍是 microStrong（族之外的两项不受影响）。
      expect(text.style!.fontSize, LfText.microStrong.fontSize);
      expect(text.style!.fontWeight, LfText.microStrong.fontWeight);
    });
  });

  group('B6/B7 文字按钮（透明底 / 无最小尺寸）', () {
    testWidgets('B6 字色 = mintText（亮 #187653 / 暗 mint-400）', (tester) async {
      const key = Key('b6');
      await tester.pumpWidget(
        host(const LfTextButton(key: key, label: '记录第一条', onPressed: _noop)),
      );
      expect(_fg(tester, key), LfColors.mintText(Brightness.light));
      expect(_fg(tester, key), const Color(0xFF187653));
      expect(
        tester
            .widget<TextButton>(find.byKey(key))
            .style!
            .backgroundColor
            ?.resolve(const {}),
        isNull,
      );
      expect(
        tester.getSize(find.byKey(key)).height,
        greaterThanOrEqualTo(LfDimens.minTouchTarget),
      );
    });

    testWidgets('B6 暗色字色提亮到 mint-400', (tester) async {
      const key = Key('b6-dark');
      await tester.pumpWidget(
        host(
          const LfTextButton(key: key, label: '查看全部', onPressed: _noop),
          dark: true,
        ),
      );
      expect(_fg(tester, key), LfColors.mintText(Brightness.dark));
      expect(_fg(tester, key), LfColors.mint(Brightness.dark).tone(400));
    });

    testWidgets('B7 字色 = error（破坏性操作用文字型）', (tester) async {
      const key = Key('b7');
      await tester.pumpWidget(
        host(const LfDangerButton(key: key, label: '清除全部数据', onPressed: _noop)),
      );
      expect(_fg(tester, key), LfSemanticColors.light.error);
    });
  });

  group('B8 LfSmallButton（12 圆角 / h44 / 实心）', () {
    const key = Key('b8');

    testWidgets('几何：12 圆角 + 最小高 44', (tester) async {
      await tester.pumpWidget(
        host(const LfSmallButton(key: key, label: '保存配置', onPressed: _noop)),
      );
      final style = tester.widget<FilledButton>(find.byKey(key)).style!;
      expect(
        (style.shape!.resolve(const {}) as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(LfDimens.radiusMd),
      );
      expect(LfDimens.radiusMd, 12);
      expect(style.minimumSize!.resolve(const {})!.height, 44);
      expect(
        style.textStyle!.resolve(const {})!.fontSize,
        LfText.captionStrong.fontSize,
      );
      // 实心档仍读主题（自己不设背景色）。
      expect(style.backgroundColor?.resolve(const {}), isNull);
      expect(
        lfSolidButtonFill(tester.element(find.byKey(key))),
        LfSemanticColors.light.primary,
      );
    });
  });

  testWidgets('B1 fitLabel：窄坑位里单行等比缩小、不折行（裁决 ④ 的兜底）', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 64,
          height: 200,
          child: Column(
            children: [
              LfPrimaryButton(
                key: const Key('fit-on'),
                label: '净摄入入账',
                fitLabel: true,
                onPressed: () {},
              ),
              LfPrimaryButton(
                key: const Key('fit-off'),
                label: '净摄入入账',
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );

    // fitLabel: true ⇒ 单行（高度 = 一行 + 内衬）；false ⇒ 折行（更高）。
    final on = tester.getRect(find.byKey(const Key('fit-on')));
    final off = tester.getRect(find.byKey(const Key('fit-off')));
    // fitLabel: true ⇒ 单行（必要时等比缩小）；false ⇒ 折行（更高）。
    expect(on.height, lessThan(off.height));
    final label = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('fit-on')),
        matching: find.text('净摄入入账'),
      ),
    );
    expect(
      label.height,
      lessThanOrEqualTo(21.5),
      reason: '标签只有一行高（14px × 1.5 = 21；缩小时更矮）',
    );
  });

  group('B11 LfLinkButton（A `.link-button`：透明底 / 12 w500 / min 44×44）', () {
    const key = Key('b11');

    testWidgets('几何：min 44×44、左右内衬 3、触达 ≥44', (tester) async {
      await tester.pumpWidget(
        host(const LfLinkButton(key: key, label: '食物管理', onPressed: _noop)),
      );
      final style = tester.widget<TextButton>(find.byKey(key)).style!;
      // A `.link-button{min-height:44px}` + `refinement.css:18{min-width:44px}`。
      expect(style.minimumSize!.resolve(const {})!.height, 44);
      expect(style.minimumSize!.resolve(const {})!.width, 44);
      // A `padding: 0 3px`（左右各 3）。
      expect(style.padding!.resolve(const {})!.horizontal, 6);
      expect(style.padding!.resolve(const {})!.vertical, 0);
      expect(
        tester.getSize(find.byKey(key)).height,
        greaterThanOrEqualTo(LfDimens.minTouchTarget),
      );
    });

    testWidgets('字色 = brand-strong（亮 mint-700 / 暗 mint-400），自己不设底', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const LfLinkButton(key: key, label: '导入食物数据', onPressed: _noop)),
      );
      expect(_fg(tester, key), LfColors.mintText(Brightness.light));
      expect(
        tester
            .widget<TextButton>(find.byKey(key))
            .style!
            .backgroundColor
            ?.resolve(const {}),
        isNull,
      );
      expect(tester.widget<Text>(find.text('导入食物数据')).style!.fontSize, 12);
      expect(
        tester.widget<Text>(find.text('导入食物数据')).style!.fontWeight,
        FontWeight.w500,
      );
    });

    // 暗色**另起一条**（与 B6 同口径）：同一条用例里二次 `pumpWidget` 时
    // `MaterialApp` 会走内部的 `AnimatedTheme`，主题在 200ms 里渐变——立刻量到的
    // 还是亮色档（这不是实现在暗色下取错了色，是量早了）。
    testWidgets('B11 暗色字色提亮到 mint-400', (tester) async {
      await tester.pumpWidget(
        host(
          const LfLinkButton(key: key, label: '导入食物数据', onPressed: _noop),
          dark: true,
        ),
      );
      expect(_fg(tester, key), LfColors.mintText(Brightness.dark));
      expect(_fg(tester, key), LfColors.mint(Brightness.dark).tone(400));
    });

    testWidgets('副行：10px `--muted`，与主行同链（A `<span>主行<small>副行</small>`）', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const LfLinkButton(
            key: key,
            label: '导入食物数据',
            subtitle: '从文件读取到食物库',
            icon: Icons.file_download_outlined,
            onPressed: _noop,
          ),
        ),
      );
      // A `polish.css:29`：`.library-footer .link-button small{color:var(--muted);
      // font-size:10px}`。
      final subtitle = tester.widget<Text>(find.text('从文件读取到食物库'));
      expect(subtitle.style!.fontSize, 10);
      expect(subtitle.style!.color, LfSemanticColors.light.mutedForeground);
      // 前置图标 16dp（A `icon('file-import', 16)`）。
      final icon = find.descendant(
        of: find.byKey(key),
        matching: find.byIcon(Icons.file_download_outlined),
      );
      expect(tester.getSize(icon), const Size(16, 16));
      // 副行在主行之下（列排 start 对齐，A `flex-direction:column`）。
      expect(
        tester.getRect(find.text('从文件读取到食物库')).top,
        greaterThanOrEqualTo(tester.getRect(find.text('导入食物数据')).bottom - 0.5),
      );
    });
  });

  group('DashedBorderPainter（B5/B9 共用的虚线画笔）', () {
    test('shouldRepaint：任一参数变化都要重绘', () {
      const base = DashedBorderPainter(color: Color(0xFFA8EBCF));
      expect(base.shouldRepaint(base), isFalse);
      expect(
        base.shouldRepaint(const DashedBorderPainter(color: Color(0xFF000000))),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const DashedBorderPainter(color: Color(0xFFA8EBCF), radius: 4),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const DashedBorderPainter(color: Color(0xFFA8EBCF), strokeWidth: 2),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const DashedBorderPainter(color: Color(0xFFA8EBCF), dash: 6),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const DashedBorderPainter(color: Color(0xFFA8EBCF), gap: 6),
        ),
        isTrue,
      );
    });
  });
}
