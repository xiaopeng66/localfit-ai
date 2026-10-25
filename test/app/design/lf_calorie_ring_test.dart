import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_calorie_ring.dart';

/// 新设计热量圆环（docs/21 §3.2 **重写**）：完整圆环 120×120、r=52、线宽 10，
/// 轨道 muted / 进度 primary，从 -90° 起画；中心三段文字。
///
/// 本文件取代 `calorie_ring_v2_test.dart`（旧半圆件）：旧件的宏量内段、拖拽
/// 明细与辉光由 docs/21 §3.2 **明令移除**，对应断言随之作废；保留下来的
/// 是不变量——几何尺寸、进度夹紧、颜色语义、读屏语义节点。
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  dynamic ringPainter(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(LfCalorieRing),
        matching: find.byType(CustomPaint),
      ),
    );
    return paint.painter! as dynamic;
  }

  test('几何按 docs/21 §3.2：全圆 120、r=52、线宽 10', () {
    expect(LfDimens.calorieRingSize, 120);
    expect(LfDimens.calorieRingRadius, 52);
    expect(LfDimens.calorieRingStroke, 10);
  });

  testWidgets('中心三段文字：数值 / 目标 / 百分比', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 1050, targetKcal: 2100)),
    );

    expect(tester.getSize(find.byType(LfCalorieRing)), const Size(120, 120));
    // A `ring()`：环心 = `format(值)` + 固定标签「已摄入 kcal」
    // （`app.js:128`）；目标值搬去卡片 foot（`dashboard-ring-target`），
    // 环内不再有「/ N kcal」这一行。
    expect(find.text('1,050'), findsOneWidget);
    expect(find.text('已摄入 kcal'), findsOneWidget);
    expect(find.text('/ 2100 kcal'), findsNothing);
    expect(find.text('50%'), findsOneWidget);
  });

  testWidgets('超过目标：进度封顶 1.0，百分比仍显示真实比例', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 2300, targetKcal: 2100)),
    );

    expect(ringPainter(tester).ratio, 1.0);
    expect(find.text('110%'), findsOneWidget);
  });

  testWidgets('无目标（target <= 0）：进度 0 且不除零', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 120, targetKcal: 0)),
    );

    expect(ringPainter(tester).ratio, 0.0);
    // 无目标不编百分比（A 的百分比是「对上目标」的派生量，没目标就没有
    // 这个量）；摄入值本身照实显示。
    expect(find.text('0%'), findsNothing);
    expect(find.text('120'), findsOneWidget);
  });

  testWidgets('颜色语义：轨道 = ringTrack、进度 = primary', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 840, targetKcal: 2100)),
    );

    final painter = ringPainter(tester);
    expect(painter.track, LfComponentColors.light.ringTrack);
    expect(painter.progress, LfSemanticColors.light.primary);
    expect(painter.ratio, closeTo(0.4, 0.0001));
  });

  testWidgets('三段文字对外是一个语义节点（旧件的可访问性契约）', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 840, targetKcal: 2100)),
    );

    final semantics = find.ancestor(
      of: find.text('840'),
      matching: find.byType(Semantics),
    );
    expect(semantics, findsWidgets);
    final props = tester.getSemantics(semantics.first);
    expect(props.label, contains('40%'));
    expect(props.value, contains('840'));
  });

  testWidgets('无目标时语义播报「无热量目标」', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 120, targetKcal: 0)),
    );

    final semantics = find.ancestor(
      of: find.text('120'),
      matching: find.byType(Semantics),
    );
    expect(semantics, findsWidgets);
    expect(tester.getSemantics(semantics.first).label, contains('无热量目标'));
  });
}
