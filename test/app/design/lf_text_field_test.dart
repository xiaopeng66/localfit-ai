import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';

/// [LfTextField] 的形态契约（docs/21 §3.10 输入框类 / docs/28 §3.1）。
///
/// 这个件存在的理由与 `AppNumberField` 同源：Material 的浮动 `labelText` 会在
/// 聚焦/有值时升到输入框顶边**之上**，骑在描边上（用户 2026-10-03 点名的
/// 「添加窗口」就是这个形态）。所以这里把选中的方案锁死——标签在框外上方、
/// 常态无描边、聚焦才有 ring——并把「到底哪种状态在框沿画了什么」用**像素**
/// 证一次，而不是只断言主题表里存了什么。
void main() {
  Widget host(Widget child, {bool dark = false}) => MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );

  /// 整列（框外标签 + 输入框）套一层 RepaintBoundary，便于取像素。
  Widget probeHost(Widget child, {bool dark = false}) => host(
    RepaintBoundary(key: const Key('probe-boundary'), child: child),
    dark: dark,
  );

  InputDecoration effectiveDecoration(WidgetTester tester) =>
      tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;

  int channelDistance(Color a, Color b) =>
      ((a.r - b.r).abs() * 255).round() +
      ((a.g - b.g).abs() * 255).round() +
      ((a.b - b.b).abs() * 255).round();

  /// 框沿像素：在 `edgeY` 上下 ±2px 里取「最不像填充色」的那一行（跳过全透明
  /// 像素——boundary 只画自己那块，框沿上方是 alpha=0 的空白，把它当「最不像
  /// 填充色」会得到一条假描边）。
  ///
  /// 四条实测教训（都在本用例最初几版假红里踩过）：
  ///
  /// 1. `toImage` 是**真异步**（要走 engine 的图像编码），在 widget test 的假
  ///    时钟里永远不完成——必须套 `tester.runAsync`，否则整条用例卡到超时
  ///    （实测 10 分钟无返回）。
  /// 2. 图像坐标是**相对 RepaintBoundary** 的，而 `tester.getRect` 给的是全屏
  ///    坐标。忘了减掉 boundary 的原点，采到的永远是框内的填充色，于是「聚焦
  ///    后没有 ring」这个假结论看起来无比确凿。
  /// 3. 描边**骑在框沿上**：2px 聚焦环落在 `field.top` 与 `field.top+1` 两行
  ///    （真实像素 `2fbe8f`），1px 错误描边落在 `field.top` 一行
  ///    （`f44336`）。只钉某一行会在换线宽/换设备时得到假结论，所以扫一小段。
  /// 4. 聚焦态 + errorText 走的是 `focusedErrorBorder`（主题原先没定义这一档，
  ///    实测聚焦后框沿一条边都不画），已按 docs/28 §3.2 的意图补进主题。
  Future<Color> readEdgeColor(
    WidgetTester tester, {
    required double x,
    required double edgeY,
    required Color fill,
  }) async {
    final origin = tester.getTopLeft(find.byKey(const Key('probe-boundary')));
    final color = await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('probe-boundary')),
      );
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final scale = image.width / boundary.size.width;
      final px = ((x - origin.dx) * scale).round().clamp(0, image.width - 1);
      var best = fill;
      var bestDistance = -1;
      for (var dy = -2; dy <= 2; dy++) {
        final py = ((edgeY + dy - origin.dy) * scale).round().clamp(
          0,
          image.height - 1,
        );
        final index = (py * image.width + px) * 4;
        final alpha = data!.getUint8(index + 3);
        // 全透明 = boundary 之外/未绘制区域，不是「描边」。
        if (alpha == 0) continue;
        final sample = Color.fromARGB(
          alpha,
          data.getUint8(index),
          data.getUint8(index + 1),
          data.getUint8(index + 2),
        );
        final distance = channelDistance(sample, fill);
        if (distance > bestDistance) {
          bestDistance = distance;
          best = sample;
        }
      }
      return best;
    });
    return color!;
  }

  testWidgets('标签固定在输入框外上方，placeholder 留在框内', (tester) async {
    await tester.pumpWidget(
      host(
        const LfTextField(
          fieldKey: Key('probe'),
          label: '窗口名称',
          hintText: '例：一楼快餐',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byKey(const Key('probe')));
    final label = tester.getRect(find.text('窗口名称'));
    expect(
      label.bottom,
      lessThanOrEqualTo(field.top),
      reason: '标签必须在框外上方；压到框沿就是用户抱怨的那行小字',
    );
    // 提示语在框内（与标签分居两处），不会挤掉也不需要浮动。
    final hint = tester.getRect(find.text('例：一楼快餐'));
    expect(hint.top, greaterThanOrEqualTo(field.top));
  });

  testWidgets('常态描边 = A 的 1dp `--border`（框沿可辨，但不是 ring 色）', (tester) async {
    await tester.pumpWidget(
      probeHost(const LfTextField(fieldKey: Key('probe'), label: '窗口名称')),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byKey(const Key('probe')));
    // Round7 A（`styles.css:422` `.form-field input{border:1px solid
    // var(--border)}`）：常态**有** 1dp 描边（旧 docs/21 §3.3 的「无边框 +
    // muted 底」被 A 覆盖：A 用 `--bg` 底 + 1dp 描边表达「内陷格」）。
    expect(
      effectiveDecoration(tester).enabledBorder!.borderSide,
      BorderSide(color: context.lf.border),
      reason: '常态框沿 = 1dp `--lf-border`',
    );

    final field = tester.getRect(find.byKey(const Key('probe')));
    final edge = await readEdgeColor(
      tester,
      x: field.center.dx,
      edgeY: field.top,
      fill: context.lf.muted,
    );
    expect(
      channelDistance(edge, context.lf.border),
      lessThan(24),
      reason: '常态框沿像素就是 `--lf-border`（实际 $edge）',
    );
    expect(
      channelDistance(edge, context.lf.primary),
      greaterThan(60),
      reason: '常态框沿不该出现 primary 聚焦环',
    );
    expect(
      channelDistance(edge, LfColors.mintText(Brightness.light)),
      greaterThan(60),
      reason: '常态框沿也不该出现 `--brand-strong` 聚焦环（A 的 focus 色）',
    );
  });

  testWidgets('聚焦才出现 ring（像素证据 + 颜色取自主题 token）', (tester) async {
    await tester.pumpWidget(
      probeHost(const LfTextField(fieldKey: Key('probe'), label: '窗口名称')),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byKey(const Key('probe')));
    final field = tester.getRect(find.byKey(const Key('probe')));
    final before = await readEdgeColor(
      tester,
      x: field.center.dx,
      edgeY: field.top,
      fill: context.lf.muted,
    );

    await tester.tap(find.byKey(const Key('probe')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<InputDecorator>(find.byType(InputDecorator)).isFocused,
      isTrue,
      reason: '点击后输入框确实进入聚焦态（否则下面的像素差异不成立）',
    );
    final after = await readEdgeColor(
      tester,
      x: field.center.dx,
      edgeY: field.top,
      fill: context.lf.muted,
    );
    expect(
      channelDistance(after, before),
      greaterThan(60),
      reason: '聚焦后框沿必须出现可观测的 ring（前 $before / 后 $after）',
    );

    // ring 的取值来自主题单源，不是硬编码：2px + 主题 focusedBorder 的颜色。
    final theme = Theme.of(context).inputDecorationTheme;
    expect(effectiveDecoration(tester).focusedBorder!.borderSide.width, 2);
    expect(
      effectiveDecoration(tester).focusedBorder!.borderSide.color,
      theme.focusedBorder!.borderSide.color,
    );
    expect(
      channelDistance(after, theme.focusedBorder!.borderSide.color),
      lessThan(90),
      reason: '框沿画的就是主题里的 ring 色（实际 $after）',
    );
  });

  testWidgets('错误双表达：框沿 error 色 + 框下文案，且框内仍可编辑', (tester) async {
    final controller = TextEditingController(text: '西区食堂');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      probeHost(
        LfTextField(
          fieldKey: const Key('probe'),
          label: '窗口名称',
          controller: controller,
          errorText: '请填写窗口名称。',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 表达一：框下文案。
    expect(find.text('请填写窗口名称。'), findsOneWidget);
    // 表达二：框沿 1px error 色（同样取自主题 token）。
    final context = tester.element(find.byKey(const Key('probe')));
    final theme = Theme.of(context).inputDecorationTheme;
    expect(
      effectiveDecoration(tester).errorBorder!.borderSide.color,
      theme.errorBorder!.borderSide.color,
    );
    expect(effectiveDecoration(tester).errorBorder!.borderSide.width, 1);

    final field = tester.getRect(find.byKey(const Key('probe')));
    final edge = await readEdgeColor(
      tester,
      x: field.center.dx,
      edgeY: field.top,
      fill: context.lf.muted,
    );
    expect(
      channelDistance(edge, theme.errorBorder!.borderSide.color),
      lessThan(90),
      reason: '错误态框沿应画 error 色（实际 $edge）',
    );

    // 框内保持可编辑：错误不是禁用态，用户可以直接改完再提交。
    await tester.enterText(find.byKey(const Key('probe')), '东区食堂');
    await tester.pump();
    expect(controller.text, '东区食堂');

    // 聚焦 + 错误：Material 走 `focusedErrorBorder`（主题原先没有这一档，
    // 实测聚焦后框沿一条边都不画）。补上后框沿仍是 error 色——「刚敲完就点
    // 保存报错」恰恰总是聚焦态。
    await tester.tap(find.byKey(const Key('probe')));
    await tester.pumpAndSettle();
    expect(
      effectiveDecoration(tester).focusedErrorBorder!.borderSide.color,
      theme.focusedErrorBorder!.borderSide.color,
    );
    final focusedEdge = await readEdgeColor(
      tester,
      x: field.center.dx,
      edgeY: field.top,
      fill: context.lf.muted,
    );
    expect(
      channelDistance(focusedEdge, context.lf.error),
      lessThan(90),
      reason: '聚焦 + 错误时框沿也要画 error 色（实际 $focusedEdge）',
    );
  });

  testWidgets('标签并进输入框语义节点，且只播报一次', (tester) async {
    final controller = TextEditingController(text: '西区食堂');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        LfTextField(
          fieldKey: const Key('probe'),
          label: '窗口名称',
          controller: controller,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    final nodes = tester.semantics
        .simulatedAccessibilityTraversal()
        .map((node) => node.getSemanticsData())
        .map((data) => '${data.label}|${data.value}')
        .where((entry) => entry != '|')
        .toList();
    handle.dispose();

    expect(nodes, contains('窗口名称|西区食堂'));
    expect(
      nodes.where((node) => node.startsWith('窗口名称|') && node.endsWith('|')),
      isEmpty,
      reason: '框外标签文字不能再作为独立节点播报一遍',
    );
  });

  testWidgets('明暗两态都取主题 token（同源码、不同色板）', (tester) async {
    Future<Color> fillColor(WidgetTester tester, {required bool dark}) async {
      await tester.pumpWidget(
        host(
          const LfTextField(fieldKey: Key('probe'), label: '窗口名称'),
          dark: dark,
        ),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byKey(const Key('probe')));
      final decoration = effectiveDecoration(tester);
      expect(
        decoration.fillColor,
        Theme.of(context).inputDecorationTheme.fillColor,
        reason: '填充色必须来自主题单源',
      );
      expect(decoration.fillColor, context.lf.background);
      return decoration.fillColor!;
    }

    final light = await fillColor(tester, dark: false);
    final dark = await fillColor(tester, dark: true);
    expect(light, isNot(dark), reason: '两套色板必须解析出不同取值');
  });
}
