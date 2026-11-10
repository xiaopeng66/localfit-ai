import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/legacy_nutrition_rules.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/data/database/legacy_nutrition_converter.dart';
import 'package:localfit_ai/data/database/nutrition_inventory.dart';
import 'package:localfit_ai/features/backup/application/backup_table_registry.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';

/// 旧数据归一与对账（docs/67 §7）。A–I 分类矩阵逐类给结果，
/// 每条用例都是真的写库、真的读回来，不看源码字符串。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 每个用例各开一个内存库做"升级 vs 恢复"对比，drift 的多库告警与本题无关。
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final now = DateTime.utc(2026, 11, 9, 6);

  group('纯规则层 A–I 矩阵', () {
    LegacyDishRow dish({
      String id = 'd1',
      String name = '宫保鸡丁',
      double kcal = 400,
      double protein = 20,
      double carbs = 30,
      double fat = 20,
      double? servingGrams,
      bool basisAssumed = false,
      bool userEdited = false,
      String source = 'manual',
      String? sourceType,
      String? sourceId,
      String basis = 'perServing',
    }) => LegacyDishRow(
      id: id,
      name: name,
      kcal: kcal,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      servingGrams: servingGrams,
      nutritionBasis: basis,
      basisAssumed: basisAssumed,
      userEdited: userEdited,
      source: source,
      sourceType: sourceType,
      sourceId: sourceId,
    );

    test('A 类：既有完整每 100g 主食物保留原 ID（迁移不重建）', () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'food-a',
              name: '米饭',
              kcalPer100g: 116,
              proteinPer100g: 2.6,
              carbsPer100g: 25.9,
              fatPer100g: 0.3,
              source: 'bundled',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await LegacyNutritionConverter(
        database: database,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      ).run();
      final food = await (database.select(
        database.foods,
      )..where((t) => t.id.equals('food-a'))).getSingle();
      expect(food.id, 'food-a');
      expect(food.currentRevisionId, isNotNull);
      final revision = await (database.select(
        database.foodNutritionRevisions,
      )..where((t) => t.id.equals(food.currentRevisionId!))).getSingle();
      expect(revision.origin, 'baseline');
      expect(revision.kcalPer100g, 116);
    });

    test('B 类：明确原每 100g 的旧条目原值归一', () {
      final decision = decideDishLibraryLegacy(
        row: dish(basis: 'per100g', kcal: 142),
      );
      expect(decision.outcome, LegacyOutcome.converted);
      expect(decision.master!.kcalPer100g, 142);
      expect(decision.reasonCode, LegacyReasonCode.explicitPer100g);
    });

    test('C 类：每份营养 + 可信每份克数 → 按公式换算', () {
      final decision = decideDishLibraryLegacy(
        row: dish(kcal: 400, servingGrams: 250),
      );
      expect(decision.outcome, LegacyOutcome.converted);
      expect(decision.master!.kcalPer100g, closeTo(160, 1e-9));
      expect(decision.master!.basisServingGrams, 250);
      expect(decision.master!.basisAssumed, isFalse);
      expect(
        decision.preservedJson,
        contains('"kcal":400'),
        reason: '换算前的原值必须留在保全资料里',
      );
    });

    test('D 类：食堂有每 100g 证据时用证据，不用旧每份副本倒推', () {
      final decision = decideDishLibraryLegacy(
        row: dish(
          kcal: 999,
          servingGrams: 100,
          sourceType: 'canteen',
          sourceId: 'menu-1',
        ),
        canteenEvidence: const LegacyCanteenEvidence(
          origin: 'ai_estimate',
          grade: 'B',
          kcalPer100g: 150,
          proteinPer100g: 12,
          carbsPer100g: 8,
          fatPer100g: 7,
        ),
      );
      expect(decision.outcome, LegacyOutcome.reused);
      expect(decision.master!.kcalPer100g, 150);
    });

    test('E 类：历史假设 100g 不换算、不吞、不填零', () {
      final decision = decideDishLibraryLegacy(
        row: dish(kcal: 400, servingGrams: 100, basisAssumed: true),
      );
      expect(decision.outcome, LegacyOutcome.needsCompletion);
      expect(decision.master, isNull);
      expect(decision.reasonCode, LegacyReasonCode.assumedServing);
      expect(decision.preservedJson, contains('"basisAssumed":true'));
    });

    test('F 类：用户手改可换算时保留用户值并要求变体', () {
      final decision = decideDishLibraryLegacy(
        row: dish(kcal: 520, servingGrams: 260, userEdited: true),
      );
      expect(decision.outcome, LegacyOutcome.converted);
      expect(decision.requiresVariant, isTrue);
      expect(decision.master!.kcalPer100g, closeTo(200, 1e-9));
    });

    test('G 类：同来源副本不一致 → 冲突，不按来源键强合并', () {
      final decision = decideDishLibraryLegacy(
        row: dish(kcal: 400, servingGrams: 250),
        duplicateSourceCopies: 2,
        copiesAgree: false,
      );
      expect(decision.outcome, LegacyOutcome.conflict);
      expect(decision.reasonCode, LegacyReasonCode.duplicateSourceDivergent);
    });

    test('H 类：多条已确认匹配 → 冲突，不猜第一条', () {
      final decision = decideDishLibraryLegacy(
        row: dish(kcal: 400, servingGrams: 250),
        confirmedMatchAmbiguous: true,
      );
      expect(decision.outcome, LegacyOutcome.conflict);
      expect(decision.reasonCode, LegacyReasonCode.duplicateConfirmedMatch);
    });

    test('I 类：非法值不进入可计算主库', () {
      final decision = decideDishLibraryLegacy(
        row: dish(kcal: double.nan, servingGrams: 250),
      );
      expect(decision.outcome, LegacyOutcome.needsCompletion);
      expect(decision.reasonCode, LegacyReasonCode.invalidValue);
    });

    test('I 类：供应只有区间没有代表值 → 待补全，不取中点', () {
      final decision = decideSupplyLegacy(
        menuItemId: 'menu-2',
        displayName: '盖浇饭',
        itemHasConfirmedMatch: false,
        evidence: const LegacyCanteenEvidence(
          origin: 'ai_estimate',
          grade: 'C',
          kcalMin: 500,
          kcalMax: 700,
        ),
      );
      expect(decision.outcome, LegacyOutcome.needsCompletion);
      expect(decision.reasonCode, LegacyReasonCode.rangeOnly);
      expect(decision.master, isNull);
    });

    test('指纹只看内容：同样的行指纹相同，改一个数就变', () {
      final a = decideDishLibraryLegacy(
        row: dish(kcal: 400, servingGrams: 250),
      );
      final b = decideDishLibraryLegacy(
        row: dish(kcal: 400, servingGrams: 250),
      );
      final c = decideDishLibraryLegacy(
        row: dish(kcal: 401, servingGrams: 250),
      );
      expect(a.fingerprint, b.fingerprint);
      expect(c.fingerprint, isNot(a.fingerprint));
    });
  });

  group('库内归一与对账', () {
    late AppDatabase database;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => database.close());

    Future<LegacyConversionReport> run() => LegacyNutritionConverter(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: FixedAppClock(now),
    ).run();

    test('A10 旧每份 400 千卡 + 可信 250g → 160 千卡/100g，原值与依据可查', () async {
      final dishId = await _seedLegacyDish(
        database,
        kcal: 400,
        proteinG: 20,
        carbsG: 30,
        fatG: 20,
        servingGrams: 250,
      );
      final report = await run();
      expect(report.reconciles, isTrue);
      expect(report.conflicts, isEmpty);

      final mapping = await _mapping(database, 'dish_library', dishId);
      expect(mapping.outcome, LegacyOutcome.converted.storedValue);
      expect(mapping.originalBasis, 'perServing');
      expect(mapping.originalServingGrams, 250);
      expect(mapping.preservedJson, contains('"kcal":400'));

      final food = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(mapping.foodId!))).getSingle();
      expect(food.kcalPer100g, closeTo(160, 1e-9));
      expect(food.name, '宫保鸡丁');

      final revision = await (database.select(
        database.foodNutritionRevisions,
      )..where((t) => t.id.equals(food.currentRevisionId!))).getSingle();
      expect(revision.basisServingGrams, 250);
      expect(revision.nutritionBasis, 'perServing');
      expect(
        revision.conversionVersion,
        LegacyNutritionRules.version,
        reason: '转换规则版本必须落库，规则升级才可重裁决',
      );
    });

    test('A11 旧每份 400 千卡 + 假设 100g → 不变成 400/100g，可查原因', () async {
      final dishId = await _seedLegacyDish(
        database,
        kcal: 400,
        servingGrams: 100,
        basisAssumed: true,
      );
      await run();
      final mapping = await _mapping(database, 'dish_library', dishId);
      expect(mapping.outcome, LegacyOutcome.needsCompletion.storedValue);
      expect(mapping.reasonCode, LegacyReasonCode.assumedServing);
      expect(mapping.foodId, isNull);
      expect(
        await database.select(database.foods).get(),
        isEmpty,
        reason: '不能凭空造一条 400 千卡/100g 的主食物',
      );
      expect(mapping.preservedJson, contains('"kcal":400'));
    });

    test('A12 同来源副本含手改：用户值不被覆盖，且重跑不增主条目', () async {
      final sharedId = await _seedLegacyDish(
        database,
        id: 'd-shared',
        kcal: 400,
        servingGrams: 200,
        sourceType: 'manual',
        sourceId: 'recipe-1',
      );
      final userCopyId = await _seedLegacyDish(
        database,
        id: 'd-user',
        kcal: 500,
        servingGrams: 200,
        sourceType: 'manual',
        sourceId: 'recipe-2',
        userEdited: true,
      );
      await run();
      final shared = await _mapping(database, 'dish_library', sharedId);
      final userCopy = await _mapping(database, 'dish_library', userCopyId);
      expect(shared.foodId, isNotNull);
      expect(userCopy.foodId, isNotNull);
      expect(userCopy.userEdited, isTrue);

      final userFood = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(userCopy.foodId!))).getSingle();
      expect(
        userFood.kcalPer100g,
        closeTo(250, 1e-9),
        reason: '用户手改的值优先，不被同步/迁移覆盖',
      );

      final foodCountBefore =
          (await database.select(database.foods).get()).length;
      await run();
      final foodCountAfter =
          (await database.select(database.foods).get()).length;
      expect(foodCountAfter, foodCountBefore, reason: '重跑不能增主条目');

      final revisionCount =
          (await database.select(database.foodNutritionRevisions).get()).length;
      await run();
      expect(
        (await database.select(database.foodNutritionRevisions).get()).length,
        revisionCount,
        reason: '同键同版本重跑不能追加修订',
      );
    });

    test('旧行被改过 → 冲突，不沿用"已迁移"静默跳过，也不造第二条主食物', () async {
      final dishId = await _seedLegacyDish(
        database,
        kcal: 400,
        servingGrams: 250,
      );
      await run();
      final first = await _mapping(database, 'dish_library', dishId);
      expect(first.outcome, LegacyOutcome.converted.storedValue);
      final foodCountBefore =
          (await database.select(database.foods).get()).length;

      await (database.update(database.dishLibrary)
            ..where((t) => t.id.equals(dishId)))
          .write(const DishLibraryCompanion(kcal: drift.Value(450)));
      final report = await run();

      final second = await _mapping(database, 'dish_library', dishId);
      expect(second.outcome, LegacyOutcome.conflict.storedValue);
      expect(report.isClean, isFalse, reason: '报告必须反映实际落库冲突');
      expect(report.dishLibraryOutcomes, {'conflict': 1});
      expect(report.conflicts, ['dish_library:$dishId']);
      expect(second.reasonCode, LegacyReasonCode.sourceChanged);
      expect(second.foodId, first.foodId, reason: '冲突时保留原关联，不另起一条');
      expect(
        (await database.select(database.foods).get()).length,
        foodCountBefore,
      );
    });

    test('已迁移条目 source_changed 冲突重跑不覆盖主库或变成成功', () async {
      final dishId = await _seedLegacyDish(
        database,
        kcal: 400,
        servingGrams: 250,
      );
      await run();
      final first = await _mapping(database, 'dish_library', dishId);
      final revisionCount =
          (await database.select(database.foodNutritionRevisions).get()).length;
      await (database.update(database.dishLibrary)
            ..where((t) => t.id.equals(dishId)))
          .write(const DishLibraryCompanion(kcal: drift.Value(450)));
      await run();
      final report = await run();
      final mapping = await _mapping(database, 'dish_library', dishId);
      final food = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(first.foodId!))).getSingle();
      expect(food.kcalPer100g, 160, reason: '重启不能替用户接受旧行修改');
      expect(mapping.outcome, 'conflict');
      expect(report.isClean, isFalse);
      expect(report.dishLibraryOutcomes, {'conflict': 1});
      expect(
        (await database.select(database.foodNutritionRevisions).get()).length,
        revisionCount,
      );
    });

    test('供应的每 100g 证据直接建主食物并回填权威链接', () async {
      final seeded = await _seedVenueWindow(database, now);
      final supplyId = await _seedSupply(
        database,
        windowId: seeded.windowId,
        displayName: '番茄牛腩',
      );
      await _seedEvidence(database, supplyId, kcal: 130);

      await run();
      final supply = await (database.select(
        database.menuItems,
      )..where((t) => t.id.equals(supplyId))).getSingle();
      expect(supply.foodId, isNotNull);
      final food = await (database.select(
        database.foods,
      )..where((t) => t.id.equals(supply.foodId!))).getSingle();
      expect(food.kcalPer100g, 130);
      expect(supply.servingGramsStatus, 'unknown');
      expect(
        supply.servingGramsSource,
        'legacy_unknown',
        reason: '没填份量的供应不能因为归一就变成"知道份量"',
      );
    });

    test('迁移不改历史餐快照', () async {
      await _seedMeal(database, now);
      final before = await NutritionInventoryReader.read(database);
      await run();
      final after = await NutritionInventoryReader.read(database);
      expect(after.mealSnapshotDigest, before.mealSnapshotDigest);
      expect(after.mealItemCount, before.mealItemCount);
      expect(after.mealCount, before.mealCount);
    });

    test('对账：每一条旧键都有结果，漏一条就红', () async {
      await _seedLegacyDish(database, id: 'd1', kcal: 400, servingGrams: 250);
      await _seedLegacyDish(database, id: 'd2', kcal: 400, basisAssumed: true);
      final seeded = await _seedVenueWindow(database, now);
      final unanalyzedId = await _seedSupply(
        database,
        windowId: seeded.windowId,
        displayName: '未分析菜',
      );
      final before = await NutritionInventoryReader.read(database);
      expect(before.everyLegacyKeyAccounted, isFalse, reason: '迁移前台账是空的');

      final report = await run();
      expect(report.reconciles, isTrue);
      final after = await NutritionInventoryReader.read(database);
      expect(
        after.everyLegacyKeyAccounted,
        isTrue,
        reason: '漏掉的键：${after.unaccountedLegacyKeys}',
      );
      expect(after.legacyKeys.toSet(), after.ledgerKeys.toSet());
      expect(after.pendingCompletionKeys, contains('dish_library:d2'));
      expect(after.pendingCompletionKeys, contains('menu_item:$unanalyzedId'));
    });

    test('转换中途抛错 → 整体回滚，不留半条主食物/台账', () async {
      final dishId = await _seedLegacyDish(
        database,
        kcal: 400,
        servingGrams: 250,
      );
      // 在写主食物的那一刻失败——模拟磁盘满/约束冲突这类中途故障。
      await database.customStatement(
        "CREATE TRIGGER fail_foods_insert BEFORE INSERT ON foods "
        "BEGIN SELECT RAISE(ABORT, 'injected'); END;",
      );

      await expectLater(run(), throwsA(anything));

      expect(
        await database.select(database.foods).get(),
        isEmpty,
        reason: '失败时不能留下半条主食物',
      );
      expect(
        await database.select(database.foodNutritionRevisions).get(),
        isEmpty,
        reason: '修订也要跟着回滚',
      );
      expect(
        await database.select(database.legacyEntityMappings).get(),
        isEmpty,
        reason: '台账不能先落一条"已转换"再失败',
      );
      // 移除故障后重跑能正常完成——回滚没有把库弄坏。
      await database.customStatement('DROP TRIGGER fail_foods_insert');
      final report = await run();
      expect(report.conflicts, isEmpty);
      final mapping = await _mapping(database, 'dish_library', dishId);
      expect(mapping.outcome, LegacyOutcome.converted.storedValue);
    });
  });

  group('A13 升级与旧 .lfb 恢复等价', () {
    test('同一旧夹具经"直接归一"和"备份恢复"得到相同业务结果', () async {
      final source = AppDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      final seeded = await _seedVenueWindow(source, now);
      await _seedLegacyDish(
        source,
        id: 'd-convert',
        kcal: 400,
        servingGrams: 250,
      );
      await _seedLegacyDish(
        source,
        id: 'd-pending',
        kcal: 400,
        basisAssumed: true,
      );
      final supplyId = await _seedSupply(
        source,
        windowId: seeded.windowId,
        displayName: '番茄牛腩',
      );
      await _seedEvidence(source, supplyId, kcal: 130);
      await _seedMeal(source, now);

      // ① 直接归一（等价于数据库升级路径的转换段）。
      final direct = AppDatabase(NativeDatabase.memory());
      addTearDown(direct.close);
      await _copyPayload(source, direct);
      await LegacyNutritionConverter(
        database: direct,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      ).run();

      // ② 备份 → 恢复到空库（等价于旧 .lfb 恢复路径）。
      final payload = await ExportLocalFitData(source).exportJson();
      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await RestoreLocalFitData(
        restored,
        clock: FixedAppClock(now),
      ).restore(payload);

      final directSummary = await _businessSummary(direct);
      final restoredSummary = await _businessSummary(restored);
      expect(restoredSummary, directSummary);

      // 具体断言，避免"两个都空"也算相等。
      expect(directSummary['foods'], 2);
      expect(
        directSummary['pending'],
        contains('dish_library:d-pending=assumed_serving'),
      );
      expect(
        directSummary['converted'],
        containsAll(<String>['dish_library:d-convert', 'menu_item:$supplyId']),
      );
    });

    test('新包已带台账：恢复不重复归一', () async {
      final source = AppDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      await _seedLegacyDish(source, id: 'd1', kcal: 400, servingGrams: 250);
      await LegacyNutritionConverter(
        database: source,
        idGenerator: const UuidV7Generator(),
        clock: FixedAppClock(now),
      ).run();
      final foodsBefore = (await source.select(source.foods).get()).length;

      final payload = await ExportLocalFitData(source).exportJson();
      final restored = AppDatabase(NativeDatabase.memory());
      addTearDown(restored.close);
      await RestoreLocalFitData(
        restored,
        clock: FixedAppClock(now),
      ).restore(payload);

      expect((await restored.select(restored.foods).get()).length, foodsBefore);
    });
  });
}

// ── 夹具 ──────────────────────────────────────────────────────────────────

Future<String> _seedLegacyDish(
  AppDatabase database, {
  String? id,
  String name = '宫保鸡丁',
  double kcal = 400,
  double proteinG = 20,
  double carbsG = 30,
  double fatG = 20,
  double? servingGrams,
  bool basisAssumed = false,
  bool userEdited = false,
  String source = 'manual',
  String? sourceType,
  String? sourceId,
}) async {
  final dishId = id ?? 'dish-${DateTime.now().microsecondsSinceEpoch}';
  await database
      .into(database.dishLibrary)
      .insert(
        DishLibraryCompanion.insert(
          id: dishId,
          name: name,
          mealSlot: 'lunch',
          kcal: kcal,
          proteinG: proteinG,
          carbsG: carbsG,
          fatG: fatG,
          source: source,
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
          servingGrams: drift.Value(servingGrams),
          basisAssumed: drift.Value(basisAssumed),
          userEdited: drift.Value(userEdited),
          sourceType: drift.Value(sourceType),
          sourceId: drift.Value(sourceId),
        ),
      );
  return dishId;
}

Future<({String venueId, String windowId, String snapshotId})> _seedVenueWindow(
  AppDatabase database,
  DateTime now,
) async {
  await database
      .into(database.campusProfiles)
      .insert(
        CampusProfilesCompanion.insert(
          id: 'campus-1',
          name: '主校区',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.venues)
      .insert(
        VenuesCompanion.insert(
          id: 'venue-1',
          campusId: 'campus-1',
          name: '香园',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.menuSources)
      .insert(
        MenuSourcesCompanion.insert(
          id: 'source-1',
          venueId: 'venue-1',
          sourceType: 'manual',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.menuSnapshots)
      .insert(
        MenuSnapshotsCompanion.insert(
          id: 'snapshot-1',
          sourceId: 'source-1',
          venueId: 'venue-1',
          businessDate: '2026-11-09',
          contentHash: 'hash-1',
          status: const drift.Value('catalog'),
          importedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.menuServices)
      .insert(
        MenuServicesCompanion.insert(
          id: 'window-1',
          snapshotId: 'snapshot-1',
          name: '一窗口',
          openTime: '11:00',
          closeTime: '13:30',
          createdAt: now,
          updatedAt: now,
        ),
      );
  return (venueId: 'venue-1', windowId: 'window-1', snapshotId: 'snapshot-1');
}

Future<String> _seedSupply(
  AppDatabase database, {
  required String windowId,
  required String displayName,
}) async {
  final id = 'supply-${displayName.hashCode}';
  await database
      .into(database.menuItems)
      .insert(
        MenuItemsCompanion.insert(
          id: id,
          serviceId: windowId,
          displayName: displayName,
          createdAt: DateTime.utc(2026, 10, 1),
          updatedAt: DateTime.utc(2026, 10, 1),
        ),
      );
  return id;
}

Future<void> _seedEvidence(
  AppDatabase database,
  String menuItemId, {
  required double kcal,
}) async {
  await database
      .into(database.menuItemNutritionEvidence)
      .insert(
        MenuItemNutritionEvidenceCompanion.insert(
          id: 'evidence-$menuItemId',
          menuItemId: menuItemId,
          grade: 'B',
          origin: 'ai_estimate',
          createdAt: DateTime.utc(2026, 10, 2),
          updatedAt: DateTime.utc(2026, 10, 2),
          kcalPer100g: drift.Value(kcal),
          proteinPer100g: const drift.Value(12),
          carbsPer100g: const drift.Value(8),
          fatPer100g: const drift.Value(7),
        ),
      );
}

Future<void> _seedMeal(AppDatabase database, DateTime now) async {
  await database
      .into(database.meals)
      .insert(
        MealsCompanion.insert(
          id: 'meal-1',
          localDate: '2026-11-08',
          slot: 'lunch',
          eatenAt: now,
          source: 'manual',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.mealItems)
      .insert(
        MealItemsCompanion.insert(
          id: 'item-1',
          mealId: 'meal-1',
          foodNameSnapshot: '旧菜',
          grams: 220,
          kcalSnapshot: 480,
          proteinSnapshot: 22,
          carbsSnapshot: 40,
          fatSnapshot: 24,
          createdAt: now,
          updatedAt: now,
        ),
      );
}

Future<LegacyEntityMappingRow> _mapping(
  AppDatabase database,
  String kind,
  String id,
) => (database.select(
  database.legacyEntityMappings,
)..where((t) => t.legacyKind.equals(kind) & t.legacyId.equals(id))).getSingle();

/// 把源库的**数据**拷进目标库（表结构已由 createAll 建好）。
Future<void> _copyPayload(AppDatabase source, AppDatabase target) async {
  final payload = await ExportLocalFitData(source).exportJson();
  final document = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
  final tables = document['tables'] as Map<String, dynamic>;
  await target.transaction(() async {
    for (final spec in LocalFitBackupTables(target).all) {
      final rows = tables[spec.key];
      if (rows is! List) continue;
      for (final row in rows) {
        await spec.write(target, row as Map<String, dynamic>);
      }
    }
  });
}

/// 归一后的业务摘要：用于比较"升级"和"恢复"两条入口是否等价。
Future<Map<String, Object?>> _businessSummary(AppDatabase database) async {
  final foods = await database.select(database.foods).get();
  final mappings = await database.select(database.legacyEntityMappings).get();
  final meals = await database.select(database.meals).get();
  final items = await database.select(database.mealItems).get();
  return {
    'foods': foods.length,
    'food_values': (<String>[
      for (final food in foods)
        '${food.name}:${food.kcalPer100g.toStringAsFixed(4)}',
    ]..sort()),
    'outcomes': (<String>[
      for (final mapping in mappings)
        '${mapping.legacyKind}:${mapping.legacyId}=${mapping.outcome}',
    ]..sort()),
    'pending': (<String>[
      for (final mapping in mappings)
        if (mapping.reasonCode != null)
          '${mapping.legacyKind}:${mapping.legacyId}=${mapping.reasonCode}',
    ]..sort()),
    'converted': (<String>[
      for (final mapping in mappings)
        if (mapping.outcome == LegacyOutcome.converted.storedValue ||
            mapping.outcome == LegacyOutcome.reused.storedValue)
          '${mapping.legacyKind}:${mapping.legacyId}',
    ]..sort()),
    'meal_digest': NutritionInventoryReader.mealSnapshotDigestOf(meals, items),
  };
}
