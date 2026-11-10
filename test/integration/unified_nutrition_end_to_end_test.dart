import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_conversation/data/drift_conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart'
    as chat;
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/add_dish_to_meal.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/master_nutrition_sink_adapter.dart';
import 'package:localfit_ai/features/nutrition/application/supply_dish_candidates.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// **端到端影响自测**（docs/67 §9 A01/A03/A04/A06/A07/A16/A21/A22 的用户视角）。
///
/// 这份文件不测单个类，而是按用户真实动作顺序把整条链跑一遍：
///
/// ```
/// 食堂目录：建地点 → 建窗口 → 建供应（引用食物库 / 每份克数）
/// 菜单页：加入一餐（按份 / 按克）
/// AI：存库 → 挂窗 → 记一餐（三个意图分别落库，互不越权）
/// 重启：旧卡片重新解析、不偷换单位
/// ```
///
/// 所有断言都读**数据库真实行**，不看源码字符串。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File dbFile;
  late AppDatabase db;
  late _Ids ids;
  final now = DateTime.utc(2026, 11, 9, 12);
  late FixedAppClock clock;

  // 生产装配（与 main.dart 同形）：同一套服务被菜单页与 AI 共用。
  late FoodRepository foods;
  late FoodCatalogService catalog;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late MealRepository meals;
  late DishLibraryRepository dishLibrary;
  late AddDishToMeal addDishToMeal;
  late RepositoryChatEditExecutor executor;
  late DriftChatEditContextLoader contextLoader;
  late DriftConversationMessageRepository messageRepository;

  Future<void> openDatabase() async {
    db = AppDatabase(NativeDatabase(dbFile));
    ids = _Ids();
    clock = FixedAppClock(now);
    foods = FoodRepository(database: db, idGenerator: ids, clock: clock);
    catalog = FoodCatalogService(database: db, idGenerator: ids, clock: clock);
    canteen = CanteenRepository(
      database: db,
      idGenerator: ids,
      clock: clock,
      masterNutritionSink: CatalogMasterNutritionSink(catalog),
    );
    supplies = SupplyCatalogRepository(database: db);
    meals = MealRepository(database: db, idGenerator: ids, clock: clock);
    dishLibrary = DishLibraryRepository(
      database: db,
      idGenerator: ids,
      clock: clock,
    );
    addDishToMeal = AddDishToMeal(
      mealRepository: meals,
      clock: clock,
      supplyCatalog: supplies,
    );
    executor = RepositoryChatEditExecutor(
      ChatEditServices(
        database: db,
        clock: clock,
        idGenerator: ids,
        foodRepository: foods,
        foodCatalog: catalog,
        supplyCatalog: supplies,
        mealRepository: meals,
        dishLibraryRepository: dishLibrary,
        waterRepository: WaterRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        measurementRepository: MeasurementRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        planningConstraintsRepository: PlanningConstraintsRepository(
          database: db,
          clock: clock,
        ),
        canteenRepository: canteen,
        workoutPlanRepository: WorkoutPlanRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        exerciseRepository: ExerciseRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        profileIdentityRepository: ProfileIdentityRepository(database: db),
        workoutSessionRepository: WorkoutSessionRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        updateWaterTargetMl: UpdateWaterTargetMl(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
        stepsRepository: StepsRepository(
          database: db,
          channel: StepsChannel(),
          idGenerator: ids,
          clock: clock,
        ),
        aiMemoryRepository: AiMemoryRepository(
          database: db,
          clock: clock,
          idGenerator: ids,
        ),
      ),
    );
    contextLoader = DriftChatEditContextLoader(
      database: db,
      clock: clock,
      mealRepository: meals,
      dishLibraryRepository: dishLibrary,
      waterRepository: WaterRepository(
        database: db,
        idGenerator: ids,
        clock: clock,
      ),
      canteenRepository: canteen,
      supplyCatalog: supplies,
      workoutPlanRepository: WorkoutPlanRepository(
        database: db,
        idGenerator: ids,
        clock: clock,
      ),
      workoutSessionRepository: WorkoutSessionRepository(
        database: db,
        idGenerator: ids,
        clock: clock,
      ),
    );
    messageRepository = DriftConversationMessageRepository(database: db);
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('localfit-e2e-');
    dbFile = File('${tempDir.path}${Platform.pathSeparator}e2e.sqlite');
    await openDatabase();
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// 跑一条 AI 信封（真实 registry 解码 + 真实执行器），返回应用结果。
  Future<List<String>> runEnvelope(String json) async {
    final turn = parseChatEditTurn(json, ChatEditCommandRegistry());
    expect(turn, isNotNull, reason: '信封必须能被 registry 解析：$json');
    final applied = await ChatEditCoordinator(
      contextBuilder: contextLoader,
      executor: executor,
    ).applyProposed(turn!, confirmDependencies: (_) async => true);
    return [
      for (final row in applied.rows)
        '${row.status.name}:${row.resultMessage ?? ''}',
    ];
  }

  Future<({String venueId, String windowId})> seedVenueWindow() async {
    final venueId = await canteen.createVenue(name: '三食堂', campusName: '示范大学');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '11:00',
      closeTime: '13:30',
    );
    return (venueId: venueId, windowId: windowId);
  }

  group('① 食堂目录：建供应 → 目录显示 → 菜单页加入一餐', () {
    test('从食物库选菜 + 每份 200g：目录/统计/记餐三处口径一致', () async {
      final seeded = await seedVenueWindow();
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

      // 目录读侧：每 100g 来自主库、份量可信、状态不再是"未分析"。
      final dish = (await canteen.listDishes(seeded.windowId)).single;
      expect(dish.hasNutrition, isTrue);
      expect(dish.kcalPer100g, 180);
      expect(dish.servingGrams, 200);
      final venues = await canteen.listVenues();
      expect(venues.single.dishCount, 1);
      expect(venues.single.analyzedCount, 1, reason: '地点统计"已分析"要跟上');

      // 菜单页候选：每份口径（180 × 200 / 100）。
      final candidates = supplyDishCandidates(
        await supplies.listAll(analyzableOnly: true),
        now: now,
      );
      expect(candidates.single.kcal, closeTo(360, 1e-9));
      expect(candidates.single.basisAssumed, isFalse);

      // 加入一餐：写全快照。
      final mealId = await addDishToMeal.run(
        dish: candidates.single,
        localDate: '2026-11-09',
      );
      final meal = (await meals.getById(mealId))!;
      expect(meal.source, 'menu_item');
      final item = meal.items.single;
      expect(item.supplyId, dishId);
      expect(item.servings, 1);
      expect(item.servingGrams, 200);
      expect(item.grams, 200);
      expect(item.nutrition.kcal, closeTo(360, 1e-9));
      expect(item.nutritionRevisionId, isNotNull);

      // 当日汇总 = 360（不是每 100g 的 180）。
      final summary = await meals.watchNutritionForDate('2026-11-09').first;
      expect(summary.consumed.kcal, closeTo(360, 1e-9));
    });

    test('按克加入：120g = 216 kcal，份数置空', () async {
      final seeded = await seedVenueWindow();
      final foodId = await catalog.createMasterFood(
        name: '宫保鸡丁',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
      );
      await canteen.createDish(
        windowId: seeded.windowId,
        name: '宫保鸡丁',
        foodId: foodId,
        servingGrams: 200,
      );
      final dish = supplyDishCandidates(
        await supplies.listAll(analyzableOnly: true),
        now: now,
      ).single;

      final mealId = await addDishToMeal.run(
        dish: dish,
        localDate: '2026-11-09',
        grams: 120,
      );
      final item = (await meals.getById(mealId))!.items.single;
      expect(item.grams, 120);
      expect(item.servings, isNull);
      expect(item.nutrition.kcal, closeTo(216, 1e-9));
    });

    test('改一窗口份量只影响它自己；改主修订不重算历史餐', () async {
      final seeded = await seedVenueWindow();
      final foodId = await catalog.createMasterFood(
        name: '宫保鸡丁',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
      );
      await canteen.createDish(
        windowId: seeded.windowId,
        name: '宫保鸡丁',
        foodId: foodId,
        servingGrams: 200,
      );
      final otherWindow = await canteen.createWindow(
        venueId: seeded.venueId,
        name: '二楼档口',
        openTime: '11:00',
        closeTime: '14:00',
      );
      await canteen.createDish(
        windowId: otherWindow,
        name: '宫保鸡丁',
        foodId: foodId,
        servingGrams: 250,
      );

      final byId = {for (final item in await supplies.listAll()) item.id: item};
      final left = byId.values.firstWhere(
        (item) => item.windowId == seeded.windowId,
      );
      final right = byId.values.firstWhere(
        (item) => item.windowId == otherWindow,
      );
      expect(left.kcalPerServing, closeTo(360, 1e-9));
      expect(right.kcalPerServing, closeTo(450, 1e-9));

      // 历史餐（右窗口 1 份 = 450）。
      final mealId = await addDishToMeal.run(
        dish: supplyDishCandidates([right], now: now).single,
        localDate: '2026-11-09',
      );

      // 改左窗口份量 → 396；右窗口与历史餐不变。
      await catalog.updateSupplyWindowInfo(
        supplyId: left.id,
        servingGrams: 220,
      );
      expect(
        (await supplies.getById(left.id))!.kcalPerServing,
        closeTo(396, 1e-9),
      );
      expect(
        (await supplies.getById(right.id))!.kcalPerServing,
        closeTo(450, 1e-9),
      );
      expect(
        (await meals.getById(mealId))!.items.single.nutrition.kcal,
        closeTo(450, 1e-9),
      );

      // 改主修订 210 → 右窗口新一份 525；历史餐仍是 450。
      await catalog.reviseMasterFood(
        foodId: foodId,
        kcalPer100g: 210,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 15,
      );
      expect(
        (await supplies.getById(right.id))!.kcalPerServing,
        closeTo(525, 1e-9),
      );
      expect(
        (await meals.getById(mealId))!.items.single.nutrition.kcal,
        closeTo(450, 1e-9),
        reason: '历史餐永不被重算',
      );
    });

    test('份量未知的供应：目录可显示每 100g，但按"份"记餐被拦', () async {
      final seeded = await seedVenueWindow();
      final foodId = await catalog.createMasterFood(
        name: '炒面',
        kcalPer100g: 200,
        proteinPer100g: 6,
        carbsPer100g: 28,
        fatPer100g: 7,
      );
      final dishId = await canteen.createDish(
        windowId: seeded.windowId,
        name: '炒面',
        foodId: foodId,
      );
      final dish = (await canteen.listDishes(seeded.windowId)).single;
      expect(dish.hasNutrition, isTrue);
      expect(dish.kcalPer100g, 200, reason: '目录仍显示每 100g');
      expect(dish.servingGrams, isNull);

      final supply = (await supplies.getById(dishId))!;
      expect(supply.kcalPerServing, isNull, reason: '不编造"一份多少千卡"');
      expect(supply.isAutoRecommendable, isFalse);
      await expectLater(
        addDishToMeal.run(
          dish: DishRecord(
            id: dishId,
            name: '炒面',
            mealSlot: 'lunch',
            kcal: 200,
            proteinG: 6,
            carbsG: 28,
            fatG: 7,
            source: 'canteen',
            createdAt: now,
            updatedAt: now,
          ),
          localDate: '2026-11-09',
        ),
        throwsA(isA<FormatException>()),
        reason: '按"份"记时必须要求补份量，不补 100g',
      );
      expect(await db.select(db.mealItems).get(), isEmpty);
    });
  });

  group('② AI 三个意图：存库 / 挂窗 / 记餐 各自落库', () {
    test('只存库：进主库，不挂窗、不记餐；快照里能查到同一个 ID', () async {
      final results = await runEnvelope(
        jsonEncode({
          'reply': '已存库',
          'edits': [
            {
              'action': 'food.create',
              'args': {
                'name': '宫保鸡丁',
                'kcalPer100g': 180.0,
                'proteinPer100g': 12,
                'carbsPer100g': 8,
                'fatPer100g': 11,
              },
            },
          ],
        }),
      );
      expect(results.single, startsWith('applied'));
      final food = await db.select(db.foods).getSingle();
      expect(food.kcalPer100g, 180);
      expect(food.currentRevisionId, isNotNull);
      expect(await db.select(db.menuItems).get(), isEmpty, reason: '不擅自挂窗');
      expect(await db.select(db.meals).get(), isEmpty, reason: '不擅自记餐');

      // AI 快照（自建食物段）能看到它，且 id 稳定。
      final snapshot = await contextLoader.build(userMessage: '看看食物库');
      expect(snapshot, contains('[food:${food.id}]'));
    });

    test('挂窗：只建供应（带主引用与份量），不记餐', () async {
      final seeded = await seedVenueWindow();
      final foodId = await catalog.createMasterFood(
        name: '宫保鸡丁',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
      );
      final results = await runEnvelope(
        jsonEncode({
          'reply': '已上架',
          'edits': [
            {
              'action': 'canteen.dish.create',
              'args': {
                'window': seeded.windowId,
                'name': '宫保鸡丁',
                'foodId': foodId,
                'servingGrams': 200.0,
                'servingGramsSource': 'user_input',
                'contract': 'v2',
              },
            },
          ],
        }),
      );
      expect(results.single, startsWith('applied'), reason: results.single);
      final supply = (await db.select(db.menuItems).get()).single;
      expect(supply.foodId, foodId);
      expect(supply.servingGrams, 200);
      expect(supply.servingGramsStatus, 'known');
      expect(await db.select(db.meals).get(), isEmpty);

      final snapshot = await contextLoader.build(userMessage: '看看食堂目录');
      expect(snapshot, contains('[canteen-dish:${supply.id}]'));
      expect(snapshot, contains('一份约 360 kcal'));
    });

    test('记一餐：用 [canteen-dish:] + 明确克数，快照带供应与修订', () async {
      final seeded = await seedVenueWindow();
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
      final results = await runEnvelope(
        jsonEncode({
          'reply': '已记入',
          'edits': [
            {
              'action': 'meal.create',
              'args': {
                'slot': 'lunch',
                'items': [
                  {'food': '[canteen-dish:$dishId]', 'grams': 100.0},
                ],
                'localDate': '2026-11-09',
              },
            },
          ],
        }),
      );
      expect(results.single, startsWith('applied'), reason: results.single);
      final item = (await db.select(db.mealItems).get()).single;
      expect(item.sourceType, 'menu_item');
      expect(item.supplyId, dishId);
      expect(item.grams, 100);
      expect(item.kcalSnapshot, closeTo(180, 1e-9), reason: '180 × 100 ÷ 100');
      expect(item.nutritionRevisionId, isNotNull);
      expect(item.foodId, foodId);
    });

    test('AI 不会把同名不同做法认成同一条（同名并存 + 用 id 精确绑定）', () async {
      final seeded = await seedVenueWindow();
      final normal = await catalog.createMasterFood(
        name: '宫保鸡丁',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
      );
      final oily = await catalog.createMasterFood(
        name: '宫保鸡丁',
        cookingNote: '二窗口偏油',
        kcalPer100g: 230,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 18,
      );
      expect(oily, isNot(normal));

      // 无前缀的裸名字 → 失败并要求用 id（不挑第一条）。
      final ambiguous = await runEnvelope(
        jsonEncode({
          'reply': '记一餐',
          'edits': [
            {
              'action': 'meal.create',
              'args': {
                'slot': 'lunch',
                'items': [
                  {'food': '宫保鸡丁', 'grams': 100.0},
                ],
                'localDate': '2026-11-09',
              },
            },
          ],
        }),
      );
      expect(ambiguous.single, startsWith('failed'));
      expect(await db.select(db.meals).get(), isEmpty);

      // 用 id → 精确落到"偏油"那条。
      final precise = await runEnvelope(
        jsonEncode({
          'reply': '记一餐',
          'edits': [
            {
              'action': 'meal.create',
              'args': {
                'slot': 'lunch',
                'items': [
                  {'food': '[food:$oily]', 'grams': 100.0},
                ],
                'localDate': '2026-11-09',
              },
            },
          ],
        }),
      );
      expect(precise.single, startsWith('applied'), reason: precise.single);
      expect(
        (await db.select(db.mealItems).get()).single.kcalSnapshot,
        closeTo(230, 1e-9),
      );
      expect(seeded.windowId, isNotEmpty);
    });

    test('旧 dish.upsert 卡片：没有每份克数 → 拒绝换算且不入库', () async {
      final results = await runEnvelope(
        jsonEncode({
          'reply': '收录菜品',
          'edits': [
            {
              'action': 'dish.upsert',
              'args': {
                'name': '麻婆豆腐',
                'slot': 'dinner',
                'kcal': 180.0,
                'protein': 12.0,
                'carbs': 8.0,
                'fat': 10.0,
              },
            },
          ],
        }),
      );
      expect(results.single, startsWith('failed'));
      expect(results.single, contains('没有每份克数'));
      expect(await db.select(db.foods).get(), isEmpty);
      expect(await db.select(db.dishLibrary).get(), isEmpty);
    });
  });

  group('③ 重启：旧卡片重新解析、不偷换单位', () {
    test('旧 [dish:id] 卡片重启后仍可读；应用时要求补全份量而不是按 100g', () async {
      // 一条旧菜品（每份口径，份量未知 = schema 28 回填的 100g + 假设）。
      await dishLibrary.create(
        DishDraft(
          name: '旧番茄炒蛋',
          mealSlot: 'lunch',
          kcal: 240,
          proteinG: 10,
          carbsG: 12,
          fatG: 16,
          source: 'manual',
        ),
      );
      final legacy = (await db.select(db.dishLibrary).get()).single;
      expect(legacy.basisAssumed, isTrue);

      // 存一条"已应用过一半"的旧信封 + 一条待应用的。
      final turn = parseChatEditTurn(
        jsonEncode({
          'reply': '记一餐',
          'edits': [
            {
              'action': 'meal.create',
              'args': {
                'slot': 'lunch',
                'items': [
                  {'food': '[dish:${legacy.id}]', 'grams': 100.0},
                ],
                'localDate': '2026-11-09',
              },
            },
          ],
        }),
        ChatEditCommandRegistry(),
      )!;
      await messageRepository.save(
        chat.ConversationMessage(
          id: 'msg-1',
          role: chat.ConversationRole.assistant,
          text: turn.reply,
          createdAt: now,
          kind: chat.ConversationMessageKind.editProposal,
          editTurn: turn,
        ),
      );

      // 重启：关库、重开、从持久化消息里读回来。
      await db.close();
      await openDatabase();
      final loaded = await messageRepository.loadRecent();
      expect(loaded, hasLength(1));
      final restored = loaded.single.editTurn!;
      expect(restored.rows.single.status, ChatEditRowStatus.proposed);
      expect(
        restored.rows.single.command!.args['items'],
        isA<List<Object>>(),
        reason: '重启后信封必须仍能解码（含旧 [dish:] 引用）',
      );

      // 应用：旧菜品份量不可信 → 失败并说明，不写任何餐。
      final applied = await ChatEditCoordinator(
        contextBuilder: contextLoader,
        executor: executor,
      ).applyProposed(restored, confirmDependencies: (_) async => true);
      expect(applied.rows.single.status, ChatEditRowStatus.failed);
      expect(
        applied.rows.single.resultMessage ?? '',
        contains('每份克数'),
        reason: '必须要求补全，不能把"一份"当 100g',
      );
      expect(await db.select(db.meals).get(), isEmpty);
    });

    test('重启后主食物生效修订指针仍在、历史餐快照不变', () async {
      final seeded = await seedVenueWindow();
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
      final dish = supplyDishCandidates(
        await supplies.listAll(analyzableOnly: true),
        now: now,
      ).single;
      final mealId = await addDishToMeal.run(
        dish: dish,
        localDate: '2026-11-09',
      );
      final before = (await meals.getById(mealId))!.items.single;

      await db.close();
      await openDatabase();

      final food = await foods.getById(foodId);
      expect(food, isNotNull);
      expect(
        (await db.select(db.foods).getSingle()).currentRevisionId,
        isNotNull,
      );
      final after = (await meals.getById(mealId))!.items.single;
      expect(after.foodName, before.foodName);
      expect(after.grams, before.grams);
      expect(after.nutrition.kcal, before.nutrition.kcal);
      expect(after.supplyId, dishId);
      final supply = (await supplies.getById(dishId))!;
      expect(
        supply.kcalPerServing,
        closeTo(390, 1e-9),
        reason: '130 × 300 ÷ 100',
      );
    });
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'e2e-${_value++}';
}
