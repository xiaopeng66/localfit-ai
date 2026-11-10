import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_calorie_ring.dart';
import 'package:localfit_ai/app/design/widgets/lf_ring_painter.dart';

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

  testWidgets('超过目标：进度封顶 1.0，第三行如实写「超上限 X」', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 2300, targetKcal: 2100)),
    );

    expect(ringPainter(tester).ratio, 1.0);
    // 【2026-10-25 断言语义变更（需求 1，强度不降）】原来第三行写未截断的
    // 「110%」。用户要的区间方案里，「超了 200 kcal」比「完成度 110%」更该
    // 被一眼看到（暖色 + 明确的超出量）。判据改钉**超出量**——它同时钉住了
    // 「数字是从 2300−2100 算出来的」，比一个百分比更难蒙对。
    expect(find.text('超上限 200'), findsOneWidget);
    expect(find.text('110%'), findsNothing, reason: '超上限时不再写百分比');
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

  testWidgets('颜色语义：轨道 = ringTrack、进度 = 深色 brandStrong（用户定稿）', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 840, targetKcal: 2100)),
    );

    final painter = ringPainter(tester);
    expect(painter.track, LfComponentColors.light.ringTrack);
    // 【2026-10-31 用户定稿】进度弧 = 深色（brandStrong），不再是亮 primary。
    expect(painter.progress, LfColors.brandStrong(Brightness.light));
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

  // 【2026-10-31 用户（「浅色带跟圆环一样宽，别那么宽」）】带同宽后指针
  // （圆钮）整件退役：深色弧的圆头线帽本身就是尖端标记。原「359% 指针绕回
  // 起点」的缺陷随指针一起消失；此处改钉 359% 时满圈暖弧 + 带转暖。
  testWidgets('359%：满圈暖弧、带转暖（指针已退役，无绕回问题）', (tester) async {
    await tester.pumpWidget(
      wrap(
        LfCalorieRing(
          consumedKcal: 6690,
          targetKcal: 1844,
          targetMinKcal: 1669,
        ),
      ),
    );
    final painter = ringPainter(tester) as LfRingPainter;
    expect(painter.ratio, 1.0, reason: '超上限 = 满圈');
    expect(painter.pointerRatio, isNull, reason: '指针退役');
    expect(painter.bandColor, isNotNull, reason: '超上限 ⇒ 带变暖色');
  });

  // 【2026-10-31 用户三轮定稿（原话：「一个圆的后边部分是一个浅色的区间，
  // 然后已摄入是深色的进度，超出以后就变色警告」）】刻度回归线性：整圈 =
  // 0 → 上限；浅色宽带在环的后段真实位置（min/上限 → 1.0）；进度弧深色
  // （brandStrong），超上限转暖。此前「0.85 余量刻度」方案被用户否决退役。
  testWidgets('有区间：浅色带在环的后段真实位置，进度弧深色', (tester) async {
    await tester.pumpWidget(
      wrap(
        const LfCalorieRing(
          consumedKcal: 0,
          targetKcal: 1844,
          targetMinKcal: 1669,
        ),
      ),
    );
    final painter = ringPainter(tester) as LfRingPainter;
    expect(painter.bandEnd, 1.0, reason: '带末 = 整圈终点（上限处）');
    expect(
      painter.bandStart,
      closeTo(1669 / 1844, 0.0001),
      reason: '带首 = 下限的真实刻度位置',
    );
    // 0 摄入：弧 0、指针退役（null）。
    expect(painter.ratio, 0.0);
    expect(painter.pointerRatio, isNull);
  });

  testWidgets('进度弧 = 深色（brandStrong），不是亮 primary', (tester) async {
    await tester.pumpWidget(
      wrap(
        const LfCalorieRing(
          consumedKcal: 900,
          targetKcal: 1844,
          targetMinKcal: 1669,
        ),
      ),
    );
    final painter = ringPainter(tester) as LfRingPainter;
    expect(
      painter.progress.toARGB32(),
      LfColors.brandStrong(Brightness.light).toARGB32(),
      reason: '用户：已摄入是「深色的进度」',
    );
    expect(painter.ratio, closeTo(900 / 1844, 0.0001), reason: '线性刻度');
  });

  testWidgets('有区间：吃到上限 = 满圈（此刻恰好在带末）', (tester) async {
    await tester.pumpWidget(
      wrap(
        const LfCalorieRing(
          consumedKcal: 1844,
          targetKcal: 1844,
          targetMinKcal: 1669,
        ),
      ),
    );
    final painter = ringPainter(tester) as LfRingPainter;
    expect(painter.ratio, 1.0, reason: '满环 = 达标（上限处）');
  });

  testWidgets('超上限：满圈转暖色', (tester) async {
    await tester.pumpWidget(
      wrap(
        const LfCalorieRing(
          consumedKcal: 7150,
          targetKcal: 1844,
          targetMinKcal: 1669,
        ),
      ),
    );
    final painter = ringPainter(tester) as LfRingPainter;
    expect(painter.ratio, 1.0);
    expect(
      painter.progress.toARGB32(),
      LfSemanticColors.light.warning.toARGB32(),
      reason: '用户：超出以后就变色警告',
    );
  });

  testWidgets('无区间（单值目标）：同一把线性尺——满环 = 达标', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 2100, targetKcal: 2100)),
    );
    final painter = ringPainter(tester) as LfRingPainter;
    expect(painter.ratio, 1.0);
    expect(painter.bandStart, isNull);
    expect(painter.bandEnd, isNull);
  });
}
