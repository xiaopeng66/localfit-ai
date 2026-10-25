import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_selected_date.dart';

/// 记录页选中日期行（A `.selected-date`，docs/21 §5.2）。
///
/// A 的实测：`2026 / 10 / 13 · 今天`，12px `--muted`，**裸在页面上**（不是卡片），
/// 位在周条之下；「· 今天」只在选中的那一天就是今天时出现——往日翻看时
/// 不能把往日说成「今天」（诚实规则）。
void main() {
  Widget host(DateTime selected, DateTime now) => MaterialApp(
    home: Scaffold(
      body: NutritionRecordSelectedDate(selectedDate: selected, now: now),
    ),
  );

  testWidgets('选中今天：日期后接「· 今天」', (tester) async {
    await tester.pumpWidget(
      host(DateTime(2026, 10, 13), DateTime(2026, 10, 13)),
    );

    expect(
      find.byKey(const Key('nutrition-record-selected-date')),
      findsOneWidget,
    );
    final text = tester.widget<Text>(find.text('2026 / 10 / 13 · 今天'));
    expect(text.style?.fontSize, 12);
    expect(text.style?.color, LfSemanticColors.light.mutedForeground);
  });

  testWidgets('选中往日：只写日期，不写「今天」', (tester) async {
    await tester.pumpWidget(host(DateTime(2026, 9, 7), DateTime(2026, 10, 13)));

    expect(find.text('2026 / 09 / 07'), findsOneWidget);
    expect(find.textContaining('今天'), findsNothing);
  });

  testWidgets('月/日补零（A 的 `2026 / 09 / 07` 形态）', (tester) async {
    await tester.pumpWidget(host(DateTime(2026, 1, 5), DateTime(2026, 3, 2)));

    expect(find.text('2026 / 01 / 05'), findsOneWidget);
  });
}
