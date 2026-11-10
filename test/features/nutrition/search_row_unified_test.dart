import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_editor_dialog.dart';

/// 【2026-10-30 用户】「来自菜品库和食物库的检索卡片样式，我不是让你统一吗，
/// 还让你加上来源的标记，你怎么不加，不统一。」
///
/// 判据：同一个搜索列表里，食物库行与菜品库行**结构完全一致**（40dp 图标 +
/// 名称/副标题 + 来源徽标 + 加号），且两行都有来源标（「食物库」/「菜品库」）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FoodRepository foods;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    foods = FoodRepository(
      database: db,
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 30)),
    );
    final now = DateTime.utc(2026, 10, 30);
    // 一条食物（名称含「鸡蛋」）。
    await db
        .into(db.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'food-egg',
            name: '鸡蛋',
            defaultServingGrams: const Value(100),
            kcalPer100g: 139,
            proteinPer100g: 13,
            carbsPer100g: 1,
            fatPer100g: 9,
            source: 'seed-v5',
            category: Value(FoodCategory.classify(name: '鸡蛋').id),
            createdAt: now,
            updatedAt: now,
          ),
        );
    // 一条菜品（名称也含「鸡蛋」）。
    await db
        .into(db.dishLibrary)
        .insert(
          DishLibraryCompanion.insert(
            id: 'dish-egg',
            name: '鸡蛋汉堡',
            mealSlot: '晚餐',
            kcal: 190,
            proteinG: 10,
            carbsG: 20,
            fatG: 9,
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MealEditorDialog(
              foodRepository: foods,
              localDate: '2026-10-30',
              dishRepository: DishLibraryRepository(
                database: db,
                idGenerator: _Ids(),
                clock: FixedAppClock(DateTime.utc(2026, 10, 30)),
              ),
            ),
          ),
        ),
      ),
    );
    // 菜品库走 `watchAll()`（无限流）：`pumpAndSettle` 永远等不到静止，
    // 用固定 pump 把首帧与异步检索结果泵出来。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('食物库行与菜品库行都有来源标（食物库 / 菜品库）', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byKey(const Key('meal-food-search')), '鸡蛋');
    // 双库检索是真实异步（DB + 菜品 watchAll().first）：用 runAsync 让它跑完，
    // 再泵两帧把 FutureBuilder 的结果画出来。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const Key('search-source-食物库')),
      findsWidgets,
      reason: '食物库结果必须带「食物库」来源标（旧版没有）',
    );
    expect(
      find.byKey(const Key('search-source-菜品库')),
      findsWidgets,
      reason: '菜品库结果必须带「菜品库」来源标',
    );
  });

  testWidgets('两库结果行同一形态：都有 40dp 图标槽 + 加号', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byKey(const Key('meal-food-search')), '鸡蛋');
    // 双库检索是真实异步（DB + 菜品 watchAll().first）：用 runAsync 让它跑完，
    // 再泵两帧把 FutureBuilder 的结果画出来。
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 两条结果（1 食物 + 1 菜品）。
    final foodRow = find.byKey(const Key('search-food-name-food-egg'));
    final dishRow = find.byKey(const Key('search-dish-name-dish-egg'));
    expect(foodRow, findsOneWidget);
    expect(dishRow, findsOneWidget);

    // 每行都有加号（统一件的固定件）。
    final addIcons = find.byIcon(Icons.add_circle_outline);
    expect(addIcons, findsNWidgets(2), reason: '两行都应有同位置同尺寸的加号');

    // 两行高度一致（同一形态的几何判据）。
    final foodCard = tester.getRect(
      find.ancestor(of: foodRow, matching: find.byType(Material)).first,
    );
    final dishCard = tester.getRect(
      find.ancestor(of: dishRow, matching: find.byType(Material)).first,
    );
    expect(
      foodCard.height,
      closeTo(dishCard.height, 0.5),
      reason: '两库结果行必须等高（同一组件）',
    );
  });

  testWidgets('手动添加入口是整行卡片（不再是小虚线胶囊），展开后是分组表单', (tester) async {
    await pumpEditor(tester);
    final toggle = find.byKey(const Key('meal-manual-toggle'));
    expect(toggle, findsOneWidget);
    // 整行：宽度接近弹层内容宽（不是内容宽度的小胶囊）。
    final width = tester.getRect(toggle).width;
    expect(width, greaterThan(300), reason: '入口是整行，不是 28dp 小胶囊');

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('meal-manual-form')), findsOneWidget);
    // 表单是白卡（DesignCard）且分组标题在。
    expect(find.text('手动填写'), findsOneWidget);
    expect(find.textContaining('三大营养素'), findsOneWidget);
  });
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'gen-${value++}';
}
