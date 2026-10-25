import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';

/// 分类筛选的 2 万行基准（Round7 阶段 3 · D35）。
///
/// **为什么单独一份**：D34 给 `count/page` 加了**可选**分类 `WHERE`，而
/// `foods.category` **没有索引**——加索引 = 改库结构，超出本轮视觉改造范围
/// （登记在证据文件）。于是分类筛选走的是「排序 + `LIMIT/OFFSET` 全表扫」，
/// 这条路的代价必须**量出来**而不是假定没事。
///
/// 口径沿用仓内既有基准（`query_benchmark_test.dart`）：桌面 in-memory SQLite、
/// 宽护栏 **<1000ms**（只捕获病态回归：索引缺失退化、意外笛卡尔积），实测值
/// 如实打印、真机门槛留阶段 7（`docs/05` §2）。
void main() {
  late AppDatabase database;
  late FoodRepository repository;

  setUpAll(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = FoodRepository(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: const SystemAppClock(),
    );
    await _seedTwentyThousand(database);
  });

  tearDownAll(() => database.close());

  test('2 万行分类筛选：count / 首页 / 深页都在宽护栏内', () async {
    // 十档真实分类轮转 ⇒ 每档 2,000 行（深页取到第 1,800 条，接近尾部）。
    const category = FoodCategory.staple;

    final countWatch = Stopwatch()..start();
    final count = await repository.count(category: category);
    countWatch.stop();

    final headWatch = Stopwatch()..start();
    final head = await repository.page(
      offset: 0,
      limit: 50,
      category: category,
    );
    headWatch.stop();

    final deepWatch = Stopwatch()..start();
    final tail = await repository.page(
      offset: 1800,
      limit: 50,
      category: category,
    );
    deepWatch.stop();

    //ignore: avoid_print
    print('分类 count（20,000 行、无索引）: ${countWatch.elapsedMilliseconds} ms');
    //ignore: avoid_print
    print('分类首页 page(0,50): ${headWatch.elapsedMilliseconds} ms');
    //ignore: avoid_print
    print('分类深页 page(1800,50): ${deepWatch.elapsedMilliseconds} ms');

    expect(count, 2000, reason: '20,000 行按十档轮转 ⇒ 每档 2,000');
    expect(head, hasLength(50));
    expect(tail, hasLength(50));
    expect(
      head.first.category,
      category,
      reason: '分类筛的是落库枚举 id（D34），返回行必须真属该档',
    );
    // 宽松回归护栏：桌面 in-memory 正常 <50ms；超过 1s 说明查询退化。
    expect(countWatch.elapsedMilliseconds, lessThan(1000));
    expect(headWatch.elapsedMilliseconds, lessThan(1000));
    expect(deepWatch.elapsedMilliseconds, lessThan(1000));
  });
}

Future<void> _seedTwentyThousand(AppDatabase database) async {
  final base = DateTime.utc(2026, 1, 1);
  final categories = FoodCategory.values;
  await database.batch((batch) {
    for (var i = 0; i < 20000; i++) {
      final ts = base.add(Duration(minutes: i));
      batch.insert(
        database.foods,
        FoodsCompanion.insert(
          id: 'bench-food-${i.toString().padLeft(6, '0')}',
          name: '基准食物${i.toString().padLeft(6, '0')}',
          kcalPer100g: 100 + i % 400,
          proteinPer100g: 10,
          carbsPer100g: 10,
          fatPer100g: 5,
          source: 'bench-20k',
          category: Value(categories[i % categories.length].id),
          createdAt: ts,
          updatedAt: ts,
        ),
      );
    }
  });
}
