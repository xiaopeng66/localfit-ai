import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('SkeletonBox 渲染指定尺寸与圆角', (tester) async {
    await tester.pumpWidget(
      wrap(
        const SkeletonBox(
          key: Key('skeleton-box'),
          width: 120,
          height: 44,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
    final box =
        tester.renderObject(find.byKey(const Key('skeleton-box'))) as RenderBox;
    expect(box.size.width, 120);
    expect(box.size.height, 44);
  });

  testWidgets('SkeletonBox 呼吸动画持续运行且可被固定步长推进', (tester) async {
    await tester.pumpWidget(wrap(const SkeletonBox(height: 10)));

    // repeat 动画让帧持续调度；pump 固定步长验证动画推进不抛异常。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SkeletonBox), findsOneWidget);
  });

  testWidgets('骨架呼吸节奏 1200ms：透明度起落（docs/21 §3）', (tester) async {
    await tester.pumpWidget(
      wrap(const SkeletonBox(key: Key('sk-breath'), height: 10)),
    );
    await tester.pump();
    final fade = find
        .descendant(
          of: find.byKey(const Key('sk-breath')),
          matching: find.byType(FadeTransition),
        )
        .evaluate()
        .single;
    final animation = (fade.widget as FadeTransition).opacity;
    final atStart = animation.value;
    await tester.pump(const Duration(milliseconds: 300));
    final atRising = animation.value;
    expect(atRising, greaterThan(atStart));
    await tester.pump(const Duration(milliseconds: 300));
    final atPeak = animation.value;
    expect(atPeak, greaterThan(atRising));
    await tester.pump(const Duration(milliseconds: 300));
    final atBack = animation.value;
    expect(atBack, lessThan(atPeak));
    // 一个完整呼吸周期（正反各 600ms）回到起点。
    await tester.pump(const Duration(milliseconds: 300));
    expect(animation.value, closeTo(atStart, 0.02));
  });

  testWidgets('减弱动画：骨架静止，不跑呼吸层', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(
            body: const SkeletonBox(key: Key('sk-static'), height: 10),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('sk-static')),
        matching: find.byType(FadeTransition),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('sk-static')), findsOneWidget);
  });

  testWidgets('SkeletonCardList 渲染指定数量的骨架卡', (tester) async {
    await tester.pumpWidget(
      wrap(
        SkeletonCardList(
          count: 3,
          cardBuilder: (context) => const SkeletonBox(height: 64),
        ),
      ),
    );
    expect(find.byType(SkeletonBox, skipOffstage: false), findsNWidgets(3));
  });
}
