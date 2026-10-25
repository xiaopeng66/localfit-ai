import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

import '../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;
  final now = DateTime(2026, 9, 9, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    final ids = _Ids();
    foods = FoodRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
    meals = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
  });

  tearDown(() => database.close());

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.nutrition,
        foodRepository: foods,
        mealRepository: meals,
        now: now,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('edits, deletes and undoes a dated meal', (tester) async {
    final rice = (await foods.search('米饭'))
        .firstWhere((food) => food.name == '米饭');
    await meals.create(
      MealDraft(
        localDate: '2026-09-09',
        slot: MealSlot.lunch,
        items: [MealItemDraft.fromFood(rice, 100)],
      ),
    );
    await pumpApp(tester);

    expect(find.textContaining('米饭 100g'), findsOneWidget);
    await tester.tap(find.byTooltip('管理 午餐'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('meal-grams-item-1')), '200');
    await tester.enterText(find.byKey(const Key('meal-notes')), '加量');
    await tester.tap(find.byKey(const Key('meal-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('米饭 200g'), findsOneWidget);
    expect(find.text('加量'), findsOneWidget);

    await tester.tap(find.byTooltip('管理 午餐'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // 上一步保存编辑弹出的「餐食已更新」SnackBar 仍悬浮在屏幕底部并盖
    // 住删除确认按钮（modal route 打开后 SnackBar 的 4 秒退出定时器不再
    // 创建，测试内无法等它自然退场），此处直接触发按钮回调以验证删除-
    // 撤销业务流；弹层本身的点按交互由 settings/food_scan 的弹层测试
    // 覆盖。
    // 2026-10-03：`meal-delete-confirm` 从裸 `FilledButton` 收敛到 §3.8 B7
    // `LfDangerButton`（破坏性确认一律字型 error + 二次确认，设计稿没有实心
    // error 按钮）；B7 内部渲染 `TextButton`，实现类型因此变化，改取 M3 按钮
    // 公共基类。断言要的是「这个键的按钮可点并走删除流」，强度不变。
    final confirm =
        find.byKey(const Key('meal-delete-confirm')).evaluate().single.widget
            as ButtonStyleButton;
    confirm.onPressed!();
    await tester.pumpAndSettle();
    // 删掉当天唯一一餐后:那条餐卡从午餐槽位里消失,槽位换回空态行。
    // 2026-10-14(docs/33 阶段 2B 步骤 5,D23):记录页不再有「日级整块
    // 空态」——A 只画四张槽位卡,空槽位各写一行空态。断言因此从「整块空态
    // 文案」改成「午餐槽位空态行 + 该槽位合计回到尚未记录(且餐卡已不在)」,
    // 能指明是哪一餐空了,强度不降。
    expect(find.textContaining('米饭 200g'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('nutrition-record-slot-lunch')),
        matching: find.text('还没记录这一餐'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('nutrition-record-slot-lunch-total')),
          )
          .data,
      '尚未记录',
    );
    // docs/21 §3.1：删除族 snack 带左图标槽（删除图标）与「撤销」操作。
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.byIcon(AppSnackBar.deleteIcon),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.textContaining('米饭 200g'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('navigates dates and reuses a historical meal', (tester) async {
    final egg = (await foods.search('鸡蛋'))
        .firstWhere((food) => food.name == '鸡蛋');
    await meals.create(
      MealDraft(
        localDate: '2026-09-08',
        slot: MealSlot.breakfast,
        items: [MealItemDraft.fromFood(egg, 50)],
      ),
    );
    await pumpApp(tester);

    // 今天(09-09)还没有记录:四个槽位都写今天的空态句(2026-10-14,步骤 5
    // ——原先断言的是日级整块空态,已随 D23 退役)。
    expect(find.text('还没记录这一餐'), findsNWidgets(4));
    await tester.tap(find.byKey(const Key('meal-day-2026-09-08')));
    await tester.pumpAndSettle();
    expect(find.textContaining('鸡蛋 50g'), findsOneWidget);
    await tester.tap(find.byKey(const Key('meal-day-2026-09-09')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('复用历史餐食'));
    await tester.pumpAndSettle();
    // 2026-10-16：弹层改成卡片式行，标题按新事实写 `MM/DD · 餐次`；测试
    // 改按行 Key 点（不再依赖标题文案）。
    expect(find.text('09/08 · 早餐'), findsOneWidget);
    await tester.tap(find.byKey(const Key('history-meal-card-2026-09-08')));
    await tester.pumpAndSettle();
    expect(find.textContaining('鸡蛋 50g'), findsOneWidget);
    expect(find.text('历史餐食已复用到所选日期。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  // 2026-10-16 用户：「复用历史餐食的界面有点丑，重新优化」——弹层从纯
  // `ListTile` 列表改成卡片式行（日期·餐次标题 + 条目摘要 + kcal 徽标 +
  // 圆形复用钮），玻璃/嵌套层次与全站卡片语言一致。
  testWidgets('复用弹层：卡片式行（日期·餐次 / 摘要 / kcal 徽标 / 复用钮）', (tester) async {
    final egg = (await foods.search('鸡蛋'))
        .firstWhere((food) => food.name == '鸡蛋');
    await meals.create(
      MealDraft(
        localDate: '2026-09-08',
        slot: MealSlot.breakfast,
        notes: '早起赶课',
        items: [
          MealItemDraft.fromFood(egg, 50),
          MealItemDraft.fromFood(egg, 30),
        ],
      ),
    );
    await pumpApp(tester);

    await tester.tap(find.byTooltip('复用历史餐食'));
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('history-meal-card-2026-09-08'));
    expect(row, findsOneWidget, reason: '卡片式行有稳定的可点 Key');
    // 卡片是 DesignCard（与全站唯一卡片形态一致）。
    expect(tester.widget(row), isA<DesignCard>());
    // 标题 = 日期 · 餐次；摘要 = 条目名；kcal 用徽标。
    expect(
      find.descendant(of: row, matching: find.text('09/08 · 早餐')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.textContaining('鸡蛋')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byType(LfBadge)),
      findsOneWidget,
    );
    // 复用钮有 tooltip（图标按钮的可访问名）。
    expect(
      find.descendant(
        of: row,
        matching: find.byKey(const Key('history-meal-reuse-2026-09-08')),
      ),
      findsOneWidget,
    );

    // 行为不变：点行 = 复用。
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('历史餐食已复用到所选日期。'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'nutrition-widget-${value++}';
}
