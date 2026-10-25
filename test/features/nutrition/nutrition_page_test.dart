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
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_week_strip.dart';

import '../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    repository = FoodRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
    );
  });

  tearDown(() => database.close());

  testWidgets('searches local foods and creates a user food', (tester) async {
    // 视口给到 1700dp：docs/28 §5.1 的四行卡片比旧版两行卡高约 30dp，
    // 1200dp 下「鸡」的第 9 条结果（鸡蛋）已经落在屏幕外——断言会变成
    // 「列表没渲染它」，而不是「搜索没命中它」。
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.nutrition,
        foodRepository: repository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('食物库'));
    await tester.pumpAndSettle();
    // 全量食物库（4.9 万条）默认列表不给浏览，先搜索再断言。
    // 结果行用 FoodCard 限定，避免命中搜索框自身的文本（搜索词与食物同名）。
    await tester.enterText(find.byKey(const Key('food-library-search')), '米饭');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FoodCard, '米饭'), findsOneWidget);
    // 用碎片词「鸡」搜索：既命中「鸡蛋」，也让后面新建的「我的鸡肉卷」能在同一条
    // 查询里刷新出来（搜索词与行名不同名，避免命中搜索框文本）。
    await tester.enterText(find.byKey(const Key('food-library-search')), '鸡');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FoodCard, '鸡蛋'), findsOneWidget);
    expect(find.widgetWithText(FoodCard, '米饭'), findsNothing);

    await tester.tap(find.byTooltip('自建食物'));
    await tester.pumpAndSettle();
    expect(find.text('新建食物'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pump();
    expect(find.text('请填写食物名称'), findsOneWidget);

    // docs/28 §5.5（N9）：弹层里不再有「默认份量」字段。
    expect(find.textContaining('默认份量'), findsNothing);

    await tester.enterText(find.byKey(const Key('new-food-name')), '我的鸡肉卷');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 热量')), '180');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 蛋白质')), '15');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 碳水')), '20');
    await tester.enterText(find.byKey(const Key('new-food-每 100g 脂肪')), '5');
    await tester.tap(find.byKey(const Key('new-food-save')));
    await tester.pumpAndSettle();

    final created = find.widgetWithText(FoodCard, '我的鸡肉卷');
    expect(created, findsOneWidget);
    // 图形化热量：卡上是能量密度环里那个数字（180/900），不是旧版右端的
    // 「180 kcal」文字。单行卡上**不再有**「kcal/100g」口径行（2026-10-08
    // docs/30 §2 D1：口径由列表头的 `FoodDensityScaleNote` 讲一次）。
    expect(
      find.descendant(of: created, matching: find.text('180')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: created, matching: find.text('kcal/100g')),
      findsNothing,
      reason: '口径行退到列表头，单行卡里没有第二行放它',
    );
    // 来源标签（自建/内置）同样退到详情弹层：单行卡只剩图标 + 名称 + 环。
    expect(
      find.descendant(of: created, matching: find.text('自建')),
      findsNothing,
    );
  });

  testWidgets('shows three chip tabs, week strip and disables future days', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.nutrition,
        foodRepository: repository,
        mealRepository: MealRepository(
          database: database,
          idGenerator: _IncrementingIdGenerator(),
          clock: FixedAppClock(DateTime.utc(2026, 9, 9)),
        ),
        now: DateTime(2026, 9, 9),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('记录'), findsOneWidget);
    expect(find.text('菜单'), findsOneWidget);
    expect(find.text('食物库'), findsOneWidget);
    // 计划 / 食谱 tab 已随整族功能下线：稳定 Key 必须不存在（防回归）。
    expect(find.byKey(const Key('nutrition-tab-plan')), findsNothing);
    expect(find.byKey(const Key('nutrition-tab-recipe')), findsNothing);
    // 周条以本周一（2026-09-07）起排七天。
    expect(find.byKey(const Key('meal-day-2026-09-07')), findsOneWidget);
    expect(find.byKey(const Key('meal-day-2026-09-13')), findsOneWidget);
    // 未来日（09-10 相对 now=09-09）点击无效：选中日不推进。
    // 探针读周条自己的 `selectedDate`（渲染事实，且与「选中日长什么样」无关
    // ——阶段 2B 把选中态的视觉从实心圆改成一枚品牌软底胶囊，属性探针不必
    // 跟着换第二次；页首的日期文案 2B 起由 `.selected-date` 一行承载）。
    expect(_weekStrip(tester).selectedDate, DateTime(2026, 9, 9));
    await tester.tap(find.byKey(const Key('meal-day-2026-09-10')));
    await tester.pumpAndSettle();
    expect(_weekStrip(tester).selectedDate, DateTime(2026, 9, 9));
    // 过去日（09-08）可切换，选中日随之回到 09-08。
    await tester.tap(find.byKey(const Key('meal-day-2026-09-08')));
    await tester.pumpAndSettle();
    expect(_weekStrip(tester).selectedDate, DateTime(2026, 9, 8));
    // 该日没有记录 ⇒ 四个槽位卡都在，且各自写**历史**空态句（2026-10-14,
    // docs/33 阶段 2B 步骤 5：日级整块空态退役，D23）。
    for (final slot in MealSlot.values) {
      expect(
        find.byKey(Key('nutrition-record-slot-${slot.storedValue}')),
        findsOneWidget,
        reason: '无记录日也要有四张槽位卡（它们是记录入口的承载）',
      );
    }
    expect(find.text('当天没有这餐记录'), findsNWidgets(4));
    // 历史日不画加号（A：`ui.date === state.today` 才渲染）。
    expect(
      find.byKey(const Key('nutrition-record-slot-lunch-add')),
      findsNothing,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

NutritionRecordWeekStrip _weekStrip(WidgetTester tester) => tester
    .widget<NutritionRecordWeekStrip>(find.byType(NutritionRecordWeekStrip));

final class _IncrementingIdGenerator implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'food-${_value++}';
}
