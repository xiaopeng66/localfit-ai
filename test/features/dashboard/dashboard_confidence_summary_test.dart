import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_confidence_summary.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

NutritionValues _nv() => const NutritionValues(
  kcal: 100,
  proteinGrams: 5,
  carbsGrams: 10,
  fatGrams: 2,
);

MealItemRecord _item(String id) => MealItemRecord(
  id: id,
  foodName: '米饭',
  grams: 200,
  nutrition: _nv(),
  createdAt: DateTime(2026, 9, 19, 12),
  updatedAt: DateTime(2026, 9, 19, 12),
);

MealRecord _meal(String id, String source, List<MealItemRecord> items) =>
    MealRecord(
      id: id,
      localDate: '2026-09-19',
      slot: MealSlot.lunch,
      eatenAt: DateTime(2026, 9, 19, 12),
      source: source,
      createdAt: DateTime(2026, 9, 19, 12),
      updatedAt: DateTime(2026, 9, 19, 12),
      items: items,
    );

void main() {
  group('今日 ConfidenceSummary（docs/21 §3：已确认 N 项 / 估算 M 项 + 环形小图）', () {
    testWidgets('混合来源：manual 2 项 + ai_scan 1 项 → 已确认 2 / 估算 1，环 2/3', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                DashboardConfidenceSummary(
                  meals: [
                    _meal('m1', 'manual', [_item('i1'), _item('i2')]),
                    _meal('m2', 'ai_scan', [_item('i3')]),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('confidence-summary')), findsOneWidget);
      // A `app.js:123`：`已确认 N 项` + `muted` 的 ` / 估算 M 项`（不再是 `·`）。
      expect(find.text('已确认 2 项 / 估算 1 项'), findsOneWidget);

      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) =>
                          w is CustomPaint &&
                          w.painter is ConfidenceRingPainter,
                    ),
                  )
                  .painter!
              as ConfidenceRingPainter;
      expect(painter.confirmedItems, 2);
      expect(painter.totalItems, 3);
    });

    testWidgets('只有 AI 估算：诚实显示 0 已确认', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                DashboardConfidenceSummary(
                  meals: [
                    _meal('m1', 'ai_scan', [_item('i1'), _item('i2')]),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('已确认 0 项 / 估算 2 项'), findsOneWidget);
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byWidgetPredicate(
                      (w) =>
                          w is CustomPaint &&
                          w.painter is ConfidenceRingPainter,
                    ),
                  )
                  .painter!
              as ConfidenceRingPainter;
      expect(painter.confirmedItems, 0);
      expect(painter.totalItems, 2);
    });

    testWidgets('当天没有餐食：整个摘要不渲染（不显示 0/0 空转行）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [DashboardConfidenceSummary(meals: const [])],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const Key('confidence-summary')), findsNothing);
    });
  });
}
