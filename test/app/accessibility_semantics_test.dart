import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_calorie_ring.dart';
import 'package:localfit_ai/app/design/widgets/macro_bar.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';

/// 可访问性语义契约（阶段 I-2b 重写）。
///
/// 旧件 `CalorieRing`（半圆）与 `MacroPill` 按 docs/21 §3.1/§3.2 废弃后，
/// 语义断言原样搬到取代件 `LfCalorieRing` / `MacroBar`：圆环三段数字对外
/// 仍是**一个**语义节点（完成度 + 摄入值），色点保持纯装饰。
Widget wrap(Widget child, {bool dark = false}) => MaterialApp(
  theme: dark ? ThemeData.dark(useMaterial3: true) : null,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('LfCalorieRing 暴露完成度与摄入值的语义节点', (tester) async {
    await tester.pumpWidget(
      wrap(
        const Center(child: LfCalorieRing(consumedKcal: 840, targetKcal: 2100)),
      ),
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

  testWidgets('LfCalorieRing 无目标时语义播报无目标', (tester) async {
    await tester.pumpWidget(
      wrap(
        const Center(child: LfCalorieRing(consumedKcal: 120, targetKcal: 0)),
      ),
    );

    final semantics = find.ancestor(
      of: find.text('120'),
      matching: find.byType(Semantics),
    );
    expect(semantics, findsWidgets);
    expect(tester.getSemantics(semantics.first).label, contains('无热量目标'));
  });

  testWidgets('骨架占位块不进入语义树', (tester) async {
    await tester.pumpWidget(wrap(const SkeletonBox(height: 44)));

    expect(
      find.descendant(
        of: find.byType(SkeletonBox),
        matching: find.byType(Semantics),
      ),
      findsNothing,
    );
  });

  testWidgets('MacroBar 色点为纯装饰，标签与数值保持可读', (tester) async {
    await tester.pumpWidget(
      wrap(
        const Center(
          child: SizedBox(
            width: 240,
            child: MacroBar(
              label: '蛋白质',
              color: Color(0xFFFF8A65),
              current: 92,
              target: 120,
            ),
          ),
        ),
      ),
    );

    // 标签与数值都在（相邻播报为「蛋白质 92 / 120 g」）。
    expect(find.text('蛋白质'), findsOneWidget);
    expect(find.text('92 / 120 g'), findsOneWidget);
    // 8dp 色点自身没有可聚焦语义节点（纯装饰，与旧 MacroPill 的契约一致）。
    final dot = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).shape == BoxShape.circle,
    );
    expect(dot, findsOneWidget);
    expect(
      find.descendant(of: dot, matching: find.byType(Semantics)),
      findsNothing,
    );
  });

  // docs/31 S8：DesignCard 的 semanticLabel 曾是死参数——构造函数收了、
  // build 从不用（体重卡/快捷统计卡传的读屏标签全部被静默丢弃）。
  // 契约：给了 label 就必须真的进语义树；没给就不凭空造节点；
  // 有 label 时子内容照常可读、整卡 onTap 的点击动作不丢。
  testWidgets('DesignCard semanticLabel 进入语义树，子内容与点击动作不丢', (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        Center(
          child: DesignCard(
            semanticLabel: '本月体重，近一个月',
            onTap: () => taps++,
            child: const Text('72.5'),
          ),
        ),
      ),
    );

    // ① 卡级标签进语义树（修前：死参数 → findsNothing）。
    final labeled = find.bySemanticsLabel(RegExp('本月体重，近一个月'));
    expect(labeled, findsOneWidget);
    // ② 子内容照常可读（container 语义节点不吞子节点）。
    expect(find.text('72.5'), findsOneWidget);
    expect(tester.getSemantics(find.text('72.5')), isNotNull);
    // ③ 整卡仍是可点节点：Semantics 包裹不吞点击，label 节点上 tap 通。
    await tester.tap(labeled);
    expect(taps, 1);

    semantics.dispose();
  });

  testWidgets('DesignCard 不传 semanticLabel 时不凭空造卡级标签节点', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      wrap(
        const Center(
          // 子节点无可访问名称（纯尺寸块）：此时语义树里不该凭空冒出
          // 任何标签——不传 label 就不造 label。
          child: DesignCard(child: SizedBox(height: 24, width: 120)),
        ),
      ),
    );

    expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);

    semantics.dispose();
  });
}
