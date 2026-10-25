import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_entry_chooser_sheet.dart';

/// `RV4-P1-06`（`docs/57` §3 / `docs/56` R3-b）：「按菜品记录」两件事。
///
/// 1. **没有搜索框**：`DishMealPickerDialog` 是整表 `ListView`，菜多了只能滚；
/// 2. **确认时不能改餐次**：`DishMealConfirmSheet` 把 `dish.mealSlot` 当只读
///    文案，用户无法改（`slotOverride` 只吃页面传进来的 `initialSlot`）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );

  DishRecord dish(
    String id,
    String name, {
    String mealSlot = '午餐',
    double kcal = 300,
  }) => DishRecord(
    id: id,
    name: name,
    mealSlot: mealSlot,
    kcal: kcal,
    proteinG: 10,
    carbsG: 30,
    fatG: 8,
    source: 'manual',
    createdAt: DateTime.utc(2026, 10, 24, 2),
    updatedAt: DateTime.utc(2026, 10, 24, 2),
  );

  final library = [
    dish('d1', '番茄炒蛋', kcal: 220),
    dish('d2', '番茄牛腩', kcal: 480),
    dish('d3', '宫保鸡丁', kcal: 380),
    dish('d4', '清炒时蔬', kcal: 120),
  ];

  group('菜品选择弹层：必须有搜索框', () {
    testWidgets('输入「番茄」只剩番茄类（不再整表）', (tester) async {
      await tester.pumpWidget(
        host(
          DishMealPickerDialog(
            dishes: library,
            mealSlotLabel: defaultMealSlotLabel,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('dish-meal-picker-search')),
        findsOneWidget,
        reason: '菜品选择必须有搜索框（原来是无搜索的整表列表）',
      );
      await tester.enterText(
        find.byKey(const Key('dish-meal-picker-search')),
        '番茄',
      );
      await tester.pumpAndSettle();

      expect(find.text('番茄炒蛋'), findsOneWidget);
      expect(find.text('番茄牛腩'), findsOneWidget);
      expect(find.text('宫保鸡丁'), findsNothing, reason: '不匹配的菜要被过滤掉');
      expect(find.text('清炒时蔬'), findsNothing);
    });

    testWidgets('空结果给可行动的空态文案', (tester) async {
      await tester.pumpWidget(
        host(
          DishMealPickerDialog(
            dishes: library,
            mealSlotLabel: defaultMealSlotLabel,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('dish-meal-picker-search')),
        '没有这道菜',
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('dish-meal-picker-no-match')),
        findsOneWidget,
      );
    });

    testWidgets('清空查询后恢复整表', (tester) async {
      await tester.pumpWidget(
        host(
          DishMealPickerDialog(
            dishes: library,
            mealSlotLabel: defaultMealSlotLabel,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('dish-meal-picker-search')),
        '番茄',
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('dish-meal-picker-search')),
        '',
      );
      await tester.pumpAndSettle();
      expect(find.text('宫保鸡丁'), findsOneWidget);
    });
  });

  group('确认弹层：餐次必须可改', () {
    testWidgets('四枚餐次胶囊都在，点「晚餐」后返回 dinner', (tester) async {
      MealSlot? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await DishMealConfirmSheet.show(
                  context,
                  dish: library.first, // 库里的餐次是午餐
                  mealSlotLabel: defaultMealSlotLabel,
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      // 四枚胶囊各有 Key（用户要能改餐次）。
      for (final slot in MealSlot.values) {
        expect(
          find.byKey(Key('dish-meal-slot-${slot.name}')),
          findsOneWidget,
          reason: '餐次胶囊 ${slot.name} 必须在',
        );
      }
      // 默认选中的是菜品存档的餐次（午餐）。
      expect(
        tester
            .widget<LfPillButton>(
              find.ancestor(
                of: find.byKey(const Key('dish-meal-slot-lunch')),
                matching: find.byType(LfPillButton),
              ),
            )
            .selected,
        isTrue,
        reason: '默认选菜品存档的餐次（午餐）',
      );

      await tester.tap(find.byKey(const Key('dish-meal-slot-dinner')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dish-meal-confirm')));
      await tester.pumpAndSettle();

      expect(result, MealSlot.dinner, reason: '用户点的餐次必须优先于菜品存档（D9 同一口径）');
    });

    testWidgets('取消返回 null（调用方据此不写库）', (tester) async {
      MealSlot? result = MealSlot.lunch;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await DishMealConfirmSheet.show(
                  context,
                  dish: library.first,
                  mealSlotLabel: defaultMealSlotLabel,
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dish-meal-cancel')));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  });

  group('AppSheet 约定（docs/21 §3.6）', () {
    test('两个弹层都不裸用 showModalBottomSheet（必须经 AppSheet）', () {
      // `AppSheet` 固定 `useRootNavigator: true` + `sheetBottomInset`；
      // 裸 showModalBottomSheet 会挂进分支导航器，最后一行被贴底栏盖住
      // （docs/21 附录 D8 的实测坑）。这条只钉「本文件不绕开 AppSheet」。
      final source = File(
        'lib/features/nutrition/presentation/meal_entry_chooser_sheet.dart',
      ).readAsStringSync();
      expect(
        source.contains('showModalBottomSheet'),
        isFalse,
        reason: '弹层必须经 AppSheet（useRootNavigator: true + 键盘 inset）',
      );
    });
  });
}
