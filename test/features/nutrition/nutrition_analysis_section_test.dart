import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_analysis_section.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// 营养分析卡（阶段 I-2b：旧 `NutritionalTrendCard` 的诚实性断言在此重新落点）。
///
/// 旧卡断言 → 新落点：
/// - 「均值只摊在已记录的天上」：域层 `TrendCalculator`
///   （`trend_calculator_test` 已锁「7 日窗口只记 2 天 → 均值来自这 2 天」）；
///   本卡只保证**如实显示**收到的均值，不二次运算。
/// - 「无记录显示空状态而不是 0」：本卡逐格写「—」占位（下方用例）。
/// - 「7/30 窗口切换」：新设计（docs/21 §5.2）不再有窗口开关——周条负责翻日、
///   趋势卡固定近 7 日；「窗口跟随选中日」由 `record_tab_trend_race_test` 锁。
/// - 「加载失败不假装没数据」：趋势失败时记录页整卡不渲染（record_tab
///   「趋势是增强内容」的失败路径），不在卡内放错误文案。
/// - 「三枚宏量胶囊复用同一件」：对应的取代件是 `MacroBar`（design_widgets_test）。
void main() {
  IntakeTrend trend({
    required int trackedDays,
    double? kcal,
    MacroAverages? macros,
  }) => IntakeTrend(
    trackedDays: trackedDays,
    averageKcal: kcal,
    averageMacros: macros,
    goalDaysMet: null,
  );

  List<DailyIntakeRecord> records({List<double> kcals = const []}) => [
    for (var i = 0; i < kcals.length; i++)
      DailyIntakeRecord(
        localDate: '2026-09-${(25 + i).toString().padLeft(2, '0')}',
        kcal: kcals[i],
        proteinGrams: 0,
        carbsGrams: 0,
        fatGrams: 0,
      ),
  ];

  Widget host({
    required IntakeTrend trend,
    required CalorieTrendBars bars,
    double? targetMinKcal,
    double? targetMaxKcal,
  }) => MaterialApp(
    home: Scaffold(
      body: NutritionAnalysisSection(
        trend: trend,
        bars: bars,
        targetMinKcal: targetMinKcal,
        targetMaxKcal: targetMaxKcal,
      ),
    ),
  );

  testWidgets('三格统计如实显示：周均 / 达成率 / 达标天数', (tester) async {
    await tester.pumpWidget(
      host(
        trend: trend(
          trackedDays: 2,
          kcal: 754,
          macros: const MacroAverages(
            proteinGrams: 30,
            carbsGrams: 90,
            fatGrams: 20,
          ),
        ),
        bars: buildCalorieTrendBars(
          records: records(kcals: [700, 808]),
          endDate: DateTime(2026, 9, 26),
          targetMinKcal: 600,
          targetMaxKcal: 2100,
        ),
        targetMinKcal: 600,
        targetMaxKcal: 2100,
      ),
    );

    expect(find.text('周均摄入 kcal'), findsOneWidget);
    expect(find.text('754'), findsOneWidget);
    // 754 / 2100 = 35.9% → 36。
    expect(find.text('目标达成率'), findsOneWidget);
    expect(find.text('36%'), findsOneWidget);
    expect(find.text('达标天数'), findsOneWidget);
    expect(find.text('2/7'), findsOneWidget);
  });

  testWidgets('无目标无记录逐格写「—」，不编 0', (tester) async {
    await tester.pumpWidget(
      host(
        trend: trend(trackedDays: 0),
        bars: buildCalorieTrendBars(
          records: const [],
          endDate: DateTime(2026, 9, 26),
        ),
      ),
    );

    expect(find.text('—'), findsNWidgets(3));
    expect(find.text('0'), findsNothing);
    expect(find.text('0%'), findsNothing);
    expect(find.text('0/7'), findsNothing);
    // 数据不足时洞察一条都不补（不出现「近 7 日有 0 天记录」这类话）。
    expect(find.textContaining('近 7 日'), findsNothing);
  });

  testWidgets('有目标无记录：「达标 0/7」是事实，「达成率」仍是「—」', (tester) async {
    await tester.pumpWidget(
      host(
        trend: trend(trackedDays: 0),
        bars: buildCalorieTrendBars(
          records: const [],
          endDate: DateTime(2026, 9, 26),
          targetMaxKcal: 2100,
        ),
        targetMaxKcal: 2100,
      ),
    );

    // 没设目标前「0/7」才是编的；设了目标后「0 天达标」是可复算的事实。
    expect(find.text('0/7'), findsOneWidget);
    // 但均值缺失时达成率无定义，不能写 0%。
    expect(find.text('—'), findsNWidgets(2));
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('低于下限：达标仍按未超上限计，洞察单独提示', (tester) async {
    await tester.pumpWidget(
      host(
        trend: trend(trackedDays: 1, kcal: 1200),
        bars: buildCalorieTrendBars(
          records: records(kcals: [1200]),
          endDate: DateTime(2026, 9, 26),
          targetMinKcal: 1400,
          targetMaxKcal: 1800,
        ),
        targetMinKcal: 1400,
        targetMaxKcal: 1800,
      ),
    );

    // 2026-10-23 用户：「今日达标但没变 0/7」——未超上限就计入达标。
    expect(find.text('1/7'), findsOneWidget);
    // 但「吃太少」不能静默：同一句洞察里如实写出低于下限的天数。
    expect(
      find.text(
        '其中 1 天摄入未超过目标上限，另有 1 天低于目标下限 1400 kcal'
        '（未超上限，但可能吃太少）。',
      ),
      findsOneWidget,
    );
  });

  testWidgets('有数据时三条洞察都是本地事实的复述', (tester) async {
    await tester.pumpWidget(
      host(
        trend: trend(
          trackedDays: 2,
          kcal: 754,
          macros: const MacroAverages(
            proteinGrams: 30,
            carbsGrams: 90,
            fatGrams: 20,
          ),
        ),
        bars: buildCalorieTrendBars(
          records: records(kcals: [700, 808]),
          endDate: DateTime(2026, 9, 26),
          targetMinKcal: 600,
          targetMaxKcal: 2100,
        ),
        targetMinKcal: 600,
        targetMaxKcal: 2100,
      ),
    );

    expect(
      find.text('近 7 日有 2 天记录，日均摄入 754 kcal（目标 600–2100 kcal）。'),
      findsOneWidget,
    );
    expect(find.text('其中 2 天摄入未超过目标上限。'), findsOneWidget);
    // 4/4/9 占比：蛋白 120kcal / 碳水 360 / 脂肪 180，合计 660。
    expect(find.text('三大宏量热量占比：蛋白质 18%、碳水 55%、脂肪 27%。'), findsOneWidget);
  });

  // ---- 退场项：卡尾 `footer` 槽位（阶段 2B 步骤 4 拆除）----
  //
  // 该槽位承载的唯一内容是置信摘要（`DashboardConfidenceSummary`），而 A 的
  // 记录页把它画成热量卡之下的**页级一行**（`.source-summary`，见 D1x/阶段
  // 2B 设计表）。槽位连同「null 不占位 / 给定则渲染在卡尾」两条断言一起
  // 退役——被保护的**行为**（摘要在记录页可达、空列表不渲染）原样搬到了
  // `record_tab_confidence_summary_test.dart`（位置契约改为「在热量卡之下、
  // 不在分析卡内」），本文件不再重复断言一个不存在的槽位。
  testWidgets('分析卡自足：不再带任何卡尾槽位', (tester) async {
    // 卡片在真实宿主里是滚动 sliver 的孩子（高度不受限 ⇒ 卡体随内容收，
    // 不被拉满一屏），这里用滚动视图还原同一种约束。
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NutritionAnalysisSection(
              trend: trend(trackedDays: 1, kcal: 800),
              bars: buildCalorieTrendBars(
                records: records(kcals: [800]),
                endDate: DateTime(2026, 9, 26),
              ),
            ),
          ),
        ),
      ),
    );

    final card = tester.getRect(
      find.byKey(const Key('nutrition-record-analysis')),
    );
    final insight = tester.getRect(find.textContaining('近 7 日有 1 天记录'));
    // 卡底到末条洞察的距离 = 卡内边距 16 + 洞察行距 8，中间没有第三件东西
    // （退役的 `footer` 槽位若不占位地回去了，这里会多出 16+）。
    expect(
      card.bottom - insight.bottom,
      LfDimens.cardPadding + LfDimens.spaceSmall,
    );
  });

  testWidgets('大字号 2.0×/320dp：三格数值缩放而不是裁字（旧件把「30%」裁成「3…」）', (tester) async {
    // 审看发现的缺陷 ⑨（阶段 2B 步骤 5 的 320dp×2.0× 帧）：三格统计的值行是
    // `maxLines:1 + ellipsis`，大字号窄屏下「30%」被静默裁成「3…」——数值是
    // 事实，裁掉就是把 30% 说成 3（同一帧里「695」与「0/7」恰好放得下，
    // 只有中间这格出事）。修法是按实际宽度缩放（FittedBox.scaleDown）。
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: NutritionAnalysisSection(
                trend: trend(
                  trackedDays: 2,
                  kcal: 695,
                  macros: const MacroAverages(
                    proteinGrams: 25,
                    carbsGrams: 90,
                    fatGrams: 20,
                  ),
                ),
                bars: buildCalorieTrendBars(
                  records: records(kcals: [700, 808]),
                  endDate: DateTime(2026, 9, 26),
                  targetMinKcal: 600,
                  targetMaxKcal: 2100,
                ),
                targetMinKcal: 600,
                targetMaxKcal: 2100,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 值文案由卡自己算（达成率 = 周均 / 目标上界），这里取实际渲染出来的
    // 那一枚而不是写死字符串——压力断言量的是**这枚字符串**的真实宽度。
    // 限定在**中间那格**（达成率）：卡里还有一条洞察句自带「%」（宏量占比），
    // 直接找 `%` 会同时命中它。
    final value = find.descendant(
      of: find.byType(MutedBlock).at(1),
      matching: find.textContaining('%'),
    );
    expect(value, findsOneWidget, reason: '达成率格必须渲染出带 % 的数值');
    final text = tester.widget<Text>(value);
    final tile = tester.getRect(
      find.ancestor(of: value, matching: find.byType(MutedBlock)),
    );
    // 压力确实是真实的：这个字符串在 2.0× 下的自然宽度超过格内可用宽度
    // （`MutedBlock` 左右各 8dp 内衬），不做处理就只能裁字或溢出。
    final painter = TextPainter(
      text: TextSpan(text: text.data, style: text.style),
      textScaler: MediaQuery.textScalerOf(tester.element(value)),
      textDirection: TextDirection.ltr,
    )..layout();
    final available = tile.width - LfDimens.spaceSmall * 2;
    expect(
      painter.width,
      greaterThan(available),
      reason: '2.0×/320dp 下「${text.data}」自然宽 ${painter.width} 超过格内宽 $available',
    );
    expect(
      text.overflow,
      isNot(TextOverflow.ellipsis),
      reason: '数值不许裁字（修前这里是 ellipsis，「30%」渲染成「3…」）',
    );
    expect(
      tester
          .widget<FittedBox>(
            find.ancestor(of: value, matching: find.byType(FittedBox)),
          )
          .fit,
      BoxFit.scaleDown,
      reason: '按实际宽度缩放，缺省字号不动',
    );
  });

  test('achievementPercent：无目标或目标为 0 时无定义', () {
    expect(
      NutritionAnalysisSection.achievementPercent(
        averageKcal: 754,
        targetMaxKcal: null,
      ),
      isNull,
    );
    expect(
      NutritionAnalysisSection.achievementPercent(
        averageKcal: 754,
        targetMaxKcal: 0,
      ),
      isNull,
    );
    expect(
      NutritionAnalysisSection.achievementPercent(
        averageKcal: null,
        targetMaxKcal: 2100,
      ),
      isNull,
    );
    expect(
      NutritionAnalysisSection.achievementPercent(
        averageKcal: 754,
        targetMaxKcal: 2100,
      ),
      36,
    );
  });
}
