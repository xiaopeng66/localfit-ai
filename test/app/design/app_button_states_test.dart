import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/design/widgets/app_button_states.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

/// 三个点的渲染 top-left，按 x 排序（左→右 = 点 0/1/2）。
/// 读点的 Container（Transform 的孩子）——Transform 自身的 localToGlobal
/// 不含自身 translate（translate 只作用于孩子的 paint 变换链）。
List<double> dotDys(WidgetTester tester, Finder loader) {
  final dots = find
      .descendant(of: loader, matching: find.byType(Container))
      .evaluate();
  final entries = <({double x, double y})>[
    for (final element in dots)
      (
        x: (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dx,
        y: (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
      ),
  ]..sort((a, b) => a.x.compareTo(b.x));
  return [for (final entry in entries) entry.y];
}

void main() {
  testWidgets('三点跳动依次上浮：t=150ms 首点峰 −4dp、后两点未起（docs/21 §3）', (tester) async {
    await tester.pumpWidget(wrap(const AppButtonDotsLoader(key: Key('dots'))));
    await tester.pump();
    final base = dotDys(tester, find.byKey(const Key('dots')));
    // t=0 相位：点 0/1 在负半周钳到 0；点 2 相位差 2π/3 尚在中途
    // （sin(−4π/3)=+0.866）已上浮 −3.46——拖尾点 t=0 不在零位。
    expect(base[0], closeTo(0, 0.15));
    expect(base[1], closeTo(0, 0.15));
    expect(base[2], closeTo(-3.46, 0.15));
    await tester.pump(const Duration(milliseconds: 150));
    final mid = dotDys(tester, find.byKey(const Key('dots')));
    // t=150（v=0.25）：首点到峰 −4dp，后两点归零（负半周钳到 0 不下沉）。
    expect(mid[0], closeTo(-4, 0.15));
    expect(mid[1], closeTo(0, 0.15));
    expect(mid[2], closeTo(0, 0.15));
  });

  testWidgets('减弱动画：三点静态不跳动', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: const AppButtonDotsLoader(key: Key('dots'))),
        ),
      ),
    );
    await tester.pump();
    final before = dotDys(tester, find.byKey(const Key('dots')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(dotDys(tester, find.byKey(const Key('dots'))), before);
  });

  testWidgets('成功态 ✓：300ms 弹簧缩放收束到 1.0（docs/21 §3）', (tester) async {
    await tester.pumpWidget(
      wrap(AppSuccessCheck(icon: const Icon(Icons.check_circle))),
    );
    await tester.pump();
    final scaleFinder = find.ancestor(
      // 裸 harness 的 MaterialApp 自带页面转场 ScaleTransition，按图标祖先链
      // scope 到自己的缩放层。
      of: find.byIcon(Icons.check_circle),
      matching: find.byType(ScaleTransition),
    );
    expect(scaleFinder, findsOneWidget);
    final animation = tester.widget<ScaleTransition>(scaleFinder.first).scale;
    expect(animation.value, lessThan(1.0));
    await tester.pumpAndSettle();
    expect(animation.value, 1.0);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('减弱动画：✓ 直显不缩放', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: AppSuccessCheck(icon: const Icon(Icons.check_circle)),
          ),
        ),
      ),
    );
    await tester.pump();
    // 减弱下自己不渲染缩放层（MaterialApp 内置转场 ScaleTransition 不算）。
    expect(
      find.ancestor(
        of: find.byIcon(Icons.check_circle),
        matching: find.byType(ScaleTransition),
      ),
      findsNothing,
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}
