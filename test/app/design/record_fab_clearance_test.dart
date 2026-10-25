import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/record_fab.dart';

/// RV2-P2-06：记录页右下常驻圆钮会压住内容（2.0× 下实测压住营养卡的
/// 「还可摄入 X kcal」）。FAB 是浮层，唯一可持续的做法是让**滚动内容**能
/// 滚出它的覆盖带——判据是末尾预留 ≥ 圆钮顶边的高度。
void main() {
  Future<double> clearanceWith(WidgetTester tester, double bottomInset) async {
    // dp = px / dpr：测试默认 dpr=3，固定成 1 才能按 dp 直接断言。
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    tester.view.viewPadding = FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    late double value;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            value = RecordFab.contentClearance(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return value;
  }

  testWidgets('无手势带时：末尾预留 = 圆钮顶边（96 + 50），不是 73.5', (tester) async {
    final value = await clearanceWith(tester, 0);
    // 断言**绝对数字**，不用被测常量自证（隔离变异 M05 抓到：原来写成
    // `bottomOffset + footprint`，把常量改小测试照样绿）。
    expect(value, 146);
    expect(
      value,
      greaterThan(LfDimens.navReservedSpace),
      reason: '翻滚回退检测：退回裸 navReserve（73.5）时必须红',
    );
  });

  testWidgets('有手势带时：末尾预留把手势带再加一遍', (tester) async {
    final value = await clearanceWith(tester, 24);
    expect(value, 170);
  });

  testWidgets('超大手势带时取较大值，不会小于 navReserve', (tester) async {
    // 极端环境（例如 200dp 的底部叠层）不得让预留缩水到 navReserve 之下。
    final value = await clearanceWith(tester, 200);
    expect(value, greaterThanOrEqualTo(346));
  });
}
