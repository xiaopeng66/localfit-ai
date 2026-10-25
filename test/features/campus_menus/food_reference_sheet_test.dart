import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/presentation/food_reference_sheet.dart';

/// `RV4-P2-12`（`docs/57` §3 / `docs/56` R6 + R7）：
/// **引用食物库弹层的四处排版/信息问题**。
///
/// 1. 候选卡贴在一起（`Column` 直排，各带 1px 描边、零间距 ⇒ 视觉上共享一条边）；
/// 2. 底部两枚来源/证据徽标在建菜语境里没有信息量（菜还没营养、来源未确定）；
/// 3. 「让 AI 重新分析 / 先不填」上下堆叠占两行（应并排）；
/// 4. 匹配分行是机器口吻（「匹配分 0.95 · 精确同名」）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FoodReferenceCandidate candidate(String id, String name, {String? brand}) =>
      FoodReferenceCandidate(
        foodId: id,
        foodName: name,
        brand: brand,
        kcalPer100g: 200,
        proteinPer100g: 10,
        carbsPer100g: 20,
        fatPer100g: 8,
        state: 'verified',
        confidence: 0.95,
      );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: FoodReferenceSheet(
            dishName: '番茄牛腩饭',
            candidates: [
              candidate('f1', '番茄牛腩饭'),
              candidate('f2', '番茄牛腩', brand: '叮咚'),
              candidate('f3', '牛腩饭'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('候选卡间距（R6）', () {
    testWidgets('相邻两张候选卡之间 gap ≥ 8dp（不再贴在一起）', (tester) async {
      await pump(tester);
      final first = tester.getRect(
        find.byKey(const Key('food-reference-candidate-f1')),
      );
      final second = tester.getRect(
        find.byKey(const Key('food-reference-candidate-f2')),
      );
      expect(
        second.top - first.bottom,
        greaterThanOrEqualTo(8.0),
        reason:
            '两张卡之间的间隙 ${second.top - first.bottom} < 8dp'
            '（R6：1px 描边贴在一起像共享一条边）',
      );
    });

    testWidgets('选中态与未选中态高度一致（描边变粗不跳）', (tester) async {
      await pump(tester);
      final first = tester.getRect(
        find.byKey(const Key('food-reference-candidate-f1')),
      );
      final second = tester.getRect(
        find.byKey(const Key('food-reference-candidate-f2')),
      );
      expect(first.height, closeTo(second.height, 0.5));
    });
  });

  group('底部动作与徽标（R7）', () {
    testWidgets('「让 AI 重新分析」与「先不填」同一行', (tester) async {
      await pump(tester);
      final analyze = tester.getRect(
        find.byKey(const Key('food-reference-analyze')),
      );
      final skip = tester.getRect(find.byKey(const Key('food-reference-skip')));
      expect(
        analyze.center.dy,
        closeTo(skip.center.dy, 1.0),
        reason: '两枚次级动作要并排（R7：上下堆叠占两行）',
      );
      expect(skip.left, greaterThan(analyze.left));
    });

    testWidgets('来源/证据双徽标已退役（建菜语境无信息量）', (tester) async {
      await pump(tester);
      expect(
        find.byKey(const Key('food-reference-source')),
        findsNothing,
        reason: 'R7：删掉这两枚徽标',
      );
      expect(find.byKey(const Key('food-reference-evidence')), findsNothing);
    });

    testWidgets('匹配说明改成人话（保留精确/模糊判断）', (tester) async {
      await pump(tester);
      expect(find.textContaining('匹配分'), findsNothing, reason: 'R7：去掉机器口吻');
      expect(find.textContaining('点哪条就用它的每 100g 数据'), findsOneWidget);
      // 三枚动作 Key 全部仍在。
      expect(find.byKey(const Key('food-reference-adopt')), findsOneWidget);
      expect(find.byKey(const Key('food-reference-analyze')), findsOneWidget);
      expect(find.byKey(const Key('food-reference-skip')), findsOneWidget);
    });
  });
}
