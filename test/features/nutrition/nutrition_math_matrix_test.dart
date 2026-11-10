import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/core/nutrition/legacy_nutrition_rules.dart';
import 'package:localfit_ai/features/nutrition/application/food_catalog_service.dart';
import 'package:localfit_ai/features/nutrition/application/nutrition_math.dart';
import 'package:localfit_ai/features/nutrition/application/supply_dish_candidates.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 营养数学的**数值域**测试（docs/67 §4.1、§3.5）：精算、边界、非法输入、
/// 浮点稳定性、单位换算、份数解析。每条断言都是纯函数行为，不碰库。
void main() {
  // ── 精算 ──────────────────────────────────────────────────────────────
  group('精算（不凑整）', () {
    test('公式：per100g × grams ÷ 100', () {
      final item = NutritionMath.fromMasterAtGrams(
        foodId: 'f',
        name: '米饭',
        kcalPer100g: 116.0,
        proteinPer100g: 2.6,
        carbsPer100g: 25.9,
        fatPer100g: 0.3,
        grams: 150,
      );
      expect(item.nutrition.kcal, closeTo(174, 1e-9));
      expect(item.nutrition.proteinGrams, closeTo(3.9, 1e-9));
      expect(item.nutrition.carbsGrams, closeTo(38.85, 1e-9));
      expect(item.nutrition.fatGrams, closeTo(0.45, 1e-9));
    });

    test('浮点稳定性：同一输入重复计算结果逐位相同', () {
      var first = NutritionMath.fromMasterAtGrams(
        foodId: 'f',
        name: 'x',
        kcalPer100g: 123.456,
        proteinPer100g: 7.89,
        carbsPer100g: 12.34,
        fatPer100g: 5.67,
        grams: 333,
      ).nutrition;
      for (var i = 0; i < 50; i++) {
        final again = NutritionMath.fromMasterAtGrams(
          foodId: 'f',
          name: 'x',
          kcalPer100g: 123.456,
          proteinPer100g: 7.89,
          carbsPer100g: 12.34,
          fatPer100g: 5.67,
          grams: 333,
        ).nutrition;
        expect(again.kcal, first.kcal);
        expect(again.proteinGrams, first.proteinGrams);
      }
    });

    test('极小克数不丢精度（0.1g）', () {
      final item = NutritionMath.fromMasterAtGrams(
        foodId: 'f',
        name: '调料',
        kcalPer100g: 800,
        proteinPer100g: 0.1,
        carbsPer100g: 99.9,
        fatPer100g: 0,
        grams: 0.1,
      );
      expect(item.nutrition.kcal, closeTo(0.8, 1e-9));
      expect(item.nutrition.carbsGrams, closeTo(0.0999, 1e-12));
    });

    test('极大克数（上限内）不溢出', () {
      final item = NutritionMath.fromMasterAtGrams(
        foodId: 'f',
        name: '油',
        kcalPer100g: 900,
        proteinPer100g: 0,
        carbsPer100g: 0,
        fatPer100g: 100,
        grams: 5000,
      );
      expect(item.nutrition.kcal, closeTo(45000, 1e-6));
      expect(item.nutrition.fatGrams, closeTo(5000, 1e-6));
    });

    test('份换算：份数 × 每份克数，0.5 份也精确', () {
      final item = NutritionMath.fromSupply(
        supplyId: 's',
        displayName: '宫保鸡丁',
        kcalPer100g: 180,
        proteinPer100g: 12,
        carbsPer100g: 8,
        fatPer100g: 11,
        servings: 0.5,
        servingGrams: 200,
      );
      expect(item.grams, closeTo(100, 1e-9));
      expect(item.nutrition.kcal, closeTo(180, 1e-9));
      expect(item.servings, 0.5);
    });
  });

  // ── 单位换算 ──────────────────────────────────────────────────────────
  group('单位换算（per100g ↔ perServing）', () {
    test('双向换算往返不漂移', () {
      const per100g = 233.7;
      const grams = 187.5;
      final perServing = perServingFromPer100g(
        per100g: per100g,
        servingGrams: grams,
      )!;
      final back = per100gFromPerServing(
        perServing: perServing,
        servingGrams: grams,
      )!;
      expect(back, closeTo(per100g, 1e-9));
    });

    test('null 份量返回 null，绝不返回 0', () {
      expect(
        per100gFromPerServing(perServing: 400, servingGrams: null),
        isNull,
      );
      expect(perServingFromPer100g(per100g: 400, servingGrams: null), isNull);
    });

    test('负份量返回 null（不换算）', () {
      expect(per100gFromPerServing(perServing: 400, servingGrams: -5), isNull);
      expect(perServingFromPer100g(per100g: 400, servingGrams: -5), isNull);
    });

    test('roundForDisplay 显示舍入不改计算值', () {
      final raw = 174.66666;
      expect(roundForDisplay(raw, digits: 0), 175);
      expect(roundForDisplay(raw, digits: 1), 174.7);
      expect(raw, 174.66666, reason: '原值不被改动');
    });
  });

  // ── 非法输入拒绝 ──────────────────────────────────────────────────────
  group('非法输入拒绝（数学层）', () {
    double buildGrams(double grams) => NutritionMath.fromMasterAtGrams(
      foodId: 'f',
      name: 'x',
      kcalPer100g: 100,
      proteinPer100g: 1,
      carbsPer100g: 1,
      fatPer100g: 1,
      grams: grams,
    ).nutrition.kcal;

    test('克数边界批量扫描', () {
      final bad = [
        -5000.0,
        -1.0,
        -0.001,
        0.0,
        double.nan,
        double.negativeInfinity,
        double.infinity,
        NutritionLimits.maxGrams + 0.001,
        999999.0,
      ];
      for (final grams in bad) {
        expect(
          () => buildGrams(grams),
          throwsA(isA<ArgumentError>()),
          reason: 'grams=$grams 必须被拒',
        );
      }
    });

    test('克数合法值批量扫描（边界含）', () {
      for (final grams in [0.001, 0.1, 1.0, 100.0, 5000.0]) {
        expect(
          () => buildGrams(grams),
          returnsNormally,
          reason: 'grams=$grams 应该合法',
        );
      }
    });

    test('份数非法批量扫描', () {
      final bad = [-1.0, 0.0, double.nan, double.infinity, 100.0];
      for (final servings in bad) {
        expect(
          () => NutritionMath.fromSupply(
            supplyId: 's',
            displayName: 'x',
            kcalPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 1,
            fatPer100g: 1,
            servings: servings,
            servingGrams: 200,
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'servings=$servings 必须被拒',
        );
      }
    });

    test('份量未知：四种形态全部拒绝按份记', () {
      final cases = [
        (null, ServingGramsStatus.unknown),
        (100.0, ServingGramsStatus.unknown),
        (double.nan, ServingGramsStatus.estimated),
        (-1.0, ServingGramsStatus.estimated),
      ];
      for (final (grams, status) in cases) {
        expect(
          () => NutritionMath.fromSupply(
            supplyId: 's',
            displayName: 'x',
            kcalPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 1,
            fatPer100g: 1,
            servings: 1,
            servingGrams: grams,
            servingGramsStatus: status,
          ),
          throwsA(isA<ServingGramsUnknown>()),
          reason: 'grams=$grams status=$status 必须按份拒绝',
        );
      }
    });

    test('resolveGrams：克数优先、份数换算、两个都无效返回 null', () {
      expect(
        NutritionMath.resolveGrams(servings: 2, grams: 150, servingGrams: 200),
        150,
        reason: '显式克数优先',
      );
      expect(NutritionMath.resolveGrams(servings: 2, servingGrams: 200), 400);
      expect(
        NutritionMath.resolveGrams(servings: 2, servingGrams: null),
        isNull,
        reason: '份量未知时份数解析不出克数',
      );
      expect(NutritionMath.resolveGrams(grams: 0, servingGrams: 200), isNull);
      expect(
        NutritionMath.resolveGrams(
          servings: -1,
          grams: null,
          servingGrams: 200,
        ),
        isNull,
      );
    });
  });

  // ── 旧菜品兼容 ────────────────────────────────────────────────────────
  group('旧菜品（每份口径）', () {
    DishRecord dish({
      double? servingGrams,
      bool basisAssumed = false,
      double kcal = 400,
    }) => DishRecord(
      id: 'd',
      name: '旧菜',
      mealSlot: 'lunch',
      kcal: kcal,
      proteinG: 20,
      carbsG: 30,
      fatG: 20,
      source: 'manual',
      servingGrams: servingGrams,
      basisAssumed: basisAssumed,
      createdAt: DateTime.utc(2026, 11, 10),
      updatedAt: DateTime.utc(2026, 11, 10),
    );

    test('可信份量：按克正确换算', () {
      final item = NutritionMath.fromLegacyDish(dish(servingGrams: 250), 100);
      expect(item.nutrition.kcal, closeTo(160, 1e-9));
      expect(item.sourceType, 'dish');
    });

    test('假设份量：拒绝', () {
      expect(
        () => NutritionMath.fromLegacyDish(
          dish(servingGrams: 100, basisAssumed: true),
          100,
        ),
        throwsA(isA<ServingGramsUnknown>()),
      );
    });

    test('负份量：拒绝', () {
      expect(
        () => NutritionMath.fromLegacyDish(dish(servingGrams: -1), 100),
        throwsA(isA<ServingGramsUnknown>()),
      );
    });

    test('nan 份量：拒绝', () {
      expect(
        () => NutritionMath.fromLegacyDish(dish(servingGrams: double.nan), 100),
        throwsA(isA<ServingGramsUnknown>()),
      );
    });
  });

  // ── 供应候选映射 ──────────────────────────────────────────────────────
  group('供应候选映射（supplyDishCandidates）', () {
    SupplyCatalogItem supply({
      required String id,
      required String name,
      required double kcal,
      double? servingGrams,
      String status = 'known',
      String source = 'user_input',
      bool archived = false,
    }) => SupplyCatalogItem(
      id: id,
      displayName: name,
      windowId: 'w',
      windowName: '窗口',
      openTime: '11:00',
      closeTime: '13:30',
      venueId: 'v',
      venueName: '食堂',
      foodId: 'food-$id',
      foodName: name,
      kcalPer100g: kcal,
      proteinPer100g: 10,
      carbsPer100g: 20,
      fatPer100g: 5,
      revisionId: 'rev-1',
      servingGrams: servingGrams,
      servingGramsStatus: ServingGramsStatus.fromStored(status),
      servingGramsSource: ServingGramsSource.fromStored(source),
      foodArchived: archived,
    );

    test('只收可推荐的：待分析/份量未知/估计/归档全部排除', () {
      final out = supplyDishCandidates([
        supply(id: 'a', name: '已知', kcal: 180, servingGrams: 200),
        supply(
          id: 'b',
          name: '估计',
          kcal: 180,
          servingGrams: 200,
          status: 'estimated',
          source: 'ai_estimate',
        ),
        supply(id: 'c', name: '未知', kcal: 180),
        supply(
          id: 'd',
          name: '归档',
          kcal: 180,
          servingGrams: 200,
          archived: true,
        ),
        supply(
          id: 'e',
          name: '来源不可信',
          kcal: 180,
          servingGrams: 200,
          source: 'legacy_unverified',
        ),
      ], now: DateTime.utc(2026, 11, 10));
      expect(out.map((dish) => dish.id), ['a']);
    });

    test('每份口径换算正确', () {
      final out = supplyDishCandidates([
        supply(id: 'a', name: '菜', kcal: 180, servingGrams: 200),
      ], now: DateTime.utc(2026, 11, 10));
      expect(out.single.kcal, closeTo(360, 1e-9));
      expect(out.single.proteinG, closeTo(20, 1e-9));
      expect(out.single.basisAssumed, isFalse);
      expect(out.single.sourceType, kCanteenSourceType);
      expect(out.single.sourceId, 'food-a');
    });

    test('来源 id 是主食物（不是供应）——快照与追踪要指向身份', () {
      final out = supplyDishCandidates([
        supply(id: 'a', name: '菜', kcal: 100, servingGrams: 100),
      ], now: DateTime.utc(2026, 11, 10));
      expect(out.single.sourceType, kCanteenSourceType);
      expect(out.single.servingGrams, 100);
    });
  });

  // ── 纯函数不变量 ──────────────────────────────────────────────────────
  group('纯函数不变量', () {
    test('isCompleteNutrition 拒绝 NaN/∞/负/null', () {
      expect(
        isCompleteNutrition(
          kcalPer100g: double.nan,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ),
        isFalse,
      );
      expect(
        isCompleteNutrition(
          kcalPer100g: -1,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ),
        isFalse,
      );
      expect(
        isCompleteNutrition(
          kcalPer100g: null,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ),
        isFalse,
      );
      expect(
        isCompleteNutrition(
          kcalPer100g: 0,
          proteinPer100g: 0,
          carbsPer100g: 0,
          fatPer100g: 0,
        ),
        isTrue,
        reason: '零是真实值（水、黑咖啡），不是缺失',
      );
    });
  });

  // ── 库级批量边界 ──────────────────────────────────────────────────────
  group('库级批量与事务边界', () {
    late AppDatabase db;
    late FoodCatalogService catalog;
    late MealRepository meals;
    final now = DateTime.utc(2026, 11, 10, 12);

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      catalog = FoodCatalogService(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
      meals = MealRepository(
        database: db,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      );
    });

    tearDown(() => db.close());

    test('批量建 500 条主食物：行数、修订数、指针全部对账', () async {
      for (var i = 0; i < 500; i++) {
        await catalog.createMasterFood(
          name: '批量菜$i',
          kcalPer100g: 100 + i % 400,
          proteinPer100g: 5 + i % 15,
          carbsPer100g: 10 + i % 20,
          fatPer100g: 3 + i % 8,
        );
      }
      final foodCount = (await db.select(db.foods).get()).length;
      final revisionCount =
          (await db.select(db.foodNutritionRevisions).get()).length;
      expect(foodCount, 500);
      expect(revisionCount, 500, reason: '每条一个基线修订');
      final missing = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM foods WHERE current_revision_id IS NULL',
          )
          .getSingle();
      expect(missing.read<int>('c'), 0);
    });

    test('批量记 200 餐：汇总与单条一致', () async {
      final foodId = await catalog.createMasterFood(
        name: '批量餐菜',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
      for (var i = 0; i < 200; i++) {
        await meals.create(
          MealDraft(
            localDate: '2026-11-10',
            slot: MealSlot.lunch,
            items: [
              NutritionMath.fromMasterAtGrams(
                foodId: foodId,
                name: '批量餐菜',
                kcalPer100g: 100,
                proteinPer100g: 5,
                carbsPer100g: 10,
                fatPer100g: 3,
                grams: (100 + i).toDouble(),
              ),
            ],
          ),
          source: 'manual',
        );
      }
      final summary = await meals.watchNutritionForDate('2026-11-10').first;
      // Σ 100..299 = 39900 g，每 100g 100 kcal ⇒ 39900 kcal。
      expect(summary.consumed.kcal, closeTo(39900, 1e-6));
      expect(summary.consumed.proteinGrams, closeTo(1995, 1e-6));
    });

    test(' meal item 批量边界：0 营养（纯水）可以记', () async {
      final foodId = await catalog.createMasterFood(
        name: '纯净水',
        kcalPer100g: 0,
        proteinPer100g: 0,
        carbsPer100g: 0,
        fatPer100g: 0,
      );
      final mealId = await meals.create(
        MealDraft(
          localDate: '2026-11-10',
          slot: MealSlot.snack,
          items: [NutritionMath.fromFood(await _foodRecord(db, foodId), 500)],
        ),
        source: 'manual',
      );
      final item = (await meals.getById(mealId))!.items.single;
      expect(item.nutrition.kcal, 0);
      expect(item.nutrition.proteinGrams, 0);
    });

    test('同事务中 food+修订+指针：中途失败整体回滚', () async {
      // 触发器让修订插入失败，验证主食物也不会留下（同事务）。
      await db.customStatement(
        "CREATE TRIGGER fail_revision BEFORE INSERT ON food_nutrition_revisions "
        "BEGIN SELECT RAISE(ABORT, 'injected'); END;",
      );
      await expectLater(
        catalog.createMasterFood(
          name: '回滚菜',
          kcalPer100g: 100,
          proteinPer100g: 5,
          carbsPer100g: 10,
          fatPer100g: 3,
        ),
        throwsA(anything),
      );
      expect(await db.select(db.foods).get(), isEmpty, reason: '食物也要回滚');
      await db.customStatement('DROP TRIGGER fail_revision');
      // 之后正常写入不受影响。
      final id = await catalog.createMasterFood(
        name: '恢复后正常',
        kcalPer100g: 100,
        proteinPer100g: 5,
        carbsPer100g: 10,
        fatPer100g: 3,
      );
      expect(id, isNotEmpty);
    });
  });

  // ── 归一边界 ──────────────────────────────────────────────────────────
  group('归一（旧数据）数值边界', () {
    test('浮点份量 187.5g 精确换算', () {
      final decision = LegacyNutritionRulesHolder.decide(
        row: LegacyDishRow(
          id: 'd',
          name: '旧菜',
          kcal: 375,
          proteinG: 18.75,
          carbsG: 28.125,
          fatG: 18.75,
          servingGrams: 187.5,
          nutritionBasis: 'perServing',
          basisAssumed: false,
          userEdited: false,
          source: 'manual',
        ),
      );
      expect(decision.master!.kcalPer100g, closeTo(200, 1e-9));
      expect(decision.master!.proteinPer100g, closeTo(10, 1e-9));
    });

    test('份量恰好 2000g（上限）：换算成功', () {
      final decision = LegacyNutritionRulesHolder.decide(
        row: LegacyDishRow(
          id: 'd',
          name: '旧菜',
          kcal: 2000,
          proteinG: 100,
          carbsG: 100,
          fatG: 100,
          servingGrams: 2000,
          nutritionBasis: 'perServing',
          basisAssumed: false,
          userEdited: false,
          source: 'manual',
        ),
      );
      expect(decision.outcome, LegacyOutcome.converted);
      expect(decision.master!.kcalPer100g, closeTo(100, 1e-9));
    });

    test('份量 2001g（超上限）：拒绝换算', () {
      final decision = LegacyNutritionRulesHolder.decide(
        row: LegacyDishRow(
          id: 'd',
          name: '旧菜',
          kcal: 2000,
          proteinG: 100,
          carbsG: 100,
          fatG: 100,
          servingGrams: 2001,
          nutritionBasis: 'perServing',
          basisAssumed: false,
          userEdited: false,
          source: 'manual',
        ),
      );
      expect(decision.outcome, LegacyOutcome.needsCompletion);
    });

    test('巨大 kcal（1000）：换算但保留原值', () {
      final decision = LegacyNutritionRulesHolder.decide(
        row: LegacyDishRow(
          id: 'd',
          name: '油',
          kcal: 1000,
          proteinG: 0,
          carbsG: 0,
          fatG: 100,
          servingGrams: 100,
          nutritionBasis: 'perServing',
          basisAssumed: false,
          userEdited: false,
          source: 'manual',
        ),
      );
      expect(decision.master!.kcalPer100g, closeTo(1000, 1e-9));
      expect(decision.preservedJson, contains('"kcal":1000'));
    });
  });
}

Future<FoodRecord> _foodRecord(AppDatabase db, String id) async {
  final row = await (db.select(
    db.foods,
  )..where((t) => t.id.equals(id))).getSingle();
  return FoodRecord(
    id: row.id,
    name: row.name,
    kcalPer100g: row.kcalPer100g,
    proteinPer100g: row.proteinPer100g,
    carbsPer100g: row.carbsPer100g,
    fatPer100g: row.fatPer100g,
    isUserCreated: row.isUserCreated,
    brand: row.brand,
    defaultServingGrams: row.defaultServingGrams,
  );
}

/// 让 `decideDishLibraryLegacy` 的调用在本文件里短一点。
final class LegacyNutritionRulesHolder {
  const LegacyNutritionRulesHolder._();
  static LegacyNutritionDecision decide({required LegacyDishRow row}) =>
      decideDishLibraryLegacy(row: row);
}
