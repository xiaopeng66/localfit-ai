import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/catalog_resolver.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 两库解析的**边界条件**（2026-11-05 审计补测）。
///
/// 重点：食物写入会归一化名称（`（外卖，…）` → `（外卖；…）`），按名字回查
/// 必须用同一套归一化；否则「刚建过、下一轮再引用」会报找不到。
void main() {
  late AppDatabase db;
  late FoodRepository foods;
  late DishLibraryRepository dishes;
  late CatalogResolver resolver;
  final now = DateTime.utc(2026, 11, 5, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    foods = FoodRepository(
      database: db,
      idGenerator: _Ids('food'),
      clock: FixedAppClock(now),
    );
    dishes = DishLibraryRepository(
      database: db,
      idGenerator: _Ids('dish'),
      clock: FixedAppClock(now),
    );
    resolver = CatalogResolver(foods: foods, dishes: dishes);
  });

  tearDown(() => db.close());

  test('食物名写入时归一化，按原名回查仍能命中', () async {
    const raw = '番茄炒蛋（外卖，午餐肉+丸子）';
    await foods.create(
      const NewFood(
        name: raw,
        kcalPer100g: 142,
        proteinPer100g: 8.4,
        carbsPer100g: 6.2,
        fatPer100g: 9.1,
      ),
    );

    final stored = (await foods.searchExact(raw));
    expect(stored, hasLength(1), reason: '逗号→分号后仍要能按原名查到');
    final resolution = await resolver.resolve(raw);
    expect(resolution, isA<CatalogFood>());
  });

  test('同名双库 → CatalogAmbiguous；带 id 可精确指定', () async {
    final food = await foods.create(
      const NewFood(
        name: '番茄炒蛋',
        kcalPer100g: 142,
        proteinPer100g: 8.4,
        carbsPer100g: 6.2,
        fatPer100g: 9.1,
      ),
    );
    final dish = await dishes.create(
      DishDraft(
        name: '番茄炒蛋',
        mealSlot: 'lunch',
        kcal: 300,
        proteinG: 15,
        carbsG: 10,
        fatG: 21,
        servingGrams: 250,
        source: 'manual',
      ),
    );

    expect(await resolver.resolve('番茄炒蛋'), isA<CatalogAmbiguous>());
    expect(await resolver.resolve('[food:${food.id}]'), isA<CatalogFood>());
    expect(await resolver.resolve('[dish:${dish.id}]'), isA<CatalogDish>());
  });

  test('未同步的 [canteen-dish:] → CatalogNeedsAnalysis，不猜', () async {
    final resolution = await resolver.resolve('[canteen-dish:menu-9]');
    expect(resolution, isA<CatalogNeedsAnalysis>());
  });
}

final class _Ids implements IdGenerator {
  _Ids(this.prefix);
  final String prefix;
  int value = 0;

  @override
  String next() => '$prefix-${value++}';
}
