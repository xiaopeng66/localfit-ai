import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/domain/food_write_failure.dart';
import 'package:localfit_ai/features/nutrition/application/nutrition_math.dart';
import 'package:localfit_ai/features/nutrition/application/catalog_search.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';

/// 统一每 100g 营养主库 + 食堂供应引用的**核心契约**（docs/67 §3、§4、§5）。
///
/// 这些用例是行为证明，不是源码字符串检查：每条都真的写库、再读回来断言。
void main() {
  late AppDatabase database;
  late FoodCatalogService catalog;
  late SupplyCatalogRepository supplies;
  late String venueId;
  late String windowA;
  late String windowB;
  final now = DateTime.utc(2026, 11, 9, 4);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    catalog = FoodCatalogService(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    supplies = SupplyCatalogRepository(database: database);
    venueId = await _seedVenue(database, now);
    windowA = await _seedWindow(database, venueId, '一窗口', now);
    windowB = await _seedWindow(database, venueId, '二窗口', now);
  });

  tearDown(() => database.close());

  group('身份与单位', () {
    test('A01 只存库：可被发现，但不会自己挂窗、也不会自己记餐', () async {
      final foodId = await catalog.createMasterFood(
        name: '宫保鸡丁',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
      );

      final food = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(foodId))).getSingle();
      expect(food.kcalPer100g, 180);
      expect(food.currentRevisionId, isNotNull, reason: '生效修订指针必须同时写好');
      expect(await database.select(database.menuItems).get(), isEmpty);
      expect(await database.select(database.meals).get(), isEmpty);
    });

    test('主表四项是生效修订的投影，不是第二个事实', () async {
      final foodId = await catalog.createMasterFood(
        name: '番茄炒蛋',
        kcalPer100g: 120,
        proteinPer100g: 6,
        carbsPer100g: 5,
        fatPer100g: 8,
      );
      final first = await _activeRevision(database, foodId);
      expect(first.revisionNumber, 1);
      expect(first.kcalPer100g, 120);
      expect(first.origin, 'user_input');

      final revisionId = await catalog.reviseMasterFood(
        foodId: foodId,
        kcalPer100g: 140,
        proteinPer100g: 6,
        carbsPer100g: 6,
        fatPer100g: 9,
        expectedRevisionNumber: 1,
      );
      final food = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(foodId))).getSingle();
      expect(food.currentRevisionId, revisionId);
      expect(food.kcalPer100g, 140, reason: '投影必须跟着生效修订走');
      final second = await _activeRevision(database, foodId);
      expect(second.revisionNumber, 2);
    });

    test('并发版本冲突：读后被别人改过就拒绝，不静默覆盖', () async {
      final foodId = await catalog.createMasterFood(
        name: '清炒时蔬',
        kcalPer100g: 60,
        proteinPer100g: 2,
        carbsPer100g: 8,
        fatPer100g: 2,
      );
      await catalog.reviseMasterFood(
        foodId: foodId,
        kcalPer100g: 70,
        proteinPer100g: 2,
        carbsPer100g: 9,
        fatPer100g: 2,
        expectedRevisionNumber: 1,
      );
      await expectLater(
        catalog.reviseMasterFood(
          foodId: foodId,
          kcalPer100g: 80,
          proteinPer100g: 2,
          carbsPer100g: 9,
          fatPer100g: 2,
          expectedRevisionNumber: 1,
        ),
        throwsA(isA<CatalogVersionConflict>()),
      );
      final food = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(foodId))).getSingle();
      expect(food.kcalPer100g, 70, reason: '冲突时不能写入');
    });

    test('A09 同名不同品牌保留不同 ID——名字不裁定身份', () async {
      final a = await catalog.createMasterFood(
        name: '酸奶',
        brand: '甲',
        kcalPer100g: 70,
        proteinPer100g: 3,
        carbsPer100g: 10,
        fatPer100g: 2,
      );
      final b = await catalog.createMasterFood(
        name: '酸奶',
        brand: '乙',
        kcalPer100g: 90,
        proteinPer100g: 3,
        carbsPer100g: 14,
        fatPer100g: 2,
      );
      expect(a, isNot(b));
      final rows = await (database.select(
        database.foods,
      )..where((t) => t.name.equals('酸奶'))).get();
      expect(rows, hasLength(2));
    });

    test('营养四项不齐不允许进主库（不插入假零食物）', () async {
      await expectLater(
        catalog.createMasterFood(
          name: '来历不明',
          kcalPer100g: double.nan,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ),
        throwsA(isA<CatalogWriteException>()),
      );
      expect(await database.select(database.foods).get(), isEmpty);
    });

    test('"每份营养 + 无依据克数"不能换算出每 100g', () async {
      await expectLater(
        catalog.createMasterFoodFromServing(
          name: '盖浇饭',
          kcalPer100gPerServing: 600,
          proteinPerServing: 20,
          carbsPerServing: 80,
          fatPerServing: 20,
          servingGrams: 100,
          servingGramsStatus: ServingGramsStatus.estimated,
          servingGramsSource: ServingGramsSource.legacyUnverified,
        ),
        throwsA(isA<CatalogWriteException>()),
      );
      expect(await database.select(database.foods).get(), isEmpty);
    });
  });

  group('食堂供应引用主库', () {
    test('A03 两窗口引用同一主食物、各自份量：360 / 450 千卡', () async {
      final foodId = await catalog.createMasterFood(
        name: '宫保鸡丁',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
      );
      final left = await catalog.createSupply(
        windowId: windowA,
        displayName: '宫保鸡丁',
        foodId: foodId,
        servingGrams: 200,
        servingGramsStatus: ServingGramsStatus.known,
        servingGramsSource: ServingGramsSource.userInput,
      );
      final right = await catalog.createSupply(
        windowId: windowB,
        displayName: '宫保鸡丁',
        foodId: foodId,
        servingGrams: 250,
        servingGramsStatus: ServingGramsStatus.known,
        servingGramsSource: ServingGramsSource.weighed,
      );

      final a = (await supplies.getById(left.supplyId))!;
      final b = (await supplies.getById(right.supplyId))!;
      expect(a.kcalPer100g, 180, reason: '供应不存独立的每份营养副本');
      expect(a.kcalPerServing, 360);
      expect(b.kcalPerServing, 450);

      final half = NutritionMath.fromSupply(
        supplyId: b.id,
        displayName: b.displayName,
        kcalPer100g: b.kcalPer100g!,
        proteinPer100g: b.proteinPer100g!,
        carbsPer100g: b.carbsPer100g!,
        fatPer100g: b.fatPer100g!,
        servings: 0.5,
        servingGrams: b.servingGrams,
        foodId: b.foodId,
        revisionId: b.revisionId,
        servingGramsStatus: b.servingGramsStatus,
      );
      expect(half.grams, 125);
      expect(half.nutrition.kcal, closeTo(225, 1e-9));
      expect(half.servings, 0.5);
      expect(half.supplyId, b.id);

      final one = NutritionMath.fromSupply(
        supplyId: a.id,
        displayName: a.displayName,
        kcalPer100g: a.kcalPer100g!,
        proteinPer100g: a.proteinPer100g!,
        carbsPer100g: a.carbsPer100g!,
        fatPer100g: a.fatPer100g!,
        servings: 1,
        servingGrams: a.servingGrams,
        foodId: a.foodId,
        revisionId: a.revisionId,
        servingGramsStatus: a.servingGramsStatus,
      );
      expect(one.grams, 200);
      expect(one.nutrition.kcal, closeTo(360, 1e-9));
    });

    test('A04 改一窗口份量只影响它自己', () async {
      final foodId = await catalog.createMasterFood(
        name: '宫保鸡丁',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
      );
      final left = await catalog.createSupply(
        windowId: windowA,
        displayName: '宫保鸡丁',
        foodId: foodId,
        servingGrams: 200,
        servingGramsSource: ServingGramsSource.userInput,
      );
      final right = await catalog.createSupply(
        windowId: windowB,
        displayName: '宫保鸡丁',
        foodId: foodId,
        servingGrams: 250,
        servingGramsSource: ServingGramsSource.userInput,
      );
      await catalog.updateSupplyWindowInfo(
        supplyId: left.supplyId,
        servingGrams: 220,
        servingGramsStatus: ServingGramsStatus.known,
        servingGramsSource: ServingGramsSource.userInput,
      );
      final a = (await supplies.getById(left.supplyId))!;
      final b = (await supplies.getById(right.supplyId))!;
      expect(a.kcalPerServing, closeTo(396, 1e-9));
      expect(b.kcalPerServing, 450);
    });

    test('A05 局部重估默认分叉：另一窗口与原主修订都不动', () async {
      final foodId = await catalog.createMasterFood(
        name: '宫保鸡丁',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
      );
      final left = await catalog.createSupply(
        windowId: windowA,
        displayName: '宫保鸡丁',
        foodId: foodId,
        servingGrams: 200,
        servingGramsSource: ServingGramsSource.userInput,
      );
      final right = await catalog.createSupply(
        windowId: windowB,
        displayName: '宫保鸡丁',
        foodId: foodId,
        servingGrams: 250,
        servingGramsSource: ServingGramsSource.userInput,
      );

      final variantId = await catalog.forkVariant(
        sourceFoodId: foodId,
        name: '宫保鸡丁（二窗口偏油）',
        kcalPer100g: 210,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 15,
      );
      await catalog.relinkSupply(supplyId: right.supplyId, foodId: variantId);

      final variant = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(variantId))).getSingle();
      expect(variant.variantOfFoodId, foodId);
      expect(variant.kcalPer100g, 210);

      final original = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(foodId))).getSingle();
      expect(original.kcalPer100g, 180, reason: '共享条目不能被窗口局部重估改掉');

      final a = (await supplies.getById(left.supplyId))!;
      final b = (await supplies.getById(right.supplyId))!;
      expect(a.foodId, foodId);
      expect(b.foodId, variantId);
      expect(a.kcalPerServing, 360);
      expect(b.kcalPerServing, 525);
    });

    test('A06 共享修订：预览受影响供应，历史餐快照逐字段不变', () async {
      final foodId = await catalog.createMasterFood(
        name: '红烧肉',
        kcalPer100g: 400,
        proteinPer100g: 14,
        carbsPer100g: 6,
        fatPer100g: 36,
      );
      final left = await catalog.createSupply(
        windowId: windowA,
        displayName: '红烧肉',
        foodId: foodId,
        servingGrams: 150,
        servingGramsSource: ServingGramsSource.userInput,
      );
      await catalog.createSupply(
        windowId: windowB,
        displayName: '红烧肉',
        foodId: foodId,
        servingGrams: 200,
        servingGramsSource: ServingGramsSource.userInput,
      );
      final mealId = await catalog.recordMeal(
        localDate: '2026-11-09',
        slot: 'lunch',
        items: [
          CatalogMealItemInput(
            name: '红烧肉',
            grams: 150,
            nutrition: const CatalogNutrition(
              kcal: 600,
              proteinGrams: 21,
              carbsGrams: 9,
              fatGrams: 54,
            ),
            foodId: foodId,
            sourceType: 'menu_item',
            sourceId: left.supplyId,
            supplyId: left.supplyId,
            servings: 1,
            servingGrams: 150,
          ),
        ],
      );
      final before = await _mealSnapshot(database, mealId);

      final impact = await catalog.previewRevision(foodId);
      expect(impact.supplyCount, 2);
      expect(impact.historicalMealsUnchanged, isTrue);

      await catalog.reviseMasterFood(
        foodId: foodId,
        kcalPer100g: 420,
        proteinPer100g: 14,
        carbsPer100g: 6,
        fatPer100g: 38,
      );

      final after = await _mealSnapshot(database, mealId);
      expect(after, before, reason: '改主库不能重算历史餐');
      final a = (await supplies.getById(left.supplyId))!;
      expect(a.kcalPerServing, closeTo(630, 1e-9), reason: '未来一份按新修订派生');
    });

    test('A07 已链接但份量未知：可按克记，按"份"被拦截且不补 100g', () async {
      final foodId = await catalog.createMasterFood(
        name: '炒面',
        kcalPer100g: 200,
        proteinPer100g: 6,
        carbsPer100g: 28,
        fatPer100g: 7,
      );
      final supply = await catalog.createSupply(
        windowId: windowA,
        displayName: '炒面',
        foodId: foodId,
        servingGramsStatus: ServingGramsStatus.unknown,
        servingGramsSource: ServingGramsSource.legacyUnknown,
      );
      final item = (await supplies.getById(supply.supplyId))!;
      expect(item.isAnalyzable, isTrue);
      expect(item.canRecordByServing, isFalse);
      expect(item.kcalPerServing, isNull, reason: '份量未知不派生"一份多少千卡"');

      expect(
        () => NutritionMath.fromSupply(
          supplyId: item.id,
          displayName: item.displayName,
          kcalPer100g: item.kcalPer100g!,
          proteinPer100g: item.proteinPer100g!,
          carbsPer100g: item.carbsPer100g!,
          fatPer100g: item.fatPer100g!,
          servings: 1,
          servingGrams: item.servingGrams,
          servingGramsStatus: item.servingGramsStatus,
        ),
        throwsA(isA<ServingGramsUnknown>()),
      );

      final byGrams = NutritionMath.fromMasterAtGrams(
        foodId: foodId,
        name: item.displayName,
        kcalPer100g: item.kcalPer100g!,
        proteinPer100g: item.proteinPer100g!,
        carbsPer100g: item.carbsPer100g!,
        fatPer100g: item.fatPer100g!,
        grams: 180,
        sourceType: 'menu_item',
        sourceId: item.id,
      );
      expect(byGrams.grams, 180);
      expect(byGrams.nutrition.kcal, closeTo(360, 1e-9));
    });

    test('A08 待分析供应：不是 0 千卡，也不进自动推荐', () async {
      final supply = await catalog.createSupply(
        windowId: windowA,
        displayName: '新菜品',
        servingGrams: 250,
        servingGramsSource: ServingGramsSource.aiEstimate,
        servingGramsStatus: ServingGramsStatus.estimated,
      );
      final item = (await supplies.getById(supply.supplyId))!;
      expect(item.state, SupplyNutritionState.needsAnalysis);
      expect(item.kcalPer100g, isNull);
      expect(item.kcalPerServing, isNull);
      expect(item.isAutoRecommendable, isFalse);
      expect(item.isAnalyzable, isFalse);
    });

    test('A15 删供应不删主食物；主食物仍被引用时不能硬删', () async {
      final foodId = await catalog.createMasterFood(
        name: '土豆丝',
        kcalPer100g: 80,
        proteinPer100g: 2,
        carbsPer100g: 15,
        fatPer100g: 1,
      );
      final left = await catalog.createSupply(
        windowId: windowA,
        displayName: '土豆丝',
        foodId: foodId,
        servingGrams: 150,
        servingGramsSource: ServingGramsSource.userInput,
      );
      await catalog.createSupply(
        windowId: windowB,
        displayName: '土豆丝',
        foodId: foodId,
        servingGrams: 180,
        servingGramsSource: ServingGramsSource.userInput,
      );

      await (database.delete(
        database.menuItems,
      )..where((t) => t.id.equals(left.supplyId))).go();

      expect(
        await (database.select(
          database.foods,
        )..where((t) => t.id.equals(foodId))).get(),
        hasLength(1),
        reason: '删一条供应不能顺手动主食物',
      );
      expect(await database.select(database.menuItems).get(), hasLength(1));
      await expectLater(
        catalog.deleteFoodIfUnreferenced(foodId),
        throwsA(isA<CatalogWriteException>()),
      );
      await catalog.archiveFood(foodId);
      final archived = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(foodId))).getSingle();
      expect(archived.archivedAt, isNotNull);
      expect(await database.select(database.menuItems).get(), hasLength(1));
    });

    test('A15 食物库删除入口同样守住引用：被供应引用时给出可归档的说明', () async {
      final foodId = await catalog.createMasterFood(
        name: '被引用的菜',
        kcalPer100g: 90,
        proteinPer100g: 4,
        carbsPer100g: 12,
        fatPer100g: 2,
      );
      await catalog.createSupply(
        windowId: windowA,
        displayName: '被引用的菜',
        foodId: foodId,
        servingGrams: 200,
        servingGramsSource: ServingGramsSource.userInput,
      );
      final repository = FoodRepository(
        database: database,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      await expectLater(
        repository.delete(foodId),
        throwsA(isA<FoodWriteFailure>()),
      );
      // 数据没被删：主食物仍在、供应仍指向它。
      final food = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(foodId))).getSingle();
      expect(food.archivedAt, isNull);
      final supply = (await supplies.listAll()).single;
      expect(supply.foodId, foodId);
    });

    test('删掉未被引用的主食物：台账保留、指针断开（重跑归一不会再造一条）', () async {
      final foodId = await catalog.createMasterFood(
        name: '要删的菜',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
      final now0 = now;
      await database
          .into(database.legacyEntityMappings)
          .insert(
            LegacyEntityMappingsCompanion.insert(
              id: 'ledger-1',
              legacyKind: 'dish_library',
              legacyId: 'dish-1',
              sourceFingerprint: 'fp',
              conversionVersion: 'legacy-nutrition-v1',
              outcome: 'converted',
              originalBasis: 'perServing',
              preservedJson: '{}',
              createdAt: now0,
              updatedAt: now0,
              foodId: drift.Value(foodId),
            ),
          );
      final repository = FoodRepository(
        database: database,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      await repository.delete(foodId);
      expect(
        await (database.select(
          database.foods,
        )..where((t) => t.id.equals(foodId))).get(),
        isEmpty,
      );
      final ledger = await database.select(database.legacyEntityMappings).get();
      expect(ledger, hasLength(1), reason: '台账不能连历史一起删');
      expect(ledger.single.foodId, isNull);
      expect(ledger.single.outcome, 'converted');
    });

    test('组合提交失败不留孤儿：窗口不存在时连主食物都不写', () async {
      await expectLater(
        catalog.createSupply(
          windowId: 'missing-window',
          displayName: '新菜',
          newFood: const NewMasterFoodInput(
            name: '新菜',
            kcalPer100g: 100,
            proteinPer100g: 5,
            carbsPer100g: 10,
            fatPer100g: 3,
          ),
        ),
        throwsA(isA<CatalogWriteException>()),
      );
      expect(await database.select(database.foods).get(), isEmpty);
      expect(await database.select(database.menuItems).get(), isEmpty);
    });

    test('重复请求（同一 requestKey）不重复建主食物', () async {
      final first = await catalog.createMasterFood(
        name: '重复提交',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
        requestKey: 'req-1',
      );
      final second = await catalog.createMasterFood(
        name: '重复提交',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
        requestKey: 'req-1',
      );
      expect(second, first);
      expect(await database.select(database.foods).get(), hasLength(1));
    });
  });

  group('三入口统一发现（A01/A09）', () {
    test('同一主食物在食物库、记餐搜索、食堂选食物三处是同一个 ID', () async {
      final foodId = await catalog.createMasterFood(
        name: '宫保鸡丁',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
      );
      // ① 食物库入口（LIKE 分页）。
      final library = await database.select(database.foods).get();
      expect(library.map((row) => row.id), contains(foodId));

      // ② 记餐搜索（CatalogSearch：食物 + 供应 + 旧菜品）。
      final mealHits = await CatalogSearch(
        foods: FoodRepository(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: FixedAppClock(now),
        ),
        dishes: DishLibraryRepository(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: FixedAppClock(now),
        ),
        supplies: supplies,
      ).search('宫保');
      expect(mealHits.foods.map((row) => row.id), contains(foodId));

      // ③ 食堂挂窗时的选食物（同一个主库）。
      final referenceHits = await _FoodSearchProbe(database).search('宫保');
      expect(referenceHits, contains(foodId));

      // 名字只做检索：另一条同名的**不同做法**不会共享这个 ID。
      final variantId = await catalog.createMasterFood(
        name: '宫保鸡丁',
        cookingNote: '二窗口偏油',
        kcalPer100g: 210,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 15,
      );
      expect(variantId, isNot(foodId));
      final both = await _FoodSearchProbe(database).search('宫保');
      expect(both, containsAll(<String>[foodId, variantId]));
    });

    test('建库后立刻可被记餐搜索发现（不重启）', () async {
      final foodId = await catalog.createMasterFood(
        name: '新入库的菜',
        kcalPer100g: 120,
        proteinPer100g: 8,
        carbsPer100g: 10,
        fatPer100g: 5,
      );
      final hits = await CatalogSearch(
        foods: FoodRepository(
          database: database,
          idGenerator: const UuidV7Generator(),
          clock: FixedAppClock(now),
        ),
        dishes: null,
        supplies: supplies,
      ).search('新入库');
      expect(hits.foods.map((row) => row.id), contains(foodId));
    });
  });
}

/// 主库里按名字/品牌检索（食堂挂窗"选已有主食物"用的同一条查询）。
final class _FoodSearchProbe {
  const _FoodSearchProbe(this.database);
  final AppDatabase database;

  Future<List<String>> search(String query) async {
    final rows = await (database.select(
      database.foods,
    )..where((t) => t.name.like('%$query%'))).get();
    return [for (final row in rows) row.id];
  }
}

Future<String> _seedVenue(AppDatabase database, DateTime now) async {
  const venueId = 'venue-1';
  await database
      .into(database.campusProfiles)
      .insert(
        CampusProfilesCompanion.insert(
          id: 'campus-1',
          name: '主校区',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.venues)
      .insert(
        VenuesCompanion.insert(
          id: venueId,
          campusId: 'campus-1',
          name: '香园',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.menuSources)
      .insert(
        MenuSourcesCompanion.insert(
          id: 'source-$venueId',
          venueId: venueId,
          sourceType: 'manual',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.menuSnapshots)
      .insert(
        MenuSnapshotsCompanion.insert(
          id: 'snapshot-$venueId',
          sourceId: 'source-$venueId',
          venueId: venueId,
          businessDate: '2026-11-09',
          contentHash: 'hash-$venueId',
          status: const drift.Value('catalog'),
          importedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
  return venueId;
}

Future<String> _seedWindow(
  AppDatabase database,
  String venueId,
  String name,
  DateTime now,
) async {
  final windowId = 'window-${name.hashCode}-$venueId';
  await database
      .into(database.menuServices)
      .insert(
        MenuServicesCompanion.insert(
          id: windowId,
          snapshotId: 'snapshot-$venueId',
          name: name,
          openTime: '11:00',
          closeTime: '13:30',
          createdAt: now,
          updatedAt: now,
        ),
      );
  return windowId;
}

Future<FoodNutritionRevision> _activeRevision(
  AppDatabase database,
  String foodId,
) async {
  final food = await (database.select(
    database.foods,
  )..where((t) => t.id.equals(foodId))).getSingle();
  return (database.select(
    database.foodNutritionRevisions,
  )..where((t) => t.id.equals(food.currentRevisionId!))).getSingle();
}

Future<String> _mealSnapshot(AppDatabase database, String mealId) async {
  final items = await (database.select(
    database.mealItems,
  )..where((t) => t.mealId.equals(mealId))).get();
  return items
      .map(
        (item) => [
          item.foodNameSnapshot,
          item.grams,
          item.kcalSnapshot,
          item.proteinSnapshot,
          item.carbsSnapshot,
          item.fatSnapshot,
        ].join('|'),
      )
      .join(';');
}
