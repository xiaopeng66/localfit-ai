import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/application/add_canteen_dishes_to_library.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// 食堂目录 → 菜品库：菜单页唯一主来源（docs/21 §5.3 写入路径 1）的写入者。
///
/// 这个类存在的原因就是「菜品库过去没有任何写入者，菜单页永远为空」，
/// 所以本文件的断言全部围绕**真的写进去了**、**写进去的是什么**、
/// **没有数据时不编**三件事。
void main() {
  late AppDatabase database;
  late CanteenRepository canteen;
  late DishLibraryRepository dishLibrary;
  late AddCanteenDishesToLibrary addDishes;
  late String venueId;
  final now = DateTime.utc(2026, 9, 28, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    canteen = CanteenRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(now),
    );
    dishLibrary = DishLibraryRepository(
      database: database,
      idGenerator: _IncrementingIdGenerator(),
      clock: FixedAppClock(now),
    );
    addDishes = AddCanteenDishesToLibrary(
      dishLibrary: dishLibrary,
      canteen: canteen,
    );
    venueId = await canteen.createVenue(name: '东区食堂', campusName: '示范大学');
  });

  tearDown(() => database.close());

  /// 建窗口 + 一道菜；[nutrition] 为 null 表示「还没分析」。
  Future<({String windowId, String dishId})> seedDish({
    String windowName = '一楼快餐',
    String openTime = '11:00',
    String closeTime = '13:30',
    String dishName = '番茄炒蛋',
    List<double>? nutrition,
  }) async {
    final windowId = await canteen.createWindow(
      venueId: venueId,
      name: windowName,
      openTime: openTime,
      closeTime: closeTime,
    );
    final dishId = await canteen.createDish(windowId: windowId, name: dishName);
    if (nutrition != null) {
      await canteen.recordNutrition(
        dishId: dishId,
        kcalPer100g: nutrition[0],
        proteinPer100g: nutrition[1],
        carbsPer100g: nutrition[2],
        fatPer100g: nutrition[3],
        grade: 'B',
        confidence: 0.8,
      );
    }
    return (windowId: windowId, dishId: dishId);
  }

  Future<List<DishRecord>> library() => dishLibrary.watchAll().first;

  test('已分析的菜品按 100g 等值写入菜品库（不是新约定，是既有口径）', () async {
    final seeded = await seedDish(nutrition: [142, 8.4, 6.2, 9.1]);
    final window = (await canteen.listWindows(venueId)).single;

    final result = await addDishes.run(
      windowId: seeded.windowId,
      dishes: window.dishes,
    );

    expect(result.written, 1);
    expect(result.skipped, 0);
    final dish = (await library()).single;
    expect(dish.name, '番茄炒蛋');
    expect(dish.kcal, 142);
    expect(dish.proteinG, 8.4);
    expect(dish.carbsG, 6.2);
    expect(dish.fatG, 9.1);
    expect(dish.source, 'ai_estimate', reason: '证据一律 ai_estimate，不冒充营养师确认');
  });

  test('缺营养值的菜品跳过并如实报数，不写半张空卡', () async {
    final analyzed = await seedDish(
      dishName: '番茄炒蛋',
      nutrition: [142, 8.4, 6.2, 9.1],
    );
    await canteen.createDish(windowId: analyzed.windowId, name: '红烧肉');
    final window = (await canteen.listWindows(venueId)).single;
    expect(window.dishes, hasLength(2));

    final result = await addDishes.run(
      windowId: analyzed.windowId,
      dishes: window.dishes,
    );

    expect(result.written, 1);
    expect(result.skipped, 1);
    expect((await library()).map((dish) => dish.name), [
      '番茄炒蛋',
    ], reason: '未分析的菜品不得进库');
  });

  test('窗口营业时段映射餐次：09:30 前=早餐、14:00 前=午餐、20:30 前=晚餐、更晚=加餐', () async {
    final cases = {
      ('06:30', '09:30'): 'breakfast',
      ('11:00', '13:30'): 'lunch',
      ('16:30', '19:00'): 'dinner',
      ('20:00', '22:30'): 'snack',
    };
    var index = 0;
    for (final entry in cases.entries) {
      index++;
      final seeded = await seedDish(
        windowName: '窗口$index',
        openTime: entry.key.$1,
        closeTime: entry.key.$2,
        dishName: '菜品$index',
        nutrition: [100, 5, 5, 5],
      );
      final window = (await canteen.listWindows(venueId))
          .firstWhere((item) => item.id == seeded.windowId);
      await addDishes.run(windowId: seeded.windowId, dishes: window.dishes);
    }

    final slots = {
      for (final dish in await library()) dish.name: dish.mealSlot,
    };
    expect(slots, {
      '菜品1': cases[('06:30', '09:30')],
      '菜品2': cases[('11:00', '13:30')],
      '菜品3': cases[('16:30', '19:00')],
      '菜品4': cases[('20:00', '22:30')],
    });
    expect(slots['菜品1'], 'breakfast');
    expect(slots['菜品2'], 'lunch');
    expect(slots['菜品3'], 'dinner');
    expect(slots['菜品4'], 'snack');
  });

  test('窗口已被删除时回落到午餐 —— 既有兜底口径，不是新猜的规则', () async {
    final seeded = await seedDish(nutrition: [142, 8.4, 6.2, 9.1]);
    final window = (await canteen.listWindows(venueId)).single;
    await canteen.deleteWindow(seeded.windowId);

    final result = await addDishes.run(
      windowId: seeded.windowId,
      dishes: window.dishes,
    );
    expect(result.written, 1);
    expect((await library()).single.mealSlot, 'lunch');
  });

  test('供应时段写进 servingWindow，供菜品卡展示', () async {
    final seeded = await seedDish(
      openTime: '11:00',
      closeTime: '13:30',
      nutrition: [142, 8.4, 6.2, 9.1],
    );
    final window = (await canteen.listWindows(venueId)).single;
    await addDishes.run(windowId: seeded.windowId, dishes: window.dishes);

    expect((await library()).single.servingWindow, '11:00-13:30');
  });

  test('同窗口重复「加入菜品库」不产生重复行，且刷新营养与时段', () async {
    final seeded = await seedDish(nutrition: [142, 8.4, 6.2, 9.1]);
    final window = (await canteen.listWindows(venueId)).single;
    await addDishes.run(windowId: seeded.windowId, dishes: window.dishes);
    final first = (await library()).single;

    // 重新分析后营养变了，再点一次「加入菜品库」。
    await canteen.recordNutrition(
      dishId: seeded.dishId,
      kcalPer100g: 160,
      proteinPer100g: 9.0,
      carbsPer100g: 7.0,
      fatPer100g: 10.5,
      grade: 'A',
      confidence: 0.95,
    );
    final window2 = (await canteen.listWindows(venueId)).single;
    await addDishes.run(windowId: seeded.windowId, dishes: window2.dishes);

    final all = await library();
    expect(all, hasLength(1), reason: '同名 = 同一道菜，不重复建行');
    expect(all.single.id, first.id, reason: '更新保留原 id，列表顺序稳定');
    expect(all.single.createdAt, first.createdAt);
    expect(all.single.kcal, 160, reason: '重新分析后要取最新值');
    expect(all.single.source, 'ai_estimate');
  });

  test('食堂证据没有的字段留空：不编点评与微量营养素', () async {
    final seeded = await seedDish(nutrition: [142, 8.4, 6.2, 9.1]);
    final window = (await canteen.listWindows(venueId)).single;
    await addDishes.run(windowId: seeded.windowId, dishes: window.dishes);

    final dish = (await library()).single;
    expect(dish.fiberG, isNull);
    expect(dish.sodiumMg, isNull);
    expect(dish.vitaminDMcg, isNull);
    expect(dish.comment, isNull);
    expect(dish.imagePath, isNull);
  });

  test('空菜品列表：一条不写，结果是空而不是抛错', () async {
    final seeded = await seedDish(nutrition: [142, 8.4, 6.2, 9.1]);
    final result = await addDishes.run(
      windowId: seeded.windowId,
      dishes: const [],
    );

    expect(result.written, 0);
    expect(result.skipped, 0);
    expect(result.isEmpty, isTrue);
    expect(await library(), isEmpty);
  });
}

class _IncrementingIdGenerator implements IdGenerator {
  var _value = 0;

  @override
  String next() => 'id-${++_value}';
}
