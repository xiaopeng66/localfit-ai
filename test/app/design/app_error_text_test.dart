import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';

void main() {
  testWidgets('AppErrorText 居中显示传入文案并使用错误色（docs/21 §3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: AppErrorText('食物加载失败，请重试。')),
      ),
    );

    final text = tester.widget<Text>(find.text('食物加载失败，请重试。'));
    expect(text.textAlign, TextAlign.center);
    expect(text.style, isNotNull);
    expect(text.style!.color, LfSemanticColors.light.error);
    // 位于全屏 Center 内，即整体居中呈现。
    expect(
      find.ancestor(
        of: find.text('食物加载失败，请重试。'),
        matching: find.byType(Center),
      ),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('AppErrorText 长文案多行也居中对齐且不溢出', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SizedBox(
            width: 200,
            child: AppErrorText('本地食物库暂时无法匹配候选；你仍可手动记餐。'),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text('本地食物库暂时无法匹配候选；你仍可手动记餐。'));
    expect(text.textAlign, TextAlign.center);
  });

  testWidgets('AppErrorText 出现时水平抖动 2 次 4dp（docs/21 §3）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: AppErrorText('食物加载失败，请重试。')),
      ),
    );
    await tester.pump();
    // 抖动 2 周期 400ms：t=50 峰右 +4，t=150 峰左 −4，t=400 归零。
    // 用渲染位置差读位移（不耦合具体 Transform 实现类型）。
    double dxAt() => tester.getTopLeft(find.text('食物加载失败，请重试。')).dx;
    final base = dxAt();
    await tester.pump(const Duration(milliseconds: 50));
    expect(dxAt() - base, closeTo(4, 0.1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(dxAt() - base, closeTo(-4, 0.1));
    await tester.pump(const Duration(milliseconds: 250));
    expect(dxAt() - base, closeTo(0, 0.1));
  });

  testWidgets('减弱动画：AppErrorText 静止直显，不跑抖动层', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AppErrorText('食物加载失败，请重试。')),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.ancestor(
        of: find.text('食物加载失败，请重试。'),
        matching: find.byType(Transform),
      ),
      findsNothing,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('食物加载失败，请重试。'), findsOneWidget);
  });
}
