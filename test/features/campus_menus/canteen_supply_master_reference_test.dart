import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/master_nutrition_sink_adapter.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';

/// 食堂供应的营养来源与"唯一生效位置"（docs/67 §3.2、P2-U23）。
///
/// 这份用例取代了旧的「食堂菜 → 菜品库自动复制」用例：复制链已退役，
/// 现在断言的是**退役本身**和它的替代路径（证据 = 分析记录，
/// 主食物修订 = 当前事实）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 9, 4);
  late AppDatabase database;
  late FoodCatalogService catalog;
  late CanteenRepository canteen;
  late DishLibraryRepository legacyLibrary;
  late SupplyCatalogRepository supplies;
  late String windowId;

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
      masterNutritionSink: CatalogMasterNutritionSink(catalog),
    );
    legacyLibrary = DishLibraryRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    supplies = SupplyCatalogRepository(database: database);
    final venueId = await canteen.createVenue(name: '三食堂', campusName: '南校区');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '08:00',
      closeTime: '20:00',
    );
  });

  tearDown(() => database.close());

  test('退役：食堂写营养不再往 dish_library 复制一份每份副本', () async {
    final foodId = await catalog.createMasterFood(
      name: '番茄牛腩饭',
      kcalPer100g: 130,
      proteinPer100g: 8,
      carbsPer100g: 18,
      fatPer100g: 4,
    );
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '番茄牛腩饭',
      foodId: foodId,
      servingGrams: 300,
      servingGramsStatus: ServingGramsStatus.known,
      servingGramsSource: ServingGramsSource.userInput,
    );
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 135,
      proteinPer100g: 8.5,
      carbsPer100g: 18,
      fatPer100g: 4.2,
      grade: 'B',
      confidence: 0.8,
      origin: 'ai_estimate',
    );

    expect(
      await database.select(database.dishLibrary).get(),
      isEmpty,
      reason: '自动复制链退役后，不应该再有独立的每份营养副本',
    );

    // 当前营养落在主食物的生效修订上（不是食堂证据里"另一组当前值"）。
    final food = await (database.select(
      database.foods,
    )..where((t) => t.id.equals(foodId))).getSingle();
    expect(food.kcalPer100g, 135);
    final revision = await (database.select(
      database.foodNutritionRevisions,
    )..where((t) => t.id.equals(food.currentRevisionId!))).getSingle();
    expect(revision.revisionNumber, 2);
    expect(revision.origin, 'ai_estimate');
    expect(revision.isEstimated, isTrue);

    // 证据仍然保留为分析记录（可追溯），但它不是"当前值"的唯一入口。
    final evidence = await database
        .select(database.menuItemNutritionEvidence)
        .get();
    expect(evidence, hasLength(1));
    expect(evidence.single.origin, 'ai_estimate');
  });

  test('手填营养：主修订 origin=user_input，不冒充 AI 估算', () async {
    final foodId = await catalog.createMasterFood(
      name: '炒青菜',
      kcalPer100g: 60,
      proteinPer100g: 2,
      carbsPer100g: 6,
      fatPer100g: 3,
    );
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '炒青菜',
      foodId: foodId,
    );
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 65,
      proteinPer100g: 2.2,
      carbsPer100g: 6,
      fatPer100g: 3.1,
      grade: 'D',
      confidence: 1,
      origin: 'user_input',
    );
    final food = await (database.select(
      database.foods,
    )..where((t) => t.id.equals(foodId))).getSingle();
    final revision = await (database.select(
      database.foodNutritionRevisions,
    )..where((t) => t.id.equals(food.currentRevisionId!))).getSingle();
    expect(revision.origin, 'user_input');
    expect(revision.isEstimated, isFalse);
  });

  test('未链接的供应完成分析 → 自动建主食物并链接（两处读数一致）', () async {
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '新分析的红烧肉',
    );
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 420,
      proteinPer100g: 14,
      carbsPer100g: 6,
      fatPer100g: 38,
      grade: 'B',
      confidence: 0.8,
      origin: 'ai_estimate',
    );

    // 目录侧：显示每 100g。
    final dish = (await canteen.listDishes(windowId)).single;
    expect(dish.hasNutrition, isTrue);
    expect(dish.kcalPer100g, 420);

    // 记餐/推荐侧：必须**同样**认为它可分析——不能一边显示有营养、
    // 一边说「待分析，不能直接记餐」。
    final supply = (await supplies.getById(dishId))!;
    expect(supply.foodId, isNotNull, reason: '分析批准后当前营养必须落到主食物（docs/67 §6.2）');
    expect(supply.state, isNot(SupplyNutritionState.needsAnalysis));
    expect(supply.isAnalyzable, isTrue);
    expect(supply.kcalPer100g, 420);
    final food = await (database.select(
      database.foods,
    )..where((t) => t.id.equals(supply.foodId!))).getSingle();
    expect(food.kcalPer100g, 420);
    expect(food.currentRevisionId, isNotNull);
  });

  test('完全没有分析的供应：可先保存为待分析，不显示 0 千卡', () async {
    // 只建供应、不做任何分析：允许保存（不要求为了挂窗录假营养）。
    final dishId = await canteen.createDish(windowId: windowId, name: '新出的菜');
    final item = (await supplies.getById(dishId))!;
    expect(item.foodId, isNull);
    expect(item.kcalPer100g, isNull, reason: '没有主食物就没有当前营养事实');
    expect(item.state, SupplyNutritionState.needsAnalysis);
    expect(item.isAutoRecommendable, isFalse);
    expect(
      await database.select(database.foods).get(),
      isEmpty,
      reason: '没有分析的供应不硬造主食物（也不填零）',
    );
    // 目录侧同样按「未分析」展示，不是 0 千卡。
    final dish = (await canteen.listDishes(windowId)).single;
    expect(dish.hasNutrition, isFalse);
  });

  test('旧 dish_library 行仍在库里可读（只读兼容，不被删除）', () async {
    await legacyLibrary.create(
      DishDraft(
        name: '旧菜',
        mealSlot: 'lunch',
        kcal: 300,
        proteinG: 10,
        carbsG: 40,
        fatG: 8,
        source: 'manual',
        servingGrams: 200,
      ),
    );
    final dishId = await canteen.createDish(windowId: windowId, name: '新菜');
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 100,
      proteinPer100g: 5,
      carbsPer100g: 12,
      fatPer100g: 3,
      grade: 'C',
      confidence: 0.5,
    );
    final rows = await database.select(database.dishLibrary).get();
    expect(rows, hasLength(1), reason: '只读兼容：旧行不会因为新写入而被删/被覆盖');
    expect(rows.single.name, '旧菜');
  });

  test('建供应时带上份量与来源：状态被如实记录', () async {
    final foodId = await catalog.createMasterFood(
      name: '米饭',
      kcalPer100g: 116,
      proteinPer100g: 2.6,
      carbsPer100g: 25.9,
      fatPer100g: 0.3,
    );
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '米饭',
      foodId: foodId,
      servingGrams: 220,
      servingGramsStatus: ServingGramsStatus.known,
      servingGramsSource: ServingGramsSource.weighed,
    );
    final item = (await supplies.getById(dishId))!;
    expect(item.state, SupplyNutritionState.servingKnown);
    expect(item.servingGrams, 220);
    expect(item.servingGramsSource, ServingGramsSource.weighed);
    expect(item.isAutoRecommendable, isTrue);
    expect(item.kcalPerServing, closeTo(255.2, 1e-9));
  });

  test('改份量后状态跟着走：清空 = 未知，不再派生"一份多少千卡"', () async {
    final foodId = await catalog.createMasterFood(
      name: '面条',
      kcalPer100g: 140,
      proteinPer100g: 5,
      carbsPer100g: 22,
      fatPer100g: 3,
    );
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '面条',
      foodId: foodId,
      servingGrams: 250,
      servingGramsStatus: ServingGramsStatus.known,
      servingGramsSource: ServingGramsSource.userInput,
    );
    await canteen.updateDishServingGrams(dishId, null);
    final item = (await supplies.getById(dishId))!;
    expect(item.state, SupplyNutritionState.servingUnknown);
    expect(item.kcalPerServing, isNull);
    expect(item.isAutoRecommendable, isFalse);
  });

  test('换算器不会把 100g 假份量当成已知份量', () async {
    // 直接写入一条"schema 28 风格"的历史行：serving_grams=100 但状态未知。
    final foodId = await catalog.createMasterFood(
      name: '历史菜',
      kcalPer100g: 200,
      proteinPer100g: 8,
      carbsPer100g: 20,
      fatPer100g: 9,
    );
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '历史菜',
      foodId: foodId,
    );
    await (database.update(
      database.menuItems,
    )..where((t) => t.id.equals(dishId))).write(
      MenuItemsCompanion(
        servingGrams: const drift.Value(100),
        servingGramsStatus: const drift.Value('unknown'),
        servingGramsSource: const drift.Value('legacy_unknown'),
      ),
    );
    final item = (await supplies.getById(dishId))!;
    expect(item.servingGrams, 100);
    expect(item.state, SupplyNutritionState.servingUnknown);
    expect(item.canRecordByServing, isFalse);
  });
}
