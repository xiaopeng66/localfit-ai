import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/legacy_nutrition_rules.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';

/// 把旧数据按 [LegacyNutritionRules] 归一进统一主库（docs/67 §7.3、§7.4）。
///
/// **数据库升级与旧 `.lfb` 恢复共用这一份实现**：两边都只是"原始行适配器"，
/// 归一规则、台账、幂等键和事务边界完全相同，所以同一份旧夹具经两条入口
/// 得到的业务结果与待补全原因必须等价（A13）。
///
/// 纪律：
/// * 每一行旧实体都有台账结果（converted/reused/needs_completion/conflict），
///   不吞异常、不填零、不丢行；
/// * 同一 `(legacyKind, legacyId)` 重跑不会造第二条主食物，也不会二次换算
///   （每次都从**原始行**重算，而不是拿已换算值再除一次）；
/// * 旧行被改过（指纹变化）判冲突，不沿用"已迁移"跳过；
/// * 台账与主库写在同一个事务里，失败整体回滚。
final class LegacyNutritionConverter {
  const LegacyNutritionConverter({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 统一入口：基线修订 → 旧菜品库 → 旧食堂供应。
  ///
  /// **幂等可重入**：schema 升级跑一次后，任何"漏网"的旧供应（升级中断、
  /// 旧版本期间新分析的菜、恢复的旧包）都会在下次启动时被这里补上——
  /// 台账唯一键保证不会给同一旧键造第二条主食物。
  Future<LegacyConversionReport> run() async {
    return database.transaction(() async {
      final now = clock.nowUtc();
      final baseline = await _ensureBaselineRevisions(now);
      final dish = await _convertDishLibrary(now);
      final supply = await _convertSupplies(now);
      return LegacyConversionReport(
        baselineRevisions: baseline,
        dishLibraryRows: dish.rows,
        dishLibraryOutcomes: dish.outcomes,
        suppliesTotal: supply.rows,
        suppliesOutcomes: supply.outcomes,
        conflicts: [...dish.conflicts, ...supply.conflicts],
      );
    });
  }

  // ── A 类：既有主食物建立基线修订 ────────────────────────────────────────

  /// 给每一个四项齐全、但还没有生效修订的食物补一条基线修订，并把主表
  /// 四项写成这条修订的投影。已经完整的行不动（幂等）。
  Future<int> _ensureBaselineRevisions(DateTime now) async {
    final rows = await database.select(database.foods).get();
    var written = 0;
    for (final row in rows) {
      if (row.currentRevisionId != null) continue;
      if (!isCompleteNutrition(
        kcalPer100g: row.kcalPer100g,
        proteinPer100g: row.proteinPer100g,
        carbsPer100g: row.carbsPer100g,
        fatPer100g: row.fatPer100g,
      )) {
        // 不完整的历史食物：保留为"未生效资料"，不顶替完整修订，也不填零。
        continue;
      }
      final revisionId = await _insertRevision(
        foodId: row.id,
        now: now,
        kcal: row.kcalPer100g,
        protein: row.proteinPer100g,
        carbs: row.carbsPer100g,
        fat: row.fatPer100g,
        origin: 'baseline',
        isEstimated: row.state == 'estimated',
        basis: NutritionBasis.per100g,
        basisServingGrams: null,
        basisAssumed: false,
        rawValuesJson: null,
        conversionVersion: null,
      );
      await (database.update(
        database.foods,
      )..where((t) => t.id.equals(row.id))).write(
        FoodsCompanion(
          currentRevisionId: Value(revisionId),
          updatedAt: Value(now),
        ),
      );
      written++;
    }
    return written;
  }

  Future<String> _insertRevision({
    required String foodId,
    required DateTime now,
    required double kcal,
    required double protein,
    required double carbs,
    required double fat,
    required String origin,
    required bool isEstimated,
    required NutritionBasis basis,
    required double? basisServingGrams,
    required bool basisAssumed,
    required String? rawValuesJson,
    required String? conversionVersion,
    double? fiberPer100g,
    double? sodiumMgPer100g,
    double? vitaminDMcgPer100g,
  }) async {
    final nextNumber = await _nextRevisionNumber(foodId);
    final id = '$foodId-rev-$nextNumber';
    await database
        .into(database.foodNutritionRevisions)
        .insert(
          FoodNutritionRevisionsCompanion.insert(
            id: id,
            foodId: foodId,
            revisionNumber: nextNumber,
            kcalPer100g: Value(kcal),
            proteinGPer100g: Value(protein),
            carbsGPer100g: Value(carbs),
            fatGPer100g: Value(fat),
            createdAt: now,
            nutritionBasis: Value(basis.storedValue),
            basisServingGrams: Value(basisServingGrams),
            basisAssumed: Value(basisAssumed),
            origin: Value(origin),
            isEstimated: Value(isEstimated),
            fiberPer100g: Value(fiberPer100g),
            sodiumMgPer100g: Value(sodiumMgPer100g),
            vitaminDMcgPer100g: Value(vitaminDMcgPer100g),
            rawValuesJson: Value(rawValuesJson),
            conversionVersion: Value(conversionVersion),
          ),
        );
    return id;
  }

  Future<int> _nextRevisionNumber(String foodId) async {
    final row = await database
        .customSelect(
          'SELECT COALESCE(MAX(revision_number), 0) AS n '
          'FROM food_nutrition_revisions WHERE food_id = ?',
          variables: [Variable.withString(foodId)],
        )
        .getSingle();
    return (row.data['n'] as int? ?? 0) + 1;
  }

  // ── 旧菜品库 ────────────────────────────────────────────────────────────

  Future<_ConversionPass> _convertDishLibrary(DateTime now) async {
    final rows = await database.select(database.dishLibrary).get();
    final outcomes = <String, int>{};
    final conflicts = <String>[];

    // G 类：同来源多副本——先算出分组，再逐行裁决。
    final bySource = <String, List<DishLibraryEntry>>{};
    for (final row in rows) {
      final sourceId = row.sourceId;
      if (sourceId == null) continue;
      bySource
          .putIfAbsent('${row.sourceType}\u0000$sourceId', () => [])
          .add(row);
    }

    // H 类：同一供应多条已确认匹配。
    final confirmedCounts = <String, int>{};
    final confirmedRows = await database
        .select(database.menuItemFoodMatches)
        .get();
    for (final match in confirmedRows) {
      if (match.matchStatus != 'confirmed') continue;
      confirmedCounts.update(
        match.menuItemId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    for (final row in rows) {
      final decision = decideDishLibraryLegacy(
        row: LegacyDishRow(
          id: row.id,
          name: row.name,
          mealSlot: row.mealSlot,
          kcal: row.kcal,
          proteinG: row.proteinG,
          carbsG: row.carbsG,
          fatG: row.fatG,
          fiberG: row.fiberG,
          sodiumMg: row.sodiumMg,
          vitaminDMcg: row.vitaminDMcg,
          servingGrams: row.servingGrams,
          nutritionBasis: row.nutritionBasis,
          basisAssumed: row.basisAssumed,
          source: row.source,
          sourceType: row.sourceType,
          sourceId: row.sourceId,
          comment: row.comment,
          imagePath: row.imagePath,
          servingWindow: row.servingWindow,
          sourceUpdatedAt: row.sourceUpdatedAt,
          userEdited: row.userEdited,
        ),
        canteenEvidence: await _latestEvidenceFor(row.sourceId),
        duplicateSourceCopies:
            bySource['${row.sourceType}\u0000${row.sourceId}']?.length ?? 1,
        copiesAgree: _copiesAgree(
          bySource['${row.sourceType}\u0000${row.sourceId}'] ?? const [],
        ),
        confirmedMatchAmbiguous: (confirmedCounts[row.sourceId] ?? 0) > 1,
        sourceExists: row.sourceId == null
            ? true
            : await _menuItemExists(row.sourceId!),
      );
      final applied = await _apply(
        legacyKind: 'dish_library',
        legacyId: row.id,
        decision: decision,
        now: now,
        originalSource: row.source,
        originalServingGrams: row.servingGrams,
        basisAssumed: row.basisAssumed,
        userEdited: row.userEdited,
        menuItemId: row.sourceType == 'canteen' ? row.sourceId : null,
      );
      outcomes.update(
        applied.outcome.storedValue,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      if (applied.outcome == LegacyOutcome.conflict) {
        conflicts.add('dish_library:${row.id}');
      }
    }
    return _ConversionPass(
      rows: rows.length,
      outcomes: outcomes,
      conflicts: conflicts,
    );
  }

  bool _copiesAgree(List<DishLibraryEntry> copies) {
    if (copies.length <= 1) return true;
    final first = copies.first;
    for (final row in copies.skip(1)) {
      if (row.kcal != first.kcal ||
          row.proteinG != first.proteinG ||
          row.carbsG != first.carbsG ||
          row.fatG != first.fatG ||
          row.servingGrams != first.servingGrams ||
          row.basisAssumed != first.basisAssumed) {
        return false;
      }
    }
    return true;
  }

  Future<LegacyCanteenEvidence?> _latestEvidenceFor(String? menuItemId) async {
    if (menuItemId == null) return null;
    final row =
        await (database.select(database.menuItemNutritionEvidence)
              ..where((t) => t.menuItemId.equals(menuItemId))
              ..orderBy([
                (t) => OrderingTerm.desc(t.createdAt),
                (t) => OrderingTerm.desc(t.id),
              ])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return LegacyCanteenEvidence(
      origin: row.origin,
      grade: row.grade,
      kcalPer100g: row.kcalPer100g,
      proteinPer100g: row.proteinPer100g,
      carbsPer100g: row.carbsPer100g,
      fatPer100g: row.fatPer100g,
      kcalMin: row.kcalMin,
      kcalMax: row.kcalMax,
      sourceText: row.sourceText,
    );
  }

  Future<bool> _menuItemExists(String id) async {
    final row =
        await (database.select(database.menuItems)
              ..where((t) => t.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  // ── 旧食堂供应 ──────────────────────────────────────────────────────────

  Future<_ConversionPass> _convertSupplies(DateTime now) async {
    final rows = await (database.select(
      database.menuItems,
    )..where((t) => t.foodId.isNull())).get();
    final outcomes = <String, int>{};
    final conflicts = <String>[];

    for (final row in rows) {
      final decision = decideSupplyLegacy(
        menuItemId: row.id,
        displayName: row.displayName,
        evidence: await _latestEvidenceFor(row.id),
        itemHasConfirmedMatch: false,
      );
      final applied = await _apply(
        legacyKind: 'menu_item',
        legacyId: row.id,
        decision: decision,
        now: now,
        originalSource: row.itemStatus,
        originalServingGrams: row.servingGrams,
        basisAssumed: false,
        userEdited: false,
        menuItemId: row.id,
      );
      if (applied.foodId != null && applied.outcome != LegacyOutcome.conflict) {
        final hasExplicitServing =
            row.servingGrams != null &&
            row.servingGrams!.isFinite &&
            row.servingGrams! > 0 &&
            ServingGramsStatus.fromStored(row.servingGramsStatus) !=
                ServingGramsStatus.unknown &&
            ServingGramsSource.fromStored(row.servingGramsSource) !=
                ServingGramsSource.legacyUnknown;
        await (database.update(
          database.menuItems,
        )..where((t) => t.id.equals(row.id))).write(
          MenuItemsCompanion(
            foodId: Value(applied.foodId),
            servingGramsStatus: Value(
              hasExplicitServing
                  ? row.servingGramsStatus
                  : _legacyServingStatus(row.servingGrams).storedValue,
            ),
            servingGramsSource: Value(
              hasExplicitServing
                  ? row.servingGramsSource
                  : _legacyServingSource(row.servingGrams).storedValue,
            ),
            updatedAt: Value(now),
          ),
        );
      }
      outcomes.update(
        applied.outcome.storedValue,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      if (applied.outcome == LegacyOutcome.conflict) {
        conflicts.add('menu_item:${row.id}');
      }
    }
    return _ConversionPass(
      rows: rows.length,
      outcomes: outcomes,
      conflicts: conflicts,
    );
  }

  ServingGramsStatus _legacyServingStatus(double? grams) =>
      grams != null && grams > 0
      ? ServingGramsStatus.estimated
      : ServingGramsStatus.unknown;

  ServingGramsSource _legacyServingSource(double? grams) =>
      grams != null && grams > 0
      ? ServingGramsSource.legacyUnverified
      : ServingGramsSource.legacyUnknown;

  // ── 台账 + 主库写入 ─────────────────────────────────────────────────────

  /// 写一条台账并（必要时）建主食物。返回实际结论，不能把规则预判当成功。
  Future<_AppliedLegacyConversion> _apply({
    required String legacyKind,
    required String legacyId,
    required LegacyNutritionDecision decision,
    required DateTime now,
    required String? originalSource,
    required double? originalServingGrams,
    required bool basisAssumed,
    required bool userEdited,
    required String? menuItemId,
  }) async {
    final existing =
        await (database.select(database.legacyEntityMappings)
              ..where(
                (t) =>
                    t.legacyKind.equals(legacyKind) &
                    t.legacyId.equals(legacyId),
              )
              ..limit(1))
            .getSingleOrNull();

    // 幂等：同一指纹 + 同一规则版本 + 终态结论 → 不重做。
    if (existing != null &&
        existing.sourceFingerprint == decision.fingerprint &&
        existing.conversionVersion == LegacyNutritionRules.version &&
        (existing.outcome == LegacyOutcome.converted.storedValue ||
            existing.outcome == LegacyOutcome.reused.storedValue) &&
        decision.outcome != LegacyOutcome.conflict) {
      return _AppliedLegacyConversion(
        foodId: existing.foodId,
        outcome: LegacyOutcome.fromStored(existing.outcome),
      );
    }

    // 无主食物的供应补齐每 100g 证据是在完成待办，不是在覆盖已采纳的营养。
    // 也恢复旧版把这种补全误标成 source_changed 的台账；其他冲突仍须确认。
    final completingPendingSupply =
        legacyKind == 'menu_item' &&
        existing?.foodId == null &&
        decision.producesMaster &&
        (existing?.outcome == LegacyOutcome.needsCompletion.storedValue ||
            (existing?.outcome == LegacyOutcome.conflict.storedValue &&
                existing?.reasonCode == LegacyReasonCode.sourceChanged));
    final unresolvedSourceConflict =
        existing?.outcome == LegacyOutcome.conflict.storedValue &&
        existing?.reasonCode == LegacyReasonCode.sourceChanged;

    // 已采纳的旧行被改过：保留原关联及指纹，重启不能代替用户确认冲突。
    if (existing != null &&
        !completingPendingSupply &&
        (existing.sourceFingerprint != decision.fingerprint ||
            unresolvedSourceConflict)) {
      await (database.update(
        database.legacyEntityMappings,
      )..where((t) => t.id.equals(existing.id))).write(
        LegacyEntityMappingsCompanion(
          outcome: Value(LegacyOutcome.conflict.storedValue),
          reasonCode: const Value(LegacyReasonCode.sourceChanged),
          reasonText: Value(
            LegacyReasonCode.describe(LegacyReasonCode.sourceChanged),
          ),
          updatedAt: Value(now),
        ),
      );
      return _AppliedLegacyConversion(
        foodId: existing.foodId,
        outcome: LegacyOutcome.conflict,
      );
    }

    String? foodId;
    if (decision.producesMaster) {
      foodId = await _materializeMaster(
        existing: existing,
        decision: decision,
        now: now,
        legacyKind: legacyKind,
      );
    } else if (existing != null) {
      foodId = existing.foodId;
    }

    // 台账结论：可换算但用户手改 → 仍算 converted，note 里保留"用户值优先"。
    final outcome = decision.outcome.storedValue;
    final companion = LegacyEntityMappingsCompanion(
      legacyKind: Value(legacyKind),
      legacyId: Value(legacyId),
      sourceFingerprint: Value(decision.fingerprint),
      conversionVersion: const Value(LegacyNutritionRules.version),
      foodId: Value(foodId),
      menuItemId: Value(menuItemId ?? existing?.menuItemId),
      outcome: Value(outcome),
      reasonCode: Value(decision.reasonCode),
      reasonText: Value(decision.reasonText),
      originalBasis: Value(decision.originalBasis),
      originalServingGrams: Value(originalServingGrams),
      basisAssumed: Value(basisAssumed),
      originalSource: Value(originalSource),
      userEdited: Value(userEdited),
      preservedJson: Value(decision.preservedJson),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
    );
    if (existing == null) {
      await database
          .into(database.legacyEntityMappings)
          .insert(companion.copyWith(id: Value(idGenerator.next())));
    } else {
      await (database.update(
        database.legacyEntityMappings,
      )..where((t) => t.id.equals(existing.id))).write(companion);
    }
    return _AppliedLegacyConversion(foodId: foodId, outcome: decision.outcome);
  }

  Future<String> _materializeMaster({
    required LegacyEntityMappingRow? existing,
    required LegacyNutritionDecision decision,
    required DateTime now,
    required String legacyKind,
  }) async {
    final draft = decision.master!;
    final existingFoodId = existing?.foodId;

    // 已有主食物（规则升级重跑）：追加修订、切指针、同步投影。
    if (existingFoodId != null) {
      final food =
          await (database.select(database.foods)
                ..where((t) => t.id.equals(existingFoodId))
                ..limit(1))
              .getSingleOrNull();
      if (food != null) {
        final revisionId = await _insertRevision(
          foodId: food.id,
          now: now,
          kcal: draft.kcalPer100g,
          protein: draft.proteinPer100g,
          carbs: draft.carbsPer100g,
          fat: draft.fatPer100g,
          origin: draft.origin,
          isEstimated: draft.isEstimated,
          basis:
              NutritionBasis.tryParse(draft.nutritionBasis) ??
              NutritionBasis.perServing,
          basisServingGrams: draft.basisServingGrams,
          basisAssumed: draft.basisAssumed,
          rawValuesJson: draft.rawValuesJson,
          conversionVersion: LegacyNutritionRules.version,
          fiberPer100g: draft.fiberPer100g,
          sodiumMgPer100g: draft.sodiumMgPer100g,
          vitaminDMcgPer100g: draft.vitaminDMcgPer100g,
        );
        await _writeProjection(
          foodId: food.id,
          revisionId: revisionId,
          draft: draft,
          now: now,
        );
        return food.id;
      }
    }

    // 新主食物。
    final id = idGenerator.next();
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: id,
            name: draft.name,
            kcalPer100g: draft.kcalPer100g,
            proteinPer100g: draft.proteinPer100g,
            carbsPer100g: draft.carbsPer100g,
            fatPer100g: draft.fatPer100g,
            source: draft.origin,
            isUserCreated: Value(true),
            createdAt: now,
            updatedAt: now,
            state: Value(draft.isEstimated ? 'estimated' : 'user_created'),
            cookingNote: Value(draft.cookingNote),
          ),
        );
    final revisionId = await _insertRevision(
      foodId: id,
      now: now,
      kcal: draft.kcalPer100g,
      protein: draft.proteinPer100g,
      carbs: draft.carbsPer100g,
      fat: draft.fatPer100g,
      origin: draft.origin,
      isEstimated: draft.isEstimated,
      basis:
          NutritionBasis.tryParse(draft.nutritionBasis) ??
          NutritionBasis.perServing,
      basisServingGrams: draft.basisServingGrams,
      basisAssumed: draft.basisAssumed,
      rawValuesJson: draft.rawValuesJson,
      conversionVersion: LegacyNutritionRules.version,
      fiberPer100g: draft.fiberPer100g,
      sodiumMgPer100g: draft.sodiumMgPer100g,
      vitaminDMcgPer100g: draft.vitaminDMcgPer100g,
    );
    await _writeProjection(
      foodId: id,
      revisionId: revisionId,
      draft: draft,
      now: now,
    );

    // 变体关系：用户手改过的旧值挂在同名共享条目下，不污染共享营养。
    if (decision.requiresVariant) {
      final parent =
          await (database.select(database.foods)
                ..where(
                  (t) =>
                      t.name.equals(draft.name) &
                      t.id.isNotValue(id) &
                      t.archivedAt.isNull(),
                )
                ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      if (parent != null) {
        await (database.update(database.foods)..where((t) => t.id.equals(id)))
            .write(FoodsCompanion(variantOfFoodId: Value(parent.id)));
      }
    }
    return id;
  }

  Future<void> _writeProjection({
    required String foodId,
    required String revisionId,
    required LegacyMasterDraft draft,
    required DateTime now,
  }) async {
    // 主表四项是生效修订的投影：同一事务里一起写，不能各自漂移。
    await (database.update(
      database.foods,
    )..where((t) => t.id.equals(foodId))).write(
      FoodsCompanion(
        currentRevisionId: Value(revisionId),
        kcalPer100g: Value(draft.kcalPer100g),
        proteinPer100g: Value(draft.proteinPer100g),
        carbsPer100g: Value(draft.carbsPer100g),
        fatPer100g: Value(draft.fatPer100g),
        updatedAt: Value(now),
      ),
    );
  }
}

final class _AppliedLegacyConversion {
  const _AppliedLegacyConversion({required this.foodId, required this.outcome});

  final String? foodId;
  final LegacyOutcome outcome;
}

final class _ConversionPass {
  const _ConversionPass({
    required this.rows,
    required this.outcomes,
    required this.conflicts,
  });

  final int rows;
  final Map<String, int> outcomes;
  final List<String> conflicts;
}

/// 一次归一运行的报告（也是逐条对账的输入）。
final class LegacyConversionReport {
  const LegacyConversionReport({
    required this.baselineRevisions,
    required this.dishLibraryRows,
    required this.dishLibraryOutcomes,
    required this.suppliesTotal,
    required this.suppliesOutcomes,
    required this.conflicts,
  });

  final int baselineRevisions;
  final int dishLibraryRows;
  final Map<String, int> dishLibraryOutcomes;
  final int suppliesTotal;
  final Map<String, int> suppliesOutcomes;
  final List<String> conflicts;

  int get converted =>
      (dishLibraryOutcomes[LegacyOutcome.converted.storedValue] ?? 0) +
      (dishLibraryOutcomes[LegacyOutcome.reused.storedValue] ?? 0) +
      (suppliesOutcomes[LegacyOutcome.converted.storedValue] ?? 0) +
      (suppliesOutcomes[LegacyOutcome.reused.storedValue] ?? 0);

  int get needsCompletion =>
      (dishLibraryOutcomes[LegacyOutcome.needsCompletion.storedValue] ?? 0) +
      (suppliesOutcomes[LegacyOutcome.needsCompletion.storedValue] ?? 0);

  /// 每一条旧实体都必须有结果：总数 == 三个终态之和。
  bool get reconciles {
    final dishTotal = dishLibraryOutcomes.values.fold(0, (a, b) => a + b);
    final supplyTotal = suppliesOutcomes.values.fold(0, (a, b) => a + b);
    return dishTotal == dishLibraryRows && supplyTotal == suppliesTotal;
  }

  bool get isClean => reconciles && conflicts.isEmpty;

  Map<String, Object?> toJson() => {
    'baseline_revisions': baselineRevisions,
    'dish_library_rows': dishLibraryRows,
    'dish_library_outcomes': dishLibraryOutcomes,
    'supplies_total': suppliesTotal,
    'supplies_outcomes': suppliesOutcomes,
    'conflicts': conflicts,
    'reconciles': reconciles,
  };

  @override
  String toString() => jsonEncode(toJson());
}
