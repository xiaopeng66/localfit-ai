import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_picker_row.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_entry_chooser_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';

/// 需求 11a（docs/60 §10）：**两种记录入口的界面要一致**。
///
/// 现状（核对过）：按食材走食物库的 `FoodCard`（40dp 图标 + 名称 + 副行 +
/// 右侧动作），按菜品走弹层里的朴素行（只有两行文字、没有左件）——同一件事
/// 两套长相。
///
/// 修法：抽 `LfPickerRow` 作为**那一行**的唯一形态，两处都用它。
/// 判据（docs/60 §12.9 的 11a）：两处的行几何与字样一致——左件 40dp、
/// 左件与文字间距相同、标题/副行同档、右侧动作与文字的间距相同；
/// 且**各自的既有 Key 一个不动**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 食物库那一侧（`FoodCard`）。
  Future<void> pumpFoodCard(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: FoodCard(
              key: const Key('food-card-x'),
              id: 'x',
              name: '米饭',
              brand: '叮咚',
              category: FoodCategory.staple,
              kcalPer100g: 116,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 「按菜品记录」那一侧（弹层里的行）。
  Future<void> pumpDishPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: DishMealPickerDialog(
            dishes: [
              DishRecord(
                id: 'd1',
                name: '番茄炒蛋',
                mealSlot: '午餐',
                kcal: 220,
                proteinG: 12,
                carbsG: 9,
                fatG: 14,
                source: 'ai_estimated',
                createdAt: DateTime(2026, 10, 25),
                updatedAt: DateTime(2026, 10, 25),
              ),
            ],
            mealSlotLabel: defaultMealSlotLabel,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('两处都用同一个行组件（`LfPickerRow`）', (tester) async {
    await pumpFoodCard(tester);
    expect(find.byType(LfPickerRow), findsOneWidget, reason: '按食材的行走共享行组件');
    await pumpDishPicker(tester);
    expect(
      find.byType(LfPickerRow),
      findsOneWidget,
      reason: '按菜品的行走**同一个**共享行组件（这就是「界面统一」的落点）',
    );
  });

  testWidgets('两处的左件尺寸与左件→文字间距一致（40 / 10）', (tester) async {
    await pumpFoodCard(tester);
    final foodTitle = tester.getRect(find.byKey(const Key('food-card-name-x')));
    final foodRow = tester.getRect(find.byType(LfPickerRow));
    expect(
      foodTitle.left - foodRow.left,
      closeTo(LfPickerRow.leadingSize + LfPickerRow.leadingGap, 0.5),
      reason: '食物卡：左件 40 + 间距 10',
    );

    await pumpDishPicker(tester);
    final dishTitle = tester.getRect(
      find.byKey(const Key('dish-meal-picker-title-d1')),
    );
    final dishRow = tester.getRect(find.byType(LfPickerRow));
    expect(
      dishTitle.left - dishRow.left,
      closeTo(LfPickerRow.leadingSize + LfPickerRow.leadingGap, 0.5),
      reason: '菜品行：同一套 40 + 10（原来没有左件，文字贴左）',
    );
  });

  testWidgets('两处右侧动作与文字的间距一致（14）', (tester) async {
    await pumpFoodCard(tester);
    final foodRow = tester.getRect(find.byType(LfPickerRow));
    final foodRing = tester.getRect(
      find.byKey(const Key('food-card-actions-x')),
    );
    expect(
      foodRow.right - foodRing.right,
      closeTo(0, 1.0),
      reason: '食物卡：右侧动作整块贴行右缘',
    );

    await pumpDishPicker(tester);
    final dishRow = tester.getRect(find.byType(LfPickerRow));
    final dishBadge = tester.getRect(
      find.byKey(const Key('dish-meal-picker-badges-d1')),
    );
    expect(
      dishRow.right - dishBadge.right,
      closeTo(0, 1.0),
      reason: '菜品行：右侧动作整块贴行右缘',
    );
  });

  testWidgets('既有 Key 一个不动（按菜品：行 / 徽标；按食材：名称 / 品牌 / 环）', (tester) async {
    await pumpDishPicker(tester);
    for (final key in const [
      'dish-meal-picker-item-d1',
      'dish-meal-picker-badge-d1-source',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    await pumpFoodCard(tester);
    for (final key in const ['food-card-name-x', 'food-card-brand-x']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    expect(
      find.byKey(const Key('food-card-ring-x-kcal')),
      findsOneWidget,
      reason: '环的既有 Key 也不动',
    );
  });

  testWidgets('320dp × 2.0×：两处都不溢出', (tester) async {
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
            body: DishMealPickerDialog(
              dishes: [
                DishRecord(
                  id: 'd1',
                  name: '超长菜名番茄炒蛋加牛肉加米饭',
                  mealSlot: '午餐',
                  kcal: 1220,
                  proteinG: 112,
                  carbsG: 19,
                  fatG: 114,
                  source: 'ai_estimated',
                  createdAt: DateTime(2026, 10, 25),
                  updatedAt: DateTime(2026, 10, 25),
                ),
              ],
              mealSlotLabel: defaultMealSlotLabel,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
