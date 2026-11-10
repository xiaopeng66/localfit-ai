import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/add_dish_to_meal.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';

/// 菜单页「加入一餐」的**生产路径**端到端（docs/67 §4.3、A18、A22）。
///
/// 这条路径曾经是"另一套换算"：自己乘 `grams/servingGrams`、把供应写成
/// `sourceType='dish'`、快照里没有供应 id/份数/修订。现在它必须：
/// * 候选来自 `supplyDishCandidates`（每份口径）；
/// * 加入后写全 `menu_item` 快照；
/// * 360/390dp + 2.0 字号不溢出，CTA 带读屏语义。
void main() {
  late AppDatabase database;
  late FoodCatalogService catalog;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late MealRepository meals;
  late DishLibraryRepository dishLibrary;
  late AddDishToMeal add;
  late String windowId;
  final now = DateTime.utc(2026, 11, 9, 11);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    catalog = FoodCatalogService(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    canteen = CanteenRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    supplies = SupplyCatalogRepository(database: database);
    meals = MealRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    dishLibrary = DishLibraryRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    add = AddDishToMeal(
      mealRepository: meals,
      clock: FixedAppClock(now),
      supplyCatalog: supplies,
    );
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '06:00',
      closeTime: '21:00',
    );
    await _seedSupply(
      catalog: catalog,
      canteen: canteen,
      windowId: windowId,
      id: 'supply-lunch',
      name: '宫保鸡丁',
      kcal: 180,
      servingGrams: 200,
    );
  });

  tearDown(() => database.close());

  /// 卸载整棵树并让 drift 的 stream-close 定时器跑掉（否则 teardown 报
  /// 「Pending timers」——`MenuDishList` 订阅了供应流）。
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pumpMenu(
    WidgetTester tester, {
    required double width,
    double textScale = 1,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: MenuDishList(
              repository: dishLibrary,
              mealRepository: meals,
              supplyCatalog: supplies,
              now: now,
              onAddToMeal: (dish, {slotOverride}) => add.run(
                dish: dish,
                localDate: '2026-11-09',
                slotOverride: MealSlot.lunch,
              ),
              onOpenCanteen: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final width in const [360.0, 390.0]) {
    testWidgets('A22 ${width.toInt()}dp + 2.0 字号：菜单页候选与加入按钮不溢出', (
      tester,
    ) async {
      await pumpMenu(tester, width: width, textScale: 2.0);
      expect(tester.takeException(), isNull, reason: '页面级不得 overflow');
      expect(
        find.byKey(const Key('cta-add-meal-1')),
        findsWidgets,
        reason: '午餐那格的「加入一餐」必须在屏上可操作',
      );
      await unmount(tester);
    });
  }

  testWidgets('加入一餐：写全供应快照（menu_item + supplyId + 份数 + 修订）', (tester) async {
    await pumpMenu(tester, width: 390);
    final cta = find.byKey(const Key('cta-add-meal-1'));
    expect(cta, findsWidgets);
    await tester.tap(cta.first);
    await tester.pumpAndSettle();

    final mealRows = await database.select(database.meals).get();
    expect(mealRows, hasLength(1));
    expect(mealRows.single.source, 'menu_item');

    final items = await database.select(database.mealItems).get();
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.sourceType, 'menu_item', reason: '不能再写成 dish');
    expect(item.sourceId, isNotEmpty);
    expect(item.supplyId, item.sourceId);
    expect(item.servings, 1);
    expect(item.servingGrams, 200);
    expect(item.grams, 200);
    expect(item.kcalSnapshot, closeTo(360, 1e-9));
    expect(item.nutritionRevisionId, isNotNull, reason: '快照要能解释"当时按哪一版算的"');
    expect(item.foodId, isNotNull);
    await unmount(tester);
  });

  testWidgets('A22 读屏：加入按钮有可辨识语义标签', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpMenu(tester, width: 390);
    expect(
      find.bySemanticsLabel(RegExp('宫保鸡丁')),
      findsWidgets,
      reason: '卡片与按钮都该把菜名读出来，而不是"加入"两个裸字',
    );
    expect(
      find.bySemanticsLabel(RegExp('加入')),
      findsWidgets,
      reason: '操作按钮必须有语义标签',
    );
    handle.dispose();
    await unmount(tester);
  });

  testWidgets('A22 暗色主题：菜单页候选可读', (tester) async {
    await pumpMenu(tester, width: 360, theme: AppTheme.dark(), textScale: 1.5);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('宫保鸡丁'), findsWidgets);
    await unmount(tester);
  });
}

Future<void> _seedSupply({
  required FoodCatalogService catalog,
  required CanteenRepository canteen,
  required String windowId,
  required String id,
  required String name,
  required double kcal,
  required double servingGrams,
}) async {
  final foodId = await catalog.createMasterFood(
    name: name,
    kcalPer100g: kcal,
    proteinPer100g: 12,
    carbsPer100g: 8,
    fatPer100g: 11,
  );
  await canteen.createDish(
    windowId: windowId,
    name: name,
    foodId: foodId,
    servingGrams: servingGrams,
  );
}
