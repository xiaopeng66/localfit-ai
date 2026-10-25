import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';

/// 3.0：菜单 Tab 装配测试（docs/07 §9.3 + 新增推荐菜单视图）。
///
/// 验证 `MenuTabView` 与 `RecommendedMenuView` 在 NutritionPage 的菜单
/// chip 下共存：目录维护 UI 和推荐控制器视图同时存在，空态不伪造数据。
void main() {
  testWidgets('menu tab renders canteen directory only (2026-10-22 撤推荐)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // 路由层需要完整的 repositories 才能构建 NutritionPage。
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.nutrition,
        foodRepository: FoodRepository(
          database: db,
          idGenerator: _Ids(),
          clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
        ),
        mealRepository: MealRepository(
          database: db,
          idGenerator: _Ids(),
          clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
        ),
        canteenRepository: CanteenRepository(
          database: db,
          idGenerator: _Ids(),
          clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
        ),
        now: DateTime(2026, 9, 9),
      ),
    );
    await tester.pumpAndSettle();

    // 菜单 tab 首屏 = 菜品库（docs/21 §5.3 唯一主来源）。
    await tester.tap(find.text('菜单'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nutrition-menu-hero')), findsOneWidget);
    // 2026-10-14（Round7 阶段 3 步骤 1，D25）：页首 hero 卡退场，改 A
    // `nutritionMenus()` 的段头块——标题、pill、指引行、汇总行。
    expect(find.text('每日菜品推荐'), findsOneWidget);
    expect(find.text('本地已分析菜品'), findsOneWidget);
    // docs/21 §5.3 Key 表：汇总行里的「已安排」段（无计划时也写 0 餐）。
    expect(
      find.byKey(const Key('nutrition-menu-hero-planned')),
      findsOneWidget,
    );

    // 食堂目录收进二级页：从页尾 `.list-link`（D28）进入后**只剩目录维护**
    // ——2026-10-22 用户：「食堂目录里的今日推荐删掉，这个界面就记录食堂菜品」。
    // 推荐只保留菜单页一处（回到记录页的 `NextMealEntryCard`）。
    expect(find.text('管理食堂目录'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cta-manage-canteen')));
    await tester.pumpAndSettle();

    expect(find.text('还没有食堂地点。'), findsOneWidget);
    expect(find.text('今日推荐'), findsNothing, reason: '食堂目录不再有今日推荐');
    expect(find.byKey(const Key('recommended-menu-idle')), findsNothing);
    expect(find.byKey(const Key('cta-request-recommendation')), findsNothing);

    // LfTopBar 的返回键（键名 `top-bar-back`）：`pageBack` 找的是
    // Cupertino/Material 的默认返回件，自定义顶栏里没有。
    await tester.tap(find.byKey(const Key('top-bar-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nutrition-menu-hero')), findsOneWidget);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'food-${_value++}';
}
