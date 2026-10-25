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

/// 2.0-6b：饮食页胶囊导航（docs/07 §9.3）。
///
/// 2026-10-04（docs/28 §6.1）：`记录 | 计划 | 菜单 | 食谱 | 食物库` 收敛为
/// `记录 | 菜单 | 食物库`——计划与食谱两枚 tab 随「食谱 / 计划」整族下线。
/// 「菜单」为新增胶囊入口（不增加底部导航，docs/07 §6.5）。
void main() {
  testWidgets('three capsules render in spec order and switch bodies', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
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

    // 顺序即 docs/07 §9.3 收敛后的三个胶囊。
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('菜单'), findsOneWidget);
    expect(find.text('食物库'), findsOneWidget);
    // 计划 / 食谱 tab 已随整族功能下线：稳定 Key 必须不存在（防回归）。
    expect(find.byKey(const Key('nutrition-tab-plan')), findsNothing);
    expect(find.byKey(const Key('nutrition-tab-recipe')), findsNothing);

    // docs/21 §5.2 的右下主操作钮：记录 tab（默认 tab）上必须真实存在——
    // 它挂在 `_tab == 0 && meals != null` 的条件上，接线断掉时只少一个
    // 悬浮按钮、不报错，所以要有断言钉住。
    expect(find.byKey(const Key('nutrition-record-fab')), findsOneWidget);

    // 切走到别的 tab，它就该收起来（正文内容中心的 FAB 覆盖列表）。
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nutrition-record-fab')), findsNothing);
    await tester.tap(find.text('记录'));
    await tester.pumpAndSettle();

    // 菜单：主来源是菜品库（docs/21 §5.3），未接线菜品库时给空态。
    // 食堂目录（地点→窗口→菜品三级自建）按 docs/22 裁决 ② 收进二级页，
    // 从 hero 右上角进入——不再是菜单 tab 的首屏内容。
    await tester.tap(find.text('菜单'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nutrition-menu-hero')), findsOneWidget);

    // 食物库：原功能保留。
    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('food-library-search')), '米饭');
    await tester.pumpAndSettle();
    expect(find.textContaining('米饭'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'food-${_value++}';
}
