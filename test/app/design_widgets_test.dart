import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_calorie_ring.dart';
import 'package:localfit_ai/app/design/widgets/macro_bar.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_widgets.dart';

/// 设计组件冒烟（阶段 I-2b 重写）。
///
/// 本文件原本测旧半圆 `CalorieRing` 与旧 `MacroPill`。两件按 docs/21 §3.1/§3.2
/// 废弃后，旧断言的去向：
///
/// - 「还可吃 814 kcal」「超过目标 200 kcal」：措辞随旧件删除（`dashboard_view_states_test`
///   反向断言旧措辞不出现在今日页）。新页面用问候行「距离目标还差」+ 状态徽标表达。
/// - 「超目标切换 error 色」：新环不给 error 色，改由徽标文字表达；分级函数
///   `DashboardCalorieCard.statusLabel` 的四个分支在 `dashboard_view_states_test` 逐条测。
/// - 「完成建档后开启目标」：保留为 `LfCalorieRing(targetKcal: 0)` 无目标档 +
///   卡片副标题「尚未设定目标」。
/// - MacroPill 圆点/标签/数值：保留为 `MacroBar` 的圆点 + 标签 + 「N / M g」。
///
/// 新环自身的几何/夹紧/颜色/语义由 `test/app/design/lf_calorie_ring_test.dart`
/// 覆盖；这里只留跨组件冒烟与 ScanConfidenceChip。
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('LfCalorieRing 显示摄入/目标/百分比，不含旧措辞', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 1286, targetKcal: 2100)),
    );

    // Round7 A：环心值千分位（`format()`），目标行搬去卡片 foot。
    expect(find.text('1,286'), findsOneWidget);
    expect(find.text('已摄入 kcal'), findsOneWidget);
    expect(find.text('/ 2100 kcal'), findsNothing);
    expect(find.text('61%'), findsOneWidget);
    expect(find.textContaining('还可吃'), findsNothing);
    expect(find.textContaining('超过目标'), findsNothing);
  });

  testWidgets('LfCalorieRing 无目标档不编剩余数字', (tester) async {
    await tester.pumpWidget(
      wrap(const LfCalorieRing(consumedKcal: 0, targetKcal: 0)),
    );

    // 「不编剩余数字」的口径不变，只是旧的两行本身已随 A 退场：
    // 环内既没有「/ 0 kcal」也没有「0%」。
    expect(find.text('/ 0 kcal'), findsNothing);
    expect(find.text('0%'), findsNothing);
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('MacroBar 渲染圆点、标签与「当前 / 目标 单位」', (tester) async {
    await tester.pumpWidget(
      wrap(
        const MacroBar(
          label: '蛋白',
          color: LfColors.proteinLight,
          current: 86,
          target: 120,
        ),
      ),
    );

    expect(find.text('蛋白'), findsOneWidget);
    expect(find.text('86 / 120 g'), findsOneWidget);
    // 8dp 数据色圆点在（旧 MacroPill 的 CircleAvatar 角色）。
    final dot = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(MacroBar),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((dot.decoration! as BoxDecoration).shape, BoxShape.circle);
    final fraction = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fraction.widthFactor, closeTo(86 / 120, 0.0001));
  });

  testWidgets('MacroBar 目标为 0 时进度 0，不除零也不越界', (tester) async {
    await tester.pumpWidget(
      wrap(
        const MacroBar(
          label: '脂肪',
          color: LfColors.fatLight,
          current: 0,
          target: 0,
        ),
      ),
    );

    final fraction = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fraction.widthFactor, 0.0);
    expect(find.text('0 / 0 g'), findsOneWidget);
  });

  testWidgets('MacroBar 超额封顶 100%', (tester) async {
    await tester.pumpWidget(
      wrap(
        const MacroBar(
          label: '碳水',
          color: LfColors.carbsLight,
          current: 300,
          target: 120,
        ),
      ),
    );

    final fraction = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fraction.widthFactor, 1.0);
    expect(find.text('300 / 120 g'), findsOneWidget);
  });

  testWidgets('MacroRatioRow 渲染三格「名称 百分比」', (tester) async {
    await tester.pumpWidget(
      wrap(
        const MacroRatioRow(
          entries: [
            ('蛋白', LfColors.proteinLight, 27),
            ('碳水', LfColors.carbsLight, 43),
            ('脂肪', LfColors.fatLight, 30),
          ],
        ),
      ),
    );

    // 设计稿（今日.html）是行内 flex：三格「名称 百分比」，放得下就一行。
    // 每格是同一个 Text.rich 的两个 span（名称灰 + 百分比数据色），所以按
    // **包含关系**断言——`find.text('蛋白')` 在 rich text 里匹配不到片段。
    for (final fragment in ['蛋白', '27%', '碳水', '43%', '脂肪', '30%']) {
      expect(find.textContaining(fragment), findsOneWidget, reason: fragment);
    }
  });

  testWidgets('ScanConfidenceChip maps confidence to high/mid/low', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const Column(
          children: [
            ScanConfidenceChip(confidence: 0.85),
            ScanConfidenceChip(confidence: 0.5),
            ScanConfidenceChip(confidence: 0.2),
          ],
        ),
      ),
    );

    expect(find.text('高 · 置信度 85%'), findsOneWidget);
    expect(find.text('中 · 置信度 50%'), findsOneWidget);
    expect(find.text('低 · 置信度 20%'), findsOneWidget);
  });
}
