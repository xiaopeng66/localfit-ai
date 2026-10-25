import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/widgets/target_range_bar.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

/// T2（docs/32 §4 / 需求 59 / §3 D4）：目标确认抽屉图形化。
///
/// 验收语句（docs/32 §4 T2）：四个数值全部可见且与 `NutritionTargetCalculator`
/// 输出一致；范围条归一函数单测（min/max/边界）；「返回修改/确认保存」流程不回归。
///
/// 这三条各有一段：① `TargetRangeBar` 的归一函数（纯函数，边界含 max=0 /
/// min>max）；② 弹层里四个区间数字逐条渲染；③ 取消不保存、确认才保存。
void main() {
  /// 与既有 onboarding 测试同法：显式给高视口，否则默认 800×600 下
  /// 表单的提交按钮不在首屏、`scrollUntilVisible` 找不到可滚目标。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('T2 范围条归一（纯函数，docs/32 §3 D4）', () {
    test('轨道量程 = max×1.2，区间右端恒落在 1/1.2 处', () {
      final w = TargetRangeBar.weights(min: 100, max: 200)!;
      // 100 / (200×1.2) = 0.4167；200 / 240 = 0.8333。
      expect(w.left, closeTo(100 / 240, 1e-9));
      expect(w.right, closeTo(200 / 240, 1e-9));
      expect(w.right, closeTo(1 / TargetRangeBar.headroom, 1e-9));
    });

    test('不含 1.2 余量会抹平各行差异（口径的反向证据）', () {
      // 同一组数据在不同余量下右端不同；1.2 是让「右端刻度=各行 max」成立的值。
      final a = TargetRangeBar.weights(min: 112, max: 140)!;
      final b = TargetRangeBar.weights(min: 222, max: 351)!;
      expect(a.left, isNot(closeTo(b.left, 1e-6)), reason: '不同区间的左端必须不同');
      expect(a.right, closeTo(b.right, 1e-9), reason: '右端＝各行 max 的落点，恒等');
    });

    test('边界：max<=0 与 min>max 返回 null（不画假位置）', () {
      expect(TargetRangeBar.weights(min: 0, max: 0), isNull);
      expect(TargetRangeBar.weights(min: 10, max: 0), isNull);
      expect(TargetRangeBar.weights(min: 120, max: 100), isNull);
    });

    test('边界：负 min 夹到 0；极窄区间给最小可见宽度', () {
      final negative = TargetRangeBar.weights(min: -50, max: 200)!;
      expect(negative.left, 0.0);
      final narrow = TargetRangeBar.weights(min: 100, max: 100)!;
      expect(narrow.width, greaterThan(0));
      expect(narrow.left + narrow.width, lessThanOrEqualTo(1.0 + 1e-9));
    });
  });

  testWidgets('抽屉显示四个区间数值，且与计算器输出逐字一致', (tester) async {
    useTallViewport(tester);
    // 期望值**手算**（不从被测代码取，否则是镜像断言）：
    // 表单默认 = 女 / 轻度活动(1.375) / 减脂，输入 30 岁 · 175cm · 75kg。
    // BMR = 10×75 + 6.25×175 − 5×30 − 161 = 1532.75
    // TDEE = 1532.75 × 1.375 = 2107.53 ⇒ 中心 = TDEE × 0.85 = 1791.40
    // 热量 = 中心 × [0.95, 1.05] = 1701.8 / 1881.0 ⇒ 1,702–1,881
    // 蛋白 = 体重 × (1.6, 2.0) = 120 / 150；脂肪 = 体重 × (0.7, 1.0) = 52.5→53 / 75
    // 碳水 = 余量/4：(1701.8−150×4−75×9)/4 = 106.7→107；(1881−120×4−52.5×9)/4 = 232.1→232
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.onboarding,
        completeOnboarding: (_) async => const NutritionTarget(
          bmrKcal: 1533,
          tdeeKcal: 2108,
          calorieMinKcal: 1702,
          calorieMaxKcal: 1881,
          proteinMinGrams: 120,
          proteinMaxGrams: 150,
          carbsMinGrams: 107,
          carbsMaxGrams: 232,
          fatMinGrams: 53,
          fatMaxGrams: 75,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_field('年龄'), '30');
    await tester.enterText(_field('身高'), '175');
    await tester.enterText(_field('当前体重'), '75');
    // docs/32 §4 T15：主行动固定在底部，不需要再滚到底才点得到。
    await tester.tap(find.byKey(const Key('onboarding-submit')).last);
    await tester.pumpAndSettle();

    expect(find.text('确认每日目标'), findsOneWidget);
    // 四个区间：热量是主行（大号 + 千分位），三个宏量各一行。
    expect(find.text('1,702–1,881'), findsOneWidget);
    expect(find.text('120–150 g'), findsOneWidget);
    expect(find.text('107–232 g'), findsOneWidget);
    expect(find.text('53–75 g'), findsOneWidget);
    // 热量单位与三个宏量名称都在。
    expect(find.text('kcal'), findsOneWidget);
    for (final label in ['蛋白质', '碳水', '脂肪']) {
      expect(find.text(label), findsOneWidget, reason: '$label 行必须在');
    }
    // 图形化（需求 59）：四条范围条必须真的渲染出来。
    expect(find.byKey(const Key('target-summary-calorie-bar')), findsOneWidget);
    for (final key in [
      'target-summary-protein',
      'target-summary-carbs',
      'target-summary-fat',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: '$key 范围条行必须在');
    }
    // 量程刻度写的是 max×1.2 的取整值（1,881×1.2 = 2,257.2 ⇒ 2,257）。
    expect(find.text('2,257'), findsOneWidget);
  });

  testWidgets('取消（返回修改）不保存，确认保存才写入', (tester) async {
    useTallViewport(tester);
    var calls = 0;
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.onboarding,
        completeOnboarding: (_) async {
          calls++;
          return const NutritionTarget(
            bmrKcal: 1699,
            tdeeKcal: 2633,
            calorieMinKcal: 2126,
            calorieMaxKcal: 2350,
            proteinMinGrams: 120,
            proteinMaxGrams: 150,
            carbsMinGrams: 200,
            carbsMaxGrams: 300,
            fatMinGrams: 53,
            fatMaxGrams: 75,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_field('年龄'), '30');
    await tester.enterText(_field('身高'), '175');
    await tester.enterText(_field('当前体重'), '75');
    // docs/32 §4 T15：主行动固定在底部，不需要再滚到底才点得到。
    await tester.tap(find.byKey(const Key('onboarding-submit')).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('返回修改'));
    await tester.pumpAndSettle();
    expect(calls, 0, reason: '取消必须不保存');
    expect(find.text('确认每日目标'), findsNothing, reason: '取消后弹层关闭');
    // 表单还在，可以继续改。
    expect(find.text('设定你的起点'), findsOneWidget);

    // 取消后仍在同一页，直接再点固定主行动。
    await tester.tap(find.byKey(const Key('onboarding-submit')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认保存'));
    await tester.pumpAndSettle();
    expect(calls, 1, reason: '确认才保存，且只保存一次');
  });
}

/// 与既有 onboarding 测试同法：字段按 `onboarding-<label>` Key 定位
/// （`onboarding_page.dart` 的 `_numberField` 把自己的 Key 传给字段）。
Finder _field(String label) => find.byKey(Key('onboarding-$label'));
