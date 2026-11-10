@Tags(['capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/widgets/lf_float_actions.dart';
import 'package:localfit_ai/app/design/widgets/lf_energy_card.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/custom_meal_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/dish_meal_editor_sheet.dart';

import 'support/round7_render.dart';

/// 2026-10-28 第二批实机反馈取帧（用户四条原话）：
/// 1. 浮钮「不在按钮中间」→ 图标 Center 兜底；
/// 2. 营养卡脚注「文字换行了，不要显示左边那个说明」→ 只剩图标钮 + 还可摄入；
/// 3. 「按菜品记录」要「按食材记录这样」→ 同构表单（胶囊+搜索+已添加+合计+保存）；
/// 4. 「自定义一顿也是一样」→ 合计卡同构确认。
/// 三档宽度逐张看过后归档 docs/evidence/2026-10-28-redesign/frames/。
void main() {
  testWidgets('浮钮居中 + 脚注图标 + 按菜品表单 + 自定义一顿', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    Future<void> pumpFrame(
      double width,
      double height,
      double textScale,
      Widget child,
    ) async {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = Size(width * 2, height * 2);
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, height),
            textScaler: TextScaler.linear(textScale),
          ),
          child: RepaintBoundary(
            key: round7Boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: round7CaptureTheme(AppTheme.light()),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    // 1. 浮钮三枚（320×2.0 重点看 flag/哑铃字形是否居中）。
    // 与旧取帧件同构的 Stack：Scaffold body 给满尺寸，Positioned 的
    // bottom: 80 才落在屏幕底；正文两行让 Stack 内容自然。
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            home: Scaffold(
              body: Stack(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('训练', style: LfText.headline),
                        SizedBox(height: 8),
                        Text('今天的计划：推日 · 4 个动作。浮钮压在内容上。', style: LfText.body),
                      ],
                    ),
                  ),
                  PositionedLfFloatingActions(
                    actions: [
                      LfFloatingAction(
                        actionKey: const Key('training-target-progress'),
                        icon: Icons.flag_outlined,
                        semanticLabel: '训练达标',
                        onPressed: () {},
                      ),
                      LfFloatingAction(
                        actionKey: const Key('training-exercise-library'),
                        icon: Icons.fitness_center,
                        semanticLabel: '动作库',
                        onPressed: () {},
                      ),
                      LfFloatingAction(
                        actionKey: const Key('cta-new-plan'),
                        icon: Icons.add,
                        semanticLabel: '新建计划',
                        emphasized: true,
                        onPressed: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await captureRound7(tester, 'review2-float-centered-320x2');

    // 2. 脚注：有编辑入口（图标 + 还可摄入）与无入口（只剩一句话）两态。
    final target = const DailyNutritionTarget(
      calorieMinKcal: 1500,
      calorieMaxKcal: 1800,
      proteinMinGrams: 90,
      proteinMaxGrams: 130,
      carbsMinGrams: 180,
      carbsMaxGrams: 260,
      fatMinGrams: 40,
      fatMaxGrams: 70,
      goalType: 'loseFat',
    );
    await pumpFrame(
      412,
      900,
      1.0,
      LfEnergyCard(
        consumed: const NutritionValues(
          kcal: 1200,
          proteinGrams: 60,
          carbsGrams: 120,
          fatGrams: 40,
        ),
        target: target,
        title: '今日营养',
        cardKey: const Key('cap-energy'),
        keyPrefix: 'cap-ring',
        onEditTarget: () {},
      ),
    );
    await captureRound7(tester, 'review2-foot-with-entry-412x1');

    await pumpFrame(
      320,
      900,
      2.0,
      LfEnergyCard(
        consumed: const NutritionValues(
          kcal: 1200,
          proteinGrams: 60,
          carbsGrams: 120,
          fatGrams: 40,
        ),
        target: target,
        title: '今日营养',
        cardKey: const Key('cap-energy'),
        keyPrefix: 'cap-ring',
      ),
    );
    await captureRound7(tester, 'review2-foot-no-entry-320x2');

    // 3. 按菜品表单（两菜 + 已添加一菜，含合计）。
    DishRecord dish(String id, String name, {double kcal = 220}) => DishRecord(
      id: id,
      name: name,
      mealSlot: '午餐',
      kcal: kcal,
      proteinG: 12,
      carbsG: 30,
      fatG: 8,
      source: 'manual',
      createdAt: DateTime.utc(2026, 10, 28, 2),
      updatedAt: DateTime.utc(2026, 10, 28, 2),
    );
    await pumpFrame(
      320,
      900,
      2.0,
      DishMealEditorSheet(
        dishes: [dish('d1', '番茄炒蛋'), dish('d2', '番茄牛腩', kcal: 480)],
        localDate: '2026-10-28',
        initialSlot: MealSlot.lunch,
        onAddDish: (_, {slotOverride}) async {},
      ),
    );
    await captureRound7(tester, 'review2-dish-editor-320x2');
    // 点一道菜进来 → 滚到下半部（已添加卡 + 合计 + 保存），逐项核对同构。
    await tester.tap(find.byKey(const Key('dish-meal-picker-item-d1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('dish-meal-totals')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await captureRound7(tester, 'review2-dish-editor-added-320x2');

    // 4. 自定义一顿（合计卡同构核对）。
    await pumpFrame(
      320,
      900,
      2.0,
      CustomMealSheet(
        localDate: '2026-10-28',
        initialSlot: MealSlot.lunch,
        onSubmit: (_) async => null,
      ),
    );
    await captureRound7(tester, 'review2-custom-meal-320x2');
    // 滚到合计卡（与按食材同构的核对点）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('custom-meal-totals')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await captureRound7(tester, 'review2-custom-meal-totals-320x2');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
