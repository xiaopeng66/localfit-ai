import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/data/drift_conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_conversation/data/meal_item_labels.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_number_grounding.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';

/// 卡片里的 `items[].food` 是**机器引用**（`[food:uuid]` / `[canteen-dish:uuid]`），
/// 绝不能直接显示给用户（2026-11-10 真机：卡片每行都是 id）。
///
/// 这份用例钉住三件事：
/// 1. 引用能解析成食物名/供应名/旧菜品名（含品牌）；
/// 2. 卡片行标题与组摘要显示**名字**，不显示 id；
/// 3. 数字接地的拒绝文案说的是名字，而且重启后（从库重读）仍然如此。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late FoodCatalogService catalog;
  late CanteenRepository canteen;
  late DishLibraryRepository dishes;
  late String windowId;
  final now = DateTime.utc(2026, 11, 10, 9);

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
    dishes = DishLibraryRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
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

  ChatEditTurn turnOf(Map<String, Object?> command) {
    final raw = <String, Object?>{
      'reply': '记一餐',
      'edits': [
        {'action': command['action'], 'args': command['args']},
      ],
    };
    final turn = parseChatEditTurn(
      // ignore: avoid_dynamic_calls
      _json(raw),
      ChatEditCommandRegistry(),
    );
    expect(turn, isNotNull, reason: '信封必须可解析');
    return turn!;
  }

  test('解析：食物（含品牌）/ 食堂供应 / 旧菜品 都有人话名字', () async {
    final foodId = await catalog.createMasterFood(
      name: '无糖茶',
      brand: '蜜雪冰城',
      kcalPer100g: 4,
      proteinPer100g: 0.2,
      carbsPer100g: 0.8,
      fatPer100g: 0,
    );
    final supplyId = await canteen.createDish(
      windowId: windowId,
      name: '招牌红烧肉',
      foodId: foodId,
      servingGrams: 150,
    );
    final dish = await dishes.create(
      DishDraft(
        name: '旧番茄炒蛋',
        mealSlot: 'lunch',
        kcal: 240,
        proteinG: 10,
        carbsG: 12,
        fatG: 16,
        source: 'manual',
        servingGrams: 200,
      ),
    );

    final labels = await MealItemLabels.resolve(db, [
      {'food': '[food:$foodId]', 'grams': 500.0},
      {'food': '[canteen-dish:$supplyId]', 'grams': 150.0},
      {'food': '[dish:${dish.id}]', 'grams': 200.0},
      {'food': '[food:does-not-exist]', 'grams': 100.0},
      {'food': '手写名字', 'grams': 80.0},
    ]);

    expect(labels['[food:$foodId]'], '无糖茶（蜜雪冰城）');
    expect(labels['[canteen-dish:$supplyId]'], '招牌红烧肉');
    expect(labels['[dish:${dish.id}]'], '旧番茄炒蛋');
    expect(labels.containsKey('[food:does-not-exist]'), isFalse);
    expect(labels.containsKey('手写名字'), isFalse);
  });

  testWidgets('卡片：行标题与摘要显示名字，不显示 id', (tester) async {
    final foodId = await catalog.createMasterFood(
      name: '无糖茶',
      kcalPer100g: 4,
      proteinPer100g: 0.2,
      carbsPer100g: 0.8,
      fatPer100g: 0,
    );
    final supplyId = await canteen.createDish(
      windowId: windowId,
      name: '招牌红烧肉',
      foodId: foodId,
      servingGrams: 150,
    );
    final turn = turnOf({
      'action': 'meal.create',
      'args': {
        'slot': 'lunch',
        'items': [
          {'food': '[canteen-dish:$supplyId]', 'grams': 150.0},
          {'food': '[food:$foodId]', 'grams': 500.0},
        ],
        'localDate': '2026-11-10',
      },
    });
    final labels = await MealItemLabels.resolve(
      db,
      (turn.rows.single.command!.args['items'] as List).cast<Object?>(),
    );
    final labelled = ChatEditTurn(
      reply: turn.reply,
      rows: [turn.rows.single.copyWith(itemLabels: labels)],
    );

    tester.view.physicalSize = const Size(420, 1000);
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
                id: 'm1',
                role: ConversationRole.assistant,
                text: labelled.reply,
                createdAt: now,
                kind: ConversationMessageKind.editProposal,
                editTurn: labelled,
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

    expect(find.textContaining('招牌红烧肉'), findsWidgets);
    expect(find.textContaining('无糖茶'), findsWidgets);
    expect(
      find.textContaining('[canteen-dish:'),
      findsNothing,
      reason: '卡片上不能出现机器引用',
    );
    expect(find.textContaining('[food:'), findsNothing);
  });

  test('数字接地：拒绝文案说名字，不说 id', () async {
    final foodId = await catalog.createMasterFood(
      name: '无糖茶',
      kcalPer100g: 4,
      proteinPer100g: 0.2,
      carbsPer100g: 0.8,
      fatPer100g: 0,
    );
    final turn = turnOf({
      'action': 'meal.create',
      'args': {
        'slot': 'snack',
        'items': [
          {'food': '[food:$foodId]', 'grams': 100.0},
        ],
        'localDate': '2026-11-10',
      },
    });
    final labels = await MealItemLabels.resolve(
      db,
      (turn.rows.single.command!.args['items'] as List).cast<Object?>(),
    );
    final labelled = ChatEditTurn(
      reply: turn.reply,
      rows: [turn.rows.single.copyWith(itemLabels: labels)],
    );

    // 回复里只说了 500ml，没有 100 —— 必须拒绝，且点名"无糖茶"。
    final problem = validateManualCardGrounding(
      labelled,
      userText: '无糖',
      assistantReply: '这杯无糖茶约 500ml，热量约 20 kcal。',
    );
    expect(problem, isNotNull);
    expect(problem, contains('无糖茶'));
    expect(problem, isNot(contains('[food:')), reason: '报错里不能出现 id');
  });

  test('重启：从库里重读的消息也会把 id 解析成名字', () async {
    final foodId = await catalog.createMasterFood(
      name: '无糖茶',
      kcalPer100g: 4,
      proteinPer100g: 0.2,
      carbsPer100g: 0.8,
      fatPer100g: 0,
    );
    final turn = turnOf({
      'action': 'meal.create',
      'args': {
        'slot': 'snack',
        'items': [
          {'food': '[food:$foodId]', 'grams': 500.0},
        ],
        'localDate': '2026-11-10',
      },
    });
    final repository = DriftConversationMessageRepository(database: db);
    await repository.save(
      ConversationMessage(
        id: 'msg-labels',
        role: ConversationRole.assistant,
        text: turn.reply,
        createdAt: now,
        kind: ConversationMessageKind.editProposal,
        editTurn: turn,
      ),
    );

    final loaded = await repository.loadRecent();
    final restored = loaded.single.editTurn!;
    expect(
      restored.rows.single.itemLabels['[food:$foodId]'],
      '无糖茶',
      reason: '重启后卡片仍要说人话',
    );
  });
}

String _json(Map<String, Object?> value) {
  final buffer = StringBuffer('{');
  var first = true;
  for (final entry in value.entries) {
    if (!first) buffer.write(',');
    first = false;
    buffer
      ..write('"${entry.key}":')
      ..write(_encode(entry.value));
  }
  buffer.write('}');
  return buffer.toString();
}

String _encode(Object? value) {
  if (value == null) return 'null';
  if (value is num || value is bool) return value.toString();
  if (value is Map) return _json(value.map((k, v) => MapEntry('$k', v)));
  if (value is List) return '[${value.map(_encode).join(',')}]';
  return '"${value.toString().replaceAll('"', '\\"')}"';
}
