@Tags(['capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_meals_card.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_next_meal_card.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_target_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/meal_record_card.dart';

import 'support/round7_render.dart';

/// 2026-10-31 用户反馈批次的取帧件：只拍本轮改过、且用户肉眼会看的四块。
/// 不在生产代码里加任何仅为取帧服务的分支。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSurface(
    WidgetTester tester,
    Widget child, {
    required double width,
    double scale = 1,
    double height = 900,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: round7CaptureTheme(AppTheme.light()),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, height),
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  testWidgets('下一餐按时刻换餐次（午餐 / 加餐，无统计行）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      const Column(
        children: [
          DashboardNextMealCard(
            key: Key('round13-next-lunch'),
            consumedKcal: 860,
            targetKcal: 2000,
            slot: MealSlot.lunch,
          ),
          SizedBox(height: 12),
          DashboardNextMealCard(
            key: Key('round13-next-snack'),
            consumedKcal: 1780,
            targetKcal: 2000,
            slot: MealSlot.snack,
          ),
        ],
      ),
      width: 412,
    );
    await shot(
      tester,
      'round13-next-meal-dynamic',
      const Key('round13-next-lunch'),
    );
  });

  testWidgets('下一餐 320dp×2.0× 不溢出', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      const DashboardNextMealCard(
        consumedKcal: 1780,
        targetKcal: 2000,
        slot: MealSlot.snack,
      ),
      width: 320,
      scale: 2,
    );
    await shot(
      tester,
      'round13-next-meal-320x2',
      const Key('dashboard-next-meal-title'),
    );
  });

  testWidgets('空餐次卡只陈述事实（没有记一餐按钮）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    await pumpSurface(
      tester,
      const DashboardMealsCard(entries: [], meals: []),
      width: 412,
    );
    await shot(
      tester,
      'round13-meals-empty',
      const Key('dashboard-meals-empty'),
    );
  });

  testWidgets('餐卡逐食物勾选（只勾第二样）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final stamp = DateTime(2026, 10, 31, 12);
    final items = [
      for (final (name, kcal) in [('米饭', 232.0), ('鸡胸肉', 165.0)])
        MealItemRecord(
          id: 'item-$name',
          foodName: name,
          grams: 100,
          nutrition: NutritionValues(
            kcal: kcal,
            proteinGrams: 12,
            carbsGrams: 20,
            fatGrams: 4,
          ),
          createdAt: stamp,
          updatedAt: stamp,
        ),
    ];
    final meal = MealRecord(
      id: 'meal-lunch',
      localDate: '2026-10-31',
      slot: MealSlot.lunch,
      eatenAt: stamp,
      source: 'manual',
      createdAt: stamp,
      updatedAt: stamp,
      items: items,
    );
    await pumpSurface(
      tester,
      MealRecordCard(
        meals: [meal],
        selectionMode: true,
        selectedItemIds: {items.last.id},
        onToggleItemSelected: (_, _) {},
      ),
      width: 412,
    );
    await shot(
      tester,
      'round13-meal-item-selection',
      Key('meal-food-select-circle-${items.last.id}'),
    );
  });

  testWidgets('营养目标弹层新版（412 与 320×2.0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    const target = DailyNutritionTarget(
      calorieMinKcal: 1800,
      calorieMaxKcal: 2200,
      proteinMinGrams: 110,
      proteinMaxGrams: 150,
      carbsMinGrams: 210,
      carbsMaxGrams: 270,
      fatMinGrams: 50,
      fatMaxGrams: 70,
    );
    for (final (tag, width, scale) in [
      ('412x1', 412.0, 1.0),
      ('320x2', 320.0, 2.0),
    ]) {
      await pumpSurface(
        tester,
        NutritionTargetSheet(
          effectiveDate: '2026-10-31',
          current: target,
          onSave: (_) async => null,
          onRestore: () {},
        ),
        width: width,
        scale: scale,
        height: 1000,
      );
      await shot(tester, 'round13-target-sheet-$tag', const Key('target-save'));
    }
  });
}
