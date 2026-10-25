import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_weight_card.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

/// 今日页体重卡的空态行动（docs/21 §3.8「空态行动一律 B6 文字按钮」）。
///
/// 这是用户 2026-10-03 反馈里**点名**的那一颗（「今日界面的『记录第一条』」）：
/// 原文是 `FilledButton.tonal` 且没设颜色，经回落链
/// `secondaryContainer ?? secondary` 拿到与实心主按钮同色的实心块——与薄荷主题
/// 整体不搭。本断言同时钉住两件：它是**文字按钮**，且这张卡里**没有实心按钮**；
/// 改回 `FilledButton.tonal` 会在这里红（这是唯一一条能抓住该回归的断言）。
void main() {
  const emptyOverview = WeightOverview(
    measurements: [],
    latest: null,
    sevenDayAverageKg: null,
    sampleDays: 0,
  );

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );

  testWidgets('空态 CTA 是文字按钮，卡内不出现实心按钮', (tester) async {
    var recorded = 0;
    await tester.pumpWidget(
      host(
        DashboardWeightCard(
          overview: emptyOverview,
          endLocalDate: '2026-10-07',
          onRecord: () => recorded++,
        ),
      ),
    );

    final cta = find.byKey(const Key('dashboard-weight-record'));
    expect(cta, findsOneWidget);
    expect(find.text('记录第一条'), findsOneWidget);
    // `LfTextButton` 的薄封装把 key 放在**原生 `TextButton`** 上；这里的
    // `widget<TextButton>` 就是「是 B6」的判据。
    expect(tester.widget<TextButton>(cta).onPressed, isNotNull);
    expect(find.byType(FilledButton), findsNothing);

    await tester.tap(cta);
    expect(recorded, 1);
  });

  // 2026-10-09 需求 44：「添加的按钮做好看点，只要图标，不要添加两个字」。
  // 这颗新件（`LfIconButton`）与旧的 `LfTextButton` 有三处实质差别，逐条钉住：
  // ① **没有可见文字**；② 视觉圆 28dp、命中盒 44dp
  // （触达下限，见 `lf_buttons.dart` 的几何契约）；③ 语义标签仍在
  // 「添加体重」——视觉精简不许让读屏失语。
  testWidgets('添加钮是纯图标：无文字、28dp 视觉圆、44dp 命中盒、有语义标签', (tester) async {
    var addTaps = 0;
    // 语义树要先开才编得出来；句柄必须在测试体结束前显式释放
    // （绑定期末会检查，`addTearDown` 也来得及；与 `training_page_test.dart` 同法）。
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        DashboardWeightCard(
          overview: emptyOverview,
          endLocalDate: '2026-10-07',
          onRecord: () {},
          onAdd: () => addTaps++,
        ),
      ),
    );

    final add = find.byKey(const Key('dashboard-weight-add'));
    expect(add, findsOneWidget);
    // ① 卡片里不再有「添加」这两个字。
    expect(find.text('添加'), findsNothing, reason: '需求 44：只要图标，不要「添加」两个字');
    // ② 命中盒 = 44×44（`LfIconButton` 的外层 SizedBox）。
    final hit = tester.getSize(add);
    expect(hit.width, 44);
    expect(hit.height, 44);
    // 视觉圆 28dp：图标钮内部那颗 `Material` 的圆。
    final circle = find.descendant(of: add, matching: find.byType(Material));
    expect(tester.getSize(circle.first).width, 28);
    // ③ 语义标签还在（读屏读得到「添加体重」）。
    expect(find.bySemanticsLabel('添加体重'), findsOneWidget);

    await tester.tap(add);
    expect(addTaps, 1);
    semantics.dispose();
  });
}
