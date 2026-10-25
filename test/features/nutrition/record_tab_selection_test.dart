import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/record_tab.dart';

/// docs/21 §3 ListCard（MealCard）长按多选：长按进入多选模式，点击切换
/// 勾选（勾选圈变形），操作条「已选 N 项 · 删除所选 · 取消」，确认后
/// 批量删除（一次确认，非逐项弹窗）。
void main() {
  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final ids = _IncrementingIdGenerator();
    foods = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
    );
    meals = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
    );
  });

  tearDown(() => database.close());

  final seededMealIds = <String>[];

  Future<void> seedMeals() async {
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'food-rice',
            name: '米饭',
            kcalPer100g: 116,
            proteinPer100g: 2.6,
            carbsPer100g: 25.9,
            fatPer100g: 0.3,
            source: 'seed',
            createdAt: DateTime.utc(2026, 9, 9),
            updatedAt: DateTime.utc(2026, 9, 9),
          ),
        );
    final rice = (await foods.search('米饭'))
        .firstWhere((food) => food.name == '米饭');
    // meals.create 同时消耗一个 meal.id 和一个 item-id（共享 id 池）。为让
    // 卡片 Key 稳定，断言用 create() 返回值而不是推索引。
    seededMealIds.clear();
    seededMealIds.add(
      await meals.create(
        MealDraft(
          localDate: '2026-09-09',
          slot: MealSlot.lunch,
          items: [MealItemDraft.fromFood(rice, 100)],
        ),
      ),
    );
    seededMealIds.add(
      await meals.create(
        MealDraft(
          localDate: '2026-09-09',
          slot: MealSlot.breakfast,
          items: [MealItemDraft.fromFood(rice, 50)],
        ),
      ),
    );
  }

  Future<void> pumpTab(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordTab(
            mealRepository: meals,
            selectedDate: DateTime(2026, 9, 9),
            now: DateTime(2026, 9, 9),
            onSelectDate: (_) {},
            onEditMeal: (_) {},
            onDeleteMeal: (_) {},
            onDeleteSelected: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 排掉 drift StreamBuilder dispose 时 schedule 的「0 时延」close timer
  /// （FakeAsync.elapse(Duration.zero) 不会触发 0-duration 定时器）。
  Future<void> drainStream(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('记录页的滚动视图挂常显可拖滑条（docs/28 §8.3）', (tester) async {
    await seedMeals();
    await pumpTab(tester);

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    await drainStream(tester);
  });

  testWidgets('长按进入多选：勾选圈出现，操作条计数；点击切换勾选', (tester) async {
    await seedMeals();
    await pumpTab(tester);

    expect(find.text('已选 0 项'), findsNothing);
    await tester.longPress(find.byKey(Key('meal-${seededMealIds[0]}')));
    await tester.pumpAndSettle();

    expect(find.text('已选 1 项'), findsOneWidget);
    expect(
      find.byKey(Key('meal-select-circle-${seededMealIds[0]}')),
      findsOneWidget,
    );

    // 多选模式下点击切换勾选（不再打开编辑）。
    await tester.tap(find.byKey(Key('meal-${seededMealIds[1]}')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);

    await tester.tap(find.byKey(Key('meal-${seededMealIds[1]}')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    await drainStream(tester);
  });

  testWidgets('取消退出多选：勾选与操作条消失，点击恢复编辑入口', (tester) async {
    await seedMeals();
    await pumpTab(tester);

    await tester.longPress(find.byKey(Key('meal-${seededMealIds[0]}')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.byKey(const Key('meals-selection-cancel')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsNothing);
    expect(
      find.byKey(Key('meal-select-circle-${seededMealIds[0]}')),
      findsNothing,
    );
    await drainStream(tester);
  });

  testWidgets('删除所选：一次确认后批量删除', (tester) async {
    await seedMeals();
    await pumpTab(tester);

    await tester.longPress(find.byKey(Key('meal-${seededMealIds[0]}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('meal-${seededMealIds[1]}')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('meals-bulk-delete')));
    await tester.pumpAndSettle();
    expect(find.text('删除所选餐食？'), findsOneWidget);

    // 破坏性确认 = §3.8 B7：error 字色的**文字**按钮。设计稿里没有实心 error
    // 按钮（`我的.html:524-532` 的「清除所有数据」就是 error 字色的一行），
    // 所以这里既不是 B2 的实心主色，也不该是 FilledButton 形态。
    final confirm = tester.widget<TextButton>(
      find.byKey(const Key('meals-bulk-delete-confirm')),
    );
    expect(
      confirm.style?.foregroundColor?.resolve(<WidgetState>{}),
      LfSemanticColors.light.error,
    );

    await tester.tap(find.byKey(const Key('meals-bulk-delete-confirm')));
    await tester.pumpAndSettle();
    // 两项都删除 → 两个槽位各自回到空态（2026-10-14，docs/33 阶段 2B 步骤 5：
    // 日级整块空态退役，D23；断言改为逐槽位可查，信息量更大）。
    expect(find.byKey(Key('meal-${seededMealIds[0]}')), findsNothing);
    expect(find.byKey(Key('meal-${seededMealIds[1]}')), findsNothing);
    expect(find.text('还没记录这一餐'), findsNWidgets(4));
    expect(find.text('尚未记录'), findsNWidgets(4));
    await drainStream(tester);
  });

  testWidgets('未勾选任何项：删除按钮禁用', (tester) async {
    await seedMeals();
    await pumpTab(tester);

    await tester.longPress(find.byKey(Key('meal-${seededMealIds[0]}')));
    await tester.pumpAndSettle();
    // 长按即勾选该项 → 再点一次取消勾选 → 0 项。
    await tester.tap(find.byKey(Key('meal-${seededMealIds[0]}')));
    await tester.pumpAndSettle();
    expect(find.text('已选 0 项'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('meals-bulk-delete')))
          .onPressed,
      isNull,
    );
    await drainStream(tester);
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}
