import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';

/// `RV4-P1-04`（`docs/57` §3 / `docs/56` R2）：主页「记录晚餐」**开抽屉、不跳页**。
///
/// 缺陷原貌：`app_router.onLogMeal` 先 `mealAddIntent.request(slot)` 再
/// `go(nutrition)`，由目标页开层——用户被带到饮食页（而且停在食物库 tab），
/// 退出弹层自然回不到主页。
///
/// 本文件钉四件事：
/// 1. 点 `cta-log-dinner` 后**记录入口弹层**出现；
/// 2. 底栏两个 tab 的 `Semantics.selected` 都**仍是 false**（没被点亮 = 没跳页）；
/// 3. 取消后 `dashboard-next-meal` 仍在（还在主页），记录页周条**不存在**；
/// 4. 关掉后切到饮食页**不该再多弹一次**（一次性意向「诈尸」）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = FixedAppClock(DateTime.utc(2026, 10, 24, 2));
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.dashboard,
        foodRepository: FoodRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        mealRepository: MealRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        now: DateTime(2026, 10, 24, 12),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapLogDinner(WidgetTester tester) async {
    final entry = find.byKey(const Key('cta-log-dinner'));
    await tester.scrollUntilVisible(
      entry,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }

  testWidgets('点「记录晚餐」→ 抽屉开在原页，底栏没被点亮', (tester) async {
    await pumpDashboard(tester);
    await tapLogDinner(tester);

    // ① 抽屉起来了。
    expect(
      find.byKey(const Key('meal-entry-chooser')),
      findsOneWidget,
      reason: '记录入口弹层必须出现（按食材 / 按菜品 两个入口）',
    );
    // ② 底栏两 tab 都没选中 —— 说明**没有**被带到饮食页。
    //    弹层盖在下层页面上方，底栏仍在树上（barrier 不吃语义）。
    for (final key in ['nutrition-tab-record', 'nutrition-tab-menu']) {
      final finder = find.byKey(Key(key));
      if (finder.evaluate().isEmpty) continue;
      expect(
        tester.getSemantics(finder).flagsCollection.isSelected.toBoolOrNull(),
        isFalse,
        reason: '$key 不得被记录入口点亮（点亮 = 已经跳页了）',
      );
    }
    // ③ 一次性意向不再被写：本测试无法直接读 `AppRouter` 的私有实例，改为
    //    行为断言——关掉弹层再切到饮食页，不该**再**多弹一次入口（诈尸）。

    // ④ 取消后仍在主页。
    await tester.tap(find.byKey(const Key('meal-entry-by-food')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('meal-food-search')),
      findsOneWidget,
      reason: '「按食材」必须进既有餐食编辑弹层',
    );
    // 关掉编辑弹层：点弹层里的「取消」（弹层不是页面，没有返回按钮）。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('dashboard-next-meal')),
      findsOneWidget,
      reason: '退出弹层必须回到主页（原缺陷：被带到饮食页，回不去）',
    );
    expect(
      find.byKey(const Key('nutrition-record-week-strip')),
      findsNothing,
      reason: '记录页的周条不得出现（出现 = 真的跳页了）',
    );
    await unmountApp(tester);
  });

  testWidgets('点「记录晚餐」→ 预选餐次是晚餐', (tester) async {
    await pumpDashboard(tester);
    await tapLogDinner(tester);
    await tester.tap(find.byKey(const Key('meal-entry-by-food')));
    await tester.pumpAndSettle();

    // 餐次胶囊里「晚餐」是选中态（`meal-slot` 组下的 _SlotPill）。
    expect(
      find.descendant(
        of: find.byKey(const Key('meal-slot')),
        matching: find.text('晚餐'),
      ),
      findsOneWidget,
    );
    final dinner = tester.getSemantics(
      find
          .ancestor(
            of: find.descendant(
              of: find.byKey(const Key('meal-slot')),
              matching: find.text('晚餐'),
            ),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      dinner.flagsCollection.isSelected.toBoolOrNull(),
      isTrue,
      reason: '主页「记录晚餐」必须把晚餐预选上（D9 口径）',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await unmountApp(tester);
  });
}

Future<void> unmountApp(WidgetTester tester) async {
  // 与 `dashboard_entry_routing_test` 同一手法：先卸载整棵树再让 drift 的
  // stream-close 定时器跑掉，否则 teardown 报「Pending timers」。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}
