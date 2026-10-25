import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/domain/ingredients.dart';
import 'package:localfit_ai/features/jobs/application/job_scheduler.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/features/nutrition/application/add_canteen_dishes_to_library.dart';
import 'package:localfit_ai/features/nutrition/application/add_dish_to_meal.dart';
import 'package:localfit_ai/features/nutrition/application/dish_staleness.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';

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
    test('食堂菜 per100g=150、servingGrams=250 ⇒ 菜品库 375 kcal/份', () async {
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
      final dish = (await repo.listDishes(windowId)).single;
      expect(dish.servingGrams, 250);

      final library = dishes();
      final result = await AddCanteenDishesToLibrary(
        dishLibrary: library,
        canteen: repo,
      ).run(windowId: windowId, dishes: [dish]);
      expect(result.written, 1);

      final stored = (await library.watchAll().first).single;
      expect(stored.kcal, closeTo(375, 0.001), reason: '150 × 250/100');
      expect(stored.proteinG, closeTo(17.5, 0.001));
      expect(stored.servingGrams, 250);
      expect(stored.basisAssumed, isFalse);
      expect(stored.sourceType, 'canteen');
      expect(stored.sourceId, dishId);
      expect(stored.kcalPer100g, closeTo(150, 0.001), reason: '每 100g 还原');
      expect(stored.kcalForGrams(200), closeTo(300, 0.001));
    });

    test('没有 servingGrams 的菜：每份=per100g 且 basisAssumed=1', () async {
      final library = dishes();
      await library.create(
        DishDraft(
          name: '历史菜',
          mealSlot: '午餐',
          kcal: 150,
          proteinG: 7,
          carbsG: 20,
          fatG: 5,
          source: 'ai_estimate',
        ),
      );
      final stored = (await library.watchAll().first).single;
      expect(stored.servingGrams, isNull);
      expect(stored.basisAssumed, isTrue, reason: '份量未知必须标假设');
      expect(stored.kcalPer100g, closeTo(150, 0.001));
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

  group('来源陈旧（同步提示，docs/40 §6）', () {
    test('来源有更新 ⇒ sourceUpdated；用户改过只提示不覆盖', () async {
      final library = dishes();
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
        proteinPer100g: 6,
        carbsPer100g: 21,
        fatPer100g: 5,
        grade: 'D',
        confidence: 0.5,
      );
      final dish = (await repo.listDishes(windowId)).single;
      await AddCanteenDishesToLibrary(
        dishLibrary: library,
        canteen: repo,
      ).run(windowId: windowId, dishes: [dish]);
      final stored = (await library.watchAll().first).single;

      final checker = DishStalenessChecker(database: db);
      // 刚同步：已是最新。
      expect((await checker.check(stored)).state, DishStalenessState.upToDate);

      // 来源被重新分析（updatedAt 变新）⇒ 提示有更新。
      await repo.recordNutrition(
        dishId: dishId,
        kcalPer100g: 160,
        proteinPer100g: 7,
        carbsPer100g: 22,
        fatPer100g: 6,
        grade: 'D',
        confidence: 0.5,
      );
      final stale = await checker.check(stored);
      expect(stale.state, DishStalenessState.sourceUpdated);
      expect(stale.shouldPrompt, isTrue);
      expect(stale.notice, '食堂营养有更新');
    });

    test('来源删除 ⇒ sourceMissing，不级联删菜品', () async {
      final library = dishes();
      await library.create(
        DishDraft(
          name: '悬空菜',
          mealSlot: '午餐',
          kcal: 200,
          proteinG: 10,
          carbsG: 20,
          fatG: 8,
          source: 'ai_estimate',
          servingGrams: 100,
          sourceType: 'canteen',
          sourceId: 'menu-item-gone',
        ),
      );
      final stored = (await library.watchAll().first).single;
      final result = await DishStalenessChecker(database: db).check(stored);
      expect(result.state, DishStalenessState.sourceMissing);
      expect(result.notice, '来源已删除');
      expect(await library.watchAll().first, hasLength(1), reason: '不级联删');
    });

    test('手工菜（无来源）⇒ unlinked，没有提示', () async {
      final library = dishes();
      await library.create(
        DishDraft(
          name: '自做饭',
          mealSlot: '午餐',
          kcal: 200,
          proteinG: 10,
          carbsG: 20,
          fatG: 8,
          source: 'manual',
          servingGrams: 100,
          sourceType: 'manual',
        ),
      );
      final stored = (await library.watchAll().first).single;
      final result = await DishStalenessChecker(database: db).check(stored);
      expect(result.state, DishStalenessState.unlinked);
      expect(result.notice, isNull);
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
