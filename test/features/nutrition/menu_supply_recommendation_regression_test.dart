import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart'
    as chat;
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/swap_daily_set_with_ai.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';

// 真 Drift → SupplyCatalogRepository → MenuDishList，不能只验证映射函数。
void main() {
  late AppDatabase db;
  late FoodCatalogService catalog;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late DishLibraryRepository dishes;
  late String windowId;
  final now = DateTime(2026, 11, 10, 8);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    const ids = UuidV7Generator();
    final clock = FixedAppClock(now.toUtc());
    catalog = FoodCatalogService(database: db, idGenerator: ids, clock: clock);
    canteen = CanteenRepository(database: db, idGenerator: ids, clock: clock);
    supplies = SupplyCatalogRepository(database: db);
    dishes = DishLibraryRepository(
      database: db,
      idGenerator: ids,
      clock: clock,
    );
    final venue = await canteen.createVenue(name: '东区食堂', campusName: '校');
    windowId = await canteen.createWindow(
      venueId: venue,
      name: '快餐',
      openTime: '06:00',
      closeTime: '21:00',
    );
  });
  tearDown(() => db.close());

  Future<String> seed({
    required String id,
    required String name,
    bool linked = true,
    double? grams = 200,
    String status = 'known',
    String source = 'user_input',
  }) async {
    final foodId = linked
        ? await catalog.createMasterFood(
            name: name,
            kcalPer100g: 150,
            proteinPer100g: 10,
            carbsPer100g: 20,
            fatPer100g: 5,
          )
        : null;
    await db
        .into(db.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: id,
            serviceId: windowId,
            displayName: name,
            foodId: drift.Value(foodId),
            servingGrams: drift.Value(grams),
            servingGramsStatus: drift.Value(status),
            servingGramsSource: drift.Value(source),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return foodId ?? '';
  }

  SwapDailySetWithAi useCase(_Service service) => SwapDailySetWithAi(
    service: service,
    canteenRepository: canteen,
    supplyCatalog: supplies,
    now: () => now,
  );

  Future<void> pumpMenu(
    WidgetTester tester, {
    Future<MenuSetSwapResult?> Function()? swap,
    VoidCallback? openCanteen,
  }) async {
    tester.view.physicalSize = const Size(480, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MenuDishList(
            repository: dishes,
            supplyCatalog: supplies,
            now: now,
            onSwapSetWithAi: swap,
            onOpenCanteen: openCanteen ?? () {},
            onAddToMeal: (dish, {slotOverride}) async {},
            searchDebounce: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> repick(WidgetTester tester) async {
    final normal = find.byKey(const Key('nutrition-menu-daily-set-repick'));
    await tester.tap(
      normal.evaluate().isNotEmpty
          ? normal
          : find.byKey(const Key('menu-empty-action')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('8 道供应 7 条完整证据但未链接：真实页面保留全部待补状态而非报库空', (tester) async {
    for (var i = 0; i < 8; i++) {
      await seed(
        id: 'legacy-$i',
        name: '旧菜单$i',
        linked: false,
        grams: null,
        status: 'unknown',
        source: 'legacy_unknown',
      );
      if (i < 7) {
        await db
            .into(db.menuItemNutritionEvidence)
            .insert(
              MenuItemNutritionEvidenceCompanion.insert(
                id: 'evidence-$i',
                menuItemId: 'legacy-$i',
                grade: 'B',
                origin: 'ai_estimate',
                createdAt: now,
                updatedAt: now,
                kcalPer100g: const drift.Value(150),
                proteinPer100g: const drift.Value(10),
                carbsPer100g: const drift.Value(20),
                fatPer100g: const drift.Value(5),
              ),
            );
      }
    }
    expect(await db.select(db.menuItemNutritionEvidence).get(), hasLength(7));
    expect((await supplies.listAll()).every((s) => s.foodId == null), isTrue);
    var opened = 0;
    await pumpMenu(tester, openCanteen: () => opened++);
    expect(find.text('菜品库还是空的。'), findsNothing);
    for (var i = 0; i < 8; i++) {
      expect(
        find.byKey(Key('nutrition-menu-supply-legacy-$i')),
        findsOneWidget,
      );
    }
    expect(find.textContaining('0 kcal'), findsNothing);
    expect(find.byKey(const Key('cta-add-meal-0')), findsNothing);
    await tester.tap(find.byKey(const Key('nutrition-menu-complete-supplies')));
    expect(opened, 1, reason: '待补状态必须给真实可用的维护入口');
    expect(await db.select(db.meals).get(), isEmpty);
  });

  testWidgets('unknown 只显示每100g，pending 无伪造热量或克数，估计份量明确标约', (tester) async {
    await seed(
      id: 'unknown',
      name: '份量未知菜',
      grams: null,
      status: 'unknown',
      source: 'legacy_unknown',
    );
    await seed(
      id: 'pending',
      name: '待分析菜',
      linked: false,
      grams: null,
      status: 'unknown',
      source: 'legacy_unknown',
    );
    await seed(
      id: 'estimated',
      name: '估计份量菜',
      status: 'estimated',
      source: 'legacy_unverified',
    );
    await pumpMenu(tester);
    final unknown = find.byKey(const Key('nutrition-menu-supply-unknown'));
    expect(unknown, findsOneWidget);
    expect(
      find.descendant(of: unknown, matching: find.textContaining('份量未知')),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: unknown,
        matching: find.textContaining('150 kcal/100g'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: unknown, matching: find.textContaining('kcal/份')),
      findsNothing,
    );
    final pending = find.byKey(const Key('nutrition-menu-supply-pending'));
    expect(
      find.descendant(of: pending, matching: find.textContaining('kcal')),
      findsNothing,
    );
    expect(
      find.descendant(of: pending, matching: find.textContaining('100 g')),
      findsNothing,
    );
    expect(find.textContaining('约 200 g/份'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('主链接与份量实时更新：待分析→未知→可信候选→营养修订→删除，无需重进页面', (tester) async {
    await seed(
      id: 'live',
      name: '实时供应',
      linked: false,
      grams: null,
      status: 'unknown',
      source: 'legacy_unknown',
    );
    await pumpMenu(tester);
    expect(find.byKey(const Key('nutrition-menu-supply-live')), findsOneWidget);
    final food = await catalog.createMasterFood(
      name: '实时主食物',
      kcalPer100g: 150,
      proteinPer100g: 10,
      carbsPer100g: 20,
      fatPer100g: 5,
    );
    await (db.update(db.menuItems)..where((t) => t.id.equals('live'))).write(
      MenuItemsCompanion(foodId: drift.Value(food)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('150 kcal/100g'), findsOneWidget);
    expect(find.byKey(const Key('cta-add-meal-0')), findsNothing);
    await catalog.updateSupplyWindowInfo(supplyId: 'live', servingGrams: 200);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cta-add-meal-0')), findsOneWidget);
    expect(find.textContaining('300 kcal'), findsWidgets);
    await catalog.reviseMasterFood(
      foodId: food,
      kcalPer100g: 180,
      proteinPer100g: 10,
      carbsPer100g: 20,
      fatPer100g: 5,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('360 kcal'), findsWidgets);
    await (db.delete(db.menuItems)..where((t) => t.id.equals('live'))).go();
    await tester.pumpAndSettle();
    expect(find.text('菜品库还是空的。'), findsOneWidget);
  });

  for (final change in ['清空份量', '删除供应']) {
    testWidgets('在途目录变化（$change）：旧 AI 结果不得回填，提示重试', (tester) async {
      await seed(id: 'in-flight', name: '在途旧供应');
      final responseGate = Completer<void>();
      addTearDown(() {
        if (!responseGate.isCompleted) responseGate.complete();
      });
      final service = _Service(
        '{"breakfast":["in-flight"]}',
        responseGate: responseGate.future,
      );
      MenuSetSwapResult? returned;
      await pumpMenu(
        tester,
        swap: () async {
          returned = await useCase(service).runDetailed();
          return returned;
        },
      );
      final breakfast = find.byKey(const Key('nutrition-menu-dish-card-0'));
      expect(breakfast, findsOneWidget);
      await tester.tap(
        find.byKey(const Key('nutrition-menu-daily-set-repick')),
      );
      // 请求在真实 runDetailed 内等外部响应，不用 pumpAndSettle 等加载动画。
      for (var i = 0; i < 100 && !service.requested.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(service.requested.isCompleted, isTrue);
      expect(returned, isNull, reason: '必须先证明请求确实还在途');

      final Finder updated;
      if (change == '清空份量') {
        await catalog.updateSupplyWindowInfo(
          supplyId: 'in-flight',
          clearServingGrams: true,
        );
        updated = find.textContaining('份量未知');
      } else {
        await (db.delete(
          db.menuItems,
        )..where((t) => t.id.equals('in-flight'))).go();
        updated = find.text('菜品库还是空的。');
      }
      for (var i = 0; i < 100 && updated.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(updated, findsOneWidget, reason: '真实供应流已把变更交给页面');
      expect(breakfast, findsNothing);

      responseGate.complete();
      await tester.pumpAndSettle();
      expect(returned, isNotNull);
      expect(returned!.unavailableReason, isNull);
      expect(
        returned!.bySlot.values.expand((picks) => picks).map((dish) => dish.id),
        ['in-flight'],
        reason: '真实用例返回的是请求前的旧供应，不能靠没有结果而假绿',
      );
      expect(breakfast, findsNothing, reason: '目录变更后的旧 AI 快照不能重新上屏');
      expect(find.textContaining('目录已更新'), findsOneWidget);
      expect(find.textContaining('重试'), findsWidgets);
      expect(await db.select(db.meals).get(), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('严格池空且本地无候选：失败提示补资料，不能声称已重排', (tester) async {
    await seed(
      id: 'unknown',
      name: '份量未知菜',
      grams: null,
      status: 'unknown',
      source: 'legacy_unknown',
    );
    final service = _Service('{"breakfast":["unknown"]}');
    await pumpMenu(tester, swap: () => useCase(service).runDetailed());
    await repick(tester);
    expect(find.textContaining('重排一整套'), findsNothing);
    expect(find.textContaining('每份克数'), findsWidgets);
    expect(service.calls, 0);
    expect(await db.select(db.meals).get(), isEmpty);
  });

  testWidgets('AI 把唯一供应安排到晚餐：本地晚餐候选为空也应显示成功结果且不跨餐重复', (tester) async {
    await seed(id: 'only', name: '晚餐选择');
    final service = _Service('{"dinner":["only"]}');
    await pumpMenu(tester, swap: () => useCase(service).runDetailed());
    await repick(tester);
    final dinner = find.byKey(const Key('nutrition-menu-dish-card-2'));
    expect(dinner, findsOneWidget);
    expect(
      find.descendant(of: dinner, matching: find.text('晚餐选择')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('nutrition-menu-dish-card-0')),
      findsNothing,
      reason: '未返回的餐次不能再用同一道菜补位',
    );
    expect(await db.select(db.meals).get(), isEmpty);
  });

  testWidgets('配置缺失且没有可计算候选：原地展示确切原因，不谎报本地重排', (tester) async {
    await seed(
      id: 'pending-config',
      name: '待补供应',
      linked: false,
      grams: null,
      status: 'unknown',
      source: 'legacy_unknown',
    );
    final service = _Service('{}');
    await pumpMenu(
      tester,
      swap: () => SwapDailySetWithAi(
        service: service,
        canteenRepository: canteen,
        now: () => now,
      ).runDetailed(),
    );
    await repick(tester);
    expect(find.textContaining('AI 配置缺失'), findsOneWidget);
    expect(find.textContaining('重排一整套'), findsNothing);
    expect(service.calls, 0);
  });

  testWidgets('有效池先成功后请求失败：回退必须移除旧 AI picks，不冒充 AI 成功', (tester) async {
    await seed(id: 'a', name: '本地首选');
    await seed(id: 'b', name: '第二道菜');
    await seed(id: 'c', name: 'AI 指定菜');
    final service = _Service('{"breakfast":["c"]}');
    await pumpMenu(tester, swap: () => useCase(service).run());
    await repick(tester);
    final breakfast = find.byKey(const Key('nutrition-menu-dish-card-0'));
    expect(
      find.descendant(of: breakfast, matching: find.text('AI 指定菜')),
      findsOneWidget,
    );
    service.fail = true;
    await repick(tester);
    expect(
      find.descendant(of: breakfast, matching: find.text('AI 指定菜')),
      findsNothing,
      reason: '失败后声称本地重排时，不能继续展示上次 AI 选中的菜',
    );
    expect(find.textContaining('AI 换一套没成功'), findsOneWidget);
    expect(await db.select(db.meals).get(), isEmpty, reason: '推荐换套不写摄入');
    expect(tester.takeException(), isNull);
  });
}

final class _Service implements AiConversationService {
  _Service(this.output, {this.responseGate});
  String output;
  final Future<void>? responseGate;
  final requested = Completer<void>();
  bool fail = false;
  int calls = 0;
  @override
  Stream<String> sendMessage({
    required List<chat.ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    calls++;
    if (!requested.isCompleted) requested.complete();
    if (fail) throw StateError('test transport failure');
    final gate = responseGate;
    if (gate != null) await gate;
    onProgress(output);
    yield output;
  }
}
