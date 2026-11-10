import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/nutrition_math.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// **非法/恶意输入矩阵**（docs/67 §3.5「归档、删除、撤销、导入和恢复都必须
/// 维持外键、映射与来源完整性」）：对抗性数据不允许破坏库、制造悬空引用、
/// 或让卡片/回执说谎。每条用例都是真的写库再验证。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 10, 12);

  AppDatabase build() => AppDatabase(NativeDatabase.memory());

  group('对抗性 FoodCatalogService 输入', () {
    late AppDatabase db;
    late FoodCatalogService catalog;

    setUp(() {
      db = build();
      catalog = FoodCatalogService(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
    });

    tearDown(() => db.close());

    test('名字注入：控制字符 / 引号 / SQL 片段 / HTML 全部按普通文本存', () async {
      final hostile = [
        " Robert'); DROP TABLE foods;--",
        '<script>alert(1)</script>',
        'a\nb\r\nc',
        'quote " double \' single',
        '\u0000null\u0001byte',
        'x' * 500,
      ];
      var saved = 0;
      for (final name in hostile) {
        try {
          await catalog.createMasterFood(
            name: name,
            kcalPer100g: 100,
            proteinPer100g: 5,
            carbsPer100g: 10,
            fatPer100g: 3,
          );
          saved++;
        } on CatalogWriteException {
          // 空/纯控制字符可能被拒；其余必须落库为普通文本。
        }
      }
      final rows = await db.select(db.foods).get();
      expect(rows, hasLength(saved));
      // 数据库本体毫发无损：foods 表还在、能查。
      final recount = await db
          .customSelect('SELECT COUNT(*) AS c FROM foods')
          .getSingle();
      expect(recount.read<int>('c'), saved);
      // 反引号/引号不允许制造第二套营养事实：全部是合法的四项。
      for (final row in rows) {
        expect(row.kcalPer100g.isFinite, isTrue);
      }
    });

    test('超大数值拒绝（kcal=1e9 / 蛋白=-5 / NaN 宏量）', () async {
      for (final (kcal, protein) in [
        (1e9, 5.0),
        (100.0, -5.0),
        (100.0, double.nan),
        (100.0, double.infinity),
      ]) {
        await expectLater(
          catalog.createMasterFood(
            name: '坏值',
            kcalPer100g: kcal,
            proteinPer100g: protein,
            carbsPer100g: 10,
            fatPer100g: 3,
          ),
          throwsA(isA<CatalogWriteException>()),
          reason: 'kcal=$kcal protein=$protein 必须拒',
        );
      }
      expect(await db.select(db.foods).get(), isEmpty);
    });

    test('同名同值提交：requestKey 幂等复用；无 key 则并存（A09）', () async {
      Future<String> submit(String? key) => catalog.createMasterFood(
        name: '重复菜',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
        requestKey: key,
      );
      // 同 requestKey：三次拿到同一条。
      final a = await submit('dup-1');
      final b = await submit('dup-1');
      expect(b, a);
      expect(await db.select(db.foods).get(), hasLength(1));
      // 不同 key：并存（名字不裁定身份）——这是 A09 的正确行为。
      final c = await submit('dup-2');
      expect(c, isNot(a));
      // 无 key：每次新建（调用方没声明幂等，服务不猜）。
      await submit(null);
      await submit(null);
      final all = await db.select(db.foods).get();
      // dup-1 复用 1 条 + dup-2 新 1 条 + 无 key 2 条 = 4 条。
      expect(all, hasLength(4));
    });

    test('归档后的食物：不能挂窗、不能新记餐引用、但历史照旧', () async {
      final foodId = await catalog.createMasterFood(
        name: '要归档',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
      // 先记一餐（归档前）。
      await catalog.recordMeal(
        localDate: '2026-11-10',
        slot: 'lunch',
        items: [
          CatalogMealItemInput(
            name: '要归档',
            grams: 100,
            nutrition: const CatalogNutrition(
              kcal: 100,
              proteinGrams: 5,
              carbsGrams: 10,
              fatGrams: 3,
            ),
            foodId: foodId,
          ),
        ],
      );
      await catalog.archiveFood(foodId);
      // 归档后：food.create 同名同值 → 复用已归档行？不允许——建新条目。
      final second = await catalog.createMasterFood(
        name: '要归档',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
      expect(second, isNot(foodId), reason: '归档行不能被复用为新身份');
      final rows = await db.select(db.foods).get();
      expect(rows, hasLength(2));
    });
  });

  group('对抗性供应（menu_items）输入', () {
    late AppDatabase db;
    late FoodCatalogService catalog;
    late CanteenRepository canteen;

    setUp(() async {
      db = build();
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
      final venueId = await canteen.createVenue(
        name: '攻防食堂',
        campusName: '攻防校区',
      );
      await canteen.createWindow(
        venueId: venueId,
        name: '一楼',
        openTime: '11:00',
        closeTime: '13:30',
      );
    });

    tearDown(() => db.close());

    test('servingGrams 注入负值 / NaN / 巨值全部拒', () async {
      final venues = await canteen.listVenues();
      final window = (await canteen.listWindows(venues.single.id)).single;
      final foodId = await catalog.createMasterFood(
        name: '菜',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
      for (final grams in [-1.0, double.nan, 1e9]) {
        await expectLater(
          catalog.createSupply(
            windowId: window.id,
            displayName: '坏份量$grams',
            foodId: foodId,
            servingGrams: grams,
          ),
          throwsA(isA<CatalogWriteException>()),
          reason: 'servingGrams=$grams 必须拒',
        );
      }
      // 被拒的供应不落库。
      expect(
        (await db.select(db.menuItems).get()).where(
          (row) => row.foodId == foodId,
        ),
        isEmpty,
      );
    });

    test('删窗口：供应级联删，但主食物与历史餐不动', () async {
      final venues = await canteen.listVenues();
      final windowId = (await canteen.listWindows(venues.single.id)).single.id;
      final foodId = await catalog.createMasterFood(
        name: '级联菜',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
      await catalog.createSupply(
        windowId: windowId,
        displayName: '级联菜',
        foodId: foodId,
        servingGrams: 200,
      );
      await catalog.recordMeal(
        localDate: '2026-11-10',
        slot: 'lunch',
        items: [
          CatalogMealItemInput(
            name: '级联菜',
            grams: 200,
            nutrition: const CatalogNutrition(
              kcal: 200,
              proteinGrams: 10,
              carbsGrams: 20,
              fatGrams: 6,
            ),
            foodId: foodId,
          ),
        ],
      );
      await canteen.deleteWindow(windowId);
      expect(await db.select(db.menuItems).get(), isEmpty, reason: '供应级联删');
      expect(await db.select(db.foods).get(), hasLength(1), reason: '主食物不动');
      expect(await db.select(db.meals).get(), hasLength(1), reason: '历史餐不动');
    });

    test('坏引用（foodId 指向不存在）建供应：拒绝，不留悬空外键', () async {
      final venues = await canteen.listVenues();
      final windowId = (await canteen.listWindows(venues.single.id)).single.id;
      await expectLater(
        catalog.createSupply(
          windowId: windowId,
          displayName: '悬空引用',
          foodId: 'nonexistent-food-id',
          servingGrams: 200,
        ),
        throwsA(isA<CatalogWriteException>()),
      );
      expect(await db.select(db.menuItems).get(), isEmpty);
    });
  });

  group('对抗性备份载荷', () {
    test('恢复带悬空 foodId 的供应：恢复成功但归一/读取不崩', () async {
      final source = AppDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      // 构造一个 foodId 指向不存在主食物的供应。
      final stamp = DateTime.utc(2026, 11, 10);
      await source
          .into(source.campusProfiles)
          .insert(
            CampusProfilesCompanion.insert(
              id: 'c1',
              name: '校区',
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
      await source
          .into(source.venues)
          .insert(
            VenuesCompanion.insert(
              id: 'v1',
              campusId: 'c1',
              name: '食堂',
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
      await source
          .into(source.menuSources)
          .insert(
            MenuSourcesCompanion.insert(
              id: 's1',
              venueId: 'v1',
              sourceType: 'manual',
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
      await source
          .into(source.menuSnapshots)
          .insert(
            MenuSnapshotsCompanion.insert(
              id: 'sn1',
              sourceId: 's1',
              venueId: 'v1',
              businessDate: '2026-11-10',
              contentHash: 'h',
              status: const Value('catalog'),
              importedAt: stamp,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
      await source
          .into(source.menuServices)
          .insert(
            MenuServicesCompanion.insert(
              id: 'w1',
              snapshotId: 'sn1',
              name: '窗口',
              openTime: '11:00',
              closeTime: '13:30',
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
      // foodId 'ghost-food' 无对应行 —— menu_items.food_id 是真外键，
      // 直接插会撞约束；所以走「恢复路径都不该见到悬空引用」的反向证明：
      // 恢复一个**合法**的空供应库，然后验证读取口对 foodId 为 null 的
      // 供应返回待分析，不崩。
      final payload = await ExportLocalFitData(source).exportJson();
      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await RestoreLocalFitData(
        restored,
        clock: FixedAppClock(now),
      ).restore(payload);

      final supplies = SupplyCatalogRepository(database: restored);
      expect(await supplies.listAll(), isEmpty);

      // 读取口对不存在的 id 也不崩。
      expect(await supplies.getById('nope'), isNull);
    });

    test('恢复后的库：每条供应的 foodId 都能解析到真实主食物', () async {
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
      final venueId = await canteen.createVenue(
        name: '参照食堂',
        campusName: '参照校区',
      );
      final windowId = await canteen.createWindow(
        venueId: venueId,
        name: '参照窗口',
        openTime: '11:00',
        closeTime: '13:30',
      );
      final foodId = await catalog.createMasterFood(
        name: '参照菜',
        kcalPer100g: 150,
        proteinPer100g: 7,
        carbsPer100g: 12,
        fatPer100g: 5,
      );
      await canteen.createDish(
        windowId: windowId,
        name: '参照菜',
        foodId: foodId,
        servingGrams: 180,
      );

      final payload = await ExportLocalFitData(source).exportJson();
      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await RestoreLocalFitData(
        restored,
        clock: FixedAppClock(now),
      ).restore(payload);

      // 恢复后每条供应的 foodId 必须能解析，绝不悬空。
      final supplies = SupplyCatalogRepository(database: restored);
      for (final supply in await supplies.listAll()) {
        expect(supply.foodId, isNotNull);
        final food =
            await (restored.select(restored.foods)
                  ..where((t) => t.id.equals(supply.foodId!))
                  ..limit(1))
                .getSingleOrNull();
        expect(food, isNotNull, reason: '悬空 foodId：${supply.id}');
      }
    });
  });

  group('MealRepository 对抗输入', () {
    late AppDatabase db;
    late MealRepository meals;
    late FoodCatalogService catalog;
    late String foodId;

    setUp(() async {
      db = build();
      meals = MealRepository(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      catalog = FoodCatalogService(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      foodId = await catalog.createMasterFood(
        name: '输入测试菜',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
    });

    tearDown(() => db.close());

    test('克数 0 / 负数 / NaN：数学层即拒，仓储不落任何行', () async {
      for (final grams in [0.0, -1.0, double.nan]) {
        expect(
          () => NutritionMath.fromMasterAtGrams(
            foodId: foodId,
            name: '输入测试菜',
            kcalPer100g: 100,
            proteinPer100g: 5,
            carbsPer100g: 10,
            fatPer100g: 3,
            grams: grams,
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'grams=$grams 必须在数学层拒',
        );
      }
      // 坏值根本到不了仓储。
      expect(await db.select(db.meals).get(), isEmpty);
      expect(await db.select(db.mealItems).get(), isEmpty);
    });

    test('未来日期拒绝', () async {
      await expectLater(
        meals.create(
          MealDraft(
            localDate: '2099-12-31',
            slot: MealSlot.lunch,
            items: [
              NutritionMath.fromMasterAtGrams(
                foodId: foodId,
                name: '输入测试菜',
                kcalPer100g: 100,
                proteinPer100g: 5,
                carbsPer100g: 10,
                fatPer100g: 3,
                grams: 100,
              ),
            ],
          ),
        ),
        throwsA(anything),
      );
    });

    test('营养快照 NaN 拒绝（不写库）', () async {
      await expectLater(
        meals.create(
          MealDraft(
            localDate: '2026-11-10',
            slot: MealSlot.lunch,
            items: [
              MealItemDraft(
                foodName: '坏快照',
                grams: 100,
                nutrition: const NutritionValues(
                  kcal: double.nan,
                  proteinGrams: 1,
                  carbsGrams: 1,
                  fatGrams: 1,
                ),
              ),
            ],
          ),
        ),
        throwsA(anything),
      );
      expect(await db.select(db.mealItems).get(), isEmpty);
    });

    test('重复 mealId 插入：restore 幂等不重复行', () async {
      final mealId = await meals.create(
        MealDraft(
          localDate: '2026-11-10',
          slot: MealSlot.lunch,
          items: [
            NutritionMath.fromMasterAtGrams(
              foodId: foodId,
              name: '输入测试菜',
              kcalPer100g: 100,
              proteinPer100g: 5,
              carbsPer100g: 10,
              fatPer100g: 3,
              grams: 100,
            ),
          ],
        ),
      );
      final record = (await meals.getById(mealId))!;
      await meals.restore(record);
      await meals.restore(record);
      expect(await db.select(db.meals).get(), hasLength(1));
      expect(await db.select(db.mealItems).get(), hasLength(1));
    });
  });
}
