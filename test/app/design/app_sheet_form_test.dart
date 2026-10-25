import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';

/// 长内容弹层（docs/21 §3.1「大弹层内 sticky 底部按钮区」）：
/// 内容滚动时按钮行固定在弹层底部，不随内容滚出屏幕。
Widget _longBody(BuildContext context) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < 30; i++)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('内容行 $i', key: Key('sheet-row-$i')),
      ),
  ],
);

/// 打开 [AppSheet.show]（标题+内容+按钮的通用弹层）。
Future<void> _openPlainSheet(WidgetTester tester, Widget content) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  AppSheet.show<void>(context, title: '长内容', content: content),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

Future<void> _openFormSheet(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => AppSheet.showForm<void>(
                context,
                title: '大弹层',
                body: (context, setSheetState) => _longBody(context),
                actions: (sheetContext, setSheetState) => Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      key: const Key('sheet-sticky-confirm'),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('保存'),
                    ),
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('AppSheet 大弹层 sticky 底部按钮区（docs/21 §3）', () {
    testWidgets('内容超长时按钮行固定在弹层底部，滚内容不动它', (tester) async {
      await _openFormSheet(tester);

      final confirm = find.byKey(const Key('sheet-sticky-confirm'));
      expect(confirm, findsOneWidget);
      final bottomBefore = tester.getBottomLeft(confirm).dy;
      final bodyTopBefore = tester
          .getTopLeft(find.byKey(const Key('sheet-row-0')))
          .dy;

      // 滚动弹层内容：按钮行位置不变（sticky），内容确实滚上去了。
      final scrollable = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollable, const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(
        tester.getBottomLeft(confirm).dy,
        closeTo(bottomBefore, 0.5),
        reason: 'sticky 底栏不随内容滚动位移',
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('sheet-row-0'))).dy,
        lessThan(bodyTopBefore - 100),
        reason: '内容确实滚动了（否则 sticky 断言是空转）',
      );
    });

    testWidgets('按钮行仍在弹层内、在内容之下（语义顺序不变）', (tester) async {
      await _openFormSheet(tester);

      final sheetRect = tester.getRect(find.byType(BottomSheet));
      final confirmRect = tester.getRect(
        find.byKey(const Key('sheet-sticky-confirm')),
      );
      expect(confirmRect.bottom, lessThanOrEqualTo(sheetRect.bottom + 0.5));
      expect(confirmRect.top, greaterThan(sheetRect.top));

      final bodyRect = tester.getRect(find.byKey(const Key('sheet-row-0')));
      expect(confirmRect.top, greaterThan(bodyRect.top));
    });

    testWidgets('body 与 actions 共享同一 StateSetter 状态', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => AppSheet.showForm<void>(
                    context,
                    title: '共享状态',
                    body: (context, setSheetState) => TextButton(
                      key: const Key('sheet-body-toggle'),
                      onPressed: () => setSheetState(() => toggled = true),
                      child: Text(toggled ? '已开启' : '未开启'),
                    ),
                    actions: (context, setSheetState) =>
                        Text(toggled ? '按钮已开启' : '按钮未开启'),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('未开启'), findsOneWidget);
      expect(find.text('按钮未开启'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sheet-body-toggle')));
      await tester.pumpAndSettle();
      // body 里的 setSheetState 必须让 sticky 区的按钮行同步重建。
      expect(find.text('已开启'), findsOneWidget);
      expect(find.text('按钮已开启'), findsOneWidget);
    });

    testWidgets('窄屏 320dp + 大字体 2.0×：sticky 底栏不溢出', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      tester.view.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);

      await _openFormSheet(tester);
      expect(find.byKey(const Key('sheet-sticky-confirm')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AppSheet 把手拖拽（docs/21 §2.9）', () {
    testWidgets('按住把手拖动跟手，松手回弹（整层不接管拖拽）', (tester) async {
      await _openFormSheet(tester);

      final handle = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 32 &&
            w.constraints?.maxHeight == 4,
      );
      expect(handle, findsOneWidget);

      final title = find.text('大弹层');
      final before = tester.getTopLeft(title).dy;
      await tester.drag(handle, const Offset(0, 40));
      await tester.pump();
      final during = tester.getTopLeft(title).dy;
      expect(during, greaterThan(before), reason: '拖动中跟手位移');

      // 位移不足关闭阈值 → 松手回弹回原位。
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title).dy, closeTo(before, 0.5));
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('层内下拉不关弹层（整层不接管纵向拖拽）', (tester) async {
      await _openFormSheet(tester);

      final scrollable = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollable, const Offset(0, 200));
      await tester.pumpAndSettle();

      // 内容已滚到顶，弹层仍在（enableDrag:true 时这一下会关掉弹层）。
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(const Key('sheet-sticky-confirm')), findsOneWidget);
    });
  });

  testWidgets('AppSheet.show 的短内容不撑高弹层（回归：不要 Flex 嵌套）', (tester) async {
    // 回归：曾把 content 包进 Flexible + SingleChildScrollView 想让长内容
    // 可滚，结果调用方自己已经在滚动视图里的弹层（training 的记录组）直接抛
    // 「Incorrect use of ParentDataWidget」——Flexible 的父节点成了
    // _SingleChildViewport 而不是 Flex。弹层壳因此保持「只摆标题/内容/按钮」
    // 的职责，滚动由需要滚动的调用方自己负责。
    await _openPlainSheet(
      tester,
      const Text('短内容', key: Key('plain-short-content')),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('plain-short-content')), findsOneWidget);
    // 壳里不该出现把内容整个包住的滚动视图。
    expect(
      find.ancestor(
        of: find.byKey(const Key('plain-short-content')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
  });

  testWidgets('调用方自己在滚动视图里时，AppSheet.show 不抛 ParentDataWidget 错', (
    tester,
  ) async {
    // 这是上一条回归的直接病因场景：内容自己带滚动。
    await _openPlainSheet(
      tester,
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 120),
        child: const SingleChildScrollView(
          child: Text('可滚动内容', key: Key('plain-scrollable-content')),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('plain-scrollable-content')), findsOneWidget);
  });
}
