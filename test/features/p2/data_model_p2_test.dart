import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/domain/ingredients.dart';
import 'package:localfit_ai/features/jobs/application/job_scheduler.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/features/nutrition/application/add_dish_to_meal.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';

/// P2（schema 28）行为判据：份量口径、配料/过敏原三层来源、队列底座。
void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 10, 18, 12);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  CanteenRepository canteen() => CanteenRepository(
    database: db,
    idGenerator: const _SeqIds(),
    clock: FixedAppClock(now),
  );

  DishLibraryRepository dishes() => DishLibraryRepository(
    database: db,
    idGenerator: const _SeqIds(),
    clock: FixedAppClock(now),
  );

  MealRepository meals() => MealRepository(
    database: db,
    idGenerator: const _SeqIds(),
    clock: FixedAppClock(now),
  );

  group('份量口径（docs/40 §2.2 不变量）', () {
    test('食堂菜 per100g=150、servingGrams=250 ⇒ 供应按份派生 375 kcal/份', () async {
      final repo = canteen();
      final now2 = DateTime.utc(2026, 10, 18);
      await db
          .into(db.campusProfiles)
          .insert(
            CampusProfilesCompanion.insert(
              id: 'c1',
              name: '示范大学',
              createdAt: now2,
              updatedAt: now2,
            ),
          );
      await db
          .into(db.venues)
          .insert(
            VenuesCompanion.insert(
              id: 'v1',
              campusId: 'c1',
              name: '东区食堂',
              createdAt: now2,
              updatedAt: now2,
            ),
          );
      final windowId = await repo.createWindow(
        venueId: 'v1',
        name: '一楼',
        openTime: '11:00',
        closeTime: '13:30',
      );
      final dishId = await repo.createDish(windowId: windowId, name: '番茄牛腩饭');
      await repo.recordNutrition(
        dishId: dishId,
        kcalPer100g: 150,
        proteinPer100g: 7,
        carbsPer100g: 20,
        fatPer100g: 5,
        grade: 'D',
        confidence: 0.6,
      );
      await repo.updateDishTagsAndIngredients(
        dishId: dishId,
        tags: const ['午餐'],
        ingredients: const CanteenIngredientInfo(entries: []),
        servingGrams: 250,
        setServingGrams: true,
      );

      // docs/67 P2-U23：食堂供应不再复制进菜品库；"一份多少"由供应自己的
      // 每份克数 × 主食物每 100g 派生。
      expect(
        await db.select(db.dishLibrary).get(),
        isEmpty,
        reason: '自动复制链已退役',
      );
      final catalog = FoodCatalogService(
        database: db,
        idGenerator: const _SeqIds(),
        clock: FixedAppClock(now),
      );
      final foodId = await catalog.createMasterFood(
        name: '番茄牛腩饭',
        kcalPer100g: 150,
        proteinPer100g: 7,
        carbsPer100g: 20,
        fatPer100g: 5,
      );
      await repo.linkSupplyToFood(dishId: dishId, foodId: foodId);
      final supply = (await SupplyCatalogRepository(database: db)
          .getById(dishId))!;
      expect(supply.servingGrams, 250);
      expect(supply.servingGramsStatus, ServingGramsStatus.known);
      expect(supply.kcalPer100g, closeTo(150, 0.001), reason: '每 100g 来自主库');
      expect(
        supply.kcalPerServing,
        closeTo(375, 0.001),
        reason: '150 × 250/100',
      );
      expect(supply.state, SupplyNutritionState.servingKnown);
    });

    test('没有 servingGrams 的菜：份量未知，不派生"一份"数', () async {
      final repo = canteen();
      final now2 = DateTime.utc(2026, 10, 18);
      await db
          .into(db.campusProfiles)
          .insert(
            CampusProfilesCompanion.insert(
              id: 'c1',
              name: '示范大学',
              createdAt: now2,
              updatedAt: now2,
            ),
          );
      await db
          .into(db.venues)
          .insert(
            VenuesCompanion.insert(
              id: 'v1',
              campusId: 'c1',
              name: '东区食堂',
              createdAt: now2,
              updatedAt: now2,
            ),
          );
      final windowId = await repo.createWindow(
        venueId: 'v1',
        name: '一楼',
        openTime: '11:00',
        closeTime: '13:30',
      );
      final dishId = await repo.createDish(windowId: windowId, name: '历史菜');
      await repo.recordNutrition(
        dishId: dishId,
        kcalPer100g: 150,
        proteinPer100g: 7,
        carbsPer100g: 20,
        fatPer100g: 5,
        grade: 'D',
        confidence: 0.6,
      );
      final supply = (await SupplyCatalogRepository(database: db)
          .getById(dishId))!;
      expect(supply.servingGrams, isNull);
      expect(supply.servingGramsStatus, ServingGramsStatus.unknown);
      expect(
        supply.state,
        SupplyNutritionState.needsAnalysis,
        reason: '没链接主食物时仍是「待分析」，不是 0 千卡',
      );
      expect(supply.kcalPerServing, isNull);
    });

    test('菜品加进餐：按 servingGrams 缩放，不固定 100g', () async {
      final library = dishes();
      final repo = meals();
      final dish = await library.create(
        DishDraft(
          name: '红烧肉',
          mealSlot: '午餐',
          kcal: 375,
          proteinG: 20,
          carbsG: 10,
          fatG: 30,
          source: 'manual',
          servingGrams: 250,
        ),
      );
      await AddDishToMeal(
        mealRepository: repo,
        clock: FixedAppClock(now),
      ).run(dish: dish, localDate: '2026-10-18');
      final meal = (await repo.watchForDate('2026-10-18').first).single;
      final item = meal.items.single;
      expect(item.grams, 250, reason: '默认记一份 = servingGrams');
      expect(item.nutrition.kcal, closeTo(375, 0.001));
      expect(item.sourceType, 'dish');
      expect(item.sourceId, dish.id);
    });

    test('菜品加进餐：给克数则按比例缩放（grams/servingGrams）', () async {
      final library = dishes();
      final repo = meals();
      final dish = await library.create(
        DishDraft(
          name: '红烧肉',
          mealSlot: '午餐',
          kcal: 375,
          proteinG: 20,
          carbsG: 10,
          fatG: 30,
          source: 'manual',
          servingGrams: 250,
        ),
      );
      await AddDishToMeal(
        mealRepository: repo,
        clock: FixedAppClock(now),
      ).run(dish: dish, localDate: '2026-10-18', grams: 125);
      final item =
          (await repo.watchForDate('2026-10-18').first).single.items.single;
      expect(item.grams, 125);
      expect(
        item.nutrition.kcal,
        closeTo(187.5, 0.001),
        reason: '375 × 125/250',
      );
    });
  });

  group('配料与过敏原（三层来源 + 由食材推导）', () {
    test('用户 > AI > 词典：用户改过则 AI 不覆盖', () {
      const userInfo = CanteenIngredientInfo(
        entries: [
          IngredientEntry(
            name: '花生',
            source: IngredientSource.user,
            confidence: 1,
          ),
        ],
        userEdited: true,
      );
      final merged = userInfo.mergeAi(const [
        IngredientEntry(name: '鸡肉', source: IngredientSource.ai),
      ]);
      expect(merged.entries.map((e) => e.name), ['花生']);
      expect(merged.isConfirmed, isTrue);
    });

    test('词典推测条目被 AI 推断升档（不改变用户条目）', () {
      const info = CanteenIngredientInfo(
        entries: [
          IngredientEntry(name: '番茄', source: IngredientSource.dictionary),
        ],
      );
      final merged = info.mergeAi(const [
        IngredientEntry(
          name: '番茄',
          source: IngredientSource.ai,
          confidence: 0.8,
        ),
      ]);
      expect(merged.entries.single.source, IngredientSource.ai);
    });

    test('过敏原由食材推导：蛋→蛋类、面粉→麸质、虾→甲壳类、豆腐→大豆', () {
      expect(allergensForIngredient('鸡蛋'), contains('蛋类'));
      expect(allergensForIngredient('面粉'), contains('麸质'));
      expect(allergensForIngredient('虾仁'), contains('甲壳类'));
      expect(allergensForIngredient('豆腐'), contains('大豆'));
      expect(allergensForIngredient('芒果'), isEmpty, reason: '查不到不猜');
    });

    test('忌口词 ∩（食材 ∪ 过敏原组）判定冲突', () {
      const info = CanteenIngredientInfo(
        entries: [
          IngredientEntry(name: '鸡蛋', source: IngredientSource.user),
          IngredientEntry(name: '面粉', source: IngredientSource.ai),
        ],
      );
      expect(info.conflictsWith(['蛋类']), {'蛋类'});
      expect(info.conflictsWith(['鸡蛋']), {'鸡蛋'});
      expect(info.conflictsWith(['花生']), isEmpty);
      // 用户声明任意食材名（如「芒果」）也能参与匹配（自由字符串口径）。
      expect(info.conflictsWith(['芒果']), isEmpty);
    });

    test('没有配料数据的菜 = 「配料未确认」，不假装安全', () {
      const info = CanteenIngredientInfo(entries: []);
      expect(info.isEmpty, isTrue);
      expect(info.badgeLabel, '配料未确认');
      expect(info.conflictsWith(['蛋类']), isEmpty);
    });

    test('词典兜底按菜名推主要食材（离线可用）', () {
      final entries = dictionaryIngredients('番茄炒蛋');
      final names = entries.map((e) => e.name).toSet();
      expect(names, containsAll(['番茄', '鸡蛋']));
      expect(
        entries.every((e) => e.source == IngredientSource.dictionary),
        isTrue,
      );
    });

    test('配料 JSON 往返（落库格式）', () {
      const info = CanteenIngredientInfo(
        entries: [
          IngredientEntry(
            name: '鸡肉',
            source: IngredientSource.ai,
            confidence: 0.8,
          ),
        ],
      );
      final decoded = CanteenIngredientInfo.decode(info.encode());
      expect(decoded.entries.single.name, '鸡肉');
      expect(decoded.entries.single.source, IngredientSource.ai);
      expect(CanteenIngredientInfo.decode('not json').isEmpty, isTrue);
    });
  });

  group('任务调度（G11：充电+空闲、可暂停、断点续跑）', () {
    BackgroundJobRepository repo() => BackgroundJobRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: _SeqIds(),
    );

    test('未充电：重任务不跑并保持 pending（只放回这一条）', () async {
      final jobs = repo();
      await jobs.enqueue(type: 'indexRebuild');
      await jobs.enqueue(type: 'dishAnalysis');
      final scheduler = JobScheduler(
        repository: jobs,
        conditions: () => const JobRunConditions(charging: false, idle: true),
        handlers: {
          'indexRebuild': (_) async => true,
          'dishAnalysis': (_) async => true,
        },
      );
      final tick = await scheduler.tick();
      // 轻任务（dishAnalysis）允许跑；**重任务必须留在 pending**。
      expect(tick.completed, lessThanOrEqualTo(1));
      expect(
        await jobs.count(
          state: BackgroundJobState.pending,
          type: 'indexRebuild',
        ),
        1,
        reason: '未充电时索引重建不得执行',
      );
    });

    test('充电+空闲：重任务跑完并出队', () async {
      final jobs = repo();
      await jobs.enqueue(type: 'indexRebuild', dedupeKey: 'rebuild');
      final scheduler = JobScheduler(
        repository: jobs,
        conditions: () => const JobRunConditions(charging: true, idle: true),
        handlers: {'indexRebuild': (_) async => true},
      );
      final tick = await scheduler.tick();
      expect(tick.completed, 1);
      expect(await jobs.count(), 0);
    });

    test('暂停后不领取任务；恢复后继续', () async {
      final jobs = repo();
      await jobs.enqueue(type: 'dishAnalysis');
      final scheduler = JobScheduler(
        repository: jobs,
        conditions: () => const JobRunConditions(charging: true, idle: true),
        handlers: {'dishAnalysis': (_) async => true},
      );
      scheduler.pause();
      final paused = await scheduler.tick();
      expect(paused.skippedReason, 'paused');
      expect(await jobs.count(state: BackgroundJobState.pending), 1);
      scheduler.resume();
      final resumed = await scheduler.tick();
      expect(resumed.completed, 1);
    });

    test('断点续跑：上次进程留下的 processing 会被放回并重跑', () async {
      final jobs = repo();
      await jobs.enqueue(type: 'dishAnalysis');
      // 模拟「领了任务但进程被杀」。
      await jobs.claimNext();
      expect(await jobs.count(state: BackgroundJobState.processing), 1);
      final scheduler = JobScheduler(
        repository: jobs,
        conditions: () => const JobRunConditions(charging: false, idle: true),
        handlers: {'dishAnalysis': (_) async => true},
      );
      final tick = await scheduler.tick();
      expect(tick.completed, 1);
      expect(await jobs.count(), 0);
    });

    test('处理器失败 ⇒ failed 可重试；未注册处理器 ⇒ failed 并写明原因', () async {
      final jobs = repo();
      await jobs.enqueue(type: 'dishAnalysis');
      await jobs.enqueue(type: 'unknownType');
      final scheduler = JobScheduler(
        repository: jobs,
        conditions: () => const JobRunConditions(charging: false, idle: true),
        handlers: {'dishAnalysis': (_) async => false},
      );
      final tick = await scheduler.tick();
      expect(tick.failed, 2);
      final failed = await jobs.list(state: BackgroundJobState.failed);
      expect(failed.map((j) => j.lastError), contains('未注册处理器：unknownType'));
    });

    test('非空闲：一律不跑', () async {
      final jobs = repo();
      await jobs.enqueue(type: 'dishAnalysis');
      final scheduler = JobScheduler(
        repository: jobs,
        conditions: () => const JobRunConditions(charging: false, idle: false),
        handlers: {'dishAnalysis': (_) async => true},
      );
      final tick = await scheduler.tick();
      expect(tick.skippedReason, 'notIdle');
      expect(await jobs.count(state: BackgroundJobState.pending), 1);
    });
  });

  group('后台任务队列（G16 底座）', () {
    BackgroundJobRepository jobs() => BackgroundJobRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: const _SeqIds(),
    );

    test('入队幂等：同 dedupeKey 的未完成任务不重复入队', () async {
      final repo = jobs();
      final first = await repo.enqueue(
        type: 'dishAnalysis',
        payload: {'dishId': 'd1'},
        dedupeKey: 'dishAnalysis:d1',
      );
      final second = await repo.enqueue(
        type: 'dishAnalysis',
        dedupeKey: 'dishAnalysis:d1',
      );
      expect(second, first);
      expect(await repo.count(), 1);
    });

    test('领取 → 失败 → 重试 → 完成（attempts 递增）', () async {
      final repo = jobs();
      await repo.enqueue(type: 'indexRebuild');
      final job = await repo.claimNext();
      expect(job, isNotNull);
      expect(job!.attempts, 1);
      expect(await repo.count(state: BackgroundJobState.processing), 1);

      await repo.fail(job.id, error: 'boom');
      expect(await repo.count(state: BackgroundJobState.failed), 1);
      expect((await repo.list()).single.lastError, 'boom');

      expect(await repo.retryFailed(), 1);
      final second = await repo.claimNext();
      expect(second!.attempts, 2);
      await repo.complete(second.id);
      expect(await repo.count(), 0);
    });

    test('断点续跑：processing 的僵死任务可放回 pending', () async {
      final repo = jobs();
      await repo.enqueue(type: 'dishAnalysis');
      await repo.claimNext();
      expect(await repo.count(state: BackgroundJobState.processing), 1);
      expect(await repo.recoverInterrupted(), 1);
      expect(await repo.count(state: BackgroundJobState.pending), 1);
    });

    test('进度与心跳可写', () async {
      final repo = jobs();
      final id = await repo.enqueue(type: 'indexRebuild');
      await repo.claimNext();
      await repo.reportProgress(id, 42);
      await repo.touch(id);
      expect((await repo.list()).single.progress, 42);
    });
  });
}

class _SeqIds implements IdGenerator {
  const _SeqIds();
  @override
  String next() => 'id-${_counter++}';
}

int _counter = 0;
