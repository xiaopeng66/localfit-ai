import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
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
    /// 【2026-10-25 断言语义反转（需求 7；强度不降）】原断言是「『让 AI 重新
    /// 分析』与『先不填』**同一行**（并排）」——那是 R7 的方案。
    ///
    /// 用户 2026-10-25 给了逐字要求（docs/60 §8）：「让 AI 分析」**升格**为与
    /// 「引用食物库营养」并排的**主按钮**，「先不填」**挪到右下角**。R7 的
    /// 「这两枚并排」因此不再成立；但 R7 要解决的问题（**不要上下堆叠占两行**）
    /// 仍被保住：现在是「两枚主按钮一行 + 出口单独一行」，竖向占位与原来相同。
    /// 断言随之改写为反向判据：**「先不填」必须落在主按钮行之下**。
    testWidgets('「先不填」在主按钮行之下（需求 7 反转 R7 的并排）', (tester) async {
      await pump(tester);
      final analyze = tester.getRect(
        find.byKey(const Key('food-reference-analyze')),
      );
      final skip = tester.getRect(find.byKey(const Key('food-reference-skip')));
      expect(
        skip.top,
        greaterThanOrEqualTo(analyze.bottom),
        reason: '需求 7：出口挪到右下角，不再与主按钮挤同一行',
      );
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

  group('需求 7（2026-10-25）：排版按用户逐字要求改', () {
    // 用户给了明确要求（docs/60 §8 的表）：
    //   1. 标题与卡片之间那句「本地匹配到食物库条目…」**删掉**；
    //   2. 两个主按钮（引用食物库营养 / 让 AI 分析）**同一行、样式一致**；
    //   3. 「先不填」挪到**右下角**。
    testWidgets('删掉「本地匹配到…」那句长文案', (tester) async {
      await pump(tester);
      expect(
        find.textContaining('本地匹配到'),
        findsNothing,
        reason: '用户点名要删的那句话不许换一种说法又回来',
      );
    });

    testWidgets('两个主按钮同一行、样式同档（都是 LfPrimaryButton）', (tester) async {
      await pump(tester);
      final adopt = tester.getRect(
        find.byKey(const Key('food-reference-adopt')),
      );
      final analyze = tester.getRect(
        find.byKey(const Key('food-reference-analyze')),
      );
      expect(
        adopt.center.dy,
        closeTo(analyze.center.dy, 1.0),
        reason: '两个主按钮必须同一行（原来一主一次、上下堆叠）',
      );
      expect(
        find.byType(LfPrimaryButton),
        findsNWidgets(2),
        reason: '两枚同档（都是 B1 主按钮），不许一个实心一个文字',
      );
      // 左右并排、不重叠。
      expect(adopt.right, lessThanOrEqualTo(analyze.left + 0.01));
    });

    testWidgets('「先不填」在右下角（不是与主按钮混在一行）', (tester) async {
      await pump(tester);
      final skip = tester.getRect(find.byKey(const Key('food-reference-skip')));
      final analyze = tester.getRect(
        find.byKey(const Key('food-reference-analyze')),
      );
      expect(
        skip.top,
        greaterThan(analyze.bottom - 0.01),
        reason: '「先不填」要在主按钮**下面**（右下角），不能混进主按钮行',
      );
      // 右对齐：右缘贴近可用区右边（容差 4dp：文字按钮自带内边距）。
      final sheet = tester.getRect(
        find.byKey(const Key('food-reference-sheet')),
      );
      expect(
        sheet.right - skip.right,
        lessThanOrEqualTo(24.0),
        reason: '「先不填」要贴右下角（离右缘 ${sheet.right - skip.right}dp）',
      );
    });

    testWidgets('三个 Key 仍在 + 320dp × 2.0 不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: FoodReferenceSheet(
                dishName: '番茄牛腩饭',
                candidates: [candidate('f1', '番茄牛腩饭')],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in const [
        'food-reference-adopt',
        'food-reference-analyze',
        'food-reference-skip',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  });
}
