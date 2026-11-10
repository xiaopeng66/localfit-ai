import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:localfit_ai/app/design/widgets/lf_calorie_ring.dart';
import 'package:localfit_ai/app/design/widgets/lf_energy_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_ring_painter.dart';
import 'package:localfit_ai/app/design/widgets/macro_bar.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

/// 需求 1（docs/60 §9，2026-10-25 用户原话）：
///
/// > 「要区间的方案，另外你的热量目标和营养推荐都要根据区间来设计，
/// > 数据一定要准，推荐一定要有依据。」
///
/// 四条判据（用户任务书 §1）：
/// 1. 仪表盘热量卡：卡头 `1,700 – 1,900`（不再单个中点）；「还可摄入」也是区间；
/// 2. 三宏量块显示区间：`90–130 g / 180–260 g / 40–70 g`；
/// 3. 进度环改**区间带**（绿带 = 目标区间，指针 = 当前位置；超上界 → 带变暖色
///    + 标「超上限 X」）；
/// 4. 卡上标**依据**（一行）；且**显示的数字与 `NutritionTargetCalculator`
///    的输出逐字相等**（不许凭空造数）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 用真实计算器算一份目标（与生产同一条链），再断言卡上显示的就是它。
  final target = const NutritionTargetCalculator().calculate(
    const NutritionTargetInput(
      age: 28,
      biologicalSex: BiologicalSex.female,
      heightCm: 165,
      weightKg: 60,
      activityLevel: ActivityLevel.moderatelyActive,
      goal: HealthGoal.loseFat,
    ),
  );

  DailyNutritionTarget dailyTarget({String? goalType = 'loseFat'}) =>
      DailyNutritionTarget(
        calorieMinKcal: target.calorieMinKcal.toDouble(),
        calorieMaxKcal: target.calorieMaxKcal.toDouble(),
        proteinMinGrams: target.proteinMinGrams.toDouble(),
        proteinMaxGrams: target.proteinMaxGrams.toDouble(),
        carbsMinGrams: target.carbsMinGrams.toDouble(),
        carbsMaxGrams: target.carbsMaxGrams.toDouble(),
        fatMinGrams: target.fatMinGrams.toDouble(),
        fatMaxGrams: target.fatMaxGrams.toDouble(),
        goalType: goalType,
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    required DailyNutritionTarget? target,
    double consumedKcal = 1200,
    double protein = 60,
    double carbs = 120,
    double fat = 40,
    Size size = const Size(430, 900),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: LfEnergyCard(
                consumed: NutritionValues(
                  kcal: consumedKcal,
                  proteinGrams: protein,
                  carbsGrams: carbs,
                  fatGrams: fat,
                ),
                target: target,
                title: '今日营养',
                cardKey: const Key('test-energy-card'),
                keyPrefix: 'test-ring',
                remainingKey: const Key('test-remaining'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data ?? '';

  testWidgets('1：卡头写**区间**（下限与上限都在同一行里）', (tester) async {
    await pumpCard(tester, target: dailyTarget());
    final range = textOf(tester, const Key('test-ring-target'));
    // 千分位与页面同一口径（四位起带逗号），所以这里按同一条格式函数比对。
    final low = withThousandsSeparator(target.calorieMinKcal);
    final high = withThousandsSeparator(target.calorieMaxKcal);
    expect(range, contains(low), reason: '下限要上屏（原来只写上限 $high）');
    expect(range, contains(high));
    expect(range, contains('–'), reason: '区间必须用区间写法（用户点名：要区间的方案）');
    // 不再有「单个上限」那种写法：整卡里这两个数字各只出现一次。
    expect(find.textContaining(high), findsOneWidget);
    expect(find.textContaining(low), findsOneWidget);
  });

  testWidgets('1：「还可摄入」也是区间（不是单值）', (tester) async {
    await pumpCard(tester, target: dailyTarget(), consumedKcal: 1200);
    final remaining = tester
        .widget<Text>(find.byKey(const Key('test-remaining')))
        .textSpan!;
    final text = remaining.toPlainText();
    final low = target.calorieMinKcal - 1200;
    final high = target.calorieMaxKcal - 1200;
    expect(text, contains('$low'), reason: '下限侧的剩余也要上屏（原来只算 max − 已摄入）');
    expect(text, contains('$high'));
  });

  testWidgets('2：三宏量块显示区间（三块都含「–」）', (tester) async {
    await pumpCard(tester, target: dailyTarget());
    final bars = tester.widgetList<MacroBar>(find.byType(MacroBar)).toList();
    expect(bars, hasLength(3));
    for (final bar in bars) {
      expect(bar.targetMin, isNotNull, reason: '${bar.label} 必须带上限（区间写法）');
      expect(
        find.descendant(
          of: find.byWidget(bar),
          matching: find.textContaining('–'),
        ),
        findsOneWidget,
        reason: '${bar.label} 的右端必须是区间写法（`min–max g`）',
      );
    }
    // 逐块核对数值来自计算器（不许凭空造数）。
    expect(
      find.descendant(
        of: find.byKey(const Key('nutrition-macro-protein')),
        matching: find.textContaining(
          '${target.proteinMinGrams}–${target.proteinMaxGrams}',
        ),
      ),
      findsOneWidget,
      reason: '蛋白质区间必须与计算器输出逐字一致',
    );
    // 三块的进度条分母仍取**上限**（有意取舍：进度条要单一分母，取上限是
    // 保守做法且与「不超上限」一致）。
    for (final bar in bars) {
      expect(bar.targetMin, isNotNull);
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('nutrition-macro-carbs')),
        matching: find.textContaining(
          '${target.carbsMinGrams}–${target.carbsMaxGrams}',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('nutrition-macro-fat')),
        matching: find.textContaining(
          '${target.fatMinGrams}–${target.fatMaxGrams}',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('3：进度环是**区间带 + 深色进度弧**（不是单值进度弧）', (tester) async {
    await pumpCard(tester, target: dailyTarget());
    final ring = tester.widget<LfCalorieRing>(find.byType(LfCalorieRing));
    expect(ring.targetMinKcal, target.calorieMinKcal, reason: '环要知道下限才能画区间带');
    expect(ring.targetKcal, target.calorieMaxKcal);
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(LfCalorieRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((paint) => paint.painter)
        .whereType<LfRingPainter>()
        .single;
    expect(painter.bandStart, isNotNull, reason: '绿带 = 目标区间');
    expect(painter.bandEnd, isNotNull);
    // 【2026-10-31 用户：浅带与环同宽 + 不要多余的点】指针（圆钮）整件
    // 退役——深色弧的圆头线帽就是尖端标记，带与弧同宽后圆钮只会鼓出环外。
    expect(painter.pointerRatio, isNull, reason: '指针已退役');
  });

  testWidgets('3：超上界时带变暖色 + 标「超上限 X」', (tester) async {
    await pumpCard(
      tester,
      target: dailyTarget(),
      consumedKcal: target.calorieMaxKcal + 120,
    );
    final painter = tester
        .widgetList<CustomPaint>(
          find.descendant(
            of: find.byType(LfCalorieRing),
            matching: find.byType(CustomPaint),
          ),
        )
        .map((paint) => paint.painter)
        .whereType<LfRingPainter>()
        .single;
    expect(
      painter.bandColor,
      LfSemanticColors.light.warning,
      reason: '超上界 ⇒ 带变暖色（不是继续画绿）',
    );
    expect(
      find.textContaining('超上限 120'),
      findsOneWidget,
      reason: '要标出超了多少（用户说的「超上限 X」）',
    );
  });

  // 【断言改写（不是删）】判据从「依据要上卡」改为「依据不上卡」：
  // 用户 2026-10-28 原话「这里文字换行了，不要显示左边那个说明」。
  // 「推荐要有依据」的承诺不变——由 docs/60 §9 的数据核实表 +
  // `NutritionTargetCalculator` 单测（本文件其余用例：卡上数字与计算器
  // 逐字相等）承担；卡面只留数字，不再占一行公式。
  testWidgets('4：卡上不印公式说明（依据由数据核实表 + 计算器单测承担）', (tester) async {
    await pumpCard(tester, target: dailyTarget());
    expect(
      find.textContaining('Mifflin–St Jeor'),
      findsNothing,
      reason: '公式说明已撤下（脚注换行难看），依据改由 docs/60 §9 承担',
    );
  });

  testWidgets('4：未设目标时如实说「尚未设定目标」，且不编区间', (tester) async {
    await pumpCard(tester, target: null);
    expect(find.textContaining('尚未设定目标'), findsWidgets);
    expect(find.textContaining('Mifflin–St Jeor'), findsNothing);
    expect(find.textContaining('–'), findsNothing);
  });

  testWidgets('2.0× / 320dp：区间写法不溢出', (tester) async {
    await pumpCard(
      tester,
      target: dailyTarget(),
      size: const Size(320, 1200),
      textScale: 2.0,
    );
    expect(tester.takeException(), isNull);
  });

  // ── 【2026-10-29 用户：区间要在进度条上显示出来】────────────────────
  // 原实现只在右端**文字**里写 `min–max g`，条本身没有任何区间痕迹——
  // 用户原话「不然我怎么知道区间在哪」。现在轨道上画 `min/max → 1.0` 的
  // 区间带（同色 35% 透明度），实心填充仍是当前值。
  testWidgets('5：宏量轨道画区间带（宽度 = 1 − min/max）', (tester) async {
    await pumpCard(tester, target: dailyTarget());
    final bars = tester.widgetList<MacroBar>(find.byType(MacroBar)).toList();
    for (final bar in bars) {
      final band = find.descendant(
        of: find.byWidget(bar),
        matching: find.byKey(const Key('macro-bar-range-band')),
      );
      expect(band, findsOneWidget, reason: '${bar.label} 轨道必须有区间带');
      final fraction = tester.widget<FractionallySizedBox>(
        find
            .ancestor(of: band, matching: find.byType(FractionallySizedBox))
            .first,
      );
      final expected = 1 - bar.targetMin! / bar.target!;
      expect(
        fraction.widthFactor,
        closeTo(expected, 0.0001),
        reason: '${bar.label} 带从下限画到上限（widthFactor = 1 − min/max）',
      );
    }
  });

  testWidgets('5：没有下限（单值目标）时不画区间带', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MacroBar(
            label: '蛋白质',
            color: const Color(0xFFFF8A65),
            current: 60,
            target: 130,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('macro-bar-range-band')), findsNothing);
  });

  testWidgets('5：min == max（退化区间）不画带', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MacroBar(
            label: '蛋白质',
            color: const Color(0xFFFF8A65),
            current: 60,
            target: 130,
            targetMin: 130,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('macro-bar-range-band')), findsNothing);
  });

  testWidgets('5：圆环指针改圆钮（半径随线宽，下限 5dp）', (tester) async {
    // 旧指针 = stroke/3（10dp 轨道上 ~3px 细刻度），压在区间带上不可辨。
    expect(LfRingPainter.knobRadius(10), closeTo(8.5, 0.001));
    expect(LfRingPainter.knobRadius(4), 5.0);
    expect(
      LfRingPainter.knobRadius(10),
      greaterThan(10 / 3),
      reason: '圆钮必须明显大于旧细刻度',
    );
  });

  /// 【复核缺陷 6】未设目标时三宏量右端写「/ 0 g」——那是一个**假目标**
  /// （用户强调过「算不出来就说数据不足，不许给假数字」）。没有目标就只写当前值。
  testWidgets('复核：未设目标时三宏量不写「/ 0 g」（不编假目标）', (tester) async {
    await pumpCard(tester, target: null);
    expect(
      find.textContaining('/ 0 g'),
      findsNothing,
      reason: '「/ 0 g」会被读成「目标 0 克」——那是编的',
    );
    expect(find.textContaining('60'), findsWidgets, reason: '当前值仍要显示');
  });
}
