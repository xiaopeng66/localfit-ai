import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// **大库性能基线**（宿主机数字，docs/67 §8 P3 阶段门的宿主侧部分）：
/// 50k 条食物下，搜索/分页/计数必须保持「与总条数无关」或亚线性。
/// 这些**不能**替代设备实测（真机列 not run），但能防止 O(n) 扫描回归。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('50k 条食物：精确搜索 + 分页 + 计数都在预算内', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = FixedAppClock(DateTime.utc(2026, 11, 10, 12));
    final foods = FoodRepository(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );

    // 一次性批量插 50k（走 createMany 的 batch 路径，避免 5 万次事务）。
    final sw = Stopwatch()..start();
    const batchSize = 5000;
    for (var batch = 0; batch < 10; batch++) {
      await db.transaction(() async {
        await foods.createMany([
          for (var i = 0; i < batchSize; i++)
            NewFood(
              name: '基准食物${batch * batchSize + i}',
              kcalPer100g: 100 + (i % 400),
              proteinPer100g: 5 + (i % 15),
              carbsPer100g: 10 + (i % 20),
              fatPer100g: 3 + (i % 8),
            ),
        ]);
      });
    }
    sw.stop();
    // ignore: avoid_print
    print('[PERF] 50k 插入：${sw.elapsedMilliseconds}ms');

    final count = await foods.count();
    expect(count, 50000);

    // 精确搜索（主库 LIKE，带相关度排序）。
    sw
      ..reset()
      ..start();
    final hits = await foods.search('基准食物49999', limit: 30);
    sw.stop();
    // ignore: avoid_print
    print('[PERF] 精确搜索：${sw.elapsedMilliseconds}ms，命中 ${hits.length}');
    expect(hits, isNotEmpty);
    expect(
      sw.elapsedMilliseconds,
      lessThan(2000),
      reason: '50k 行 LIKE+排序必须亚秒级（宿主机）',
    );

    // 前缀搜索。
    sw
      ..reset()
      ..start();
    final prefix = await foods.search('基准食物25', limit: 30);
    sw.stop();
    // ignore: avoid_print
    print('[PERF] 前缀搜索：${sw.elapsedMilliseconds}ms，命中 ${prefix.length}');
    expect(prefix, isNotEmpty);
    expect(sw.elapsedMilliseconds, lessThan(2000));

    // 分页（offset 深处）。
    sw
      ..reset()
      ..start();
    final deep = await foods.page(query: '', offset: 49000, limit: 50);
    sw.stop();
    // ignore: avoid_print
    print('[PERF] 深分页：${sw.elapsedMilliseconds}ms，返回 ${deep.length}');
    expect(deep, hasLength(50));
    expect(sw.elapsedMilliseconds, lessThan(1000));

    // 计数。
    sw
      ..reset()
      ..start();
    final total = await foods.count();
    sw.stop();
    // ignore: avoid_print
    print('[PERF] 计数：${sw.elapsedMilliseconds}ms → $total');
    expect(total, 50000);
    expect(sw.elapsedMilliseconds, lessThan(1000));
  });

  test('50k 条下 FoodCatalogService 重复建库（每次带修订）仍可用', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final catalog = FoodCatalogService(
      database: db,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(DateTime.utc(2026, 11, 10, 12)),
    );

    final sw = Stopwatch()..start();
    for (var i = 0; i < 2000; i++) {
      await catalog.createMasterFood(
        name: '服务基准菜$i',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
    }
    sw.stop();
    // ignore: avoid_print
    print('[PERF] 服务级 2000 次建库：${sw.elapsedMilliseconds}ms');
    expect(sw.elapsedMilliseconds, lessThan(60000));
  });
}
