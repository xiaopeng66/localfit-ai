@Tags(['capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/widgets/lf_float_actions.dart';

import 'support/round7_render.dart';

/// 2026-10-28 用户实机截图：训练页右下两枚次级浮钮（白底 + 灰边 + 灰图标）
/// 读起来像**禁用态**，圆外一圈阴影灰晕。改软底强调档（`brandSoft` 底 +
/// `mintText` 图标、去描边去阴影）后取帧自看：320×2.0 与 412×1.0 各一张
/// 训练页三枚；菜单页带字档（白卡 + 描边）一张防空改。
void main() {
  testWidgets('浮钮列 · 训练页三枚（320×2.0 与 412×1.0）+ 菜单页带字档', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    Future<void> pumpFrame(
      double width,
      double height,
      double textScale,
      List<LfFloatingAction> actions,
    ) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = Size(width * 2, height * 2);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      // 每档从空树重建（弹层/组件 State 不跨档残留）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(textScale),
          ),
          child: RepaintBoundary(
            key: round7Boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: round7CaptureTheme(AppTheme.light()),
              home: Scaffold(
                body: Stack(
                  children: [
                    // 一点页面内容做参照：浮钮是压在内容上的，别悬在纯白里看。
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('训练', style: LfText.headline),
                          const SizedBox(height: 8),
                          Text(
                            '今天的计划：推日 · 4 个动作。列表内容会滚到浮钮底下，'
                            '所以按钮必须自己带底（不能只靠描边）。',
                            style: LfText.body,
                          ),
                        ],
                      ),
                    ),
                    PositionedLfFloatingActions(actions: actions),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    final training = <LfFloatingAction>[
      LfFloatingAction(
        actionKey: const Key('training-target-progress'),
        icon: Icons.flag_outlined,
        semanticLabel: '训练达标',
        onPressed: () {},
      ),
      LfFloatingAction(
        actionKey: const Key('training-exercise-library'),
        icon: Icons.fitness_center,
        semanticLabel: '动作库',
        onPressed: () {},
      ),
      LfFloatingAction(
        actionKey: const Key('cta-new-plan'),
        icon: Icons.add,
        semanticLabel: '新建计划',
        emphasized: true,
        onPressed: () {},
      ),
    ];
    for (final (tag, w, h, ts) in const [
      ('320x2', 320.0, 640.0, 2.0),
      ('412x1', 412.0, 900.0, 1.0),
    ]) {
      await pumpFrame(w, h, ts, training);
      await captureRound7(tester, 'review-float-actions-$tag');
    }

    // 菜单页浮钮：2026-11-02 用户裁决去掉文字，只留圆形店面图标。
    await pumpFrame(412.0, 900.0, 1.0, [
      LfFloatingAction(
        actionKey: const Key('cta-manage-canteen'),
        icon: Icons.storefront_outlined,
        semanticLabel: '管理食堂目录',
        onPressed: () {},
      ),
    ]);
    await captureRound7(tester, 'review-float-actions-canteen-412x1');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
