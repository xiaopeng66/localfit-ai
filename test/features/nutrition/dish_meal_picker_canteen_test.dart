import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_entry_chooser_sheet.dart';

/// **「按菜品记录」能搜到未分析的食堂菜**（2026-10-25 用户裁决 D-1 选项 2）。
///
/// 用户原话：「为什么我在食堂目录里加入的菜品，无法在这个记录一餐的按菜品
/// 记录里搜到，我不是统一了菜品库和食堂目录了吗，他们应该是一个东西，
/// 为什么那边有，这边没有」。
///
/// **根因**：`AddCanteenDishesToLibrary.run` 对**没有营养**的食堂菜
/// `continue`（`add_canteen_dishes_to_library.dart:88`）——它们不进菜品库；
/// 而「按菜品记录」只读菜品库 ⇒ 未分析的菜**永远搜不到**。
///
/// **用户裁决**：**不进库（保持菜品库干净），但记录弹层里能搜到**。
///
/// **纪律**：未分析的菜**不能直接记**——它没有营养，记下去就是 0 kcal，
/// 那会污染当天热量（属"静默写错事实"）。所以点它要给**明确的下一步**
/// （去分析），而不是假装能记。
void main() {
  DishRecord libraryDish(String name, {String id = 'd-1'}) => DishRecord(
    id: id,
    name: name,
    mealSlot: 'lunch',
    kcal: 220,
    proteinG: 12,
    carbsG: 8,
    fatG: 15,
    source: 'manual',
    createdAt: DateTime(2026, 10, 25),
    updatedAt: DateTime(2026, 10, 25),
  );

  /// 未分析的食堂菜：`evidence == null` ⇒ `hasNutrition == false`
  /// （即 `AddCanteenDishesToLibrary` 会跳过、不进菜品库的那一类）。
  CanteenDish canteenDish(String name, {String id = 'c-1'}) => CanteenDish(
    id: id,
    windowId: 'w-1',
    name: name,
    evidenceGrade: 'C',
    itemStatus: 'unresolved',
    evidence: null,
  );

  Future<DishPick?> open(
    WidgetTester tester, {
    required List<DishRecord> dishes,
    required List<CanteenDish> unanalyzed,
    String query = '',
  }) async {
    DishPick? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<DishPick>(
                  context: context,
                  builder: (_) => Dialog(
                    child: DishMealPickerDialog(
                      dishes: dishes,
                      unanalyzedCanteenDishes: unanalyzed,
                      mealSlotLabel: (slot) => slot,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    if (query.isNotEmpty) {
      await tester.enterText(
        find.byKey(const Key('dish-meal-picker-search')),
        query,
      );
      await tester.pumpAndSettle();
    }
    return result;
  }

  group('未分析的食堂菜：能搜到（D-1 选项 2）', () {
    testWidgets('出现在选择弹层里，且有自己的分组标题', (tester) async {
      await open(
        tester,
        dishes: [libraryDish('番茄炒蛋')],
        unanalyzed: [canteenDish('蘸水菜')],
      );
      expect(
        find.byKey(const Key('dish-meal-picker-canteen-section')),
        findsOneWidget,
        reason: '未分析的食堂菜要有独立分组（与菜品库区分来源）',
      );
      expect(find.text('蘸水菜'), findsOneWidget);
    });

    testWidgets('搜索能命中未分析的食堂菜', (tester) async {
      await open(
        tester,
        dishes: [libraryDish('番茄炒蛋')],
        unanalyzed: [
          canteenDish('蘸水菜'),
          canteenDish('红烧肉', id: 'c-2'),
        ],
        query: '蘸水',
      );
      expect(find.text('蘸水菜'), findsOneWidget);
      expect(find.text('红烧肉'), findsNothing, reason: '搜索要真的过滤');
    });

    testWidgets('条目上如实标「营养待分析」，不假装有数据', (tester) async {
      await open(tester, dishes: const [], unanalyzed: [canteenDish('蘸水菜')]);
      expect(
        find.textContaining('待分析'),
        findsOneWidget,
        reason: '没有营养就要如实说，不能显示「0 kcal/份」那种假数据',
      );
    });

    testWidgets('点它 → 返回「未分析的食堂菜」结果（不是菜品库那条路）', (tester) async {
      late DishPick? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await showDialog<DishPick>(
                    context: context,
                    builder: (_) => Dialog(
                      child: DishMealPickerDialog(
                        dishes: [libraryDish('番茄炒蛋')],
                        unanalyzedCanteenDishes: [canteenDish('蘸水菜')],
                        mealSlotLabel: (slot) => slot,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dish-meal-picker-canteen-c-1')));
      await tester.pumpAndSettle();
      expect(picked, isA<PickedUnanalyzedCanteenDish>());
      expect((picked! as PickedUnanalyzedCanteenDish).dish.name, '蘸水菜');
    });

    testWidgets('没有未分析菜时不出该分组（不留空标题）', (tester) async {
      await open(tester, dishes: [libraryDish('番茄炒蛋')], unanalyzed: const []);
      expect(
        find.byKey(const Key('dish-meal-picker-canteen-section')),
        findsNothing,
      );
    });

    testWidgets('菜品库那条路不变：点库里的菜仍返回 PickedLibraryDish', (tester) async {
      late DishPick? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  picked = await showDialog<DishPick>(
                    context: context,
                    builder: (_) => Dialog(
                      child: DishMealPickerDialog(
                        dishes: [libraryDish('番茄炒蛋', id: 'd-9')],
                        unanalyzedCanteenDishes: const [],
                        mealSlotLabel: (slot) => slot,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dish-meal-picker-item-d-9')));
      await tester.pumpAndSettle();
      expect(picked, isA<PickedLibraryDish>());
      expect((picked! as PickedLibraryDish).dish.name, '番茄炒蛋');
    });

    testWidgets('菜品库为空但食堂有未分析菜时，仍能看到它们', (tester) async {
      await open(tester, dishes: const [], unanalyzed: [canteenDish('蘸水菜')]);
      expect(
        find.text('蘸水菜'),
        findsOneWidget,
        reason: '菜品库空不该把食堂菜也一起藏掉——这正是用户抱怨的场景',
      );
      expect(
        find.byKey(const Key('dish-meal-picker-empty')),
        findsNothing,
        reason: '有食堂菜可显示时，不该再说「菜品库还是空的」',
      );
    });
  });
}
