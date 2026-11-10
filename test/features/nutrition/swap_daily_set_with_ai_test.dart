import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart'
    as chat;
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/swap_daily_set_with_ai.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 「换一套」的候选池与预算口径（docs/67 §6.5）。
///
/// 收敛后的硬口径：
/// 1. 候选池 = **完整营养 + 可信份量**的供应；待分析/份量未知的项不进候选，
///    也不给"一份"数（不补 100g）；
/// 2. 清单与预算都按**一份**（每 100g × 每份克数 ÷ 100），不是每 100g；
/// 3. AI 输出经本地硬校验（编造 id / 跨餐重复 / 超预算 / 忌口一律丢弃）；
/// 4. 不写任何餐记录（本用例不依赖 `MealRepository`）。
void main() {
  late AppDatabase db;
  late FoodCatalogService catalog;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late String windowId;
  final now = DateTime.utc(2026, 10, 29, 8);

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
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '06:00',
      closeTime: '21:00',
    );
  });

  tearDown(() => db.close());

  /// 一条**可自动推荐**的供应：完整营养 + 可信份量。
  Future<void> seedSupply({
    required String id,
    required String name,
    required double kcalPer100g,
    double servingGrams = 200,
    double proteinPer100g = 10,
    double carbsPer100g = 20,
    double fatPer100g = 8,
    String? serviceId,
  }) async {
    final foodId = await catalog.createMasterFood(
      name: name,
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
    );
    await db
        .into(db.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: id,
            serviceId: serviceId ?? windowId,
            displayName: name,
            createdAt: now,
            updatedAt: now,
            foodId: drift.Value(foodId),
            servingGrams: drift.Value(servingGrams),
            servingGramsStatus: const drift.Value('known'),
            servingGramsSource: const drift.Value('user_input'),
          ),
        );
  }

  Future<void> seedUnanalysed({
    required String id,
    required String name,
  }) async {
    await db
        .into(db.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: id,
            serviceId: windowId,
            displayName: name,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  SwapDailySetWithAi build(
    _ScriptedService service, {
    Future<PlanningConstraints> Function()? loadConstraints,
    Future<List<MealRecord>> Function(String localDate)? loadMeals,
    Future<DailyNutritionSummary> Function(String localDate)? loadNutrition,
    DateTime? at,
  }) => SwapDailySetWithAi(
    service: service,
    canteenRepository: canteen,
    supplyCatalog: supplies,
    now: () => at ?? now,
    loadConstraints: loadConstraints,
    loadMeals: loadMeals,
    loadNutrition: loadNutrition,
  );

  test('详细结果：没有供应与没有主库营养可区分，且都不外呼', () async {
    final service = _ScriptedService('{}');
    final empty = await build(service).runDetailed();
    expect(empty.unavailableReason, MenuSetSwapUnavailableReason.noSupply);
    await seedUnanalysed(id: 'unlinked', name: '尚未链接');
    final unlinked = await build(service).runDetailed();
    expect(
      unlinked.unavailableReason,
      MenuSetSwapUnavailableReason.noNutrition,
    );
    expect(service.calls, 0);
  });

  for (final status in ['estimated', 'known']) {
    test('详细结果：$status + 未验证来源不放宽可信门槛，不外呼且解释份量', () async {
      await seedSupply(id: 'untrusted', name: '历史份量', kcalPer100g: 150);
      await (db.update(
        db.menuItems,
      )..where((t) => t.id.equals('untrusted'))).write(
        MenuItemsCompanion(
          servingGramsStatus: drift.Value(status),
          servingGramsSource: const drift.Value('legacy_unverified'),
        ),
      );
      final service = _ScriptedService('{"breakfast":["untrusted"]}');
      final result = await build(service).runDetailed();
      expect(
        result.unavailableReason,
        MenuSetSwapUnavailableReason.servingUnverified,
      );
      expect(result.unavailableReason!.message, contains('每份克数'));
      expect(service.calls, 0);
    });
  }

  test('详细结果：数据源未接线是配置缺失，不伪装网络故障', () async {
    final service = _ScriptedService('{}');
    final result = await SwapDailySetWithAi(
      service: service,
      canteenRepository: canteen,
      now: () => now,
    ).runDetailed();
    expect(
      result.unavailableReason,
      MenuSetSwapUnavailableReason.configurationMissing,
    );
    expect(service.calls, 0);
  });

  test('详细结果：有效池区分请求失败、输出不可用与成功，不写摄入', () async {
    await seedSupply(id: 'c1', name: '鸡蛋', kcalPer100g: 150);
    final failed = _ScriptedService('')..fail = true;
    expect(
      (await build(failed).runDetailed()).unavailableReason,
      MenuSetSwapUnavailableReason.requestFailed,
    );
    final unusable = _ScriptedService('{"breakfast":["ghost"]}');
    final rejected = await build(unusable).runDetailed();
    expect(
      rejected.unavailableReason,
      MenuSetSwapUnavailableReason.unusableOutput,
    );
    expect(rejected.filtered, 1);
    final valid = _ScriptedService('{"breakfast":["c1"]}');
    final accepted = await build(valid).runDetailed();
    expect(accepted.unavailableReason, isNull);
    expect(accepted.bySlot[MealSlot.breakfast]!.single.id, 'c1');
    expect(await db.select(db.meals).get(), isEmpty);
  });

  test('合法输出：候选来自供应，字段口径 = 每份（不是每 100g）', () async {
    await seedSupply(id: 'c1', name: '鸡蛋', kcalPer100g: 139, servingGrams: 50);
    await seedSupply(id: 'c2', name: '米饭', kcalPer100g: 116, servingGrams: 200);
    await seedSupply(id: 'c3', name: '青菜', kcalPer100g: 60, servingGrams: 150);
    await seedSupply(id: 'c4', name: '鸡腿', kcalPer100g: 200, servingGrams: 120);
    await seedUnanalysed(id: 'c9', name: '未分析菜');

    final service = _ScriptedService(
      '{"breakfast":["c1"],"lunch":["c2","c3"],"dinner":["c4"]}',
    );
    final result = await build(service).run();
    expect(result, isNotNull);
    expect(result!.filtered, 0);
    expect(result.bySlot[MealSlot.breakfast]!.single.name, '鸡蛋');
    expect(result.bySlot[MealSlot.lunch], hasLength(2));
    expect(result.bySlot[MealSlot.dinner]!.single.name, '鸡腿');

    final mapped = result.bySlot[MealSlot.breakfast]!.single;
    expect(mapped.source, 'canteen');
    expect(mapped.servingGrams, 50, reason: '该供应自己的每份克数');
    expect(mapped.basisAssumed, isFalse, reason: '份量可信，不是"按 100g 估算"');
    expect(
      mapped.kcal,
      closeTo(69.5, 1e-9),
      reason: '139 × 50 ÷ 100 = 69.5（一份），不是 139（每 100g）',
    );

    // 提示词里给的是"一份 kcal + 每份克数"。
    expect(service.lastSystemContext, contains('c1'));
    expect(service.lastSystemContext, contains('每份 50g'));
    expect(service.lastSystemContext, contains('70 kcal/份'));
    expect(service.lastSystemContext, contains('清单（营养均为每份）'));
    expect(service.lastSystemContext, isNot(contains('营养均为每100g')));
    expect(service.lastSystemContext, isNot(contains('c9')));
  });

  test('饮食约束写入提示词，并在候选池/输出两处本地过滤', () async {
    await seedSupply(id: 'c1', name: '花生酱拌面', kcalPer100g: 300);
    await seedSupply(id: 'c2', name: '鸡胸肉饭', kcalPer100g: 150);

    final service = _ScriptedService(
      '{"breakfast":["c1"],"lunch":["c2"],"dinner":["c2"]}',
    );
    final result = await build(
      service,
      loadConstraints: () async =>
          const PlanningConstraints(allergenAvoidances: ['花生']),
    ).run();
    expect(result, isNotNull);
    expect(service.lastSystemContext, contains('用户饮食硬约束'));
    expect(service.lastSystemContext, contains('花生'));
    expect(
      service.lastSystemContext,
      isNot(contains('花生酱拌面')),
      reason: '明显冲突的菜不该进 AI 候选清单',
    );
    final all = [for (final list in result!.bySlot.values) ...list];
    expect(all.map((dish) => dish.name), isNot(contains('花生酱拌面')));
    expect(result.bySlot[MealSlot.lunch]!.single.name, '鸡胸肉饭');
  });

  test('候选上限前先按饮食约束过滤：前 60 条禁用，第 61 条仍进入请求和结果', () async {
    for (var i = 0; i < 60; i++) {
      await seedSupply(
        id: 'blocked-${i.toString().padLeft(3, '0')}',
        name: '花生配菜$i',
        kcalPer100g: 150,
      );
    }
    await seedSupply(id: 'allowed-61', name: '清蒸鸡肉', kcalPer100g: 150);
    final stored = await supplies.listAll();
    expect(stored, hasLength(61));
    expect(stored.every((supply) => supply.isAutoRecommendable), isTrue);
    expect(stored.take(60).map((supply) => supply.id), [
      for (var i = 0; i < 60; i++) 'blocked-${i.toString().padLeft(3, '0')}',
    ], reason: '真实仓储返回的前 60 条必须确实全被约束排除');
    expect(stored.last.id, 'allowed-61');

    final service = _ScriptedService('{"breakfast":["allowed-61"]}');
    final result = await build(
      service,
      loadConstraints: () async =>
          const PlanningConstraints(allergenAvoidances: ['花生']),
    ).runDetailed();
    expect(
      result.unavailableReason,
      isNull,
      reason: '第 61 条符合所有硬约束，不能因前 60 条禁用误报 constraintsExcluded',
    );
    expect(result.bySlot[MealSlot.breakfast]!.single.id, 'allowed-61');
    expect(service.calls, 1);
    expect(service.lastSystemContext, contains('allowed-61\t清蒸鸡肉\t'));
    expect(service.lastSystemContext, isNot(contains('blocked-')));
    expect(await db.select(db.meals).get(), isEmpty);
  });

  for (final breakfastRecorded in [false, true]) {
    final inactive = breakfastRecorded ? '早餐已记录' : '早餐已过时段';
    test('候选上限前先按有效餐次过滤（$inactive）：第 61 条午餐供应仍可选', () async {
      final breakfastWindow = await canteen.createWindow(
        venueId: (await db.select(db.venues).get()).single.id,
        name: '早餐专窗',
        openTime: '06:00',
        closeTime: '09:00',
      );
      for (var i = 0; i < 60; i++) {
        await seedSupply(
          id: 'breakfast-${i.toString().padLeft(3, '0')}',
          name: '早餐供应$i',
          kcalPer100g: 150,
          serviceId: breakfastWindow,
        );
      }
      await seedSupply(id: 'active-61', name: '午餐供应', kcalPer100g: 150);
      final stored = await supplies.listAll();
      expect(stored, hasLength(61));
      expect(stored.every((supply) => supply.isAutoRecommendable), isTrue);
      expect(stored.take(60).map((supply) => supply.id), [
        for (var i = 0; i < 60; i++)
          'breakfast-${i.toString().padLeft(3, '0')}',
      ]);
      expect(stored.last.id, 'active-61');
      final service = _ScriptedService('{"lunch":["active-61"]}');
      final result = await build(
        service,
        at: DateTime.utc(2026, 10, 29, breakfastRecorded ? 8 : 12),
        loadMeals: (_) async => [
          if (breakfastRecorded)
            MealRecord(
              id: 'already-eaten-breakfast',
              localDate: '2026-10-29',
              slot: MealSlot.breakfast,
              eatenAt: now,
              source: 'manual',
              createdAt: now,
              updatedAt: now,
              items: [
                MealItemRecord(
                  id: 'already-eaten-item',
                  foodName: '已吃早餐',
                  grams: 100,
                  nutrition: const NutritionValues(
                    kcal: 300,
                    proteinGrams: 10,
                    carbsGrams: 30,
                    fatGrams: 10,
                  ),
                  createdAt: now,
                  updatedAt: now,
                ),
              ],
            ),
        ],
      ).runDetailed();
      expect(result.unavailableReason, isNull, reason: '无有效餐次的供应不能占满候选名额');
      expect(result.bySlot[MealSlot.lunch]!.single.id, 'active-61');
      expect(service.calls, 1);
      expect(service.lastSystemContext, contains('active-61\t午餐供应\t'));
      expect(service.lastSystemContext, isNot(contains('breakfast-000\t')));
      expect(await db.select(db.meals).get(), isEmpty);
    });
  }

  test('有效餐次没有覆盖供应：不请求 AI，说明供应时段而非谎报饮食约束', () async {
    await (db.update(
      db.menuServices,
    )..where((t) => t.id.equals(windowId))).write(
      const MenuServicesCompanion(
        openTime: drift.Value('06:00'),
        closeTime: drift.Value('09:00'),
      ),
    );
    await seedSupply(id: 'breakfast-only', name: '早餐限定', kcalPer100g: 150);
    final service = _ScriptedService('{"lunch":["breakfast-only"]}');
    final result = await build(
      service,
      at: DateTime.utc(2026, 10, 29, 12),
    ).runDetailed();
    expect(service.calls, 0, reason: '所有供应都不覆盖当前有效餐次，不能空池外呼');
    expect(result.bySlot, isEmpty);
    expect(result.unavailableReason?.message, contains('供应时段'));
    expect(
      result.unavailableReason,
      isNot(MenuSetSwapUnavailableReason.constraintsExcluded),
    );
  });

  test('编造 dishId + 跨餐重复：本地硬校验丢弃并计数（不许模型编菜）', () async {
    await seedSupply(id: 'c1', name: '鸡蛋', kcalPer100g: 150, servingGrams: 60);
    await seedSupply(id: 'c2', name: '米饭', kcalPer100g: 116, servingGrams: 200);
    await seedSupply(id: 'c3', name: '鸡腿', kcalPer100g: 200, servingGrams: 120);

    final service = _ScriptedService(
      '{"breakfast":["c1","ghost"],"lunch":["c1","c2"],"dinner":["c3"]}',
    );
    final result = await build(service).run();
    expect(result, isNotNull);
    expect(result!.filtered, 2, reason: 'ghost 不在清单 + c1 跨餐重复');
    final all = [for (final list in result.bySlot.values) ...list];
    expect(all.map((d) => d.id), isNot(contains('ghost')));
    expect(all.where((d) => d.id == 'c1'), hasLength(1), reason: '跨餐不重复');
  });

  test('输出不是 JSON / 解析不出餐次 ⇒ null（调用方回退本地重排）', () async {
    await seedSupply(id: 'c1', name: '鸡蛋', kcalPer100g: 150);
    final service = _ScriptedService('好的，我给你推荐一些菜吧。');
    expect(await build(service).run(), isNull);
  });

  test('请求失败：旧 run API 返回 null，不把传输异常泄漏给调用方', () async {
    await seedSupply(id: 'c1', name: '鸡蛋', kcalPer100g: 150);
    final service = _ScriptedService('')..fail = true;
    expect(await build(service).run(), isNull);
  });

  test('没有可信份量的供应 ⇒ 不进候选；池空则不请求 AI', () async {
    await seedUnanalysed(id: 'c9', name: '未分析菜');
    final service = _ScriptedService('{"breakfast":["c1"]}');
    expect(await build(service).run(), isNull);
    expect(service.calls, 0, reason: '候选池为空不该发请求');
  });

  test('份量未知的已分析供应同样不进自动推荐（不补 100g）', () async {
    final foodId = await catalog.createMasterFood(
      name: '份量未知菜',
      kcalPer100g: 200,
      proteinPer100g: 8,
      carbsPer100g: 20,
      fatPer100g: 9,
    );
    await db
        .into(db.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: 'c-unknown',
            serviceId: windowId,
            displayName: '份量未知菜',
            createdAt: now,
            updatedAt: now,
            foodId: drift.Value(foodId),
            servingGramsStatus: const drift.Value('unknown'),
            servingGramsSource: const drift.Value('legacy_unknown'),
          ),
        );
    final service = _ScriptedService('{"breakfast":["c-unknown"]}');
    expect(await build(service).run(), isNull);
    expect(service.calls, 0);
  });

  test('按目标减已摄入分配；已记录餐次与超预算菜被本地硬过滤', () async {
    await seedSupply(id: 'c1', name: '鸡蛋', kcalPer100g: 400, servingGrams: 50);
    await seedSupply(
      id: 'c2',
      name: '超大份盖饭',
      kcalPer100g: 250,
      servingGrams: 400,
    );
    await seedSupply(id: 'c3', name: '青菜', kcalPer100g: 100, servingGrams: 100);
    await seedSupply(id: 'c4', name: '鸡腿', kcalPer100g: 200, servingGrams: 100);

    final stamp = DateTime.utc(2026, 10, 31, 8);
    final recordedBreakfast = MealRecord(
      id: 'meal-breakfast',
      localDate: '2026-10-31',
      slot: MealSlot.breakfast,
      eatenAt: stamp,
      source: 'manual',
      createdAt: stamp,
      updatedAt: stamp,
      items: [
        MealItemRecord(
          id: 'item-breakfast',
          foodName: '早餐',
          grams: 100,
          nutrition: const NutritionValues(
            kcal: 500,
            proteinGrams: 20,
            carbsGrams: 60,
            fatGrams: 15,
          ),
          createdAt: stamp,
          updatedAt: stamp,
        ),
      ],
    );
    const target = DailyNutritionTarget(
      calorieMinKcal: 1800,
      calorieMaxKcal: 2000,
      proteinMinGrams: 120,
      proteinMaxGrams: 160,
      carbsMinGrams: 200,
      carbsMaxGrams: 260,
      fatMinGrams: 50,
      fatMaxGrams: 70,
    );
    final service = _ScriptedService(
      '{"breakfast":["c1"],"lunch":["c2","c3"],"dinner":["c4"]}',
    );

    final result = await build(
      service,
      at: DateTime.utc(2026, 10, 31, 8),
      loadMeals: (_) async => [recordedBreakfast],
      loadNutrition: (_) async => const DailyNutritionSummary(
        consumed: NutritionValues(
          kcal: 500,
          proteinGrams: 20,
          carbsGrams: 60,
          fatGrams: 15,
        ),
        target: target,
      ),
    ).run();

    expect(result, isNotNull);
    // 早餐已记录 ⇒ 模型即使再给也不算；1 条被过滤。
    expect(result!.bySlot.containsKey(MealSlot.breakfast), isFalse);
    expect(result.filtered, greaterThanOrEqualTo(1));
    expect(
      result.bySlot[MealSlot.lunch]!.map((d) => d.id),
      isNot(contains('c2')),
      reason: '一份 1000 kcal 超出午餐预算',
    );
    expect(result.bySlot[MealSlot.lunch]!.map((d) => d.id), contains('c3'));
  });

  test('AI 输出与供应时段不匹配：午餐窗口不能成为早餐', () async {
    await (db.update(
      db.menuServices,
    )..where((t) => t.id.equals(windowId))).write(
      const MenuServicesCompanion(
        openTime: drift.Value('11:00'),
        closeTime: drift.Value('14:00'),
      ),
    );
    await seedSupply(id: 'lunch-only', name: '午餐限定', kcalPer100g: 150);
    final service = _ScriptedService('{"breakfast":["lunch-only"]}');
    expect(await build(service).run(), isNull);
    expect(service.calls, 1, reason: '本地校验不能把时段正确性寄托在模型上');
  });

  test('所有推荐时段都已过：不请求 AI，也不把早餐塞回请求', () async {
    await seedSupply(id: 'c1', name: '鸡蛋', kcalPer100g: 150);
    final service = _ScriptedService('{"breakfast":["c1"]}');
    final result = await build(
      service,
      at: DateTime.utc(2026, 10, 29, 23),
    ).run();
    expect(result, isNull);
    expect(service.calls, 0);
  });

  test('三餐都已有记录：不请求 AI，也不产生新的推荐', () async {
    await seedSupply(id: 'c1', name: '鸡蛋', kcalPer100g: 150);
    final stamp = DateTime.utc(2026, 10, 29, 8);
    MealRecord meal(MealSlot slot) => MealRecord(
      id: 'meal-${slot.storedValue}',
      localDate: '2026-10-29',
      slot: slot,
      eatenAt: stamp,
      source: 'manual',
      createdAt: stamp,
      updatedAt: stamp,
      items: [
        MealItemRecord(
          id: 'item-${slot.storedValue}',
          foodName: '已吃',
          grams: 100,
          nutrition: const NutritionValues(
            kcal: 300,
            proteinGrams: 10,
            carbsGrams: 30,
            fatGrams: 10,
          ),
          createdAt: stamp,
          updatedAt: stamp,
        ),
      ],
    );
    final service = _ScriptedService('{"breakfast":["c1"]}');
    final result = await build(
      service,
      loadMeals: (_) async => [
        meal(MealSlot.breakfast),
        meal(MealSlot.lunch),
        meal(MealSlot.dinner),
      ],
    ).run();
    expect(result, isNull);
    expect(service.calls, 0);
  });
}

/// 脚本化 AI：只回一段固定文本，并记录最后一次 systemContext。
final class _ScriptedService implements AiConversationService {
  _ScriptedService(this.output);

  final String output;
  bool fail = false;
  int calls = 0;
  String lastSystemContext = '';

  @override
  Stream<String> sendMessage({
    required List<chat.ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    calls++;
    if (fail) throw StateError('test transport failure');
    lastSystemContext = systemContext ?? '';
    onProgress(output);
    yield output;
  }
}
