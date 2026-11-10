import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/dish_meal_editor_sheet.dart';

/// 「按菜品记录」**表单弹层**（2026-10-28 用户原话：「按菜品记录为什么弹窗
/// 还是这样，我要的是按食材记录这样，自定义一顿也是一样」）。
///
/// 旧路「选菜 → 二次确认」与本件（同构表单）的差异判据：
/// 1. **同一张表单结构**：餐次胶囊 + 搜索 + 已添加 + 合计 + 保存，
///    与 `MealEditorDialog`（按食材）同构——这是用户点名的诉求本身；
/// 2. 点结果行 = **加进来**（弹层不关），点保存才落库（逐条
///    `AddDishToMeal.run`，一次一条）；
/// 3. 餐次胶囊可改，保存把**用户选的**餐次传给写入路径（D9 同口径）；
/// 4. Key 契约（docs/21 附录 D1）：`dish-meal-editor` / `dish-meal-slot` /
///    `dish-meal-totals` 在 docs 点名，必须真有断言（ui_spec_key_sync）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  Widget host(DishMealEditorSheet sheet) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: sheet)),
  );

  testWidgets('同构表单：胶囊 + 搜索 + 已添加 + 合计 + 保存（五个部件都在）', (tester) async {
    await tester.pumpWidget(
      host(
        DishMealEditorSheet(
          dishes: [dish('d1', '番茄炒蛋')],
          localDate: '2026-10-28',
          onAddDish: (_, {slotOverride}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final key in const [
      'dish-meal-editor', // 弹层根（docs/21 D1）
      'dish-meal-slot', // 餐次胶囊组
      'dish-meal-picker-search', // 搜索（沿用旧键）
      'dish-meal-totals', // 合计卡（docs/21 D1）
      'meal-save', // 保存键（与按食材一字不差）
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    // 空已添加状态如实说（不是「暂无数据」）。
    expect(find.byKey(const Key('dish-meal-added-empty')), findsOneWidget);
  });

  testWidgets('点结果行 = 加进来（弹层不关），合计与已添加卡跟着出现', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await DishMealEditorSheet.show(
                  context,
                  dishes: [dish('d1', '番茄炒蛋'), dish('d2', '番茄牛腩', kcal: 480)],
                  localDate: '2026-10-28',
                  onAddDish: (_, {slotOverride}) async {},
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dish-meal-picker-item-d1')));
    await tester.pumpAndSettle();
    expect(closed, isFalse, reason: '点行是「加进来」，不是旧路的「选中并关弹层」');
    expect(find.byKey(const Key('dish-meal-added-d1')), findsOneWidget);
    // 已加入的行右侧换成对勾。
    expect(find.byIcon(Icons.check), findsOneWidget);

    // 合计 = 该菜整份营养。
    expect(find.byKey(const Key('dish-meal-totals')), findsOneWidget);
    expect(find.text('220 kcal'), findsOneWidget);
  });

  testWidgets('保存逐条落库，并把用户选的餐次传下去（D9 同口径）', (tester) async {
    final saved = <(String, MealSlot?)>[];
    await tester.pumpWidget(
      host(
        DishMealEditorSheet(
          dishes: [dish('d1', '番茄炒蛋'), dish('d2', '番茄牛腩')],
          localDate: '2026-10-28',
          initialSlot: MealSlot.breakfast,
          onAddDish: (dish, {slotOverride}) async {
            saved.add((dish.id, slotOverride));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('dish-meal-slot-dinner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dish-meal-picker-item-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dish-meal-picker-item-d2')));
    await tester.pumpAndSettle();
    // 保存键在弹层底部：默认测试视口（800×600）里已加两卡后它会沉到
    // 折叠线下，先滚进视口再点（tap 对 off-screen 目标不会命中）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('meal-save')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    expect(saved, hasLength(2), reason: '两道菜各落一条（逐条 AddDishToMeal.run）');
    for (final (id, slot) in saved) {
      expect(slot, MealSlot.dinner, reason: '$id 必须用用户点的餐次（不是预选早餐）');
    }
  });

  testWidgets('没加菜就保存：内联报错、不落库（不是空跑）', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        DishMealEditorSheet(
          dishes: [dish('d1', '番茄炒蛋')],
          localDate: '2026-10-28',
          onAddDish: (_, {slotOverride}) async {
            calls++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('meal-save')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    expect(calls, 0, reason: '没菜不该写库');
    expect(
      find.byKey(const Key('dish-meal-editor-error')),
      findsOneWidget,
      reason: '错误内联显示（弹层盖住 Scaffold，SnackBar 会被遮）',
    );
  });

  testWidgets('写入抛异常：内联报错、弹层不关、已成功的不回滚', (tester) async {
    var calls = 0;
    DishRecord? failed;
    await tester.pumpWidget(
      host(
        DishMealEditorSheet(
          dishes: [dish('d1', '番茄炒蛋'), dish('d2', '番茄牛腩')],
          localDate: '2026-10-28',
          onAddDish: (dish, {slotOverride}) async {
            calls++;
            if (dish.id == 'd2') {
              failed = dish;
              throw Exception('db down');
            }
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dish-meal-picker-item-d1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dish-meal-picker-item-d2')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('meal-save')),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(failed?.id, 'd2');
    expect(
      find.byKey(const Key('dish-meal-editor-error')),
      findsOneWidget,
      reason: '失败内联显示、弹层不关（N7 同一口径）',
    );
    // 失败的菜留在待存列表里（重按只补它）。
    expect(find.byKey(const Key('dish-meal-added-d2')), findsOneWidget);
    expect(
      find.byKey(const Key('dish-meal-added-d1')),
      findsNothing,
      reason: '已成功的从待存列表移除，重按保存不会重复写',
    );
  });

  testWidgets('搜索：输入「番茄」只剩番茄类（与食材侧同源口径）', (tester) async {
    await tester.pumpWidget(
      host(
        DishMealEditorSheet(
          dishes: [dish('d1', '番茄炒蛋'), dish('d2', '宫保鸡丁')],
          localDate: '2026-10-28',
          onAddDish: (_, {slotOverride}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('dish-meal-picker-search')),
      '番茄',
    );
    await tester.pumpAndSettle();
    expect(find.text('番茄炒蛋'), findsOneWidget);
    expect(find.text('宫保鸡丁'), findsNothing);
  });

  testWidgets('空菜品库：可行动空态（不写「暂无数据」）', (tester) async {
    await tester.pumpWidget(
      host(
        DishMealEditorSheet(
          dishes: const [],
          localDate: '2026-10-28',
          onAddDish: (_, {slotOverride}) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dish-meal-picker-empty')), findsOneWidget);
    expect(find.textContaining('存为菜品'), findsOneWidget);
  });
}
