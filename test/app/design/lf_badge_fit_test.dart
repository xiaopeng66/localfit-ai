import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';

/// R-1（2026-10-29 用户：今日页饮水卡「达标 n%」显示不全）。
///
/// 根因：`LfBadge` 文本 `Flexible + maxLines:1 + ellipsis`——被行内挤压时
/// 显示成「达标 …」（用户实机截图），比完整数字更误导。修法：文本外再套
/// `FittedBox(scaleDown)`——有界挤压时**等比缩小**而不是省略号；够宽时逐
/// 像素同旧版（scaleDown 只在放不下时缩）。
///
/// 本文件钉两件事：
/// 1. 挤压场景下徽标文本**没有省略号**（RED 于旧版：overflow == ellipsis）；
/// 2. 挤压场景下整枚徽标可见（无 RenderFlex overflow），且文本渲染宽度 =
///    约束宽（FittedBox 真的缩放了，不是把字藏掉）。
void main() {
  testWidgets('挤压下不省略、整枚可见（FittedBox 缩放兜底）', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    const constraintWidth = 64.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: constraintWidth,
              child: Row(children: [Flexible(child: LfBadge.mint('达标 100%'))]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: '挤压不构成溢出');
    final text = tester.widget<Text>(
      find.descendant(of: find.byType(LfBadge), matching: find.byType(Text)),
    );
    expect(
      text.overflow,
      isNot(TextOverflow.ellipsis),
      reason: '「达标 …」比完整数字更误导——徽标文本不许省略号',
    );
    // FittedBox 生效：**徽标本体**收进约束（FittedBox 里的 Text 以自然宽
    // 参与缩放计算，绘制时等比缩小，不能拿 Text 的 RenderBox 断言宽度）。
    final badge = tester.renderObject<RenderBox>(find.byType(LfBadge));
    expect(
      badge.size.width,
      lessThanOrEqualTo(constraintWidth),
      reason: '徽标本体必须收进约束（scaleDown 生效）',
    );
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('足够宽时与旧版一致：不缩放、按内容定宽', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: LfBadge.mint('达标 42%'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 无界方向上 FittedBox 退化为按内容定宽：徽标行高度与字号一致，
    // 文本完整（本用例钉「没把正常态变坏」）。
    final badgeBox = tester.renderObject<RenderBox>(find.byType(LfBadge));
    expect(badgeBox.size.width, greaterThan(60));
  });
}
