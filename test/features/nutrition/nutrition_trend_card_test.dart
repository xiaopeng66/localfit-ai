import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_trend_card.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

import '../../support/round7_render.dart';

/// 记录页七日趋势卡（阶段 2B 步骤 4）：视觉 = Round7 A `nutritionTrend()`
/// 在浏览器里的实测值（360dp）。
///
/// 实测要点：
///  * 卡 `padding:16`；标题行两端对齐：h2「七日摄入趋势」15px w600 + 右侧
///    quiet-label「6 天有记录」12px muted —— **无副标题、无达标徽标**（达标
///    天数在分析卡里，D13）；
///  * 图区 145（`padding:22 0`）：轴宽 30 且 `translateY(-5px)`、柱区 101
///    带 1px `--border` 下边框、柱列 7 等分列间 8px；
///  * 柱：宽 60%（上限 24）、圆角 4/4/0/0，高 = 无记录 3% / 有记录
///    `max(2%, kcal / 纵轴上界)`，色 = 无记录 `--border` / 超目标 `--protein`
///    / 其余 `--brand`；
///  * 日号在柱区之下 6px；目标虚线 1px dashed `--muted`；9px「目标 1,800」
///    2026-10-16 起**移到柱区之上**（用户要求「放在柱状图界外」）右端齐平；
///    图下 hint 10px（有目标时多一句「虚线为每日目标」）；
///  * 空态 `min-height:80` +「近 7 日还没有记录。」，轴 / 日号 / hint 都不渲染。
///
/// 大字号（自检 2 ③）：轴宽按实测文字宽让位（上限 28% 卡宽）、日号折行扩高、
/// 目标标签允许画进图区上方的 22px 内边距——都不裁字、不缩字号、不溢出。
void main() {
  /// 真字体只装一次（`FontLoader` 是全局注册表，逐用例重复装载是浪费）。
  var fontsLoaded = false;

  CalorieTrendBars bars({Map<int, double> days = const {}, double? target}) =>
      buildCalorieTrendBars(
        records: [
          for (final day in days.entries)
            DailyIntakeRecord(
              localDate: '2026-09-${day.key.toString().padLeft(2, '0')}',
              kcal: day.value,
              proteinGrams: 0,
              carbsGrams: 0,
              fatGrams: 0,
            ),
        ],
        endDate: DateTime(2026, 9, 13),
        targetMaxKcal: target,
      );

  Future<void> pump(
    WidgetTester tester, {
    Map<int, double> days = const {},
    double? target,
    double textScale = 1.0,
    double width = 360,
  }) async {
    // 几何断言里有「轴宽 = A 实测的 30」这类文字尺寸判据——默认测试字体
    // （FlutterTest）每字 1em，「2,200」要 51dp 才画得下，实测值就对不上。
    // 装载本机 CJK 字体后度量与整页捕获、与真实渲染同一套。
    if (!fontsLoaded) {
      await tester.runAsync(loadRound7Fonts);
      fontsLoaded = true;
    }
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(LfDimens.pagePadding),
                child: NutritionTrendCard(
                  bars: bars(days: days, target: target),
                  targetKcal: target,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final cardKey = find.byKey(const Key('nutrition-record-trend-chart'));
  final trackedKey = find.byKey(const Key('nutrition-record-trend-tracked'));
  final chartAreaKey = find.byKey(
    const Key('nutrition-record-trend-chart-area'),
  );
  final axisKey = find.byKey(const Key('nutrition-record-trend-axis'));
  final plotKey = find.byKey(const Key('nutrition-record-trend-plot'));

  testWidgets('标题行 = 「七日摄入趋势」+ 右侧「N 天有记录」；副标题与达标徽标退役（A 实测 / D13）', (
    tester,
  ) async {
    await pump(tester, days: {7: 2000, 8: 500}, target: 1800);

    expect(find.text('七日摄入趋势'), findsOneWidget);
    expect(find.text('近 7 日热量趋势'), findsNothing, reason: '旧标题退役');
    final tracked = tester.widget<Text>(trackedKey);
    expect(tracked.data, '2 天有记录');
    expect(tracked.style?.fontSize, 12);
    expect(tracked.style?.color, LfSemanticColors.light.mutedForeground);
    // 标题行两端对齐：quiet-label 右边贴卡片内容右缘。
    expect(
      tester.getRect(cardKey).right - tester.getRect(trackedKey).right,
      LfDimens.cardPadding,
    );
    // 有目标也不再出现「达标 N/7」徽标与「摄入 vs 目标」副标题。
    expect(find.byKey(const Key('nutrition-record-trend-goal')), findsNothing);
    expect(find.textContaining('摄入 vs 目标'), findsNothing);
    expect(
      find.descendant(of: cardKey, matching: find.textContaining('达标')),
      findsNothing,
      reason: '达标天数由分析卡承载（D13）',
    );
  });

  testWidgets('几何：图区 145、柱区 101（1px 下边框）、轴宽 30 且顶对齐（2026-10-22 退场上移）', (
    tester,
  ) async {
    await pump(tester, days: {7: 2000}, target: 1800);

    expect(tester.getSize(chartAreaKey).height, 145);
    expect(tester.getSize(plotKey).height, 101);
    expect(tester.getSize(axisKey).width, 30);
    expect(tester.getSize(axisKey).height, 101);

    final plot = tester.getRect(plotKey);
    final axis = tester.getRect(axisKey);
    expect(
      plot.left - axis.right,
      8,
      reason: 'A `.nutrition-bar-chart{gap:8px}`',
    );
    // 2026-10-22 用户：「纵坐标高度有点偏移」⇒ 轴整体上移 5dp（旧
    // `translateY(-5px)`）退场，轴盒与柱区顶对齐；四档刻度由绝对定位
    // 钉在网格线上（0/⅓/⅔/1）。
    expect(plot.top - axis.top, 0);

    final deco = tester.widget<Container>(plotKey).decoration! as BoxDecoration;
    expect(deco.border!.bottom.color, LfSemanticColors.light.border);
    expect(deco.border!.bottom.width, 1);
  });

  testWidgets('纵轴四档「2,200 / 1,467 / 733 / 0」；日号在柱区之下 6dp 且 10px', (
    tester,
  ) async {
    await pump(tester, days: {7: 2000}, target: 1800);

    // 上界 = max(2200, 目标 1800, 峰值 2000) = 2200（D17）。
    // 2026-10-22 用户：「纵轴值有点少，就收尾两个，增加为 4 个点」⇒ 四档
    // = 上界 / ⅔ 上界 / ⅓ 上界 / 0（与体重图 axisFor 同口径）。
    // 锚文本（不可见）+ Positioned 刻度各有一份 ⇒ 用「至少一份」口径。
    expect(find.text('2,200'), findsWidgets);
    expect(find.text('1,467'), findsOneWidget, reason: '2200 × 2/3');
    expect(find.text('733'), findsOneWidget, reason: '2200 × 1/3');
    expect(find.text('0'), findsOneWidget);
    final plot = tester.getRect(plotKey);
    for (final day in ['7', '13']) {
      final label = tester.getRect(find.text(day));
      expect(label.top - plot.bottom, 6, reason: 'A `top:calc(100% + 6px)`');
      expect(tester.widget<Text>(find.text(day)).style?.fontSize, 10);
    }
  });

  testWidgets('目标虚线位置 = 目标/上界 × 柱区高（以 9px 标签钉住）；无目标则线与标签都不画', (tester) async {
    await pump(tester, days: {7: 2000}, target: 1800);

    final label = find.text('目标 1,800');
    expect(label, findsOneWidget);
    expect(tester.widget<Text>(label).style?.fontSize, 9);
    final plot = tester.getRect(plotKey);
    expect(
      tester.getRect(label).right,
      plot.right,
      reason: 'A `.target-line>span{right:0}`',
    );
    // 2026-10-16 用户：「目标标签能不能放在柱状图界外（往上移）」——标签从
    // 虚线旁移出柱区，落到**柱区之上**（图区上内边距里），右端仍与柱区齐平。
    // 虚线本身留在原处（它才是「目标在哪」的事实）。
    expect(
      plot.top - tester.getRect(label).bottom,
      closeTo(4, 0.01),
      reason: '标签底距柱区顶 4dp',
    );
    expect(
      tester.getRect(label).bottom,
      lessThanOrEqualTo(plot.top),
      reason: '标签整块在柱区外（不再压柱身）',
    );

    await pump(tester, days: {7: 2000});
    expect(find.textContaining('目标'), findsNothing);
    expect(find.textContaining('虚线'), findsNothing);
  });

  testWidgets('hint：有目标多说一句「虚线为每日目标」；空态 80dp 且不渲染轴/日号/hint（A 实测）', (
    tester,
  ) async {
    await pump(tester, days: {7: 2000}, target: 1800);
    final hint = find.text('单位 kcal · 灰色短柱为无记录 · 虚线为每日目标');
    expect(hint, findsOneWidget);
    expect(tester.widget<Text>(hint).style?.fontSize, 10);

    await pump(tester, days: const {});
    expect(find.text('近 7 日还没有记录。'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('nutrition-record-trend-empty')))
          .height,
      80,
    );
    expect(find.textContaining('单位 kcal'), findsNothing, reason: '空态不渲染 hint');
    expect(chartAreaKey, findsNothing, reason: '空图表不画坐标轴');
    expect(axisKey, findsNothing);
  });

  testWidgets('大字号 2.0×：轴让位（>30 且 ≤28% 卡宽）、图区不裁字、无溢出', (tester) async {
    await pump(tester, days: {7: 2000}, target: 1800, textScale: 2.0);

    expect(tester.takeException(), isNull);
    final axisWidth = tester.getSize(axisKey).width;
    final cardWidth = tester.getSize(cardKey).width;
    expect(axisWidth, greaterThan(30), reason: '1.0× 恒 30，大字要按实测文字宽让位');
    expect(
      axisWidth,
      lessThanOrEqualTo((cardWidth - LfDimens.cardPadding * 2) * 0.28 + 0.01),
    );
    expect(
      tester.getSize(chartAreaKey).height,
      greaterThanOrEqualTo(145),
      reason: '大字下日号折行则图区扩高，不裁字',
    );
  });

  testWidgets('大字号 2.0×/320dp：日号必须单行且画在图区之内（旧件折行溢出到 hint 上）', (tester) async {
    // 审看发现的缺陷 ⑧（阶段 2B 步骤 5 的 320dp×2.0× 帧）：柱区在窄屏大字号下
    // 被轴标签吃掉宽度后，每个日号只有 ~20dp，`10` 这样的两位日号会**折成两行**；
    // 而日号是 `Stack` 里的溢出定位（`Clip.none`），折出的第二行直接画到
    // 卡片下方的 hint 文案上（「单位 kcal · 灰色短柱为无记录」被数字压住）。
    // 上面那条 2.0× 用例宿主 360dp，正好差一点点不出事——320dp 才会露。
    await pump(
      tester,
      days: {7: 2000, 8: 500, 13: 1800},
      target: 1800,
      textScale: 2.0,
      width: 320,
    );

    expect(tester.takeException(), isNull);
    final chartAreaBottom = tester.getRect(chartAreaKey).bottom;
    for (final day in ['7', '8', '9', '10', '11', '12', '13']) {
      final label = find.text(day);
      expect(label, findsOneWidget, reason: '日号 $day 必须在');
      final style = tester.widget<Text>(label).style!;
      // 本帧实际生效的缩放（含系统钳制），而不是我设的那个数：断言量的
      // 是「这一行排了几行字」，尺子必须是渲染用的那把。
      final oneLine =
          MediaQuery.textScalerOf(tester.element(label))
              .scale(style.fontSize!) *
          (style.height ?? 1.0);
      expect(
        tester.getSize(label).height,
        lessThanOrEqualTo(oneLine * 1.05),
        reason: '日号 $day 折成了多行（320dp×2.0× 的实测宽度只够一行）',
      );
      expect(
        tester.getRect(label).bottom,
        lessThanOrEqualTo(chartAreaBottom + 0.01),
        reason: '日号 $day 画到了图区之外（会压住 hint）',
      );
    }
  });

  testWidgets('柱高与柱色的判定是纯函数（无记录 3% / 有记录 max(2%, kcal/上界) / 超目标 protein）', (
    tester,
  ) async {
    // 上界 = max(2200, 1800, 3000) = 3000。
    final b = bars(days: {7: 2000, 8: 0, 9: 3000}, target: 1800);
    expect(trendBarFraction(b, 0), closeTo(2000 / 3000, 0.0001));
    expect(trendBarFraction(b, 1), 0.02, reason: '记了 0 kcal 是「有记录」，走 2% 下限');
    expect(trendBarFraction(b, 2), 1.0);
    expect(trendBarFraction(b, 3), 0.03, reason: '无记录走 3%');

    expect(trendBarTone(kcal: null, targetKcal: 1800), TrendBarTone.empty);
    expect(
      trendBarTone(kcal: 1800, targetKcal: 1800),
      TrendBarTone.track,
      reason: '等于目标不算超',
    );
    expect(trendBarTone(kcal: 1801, targetKcal: 1800), TrendBarTone.over);
    expect(
      trendBarTone(kcal: 9999),
      TrendBarTone.track,
      reason: '没设目标就没有「超目标」可言',
    );
  });

  testWidgets('文字等价物随标题更新（读屏听到「七日摄入趋势」）', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, days: {7: 2000, 8: 500}, target: 1800);

    expect(find.bySemanticsLabel(RegExp('^七日摄入趋势：')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('周一 2000 kcal')),
      findsOneWidget,
      reason: '逐日事实仍在（柱高只是缩放图）',
    );
    expect(
      find.bySemanticsLabel(RegExp('周三 无记录')),
      findsOneWidget,
      reason: '无记录的日子也要读出来（不能只靠灰柱子）',
    );
    handle.dispose();
  });
}
