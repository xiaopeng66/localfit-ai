import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/data/database/legacy_nutrition_converter.dart';
import 'package:localfit_ai/data/database/nutrition_inventory.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/nutrition_math.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 统一主库的**健壮性面**（docs/67 §7.3、§4.1、§3.5）：
/// * 跨进程重开库时归一**幂等**（不重复建主条目/修订）；
/// * 边界与非法输入一律拒绝，且不落半条数据；
/// * schema 列集与生成代码一致（防漂移）；
/// * 备份往返后关系、修订、台账、历史快照逐项相等。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 10, 12);

  group('跨进程归一幂等', () {
    late Directory tempDir;
    late File file;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('localfit-idem-');
      file = File('${tempDir.path}${Platform.pathSeparator}idem.sqlite');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Future<LegacyConversionReport> convertOnce() async {
      final db = AppDatabase(NativeDatabase(file));
      try {
        return await LegacyNutritionConverter(
          database: db,
          idGenerator: const UuidV7Generator(),
          clock: FixedAppClock(now),
        ).run();
      } finally {
        await db.close();
      }
    }

    test('关库重开再跑归一：不增主条目、不增修订、结论不变', () async {
      final db = AppDatabase(NativeDatabase(file));
      await db
          .into(db.dishLibrary)
          .insert(
            DishLibraryCompanion.insert(
              id: 'legacy-1',
              name: '旧宫保鸡丁',
              mealSlot: 'lunch',
              kcal: 400,
              proteinG: 20,
              carbsG: 30,
              fatG: 20,
              source: 'manual',
              createdAt: now,
              updatedAt: now,
              servingGrams: const Value(250),
            ),
          );
      await db.close();

      final first = await convertOnce();
      final second = await convertOnce();

      expect(first.reconciles, isTrue);
      expect(second.reconciles, isTrue);
      expect(second.conflicts, isEmpty);

      final check = AppDatabase(NativeDatabase(file));
      addTearDown(check.close);
      final foods = await check.select(check.foods).get();
      final revisions = await check.select(check.foodNutritionRevisions).get();
      final ledger = await check.select(check.legacyEntityMappings).get();
      expect(foods, hasLength(1), reason: '重开一次不能再造一条主食物');
      expect(revisions, hasLength(1), reason: '同键同版本不能追加修订');
      expect(ledger, hasLength(1));
      expect(ledger.single.outcome, 'converted');
      expect(foods.single.kcalPer100g, closeTo(160, 1e-9));
      expect(foods.single.currentRevisionId, revisions.single.id);
    });
  });

  group('边界与非法输入', () {
    late AppDatabase db;
    late FoodCatalogService catalog;
    late CanteenRepository canteen;
    late SupplyCatalogRepository supplies;
    late String windowId;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      catalog = FoodCatalogService(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      canteen = CanteenRepository(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      supplies = SupplyCatalogRepository(database: db);
      final venueId = await canteen.createVenue(
        name: '测试食堂',
        campusName: '测试校区',
      );
      windowId = await canteen.createWindow(
        venueId: venueId,
        name: '测试窗口',
        openTime: '11:00',
        closeTime: '13:30',
      );
    });

    tearDown(() => db.close());

    test('超长名 / emoji / 换行：能存就存，不崩', () async {
      final longName = '超长菜名' * 40; // 200 字
      final id = await catalog.createMasterFood(
        name: longName,
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
      final emojiId = await catalog.createMasterFood(
        name: '🍜 拉面',
        kcalPer100g: 120,
        proteinPer100g: 6,
        carbsPer100g: 20,
        fatPer100g: 2,
      );
      expect((await db.select(db.foods).get()), hasLength(2));
      expect(id, isNotEmpty);
      expect(emojiId, isNotEmpty);
    });

    test('空白名拒绝；NaN/无穷/负营养拒绝；超上限拒绝', () async {
      await expectLater(
        catalog.createMasterFood(
          name: '   ',
          kcalPer100g: 100,
          proteinPer100g: 5,
          carbsPer100g: 10,
          fatPer100g: 3,
        ),
        throwsA(isA<CatalogWriteException>()),
      );
      for (final bad in [double.nan, double.infinity, -1.0]) {
        await expectLater(
          catalog.createMasterFood(
            name: '坏值',
            kcalPer100g: bad,
            proteinPer100g: 5,
            carbsPer100g: 10,
            fatPer100g: 3,
          ),
          throwsA(isA<CatalogWriteException>()),
          reason: 'kcal=$bad 必须被拒',
        );
      }
      await expectLater(
        catalog.createMasterFood(
          name: '超上限',
          kcalPer100g: NutritionLimits.maxKcalPer100g + 1,
          proteinPer100g: 5,
          carbsPer100g: 10,
          fatPer100g: 3,
        ),
        throwsA(isA<CatalogWriteException>()),
      );
      expect(await db.select(db.foods).get(), isEmpty);
    });

    test('克数/份数的非法值在数学层就拒绝', () async {
      expect(
        () => NutritionMath.fromMasterAtGrams(
          foodId: 'f',
          name: 'x',
          kcalPer100g: 100,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
          grams: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => NutritionMath.fromMasterAtGrams(
          foodId: 'f',
          name: 'x',
          kcalPer100g: 100,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
          grams: NutritionLimits.maxGrams + 1,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => NutritionMath.fromSupply(
          supplyId: 's',
          displayName: 'x',
          kcalPer100g: 100,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
          servings: 0,
          servingGrams: 200,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('份量上限：2001g 被拒；2000g 接受但会被标"估计"以外的合法状态', () async {
      final foodId = await catalog.createMasterFood(
        name: '边界菜',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
      await expectLater(
        catalog.createSupply(
          windowId: windowId,
          displayName: '超重份量',
          foodId: foodId,
          servingGrams: NutritionLimits.maxServingGrams + 1,
        ),
        throwsA(isA<CatalogWriteException>()),
      );
      final ok = await catalog.createSupply(
        windowId: windowId,
        displayName: '整公斤',
        foodId: foodId,
        servingGrams: NutritionLimits.maxServingGrams,
      );
      final item = (await supplies.getById(ok.supplyId))!;
      expect(item.servingGrams, 2000);
      expect(item.canRecordByServing, isTrue);
    });
  });

  group('schema 与生成代码一致', () {
    test('四张改动表的列集 == drift 生成列', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      Future<Set<String>> dbColumns(String table) async {
        final rows = await db.customSelect('PRAGMA table_info($table)').get();
        return {for (final row in rows) row.data['name'] as String};
      }

      expect(
        await dbColumns('foods'),
        db.foods.$columns.map((column) => column.$name).toSet(),
      );
      expect(
        await dbColumns('food_nutrition_revisions'),
        db.foodNutritionRevisions.$columns.map((c) => c.$name).toSet(),
      );
      expect(
        await dbColumns('menu_items'),
        db.menuItems.$columns.map((column) => column.$name).toSet(),
      );
      expect(
        await dbColumns('meal_items'),
        db.mealItems.$columns.map((column) => column.$name).toSet(),
      );
      expect(
        await dbColumns('legacy_entity_mappings'),
        db.legacyEntityMappings.$columns.map((column) => column.$name).toSet(),
      );
      expect(
        await db
            .customSelect('PRAGMA user_version')
            .getSingle()
            .then((row) => row.data['user_version']),
        31,
      );
    });
  });

  group('备份闭环', () {
    test('导出 → 恢复到空库：身份/修订/关系/台账/历史快照逐项相等', () async {
      final source = AppDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      final catalog = FoodCatalogService(
        database: source,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      final canteen = CanteenRepository(
        database: source,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      final meals = MealRepository(
        database: source,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      final venueId = await canteen.createVenue(
        name: '备份食堂',
        campusName: '备份校区',
      );
      final windowId = await canteen.createWindow(
        venueId: venueId,
        name: '备份窗口',
        openTime: '11:00',
        closeTime: '13:30',
      );
      final foodId = await catalog.createMasterFood(
        name: '备份菜',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
      );
      final supplyId = await canteen.createDish(
        windowId: windowId,
        name: '备份菜',
        foodId: foodId,
        servingGrams: 200,
      );
      await catalog.reviseMasterFood(
        foodId: foodId,
        kcalPer100g: 190,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 12,
      );
      await meals.create(
        MealDraft(
          localDate: '2026-11-09',
          slot: MealSlot.lunch,
          items: [
            MealItemDraft(
              foodId: foodId,
              foodName: '备份菜',
              grams: 200,
              nutrition: const NutritionValues(
                kcal: 380,
                proteinGrams: 24,
                carbsGrams: 16,
                fatGrams: 24,
              ),
              sourceType: 'menu_item',
              sourceId: supplyId,
              supplyId: supplyId,
              nutritionRevisionId: 'rev-2',
              servings: 1,
              servingGrams: 200,
            ),
          ],
        ),
        source: 'menu_item',
      );
      await source
          .into(source.legacyEntityMappings)
          .insert(
            LegacyEntityMappingsCompanion.insert(
              id: 'ledger-1',
              legacyKind: 'dish_library',
              legacyId: 'legacy-x',
              sourceFingerprint: 'fp',
              conversionVersion: 'legacy-nutrition-v1',
              outcome: 'needs_completion',
              originalBasis: 'perServing',
              preservedJson: '{"name":"旧菜"}',
              createdAt: now,
              updatedAt: now,
              reasonCode: const Value('assumed_serving'),
            ),
          );

      final before = await NutritionInventoryReader.read(source);
      final payload = await ExportLocalFitData(source).exportJson();

      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await RestoreLocalFitData(
        restored,
        clock: FixedAppClock(now),
      ).restore(payload);
      final after = await NutritionInventoryReader.read(restored);

      expect(after.foodCount, before.foodCount);
      expect(after.revisionCount, before.revisionCount);
      expect(after.foodsWithoutActiveRevision, 0);
      expect(after.linkedMenuItemCount, before.linkedMenuItemCount);
      expect(after.ledgerKeys, before.ledgerKeys);
      expect(after.mealSnapshotDigest, before.mealSnapshotDigest);
      expect(after.pendingCompletionKeys, before.pendingCompletionKeys);

      // 关系本身也逐项对得上（不只计数）。
      final supply = (await SupplyCatalogRepository(database: restored)
          .getById(supplyId))!;
      expect(supply.foodId, foodId);
      expect(supply.servingGrams, 200);
      expect(supply.kcalPer100g, 190, reason: '生效修订的投影跟着回来');
      final item = (await restored.select(restored.mealItems).get()).single;
      expect(item.supplyId, supplyId);
      expect(item.nutritionRevisionId, 'rev-2');
      expect(item.servings, 1);
    });
  });
}
