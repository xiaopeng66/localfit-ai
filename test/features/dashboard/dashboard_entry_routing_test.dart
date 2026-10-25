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

/// 阶段 2 验收（docs/21 §5.1）：
///
/// 「菜单/记录/AI 入口走正确路由」——三个入口里此前只有菜单入口有端到端
/// 覆盖（`open_nutrition_menu_intent_test.dart`）。记录与 AI 两个入口的
/// 路由断言此前不存在，本文件补齐。
///
/// 断言的是「落到了哪个页面」而不是「有没有回调」：回调存在但指向错误
/// 路由同样是缺陷，只有页面身份能区分。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDashboard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = FixedAppClock(DateTime.utc(2026, 9, 17, 12));
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
        now: DateTime(2026, 9, 17, 12),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  /// CTA 行在首屏以下，懒加载列表不滚过去就不会构建。
  Future<void> tapCta(WidgetTester tester, String key) async {
    final entry = find.byKey(Key(key));
    await tester.scrollUntilVisible(
      entry,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
  }

  // 【语义变更，不是删断言换绿】`RV4-P1-04`（docs/56 R2）改的就是这个行为：
  // 主页「记录晚餐」不再把用户带到饮食页，而是**在本页开抽屉**。
  //
  // 原断言对象（「落到饮食页记录 Tab 且点亮它」）**不存在了**——那不是缺陷
  // 修掉了，而是产品行为被裁决改掉（docs/56 §4 D9 之后的 R2：「退出也回不去
  // 主页」）。替代断言在 `dashboard_meal_sheet_test.dart`：
  //   ① `meal-entry-chooser` 出现；② 底栏两 tab 的 selected 都仍是 false；
  //   ③ 取消后 `dashboard-next-meal` 仍在、`nutrition-record-week-strip` 不存在；
  //   ④ 预选餐次是晚餐。
  // 本文件保留其余路由断言（AI 卡、菜单入口等）。
  testWidgets('今日页记录入口 → 本页开抽屉（不再跳饮食页，RV4-P1-04）', (tester) async {
    await pumpDashboard(tester);
    await tapCta(tester, 'cta-log-dinner');

    // 抽屉起来了。
    expect(find.byKey(const Key('meal-entry-chooser')), findsOneWidget);
    // 底栏没被点亮 = 没跳页。两个 tab 都在树上（shell 常驻）。
    for (final key in ['nutrition-tab-record', 'nutrition-tab-menu']) {
      final finder = find.byKey(Key(key));
      if (finder.evaluate().isEmpty) continue;
      expect(
        tester.getSemantics(finder).flagsCollection.isSelected.toBoolOrNull(),
        isFalse,
        reason: '$key 不得被点亮（点亮 = 已被带到饮食页）',
      );
    }
    await unmountApp(tester);
  });

  // docs/21 §5.1 交互表对这张卡给过两种说法（「AI 健康助手」听起来像 /ai-chat），
  // 规范自己裁定了以 `cta-ai-workbench` 这个 id 为准 → 跳 AI 工作台。
  // 这里断言实际落地页，避免规范措辞与实现各说各话。
  testWidgets('今日页 AI 卡 → AI 工作台（job 路由，不是 /ai-chat）', (tester) async {
    await pumpDashboard(tester);

    await tapCta(tester, 'cta-ai-workbench');

    // docs/32 §4 T6c：工作台是**画廊**（六张启动卡），旧「未配置」空态
    // 已随任务注入退役；「到了工作台」的判据改为画廊的两组分节标题。
    expect(
      find.text('饮食'),
      findsOneWidget,
      reason: '`cta-ai-workbench` 必须推入 /ai-workbench',
    );
    expect(
      find.byKey(const Key('ai-workbench-task-menu-normalize')),
      findsOneWidget,
    );
    expect(
      find.text('AI 对话服务尚未配置，请先在「我的」里完成 AI 服务。'),
      findsNothing,
      reason: 'AI 工作台不是 AI 对话页，别把两个入口的目标搞混',
    );

    await unmountApp(tester);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'entry-route-${_value++}';
}
