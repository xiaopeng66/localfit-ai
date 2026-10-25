import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/widgets/lf_bottom_nav.dart';

/// RV2-P2-05（`docs/52`）：320dp 截图里中央「AI」标签看起来压在手势条上。
/// 先用几何断言把事实钉住：标签底边必须**在手势带之上**，且在 320dp 与
/// 360dp 两种宽度、1.0× / 2.0× 两种字号下都成立。
///
/// 若这条断言在原生 metrics 下本来就绿，说明截图里那一次是 `wm size/density`
/// override 造成的测量假象（系统 inset 没有跟着 dp 换算），不是真机缺陷。
void main() {
  Future<void> pumpNav(
    WidgetTester tester, {
    required Size size,
    required double inset,
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: inset);
    tester.view.viewPadding = FakeViewPadding(bottom: inset);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: LfBottomNav(currentIndex: 0, onTap: (_) {}),
        ),
      ),
    );
    await tester.pump();
  }

  void expectLabelAboveInset(WidgetTester tester, double inset) {
    final label = tester.getRect(find.text('AI'));
    final navBottom = tester.getRect(find.byType(LfBottomNav)).bottom;
    final usableBottom =
        navBottom - LfInsets.bottom(tester.element(find.byType(LfBottomNav)));
    expect(
      label.bottom,
      lessThanOrEqualTo(usableBottom + 0.01),
      reason: '「AI」标签底边 ${label.bottom} 越过了手势带起始线 $usableBottom',
    );
    expect(label.top, greaterThan(0));
  }

  for (final width in const [320.0, 360.0]) {
    testWidgets('${width.toInt()}dp：AI 标签在手势带之上（1.0×）', (tester) async {
      await pumpNav(tester, size: Size(width, 640), inset: 24);
      expectLabelAboveInset(tester, 24);
    });

    testWidgets('${width.toInt()}dp：AI 标签在手势带之上（2.0×）', (tester) async {
      await pumpNav(tester, size: Size(width, 640), inset: 24, scale: 2);
      expectLabelAboveInset(tester, 24);
    });
  }
}
