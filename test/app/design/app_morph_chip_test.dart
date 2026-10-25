import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_morph_chip.dart';

/// docs/21 §3 Chip/分段控制：胶囊吞没变形+弹簧。AppMorphChip 统一替换
/// FilterChip/ChoiceChip/ActionChip，key/label/回调语义与原生 Chip 一致。
void main() {
  testWidgets('未选中点击 → onSelected(true)，胶囊变形可 settle', (tester) async {
    var received = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMorphChip(
              key: const Key('morph-chip'),
              label: '测试标签',
              selected: false,
              onSelected: (selected) => received = selected,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('morph-chip')));
    await tester.pumpAndSettle();
    expect(received, isTrue);
  });

  testWidgets('已选中点击 → onSelected(false)', (tester) async {
    var selectedAfter = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMorphChip(
              key: const Key('morph-chip'),
              label: '测试标签',
              selected: true,
              onSelected: (selected) => selectedAfter = selected,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('morph-chip')));
    await tester.pumpAndSettle();
    expect(selectedAfter, isFalse);
  });

  testWidgets('onPressed 语义（ActionChip 替换）：点击走 onPressed', (tester) async {
    var pressed = 0;
    var selectedReceived = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMorphChip(
              key: const Key('morph-chip'),
              label: '测试标签',
              onPressed: () => pressed++,
              onSelected: (selected) => selectedReceived = selected,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('morph-chip')));
    await tester.pumpAndSettle();
    expect(pressed, 1);
    expect(selectedReceived, isFalse);
  });

  testWidgets('禁用（onSelected/onPressed 均空）：点击无回调', (tester) async {
    var pressed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMorphChip(key: const Key('morph-chip'), label: '测试标签'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('morph-chip')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(pressed, 0);
  });

  testWidgets('点击区覆盖整枚胶囊（高度不小于 32）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMorphChip(
              key: const Key('morph-chip'),
              label: '测试标签',
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final size = tester.getSize(find.byKey(const Key('morph-chip')));
    expect(size.height, greaterThanOrEqualTo(32));
  });

  // ── 描边档（docs/21 §3.12，2026-10-06 选中态重做）─────────────────────

  BoxDecoration? outlinedDecoration(WidgetTester tester, Key key) {
    for (final box in tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(AnimatedContainer),
      ),
    )) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration) return decoration;
    }
    return null;
  }

  testWidgets('outlined 选中：2px 主色描边 + 主色字 + 轻抬升，不再换底、无圆点', (tester) async {
    const key = Key('outlined-chip');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMorphChip(
              key: key,
              label: '东区食堂',
              variant: AppMorphChipVariant.outlined,
              selected: true,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final decoration = outlinedDecoration(tester, key)!;
    // 底色恒为 card（换底正是旧选中态第二个「极淡」信号的来源）。
    expect(decoration.color, LfSemanticColors.light.card);
    // 描边加粗到 2px 主色（宽度变化承担形状信息，替代被删掉的圆点）。
    expect(decoration.border, isA<Border>());
    final border = decoration.border! as Border;
    expect(border.top.width, 2);
    expect(border.top.color, LfColors.mint(Brightness.light).tone(600));
    // 轻抬升：0 1px 3px mint-500 30%。
    expect(decoration.boxShadow, hasLength(1));
    expect(decoration.boxShadow!.single.offset, const Offset(0, 1));
    expect(decoration.boxShadow!.single.blurRadius, 3);
    expect(
      decoration.boxShadow!.single.color,
      LfColors.mint(Brightness.light).tone(500).withValues(alpha: 0.30),
    );
    // 字色 = mintText（亮色 mint-700）。
    final text = tester.widget<Text>(
      find.descendant(of: find.byKey(key), matching: find.byType(Text)),
    );
    expect(text.style?.color, LfColors.mintText(Brightness.light));
    // 圆点已删：chip 内部没有圆形装饰的 Container（AnimatedContainer 自己
    // 会构建方形容器，不能按类型排除）。
    expect(
      find.descendant(
        of: find.byKey(key),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('outlined 未选中：1px 边 + foreground 字 + 无阴影（选中态才有抬升）', (
    tester,
  ) async {
    const key = Key('outlined-chip');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMorphChip(
              key: key,
              label: '西区食堂',
              variant: AppMorphChipVariant.outlined,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final decoration = outlinedDecoration(tester, key)!;
    expect(decoration.color, LfSemanticColors.light.card);
    final border = decoration.border! as Border;
    expect(border.top.width, 1);
    expect(border.top.color, LfSemanticColors.light.border);
    expect(decoration.boxShadow, isNull);
    final text = tester.widget<Text>(
      find.descendant(of: find.byKey(key), matching: find.byType(Text)),
    );
    expect(text.style?.color, LfSemanticColors.light.foreground);
  });

  testWidgets('outlined 触达线：高度 44 不因描边加粗变化', (tester) async {
    const key = Key('outlined-chip');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AppMorphChip(
              key: key,
              label: '东区食堂',
              variant: AppMorphChipVariant.outlined,
              selected: true,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(key)).height, 44);
  });
}
