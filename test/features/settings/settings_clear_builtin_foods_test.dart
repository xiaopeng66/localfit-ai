import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/setting_row.dart';
import 'package:localfit_ai/app/design/widgets/settings_group.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/clear_builtin_foods.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

import '../../support/food_fixture.dart';

/// 设置页「清空内置食物」入口（docs/32 §4 T11 需求 75 / §3 D14；设计稿
/// `ui设计/round5/t11-clear-foods.html`）。
///
/// 这个入口存在的唯一理由：**升级安装**里还躺着一整库内置食物，而 T13 之后
/// 随包种子不再自动灌库——没有这个可点入口，那批行就永远清不掉。四条外面
/// 可见的结论在这里钉住：
/// 1. 自门控：未接线、库里没有内置行、概览没加载出来 ⇒ 都不渲染（不摆点了
///    没反应的行，也不摆「删 0 条」的动作）；
/// 2. 位置：接线且有内置行时它是「食材库」组**最后一行**（D10 的三行顺序不动）；
/// 3. 弹层的数字是**现算的**（preview），不是概览里的旧快照；
/// 4. 确认后一次动作三个后果：库真的清了、计数行就地刷新、行自己消失，
///    snackbar 报的是真实结果；取消则什么都不发生。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 10, 13, 9);
    // 六条夹具内置行 + 一批同形状行：把条数抬过千位，弹层里的千位分隔符
    // 也就顺带进了断言（真机上那批本来就是四万九千多条）。
    await seedFoodFixture(database);
    await database.batch(
      (batch) => batch.insertAll(database.foods, [
        for (var i = 0; i < 1228; i++)
          FoodsCompanion.insert(
            id: 'seed-batch-$i',
            name: '食物$i',
            kcalPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 2,
            fatPer100g: 3,
            source: 'seed-v5',
            createdAt: now,
            updatedAt: now,
          ),
      ]),
    );
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'user-1',
            name: '我的鸡肉卷',
            kcalPer100g: 180,
            proteinPer100g: 15,
            carbsPer100g: 20,
            fatPer100g: 5,
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() => database.close());

  /// 引用链：一条餐次条目指向内置食物、一条指向自建（记录本身必须活下来），
  /// 一处菜单匹配指向内置（派生行，清空时移除）。
  Future<void> seedReferences() async {
    final now = DateTime.utc(2026, 10, 13, 9);
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-1',
            localDate: '2026-10-13',
            slot: 'lunch',
            eatenAt: now,
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
    for (final (itemId, foodId, name) in [
      ('item-builtin', 'seed-fc-1', '米饭'),
      ('item-user', 'user-1', '我的鸡肉卷'),
    ]) {
      await database
          .into(database.mealItems)
          .insert(
            MealItemsCompanion.insert(
              id: itemId,
              mealId: 'meal-1',
              foodId: Value(foodId),
              foodNameSnapshot: name,
              grams: 200,
              kcalSnapshot: 232,
              proteinSnapshot: 10,
              carbsSnapshot: 30,
              fatSnapshot: 3,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    await database
        .into(database.campusProfiles)
        .insert(
          CampusProfilesCompanion.insert(
            id: 'campus-1',
            name: '示范大学',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.venues)
        .insert(
          VenuesCompanion.insert(
            id: 'venue-1',
            campusId: 'campus-1',
            name: '东区食堂',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final canteens = CanteenRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final windowId = await canteens.createWindow(
      venueId: 'venue-1',
      name: '一楼窗口',
      openTime: '10:30',
      closeTime: '13:30',
    );
    final dishId = await canteens.createDish(windowId: windowId, name: '鸡胸肉饭');
    await database
        .into(database.menuItemFoodMatches)
        .insert(
          MenuItemFoodMatchesCompanion.insert(
            id: 'match-builtin',
            menuItemId: dishId,
            foodId: 'seed-fc-1',
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget page({bool wired = true}) => MaterialApp(
    home: SettingsPage(
      clearBuiltinFoods: wired ? ClearBuiltinFoods(database) : null,
      profileOverviewLoader: LoadProfileOverview(
        database: database,
        clock: FixedAppClock(DateTime.utc(2026, 10, 13, 9)),
      ),
      onAddCustomFood: () async {},
      onImportFoodCsv: () async {},
      onOpenMenuSources: () {},
    ),
  );

  Future<void> scrollTo(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// 「食材库」组内的行标题（按渲染顺序）。与 T8 的行序测试同一套取法。
  List<String> catalogRowTitles(WidgetTester tester) {
    final group = find.byWidgetPredicate(
      (widget) => widget is SettingsGroup && widget.title == '食材库',
      description: 'SettingsGroup(title: 食材库)',
    );
    return tester
        .widgetList<SettingRow>(
          find.descendant(of: group, matching: find.byType(SettingRow)),
        )
        .map((row) => row.title)
        .toList();
  }

  testWidgets('未接线 clearBuiltinFoods ⇒ 不渲染清空行（有内置行也不渲染）', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(page(wired: false));
    await tester.pumpAndSettle();

    await scrollTo(tester, const Key('settings-food-db-row'));
    expect(find.byKey(const Key('settings-clear-builtin-foods')), findsNothing);
    expect(catalogRowTitles(tester), ['食材数据库', '添加食物数据', '维护地点 / 窗口 / 菜品']);
  });

  testWidgets('接线且有内置行 ⇒ 清空行是「食材库」组最后一行', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await scrollTo(tester, const Key('settings-clear-builtin-foods'));
    expect(catalogRowTitles(tester), [
      '食材数据库',
      '添加食物数据',
      '维护地点 / 窗口 / 菜品',
      '清空内置食物数据',
    ], reason: 'D10 的三行顺序不动，销毁行落在组末');
    expect(find.text('1,235 条（自建 1 条）'), findsOneWidget);
  });

  testWidgets('库里没有内置行（全新安装）⇒ 不渲染：没有可清的东西就不摆动作', (tester) async {
    useTallViewport(tester);
    await ClearBuiltinFoods(database).call();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await scrollTo(tester, const Key('settings-food-db-row'));
    expect(find.byKey(const Key('settings-clear-builtin-foods')), findsNothing);
    expect(find.text('1 条（自建 1 条）'), findsOneWidget);
  });

  testWidgets('点击 ⇒ 弹层用现算的三组计数；取消则库与界面都不动', (tester) async {
    useTallViewport(tester);
    await seedReferences();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await scrollTo(tester, const Key('settings-clear-builtin-foods'));
    // 页面渲染完（概览快照 = 1,234 条内置）之后，库里又多了两条：如果弹层
    // 偷懒用概览里的旧快照，下面这两条断言就会红——「现算」才算真钉住。
    final now = DateTime.utc(2026, 10, 13, 10);
    await database.batch(
      (batch) => batch.insertAll(database.foods, [
        for (final id in const ['seed-late-1', 'seed-late-2'])
          FoodsCompanion.insert(
            id: id,
            name: '晚到的食物$id',
            kcalPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 2,
            fatPer100g: 3,
            source: 'seed-v5',
            createdAt: now,
            updatedAt: now,
          ),
      ]),
    );
    await tester.tap(find.byKey(const Key('settings-clear-builtin-foods')));
    await tester.pumpAndSettle();

    final body = tester
        .widget<Text>(find.byKey(const Key('clear-builtin-foods-body')))
        .data!;
    expect(body, contains('将删除 1,236 条内置食物（自建食物保留）。'));
    expect(body, isNot(contains('1,234')), reason: '弹层的数是现算的，不是概览旧快照');
    expect(body, contains('有 1 条饮食记录引用了这些食物'));
    expect(body, contains('有 1 条菜单匹配会移除'));
    expect(body, contains('不可撤销'));
    expect(body, isNot(contains('0 条')));

    expect(find.text('取消'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('clear-builtin-foods-body')), findsNothing);
    expect(
      (await database.select(database.foods).get()),
      hasLength(1237),
      reason: '取消 = 什么都不做（含后面晚到的那两条）',
    );
    expect(
      find.byKey(const Key('settings-clear-builtin-foods')),
      findsOneWidget,
      reason: '取消后行还在（库没变）',
    );
  });

  testWidgets('确认 ⇒ 库清了、计数行就地刷新、行消失、snackbar 报真实结果', (tester) async {
    useTallViewport(tester);
    await seedReferences();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await scrollTo(tester, const Key('settings-clear-builtin-foods'));
    await tester.tap(find.byKey(const Key('settings-clear-builtin-foods')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clear-builtin-foods-confirm')));
    await tester.pumpAndSettle();

    // ① 库：内置 0 条、自建原样、记录本身一条不少且引用被置空。
    final foods = await database.select(database.foods).get();
    expect(foods.map((row) => row.id), ['user-1']);
    final items = await database.select(database.mealItems).get();
    expect(items, hasLength(2), reason: '清食物不是清记录');
    expect(items.singleWhere((row) => row.id == 'item-builtin').foodId, isNull);
    expect(items.singleWhere((row) => row.id == 'item-user').foodId, 'user-1');
    expect(await database.select(database.menuItemFoodMatches).get(), isEmpty);

    // ② 计数行不再停旧快照（弹层返回不触发 TickerMode 重读，必须自己重读）。
    expect(find.text('1 条（自建 1 条）'), findsOneWidget);
    expect(find.textContaining('1,235'), findsNothing);
    // ③ 行自己消失：库里已无内置行。
    expect(find.byKey(const Key('settings-clear-builtin-foods')), findsNothing);
    // ④ snackbar 报数：删了多少、断了几条引用。
    expect(find.text('已清空内置食物：删除 1,234 条，1 条记录的食物引用已清空。'), findsOneWidget);
  });

  testWidgets('没有引用时弹层不提记录与菜单匹配两句（0 条不是要念出来的信息）', (tester) async {
    useTallViewport(tester);
    await ClearBuiltinFoods(database).call();
    await seedFoodFixture(database); // 只把六条内置行放回来，不建任何引用
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await scrollTo(tester, const Key('settings-clear-builtin-foods'));
    await tester.tap(find.byKey(const Key('settings-clear-builtin-foods')));
    await tester.pumpAndSettle();

    final body = tester
        .widget<Text>(find.byKey(const Key('clear-builtin-foods-body')))
        .data!;
    expect(body, contains('将删除 6 条内置食物（自建食物保留）。'));
    expect(body, isNot(contains('饮食记录')));
    expect(body, isNot(contains('菜单匹配')));
  });

  testWidgets('行的判据是旧快照、库已被别处清空 ⇒ 不弹层，回一条实话并让行消失', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await scrollTo(tester, const Key('settings-clear-builtin-foods'));

    // 别处（另一个入口/另一次会话）已经把内置行清掉，而本页概览还是旧的。
    await ClearBuiltinFoods(database).call();

    await tester.tap(find.byKey(const Key('settings-clear-builtin-foods')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('clear-builtin-foods-body')),
      findsNothing,
      reason: '预览为空 ⇒ 不拿「删 0 条」的确认框当流程',
    );
    expect(find.text('没有内置食物可清空。'), findsOneWidget);
    expect(
      find.byKey(const Key('settings-clear-builtin-foods')),
      findsNothing,
      reason: '空预览这次要顺手把计数行/行本身带回真实态',
    );
  });
}
