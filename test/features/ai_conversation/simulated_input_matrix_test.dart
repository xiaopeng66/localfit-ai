import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_number_grounding.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

/// **模拟输入矩阵**（2026-11-10 用户：「按理说这些都是你应该提前测试的」）。
///
/// v4132 的教训：我验证了**库里的行**与**回执**，却没有验证**卡片上真正显示
/// 什么**，于是模型按规则 15 抄进来的 `[food:uuid]` 原样上了屏；同时也漏了
/// 「库里没有的品牌饮品」这条常见说法。
///
/// 这份矩阵的做法是：给一批**用户会真的这么说**的话 + 对应的模型信封，跑完整
/// 链路（registry 严格校验 → 展示名解析 → 数字接地 → 执行器落库），然后把
/// **卡片真的渲染出来**，逐条扫描屏幕上所有文字与所有回执，断言：
///
/// 1. **用户可见文本里不出现任何机器引用/裸 id**（`[food:…]`、uuid）；
/// 2. 三个意图互不越权（存库不挂窗、挂窗不记餐）；
/// 3. 同名歧义给候选、不挑第一条；缺食物给「先建」的修复；
/// 4. 旧菜品份量不可信时要求补全，不按 100g 记；
/// 5. 供应的每份克数来自它自己，未知份量不出现"一份多少千卡"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FoodCatalogService catalog;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late MealRepository meals;
  late FoodRepository foods;
  late DishLibraryRepository dishes;
  late RepositoryChatEditExecutor executor;
  late DriftChatEditContextLoader contextLoader;
  late String windowId;

  final now = DateTime.utc(2026, 11, 10, 9);
  final ids = const UuidV7Generator();
  const forbidden = [
    '[food:',
    '[canteen-dish:',
    '[dish:',
    '[window:',
    '[venue:',
    '[meal:',
  ];
  final uuid = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(now);
    foods = FoodRepository(database: db, idGenerator: ids, clock: clock);
    catalog = FoodCatalogService(database: db, idGenerator: ids, clock: clock);
    canteen = CanteenRepository(database: db, idGenerator: ids, clock: clock);
    supplies = SupplyCatalogRepository(database: db);
    meals = MealRepository(database: db, idGenerator: ids, clock: clock);
    dishes = DishLibraryRepository(
      database: db,
      idGenerator: ids,
      clock: clock,
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
        dishLibraryRepository: dishes,
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
          idGenerator: ids,
          channel: StepsChannel(),
          clock: clock,
        ),
        aiMemoryRepository: AiMemoryRepository(
          database: db,
          idGenerator: ids,
          clock: clock,
        ),
      ),
    );
    contextLoader = DriftChatEditContextLoader(
      database: db,
      clock: clock,
      mealRepository: meals,
      dishLibraryRepository: dishes,
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
        clock: clock,
        idGenerator: ids,
      ),
    );
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '11:00',
      closeTime: '13:30',
    );
  });

  tearDown(() => db.close());

  /// 跑一条"模型信封"：解析 → 补展示名 → 数字接地 → 应用（含依赖链）。
  ///
  /// 返回应用后的 turn（行上带 resultMessage / itemLabels），供渲染与扫描。
  Future<ChatEditTurn> runCase(
    String userText,
    Map<String, Object?> envelope, {
    String assistantReply = '',
  }) async {
    final turn = parseChatEditTurn(
      _encode(envelope),
      ChatEditCommandRegistry(),
    );
    expect(turn, isNotNull, reason: '信封必须可解析：$envelope');
    final coordinator = ChatEditCoordinator(
      contextBuilder: contextLoader,
      executor: executor,
      database: db,
    );
    final labelled = await coordinator.annotateItemLabels(turn!);
    if (assistantReply.isNotEmpty) {
      final problem = validateManualCardGrounding(
        labelled,
        userText: userText,
        assistantReply: assistantReply,
      );
      expect(problem, isNull, reason: '这条模拟输入不该被接地拦下：$problem');
    }
    return coordinator.applyProposed(
      labelled,
      confirmDependencies: (_) async => true,
    );
  }

  /// 把卡片真的渲染出来，收集**屏幕上所有文字**。
  Future<List<String>> visibleTexts(
    WidgetTester tester,
    ChatEditTurn turn,
  ) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatEditCard(
              index: 0,
              message: ConversationMessage(
                id: 'msg-${turn.reply.hashCode}',
                role: ConversationRole.assistant,
                text: turn.reply,
                createdAt: now,
                kind: ConversationMessageKind.editProposal,
                editTurn: turn,
              ),
              onApply: () {},
              onApplyRows: (_) {},
              onDismiss: () {},
              onApplySuggestion: (_) {},
              onRepair: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final out = <String>[];
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final data = text.data;
      if (data != null && data.isNotEmpty) out.add(data);
      final span = text.textSpan;
      if (span != null) out.add(span.toPlainText());
    }
    return out;
  }

  void expectNoMachineIds(Iterable<String> texts, {String? where}) {
    for (final text in texts) {
      for (final token in forbidden) {
        expect(
          text.contains(token),
          isFalse,
          reason: '${where ?? ''}出现了机器引用「$token」：$text',
        );
      }
      expect(
        uuid.hasMatch(text),
        isFalse,
        reason: '${where ?? ''}出现了裸 uuid：$text',
      );
    }
  }

  List<String> receiptsOf(ChatEditTurn turn) => [
    for (final row in turn.rows)
      if (row.resultMessage != null) row.resultMessage!,
    for (final row in turn.rows) ...row.itemNotes.values,
  ];

  // ── 场景矩阵 ──────────────────────────────────────────────────────────

  testWidgets('存库：只进食物库，不挂窗不记餐；回执与卡片无 id', (tester) async {
    final turn = await runCase('帮我把宫保鸡丁存到食物库，每 100g 180 千卡、蛋白 12、碳水 8、脂肪 11', {
      'reply': '已存库',
      'edits': [
        {
          'action': 'food.create',
          'args': {
            'name': '宫保鸡丁',
            'kcalPer100g': 180.0,
            'proteinPer100g': 12.0,
            'carbsPer100g': 8.0,
            'fatPer100g': 11.0,
          },
        },
      ],
    }, assistantReply: '每 100g 180 千卡、蛋白 12g、碳水 8g、脂肪 11g。');
    expect(await db.select(db.menuItems).get(), isEmpty, reason: '只存库不能偷偷挂窗');
    expect(await db.select(db.meals).get(), isEmpty, reason: '也不能偷偷记餐');
    expectNoMachineIds(receiptsOf(turn), where: '存库回执');
    expectNoMachineIds(await visibleTexts(tester, turn), where: '存库卡片');
  });

  testWidgets('挂窗：带主引用与份量；回执不得出现 uuid', (tester) async {
    final foodId = await catalog.createMasterFood(
      name: '宫保鸡丁',
      kcalPer100g: 180,
      proteinPer100g: 12,
      carbsPer100g: 8,
      fatPer100g: 11,
    );
    final turn = await runCase('把宫保鸡丁放到一窗口，一份 200 克', {
      'reply': '已上架',
      'edits': [
        {
          'action': 'canteen.dish.create',
          'args': {
            'window': windowId,
            'name': '宫保鸡丁',
            'foodId': foodId,
            'servingGrams': 200.0,
            'contract': 'v2',
          },
        },
      ],
    }, assistantReply: '一份 200 克，每 100g 180 千卡。');
    expect(await db.select(db.meals).get(), isEmpty, reason: '挂窗不记餐');
    expectNoMachineIds(receiptsOf(turn), where: '挂窗回执');
    expectNoMachineIds(await visibleTexts(tester, turn), where: '挂窗卡片');
  });

  testWidgets('挂窗：还没选主食物（待分析）也不显示 uuid', (tester) async {
    final turn = await runCase('先在一窗口建个"神秘炖菜"，营养之后再说', {
      'reply': '已建供应，待分析',
      'edits': [
        {
          'action': 'canteen.dish.create',
          'args': {'window': windowId, 'name': '神秘炖菜'},
        },
      ],
    });
    expect(await db.select(db.menuItems).get(), hasLength(1));
    expectNoMachineIds(receiptsOf(turn), where: '待分析回执');
    expectNoMachineIds(await visibleTexts(tester, turn), where: '待分析卡片');
  });

  testWidgets('记餐（按供应 id）：快照完整、卡片显示供应名', (tester) async {
    final foodId = await catalog.createMasterFood(
      name: '宫保鸡丁',
      kcalPer100g: 180,
      proteinPer100g: 12,
      carbsPer100g: 8,
      fatPer100g: 11,
    );
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '招牌宫保鸡丁',
      foodId: foodId,
      servingGrams: 200,
    );
    final turn = await runCase('午餐吃了半个招牌宫保鸡丁', {
      'reply': '已记入午餐',
      'edits': [
        {
          'action': 'meal.create',
          'args': {
            'slot': 'lunch',
            'items': [
              {'food': '[canteen-dish:$dishId]', 'grams': 100.0},
            ],
            'localDate': '2026-11-10',
          },
        },
      ],
    }, assistantReply: '半份约 100 克。');
    final item = (await db.select(db.mealItems).get()).single;
    expect(item.supplyId, dishId);
    expect(item.kcalSnapshot, closeTo(180, 1e-9));
    final texts = await visibleTexts(tester, turn);
    expect(texts.any((text) => text.contains('招牌宫保鸡丁')), isTrue);
    expectNoMachineIds(texts, where: '记餐卡片');
  });

  testWidgets('记餐（新食物 + 记一餐同卡）：两行都显示名字', (tester) async {
    final turn = await runCase('早餐吃了两个水煮蛋，帮我记上', {
      'reply': '已记入早餐',
      'edits': [
        {
          'action': 'food.create',
          'args': {
            'name': '水煮蛋',
            'kcalPer100g': 143.0,
            'proteinPer100g': 12.6,
            'carbsPer100g': 1.1,
            'fatPer100g': 9.5,
          },
        },
        {
          'action': 'meal.create',
          'args': {
            'slot': 'breakfast',
            'items': [
              {'food': '水煮蛋', 'grams': 100.0},
            ],
            'localDate': '2026-11-10',
          },
        },
      ],
    }, assistantReply: '两个水煮蛋约 100 克。');
    expect(
      turn.rows.where((row) => row.status.name == 'applied'),
      hasLength(2),
    );
    final texts = await visibleTexts(tester, turn);
    expect(texts.any((text) => text.contains('水煮蛋')), isTrue);
    expectNoMachineIds(texts, where: '组合卡片');
  });

  testWidgets('同名歧义：给候选不写库；提示里不出现 id', (tester) async {
    await catalog.createMasterFood(
      name: '酸奶',
      brand: '甲',
      kcalPer100g: 70,
      proteinPer100g: 3,
      carbsPer100g: 10,
      fatPer100g: 2,
    );
    await catalog.createMasterFood(
      name: '酸奶',
      brand: '乙',
      kcalPer100g: 90,
      proteinPer100g: 3,
      carbsPer100g: 14,
      fatPer100g: 2,
    );
    final turn = await runCase('记一盒酸奶', {
      'reply': '需要你选一个',
      'edits': [
        {
          'action': 'meal.create',
          'args': {
            'slot': 'snack',
            'items': [
              {'food': '酸奶', 'grams': 100.0},
            ],
            'localDate': '2026-11-10',
          },
        },
      ],
    });
    final row = turn.rows.single;
    expect(row.status, ChatEditRowStatus.failed);
    expect(row.repair?.kind, ChatEditRepairKind.chooseCatalog);
    expect(await db.select(db.meals).get(), isEmpty, reason: '歧义不写库');
    expectNoMachineIds(receiptsOf(turn), where: '歧义回执');
    expectNoMachineIds(await visibleTexts(tester, turn), where: '歧义卡片');
  });

  testWidgets('缺食物：给「先建」的修复，提示不出现 id', (tester) async {
    final turn = await runCase('记一份"外星烤肉"给我', {
      'reply': '库里没有这道菜',
      'edits': [
        {
          'action': 'meal.create',
          'args': {
            'slot': 'lunch',
            'items': [
              {'food': '外星烤肉', 'grams': 150.0},
            ],
            'localDate': '2026-11-10',
          },
        },
      ],
    });
    final row = turn.rows.single;
    expect(row.status, ChatEditRowStatus.failed);
    expect(row.repair?.kind, ChatEditRepairKind.createFood);
    expectNoMachineIds(receiptsOf(turn), where: '缺食物回执');
    expectNoMachineIds(await visibleTexts(tester, turn), where: '缺食物卡片');
  });

  testWidgets('旧菜品无份量：要求补全，不按 100g 记', (tester) async {
    final dish = await dishes.create(
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
    final turn = await runCase('午餐吃了旧番茄炒蛋一份', {
      'reply': '这条旧记录缺份量',
      'edits': [
        {
          'action': 'meal.create',
          'args': {
            'slot': 'lunch',
            'items': [
              {'food': '[dish:${dish.id}]', 'grams': 200.0},
            ],
            'localDate': '2026-11-10',
          },
        },
      ],
    });
    expect(turn.rows.single.status, ChatEditRowStatus.failed);
    expect(await db.select(db.meals).get(), isEmpty);
    expectNoMachineIds(await visibleTexts(tester, turn), where: '旧菜品卡片');
  });

  testWidgets('品牌饮料（库里没有）：同卡先建库再记，克数与回复一致', (tester) async {
    final turn = await runCase('刚喝了一杯蜜雪冰城无糖茶 500ml，记到加餐', {
      'reply': '已建库并记入加餐',
      'edits': [
        {
          'action': 'food.create',
          'args': {
            'name': '蜜雪冰城无糖茶',
            'kcalPer100g': 4.0,
            'proteinPer100g': 0.2,
            'carbsPer100g': 0.8,
            'fatPer100g': 0.0,
          },
        },
        {
          'action': 'meal.create',
          'args': {
            'slot': 'snack',
            'items': [
              {'food': '蜜雪冰城无糖茶', 'grams': 500.0},
            ],
            'localDate': '2026-11-10',
          },
        },
      ],
    }, assistantReply: '这杯 500ml，约 20 千卡。');
    expect(await db.select(db.meals).get(), hasLength(1));
    expect(
      (await db.select(db.mealItems).get()).single.grams,
      closeTo(500, 1e-9),
    );
    final texts = await visibleTexts(tester, turn);
    expect(texts.any((text) => text.contains('蜜雪冰城无糖茶')), isTrue);
    expectNoMachineIds(texts, where: '品牌饮料卡片');
  });

  testWidgets('坏 id：报错说人话，不回显 uuid', (tester) async {
    final turn = await runCase('把菜品 <失效> 删掉', {
      'reply': '这条已经没了',
      'edits': [
        {
          'action': 'dish.delete',
          'args': {'dishId': '01a163f2-98bc-7c3a-9f11-0b3d5c1a2e33'},
        },
      ],
    });
    expect(turn.rows.single.status, ChatEditRowStatus.failed);
    expectNoMachineIds(receiptsOf(turn), where: '坏 id 回执');
    expectNoMachineIds(await visibleTexts(tester, turn), where: '坏 id 卡片');
  });

  test('供应的份量口径：已知按份、未知不给"一份多少千卡"', () async {
    final foodId = await catalog.createMasterFood(
      name: '炒面',
      kcalPer100g: 200,
      proteinPer100g: 6,
      carbsPer100g: 28,
      fatPer100g: 7,
    );
    final knownId = await canteen.createDish(
      windowId: windowId,
      name: '炒面（大份）',
      foodId: foodId,
      servingGrams: 250,
    );
    final unknownId = await canteen.createDish(
      windowId: windowId,
      name: '炒面（未知份量）',
      foodId: foodId,
    );
    final known = (await supplies.getById(knownId))!;
    final unknown = (await supplies.getById(unknownId))!;
    expect(known.kcalPerServing, closeTo(500, 1e-9));
    expect(unknown.kcalPerServing, isNull);
    expect(unknown.canRecordByServing, isFalse);
    expect(known.state, SupplyNutritionState.servingKnown);
    expect(unknown.state, SupplyNutritionState.servingUnknown);
  });

  test('意图分离：存库后不自动挂窗；挂窗后不自动记餐', () async {
    await runCase('存一个"测试菜"到库里', {
      'reply': '已存库',
      'edits': [
        {
          'action': 'food.create',
          'args': {
            'name': '测试菜',
            'kcalPer100g': 100.0,
            'proteinPer100g': 5.0,
            'carbsPer100g': 10.0,
            'fatPer100g': 3.0,
          },
        },
      ],
    });
    expect(await db.select(db.foods).get(), hasLength(1));
    expect(await db.select(db.menuItems).get(), isEmpty);
    expect(await db.select(db.meals).get(), isEmpty);
  });
}

/// `parseChatEditTurn` 吃的是 JSON 文本；这里用最小的确定性编码器。
String _encode(Map<String, Object?> value) => _encodeValue(value);

String _encodeValue(Object? value) {
  if (value == null) return 'null';
  if (value is num || value is bool) return value.toString();
  if (value is Map) {
    final entries = value.entries.map(
      (entry) => '"${entry.key}":${_encodeValue(entry.value)}',
    );
    return '{${entries.join(',')}}';
  }
  if (value is List) return '[${value.map(_encodeValue).join(',')}]';
  return '"${value.toString().replaceAll('"', '\\"')}"';
}
