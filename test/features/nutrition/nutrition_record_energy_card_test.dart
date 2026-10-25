import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_ring_painter.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_energy_card.dart';

/// 记录页顶部卡：Round7 A `energy(ui.date)`（阶段 2B **D10**）。
///
/// A 的记录页与今日页画的是**同一个 `energy()`**：标题按
/// `date === today ? '今日' : '当日'` 选词，卡体、脚注、占比全同。阶段 2A
/// 已经把卡体收敛成共享件 `LfEnergyCard`，本文件盯住记录页那一侧的接线：
///
///  * 标题分档（今日 / 当日）与两页各自的历史 Key；
///  * **退役口径**：hero 的「三段统计 + 进度条」是自绘件，2B 起由热量卡承载
///    ——已摄入/目标在环心与脚注、百分比在环心第三行、剩余额度在脚注右侧。
///    所以 `nutrition-record-hero*` 六个 Key 一个都不许再出现（旧件整个删掉，
///    不是留着不看）；
///  * D20：状态徽标分档（超目标 ⇒ honey）。记录页是**第二个**受影响的宿主，
///    单独盯一次是因为今天/当日两处标题不同、卡不同实例，两处都要分档才对；
///  * 诚实规则不变（docs/21 §5.1）：无目标不画弧、不编百分比，脚注写
///    「尚未设定目标 / 设置目标后查看进度」。
void main() {
  const target = DailyNutritionTarget(
    calorieMinKcal: 1500,
    calorieMaxKcal: 1800,
    proteinMinGrams: 50,
    proteinMaxGrams: 60,
    carbsMinGrams: 180,
    carbsMaxGrams: 200,
    fatMinGrams: 40,
    fatMaxGrams: 50,
  );

  /// 宏量随热量等比缩放（0 kcal ⇒ 三项全 0）：「暂无记录」占位只在**真的没有
  /// 可计算总量**时出现，热量为 0 而宏量不为 0 的组合其实算得出占比。
  NutritionValues consumed(double kcal) => NutritionValues(
    kcal: kcal,
    proteinGrams: kcal * 0.08,
    carbsGrams: kcal * 0.25,
    fatGrams: kcal * 0.03,
  );

  Widget host({
    DateTime? selectedDate,
    DateTime? now,
    double kcal = 450,
    DailyNutritionTarget? goal = target,
  }) {
    final date = selectedDate ?? DateTime(2026, 9, 12);
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: NutritionRecordEnergyCard(
          consumed: consumed(kcal),
          target: goal,
          selectedDate: date,
          now: now ?? date,
        ),
      ),
    );
  }

  LfRingPainter ring(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find
          .descendant(
            of: find.byKey(const Key('lf-calorie-ring')),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    return paint.painter! as LfRingPainter;
  }

  testWidgets('今天是「今日营养」、历史日是「当日营养」（A `date===today`）', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('今日营养'), findsOneWidget);
    expect(find.text('当日营养'), findsNothing);

    // 选中的 09-12 是「过去」，now 已经走到 09-13。
    await tester.pumpWidget(
      host(selectedDate: DateTime(2026, 9, 12), now: DateTime(2026, 9, 13)),
    );
    await tester.pumpAndSettle();
    expect(find.text('当日营养'), findsOneWidget);
    expect(find.text('今日营养'), findsNothing);
  });

  testWidgets('记录页锚点：卡 / 环心三段 / 脚注 / 占比 / 状态都在（hero Key 全部退役）', (tester) async {
    await tester.pumpWidget(host(kcal: 450));
    await tester.pumpAndSettle();

    for (final key in [
      'nutrition-record-energy',
      'nutrition-record-energy-consumed',
      'nutrition-record-energy-percent',
      'nutrition-record-energy-target',
      'nutrition-record-energy-remaining',
      'nutrition-record-energy-ratios',
      'nutrition-record-energy-status',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    // hero 六个 Key 退役：卡体换了，旧锚点必须一起消失（留着等于两套契约）。
    for (final key in [
      'nutrition-record-hero',
      'nutrition-record-hero-consumed',
      'nutrition-record-hero-target',
      'nutrition-record-hero-remaining',
      'nutrition-record-hero-bar',
      'nutrition-record-hero-percent',
      'nutrition-record-hero-bar-target',
    ]) {
      expect(find.byKey(Key(key)), findsNothing, reason: '退役：$key');
    }

    // 三段统计的事实落到哪：环心（已摄入 / 百分比）、脚注（目标 / 剩余）。
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('nutrition-record-energy-consumed')),
          )
          .data,
      '450',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('nutrition-record-energy-percent')),
          )
          .data,
      '25%',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('nutrition-record-energy-target')))
          .data,
      '目标 1,800 kcal',
    );
    expect(find.text('还可摄入 1,350 kcal', findRichText: true), findsOneWidget);
    // 450/1800 = 0.25：弧长拿未截断的原比例（画不画得满是画家的事）。
    expect(ring(tester).ratio, closeTo(0.25, 1e-9));
  });

  testWidgets('无目标：不画弧、无百分比，脚注写「尚未设定目标 / 设置目标后查看进度」', (tester) async {
    await tester.pumpWidget(host(goal: null));
    await tester.pumpAndSettle();

    expect(ring(tester).ratio, 0);
    expect(
      find.byKey(const Key('nutrition-record-energy-percent')),
      findsNothing,
      reason: '没有分母就没有百分比（旧 hero 的等价契约）',
    );
    // 「还可摄入 N kcal」是派生量：分母不存在时这一行不存在，锚点也随之退场
    // （把同一个 Key 挂到占位句上会让「-remaining」指代两种不同的东西）。
    expect(
      find.byKey(const Key('nutrition-record-energy-remaining')),
      findsNothing,
      reason: '无目标时没有「还可摄入」这一行',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('nutrition-record-energy-target')))
          .data,
      '尚未设定目标',
    );
    expect(find.text('设置目标后查看进度'), findsOneWidget);
    expect(
      tester
          .widget<LfBadge>(
            find.byKey(const Key('nutrition-record-energy-status')),
          )
          .text,
      '未设目标',
    );
  });

  testWidgets('目标上限为 0 同样不画（0 是合法输入，不是合法分母）', (tester) async {
    await tester.pumpWidget(
      host(
        goal: const DailyNutritionTarget(
          calorieMinKcal: 0,
          calorieMaxKcal: 0,
          proteinMinGrams: 0,
          proteinMaxGrams: 0,
          carbsMinGrams: 0,
          carbsMaxGrams: 0,
          fatMinGrams: 0,
          fatMaxGrams: 0,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(ring(tester).ratio, 0);
    expect(
      find.byKey(const Key('nutrition-record-energy-percent')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('D20：记录页超目标同样换 honey 档，且不带火苗图标（A 无图标）', (tester) async {
    await tester.pumpWidget(host(kcal: 2000));
    await tester.pumpAndSettle();

    final badge = tester.widget<LfBadge>(
      find.byKey(const Key('nutrition-record-energy-status')),
    );
    expect(badge.text, '已超目标');
    expect(badge.variant, LfBadgeVariant.honey);
    expect(badge.icon, isNull, reason: 'A 的状态 pill 没有前置图标');
  });

  testWidgets('零摄入：占比行写「暂无记录」占位，不编 0%/0%/0%', (tester) async {
    await tester.pumpWidget(host(kcal: 0));
    await tester.pumpAndSettle();

    expect(find.text('暂无记录，记录后显示营养占比'), findsOneWidget);
    // 有摄入时同一 Key 上是真实占比行（能量占比 = 4/4/9 口径）。
    await tester.pumpWidget(host(kcal: 450));
    await tester.pumpAndSettle();
    expect(find.text('能量占比'), findsOneWidget);
    expect(find.text('暂无记录，记录后显示营养占比'), findsNothing);
  });
}
