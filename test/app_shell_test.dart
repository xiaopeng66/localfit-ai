import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/localfit_app.dart';

void main() {
  testWidgets('shows five primary destinations and navigates between them', (
    tester,
  ) async {
    await tester.pumpWidget(const LocalFitApp());
    await tester.pumpAndSettle();

    // docs/21 §4.1：底栏五槽 = 今日/饮食/AI（凸起圆）/训练/我的。
    expect(find.text('今日'), findsAtLeastNWidgets(1));
    expect(find.text('饮食'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('训练'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('热量、营养目标和今日训练将在这里汇总。'), findsOneWidget);

    await tester.tap(find.text('饮食'));
    await tester.pumpAndSettle();
    expect(find.text('在本地记录餐食、搜索食物并查看营养历史。'), findsOneWidget);

    // 中央槽 = AI 对话（拍照识餐改为推入式二级页，docs/21 §4.1 裁决）。
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('AI 对话服务尚未配置，请先在「我的」里完成 AI 服务。'), findsOneWidget);

    await tester.tap(find.text('训练'));
    await tester.pumpAndSettle();
    expect(find.text('训练计划、逐组记录和进步趋势将在这里管理。'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    // 我的页是**可滚动的懒列表**：docs/29 §P2 把健康数据从三格瓦片换成三张图形卡
    // 之后整页变高，「AI 配置」分组落到首屏之外——懒列表根本没构建它，`find` 找不到。
    // 这里真的滚到它，而不是放宽断言或换一个靠上的标记（那样会丢掉
    // 「AI 分组在 shell 里渲染 + 未初始化错误可见」这两条原有含义）。
    final scrollable = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .first;
    for (var i = 0; i < 10 && find.text('AI 配置').evaluate().isEmpty; i++) {
      await tester.drag(scrollable, const Offset(0, -320));
      await tester.pump();
    }
    expect(find.text('AI 配置'), findsOneWidget);
    expect(find.text('AI 配置未初始化。'), findsOneWidget);
  });
}
