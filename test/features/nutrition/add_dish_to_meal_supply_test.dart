import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/add_dish_to_meal.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/nutrition_math.dart';
import 'package:localfit_ai/features/nutrition/application/supply_dish_candidates.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// 菜单页「加入一餐」的**生产路径**（docs/67 §4.3、A18）。
///
/// 菜单页的候选来自 `supplyDishCandidates`（每份口径的 `DishRecord`，id = 供应 id）。
/// 加入时必须：
/// * 走统一换算（不是自己乘一遍）；
/// * 写全快照：`sourceType=menu_item`、`sourceId/supplyId=供应`、
///   `servings`、`servingGrams`、`nutritionRevisionId`；
/// * 份量未知时拒绝，不补 100g。
void main() {
  late AppDatabase database;
  late FoodCatalogService catalog;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late MealRepository meals;
  late AddDishToMeal add;
  late String windowId;
  final now = DateTime.utc(2026, 11, 9, 12);

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
    add = AddDishToMeal(
      mealRepository: meals,
      clock: FixedAppClock(now),
      supplyCatalog: supplies,
    );
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '11:00',
      closeTime: '13:30',
    );
  });

  tearDown(() => database.close());

  Future<String> seedSupply({
    required String id,
    required String name,
    required double kcal,
    double? servingGrams,
    double proteinPer100g = 12,
    double carbsPer100g = 8,
    double fatPer100g = 11,
  }) async {
    final foodId = await catalog.createMasterFood(
      name: name,
      kcalPer100g: kcal,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
    );
    await database
        .into(database.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: id,
            serviceId: windowId,
            displayName: name,
            createdAt: now,
            updatedAt: now,
            foodId: Value(foodId),
            servingGrams: Value(servingGrams),
            servingGramsStatus: Value(
              servingGrams == null ? 'unknown' : 'known',
            ),
            servingGramsSource: Value(
              servingGrams == null ? 'legacy_unknown' : 'user_input',
            ),
          ),
        );
    return foodId;
  }

  /// 菜单页实际拿到的候选（每份口径的 DishRecord）。
  Future<DishRecord> candidateOf(String supplyId) async {
    final supply = (await supplies.getById(supplyId))!;
    return supplyDishCandidates([supply], now: now).single;
  }

  test('按一份加入：写全供应快照，克数 = 该供应每份克数', () async {
    final foodId = await seedSupply(
      id: 'supply-gb',
      name: '宫保鸡丁',
      kcal: 180,
      servingGrams: 200,
    );
    final dish = await candidateOf('supply-gb');
    expect(dish.kcal, closeTo(360, 1e-9), reason: '候选是每份口径');
    expect(dish.servingGrams, 200);

    final mealId = await add.run(dish: dish, localDate: '2026-11-09');
    final meal = (await meals.getById(mealId))!;
    final item = meal.items.single;

    expect(meal.source, 'menu_item');
    expect(item.sourceType, 'menu_item', reason: '不能退化成 dish');
    expect(item.sourceId, 'supply-gb');
    expect(item.supplyId, 'supply-gb');
    expect(item.servings, 1);
    expect(item.servingGrams, 200);
    expect(item.grams, 200);
    expect(item.foodId, foodId);
    expect(item.nutrition.kcal, closeTo(360, 1e-9));

    final revisionId = await database
        .customSelect(
          'SELECT current_revision_id AS r FROM foods WHERE id = ?',
          variables: [Variable.withString(foodId)],
        )
        .getSingle();
    expect(
      item.nutritionRevisionId,
      revisionId.data['r'],
      reason: '快照要记下"当时按哪一版算的"',
    );
  });

  test('给明确克数：按克记（servings 置空），仍带来源与修订', () async {
    final foodId = await seedSupply(
      id: 'supply-gb',
      name: '宫保鸡丁',
      kcal: 180,
      servingGrams: 200,
    );
    final dish = await candidateOf('supply-gb');

    final mealId = await add.run(
      dish: dish,
      localDate: '2026-11-09',
      grams: 120,
    );
    final item = (await meals.getById(mealId))!.items.single;
    expect(item.grams, 120);
    expect(item.servings, isNull, reason: '手改克数后不再声称"几份"');
    expect(item.servingGrams, 200, reason: '份量依据仍保留，便于解释');
    expect(item.supplyId, 'supply-gb');
    expect(item.foodId, foodId);
    expect(item.nutrition.kcal, closeTo(216, 1e-9), reason: '180 × 120 ÷ 100');
  });

  test('份量未知的供应：拒绝并给可行动提示，不补 100g', () async {
    await seedSupply(
      id: 'supply-unknown',
      name: '炒面',
      kcal: 200,
      servingGrams: null,
    );
    // 手工构造"菜单页看到的"候选：份量未知的供应不进 supplyDishCandidates
    // （自动推荐只接受可信份量），所以这里直接用供应自身的数值模拟旧入口。
    final supply = (await supplies.getById('supply-unknown'))!;
    final dish = DishRecord(
      id: supply.id,
      name: supply.displayName,
      mealSlot: 'lunch',
      kcal: supply.kcalPer100g!,
      proteinG: supply.proteinPer100g!,
      carbsG: supply.carbsPer100g!,
      fatG: supply.fatPer100g!,
      source: 'canteen',
      servingGrams: null,
      createdAt: now,
      updatedAt: now,
    );

    await expectLater(
      add.run(dish: dish, localDate: '2026-11-09'),
      throwsA(isA<ServingGramsUnknown>()),
    );
    expect(await database.select(database.mealItems).get(), isEmpty);
  });

  test('未分析的供应：拒绝，不写 0 千卡', () async {
    await database
        .into(database.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: 'supply-raw',
            serviceId: windowId,
            displayName: '新菜',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final dish = DishRecord(
      id: 'supply-raw',
      name: '新菜',
      mealSlot: 'lunch',
      kcal: 0,
      proteinG: 0,
      carbsG: 0,
      fatG: 0,
      source: 'canteen',
      createdAt: now,
      updatedAt: now,
    );
    await expectLater(
      add.run(dish: dish, localDate: '2026-11-09'),
      throwsA(isA<NutritionIncomplete>()),
    );
    expect(await database.select(database.mealItems).get(), isEmpty);
  });

  test('未接线供应读取口时走旧菜品路径，但仍要求可信份量', () async {
    final legacy = AddDishToMeal(
      mealRepository: meals,
      clock: FixedAppClock(now),
    );
    final trusted = DishRecord(
      id: 'legacy-1',
      name: '旧菜',
      mealSlot: 'lunch',
      kcal: 300,
      proteinG: 10,
      carbsG: 40,
      fatG: 8,
      source: 'manual',
      servingGrams: 250,
      createdAt: now,
      updatedAt: now,
    );
    final mealId = await legacy.run(dish: trusted, localDate: '2026-11-09');
    final item = (await meals.getById(mealId))!.items.single;
    expect(item.grams, 250);
    expect(item.nutrition.kcal, 300);
    expect(item.sourceType, 'dish');
    expect((await meals.getById(mealId))!.source, 'dish_library');

    final assumed = DishRecord(
      id: 'legacy-2',
      name: '份量假设',
      mealSlot: 'lunch',
      kcal: 300,
      proteinG: 10,
      carbsG: 40,
      fatG: 8,
      source: 'manual',
      servingGrams: 100,
      basisAssumed: true,
      createdAt: now,
      updatedAt: now,
    );
    await expectLater(
      legacy.run(dish: assumed, localDate: '2026-11-09'),
      throwsA(isA<ServingGramsUnknown>()),
    );
  });

  test('A18 预览与最终记餐同一份量：候选上的数字 = 记进去的数字', () async {
    await seedSupply(
      id: 'supply-rice',
      name: '米饭',
      kcal: 116,
      servingGrams: 220,
      proteinPer100g: 2.6,
      carbsPer100g: 25.9,
      fatPer100g: 0.3,
    );
    final dish = await candidateOf('supply-rice');
    expect(dish.kcal, closeTo(255.2, 1e-9), reason: '预览：116 × 220 ÷ 100');

    final mealId = await add.run(dish: dish, localDate: '2026-11-09');
    final item = (await meals.getById(mealId))!.items.single;
    expect(item.nutrition.kcal, closeTo(dish.kcal, 1e-9));
    expect(item.nutrition.proteinGrams, closeTo(dish.proteinG, 1e-9));
    expect(item.grams, 220);
  });

  test('改主修订后不重算已记的餐，但新记的一份用新值', () async {
    final foodId = await seedSupply(
      id: 'supply-gb',
      name: '宫保鸡丁',
      kcal: 180,
      servingGrams: 200,
    );
    final first = await add.run(
      dish: await candidateOf('supply-gb'),
      localDate: '2026-11-09',
    );
    await catalog.reviseMasterFood(
      foodId: foodId,
      kcalPer100g: 210,
      proteinPer100g: 12,
      carbsPer100g: 8,
      fatPer100g: 15,
    );
    final old = (await meals.getById(first))!.items.single;
    expect(old.nutrition.kcal, closeTo(360, 1e-9), reason: '历史餐不重算');

    final second = await add.run(
      dish: await candidateOf('supply-gb'),
      localDate: '2026-11-09',
    );
    expect(
      (await meals.getById(second))!.items.single.nutrition.kcal,
      closeTo(420, 1e-9),
    );
    expect(
      (await meals.getById(second))!.items.single.nutritionRevisionId,
      isNot(old.nutritionRevisionId),
      reason: '快照记下各自当时的修订',
    );
  });
}
