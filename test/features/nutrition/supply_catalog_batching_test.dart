import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';

/// P3 阶段门与 A21（docs/67 §8 P3、§9）：
/// * **查询次数不随供应条数增长**——1 条与 100 条的页面读取必须是同一量级，
///   不能每行再查一次库；
/// * **改名/改营养后立刻可见**——不重启、不靠"下次进页面"，三处读取口
///   （供应投影、统一检索、AI 快照数据源）都读到新值。
void main() {
  final now = DateTime.utc(2026, 11, 9, 12);

  Future<({AppDatabase db, _Counter counter})> open() async {
    final counter = _Counter();
    final db = AppDatabase(
      NativeDatabase.memory().interceptWith(counter.interceptor),
    );
    return (db: db, counter: counter);
  }

  Future<({String windowId, String venueId})> seedWindow(
    AppDatabase db,
    CanteenRepository canteen,
  ) async {
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '11:00',
      closeTime: '13:30',
    );
    return (windowId: windowId, venueId: venueId);
  }

  /// 在一个**干净库**里量"读数要几条查询"（供应条数由 [count] 决定）。
  Future<int> measureQueries(int count) async {
    final opened = await open();
    final db = opened.db;
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final catalog = FoodCatalogService(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final supplies = SupplyCatalogRepository(database: db);
    final seeded = await seedWindow(db, canteen);
    for (var index = 0; index < count; index++) {
      final foodId = await catalog.createMasterFood(
        name: '菜品$index',
        kcalPer100g: (100 + index).toDouble(),
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
      await canteen.createDish(
        windowId: seeded.windowId,
        name: '菜品$index',
        foodId: foodId,
        servingGrams: 200,
      );
    }
    opened.counter.reset();
    final items = await supplies.listAll();
    expect(items, hasLength(count));
    return opened.counter.selects;
  }

  test('批量读取：100 条供应的查询次数与 1 条相同（无 N+1）', () async {
    final oneQuery = await measureQueries(1);
    final hundredQueries = await measureQueries(100);
    expect(
      hundredQueries,
      oneQuery,
      reason:
          '供应投影必须是固定条数的批量查询（1 条=$oneQuery，'
          '100 条=$hundredQueries）；涨了就说明退化成 N+1 了',
    );
    expect(oneQuery, lessThanOrEqualTo(8), reason: '固定查询数应保持个位数');
  });

  test('食堂目录（地点/窗口/菜品树）同样不随条数增长', () async {
    Future<int> measureCanteen(int count) async {
      final opened = await open();
      final db = opened.db;
      addTearDown(db.close);
      final canteen = CanteenRepository(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      final catalog = FoodCatalogService(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      final seeded = await seedWindow(db, canteen);
      for (var index = 0; index < count; index++) {
        final foodId = await catalog.createMasterFood(
          name: '目录菜$index',
          kcalPer100g: 150,
          proteinPer100g: 7,
          carbsPer100g: 12,
          fatPer100g: 5,
        );
        await canteen.createDish(
          windowId: seeded.windowId,
          name: '目录菜$index',
          foodId: foodId,
          servingGrams: 180,
        );
      }
      opened.counter.reset();
      final venues = await canteen.listVenues();
      final windows = await canteen.listWindowsByVenue(
        venueIds: [seeded.venueId],
      );
      final dishes = await canteen.listDishes(seeded.windowId);
      final used = opened.counter.selects;
      expect(venues.single.dishCount, count);
      expect(venues.single.analyzedCount, count, reason: '主食物派生也要计入"已分析"');
      expect(windows[seeded.venueId]!.single.dishes, hasLength(count));
      expect(dishes, hasLength(count));
      return used;
    }

    final one = await measureCanteen(1);
    final hundred = await measureCanteen(100);
    expect(hundred, one, reason: '目录树的查询数必须与供应条数无关（1 条=$one，100 条=$hundred）');
    // 这里是**三次**独立读取（地点 / 窗口树 / 单窗口列表）之和，每约 4–5 条，
    // 真正的判据是"与条数无关"（上面的相等断言）；上限只防它悄悄变成逐行查。
    expect(one, lessThanOrEqualTo(16), reason: '三次读取的固定查询数总和应是个位数量级');
  });

  test('统一检索同样不随条数增长', () async {
    final opened = await open();
    final db = opened.db;
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final catalog = FoodCatalogService(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final supplies = SupplyCatalogRepository(database: db);
    final seeded = await seedWindow(db, canteen);
    for (var index = 0; index < 40; index++) {
      final foodId = await catalog.createMasterFood(
        name: '检索菜$index',
        kcalPer100g: 120,
        proteinPer100g: 6,
        carbsPer100g: 12,
        fatPer100g: 4,
      );
      await canteen.createDish(
        windowId: seeded.windowId,
        name: '检索菜$index',
        foodId: foodId,
        servingGrams: 180,
      );
    }
    opened.counter.reset();
    final hits = await supplies.search('检索菜');
    expect(hits, hasLength(20), reason: '默认 limit');
    expect(
      opened.counter.selects,
      lessThanOrEqualTo(8),
      reason: '检索也是一次批量装配，不是逐行查',
    );
  });

  test('候选流：先发当前值，写入后再发一次（菜单页首屏不为空）', () async {
    final opened = await open();
    final db = opened.db;
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final catalog = FoodCatalogService(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final supplies = SupplyCatalogRepository(database: db);
    final seeded = await seedWindow(db, canteen);
    final foodId = await catalog.createMasterFood(
      name: '先发一次的菜',
      kcalPer100g: 150,
      proteinPer100g: 8,
      carbsPer100g: 12,
      fatPer100g: 5,
    );
    final dishId = await canteen.createDish(
      windowId: seeded.windowId,
      name: '先发一次的菜',
      foodId: foodId,
      servingGrams: 200,
    );

    final emitted = <List<SupplyCatalogItem>>[];
    final subscription = supplies.watchAnalyzable().listen(emitted.add);
    // 首帧：订阅即发，不依赖任何写入。
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(emitted, hasLength(1), reason: '首屏必须立刻有值');
    expect(emitted.single.map((item) => item.id), [dishId]);

    await catalog.reviseMasterFood(
      foodId: foodId,
      kcalPer100g: 180,
      proteinPer100g: 8,
      carbsPer100g: 12,
      fatPer100g: 6,
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(emitted.length, greaterThanOrEqualTo(2), reason: '写入后要刷新');
    expect(emitted.last.single.kcalPer100g, 180);

    await subscription.cancel();
  });

  test('A21 改主食物营养：供应投影与统一检索立刻读到新值', () async {
    final opened = await open();
    final db = opened.db;
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final catalog = FoodCatalogService(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final supplies = SupplyCatalogRepository(database: db);
    final seeded = await seedWindow(db, canteen);
    final foodId = await catalog.createMasterFood(
      name: '宫保鸡丁',
      kcalPer100g: 180,
      proteinPer100g: 12,
      carbsPer100g: 8,
      fatPer100g: 11,
    );
    final dishId = await canteen.createDish(
      windowId: seeded.windowId,
      name: '宫保鸡丁',
      foodId: foodId,
      servingGrams: 200,
    );

    expect((await supplies.getById(dishId))!.kcalPer100g, 180);

    // 监听：任何一处写入都应该让目录/记餐页收到刷新信号。
    final firstChange = supplies.watchChanges().first;
    final revisionId = await catalog.reviseMasterFood(
      foodId: foodId,
      kcalPer100g: 210,
      proteinPer100g: 12,
      carbsPer100g: 8,
      fatPer100g: 15,
    );
    await firstChange.timeout(const Duration(seconds: 2));

    final after = (await supplies.getById(dishId))!;
    expect(after.kcalPer100g, 210, reason: '不重启就可见');
    expect(after.revisionId, revisionId);
    expect(after.kcalPerServing, closeTo(420, 1e-9));

    // 统一检索（记餐搜索入口）读到的也是新值。
    final hits = await supplies.search('宫保');
    expect(hits.single.kcalPer100g, 210);

    // AI 快照（同一份供应投影）也立刻反映新值——不重启才可见。
    final snapshot = await DriftChatEditContextLoader(
      database: db,
      clock: FixedAppClock(now),
      mealRepository: MealRepository(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      ),
      dishLibraryRepository: DishLibraryRepository(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      ),
      waterRepository: WaterRepository(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      ),
      canteenRepository: canteen,
      supplyCatalog: supplies,
      workoutPlanRepository: WorkoutPlanRepository(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      ),
      workoutSessionRepository: WorkoutSessionRepository(
        database: db,
        clock: FixedAppClock(now),
        idGenerator: const UuidV7Generator(),
      ),
    ).build(userMessage: '帮我看看食堂目录');
    final canteenSection = snapshot.split('【食堂目录】').last;
    expect(canteenSection, contains('210 kcal/100g'));
    expect(canteenSection, contains('一份约 420 kcal'), reason: '份量已知时快照要给出按份派生值');
  });

  test('A21 改展示名：供应名跟着变，但主食物身份不变、按名字也搜得到新名', () async {
    final opened = await open();
    final db = opened.db;
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final catalog = FoodCatalogService(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final supplies = SupplyCatalogRepository(database: db);
    final seeded = await seedWindow(db, canteen);
    final foodId = await catalog.createMasterFood(
      name: '番茄牛腩',
      kcalPer100g: 130,
      proteinPer100g: 8,
      carbsPer100g: 12,
      fatPer100g: 4,
    );
    final dishId = await canteen.createDish(
      windowId: seeded.windowId,
      name: '番茄牛腩',
      foodId: foodId,
      servingGrams: 300,
    );

    await catalog.updateSupplyWindowInfo(
      supplyId: dishId,
      displayName: '招牌番茄牛腩',
    );
    final after = (await supplies.getById(dishId))!;
    expect(after.displayName, '招牌番茄牛腩');
    expect(after.foodId, foodId, reason: '改名不换 ID / 不换主食物');

    expect((await supplies.search('招牌')).single.id, dishId);
    expect((await supplies.search('番茄')).single.id, dishId);

    // 旧名不再命中展示名，但主食物名仍能命中——检索不裁定身份，只是给人找。
    final byFoodName = await supplies.search('番茄牛腩');
    expect(byFoodName.map((item) => item.id), contains(dishId));
  });

  test('归档主食物：供应仍在，但不进自动推荐、不能新挂窗', () async {
    final opened = await open();
    final db = opened.db;
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final catalog = FoodCatalogService(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final supplies = SupplyCatalogRepository(database: db);
    final seeded = await seedWindow(db, canteen);
    final foodId = await catalog.createMasterFood(
      name: '要归档的菜',
      kcalPer100g: 150,
      proteinPer100g: 8,
      carbsPer100g: 12,
      fatPer100g: 5,
    );
    final dishId = await canteen.createDish(
      windowId: seeded.windowId,
      name: '要归档的菜',
      foodId: foodId,
      servingGrams: 200,
    );
    await catalog.archiveFood(foodId);

    final item = (await supplies.getById(dishId))!;
    expect(item.foodArchived, isTrue);
    expect(item.hasCompleteNutrition, isTrue, reason: '既有供应详情仍可解释');
    expect(item.isAutoRecommendable, isFalse, reason: '归档不进自动推荐');
    await expectLater(
      catalog.createSupply(
        windowId: seeded.windowId,
        displayName: '新窗口的同一道菜',
        foodId: foodId,
        servingGrams: 200,
      ),
      throwsA(anything),
      reason: '归档主食物不能新挂窗',
    );
  });
}

/// 记录 `runSelect` 次数（drift 的查询拦截器）。
final class _Counter {
  int selects = 0;

  void reset() => selects = 0;

  QueryInterceptor get interceptor => _CountingInterceptor(this);
}

final class _CountingInterceptor extends QueryInterceptor {
  _CountingInterceptor(this.counter);

  final _Counter counter;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    counter.selects++;
    return executor.runSelect(statement, args);
  }
}
