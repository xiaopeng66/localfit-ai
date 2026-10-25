import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';

/// [AppNumberField] 的语义契约（docs/21 §3.3）。
///
/// 这个组件存在的理由是「克数框的上边框那行小字」：标签必须固定在框外
/// 上方，不能浮到框顶之上，也不能在空态里不可见。两条替代方案都被实测
/// 否掉（`labelText` 会浮出框顶、`prefixText` 空态 opacity=0），所以这里
/// 把选中的方案与它的无障碍行为一起锁住。
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );

  /// 输入框与它上方标签的几何关系。
  Rect fieldRect(WidgetTester tester) =>
      tester.getRect(find.byType(TextFormField).first);
  Rect labelRect(WidgetTester tester, String label) =>
      tester.getRect(find.text(label).first);

  /// 读屏遍历到的全部节点，格式 `标签|值`。
  ///
  /// 走 `simulatedAccessibilityTraversal` 而不是自己爬 `PipelineOwner`：
  /// 后者在 Flutter 3.10 起已废弃（`tester.binding.pipelineOwner`），且根
  /// PipelineOwner 本身不持有语义树。模拟遍历的额外好处是它断言的正是
  /// 辅助技术实际会读到的东西——被 `ExcludeSemantics` 摘掉的节点不会出现。
  List<String> semanticsNodes(WidgetTester tester) {
    final handle = tester.ensureSemantics();
    final found = tester.semantics
        .simulatedAccessibilityTraversal()
        .map((node) {
          final data = node.getSemanticsData();
          return '${data.label}|${data.value}';
        })
        .where((entry) => entry != '|')
        .toList();
    handle.dispose();
    return found;
  }

  testWidgets('标签固定在输入框上方，不浮到框外顶上', (tester) async {
    await tester.pumpWidget(
      host(
        const AppNumberField(fieldKey: Key('probe'), label: '克数', unit: 'g'),
      ),
    );
    await tester.pumpAndSettle();

    final field = fieldRect(tester);
    final label = labelRect(tester, '克数（g）');
    // 标签整体在输入框顶边之上（框外上方），不是压在框沿上。
    expect(
      label.bottom,
      lessThanOrEqualTo(field.top),
      reason: '标签必须在输入框之外的上方；压到框沿就是用户抱怨的那行小字',
    );
  });

  testWidgets('空态与聚焦态都看得见标签（prefixText 会在空态隐身）', (tester) async {
    await tester.pumpWidget(
      host(
        const AppNumberField(fieldKey: Key('probe'), label: '克数', unit: 'g'),
      ),
    );
    await tester.pumpAndSettle();

    for (final phase in const ['空未聚焦', '空聚焦']) {
      final finder = find.text('克数（g）');
      expect(finder, findsOneWidget, reason: '$phase：标签必须存在');
      final element = finder.evaluate().first;
      var opacity = 1.0;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is AnimatedOpacity) {
          opacity = (ancestor.widget as AnimatedOpacity).opacity;
          return false;
        }
        return true;
      });
      expect(opacity, 1.0, reason: '$phase：标签必须完全可见');
      if (phase == '空未聚焦') {
        await tester.tap(find.byType(TextFormField));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('标签并进输入框语义节点，且只播报一次', (tester) async {
    final controller = TextEditingController(text: '150');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        AppNumberField(
          fieldKey: const Key('probe'),
          label: '克数',
          unit: 'g',
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nodes = semanticsNodes(tester);
    // 一个节点同时带标签与值：读屏播报「克数（g），150」。
    expect(nodes, contains('克数（g）|150'));
    // 标签不得作为独立节点再出现一次（框外标签必须 ExcludeSemantics）。
    expect(
      nodes.where((node) => node.startsWith('克数（g）|') && node.endsWith('|')),
      isEmpty,
      reason: '标签被播报了两遍：可见标签文字也在语义树里',
    );
  });

  testWidgets('标签文本把单位与「可选」并进括号', (tester) async {
    await tester.pumpWidget(
      host(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppNumberField(fieldKey: Key('a'), label: '克数', unit: 'g'),
            AppNumberField(
              fieldKey: Key('b'),
              label: '默认份量',
              unit: 'g',
              optional: true,
            ),
            AppNumberField(fieldKey: Key('c'), label: '目标组数', unit: '组'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('克数（g）'), findsOneWidget);
    expect(find.text('默认份量（g，可选）'), findsOneWidget);
    expect(find.text('目标组数（组）'), findsOneWidget);
  });
}
