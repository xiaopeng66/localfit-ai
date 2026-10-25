import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

final class MealRepository {
  const MealRepository({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  Stream<void> watchIntakeChanges() => database
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          database.meals,
          database.mealItems,
          database.dailyTargets,
          database.goals,
        ]),
      )
      .map((_) {});

  Future<void> saveManualMeal(ManualMealDraft draft) =>
      create(draft.toMealDraft());

  Future<String> create(MealDraft draft, {String source = 'manual'}) async {
    _validate(draft);
    final id = idGenerator.next();
    final now = clock.nowUtc();
    await database.saveConfirmedMeal(
      meal: _mealCompanion(
        id: id,
        draft: draft,
        source: source,
        eatenAt: now,
        createdAt: now,
        updatedAt: now,
      ),
      items: _newItemCompanions(id, draft.items, now),
    );
    return id;
  }

  /// 当天餐食，**按餐位域序**（早餐 → 午餐 → 晚餐 → 加餐），同餐位内按记录时刻。
  ///
  /// 不按 `ORDER BY slot` 排：那是存储串的字符串序，`'dinner' < 'lunch'`，
  /// 于是列表渲染成 早餐 / 晚餐 / 午餐（round7 2A 整页渲染逐张审看抓到的
  /// 真实缺陷）。域顺序的唯一事实源是 `MealSlot.values` 的声明序，SQL 侧
  /// 没有它——查询只负责给确定性的 `eatenAt` 序，装载后在这里定序。
  Stream<List<MealRecord>> watchForDate(String localDate) {
    _validateDate(localDate);
    final query = database.select(database.meals)
      ..where((row) => row.localDate.equals(localDate))
      ..orderBy([(row) => OrderingTerm.asc(row.eatenAt)]);
    return query.watch().asyncMap(_loadAggregates).map(_sortedBySlot);
  }

  /// 按餐位域序排序（同餐位内保持入参顺序 = SQL 的 `eatenAt` 升序）。
  ///
  /// `List.sort` 不保证稳定，所以比较器里带上 `eatenAt`，不靠顺序巧合。
  static List<MealRecord> _sortedBySlot(List<MealRecord> meals) {
    final sorted = [...meals]
      ..sort((a, b) {
        final bySlot = a.slot.index.compareTo(b.slot.index);
        return bySlot != 0 ? bySlot : a.eatenAt.compareTo(b.eatenAt);
      });
    return sorted;
  }

  Future<List<MealRecord>> listRecent({int limit = 50}) async {
    if (limit <= 0) return const [];
    final query = database.select(database.meals)
      ..orderBy([
        (row) => OrderingTerm.desc(row.localDate),
        (row) => OrderingTerm.desc(row.eatenAt),
      ])
      ..limit(limit);
    return _loadAggregates(await query.get());
  }

  Future<MealRecord?> getById(String id) async {
    final row = await (database.select(
      database.meals,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return _loadAggregate(row);
  }

  Future<void> update(String id, MealDraft draft) async {
    _validate(draft);
    final existing = await getById(id);
    if (existing == null) throw StateError('餐食不存在或已被删除。');
    final now = clock.nowUtc();
    await database.transaction(() async {
      final changed =
          await (database.update(
            database.meals,
          )..where((row) => row.id.equals(id))).write(
            MealsCompanion(
              localDate: Value(draft.localDate),
              slot: Value(draft.slot.storedValue),
              notes: Value(_normalizedNotes(draft.notes)),
              updatedAt: Value(now),
            ),
          );
      if (changed != 1) throw StateError('餐食不存在或已被删除。');
      await (database.delete(
        database.mealItems,
      )..where((row) => row.mealId.equals(id))).go();
      await database.batch(
        (batch) => batch.insertAll(
          database.mealItems,
          _newItemCompanions(id, draft.items, now),
        ),
      );
    });
  }

  Future<MealRecord?> delete(String id) async {
    final existing = await getById(id);
    if (existing == null) return null;
    final deleted = await (database.delete(
      database.meals,
    )..where((row) => row.id.equals(id))).go();
    return deleted == 1 ? existing : null;
  }

  Future<void> restore(MealRecord record) async {
    _validate(record.toDraft());
    await database.saveConfirmedMeal(
      meal: _mealCompanion(
        id: record.id,
        draft: record.toDraft(),
        source: record.source,
        eatenAt: record.eatenAt,
        createdAt: record.createdAt,
        updatedAt: record.updatedAt,
      ),
      items: record.items
          .map(
            (item) => MealItemsCompanion.insert(
              id: item.id,
              mealId: record.id,
              foodId: Value(item.foodId),
              foodNameSnapshot: item.foodName,
              grams: item.grams,
              kcalSnapshot: item.nutrition.kcal,
              proteinSnapshot: item.nutrition.proteinGrams,
              carbsSnapshot: item.nutrition.carbsGrams,
              fatSnapshot: item.nutrition.fatGrams,
              createdAt: item.createdAt,
              updatedAt: item.updatedAt,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<String> reuse(
    String sourceMealId, {
    required String localDate,
    MealSlot? slot,
  }) async {
    _validateDate(localDate);
    final source = await getById(sourceMealId);
    if (source == null) throw StateError('历史餐食不存在。');
    return create(
      MealDraft(
        localDate: localDate,
        slot: slot ?? source.slot,
        notes: source.notes,
        items: source.items
            .map((item) => item.scaledTo(item.grams))
            .toList(growable: false),
      ),
      source: 'history_reuse',
    );
  }

  Stream<DailyNutritionSummary> watchNutritionForDate(String localDate) {
    _validateDate(localDate);
    final mealsForDate = database.selectOnly(database.meals)
      ..addColumns([database.meals.id])
      ..where(database.meals.localDate.equals(localDate));
    final kcal = database.mealItems.kcalSnapshot.sum();
    final protein = database.mealItems.proteinSnapshot.sum();
    final carbs = database.mealItems.carbsSnapshot.sum();
    final fat = database.mealItems.fatSnapshot.sum();
    final totalsQuery = database.selectOnly(database.mealItems)
      ..addColumns([kcal, protein, carbs, fat])
      ..where(database.mealItems.mealId.isInQuery(mealsForDate));

    return totalsQuery.watchSingle().asyncMap((row) async {
      double total(Expression<double> expression) => row.read(expression) ?? 0;
      return DailyNutritionSummary(
        consumed: NutritionValues(
          kcal: total(kcal),
          proteinGrams: total(protein),
          carbsGrams: total(carbs),
          fatGrams: total(fat),
        ),
        target: await _targetForDate(localDate),
      );
    });
  }

  /// Aggregated per-day intake totals for the inclusive local-date range.
  /// Days without any recorded meal are absent from the result.
  Future<List<DailyNutritionRecord>> listDailyIntakeBetween(
    String startLocalDate,
    String endLocalDate,
  ) async {
    final kcal = database.mealItems.kcalSnapshot.sum();
    final protein = database.mealItems.proteinSnapshot.sum();
    final carbs = database.mealItems.carbsSnapshot.sum();
    final fat = database.mealItems.fatSnapshot.sum();
    final query = database.selectOnly(database.meals).join([
      innerJoin(
        database.mealItems,
        database.mealItems.mealId.equalsExp(database.meals.id),
      ),
    ]);
    query.addColumns([database.meals.localDate, kcal, protein, carbs, fat]);
    query.where(
      database.meals.localDate.isBiggerOrEqualValue(startLocalDate) &
          database.meals.localDate.isSmallerOrEqualValue(endLocalDate),
    );
    query.groupBy([database.meals.localDate]);
    final rows = await query.get();
    return rows
        .map((row) {
          double total(Expression<double> expression) =>
              row.read(expression) ?? 0;
          return DailyNutritionRecord(
            localDate: row.read(database.meals.localDate)!,
            nutrition: NutritionValues(
              kcal: total(kcal),
              proteinGrams: total(protein),
              carbsGrams: total(carbs),
              fatGrams: total(fat),
            ),
          );
        })
        .toList(growable: false);
  }

  Future<List<MealRecord>> _loadAggregates(List<Meal> rows) async {
    if (rows.isEmpty) return const [];
    // 一条 IN 查询批量装载所有条目，避免每餐单独查询（N+1）。
    // 全局按 createdAt 升序取回，按 mealId 分组后每餐内相对顺序与
    // 逐餐 ORDER BY created_at ASC 完全一致。
    final itemRows =
        await (database.select(database.mealItems)
              ..where((item) => item.mealId.isIn(rows.map((row) => row.id)))
              ..orderBy([(item) => OrderingTerm.asc(item.createdAt)]))
            .get();
    final itemsByMeal = <String, List<MealItem>>{};
    for (final item in itemRows) {
      itemsByMeal.putIfAbsent(item.mealId, () => []).add(item);
    }
    return [
      for (final row in rows)
        _recordFromRow(row, itemsByMeal[row.id] ?? const []),
    ];
  }

  MealRecord _recordFromRow(Meal row, List<MealItem> itemRows) => MealRecord(
    id: row.id,
    localDate: row.localDate,
    slot: MealSlot.fromStoredValue(row.slot),
    eatenAt: row.eatenAt,
    notes: row.notes,
    source: row.source,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    items: itemRows
        .map(
          (item) => MealItemRecord(
            id: item.id,
            foodId: item.foodId,
            foodName: item.foodNameSnapshot,
            grams: item.grams,
            nutrition: NutritionValues(
              kcal: item.kcalSnapshot,
              proteinGrams: item.proteinSnapshot,
              carbsGrams: item.carbsSnapshot,
              fatGrams: item.fatSnapshot,
            ),
            sourceType: item.sourceType,
            sourceId: item.sourceId,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
          ),
        )
        .toList(growable: false),
  );

  Future<MealRecord> _loadAggregate(Meal row) async {
    final itemRows =
        await (database.select(database.mealItems)
              ..where((item) => item.mealId.equals(row.id))
              ..orderBy([(item) => OrderingTerm.asc(item.createdAt)]))
            .get();
    return _recordFromRow(row, itemRows);
  }

  MealsCompanion _mealCompanion({
    required String id,
    required MealDraft draft,
    required String source,
    required DateTime eatenAt,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) => MealsCompanion.insert(
    id: id,
    localDate: draft.localDate,
    slot: draft.slot.storedValue,
    eatenAt: eatenAt,
    notes: Value(_normalizedNotes(draft.notes)),
    source: source,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  List<MealItemsCompanion> _newItemCompanions(
    String mealId,
    List<MealItemDraft> items,
    DateTime now,
  ) => items
      .map(
        (item) => MealItemsCompanion.insert(
          id: idGenerator.next(),
          mealId: mealId,
          foodId: Value(item.foodId),
          foodNameSnapshot: item.foodName.trim(),
          grams: item.grams,
          kcalSnapshot: item.nutrition.kcal,
          proteinSnapshot: item.nutrition.proteinGrams,
          carbsSnapshot: item.nutrition.carbsGrams,
          fatSnapshot: item.nutrition.fatGrams,
          sourceType: Value(item.sourceType),
          sourceId: Value(item.sourceId),
          createdAt: now,
          updatedAt: now,
        ),
      )
      .toList(growable: false);

  Future<DailyNutritionTarget?> _targetForDate(String localDate) async {
    final query = database.select(database.dailyTargets)
      ..where((row) => row.effectiveDate.isSmallerOrEqualValue(localDate))
      ..orderBy([(row) => OrderingTerm.desc(row.effectiveDate)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return DailyNutritionTarget(
      calorieMinKcal: row.calorieMinKcal,
      calorieMaxKcal: row.calorieMaxKcal,
      proteinMinGrams: row.proteinMinGrams,
      proteinMaxGrams: row.proteinMaxGrams,
      carbsMinGrams: row.carbsMinGrams,
      carbsMaxGrams: row.carbsMaxGrams,
      fatMinGrams: row.fatMinGrams,
      fatMaxGrams: row.fatMaxGrams,
    );
  }

  void _validate(MealDraft draft) {
    _validateDate(draft.localDate);
    if (draft.items.isEmpty) {
      throw const FormatException('请至少添加一种食物。');
    }
    for (final item in draft.items) {
      if (item.foodName.trim().isEmpty) {
        throw const FormatException('食物名称不能为空。');
      }
      if (!item.grams.isFinite || item.grams <= 0) {
        throw const FormatException('食物克数必须是大于零的有限数值。');
      }
      final values = [
        item.nutrition.kcal,
        item.nutrition.proteinGrams,
        item.nutrition.carbsGrams,
        item.nutrition.fatGrams,
      ];
      if (values.any((value) => !value.isFinite || value < 0)) {
        throw const FormatException('营养快照必须是非负有限数值。');
      }
    }
  }

  void _validateDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) throw const FormatException('餐食日期格式无效。');
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      throw const FormatException('餐食日期无效。');
    }
  }

  String? _normalizedNotes(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
