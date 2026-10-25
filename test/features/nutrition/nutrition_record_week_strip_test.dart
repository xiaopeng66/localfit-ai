import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_week_section.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_week_strip.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// 记录页周条（阶段 2B 步骤 3：视觉改为 Round7 A 的实测形态）。
///
/// A 的 `.date-strip`（浏览器实测，360dp）→ 本件落点：
/// - 单元格：`min-height:91px` + `padding:8px 2px` + 圆角 10，内容顶对齐
///   （底部留 ~4px 余量）；
/// - 星期字：10px `--muted`，**选中日也一样浅**（旧件选中转深色，已删）；
/// - 日期数字：15px w600，未选中 `--fg`、选中 `--brand-strong`；
/// - 选中底：`--brand-soft` 胶囊（旧件的实心 mint 圆 + 白字是上一版视觉）；
/// - 短条：12px 宽的轨道不存在——**5×24 的轨道**、条从底部向上长，
///   高度 = `clamp(kcal / 2200, 6%, 100%)`；选中日的条取 `--brand-strong`。
///
/// 三条**承重语义**（不随视觉变）：
/// 1. 左右滑切上/下一周同日、不越界到未来（旧件有、I-2b 迁移时漏掉，
///    I-2c 补回并配测试）；
/// 2. 短条比例必须按真实摄入算，无记录的日子**画 4dp 灰标记**（A 只画空，
///    本仓保留可见标记：空着与「比例极小」看起来一样，D21 已登记偏离），
///    不伪造设计稿的手写高度；
/// 3. 每天的 `Semantics` 标签写真实事实（A 的 `aria-label` 同款）：
///    「2026-09-07 2,000 kcal」/「2026-09-09 无记录」——柱高是缩放图，
///    真实数值只有这里和趋势卡给得出。
void main() {
  // 2026-09-07（周一）– 09-13（周日）；选中 09-10（周四），今天 09-10。
  final selected = DateTime(2026, 9, 10);
  final now = DateTime(2026, 9, 10);

  /// 记录日 → 当日 kcal；**缺的日子才是「无记录」**（记了 0 kcal 是另一回事，
  /// 它有自己的 6% 小条与 `0 kcal` 语义）。
  CalorieTrendBars bars({
    Map<int, double> days = const {},
    DateTime? end,
    double? targetMaxKcal = 2000,
  }) => buildCalorieTrendBars(
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
    endDate: end ?? DateTime(2026, 9, 13),
    targetMaxKcal: targetMaxKcal,
  );

  Widget host({
    required ValueChanged<DateTime> onSelect,
    CalorieTrendBars? data,
    DateTime? selectedDate,
  }) => MaterialApp(
    home: Scaffold(
      body: NutritionRecordWeekStrip(
        bars: data ?? bars(),
        selectedDate: selectedDate ?? selected,
        now: now,
        onSelect: onSelect,
      ),
    ),
  );

  // 滑动切周手势：首步 move 越过 slop 触发识别（识别当帧的位移被 drag start
  // 消费，同帧单次大步 move 的 onDragUpdate 累计恒 0），后续小步才流入累计。
  Future<void> swipeWeek(WidgetTester tester, Finder on, double dx) async {
    final gesture = await tester.startGesture(tester.getCenter(on));
    await gesture.moveBy(Offset(dx, 0));
    await tester.pump();
    await gesture.moveBy(Offset(dx, 0));
    await tester.pump();
    await gesture.moveBy(Offset(dx, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// 单元格内所有 `Container`（树序）：首个 = 选中底/单元格本体，
  /// 短条轨道与其填充（都带 `maxWidth == 5`）在最后。
  List<Container> boxesIn(WidgetTester tester, String key) => tester
      .widgetList<Container>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Container),
        ),
      )
      .toList();

  Container trackOf(WidgetTester tester, String key) =>
      boxesIn(tester, key).firstWhere((c) => c.constraints?.maxWidth == 5);

  Container fillOf(WidgetTester tester, String key) =>
      boxesIn(tester, key).lastWhere((c) => c.constraints?.maxWidth == 5);

  testWidgets('选中日 = brand-soft 胶囊 + brand-strong 数字；未选中透明（A 实测）', (
    tester,
  ) async {
    await tester.pumpWidget(host(onSelect: (_) {}));

    final cellBox = boxesIn(tester, 'meal-day-2026-09-10').first;
    final cellDec = cellBox.decoration! as BoxDecoration;
    expect(cellDec.color, LfColors.brandSoft(Brightness.light));
    expect(cellDec.borderRadius, BorderRadius.circular(10));
    expect(cellDec.border, isNull, reason: '选中日不再叠描边（胶囊已表达身份）');

    final number = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const Key('meal-day-2026-09-10')),
            matching: find.text('10'),
          )
          .first,
    );
    expect(number.style?.color, LfColors.mintText(Brightness.light));
    expect(number.style?.fontSize, 15, reason: 'A 的日期数字是 15px');
    expect(number.style?.fontWeight, FontWeight.w600);

    // 未选中日（09-09）：不铺底（A `background:none`，等价于透明）、无边框，
    // 数字取正文前景色。
    final otherBox = boxesIn(tester, 'meal-day-2026-09-09').first;
    final otherDec = otherBox.decoration! as BoxDecoration;
    expect(otherDec.color, isNull);
    expect(otherDec.border, isNull);
    final otherNumber = tester.widget<Text>(
      find
          .descendant(
            of: find.byKey(const Key('meal-day-2026-09-09')),
            matching: find.text('9'),
          )
          .first,
    );
    expect(otherNumber.style?.color, LfSemanticColors.light.foreground);
  });

  testWidgets('星期字恒为 10px muted：选中日也**不**转深色（A 实测）', (tester) async {
    await tester.pumpWidget(host(onSelect: (_) {}));

    for (final entry in {
      'meal-day-2026-09-09': '三',
      'meal-day-2026-09-10': '四',
    }.entries) {
      final label = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(Key(entry.key)),
              matching: find.text(entry.value),
            )
            .first,
      );
      expect(
        label.style?.color,
        LfSemanticColors.light.mutedForeground,
        reason: '${entry.value} 的星期字必须是 --muted（选中日也不加深）',
      );
      expect(label.style?.fontSize, 10);
      expect(label.style?.fontWeight, FontWeight.w400);
    }
  });

  testWidgets('单元格 91 高、短条轨道 5×24（A 实测几何）', (tester) async {
    await tester.pumpWidget(host(onSelect: (_) {}));

    expect(
      tester.getSize(find.byKey(const Key('meal-day-2026-09-10'))).height,
      91,
      reason: 'A 的 .date-strip button{min-height:91px}',
    );
    final track = trackOf(tester, 'meal-day-2026-09-10');
    expect(track.constraints?.maxHeight, 24);
    expect(track.constraints?.maxWidth, 5);
    // 内容顶对齐：星期字距单元格顶 8px，轨道底距单元格底 8px。
    final cell = tester.getRect(find.byKey(const Key('meal-day-2026-09-10')));
    final weekday = tester.getRect(
      find
          .descendant(
            of: find.byKey(const Key('meal-day-2026-09-10')),
            matching: find.text('四'),
          )
          .first,
    );
    expect(weekday.top - cell.top, 8);
  });

  testWidgets('短条按真实摄入算比例；无记录画 4dp 短线（诚实规则）', (tester) async {
    // 09-07 记 2000、09-08 记 500、09-10 记 2500（选中日，超 2200 基数
    // 也只画满轨道，不溢出）、09-11 记 0（有记录，画 6% 下限）。
    await tester.pumpWidget(
      host(
        onSelect: (_) {},
        data: bars(days: {7: 2000, 8: 500, 10: 2500, 11: 0}),
      ),
    );

    // 09-07: 2000/2200 → 24 * 0.909 = 21.818。
    expect(
      fillOf(tester, 'meal-day-2026-09-07').constraints?.maxHeight,
      closeTo(24 * (2000 / 2200), 0.01),
    );
    // 09-08: 500/2200 → 24 * 0.227 = 5.4545。
    expect(
      fillOf(tester, 'meal-day-2026-09-08').constraints?.maxHeight,
      closeTo(24 * (500 / 2200), 0.01),
    );
    // 09-10: 2500 超基数 → 画满 24，不溢出。
    expect(fillOf(tester, 'meal-day-2026-09-10').constraints?.maxHeight, 24);
    // 09-11: 记了 0 kcal → 6% 下限（24 * 0.06 = 1.44），不是「无记录」的 4dp。
    expect(
      fillOf(tester, 'meal-day-2026-09-11').constraints?.maxHeight,
      closeTo(24 * 0.06, 0.01),
    );
    // 无记录日（09-09）画 4dp 灰短线，不空着也不编比例。
    final empty = fillOf(tester, 'meal-day-2026-09-09');
    expect(empty.constraints?.maxHeight, 4);
    expect(
      (empty.decoration! as BoxDecoration).color,
      LfSemanticColors.light.border,
    );
  });

  testWidgets('短条分母恒为 2200（A 字面基数），不随目标/峰值缩放（A 实测）', (tester) async {
    // 目标 3000：趋势纵轴会用 max(2200, 3000) = 3000 当分母，周条仍是 2200
    // ——A 的两张图各自成图（纵轴 81.8% 的目标线也只在趋势卡里）。
    await tester.pumpWidget(
      host(
        onSelect: (_) {},
        data: bars(days: {7: 2000}, targetMaxKcal: 3000),
      ),
    );

    expect(
      fillOf(tester, 'meal-day-2026-09-07').constraints?.maxHeight,
      closeTo(24 * (2000 / 2200), 0.01),
      reason: '周条基数固定 2200；用 2000/3000 会得到 16.0，是趋势卡的分母',
    );
  });

  testWidgets('短条颜色：未选中 brand、选中 brand-strong（A 实测）', (tester) async {
    await tester.pumpWidget(
      host(
        onSelect: (_) {},
        data: bars(days: {7: 2000, 10: 2500}),
      ),
    );

    expect(
      (fillOf(tester, 'meal-day-2026-09-07').decoration! as BoxDecoration)
          .color,
      LfSemanticColors.light.primary,
    );
    expect(
      (fillOf(tester, 'meal-day-2026-09-10').decoration! as BoxDecoration)
          .color,
      LfColors.mintText(Brightness.light),
    );
    expect(
      (fillOf(tester, 'meal-day-2026-09-07').decoration! as BoxDecoration)
          .borderRadius,
      BorderRadius.circular(3),
    );
  });

  testWidgets('每日语义标签写真实事实（A 的 aria-label 同款）', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        onSelect: (_) {},
        data: bars(days: {7: 2000, 8: 500}),
      ),
    );

    expect(find.bySemanticsLabel('2026-09-07 2,000 kcal'), findsOneWidget);
    expect(find.bySemanticsLabel('2026-09-08 500 kcal'), findsOneWidget);
    expect(find.bySemanticsLabel('2026-09-09 无记录'), findsOneWidget);

    final selectedNode = tester.getSemantics(
      find.byKey(const Key('meal-day-2026-09-10')),
    );
    expect(selectedNode.flagsCollection.isButton, isTrue);
    expect(selectedNode.flagsCollection.isSelected.toBoolOrNull(), isTrue);
    final plainNode = tester.getSemantics(
      find.byKey(const Key('meal-day-2026-09-11')),
    );
    expect(plainNode.flagsCollection.isSelected.toBoolOrNull(), isFalse);
    // 未来日（09-12）语义上也标成不可用，读屏不会把人引到点不动的日期。
    expect(
      tester
          .getSemantics(find.byKey(const Key('meal-day-2026-09-12')))
          .flagsCollection
          .isEnabled
          .toBoolOrNull(),
      isFalse,
    );

    handle.dispose();
  });

  testWidgets('周条与日期行同属一个区块；日期行紧贴周条之下 8dp（A 实测）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NutritionRecordWeekSection(
            bars: bars(days: {7: 2000}),
            selectedDate: selected,
            now: now,
            onSelect: (_) {},
            onReuseHistory: () {},
          ),
        ),
      ),
    );

    final stripRect = tester.getRect(
      find.byKey(const Key('nutrition-record-week-strip')),
    );
    final dateRect = tester.getRect(
      find.byKey(const Key('nutrition-record-selected-date')),
    );
    expect(
      dateRect.top - stripRect.bottom,
      8,
      reason: 'A：16px 页间隙 − `margin-top:-8px` = 8dp',
    );
    expect(find.byKey(const Key('meal-reuse-history')), findsOneWidget);
    expect(
      find.text('2026 / 09 / 10 · 今天'),
      findsOneWidget,
      reason: '日期行写的是**选中日**（这里正是今天）',
    );
  });

  testWidgets('右滑切上一周同日；左滑不越界到未来', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(host(onSelect: (date) => picked = date));

    // 向右滑（内容右移）= 上一周同日（选中 09-10 − 7d = 09-03）。
    await swipeWeek(tester, find.byKey(const Key('meal-day-2026-09-09')), 40);
    expect(picked, DateTime(2026, 9, 3));

    // 左滑（内容左移）= 下一周同日；09-10 + 7d = 09-17 越过今天（09-10），
    // 必须不切换。
    picked = null;
    await swipeWeek(tester, find.byKey(const Key('meal-day-2026-09-09')), -40);
    expect(picked, isNull);
  });

  testWidgets('滑动位移不足阈值不切周：退化为点击（选中所指那天）', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(host(onSelect: (date) => picked = date));

    // 累计位移 ~10dp，低于 60dp 阈值 → 不切周。因为拖拽没能被识别为
    // 横向拖动，手势退化为对 09-09 的点击（选中它），而**不是**切到
    // 上一/下一周（即结果日期必须落在同一周内）。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('meal-day-2026-09-09'))),
    );
    await gesture.moveBy(const Offset(5, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(5, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 9, 9));
  });

  testWidgets('点未来日期不触发（onSelect 不被调用）', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(host(onSelect: (date) => picked = date));

    // 09-12（周六）在选中周内、晚于今天（09-10）。
    await tester.tap(find.byKey(const Key('meal-day-2026-09-12')));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });

  testWidgets('整周 7 列；今天未选中时描边圈落在单元格上（D14）', (tester) async {
    await tester.pumpWidget(
      host(onSelect: (_) {}, selectedDate: DateTime(2026, 9, 8)),
    );

    expect(
      find.byKey(const Key('nutrition-record-week-strip')),
      findsOneWidget,
    );
    for (final day in ['07', '08', '09', '10', '11', '12', '13']) {
      expect(find.byKey(Key('meal-day-2026-09-$day')), findsOneWidget);
    }
    expect(find.text('一'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);

    // 今天（09-10）不是选中日 → 单元格描边表达「今天在哪」。
    final todayDec =
        boxesIn(tester, 'meal-day-2026-09-10').first.decoration!
            as BoxDecoration;
    expect(todayDec.border, isNotNull);
    expect(todayDec.border!.top.color, LfSemanticColors.light.primary);
    expect(todayDec.border!.top.width, 1.2);
    // 选中日（09-08）用胶囊、不叠描边。
    expect(
      (boxesIn(tester, 'meal-day-2026-09-08').first.decoration!
              as BoxDecoration)
          .color,
      LfColors.brandSoft(Brightness.light),
    );
  });
}
