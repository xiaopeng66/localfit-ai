import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_cover_placeholder.dart';

/// 图片占位（阶段 I-2c：取代旧生成式封面 `AppCoverArt`）。
///
/// 旧件断言的去向：
/// - 「5 种 pattern / 按名 hash 选 pattern / 名 hash 选封面六色」——
///   生成式纹理按 docs/21 §3.1 整体废弃，这些断言随件删除（新设计没有
///   「按菜名换纹理」这个行为）；
/// - 「AppPatternOverlay 纯装饰、不进语义树」——保留为「占位整件不进语义树」；
/// - 「五种 pattern 全部可渲染」——保留为「四种设计稿占位渐变全部可渲染」。
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('占位渲染渐变与图标，且整件不进语义树（纯装饰）', (tester) async {
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 160,
          height: 120,
          child: LfCoverPlaceholder(
            gradient: LfGradients.warmPlaceholder,
            icon: Icons.restaurant_outlined,
          ),
        ),
      ),
    );

    expect(find.byType(LfCoverPlaceholder), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_outlined), findsOneWidget);
    // 占位是纯装饰：子树里的 Semantics 组件（Icon 自带的那个）一个标签
    // 都不带，读屏什么都不会播报（docs/21 §5.8.3）。
    // 不用 `find.byType(Semantics) findsNothing`——Icon 内部无条件建一个
    // 空 properties 的 Semantics 组件，那是实现细节，不是契约。
    final semantics = tester.widgetList<Semantics>(
      find.descendant(
        of: find.byType(LfCoverPlaceholder),
        matching: find.byType(Semantics),
      ),
    );
    for (final node in semantics) {
      expect(node.properties.label, isNull, reason: '占位不得播报任何标签，语义由相邻菜名/标题承担');
    }
  });

  testWidgets('aspectRatio 给定后按高宽比布局；圆角生效', (tester) async {
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 300,
          child: LfCoverPlaceholder(
            gradient: LfGradients.warmPlaceholder,
            aspectRatio: 4 / 3,
            borderRadius: 16,
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(LfCoverPlaceholder));
    expect(rect.width, 300);
    expect(rect.height, closeTo(225, 0.01)); // 300 / (4/3)
    expect(find.byType(ClipRRect), findsOneWidget);
  });

  testWidgets('四种设计稿占位渐变全部可渲染（docs/21 §2.5）', (tester) async {
    final gradients = <LinearGradient>[
      LfGradients.warmPlaceholder,
      LfGradients.proteinPlaceholder(LfSemanticColors.light),
      LfGradients.mintPlaceholder(Brightness.light),
      LfGradients.fatPlaceholder(LfSemanticColors.light),
    ];
    for (final gradient in gradients) {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 120,
            height: 90,
            child: LfCoverPlaceholder(gradient: gradient),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(LfCoverPlaceholder), findsOneWidget);
    }
  });

  testWidgets('无 aspectRatio 时取满父级（外层已定尺寸）', (tester) async {
    await tester.pumpWidget(
      host(
        const SizedBox(
          width: 56,
          height: 56,
          child: LfCoverPlaceholder(
            gradient: LfGradients.warmPlaceholder,
            icon: Icons.restaurant_outlined,
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byType(LfCoverPlaceholder));
    expect(rect.width, 56);
    expect(rect.height, 56);
  });
}
