import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

import '../../support/food_fixture.dart';

/// 2026-10-31 用户：「餐卡逐食物勾选删除，而不是只能整餐删除」。
/// 删除与撤销都走真实 Drift 库，验证不会误删同餐其他食物，也不会在撤销时
/// 多出一条重复餐记录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository foods;
  late MealRepository meals;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    final ids = _Ids();
    final clock = FixedAppClock(DateTime.utc(2026, 10, 31, 12));
    foods = FoodRepository(database: database, idGenerator: ids, clock: clock);
    meals = MealRepository(database: database, idGenerator: ids, clock: clock);
  });

  tearDown(() => database.close());

  Future<MealRecord> seedLunch() async {
    final rice = (await foods.search('米饭')).first;
    final egg = (await foods.search('鸡蛋')).first;
    final id = await meals.create(
      MealDraft(
        localDate: '2026-10-31',
        slot: MealSlot.lunch,
        items: [
          MealItemDraft.fromFood(rice, 100),
          MealItemDraft.fromFood(egg, 50),
        ],
      ),
    );
    return (await meals.getById(id))!;
  }

  test('只删选中的 item：同餐其他食物与合计按真实剩余重算', () async {
    final before = await seedLunch();
    final removed = before.items.first;
    final kept = before.items.last;

    final snapshot = await meals.deleteItems(before.id, {removed.id});

    expect(snapshot!.items, hasLength(2), reason: '撤销需要完整删除前快照');
    final after = (await meals.getById(before.id))!;
    expect(after.items.map((item) => item.id), [kept.id]);
    final summary = await meals.watchNutritionForDate('2026-10-31').first;
    expect(summary.consumed.kcal, closeTo(kept.nutrition.kcal, .001));
  });

  test('撤销部分删除：按原 item id 补回，不重复建餐', () async {
    final before = await seedLunch();
    final snapshot = (await meals.deleteItems(before.id, {
      before.items.first.id,
    }))!;

    await meals.restore(snapshot);
    await meals.restore(snapshot); // 重复撤销也幂等。

    final restored = (await meals.getById(before.id))!;
    expect(
      restored.items.map((item) => item.id).toSet(),
      before.items.map((item) => item.id).toSet(),
    );
    expect(await database.select(database.meals).get(), hasLength(1));
    expect(await database.select(database.mealItems).get(), hasLength(2));
  });

  test('全部 item 被选中：移除餐记录；撤销后完整恢复', () async {
    final before = await seedLunch();
    final snapshot = (await meals.deleteItems(before.id, {
      for (final item in before.items) item.id,
    }))!;

    expect(await meals.getById(before.id), isNull);
    await meals.restore(snapshot);
    expect((await meals.getById(before.id))!.items, hasLength(2));
  });

  test('没有命中 item：不修改任何数据', () async {
    final before = await seedLunch();
    expect(await meals.deleteItems(before.id, {'not-found'}), isNull);
    expect((await meals.getById(before.id))!.items, hasLength(2));
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'item-delete-${_value++}';
}
