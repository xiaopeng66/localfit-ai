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

/// 阶段 1 验收（docs/21 §5.8.2 `openNutritionMenu`
/// + docs/21 §5.8.3「横向 Tab/Chip/日期条……保持选中项可见」）。
///
/// 意图契约：从**还存在的入口**（我的页·菜单来源管理）切到饮食页的
/// **菜单** Tab，且被选中的 chip 必须在视口内（否则用户看不到自己在哪一页）。
///
/// Round7 A（决策 D4）起今日页不再有「查看菜单」捷径：A 的 `.card-title`
/// 行只有「查看全部 → 记录」（`app.js:151`），旧 `cta-view-menu` 退场。
/// 本节因此拆成两半——① 今日页**没有**菜单入口（负向哨兵，防它悄悄
/// 复活）；② 我的页入口仍然把菜单 Tab 置为选中且 chip 在视口内
/// （`menuTabRequest` 的端到端覆盖不因退场而丢）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 320dp 窄屏是 chips 最容易把选中项挤出视口的宽度，用它做验收。
  const narrow = Size(320, 640);

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = FixedAppClock(DateTime.utc(2026, 9, 17));
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
        canteenRepository: CanteenRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        now: DateTime(2026, 9, 17),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// 饮食页 chips 是横向懒列表；用 `nutrition-tab-*` 稳定 Key 定位。
  Finder menuChip() => find.byKey(const Key('nutrition-tab-menu'));

  /// 「我的」分支里的菜单来源入口在列表深处，懒加载不滚过去就不会构建。
  Future<void> openMenuIntent(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('settings-menu-sources'));
    await tester.scrollUntilVisible(
      entry,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }

  testWidgets('今日页不再有菜单捷径（D4）：cta-view-menu / cta-quick-log 都不许复活', (
    tester,
  ) async {
    await pumpAt(tester, narrow);

    // 菜单 Tab 的意图覆盖改由「我的页·菜单来源管理」承担（见本文件后两条
    // 用例）；今日页这条只留负向哨兵，防止退场的捷径悄悄长回来。
    expect(
      find.byKey(const Key('cta-view-menu')),
      findsNothing,
      reason: 'D4：今日页的菜单捷径按 A 退场',
    );
    expect(
      find.byKey(const Key('cta-quick-log')),
      findsNothing,
      reason: 'D4/D9：记录入口改成餐次卡的 cta-log-meal / cta-log-dinner',
    );

    // 正向哨兵：退场的是**捷径**，不是「记录」这件事——今日页首屏的热量环
    // 必须在（记录饮食那颗在页面深处的餐次卡里，320dp 下不滚过去不会构建，
    // 它的正门地位由 dashboard_entry_routing_test 的 D9 用例钉住）。
    expect(
      find.byKey(const Key('dashboard-calorie-ring')),
      findsOneWidget,
      reason: '今日页仍要正常上屏',
    );
    // 本用例停在今日页，没有菜单 Tab 可读——选中态断言属于后两条
    // （意图入口搬到「我的页 → 菜单来源管理」之后，今日页不再有菜单 chip）。

    await unmountApp(tester);
  });

  testWidgets('320dp：意图切到菜单 Tab 后，选中 chip 完整在视口内（docs/21 §5.8.3）', (
    tester,
  ) async {
    await pumpAt(tester, narrow);
    await openMenuIntent(tester);

    final rect = tester.getRect(menuChip());
    expect(rect.left, greaterThanOrEqualTo(-0.01), reason: '选中 chip 左缘跑出视口');
    expect(
      rect.right,
      lessThanOrEqualTo(narrow.width + 0.01),
      reason: '选中 chip 右缘跑出视口，用户看不到当前在哪一页（docs/21 §5.8.3）',
    );

    await unmountApp(tester);
  });

  testWidgets('我的页「菜单来源管理」→ 切到菜单 Tab（D4 后仅存的入口）', (tester) async {
    await pumpAt(tester, narrow);

    // Round7 A 起这是菜单 Tab 仅存的深链入口（今日页捷径 D4 退场）；
    // 覆盖「我的」这条懒分支的创建路径 + `menuTabRequest` 的端到端行为。
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();

    final entry = find.byKey(const Key('settings-menu-sources'));
    await tester.scrollUntilVisible(
      entry,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    final node = tester.getSemantics(menuChip());
    expect(
      node.flagsCollection.isSelected.toBoolOrNull(),
      isTrue,
      reason: '我的页的菜单来源入口也必须落到菜单 Tab（docs/21 §5.8.2 openMenuSourceManager）',
    );

    await unmountApp(tester);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'menu-intent-${_value++}';
}
