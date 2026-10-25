import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/core/validation/entity_name.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// 菜品库仓储（docs/21 §5.3 数据源裁决 / §7.2 `DishLibrary`）。
///
/// 「饮食·菜单」页只从这里读；`MenuItems` 是写入时的证据来源，不进展示层。
final class DishLibraryRepository {
  const DishLibraryRepository({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 监听全部菜品（按餐次、再按创建时间排序，列表顺序稳定）。
  Stream<List<DishRecord>> watchAll({
    DishLibraryFilter filter = const DishLibraryFilter(),
  }) {
    final query = database.select(database.dishLibrary)
      ..orderBy([
        (row) => OrderingTerm.asc(row.mealSlot),
        (row) => OrderingTerm.asc(row.createdAt),
      ]);
    final slot = filter.mealSlot;
    if (slot != null) {
      query.where((row) => row.mealSlot.equals(slot));
    }
    if (filter.hotOnly) {
      query.where((row) => row.isHot.equals(true));
    }
    return query.watch().map((rows) => rows.map(_map).toList(growable: false));
  }

  /// 命中「本周热门」的菜品（`isHot`）。
  Stream<List<DishRecord>> watchHot() =>
      watchAll(filter: const DishLibraryFilter(hotOnly: true));

  /// 新增一道菜。
  Future<DishRecord> create(DishDraft draft) async {
    final name = draft.name.trim();
    validateDishNutrition(
      name: name,
      kcal: draft.kcal,
      proteinG: draft.proteinG,
      carbsG: draft.carbsG,
      fatG: draft.fatG,
      fiberG: draft.fiberG,
      sodiumMg: draft.sodiumMg,
      vitaminDMcg: draft.vitaminDMcg,
    );
    validateServingWindow(draft.servingWindow);
    final now = clock.nowUtc();
    final id = idGenerator.next();
    // 归一化一次、两处（落库 + 返回值）共用：只归一化落库那一份会让调用方
    // 拿到 `'   '` 而当宝，展示层于是渲染出一个空点评块。
    final comment = _normalizeText(draft.comment);
    final servingWindow = _normalizeText(draft.servingWindow);
    // 空字符串路径同样折算成 null：`Image.file('')` 会抛错，而「无照片」
    // 本来就该走渐变占位（docs/21 §6.1）。
    final imagePath = _normalizeText(draft.imagePath);
    await database
        .into(database.dishLibrary)
        .insert(
          DishLibraryCompanion.insert(
            id: id,
            name: name,
            mealSlot: draft.mealSlot,
            kcal: draft.kcal,
            proteinG: draft.proteinG,
            carbsG: draft.carbsG,
            fatG: draft.fatG,
            source: draft.source,
            createdAt: now,
            updatedAt: now,
            imagePath: Value(imagePath),
            servingWindow: Value(servingWindow),
            isHot: Value(draft.isHot),
            fiberG: Value(draft.fiberG),
            sodiumMg: Value(draft.sodiumMg),
            vitaminDMcg: Value(draft.vitaminDMcg),
            comment: Value(comment),
            servingGrams: Value(draft.servingGrams),
            nutritionBasis: Value(draft.nutritionBasis),
            basisAssumed: Value(draft.servingGrams == null),
            sourceType: Value(draft.sourceType),
            sourceId: Value(draft.sourceId),
            sourceUpdatedAt: Value(draft.sourceUpdatedAt),
            userEdited: Value(draft.userEdited),
          ),
        );
    return DishRecord(
      id: id,
      name: name,
      mealSlot: draft.mealSlot,
      kcal: draft.kcal,
      proteinG: draft.proteinG,
      carbsG: draft.carbsG,
      fatG: draft.fatG,
      source: draft.source,
      createdAt: now,
      updatedAt: now,
      imagePath: imagePath,
      servingWindow: servingWindow,
      isHot: draft.isHot,
      fiberG: draft.fiberG,
      sodiumMg: draft.sodiumMg,
      vitaminDMcg: draft.vitaminDMcg,
      comment: comment,
      servingGrams: draft.servingGrams,
      basisAssumed: draft.servingGrams == null,
      sourceType: draft.sourceType,
      sourceId: draft.sourceId,
      sourceUpdatedAt: draft.sourceUpdatedAt,
      userEdited: draft.userEdited,
    );
  }

  /// 去空白；空串与全空白一律折成 null（展示层据此不渲染该块）。
  static String? _normalizeText(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// 按菜名写入或更新（同名 = 同一道菜）。
  ///
  /// 食堂路径反复「加入菜品库」时用它：每次 `create` 会让菜单页堆出多张
  /// 同名卡，用户看到的却是同一道菜的两份营养。菜名是本应用里菜品唯一
  /// 可见标识（`DishLibrary` 没有来源菜品列），所以同名的语义就是同一道菜。
  ///
  /// 更新保留原 `id` 与 `createdAt`（列表顺序稳定），刷新 `updatedAt`。
  Future<DishRecord> upsertByName(DishDraft draft) async {
    final name = validatedEntityName(draft.name, label: '菜名');
    // 2026-10-21 RV-P2-05：同名更新也必须走与新建同一套数值校验。
    validateDishNutrition(
      name: name,
      kcal: draft.kcal,
      proteinG: draft.proteinG,
      carbsG: draft.carbsG,
      fatG: draft.fatG,
      fiberG: draft.fiberG,
      sodiumMg: draft.sodiumMg,
      vitaminDMcg: draft.vitaminDMcg,
    );
    final existing =
        await (database.select(database.dishLibrary)
              ..where((row) => row.name.equals(name))
              ..limit(1))
            .getSingleOrNull();
    if (existing == null) return create(draft);
    final record = _updated(existing, draft, name);
    // 复用 restore 的 insertOnConflictUpdate：更新与回写只需一条写路径。
    await restore(record);
    return record;
  }

  /// 按**来源**写入或更新（2026-10-24 用户：「食堂目录和菜品库就是一个库」）。
  ///
  /// `(sourceType, sourceId)` 是来源菜在菜品库里的身份：改名、改营养、换照片
  /// 都更新**同一行**，不会因改名堆出第二张同名卡（[upsertByName] 按名字找，
  /// 改名会新建一行——那正是「两个库」时代的重复来源）。
  ///
  /// 找不到来源行时回落到**同名**行并把来源链接补上：历史行可能是在来源列
  /// 之前写的，而「同名 = 同一道菜」是本文件的既有语义。
  Future<DishRecord> upsertBySource({
    required String sourceType,
    required String sourceId,
    required DishDraft draft,
  }) async {
    final name = validatedEntityName(draft.name, label: '菜名');
    validateDishNutrition(
      name: name,
      kcal: draft.kcal,
      proteinG: draft.proteinG,
      carbsG: draft.carbsG,
      fatG: draft.fatG,
      fiberG: draft.fiberG,
      sodiumMg: draft.sodiumMg,
      vitaminDMcg: draft.vitaminDMcg,
    );
    final bySource =
        await (database.select(database.dishLibrary)
              ..where(
                (row) =>
                    row.sourceType.equals(sourceType) &
                    row.sourceId.equals(sourceId),
              )
              ..limit(1))
            .getSingleOrNull();
    final existing =
        bySource ??
        await (database.select(database.dishLibrary)
              ..where((row) => row.name.equals(name))
              ..limit(1))
            .getSingleOrNull();
    if (existing == null) return create(draft);
    // `RV4-P2-09`（`docs/56` R10-c）：「用户手改即冻结」。
    //
    // 「陈旧提示 + 手动同步」整族退役后，自动同步是**唯一**写路径；它必须
    // 尊重用户手改过的那一行——否则用户把估值改成 99 kcal，食堂侧下一次
    // 分析就把它悄悄改回 160，这比「不更新」更糟（用户看到自己改的数消失）。
    //
    // 冻结的是**营养四值**；菜名/餐次/来源这些「来源侧的排布事实」仍跟随来源
    // （改名场景的既有测试要求同一行更新，不是新造一行）。用户想解除冻结：
    // 在菜品库编辑那一行（`userEdited` 会被那次编辑重新置位）或删除重建。
    //
    // 这一层放在仓储而不是 UI：调用方有三个（自动同步 / backfill / 手动），
    // 策略写在仓储才不会漏。
    if (existing.userEdited) {
      final record = _updatedPreservingUserNutrition(existing, draft, name);
      await restore(record);
      return record;
    }
    final record = _updated(existing, draft, name);
    await restore(record);
    return record;
  }

  /// `existing.userEdited == true` 时的行构造：**营养四值 + 来源证据保留
  /// 用户的值与 `manual` 标记**，其余（名称/餐次/照片/窗口/份量/来源键）
  /// 跟随来源。`userEdited` 恒为 true。
  DishRecord _updatedPreservingUserNutrition(
    DishLibraryEntry existing,
    DishDraft draft,
    String name,
  ) => DishRecord(
    id: existing.id,
    name: name,
    mealSlot: draft.mealSlot,
    // 用户手改的四值原样保留。
    kcal: existing.kcal,
    proteinG: existing.proteinG,
    carbsG: existing.carbsG,
    fatG: existing.fatG,
    source: existing.source,
    createdAt: existing.createdAt,
    updatedAt: clock.nowUtc(),
    // 照片/窗口/份量是来源侧的排布事实，跟随来源。
    imagePath: _normalizeText(draft.imagePath),
    servingWindow: _normalizeText(draft.servingWindow),
    isHot: draft.isHot,
    fiberG: existing.fiberG,
    sodiumMg: existing.sodiumMg,
    vitaminDMcg: existing.vitaminDMcg,
    comment: _normalizeText(draft.comment),
    servingGrams: draft.servingGrams,
    basisAssumed: draft.servingGrams == null,
    sourceType: draft.sourceType,
    sourceId: draft.sourceId,
    // 来源证据时间**不动**：动了会让「来源有更新」的陈旧判定以为已同步。
    sourceUpdatedAt: existing.sourceUpdatedAt,
    userEdited: true,
  );

  /// 按来源删除（来源菜被删 → 同源行跟随删除；一个库不留幽灵）。
  /// 幂等：没有同源行时返回 false。
  Future<bool> deleteBySource({
    required String sourceType,
    required String sourceId,
  }) async {
    final deleted =
        await (database.delete(database.dishLibrary)..where(
              (row) =>
                  row.sourceType.equals(sourceType) &
                  row.sourceId.equals(sourceId),
            ))
            .go();
    return deleted > 0;
  }

  /// `upsertByName` / `upsertBySource` 共用的「保留 id 与 createdAt、
  /// 其余按草稿覆盖」行构造。
  DishRecord _updated(
    DishLibraryEntry existing,
    DishDraft draft,
    String name,
  ) => DishRecord(
    id: existing.id,
    name: name,
    mealSlot: draft.mealSlot,
    kcal: draft.kcal,
    proteinG: draft.proteinG,
    carbsG: draft.carbsG,
    fatG: draft.fatG,
    source: draft.source,
    createdAt: existing.createdAt,
    updatedAt: clock.nowUtc(),
    imagePath: _normalizeText(draft.imagePath),
    servingWindow: _normalizeText(draft.servingWindow),
    isHot: draft.isHot,
    fiberG: draft.fiberG,
    sodiumMg: draft.sodiumMg,
    vitaminDMcg: draft.vitaminDMcg,
    comment: _normalizeText(draft.comment),
    servingGrams: draft.servingGrams,
    basisAssumed: draft.servingGrams == null,
    sourceType: draft.sourceType,
    sourceId: draft.sourceId,
    sourceUpdatedAt: draft.sourceUpdatedAt,
    // **只置位、不清零**：自动同步（食堂菜每次写入都会 upsert）不能把用户
    // 「我手改过这一行」的标记抹掉——那是「以后别自动覆盖我」的唯一凭据。
    // 老实现无条件写 `draft.userEdited`（草稿默认 false），一个自动同步就会
    // 静默清掉它（2026-10-24 复核时抓到）。
    userEdited: existing.userEdited || draft.userEdited,
  );

  /// 把来源（食堂菜）最新营养同步进这一行（docs/40 §6 的「同步」动作）。
  ///
  /// 只改营养四值与 `sourceUpdatedAt`：**份量模板 `servingGrams` 不动**——
  /// 那是用户的份量，不是来源的事实。`userEdited` 的拦截在 `DishSourceSync`
  /// （策略与写分离，仓储只做一次写）。
  Future<DishRecord> updateNutritionFromSource({
    required String id,
    required double kcal,
    required double proteinG,
    required double carbsG,
    required double fatG,
    required DateTime sourceUpdatedAt,
  }) async {
    await (database.update(
      database.dishLibrary,
    )..where((row) => row.id.equals(id))).write(
      DishLibraryCompanion(
        kcal: Value(kcal),
        proteinG: Value(proteinG),
        carbsG: Value(carbsG),
        fatG: Value(fatG),
        sourceUpdatedAt: Value(sourceUpdatedAt),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
    final row = await (database.select(
      database.dishLibrary,
    )..where((row) => row.id.equals(id))).getSingle();
    return _map(row);
  }

  /// 把菜品库的一行关联到食堂菜（docs/40 §4「确认后才生效」）。
  ///
  /// 关联后 `sourceUpdatedAt` 先对齐到来源的 `updatedAt`：刚建立的链接
  /// 不应该立刻显示「有更新」——用户还没做任何同步动作。
  ///
  /// 已关联到**另一条**食堂菜时拒绝（[FormatException]）：同名不同窗口是
  /// 正常情况，但「一道菜同时指向两个来源」会让陈旧判定失去唯一答案。
  Future<DishRecord> linkSource({
    required String id,
    required String sourceType,
    required String sourceId,
    required DateTime sourceUpdatedAt,
  }) async {
    final row =
        await (database.select(database.dishLibrary)
              ..where((item) => item.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      throw const FormatException('菜品不存在，可能已被删除。');
    }
    final existing = row.sourceId;
    if (existing != null && existing.isNotEmpty && existing != sourceId) {
      throw const FormatException('这道菜已关联另一个食堂菜品。');
    }
    await (database.update(
      database.dishLibrary,
    )..where((item) => item.id.equals(id))).write(
      DishLibraryCompanion(
        sourceType: Value(sourceType),
        sourceId: Value(sourceId),
        sourceUpdatedAt: Value(sourceUpdatedAt),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
    final updated = await (database.select(
      database.dishLibrary,
    )..where((item) => item.id.equals(id))).getSingle();
    return _map(updated);
  }

  /// 只把 `sourceUpdatedAt` 对齐到来源（同步后「不再陈旧」的落点；
  /// 也用于把一条已有菜品挂到来源上）。
  Future<void> updateSourceUpdatedAt({
    required String id,
    required DateTime sourceUpdatedAt,
  }) async {
    await (database.update(database.dishLibrary)
          ..where((row) => row.id.equals(id)))
        .write(DishLibraryCompanion(sourceUpdatedAt: Value(sourceUpdatedAt)));
  }

  /// 删除一道菜，返回被删除的记录（不存在返回 null，供撤销使用）。
  Future<DishRecord?> delete(String id) async {
    final row =
        await (database.select(database.dishLibrary)
              ..where((row) => row.id.equals(id))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    await (database.delete(
      database.dishLibrary,
    )..where((row) => row.id.equals(id))).go();
    return _map(row);
  }

  /// 回写一条记录（撤销删除用）。
  Future<void> restore(DishRecord record) async {
    await database
        .into(database.dishLibrary)
        .insertOnConflictUpdate(
          DishLibraryCompanion.insert(
            id: record.id,
            name: record.name,
            mealSlot: record.mealSlot,
            kcal: record.kcal,
            proteinG: record.proteinG,
            carbsG: record.carbsG,
            fatG: record.fatG,
            source: record.source,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            imagePath: Value(record.imagePath),
            servingWindow: Value(record.servingWindow),
            isHot: Value(record.isHot),
            fiberG: Value(record.fiberG),
            sodiumMg: Value(record.sodiumMg),
            vitaminDMcg: Value(record.vitaminDMcg),
            comment: Value(record.comment),
            // schema 28 的列也要回写：撤销删除不能把份量与来源丢掉
            // （否则「撤销」回来的是另一道菜——份量变假设、陈旧提示消失）。
            servingGrams: Value(record.servingGrams),
            basisAssumed: Value(record.basisAssumed),
            sourceType: Value(record.sourceType),
            sourceId: Value(record.sourceId),
            sourceUpdatedAt: Value(record.sourceUpdatedAt),
            userEdited: Value(record.userEdited),
          ),
        );
  }

  DishRecord _map(DishLibraryEntry row) => DishRecord(
    id: row.id,
    name: row.name,
    mealSlot: row.mealSlot,
    kcal: row.kcal,
    proteinG: row.proteinG,
    carbsG: row.carbsG,
    fatG: row.fatG,
    source: row.source,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    imagePath: row.imagePath,
    servingWindow: row.servingWindow,
    isHot: row.isHot,
    fiberG: row.fiberG,
    sodiumMg: row.sodiumMg,
    vitaminDMcg: row.vitaminDMcg,
    comment: row.comment,
    servingGrams: row.servingGrams,
    basisAssumed: row.basisAssumed,
    sourceType: row.sourceType,
    sourceId: row.sourceId,
    sourceUpdatedAt: row.sourceUpdatedAt,
    userEdited: row.userEdited,
  );
}

/// 新增菜品的草稿（`source` 由调用方给：用户自建 vs AI 生成）。
final class DishDraft {
  const DishDraft({
    required this.name,
    required this.mealSlot,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.source,
    this.imagePath,
    this.servingWindow,
    this.isHot = false,
    this.fiberG,
    this.sodiumMg,
    this.vitaminDMcg,
    this.comment,
    this.servingGrams,
    this.nutritionBasis = 'perServing',
    this.sourceType,
    this.sourceId,
    this.sourceUpdatedAt,
    this.userEdited = false,
  });

  final String name;
  final String mealSlot;
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final String source;
  final String? imagePath;
  final String? servingWindow;
  final bool isHot;
  final double? fiberG;
  final double? sodiumMg;
  final double? vitaminDMcg;
  final String? comment;

  // ── schema 28（docs/40 §2.1）：份量口径与来源 ────────────────────────
  /// 一份多少克（null = 份量未知，落库时按 100g 假设并标 `basisAssumed`）。
  final double? servingGrams;

  /// `perServing` | `per100g`（null 按 perServing）。
  final String nutritionBasis;

  /// `canteen` | `food` | `manual` | `imported`。
  final String? sourceType;

  /// menuItemId / foodId（允许来源删除后悬空）。
  final String? sourceId;

  /// 来源最后一次营养变更时间（同步提示用）。
  final DateTime? sourceUpdatedAt;

  /// 用户手改过营养/份量（同步时不覆盖）。
  final bool userEdited;
}
