import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/master_nutrition_sink_adapter.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

/// AI 快照里的**供应身份与单位**（docs/67 §6.3）。
///
/// 收敛前后最大的区别：食堂供应现在是一等可记录实体（`[canteen-dish:]`），
/// 但它必须同时说清「哪个窗口 / 每 100g / 每份多少克·来源可信度」——
/// 不能让模型把每 100g 当"一份"，也不能给出没有依据的"一份多少千卡"。
void main() {
  late AppDatabase db;
  late FoodCatalogService catalog;
  late DishLibraryRepository dishes;
  late CanteenRepository canteen;
  late SupplyCatalogRepository supplies;
  late String windowId;
  late String linkedDishId;
  late String unknownServingDishId;
  late String unanalyzedDishId;

  final now = DateTime.utc(2026, 11, 9, 6);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    catalog = FoodCatalogService(
      database: db,
      idGenerator: _SeqIds('food'),
      clock: FixedAppClock(now),
    );
    dishes = DishLibraryRepository(
      database: db,
      idGenerator: _SeqIds('dish'),
      clock: FixedAppClock(now),
    );
    canteen = CanteenRepository(
      database: db,
      idGenerator: _SeqIds('canteen'),
      clock: FixedAppClock(now),
      masterNutritionSink: CatalogMasterNutritionSink(catalog),
    );
    supplies = SupplyCatalogRepository(database: db);

    final venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
    windowId = await canteen.createWindow(
      venueId: venueId,
      name: '一楼快餐',
      openTime: '11:00',
      closeTime: '13:30',
    );

    final foodId = await catalog.createMasterFood(
      name: '番茄炒蛋',
      kcalPer100g: 142,
      proteinPer100g: 8.4,
      carbsPer100g: 6.2,
      fatPer100g: 9.1,
    );
    linkedDishId = await canteen.createDish(
      windowId: windowId,
      name: '番茄炒蛋',
      foodId: foodId,
      servingGrams: 200,
      servingGramsStatus: ServingGramsStatus.known,
      servingGramsSource: ServingGramsSource.userInput,
    );
    unknownServingDishId = await canteen.createDish(
      windowId: windowId,
      name: '番茄炒蛋(大份)',
      foodId: foodId,
    );
    unanalyzedDishId = await canteen.createDish(
      windowId: windowId,
      name: '清炒时蔬',
    );
  });

  tearDown(() async => db.close());

  DriftChatEditContextLoader loader() => DriftChatEditContextLoader(
    database: db,
    clock: FixedAppClock(now),
    mealRepository: MealRepository(
      database: db,
      idGenerator: _SeqIds('meal'),
      clock: FixedAppClock(now),
    ),
    dishLibraryRepository: dishes,
    waterRepository: WaterRepository(
      database: db,
      idGenerator: _SeqIds('water'),
      clock: FixedAppClock(now),
    ),
    canteenRepository: canteen,
    supplyCatalog: supplies,
    workoutPlanRepository: WorkoutPlanRepository(
      database: db,
      idGenerator: _SeqIds('wplan'),
      clock: FixedAppClock(now),
    ),
    workoutSessionRepository: WorkoutSessionRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: _SeqIds('session'),
    ),
    dishSearch: const DishSearchService(),
  );

  test('食堂目录段：已链接供应给每 100g + 每份克数 + 一份热量', () async {
    final snapshot = await loader().build(userMessage: '帮我看看食堂目录');
    final section = snapshot.split('【食堂目录】').last;

    expect(
      section,
      contains('[canteen-dish:$linkedDishId] 番茄炒蛋'),
      reason: '已链接的供应是**可记录实体**，必须给出 id',
    );
    expect(section, contains('主食物:番茄炒蛋'));
    expect(section, contains('142 kcal/100g'));
    expect(section, contains('每份 200g（已知，可记"份"）'));
    expect(section, contains('一份约 284 kcal'));
  });

  test('份量未知的供应：只给每 100g，不给"一份多少千卡"', () async {
    final snapshot = await loader().build(userMessage: '帮我看看食堂目录');
    final section = snapshot.split('【食堂目录】').last;
    final line = section
        .split('\n')
        .firstWhere(
          (row) => row.contains('[canteen-dish:$unknownServingDishId]'),
        );
    expect(line, contains('142 kcal/100g'));
    expect(line, contains('每份克数未知'));
    expect(line, isNot(contains('一份约')));
  });

  test('未分析的供应：明确写不能直接记餐', () async {
    final snapshot = await loader().build(userMessage: '帮我看看食堂目录');
    final section = snapshot.split('【食堂目录】').last;
    expect(section, contains('[canteen-dish:$unanalyzedDishId] 清炒时蔬'));
    expect(section, contains('未分析营养，不能直接记餐'));
  });

  test('候选段：供应候选带窗口与份量，与菜品库条目可区分', () async {
    final snapshot = await loader().build(userMessage: '今天午餐吃什么');
    final section = snapshot.split('【候选菜品（本地检索）】').last;
    expect(section, contains('【食堂供应（按窗口，可记"份"或"克"）】'));
    expect(section, contains('[canteen-dish:$linkedDishId] 番茄炒蛋'));
    expect(section, contains('一楼快餐'), reason: '供应必须带窗口，不能当成无窗口的重复行');
    expect(
      section,
      isNot(contains('[canteen-dish:$unanalyzedDishId]')),
      reason: '未分析的供应不进候选',
    );
  });
}

final class _SeqIds implements IdGenerator {
  _SeqIds(this.prefix);
  final String prefix;
  int value = 0;

  @override
  String next() => '$prefix-${value++}';
}
