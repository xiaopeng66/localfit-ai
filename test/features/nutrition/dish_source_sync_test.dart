import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/dish_source_sync.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';

/// 「同步食堂营养」的判据（docs/40 §6，2026-10-19 补）。
///
/// 纪律：**只由用户点「同步」触发**；`userEdited` 的行拒绝覆盖（页面只提示）；
/// 来源删除/没营养值时不写；已是最新时不写。所有分支都要有测试。
void main() {
  late AppDatabase db;
  late DishLibraryRepository dishes;
  late CanteenRepository canteen;

  final now = DateTime.utc(2026, 10, 19, 4);
  final yesterday = now.subtract(const Duration(days: 1));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dishes = DishLibraryRepository(
      database: db,
      idGenerator: const _SeqIds(),
      clock: FixedAppClock(now),
    );
    canteen = CanteenRepository(
      database: db,
      idGenerator: const _SeqIds(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => db.close());

  DishSourceSync sync() => DishSourceSync(database: db, dishes: dishes);

  /// 建一条「食堂来源」的菜品库行；返回 (libraryId, menuItemId)。
  Future<(String, String)> seed({bool userEdited = false}) async {
    final venueId = await canteen.createVenue(name: '一食堂', campusName: '主校区');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '3 号窗口',
      openTime: '10:30',
      closeTime: '13:30',
    );
    final menuItemId = await canteen.createDish(
      windowId: windowId,
      name: '番茄牛腩饭',
    );
    await canteen.recordNutrition(
      dishId: menuItemId,
      kcalPer100g: 150,
      proteinPer100g: 7,
      carbsPer100g: 20,
      fatPer100g: 5,
      grade: 'D',
      confidence: 0.6,
    );
    final stored = await dishes.create(
      DishDraft(
        name: '番茄牛腩饭',
        mealSlot: '午餐',
        kcal: 150,
        proteinG: 7,
        carbsG: 20,
        fatG: 5,
        source: 'ai_estimate',
        servingGrams: 250,
        sourceType: 'canteen',
        sourceId: menuItemId,
        // 比来源旧 ⇒ 陈旧。
        sourceUpdatedAt: yesterday,
        userEdited: userEdited,
      ),
    );
    return (stored.id, menuItemId);
  }

  test('来源更新后可同步：按 servingGrams 缩放，并记下来源的 updatedAt', () async {
    final (libraryId, menuItemId) = await seed();
    // 食堂重新分析：per100g 150 → 200。
    await canteen.recordNutrition(
      dishId: menuItemId,
      kcalPer100g: 200,
      proteinPer100g: 10,
      carbsPer100g: 22,
      fatPer100g: 8,
      grade: 'C',
      confidence: 0.8,
    );

    final result = await sync().apply((await dishes.watchAll().first).single);

    expect(result.outcome, DishSyncOutcome.applied);
    final stored = (await dishes.watchAll().first).single;
    expect(stored.id, libraryId);
    expect(stored.kcal, closeTo(500, 0.001), reason: '200 × 250/100');
    expect(stored.proteinG, closeTo(25, 0.001));
    expect(stored.carbsG, closeTo(55, 0.001));
    expect(stored.fatG, closeTo(20, 0.001));
    expect(stored.servingGrams, 250, reason: '份量是用户模板，同步不动它');
    expect(stored.kcalPer100g, closeTo(200, 0.001));
    // 同步后不再陈旧。
    final menu = await (db.select(
      db.menuItems,
    )..where((row) => row.id.equals(menuItemId))).getSingle();
    expect(stored.sourceUpdatedAt, menu.updatedAt);
  });

  test('userEdited 的行拒绝覆盖（只提示，不动）', () async {
    await seed(userEdited: true);
    final before = (await dishes.watchAll().first).single;

    final result = await sync().apply(before);

    expect(result.outcome, DishSyncOutcome.userEdited);
    final after = (await dishes.watchAll().first).single;
    expect(after.kcal, before.kcal);
    expect(after.sourceUpdatedAt, before.sourceUpdatedAt);
  });

  test('userEdited 的行只有在明确 force 时才覆盖', () async {
    final (_, menuItemId) = await seed(userEdited: true);
    await canteen.recordNutrition(
      dishId: menuItemId,
      kcalPer100g: 200,
      proteinPer100g: 10,
      carbsPer100g: 22,
      fatPer100g: 8,
      grade: 'C',
      confidence: 0.8,
    );

    final result = await sync().apply(
      (await dishes.watchAll().first).single,
      force: true,
    );

    expect(result.outcome, DishSyncOutcome.applied);
    expect((await dishes.watchAll().first).single.kcal, closeTo(500, 0.001));
  });

  test('来源已是最新（时间相等）⇒ 不写', () async {
    final (_, menuItemId) = await seed();
    final menu = await (db.select(
      db.menuItems,
    )..where((row) => row.id.equals(menuItemId))).getSingle();
    // 把菜品库的 sourceUpdatedAt 对齐到来源：不存在陈旧。
    await dishes.updateSourceUpdatedAt(
      id: (await dishes.watchAll().first).single.id,
      sourceUpdatedAt: menu.updatedAt,
    );

    final result = await sync().apply((await dishes.watchAll().first).single);

    expect(result.outcome, DishSyncOutcome.upToDate);
  });

  test('来源已删除 ⇒ 不写、给出 sourceMissing', () async {
    final (_, menuItemId) = await seed();
    await (db.delete(
      db.menuItems,
    )..where((row) => row.id.equals(menuItemId))).go();

    final result = await sync().apply((await dishes.watchAll().first).single);

    expect(result.outcome, DishSyncOutcome.sourceMissing);
  });

  test('来源还没有营养值 ⇒ 不写（noNutrition）', () async {
    final venueId = await canteen.createVenue(name: '二食堂', campusName: '主校区');
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: '1 号窗口',
      openTime: '10:30',
      closeTime: '13:30',
    );
    final menuItemId = await canteen.createDish(
      windowId: windowId,
      name: '凉拌黄瓜',
    );
    await dishes.create(
      DishDraft(
        name: '凉拌黄瓜',
        mealSlot: '午餐',
        kcal: 40,
        proteinG: 1,
        carbsG: 8,
        fatG: 0.2,
        source: 'manual',
        sourceType: 'canteen',
        sourceId: menuItemId,
        sourceUpdatedAt: yesterday,
      ),
    );

    final result = await sync().apply((await dishes.watchAll().first).single);

    expect(result.outcome, DishSyncOutcome.noNutrition);
  });

  test('没有来源链接 ⇒ notLinked', () async {
    final stored = await dishes.create(
      DishDraft(
        name: '手工菜',
        mealSlot: '晚餐',
        kcal: 300,
        proteinG: 10,
        carbsG: 40,
        fatG: 8,
        source: 'manual',
      ),
    );
    final result = await sync().apply(stored);
    expect(result.outcome, DishSyncOutcome.notLinked);
  });
}

class _SeqIds implements IdGenerator {
  const _SeqIds();

  static int _next = 0;

  @override
  String next() => 'id-${++_next}';
}
