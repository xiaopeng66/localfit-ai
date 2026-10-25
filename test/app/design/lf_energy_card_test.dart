import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_energy_card.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 共享热量卡（Round7 A `.energy-summary`）的状态徽标**分档**。
///
/// A `app.js:125`：`<span class="pill ${hasGoal&&total.kcal>state.energyGoal?
/// 'warning':'today'}">` —— 超目标换 `warning` 档（`refinement.css:3`
/// `.pill.warning{background:#FFF4D6;color:#795700}`，底色即 carbs-100）。
/// 阶段 2A 的 `LfEnergyCard` 恒渲染 `mint` 档（两页共用同一件，所以今日页
/// 的超目标帧也受影响），阶段 2B（D20）补上分档并按本文件钉住。
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

  NutritionValues consumed(double kcal) => NutritionValues(
    kcal: kcal,
    proteinGrams: 10,
    carbsGrams: 20,
    fatGrams: 5,
  );

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );

  LfBadge badge(WidgetTester tester) =>
      tester.widget<LfBadge>(find.byKey(const Key('probe-status')));

  Future<void> pump(
    WidgetTester tester,
    NutritionValues values,
    DailyNutritionTarget? goal,
  ) async {
    await tester.pumpWidget(
      host(
        LfEnergyCard(
          consumed: values,
          target: goal,
          title: '当日营养',
          cardKey: const Key('probe-card'),
          keyPrefix: 'probe',
          statusKey: const Key('probe-status'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('已超目标：徽标换 honey 档（A `pill warning` 的等价色板）', (tester) async {
    await pump(tester, consumed(2000), target);

    expect(badge(tester).text, '已超目标');
    expect(
      badge(tester).variant,
      LfBadgeVariant.honey,
      reason: 'A：超目标时 pill 走 warning 档；恒 mint 会让「超了」和「额度充足」同色',
    );
    // 底色 = carbs-100（A `#FFF4D6`）、文字 = 卡前景色（LfBadge.honey 的既有档位）。
    expect(
      badge(tester).variant == LfBadgeVariant.honey,
      isTrue,
      reason: 'honey 档 = carbs100 底（A warning 的 #FFF4D6）',
    );
  });

  testWidgets('额度充足 / 接近上限：仍是 mint 档（不是所有状态都告警）', (tester) async {
    await pump(tester, consumed(1200), target);
    expect(badge(tester).text, '额度充足');
    expect(badge(tester).variant, LfBadgeVariant.mint);

    await pump(tester, consumed(1650), target);
    expect(badge(tester).text, '接近上限');
    expect(badge(tester).variant, LfBadgeVariant.mint);
  });

  testWidgets('未设目标：mint 档 + 「未设目标」（无分母就无告警）', (tester) async {
    await pump(tester, consumed(1200), null);
    expect(badge(tester).text, '未设目标');
    expect(badge(tester).variant, LfBadgeVariant.mint);
  });
}
