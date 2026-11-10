import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/data/database/legacy_nutrition_converter.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';

/// **启动时归一补跑**：用真实 Drift 夹具覆盖证据与台账的先后顺序。
///
/// 用户截图显示目录有 8 道菜、已分析 7 道而推荐为空；没有取得手机数据库，
/// 下列「完整证据、无 food_id」是可复现夹具，不是对用户真实行内容的断言。
///
/// converter 必须可重入：既覆盖首次见到完整证据的供应，也覆盖先登记为
/// 待补全、后来补齐证据的供应。本次 run 即应补链接且报告与台账一致；
/// 保留已确认份量，不因补跑覆盖已采纳的营养或制造第二条主食物。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 10, 12);

  Future<LegacyNutritionConverter> converter(AppDatabase db) async {
    return LegacyNutritionConverter(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
  }

  test('升级后新出现的"有证据无链接"供应 → 再跑一次归一即补链接', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final supplies = SupplyCatalogRepository(database: db);

    // 模拟旧库升级完成后的状态：归一已跑（无旧数据），然后**在旧版本行为
    // 下**新增一条供应并写证据（不建主食物、不链接）。
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '校');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '快餐',
      openTime: '08:00',
      closeTime: '20:00',
    );
    final dishId = await canteen.createDish(windowId: windowId, name: '鸡蛋汉堡');
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 190,
      proteinPer100g: 21.5,
      carbsPer100g: 0.7,
      fatPer100g: 11.3,
      grade: 'B',
      confidence: 0.8,
    );

    final before = (await supplies.getById(dishId))!;
    expect(before.foodId, isNull, reason: '未接线_sink 的写入不链接（旧行为）');
    expect(before.kcalPer100g, isNull, reason: '主库视角=待分析');

    // 补跑归一（启动时行为）。
    final report = await (await converter(db)).run();
    expect(report.suppliesTotal, 1);
    expect(report.isClean, isTrue, reason: report.toString());

    final after = (await supplies.getById(dishId))!;
    expect(after.foodId, isNotNull, reason: '补跑必须给有完整证据的供应建主食物并链接');
    expect(after.kcalPer100g, 190);
    expect(after.isAnalyzable, isTrue, reason: '推荐/记餐从此可用');
    final food = await (db.select(
      db.foods,
    )..where((t) => t.id.equals(after.foodId!))).getSingle();
    expect(food.kcalPer100g, 190);
  });

  test('补跑幂等：同一供应不会被造第二条主食物', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '校');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '快餐',
      openTime: '08:00',
      closeTime: '20:00',
    );
    final dishId = await canteen.createDish(windowId: windowId, name: '鸡蛋');
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 135,
      proteinPer100g: 12.7,
      carbsPer100g: 1.6,
      fatPer100g: 8.9,
      grade: 'B',
      confidence: 0.8,
    );

    final conv = await converter(db);
    await conv.run();
    await conv.run();
    await conv.run();

    final foods = await db.select(db.foods).get();
    expect(foods, hasLength(1), reason: '三次补跑不能造三条主食物');
    final supplies = SupplyCatalogRepository(database: db);
    final supply = (await supplies.getById(dishId))!;
    expect(supply.foodId, foods.single.id);
  });

  test('先登记待补全再补齐证据：本次补跑立即链接，报告与台账一致', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '校');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '快餐',
      openTime: '08:00',
      closeTime: '20:00',
    );
    final dishId = await canteen.createDish(windowId: windowId, name: '鸡蛋汉堡');
    final conv = await converter(db);
    final first = await conv.run();
    expect(first.needsCompletion, 1);
    final pending = await db.select(db.legacyEntityMappings).getSingle();
    expect(pending.outcome, 'needs_completion');
    expect(pending.foodId, isNull);

    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 190,
      proteinPer100g: 21.5,
      carbsPer100g: 0.7,
      fatPer100g: 11.3,
      grade: 'B',
      confidence: 0.8,
    );
    final second = await conv.run();
    final completed = await db.select(db.legacyEntityMappings).getSingle();
    final supply = (await SupplyCatalogRepository(database: db)
        .getById(dishId))!;
    expect(supply.foodId, isNotNull, reason: '补全后不应要求再重启一次才链接');
    expect(completed.id, pending.id, reason: '补全同一台账，不能另建迁移键');
    expect(completed.foodId, supply.foodId);
    expect(completed.outcome, 'converted');
    expect(second.suppliesOutcomes, {'converted': 1});
    expect(second.conflicts, isEmpty);
    expect(second.isClean, isTrue);
    expect(supply.kcalPer100g, 190);
    await conv.run();
    expect(await db.select(db.foods).get(), hasLength(1));
    expect(await db.select(db.foodNutritionRevisions).get(), hasLength(1));
  });

  test('已明确填写的份量补主链接后仍可信，不降级成历史估计', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '校');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '快餐',
      openTime: '08:00',
      closeTime: '20:00',
    );
    final dishId = await canteen.createDish(
      windowId: windowId,
      name: '蒸蛋',
      servingGrams: 180,
    );
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 135,
      proteinPer100g: 12.7,
      carbsPer100g: 1.6,
      fatPer100g: 8.9,
      grade: 'B',
      confidence: 0.8,
    );
    await (await converter(db)).run();
    final supply = (await SupplyCatalogRepository(database: db)
        .getById(dishId))!;
    expect(supply.servingGramsStatus.storedValue, 'known');
    expect(supply.servingGramsSource.storedValue, 'user_input');
    expect(supply.servingGrams, 180);
    expect(supply.isAutoRecommendable, isTrue, reason: '归一不能抹去用户明确确认过的份量来源');
  });

  test('旧版误报的无主链接 source_changed 冲突可被完整证据安全补全', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '校');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '快餐',
      openTime: '08:00',
      closeTime: '20:00',
    );
    final dishId = await canteen.createDish(windowId: windowId, name: '蒸蛋');
    final conv = await converter(db);
    await conv.run();
    await db
        .update(db.legacyEntityMappings)
        .write(
          const LegacyEntityMappingsCompanion(
            outcome: Value('conflict'),
            reasonCode: Value('source_changed'),
          ),
        );
    await canteen.recordNutrition(
      dishId: dishId,
      kcalPer100g: 135,
      proteinPer100g: 12.7,
      carbsPer100g: 1.6,
      fatPer100g: 8.9,
      grade: 'B',
      confidence: 0.8,
    );
    final report = await conv.run();
    expect(
      (await SupplyCatalogRepository(database: db).getById(dishId))!.foodId,
      isNotNull,
    );
    expect(
      (await db.select(db.legacyEntityMappings).getSingle()).outcome,
      'converted',
    );
    expect(report.isClean, isTrue);
  });

  test('证据只有区间（无代表值）的供应：补跑不硬造，保持待分析', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final canteen = CanteenRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    );
    final supplies = SupplyCatalogRepository(database: db);
    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '校');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '快餐',
      openTime: '08:00',
      closeTime: '20:00',
    );
    final dishId = await canteen.createDish(windowId: windowId, name: '区间菜');
    // 手写一条只有区间的证据（模拟历史行）。
    await db
        .into(db.menuItemNutritionEvidence)
        .insert(
          MenuItemNutritionEvidenceCompanion.insert(
            id: 'ev-range',
            menuItemId: dishId,
            grade: 'C',
            origin: 'ai_estimate',
            createdAt: now,
            updatedAt: now,
            kcalMin: const Value(500),
            kcalMax: const Value(700),
          ),
        );

    final report = await (await converter(db)).run();
    final mapping = await (db.select(
      db.legacyEntityMappings,
    )..where((t) => t.legacyId.equals(dishId))).getSingle();
    expect(mapping.outcome, 'needs_completion');
    expect(mapping.reasonCode, 'range_only');
    expect(await db.select(db.foods).get(), isEmpty, reason: '不取中点造主食物');
    final supply = (await supplies.getById(dishId))!;
    expect(supply.foodId, isNull);
    expect(supply.state, SupplyNutritionState.needsAnalysis);
    expect(report.isClean, isTrue, reason: '待补全不算冲突');
  });
}
