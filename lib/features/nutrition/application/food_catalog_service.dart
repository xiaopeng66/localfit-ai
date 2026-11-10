import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';

/// 统一主库的**唯一写入服务**（docs/67 §5、D12）。
///
/// 手动界面、AI 命令、食堂目录和推荐应用都必须经过这里；任何地方再自己
/// `into(foods).insert()` 或把营养拷进另一张表，就会出现第二套当前事实。
///
/// 三种意图分开（D07/§5.5）：
/// * [createMasterFood] — 只存库；
/// * [createSupply] — 只挂窗（可引用已有主食物，也可在同一事务里新建）；
/// * [recordMeal] — 只记餐。
/// 组合意图由调用方按顺序组合；每一段自己的失败各自回滚，不留半成品。
///
/// 所有写入用 [requestKey] 做业务级幂等：同一次"建库+挂窗+记餐"重试
/// 不会写第二遍（服务层再挡一次，不只靠 UI 禁用按钮）。
final class FoodCatalogService {
  FoodCatalogService({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 幂等请求键 → 已产生的结果（进程内）。跨重启的重复提交由业务唯一键
  /// 兜底：供应看窗口+展示名，记餐看日期+档位去重。
  final Map<String, String> _requestResults = {};

  // ── 1. 存库 ─────────────────────────────────────────────────────────────

  /// 建一条主食物（每 100g），同时写第一条**生效修订**并同步主表投影。
  ///
  /// 四项必须齐全合法：缺项应先保存为分析草稿/待分析供应，不插入一行假零
  /// 食物（docs/67 §3.1）。
  Future<String> createMasterFood({
    required String name,
    required double kcalPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    String? brand,
    String? cookingNote,
    String? category,
    double? fiberPer100g,
    double? sodiumMgPer100g,
    double? vitaminDMcgPer100g,
    double? defaultServingGrams,
    String origin = 'user_input',
    bool isEstimated = false,
    String? variantOfFoodId,
    List<String>? aliases,
    String? requestKey,

    /// 这一组每 100g 值是从什么口径换算来的（docs/67 §3.2）。
    /// 用户直接填每 100g 时是 `per100g` + null 克数；由"每份"录入时记录
    /// 原口径与换算用的每份克数，谁都改不掉这段来历。
    NutritionBasis basis = NutritionBasis.per100g,
    double? basisServingGrams,
    bool basisAssumed = false,
    String? originalRawValuesJson,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const CatalogWriteException('食物名称不能为空。');
    }
    _requireCompleteNutrition(
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
      name: trimmed,
    );
    _requireServingGrams(defaultServingGrams, allowNull: true);

    final cached = _cachedRequest(requestKey);
    if (cached != null) return cached;

    final now = clock.nowUtc();
    final id = idGenerator.next();
    await database.transaction(() async {
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: id,
              name: trimmed,
              brand: Value(
                brand?.trim().isEmpty ?? true ? null : brand!.trim(),
              ),
              defaultServingGrams: Value(defaultServingGrams),
              kcalPer100g: kcalPer100g,
              proteinPer100g: proteinPer100g,
              carbsPer100g: carbsPer100g,
              fatPer100g: fatPer100g,
              source: origin,
              isUserCreated: const Value(true),
              createdAt: now,
              updatedAt: now,
              state: Value(isEstimated ? 'estimated' : 'user_created'),
              category: Value(category),
              cookingNote: Value(
                cookingNote?.trim().isEmpty ?? true
                    ? null
                    : cookingNote!.trim(),
              ),
              variantOfFoodId: Value(variantOfFoodId),
            ),
          );
      await _appendRevision(
        foodId: id,
        now: now,
        kcalPer100g: kcalPer100g,
        proteinPer100g: proteinPer100g,
        carbsPer100g: carbsPer100g,
        fatPer100g: fatPer100g,
        fiberPer100g: fiberPer100g,
        sodiumMgPer100g: sodiumMgPer100g,
        vitaminDMcgPer100g: vitaminDMcgPer100g,
        origin: origin,
        isEstimated: isEstimated,
        basis: basis,
        basisServingGrams: basisServingGrams,
        basisAssumed: basisAssumed,
        rawValuesJson:
            originalRawValuesJson ??
            jsonEncode({
              'basis': basis.storedValue,
              'kcalPer100g': kcalPer100g,
              'proteinPer100g': proteinPer100g,
              'carbsPer100g': carbsPer100g,
              'fatPer100g': fatPer100g,
            }),
        activateOnFood: true,
      );
      if (aliases != null) {
        await _replaceAliases(id, aliases, now);
      }
    });
    _rememberRequest(requestKey, id);
    return id;
  }

  /// 用"每份营养 + 可信每份克数"录入，落库仍是每 100g。
  ///
  /// 界面应先预览换算后的每 100g 再提交（docs/67 §5.1）；没有可信克数时
  /// 不允许走这条路——必须补全或改填每 100g。
  Future<String> createMasterFoodFromServing({
    required String name,
    required double kcalPer100gPerServing,
    required double proteinPerServing,
    required double carbsPerServing,
    required double fatPerServing,
    required double servingGrams,
    ServingGramsStatus servingGramsStatus = ServingGramsStatus.known,
    ServingGramsSource servingGramsSource = ServingGramsSource.userInput,
    String? brand,
    String? cookingNote,
    String? category,
    String origin = 'user_input',
    bool isEstimated = false,
    String? requestKey,
  }) async {
    if (servingGramsStatus == ServingGramsStatus.unknown ||
        !servingGramsSource.isTrustedBasis) {
      throw const CatalogWriteException(
        '每份克数没有可信依据，不能把"一份"的营养换成每 100g。'
        '请填写可信的每份克数，或直接填每 100g 的值。',
      );
    }
    final kcal = per100gFromPerServing(
      perServing: kcalPer100gPerServing,
      servingGrams: servingGrams,
    );
    final protein = per100gFromPerServing(
      perServing: proteinPerServing,
      servingGrams: servingGrams,
    );
    final carbs = per100gFromPerServing(
      perServing: carbsPerServing,
      servingGrams: servingGrams,
    );
    final fat = per100gFromPerServing(
      perServing: fatPerServing,
      servingGrams: servingGrams,
    );
    if (kcal == null || protein == null || carbs == null || fat == null) {
      throw const CatalogWriteException('每份克数无效，无法换算每 100g。');
    }
    return createMasterFood(
      name: name,
      kcalPer100g: kcal,
      proteinPer100g: protein,
      carbsPer100g: carbs,
      fatPer100g: fat,
      brand: brand,
      cookingNote: cookingNote,
      category: category,
      origin: origin,
      isEstimated: isEstimated,
      requestKey: requestKey,
      // 原始口径与原始值必须留在修订里：只留换算结果等于把"每份 600 千卡"
      // 这段来历抹掉（docs/67 §3.2 第 3 条）。
      basis: NutritionBasis.perServing,
      basisServingGrams: servingGrams,
      basisAssumed: false,
      originalRawValuesJson: jsonEncode({
        'basis': 'perServing',
        'servingGrams': servingGrams,
        'servingGramsStatus': servingGramsStatus.storedValue,
        'servingGramsSource': servingGramsSource.storedValue,
        'kcalPerServing': kcalPer100gPerServing,
        'proteinPerServing': proteinPerServing,
        'carbsPerServing': carbsPerServing,
        'fatPerServing': fatPerServing,
      }),
    );
  }

  /// 追加一条营养修订并切换生效指针（同一事务，投影一起更新）。
  ///
  /// [expectedRevisionNumber] 是"我在界面上看到的是第几版"；与库里不一致时
  /// 抛 [CatalogVersionConflict]，调用方重取重预览，不做静默最后写入覆盖。
  Future<String> reviseMasterFood({
    required String foodId,
    required double kcalPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    double? fiberPer100g,
    double? sodiumMgPer100g,
    double? vitaminDMcgPer100g,
    String origin = 'user_input',
    bool isEstimated = false,
    int? expectedRevisionNumber,
  }) async {
    _requireCompleteNutrition(
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
      name: foodId,
    );
    final now = clock.nowUtc();
    late String revisionId;
    await database.transaction(() async {
      final food =
          await (database.select(database.foods)
                ..where((t) => t.id.equals(foodId))
                ..limit(1))
              .getSingleOrNull();
      if (food == null) {
        throw const CatalogWriteException('要修改的食物不存在。');
      }
      final latest = await _latestRevisionNumber(foodId);
      if (expectedRevisionNumber != null && latest != expectedRevisionNumber) {
        throw CatalogVersionConflict(
          expected: expectedRevisionNumber,
          actual: latest,
        );
      }
      revisionId = await _appendRevision(
        foodId: foodId,
        now: now,
        kcalPer100g: kcalPer100g,
        proteinPer100g: proteinPer100g,
        carbsPer100g: carbsPer100g,
        fatPer100g: fatPer100g,
        fiberPer100g: fiberPer100g,
        sodiumMgPer100g: sodiumMgPer100g,
        vitaminDMcgPer100g: vitaminDMcgPer100g,
        origin: origin,
        isEstimated: isEstimated,
        basis: NutritionBasis.per100g,
        basisServingGrams: null,
        basisAssumed: false,
        rawValuesJson: null,
      );
      await (database.update(
        database.foods,
      )..where((t) => t.id.equals(foodId))).write(
        FoodsCompanion(
          currentRevisionId: Value(revisionId),
          kcalPer100g: Value(kcalPer100g),
          proteinPer100g: Value(proteinPer100g),
          carbsPer100g: Value(carbsPer100g),
          fatPer100g: Value(fatPer100g),
          state: Value(isEstimated ? 'estimated' : food.state),
          updatedAt: Value(now),
        ),
      );
    });
    return revisionId;
  }

  /// 共享修订的影响范围（**先预览，再决定**）。
  ///
  /// 历史餐永不在影响范围里：它们保存的是当时快照（docs/67 D09）。
  Future<CatalogRevisionImpact> previewRevision(String foodId) async {
    final supplies = await (database.select(
      database.menuItems,
    )..where((t) => t.foodId.equals(foodId))).get();
    final windows = supplies.isEmpty
        ? const <MenuService>[]
        : await (database.select(
            database.menuServices,
          )..where((t) => t.id.isIn(supplies.map((s) => s.serviceId)))).get();
    final windowNames = {for (final row in windows) row.id: row.name};
    return CatalogRevisionImpact(
      foodId: foodId,
      supplies: [
        for (final supply in supplies)
          CatalogImpactedSupply(
            supplyId: supply.id,
            displayName: supply.displayName,
            windowName: windowNames[supply.serviceId] ?? '窗口',
          ),
      ],
      historicalMealsUnchanged: true,
    );
  }

  /// 局部重估默认分叉：建一条变体，只让当前供应改引用（D09）。
  Future<String> forkVariant({
    required String sourceFoodId,
    required String name,
    required double kcalPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    double? servingGramsForVariant,
    String origin = 'user_input',
    bool isEstimated = false,
    String? requestKey,
  }) async {
    final source =
        await (database.select(database.foods)
              ..where((t) => t.id.equals(sourceFoodId))
              ..limit(1))
            .getSingleOrNull();
    if (source == null) {
      throw const CatalogWriteException('原食物不存在，无法建立变体。');
    }
    // 变体父指向"根"条目，避免层层套娃。
    final parentId = source.variantOfFoodId ?? source.id;
    return createMasterFood(
      name: name,
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
      brand: source.brand,
      cookingNote: source.cookingNote,
      category: source.category,
      defaultServingGrams: servingGramsForVariant,
      origin: origin,
      isEstimated: isEstimated,
      variantOfFoodId: parentId,
      requestKey: requestKey,
    );
  }

  // ── 2. 挂窗 ─────────────────────────────────────────────────────────────

  /// 建一条食堂供应：可引用已有主食物，也可在同一事务里新建主食物。
  ///
  /// 返回 [SupplyWriteResult]，区分"新建供应"与"已存在同名供应"，
  /// 让回执能说清到底做了什么。
  Future<SupplyWriteResult> createSupply({
    required String windowId,
    required String displayName,
    String? foodId,
    NewMasterFoodInput? newFood,
    double? servingGrams,
    ServingGramsStatus servingGramsStatus = ServingGramsStatus.known,
    ServingGramsSource servingGramsSource = ServingGramsSource.userInput,
    String? imagePath,
    String? stationName,
    List<String> tags = const [],
    String? requestKey,
  }) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) {
      throw const CatalogWriteException('菜品名称不能为空。');
    }
    if (newFood != null && foodId != null) {
      throw const CatalogWriteException('不能同时指定已有食物和新建食物。');
    }
    if (servingGrams != null) {
      _requireServingGrams(servingGrams, allowNull: false);
    }
    if (servingGrams == null &&
        servingGramsStatus != ServingGramsStatus.unknown) {
      throw const CatalogWriteException('没有填每份克数时，份量状态只能是未知。');
    }

    final window =
        await (database.select(database.menuServices)
              ..where((t) => t.id.equals(windowId))
              ..limit(1))
            .getSingleOrNull();
    if (window == null) {
      throw const CatalogWriteException('要挂的窗口不存在。');
    }
    if (foodId != null) {
      await _requireActiveFood(foodId);
    }

    final now = clock.nowUtc();
    String? supplyId;
    var created = false;
    await database.transaction(() async {
      String? resolvedFoodId = foodId;
      if (newFood != null) {
        resolvedFoodId = await createMasterFood(
          name: newFood.name,
          kcalPer100g: newFood.kcalPer100g,
          proteinPer100g: newFood.proteinPer100g,
          carbsPer100g: newFood.carbsPer100g,
          fatPer100g: newFood.fatPer100g,
          brand: newFood.brand,
          cookingNote: newFood.cookingNote,
          origin: newFood.origin,
          isEstimated: newFood.isEstimated,
        );
      }
      final existing =
          await (database.select(database.menuItems)
                ..where(
                  (t) =>
                      t.serviceId.equals(windowId) &
                      t.displayName.equals(trimmed),
                )
                ..limit(1))
              .getSingleOrNull();
      if (existing != null) {
        supplyId = existing.id;
        created = false;
        final resolvedGrams = servingGrams ?? existing.servingGrams;
        await (database.update(
          database.menuItems,
        )..where((t) => t.id.equals(existing.id))).write(
          MenuItemsCompanion(
            foodId: Value(resolvedFoodId ?? existing.foodId),
            servingGrams: Value(resolvedGrams),
            servingGramsStatus: Value(
              resolvedGrams == null
                  ? ServingGramsStatus.unknown.storedValue
                  : servingGramsStatus.storedValue,
            ),
            servingGramsSource: Value(servingGramsSource.storedValue),
            imagePath: Value(imagePath ?? existing.imagePath),
            stationName: Value(stationName ?? existing.stationName),
            updatedAt: Value(now),
          ),
        );
      } else {
        final id = idGenerator.next();
        supplyId = id;
        created = true;
        await database
            .into(database.menuItems)
            .insert(
              MenuItemsCompanion.insert(
                id: id,
                serviceId: windowId,
                displayName: trimmed,
                stationName: Value(stationName),
                imagePath: Value(imagePath),
                evidenceGrade: const Value('C'),
                itemStatus: Value(
                  resolvedFoodId == null ? 'unresolved' : 'estimated',
                ),
                createdAt: now,
                updatedAt: now,
                servingGrams: Value(servingGrams),
                tagsJson: Value(tags.isEmpty ? '[]' : jsonEncode(tags)),
                foodId: Value(resolvedFoodId),
                servingGramsStatus: Value(
                  servingGrams == null
                      ? ServingGramsStatus.unknown.storedValue
                      : servingGramsStatus.storedValue,
                ),
                servingGramsSource: Value(servingGramsSource.storedValue),
              ),
            );
      }
    });
    _rememberRequest(requestKey, supplyId!);
    return SupplyWriteResult(
      supplyId: supplyId!,
      created: created,
      displayName: trimmed,
    );
  }

  /// 改供应的窗口信息（展示名 / 每份克数 / 照片）。**只影响这条供应**。
  Future<void> updateSupplyWindowInfo({
    required String supplyId,
    String? displayName,
    double? servingGrams,
    bool clearServingGrams = false,
    ServingGramsStatus servingGramsStatus = ServingGramsStatus.known,
    ServingGramsSource servingGramsSource = ServingGramsSource.userInput,
    String? imagePath,
    bool setImagePath = false,
  }) async {
    if (clearServingGrams && servingGrams != null) {
      throw const CatalogWriteException('不能同时设置和清除每份克数。');
    }
    if (servingGrams != null) {
      _requireServingGrams(servingGrams, allowNull: false);
    }
    final now = clock.nowUtc();
    final touchesServing = clearServingGrams || servingGrams != null;
    final companion = MenuItemsCompanion(
      displayName: displayName == null
          ? const Value.absent()
          : Value(displayName.trim()),
      servingGrams: clearServingGrams
          ? const Value<double?>(null)
          : (servingGrams == null
                ? const Value<double?>.absent()
                : Value<double?>(servingGrams)),
      servingGramsStatus: touchesServing
          ? Value(
              clearServingGrams
                  ? ServingGramsStatus.unknown.storedValue
                  : servingGramsStatus.storedValue,
            )
          : const Value.absent(),
      servingGramsSource: touchesServing
          ? Value(
              clearServingGrams
                  ? ServingGramsSource.legacyUnknown.storedValue
                  : servingGramsSource.storedValue,
            )
          : const Value.absent(),
      imagePath: setImagePath
          ? Value<String?>(imagePath)
          : const Value<String?>.absent(),
      updatedAt: Value(now),
    );
    final updated = await (database.update(
      database.menuItems,
    )..where((t) => t.id.equals(supplyId))).write(companion);
    if (updated == 0) {
      throw const CatalogWriteException('要修改的供应不存在。');
    }
  }

  /// 供应改引用另一条主食物（局部重估分叉后的落点）。
  Future<void> relinkSupply({
    required String supplyId,
    required String foodId,
  }) async {
    await _requireActiveFood(foodId);
    final updated =
        await (database.update(
          database.menuItems,
        )..where((t) => t.id.equals(supplyId))).write(
          MenuItemsCompanion(
            foodId: Value(foodId),
            itemStatus: const Value('estimated'),
            updatedAt: Value(clock.nowUtc()),
          ),
        );
    if (updated == 0) {
      throw const CatalogWriteException('要改引用的供应不存在。');
    }
  }

  /// 归档主食物：仍被供应引用时**不删**，只是不再进新挂窗与自动推荐。
  Future<void> archiveFood(String foodId) async {
    final now = clock.nowUtc();
    final updated =
        await (database.update(
          database.foods,
        )..where((t) => t.id.equals(foodId))).write(
          FoodsCompanion(
            archivedAt: Value(now),
            state: const Value('archived'),
            updatedAt: Value(now),
          ),
        );
    if (updated == 0) {
      throw const CatalogWriteException('要归档的食物不存在。');
    }
  }

  /// 删主食物：仍被供应引用时拒绝（先归档），避免静默级联删供应。
  Future<void> deleteFoodIfUnreferenced(String foodId) async {
    final referencing =
        await (database.select(database.menuItems)
              ..where((t) => t.foodId.equals(foodId))
              ..limit(1))
            .getSingleOrNull();
    if (referencing != null) {
      throw const CatalogWriteException('这条食物还在被食堂窗口引用，不能删除；可以先归档。');
    }
    final usedByMeal =
        await (database.select(database.mealItems)
              ..where((t) => t.foodId.equals(foodId))
              ..limit(1))
            .getSingleOrNull();
    if (usedByMeal != null) {
      // 历史餐保留快照，只断开外键；快照值不动（docs/67 §4.3）。
      await (database.update(database.mealItems)
            ..where((t) => t.foodId.equals(foodId)))
          .write(const MealItemsCompanion(foodId: Value(null)));
    }
    await (database.delete(
      database.legacyEntityMappings,
    )..where((t) => t.foodId.equals(foodId))).go();
    await (database.delete(
      database.foods,
    )..where((t) => t.id.equals(foodId))).go();
  }

  // ── 3. 记餐 ─────────────────────────────────────────────────────────────

  /// 记一餐：底层永远是**克数**，营养来自主食物当前生效修订的快照。
  ///
  /// 改主库或改供应份量都不重算历史餐——这里写进去的就是当时的快照。
  Future<String> recordMeal({
    required String localDate,
    required String slot,
    required List<CatalogMealItemInput> items,
    String source = 'manual',
    String? notes,
  }) async {
    if (items.isEmpty) {
      throw const CatalogWriteException('这一餐至少要有一样食物。');
    }
    final now = clock.nowUtc();
    final mealId = idGenerator.next();
    await database.transaction(() async {
      await database
          .into(database.meals)
          .insert(
            MealsCompanion.insert(
              id: mealId,
              localDate: localDate,
              slot: slot,
              eatenAt: now,
              notes: Value(notes),
              source: source,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database.batch((batch) {
        batch.insertAll(database.mealItems, [
          for (final item in items)
            MealItemsCompanion.insert(
              id: idGenerator.next(),
              mealId: mealId,
              foodId: Value(item.foodId),
              foodNameSnapshot: item.name.trim(),
              grams: item.grams,
              kcalSnapshot: item.nutrition.kcal,
              proteinSnapshot: item.nutrition.proteinGrams,
              carbsSnapshot: item.nutrition.carbsGrams,
              fatSnapshot: item.nutrition.fatGrams,
              sourceType: Value(item.sourceType),
              sourceId: Value(item.sourceId),
              supplyId: Value(item.supplyId),
              nutritionRevisionId: Value(item.nutritionRevisionId),
              servings: Value(item.servings),
              servingGrams: Value(item.servingGrams),
              createdAt: now,
              updatedAt: now,
            ),
        ]);
      });
    });
    return mealId;
  }

  // ── 内部 ────────────────────────────────────────────────────────────────

  Future<String> _appendRevision({
    required String foodId,
    required DateTime now,
    required double kcalPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    required String origin,
    required bool isEstimated,
    required NutritionBasis basis,
    required double? basisServingGrams,
    required bool basisAssumed,
    required String? rawValuesJson,
    double? fiberPer100g,
    double? sodiumMgPer100g,
    double? vitaminDMcgPer100g,
    bool activateOnFood = false,
  }) async {
    final number = await _latestRevisionNumber(foodId) + 1;
    final id = '$foodId-rev-$number';
    await database
        .into(database.foodNutritionRevisions)
        .insert(
          FoodNutritionRevisionsCompanion.insert(
            id: id,
            foodId: foodId,
            revisionNumber: number,
            kcalPer100g: Value(kcalPer100g),
            proteinGPer100g: Value(proteinPer100g),
            carbsGPer100g: Value(carbsPer100g),
            fatGPer100g: Value(fatPer100g),
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
          ),
        );
    if (activateOnFood) {
      // 主表四项是这条修订的投影，指针与投影同事务写：不能出现"有当前值
      // 但不知道是按哪一版算的"。
      await (database.update(database.foods)..where((t) => t.id.equals(foodId)))
          .write(FoodsCompanion(currentRevisionId: Value(id)));
    }
    return id;
  }

  Future<int> _latestRevisionNumber(String foodId) async {
    final row = await database
        .customSelect(
          'SELECT COALESCE(MAX(revision_number), 0) AS n '
          'FROM food_nutrition_revisions WHERE food_id = ?',
          variables: [Variable.withString(foodId)],
        )
        .getSingle();
    return (row.data['n'] as int? ?? 0);
  }

  Future<void> _requireActiveFood(String foodId) async {
    final food =
        await (database.select(database.foods)
              ..where((t) => t.id.equals(foodId))
              ..limit(1))
            .getSingleOrNull();
    if (food == null) {
      throw const CatalogWriteException('要引用的食物不存在。');
    }
    if (food.archivedAt != null) {
      throw const CatalogWriteException('这条食物已归档，不能新挂窗；请选择替代条目。');
    }
    if (!isCompleteNutrition(
      kcalPer100g: food.kcalPer100g,
      proteinPer100g: food.proteinPer100g,
      carbsPer100g: food.carbsPer100g,
      fatPer100g: food.fatPer100g,
    )) {
      throw const CatalogWriteException('这条食物的营养还不完整，不能挂窗。');
    }
  }

  Future<void> _replaceAliases(
    String foodId,
    List<String> aliases,
    DateTime now,
  ) async {
    await (database.delete(
      database.foodAliases,
    )..where((t) => t.foodId.equals(foodId))).go();
    for (final alias in aliases) {
      final trimmed = alias.trim();
      if (trimmed.isEmpty) continue;
      await database
          .into(database.foodAliases)
          .insert(
            FoodAliasesCompanion.insert(
              id: idGenerator.next(),
              foodId: foodId,
              normalizedText: trimmed.toLowerCase(),
              aliasType: 'manual',
              source: 'user',
              createdAt: now,
            ),
          );
    }
  }

  void _requireCompleteNutrition({
    required double kcalPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    required String name,
  }) {
    if (!isCompleteNutrition(
      kcalPer100g: kcalPer100g,
      proteinPer100g: proteinPer100g,
      carbsPer100g: carbsPer100g,
      fatPer100g: fatPer100g,
    )) {
      throw CatalogWriteException('「$name」的营养必须是四项齐全的非负数。');
    }
    if (kcalPer100g > NutritionLimits.maxKcalPer100g ||
        proteinPer100g > NutritionLimits.maxMacroPer100g ||
        carbsPer100g > NutritionLimits.maxMacroPer100g ||
        fatPer100g > NutritionLimits.maxMacroPer100g) {
      throw CatalogWriteException('「$name」的营养数值超出合理范围。');
    }
  }

  void _requireServingGrams(double? grams, {required bool allowNull}) {
    if (grams == null) {
      if (allowNull) return;
      throw const CatalogWriteException('每份克数不能为空。');
    }
    if (!grams.isFinite ||
        grams <= 0 ||
        grams > NutritionLimits.maxServingGrams) {
      throw const CatalogWriteException('每份克数要填 0–2000 之间的数字。');
    }
  }

  String? _cachedRequest(String? key) =>
      key == null ? null : _requestResults[key];

  void _rememberRequest(String? key, String value) {
    if (key == null) return;
    if (_requestResults.length > 200) _requestResults.clear();
    _requestResults[key] = value;
  }
}

/// 新建主食物的输入（供"同流程新建+挂窗"用）。
final class NewMasterFoodInput {
  const NewMasterFoodInput({
    required this.name,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.brand,
    this.cookingNote,
    this.origin = 'user_input',
    this.isEstimated = false,
  });

  final String name;
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final String? brand;
  final String? cookingNote;
  final String origin;
  final bool isEstimated;
}

final class SupplyWriteResult {
  const SupplyWriteResult({
    required this.supplyId,
    required this.created,
    required this.displayName,
  });

  final String supplyId;
  final bool created;
  final String displayName;
}

/// 记餐条目的统一输入（已解析成克数与营养）。
final class CatalogMealItemInput {
  const CatalogMealItemInput({
    required this.name,
    required this.grams,
    required this.nutrition,
    this.foodId,
    this.sourceType = 'manual',
    this.sourceId,
    this.supplyId,
    this.nutritionRevisionId,
    this.servings,
    this.servingGrams,
  });

  final String name;
  final double grams;
  final CatalogNutrition nutrition;
  final String? foodId;
  final String sourceType;
  final String? sourceId;
  final String? supplyId;
  final String? nutritionRevisionId;
  final double? servings;
  final double? servingGrams;
}

/// 四值快照（避免写入服务依赖展示层的营养类型）。
final class CatalogNutrition {
  const CatalogNutrition({
    required this.kcal,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  final double kcal;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
}

final class CatalogRevisionImpact {
  const CatalogRevisionImpact({
    required this.foodId,
    required this.supplies,
    required this.historicalMealsUnchanged,
  });

  final String foodId;
  final List<CatalogImpactedSupply> supplies;

  /// 历史餐永远不变——这不是"暂时"的实现细节，是契约。
  final bool historicalMealsUnchanged;

  int get supplyCount => supplies.length;
}

final class CatalogImpactedSupply {
  const CatalogImpactedSupply({
    required this.supplyId,
    required this.displayName,
    required this.windowName,
  });

  final String supplyId;
  final String displayName;
  final String windowName;
}

/// 写入被业务规则拒绝（用户可读）。
final class CatalogWriteException implements Exception {
  const CatalogWriteException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

/// 读后被别人改过：必须重取重预览，不能静默覆盖。
final class CatalogVersionConflict implements Exception {
  const CatalogVersionConflict({required this.expected, required this.actual});

  final int expected;
  final int actual;

  String get userMessage => '这条食物的营养刚被别人改过（当前第 $actual 版），请重新预览后再保存。';

  @override
  String toString() => userMessage;
}
