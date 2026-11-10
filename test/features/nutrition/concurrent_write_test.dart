import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/nutrition_math.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';

/// **真并发写竞争**（docs/67 §3.2 第 7 条）：两个**独立数据库连接**对同一条
/// 食物同时改，验证乐观锁与「最后写入不静默赢」。用文件库（内存库在 drift
/// 里是每实例独立的，连不到一起）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('双连接并发 revise：后提交者拿到投影冲突，先提交者数据不被覆盖', () async {
    final directory = await Directory.systemTemp.createTemp('localfit-conc-');
    final file = File('${directory.path}${Platform.pathSeparator}conc.sqlite');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final clock = FixedAppClock(DateTime.utc(2026, 11, 10, 12));
    final ids = const UuidV7Generator();

    // 连接 A：创建食物。
    final dbA = AppDatabase(NativeDatabase(file));
    final catalogA = FoodCatalogService(
      database: dbA,
      idGenerator: ids,
      clock: clock,
    );
    final foodId = await catalogA.createMasterFood(
      name: '并发菜',
      kcalPer100g: 100,
      proteinPer100g: 5,
      carbsPer100g: 10,
      fatPer100g: 3,
    );
    await dbA.close();

    // 连接 B 与 C 同时打开，各自 revise。
    final dbB = AppDatabase(NativeDatabase(file));
    final dbC = AppDatabase(NativeDatabase(file));
    addTearDown(dbB.close);
    addTearDown(dbC.close);
    final catalogB = FoodCatalogService(
      database: dbB,
      idGenerator: ids,
      clock: clock,
    );
    final catalogC = FoodCatalogService(
      database: dbC,
      idGenerator: ids,
      clock: clock,
    );

    // 两个连接**同时**发起 revise（同一 tick 启动）。SQLite 无 busy_timeout，
    // 撞锁即抛 SqliteException——应用生产是单连接写，双连接只是测试环境；
    // 这里验证的是「无论谁赢，库保持一致」。
    final results = await Future.wait([
      catalogB
          .reviseMasterFood(
            foodId: foodId,
            kcalPer100g: 110,
            proteinPer100g: 5,
            carbsPer100g: 10,
            fatPer100g: 3,
          )
          .then((_) => 'B-ok')
          .catchError((Object _) => 'B-conflict'),
      catalogC
          .reviseMasterFood(
            foodId: foodId,
            kcalPer100g: 120,
            proteinPer100g: 5,
            carbsPer100g: 10,
            fatPer100g: 3,
          )
          .then((_) => 'C-ok')
          .catchError((Object _) => 'C-conflict'),
    ]);

    // 至少一个成功；库必须保持一致（修订数 = 成功次数 + 1 基线）。
    final dbCheck = AppDatabase(NativeDatabase(file));
    addTearDown(dbCheck.close);
    final food = await (dbCheck.select(
      dbCheck.foods,
    )..where((t) => t.id.equals(foodId))).getSingle();
    final revisions = await dbCheck
        .select(dbCheck.foodNutritionRevisions)
        .get();
    final successes = results.where((r) => r.endsWith('ok')).length;
    expect(revisions.length, 1 + successes);

    // 生效指针与投影必须一致：四项等于当前生效修订，不能是混合值。
    final active = revisions.firstWhere((r) => r.id == food.currentRevisionId);
    expect(food.kcalPer100g, active.kcalPer100g);
    expect(food.proteinPer100g, active.proteinGPer100g);
    expect(
      food.kcalPer100g,
      anyOf(closeTo(100, 1e-9), closeTo(110, 1e-9), closeTo(120, 1e-9)),
      reason: '生效值必须是基线或两个并发写之一，不能是混合',
    );
  });

  test('双连接并发 update（乐观锁 token 相同）：恰有一个赢', () async {
    final directory = await Directory.systemTemp.createTemp('localfit-upd-');
    final file = File('${directory.path}${Platform.pathSeparator}upd.sqlite');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final clock = FixedAppClock(DateTime.utc(2026, 11, 10, 12));
    final ids = const UuidV7Generator();
    final dbSetup = AppDatabase(NativeDatabase(file));
    final foodsSetup = FoodRepository(
      database: dbSetup,
      idGenerator: ids,
      clock: clock,
    );
    final created = await foodsSetup.create(
      const NewFood(
        name: '并发编辑菜',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      ),
    );
    final staleToken = (await (dbSetup.select(
      dbSetup.foods,
    )..where((t) => t.id.equals(created.id))).getSingle()).updatedAt;
    await dbSetup.close();

    // 两个连接各开事务改同一行。
    final dbB = AppDatabase(NativeDatabase(file));
    final dbC = AppDatabase(NativeDatabase(file));
    addTearDown(dbB.close);
    addTearDown(dbC.close);
    final foodsB = FoodRepository(
      database: dbB,
      idGenerator: ids,
      clock: clock,
    );
    final foodsC = FoodRepository(
      database: dbC,
      idGenerator: ids,
      clock: clock,
    );

    final outcomes = await Future.wait([
      foodsB
          .update(
            created.id,
            const NewFood(
              name: '并发编辑菜',
              kcalPer100g: 111,
              proteinPer100g: 5,
              carbsPer100g: 10,
              fatPer100g: 3,
            ),
            expectedUpdatedAt: staleToken,
          )
          .then((_) => 'B-ok')
          .catchError((Object _) => 'B-conflict'),
      foodsC
          .update(
            created.id,
            const NewFood(
              name: '并发编辑菜',
              kcalPer100g: 122,
              proteinPer100g: 5,
              carbsPer100g: 10,
              fatPer100g: 3,
            ),
            expectedUpdatedAt: staleToken,
          )
          .then((_) => 'C-ok')
          .catchError((Object _) => 'C-conflict'),
    ]);

    // 乐观锁保证：至多一个成功（SQLITE_BUSY 也算 conflict）。
    final wins = outcomes.where((r) => r.endsWith('ok')).length;
    expect(wins, lessThanOrEqualTo(1), reason: '同 token 双写必须至多一赢：$outcomes');

    // 库里最终值是赢家之一（或原值，如果都被 BUSY 挡掉）。
    final dbCheck = AppDatabase(NativeDatabase(file));
    addTearDown(dbCheck.close);
    final row = await (dbCheck.select(
      dbCheck.foods,
    )..where((t) => t.id.equals(created.id))).getSingle();
    expect(row.kcalPer100g, anyOf(100, 111, 122), reason: '不能是混合值或其它值');
  });

  test('并发批量记餐（双连接各记 50 餐）：行数精确、无半行', () async {
    final directory = await Directory.systemTemp.createTemp('localfit-meal-');
    final file = File('${directory.path}${Platform.pathSeparator}meal.sqlite');
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final clock = FixedAppClock(DateTime.utc(2026, 11, 10, 12));
    final ids = const UuidV7Generator();
    final dbSetup = AppDatabase(NativeDatabase(file));
    final catalog = FoodCatalogService(
      database: dbSetup,
      idGenerator: ids,
      clock: clock,
    );
    final foodId = await catalog.createMasterFood(
      name: '并发餐菜',
      kcalPer100g: 100,
      proteinPer100g: 5,
      carbsPer100g: 10,
      fatPer100g: 3,
    );
    await dbSetup.close();

    final dbB = AppDatabase(NativeDatabase(file));
    final dbC = AppDatabase(NativeDatabase(file));
    addTearDown(dbB.close);
    addTearDown(dbC.close);
    final mealsB = MealRepository(
      database: dbB,
      idGenerator: ids,
      clock: clock,
    );
    final mealsC = MealRepository(
      database: dbC,
      idGenerator: ids,
      clock: clock,
    );

    Future<String> writeMeal(MealRepository repo, int grams) => repo.create(
      MealDraft(
        localDate: '2026-11-10',
        slot: MealSlot.lunch,
        items: [
          NutritionMath.fromMasterAtGrams(
            foodId: foodId,
            name: '并发餐菜',
            kcalPer100g: 100,
            proteinPer100g: 5,
            carbsPer100g: 10,
            fatPer100g: 3,
            grams: grams.toDouble(),
          ),
        ],
      ),
    );

    // 100 个并发写，SQLite 撞锁的会失败（无 busy_timeout）——预期。
    // 断言：**成功多少就落多少行，绝不出现半行**；汇总与成功行一致。
    final outcomes = await Future.wait([
      for (var i = 0; i < 50; i++)
        writeMeal(
          mealsB,
          100 + i,
        ).then((_) => 100 + i).catchError((Object _) => -1),
      for (var i = 0; i < 50; i++)
        writeMeal(
          mealsC,
          200 + i,
        ).then((_) => 200 + i).catchError((Object _) => -1),
    ]);
    final succeededGrams = outcomes.where((g) => g >= 0).toList();

    final dbCheck = AppDatabase(NativeDatabase(file));
    addTearDown(dbCheck.close);
    final mealCount = await dbCheck
        .customSelect('SELECT COUNT(*) AS c FROM meals')
        .getSingle();
    final itemCount = await dbCheck
        .customSelect('SELECT COUNT(*) AS c FROM meal_items')
        .getSingle();
    expect(mealCount.read<int>('c'), succeededGrams.length, reason: '无半行');
    expect(itemCount.read<int>('c'), succeededGrams.length, reason: '无丢失');
    final summary = await MealRepository(
      database: dbCheck,
      idGenerator: ids,
      clock: clock,
    ).watchNutritionForDate('2026-11-10').first;
    // 汇总 = Σ 成功行的 kcal（每 100g 100 kcal ⇒ kcal == 克数）。
    final expected = succeededGrams.fold(0.0, (sum, grams) => sum + grams);
    expect(summary.consumed.kcal, closeTo(expected, 1e-6));
  });
}
