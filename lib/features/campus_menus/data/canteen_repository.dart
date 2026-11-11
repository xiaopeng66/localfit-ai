import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/core/validation/entity_name.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/dish_image_store.dart';
import 'package:localfit_ai/features/campus_menus/domain/ingredients.dart';
import 'package:localfit_ai/features/campus_menus/domain/master_nutrition_sink.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';

/// 食堂营养证据允许的 `origin` 三档（docs/40 §3.1）。
///
/// 单一事实源：仓库校验与界面文案都读它，避免「写入允许第四种、
/// 界面只认识三种」这种会静默丢来源的漂移。
const Set<String> kCanteenNutritionOrigins = {
  'ai_estimate',
  'food_library',
  'user_input',
};

/// 食堂目录（3.0 起）：**地点 → 窗口 → 菜品** 三级自建结构，
/// 取代「导入菜单文件 → 生成快照」的旧路径。
///
/// 为什么不用快照：导入一次菜单只描述「某一天某窗口有什么」，用户真正
/// 需要维护的是**常驻结构**（我在哪几个地点吃饭、每个地点有哪些窗口、
/// 每个窗口常卖哪些菜）。每日推荐需要的是后者的稳定事实。
///
/// 三者复用既有 venues/menu_services/menu_items 三张表，用一个内部
/// 快照行（[catalogSnapshotIdFor]）作为父节点承接外键——旧表的
/// business_date / 退位 / 原文许可语义对自建目录不适用，但表结构
/// （名称/时段/价格/等级/状态）完全吻合，重建三张表只会让
/// daily_plan / 备份 / 清除全量数据的既有接线全部重写。
///
/// 写库范围严格限定在菜单四表 + 证据表，**绝不写 meals**（推荐不写已吃）。
///
/// 刻意**非 final**：`menu_tab_view_test` 用门控子类卡住 `listWindows`，
/// 验证「刷新中继续画旧列表 + 细进度条」（docs/29 §P7 需求 18 的
/// stale-while-revalidate 路径）；本类没有继承链，开放继承无风险。
class CanteenRepository {
  CanteenRepository({
    required this.database,
    required this.idGenerator,
    required this.clock,
    this.dishImageStore,
    this.masterNutritionSink,
  });

  static const _catalogSnapshotSuffix = 'canteen-catalog';

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 菜品照片的文件清理（docs/29 §P7 需求 16）；null＝不清理（测试或
  /// 未接线的装配），只影响孤儿文件，不影响数据正确性。
  final DishImageStore? dishImageStore;

  /// 批准后的当前营养**唯一的落点**（docs/67 §3.2）。
  ///
  /// 供应自己只保留分析证据（`menu_item_nutrition_evidence`，是可追溯的
  /// 分析记录）；当前生效值写进主食物的修订。null = 未接线（单测/纯目录
  /// 读写），此时只写证据，不假装已经更新了主库。
  ///
  /// 端口定义在 campus_menus/domain，实现在 nutrition；依赖方向不反转。
  final MasterNutritionSink? masterNutritionSink;

  /// 某个食堂的自建目录快照 id（内部父节点，不参与「新鲜度」语义）。
  static String catalogSnapshotIdFor(String venueId) =>
      'menu-snapshot-$_catalogSnapshotSuffix-$venueId';

  /// **目录相关表的变更流**（2026-10-16 设备实测补）。
  ///
  /// 由来：用户在「食堂目录」里点「AI 分析」→ 到对话里应用 `canteen.dish.nutrition`
  /// → 返回目录时那张**还活着的页面实例**仍显示旧数据（行上写着「未分析营养」、
  /// 统计写「0 道 已分析」），而那顿营养其实已经落库。用户看到的结论正好相反
  /// （以为分析失败了）。目录页订阅这个流，任何一端写入都自动刷新。
  ///
  /// 覆盖四张表：菜品（名称/照片/档口）、营养证据（等级与数值）、窗口、地点。
  Stream<void> watchDirectory() => database
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          database.menuItems,
          database.menuItemNutritionEvidence,
          database.menuServices,
          database.venues,
        ]),
      )
      .map((_) {});

  // ── 地点（venue）────────────────────────────────────────────────────

  /// 全部食堂，按校园、再按名称排序（每个食堂就是一个「地点」）。
  ///
  /// 2026-10-18（docs/41 §9 G18）：三级装配从「逐地点拉窗口、逐窗口拉菜品
  /// （1 + V·(1 + W·2) 条查询）」改为**固定 5 条**查询在内存里装配——快照
  /// 装配与页面首屏共用这条路， venue/window 数量增长不再放大查询数。
  /// 计数口径（`windowCount` / `dishCount` / `analyzedCount`）与旧实现一致，
  /// 由同一批内存数据算出。
  Future<List<CanteenVenue>> listVenues() async {
    final rows =
        await (database.select(database.venues)..orderBy([
              (row) => OrderingTerm.asc(row.campusId),
              (row) => OrderingTerm.asc(row.name),
            ]))
            .get();
    if (rows.isEmpty) return const [];
    final campusRows = await database.select(database.campusProfiles).get();
    final campusNames = {
      for (final campus in campusRows) campus.id: campus.name,
    };
    final windowsByVenue = await listWindowsByVenue(
      venueIds: [for (final row in rows) row.id],
    );
    final result = <CanteenVenue>[];
    for (final row in rows) {
      final windows = windowsByVenue[row.id] ?? const <CanteenWindow>[];
      final dishCount = windows.fold<int>(
        0,
        (sum, window) => sum + window.dishes.length,
      );
      final analyzedCount = windows.fold<int>(
        0,
        (sum, window) =>
            sum + window.dishes.where((dish) => dish.hasNutrition).length,
      );
      result.add(
        CanteenVenue(
          id: row.id,
          campusId: row.campusId,
          campusName: campusNames[row.campusId] ?? '未命名校园',
          name: row.name,
          notes: row.notes,
          windowCount: windows.length,
          dishCount: dishCount,
          analyzedCount: analyzedCount,
        ),
      );
    }
    return result;
  }

  /// 一批地点的窗口树（含每窗口菜品与最新营养证据）。
  ///
  /// 固定 **3 条**查询（窗口 / 菜品 / 证据），在内存里按归属装配；
  /// [listWindows] 与 [listVenues] 都委托它，消除逐窗口的 N+1
  /// （docs/41 §9 G18 的食堂三级查询消解）。
  Future<Map<String, List<CanteenWindow>>> listWindowsByVenue({
    List<String>? venueIds,
  }) async {
    final ids = venueIds;
    final snapshotIds = <String, String>{
      for (final venueId in ids ?? const <String>[])
        catalogSnapshotIdFor(venueId): venueId,
    };
    final windowRows =
        await (database.select(database.menuServices)
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
              ..where(
                (row) => snapshotIds.isEmpty
                    ? row.snapshotId.like(
                        'menu-snapshot-$_catalogSnapshotSuffix-%',
                      )
                    : row.snapshotId.isIn(snapshotIds.keys.toList()),
              ))
            .get();
    if (windowRows.isEmpty) return const {};
    final dishRows =
        await (database.select(database.menuItems)
              ..where(
                (row) => row.serviceId.isIn([
                  for (final window in windowRows) window.id,
                ]),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    final evidenceRows = dishRows.isEmpty
        ? const <MenuItemNutritionEvidenceData>[]
        : await (database.select(database.menuItemNutritionEvidence)
                ..where(
                  (row) => row.menuItemId.isIn([
                    for (final dish in dishRows) dish.id,
                  ]),
                )
                ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
              .get();
    final evidenceByItem = <String, MenuItemNutritionEvidenceData>{};
    for (final evidence in evidenceRows) {
      evidenceByItem.putIfAbsent(evidence.menuItemId, () => evidence);
    }
    final dishesByWindow = <String, List<CanteenDish>>{};
    final masterById = await _masterFoodsFor(dishRows);
    for (final row in dishRows) {
      (dishesByWindow[row.serviceId] ??= []).add(
        _dishOf(
          row,
          evidence: evidenceByItem[row.id],
          master: row.foodId == null ? null : masterById[row.foodId],
        ),
      );
    }
    final result = <String, List<CanteenWindow>>{};
    for (final row in windowRows) {
      final venueId =
          snapshotIds[row.snapshotId] ??
          // 快照行不属于入参地点（不该发生；按后缀兜底解析，绝不串数据）。
          _venueIdFromSnapshotId(row.snapshotId);
      if (venueId == null) continue;
      (result[venueId] ??= []).add(
        CanteenWindow(
          id: row.id,
          venueId: venueId,
          name: row.name,
          openTime: row.openTime,
          closeTime: row.closeTime,
          dishes: dishesByWindow[row.id] ?? const <CanteenDish>[],
        ),
      );
    }
    return result;
  }

  /// 一次批量取「供应链接的主食物」（docs/67 §3.3）：固定 1 条查询，
  /// 不随供应条数增长。
  Future<Map<String, Food>> _masterFoodsFor(List<MenuItem> rows) async {
    final foodIds = {
      for (final row in rows)
        if (row.foodId != null) row.foodId!,
    };
    if (foodIds.isEmpty) return const {};
    final masterRows = await (database.select(
      database.foods,
    )..where((t) => t.id.isIn(foodIds))).get();
    return {for (final food in masterRows) food.id: food};
  }

  /// `MenuItems` 行 → [CanteenDish] 的**唯一映射**。
  ///
  /// 两个读取口（单窗口 `listDishes` / 批量 `listWindowsByVenue`）必须共用它：
  /// 各写一遍时「主食物派生」只在其中一个里生效，地点统计就会显示
  /// 「已分析 0」而列表里明明有营养（本轮实测踩到）。
  CanteenDish _dishOf(
    MenuItem row, {
    required MenuItemNutritionEvidenceData? evidence,
    required Food? master,
  }) => CanteenDish(
    id: row.id,
    windowId: row.serviceId,
    name: row.displayName,
    stationName: row.stationName,
    imagePath: row.imagePath,
    evidenceGrade: row.evidenceGrade,
    itemStatus: row.itemStatus,
    evidence: evidence,
    servingGrams: row.servingGrams,
    tags: decodeCanteenTags(row.tagsJson),
    ingredients: CanteenIngredientInfo.decode(row.ingredientsJson),
    foodId: row.foodId,
    masterPer100g: _masterValuesOf(master),
  );

  /// 主食物的每 100g 四项；不完整返回 null（**不填零**）。
  static ({double kcal, double protein, double carbs, double fat})?
  _masterValuesOf(Food? food) {
    if (food == null) return null;
    if (!isCompleteNutrition(
      kcalPer100g: food.kcalPer100g,
      proteinPer100g: food.proteinPer100g,
      carbsPer100g: food.carbsPer100g,
      fatPer100g: food.fatPer100g,
    )) {
      return null;
    }
    return (
      kcal: food.kcalPer100g,
      protein: food.proteinPer100g,
      carbs: food.carbsPer100g,
      fat: food.fatPer100g,
    );
  }

  /// `catalogSnapshotIdFor` 的逆解析；格式不对（老数据/脏行）返回 null，
  /// 调用侧跳过该窗口而不是把它挂到错误的地点。
  String? _venueIdFromSnapshotId(String snapshotId) {
    final marker = 'menu-snapshot-$_catalogSnapshotSuffix-';
    if (!snapshotId.startsWith(marker)) return null;
    final venueId = snapshotId.substring(marker.length);
    return venueId.isEmpty ? null : venueId;
  }

  /// 新建地点。校园按名称 find-or-create（2.0 范围单校园，多校园归后续）。
  Future<String> createVenue({
    required String name,
    required String campusName,
  }) async {
    final venueName = name.trim();
    if (venueName.isEmpty) {
      throw const CanteenWriteException('地点名称不能为空。');
    }
    validatedEntityName(venueName, label: '地点名称');
    final campus = await _findOrCreateCampus(campusName.trim());
    final now = clock.nowUtc();
    final id = idGenerator.next();
    await database
        .into(database.venues)
        .insert(
          VenuesCompanion.insert(
            id: id,
            campusId: campus.id,
            name: venueName,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await _ensureCatalogSnapshot(id, campus.id);
    return id;
  }

  Future<void> renameVenue(String venueId, String name) async {
    final trimmed = name.trim();
    // 空名保持 CanteenWriteException（UI 与 AI 都按它翻人话）；超长走统一校验。
    if (trimmed.isEmpty) {
      throw const CanteenWriteException('地点名称不能为空。');
    }
    validatedEntityName(trimmed, label: '地点名称');
    await (database.update(
      database.venues,
    )..where((row) => row.id.equals(venueId))).write(
      VenuesCompanion(name: Value(trimmed), updatedAt: Value(clock.nowUtc())),
    );
  }

  /// 删除地点：窗口/菜品/证据/所有菜单快照随地点一起删除。
  ///
  /// `menu_snapshots.venueId` 没有级联（历史导入/AI 快照也可能存在），所以
  /// 必须先删除**地点名下全部快照**，不能只删本仓库生成的 catalog snapshot。
  Future<void> deleteVenue(String venueId) async {
    await database.transaction(() async {
      await (database.delete(
        database.menuSnapshots,
      )..where((row) => row.venueId.equals(venueId))).go();
      // sourceId 不是级联到 venue 的关系；快照删除后再删来源，避免留下空来源。
      await (database.delete(
        database.menuSources,
      )..where((row) => row.venueId.equals(venueId))).go();
      final deleted = await (database.delete(
        database.venues,
      )..where((row) => row.id.equals(venueId))).go();
      if (deleted != 1) {
        throw StateError('食堂地点不存在或已被删除。');
      }
    });
  }

  // ── 窗口（menu_service）──────────────────────────────────────────────

  /// 一个地点的窗口列表（委托 [listWindowsByVenue]，与批量路径同一装配）。
  Future<List<CanteenWindow>> listWindows(String venueId) async {
    final map = await listWindowsByVenue(venueIds: [venueId]);
    return map[venueId] ?? const <CanteenWindow>[];
  }

  Future<String> createWindow({
    required String venueId,
    required String name,
    required String openTime,
    required String closeTime,
  }) async {
    final windowName = name.trim();
    if (windowName.isEmpty) {
      throw const CanteenWriteException('窗口名称不能为空。');
    }
    validatedEntityName(windowName, label: '窗口名称');
    _requireHhmm(openTime, '开始时间');
    _requireHhmm(closeTime, '结束时间');
    if (_minuteOf(closeTime) <= _minuteOf(openTime)) {
      throw const CanteenWriteException('结束时间要晚于开始时间。');
    }
    final venue = await _venueOrThrow(venueId);
    await _ensureCatalogSnapshot(venueId, venue.campusId);
    final now = clock.nowUtc();
    final id = idGenerator.next();
    await database
        .into(database.menuServices)
        .insert(
          MenuServicesCompanion.insert(
            id: id,
            snapshotId: catalogSnapshotIdFor(venueId),
            name: windowName,
            openTime: openTime,
            closeTime: closeTime,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// 删除窗口：菜品与营养证据级联删除。
  Future<void> deleteWindow(String windowId) async {
    await (database.delete(
      database.menuServices,
    )..where((row) => row.id.equals(windowId))).go();
  }

  // ── 菜品（menu_item）────────────────────────────────────────────────

  Future<List<CanteenDish>> listDishes(String windowId) async {
    final rows =
        await (database.select(database.menuItems)
              ..where((row) => row.serviceId.equals(windowId))
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    return _mapDishes(rows);
  }

  /// 同窗口内按**精确名**找菜；找不到返回 null（AI 建菜查重用）。
  ///
  /// 判据 = trim 后全等：窗口内同名就是同一道菜，不猜、不模糊。
  Future<CanteenDish?> findDishInWindow({
    required String windowId,
    required String name,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final dishes = await listDishes(windowId);
    for (final dish in dishes) {
      if (dish.name.trim() == trimmed) return dish;
    }
    return null;
  }

  /// 菜单项行 → [CanteenDish]（含每项**最新**一条营养证据）。
  /// `listDishes` 与 `findDish` 共用：两处各映射一遍迟早会漂（一个有
  /// servingGrams、一个没有）。
  Future<List<CanteenDish>> _mapDishes(List<MenuItem> rows) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((row) => row.id).toList();
    // 一次取全部证据（避免逐条查询），取每项「最新」一条。
    final evidenceRows =
        await (database.select(database.menuItemNutritionEvidence)
              ..where((row) => row.menuItemId.isIn(ids))
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    final evidenceByItem = <String, MenuItemNutritionEvidenceData>{};
    for (final evidence in evidenceRows) {
      evidenceByItem.putIfAbsent(evidence.menuItemId, () => evidence);
    }
    final masterById = await _masterFoodsFor(rows);
    return [
      for (final row in rows)
        _dishOf(
          row,
          evidence: evidenceByItem[row.id],
          master: row.foodId == null ? null : masterById[row.foodId],
        ),
    ];
  }

  /// 新增菜品；[DishDraft.grams] 是「这一份」的克重，用于把每 100g
  /// 营养换算成这一份的展示值（不写库，展示时算）。
  ///
  /// [imagePath]（docs/29 §P7 需求 16）是 `DishImageStore` 复制进私有
  /// 目录后的路径；null＝无照片。
  Future<String> createDish({
    required String windowId,
    required String name,
    String? stationName,
    String? imagePath,
    String? foodId,
    double? servingGrams,
    // 给了克数就当"已知"（调用方是在这一步明确填的）；null 才退回 unknown。
    ServingGramsStatus? servingGramsStatus,
    ServingGramsSource servingGramsSource = ServingGramsSource.userInput,
  }) async {
    final dishName = name.trim();
    if (dishName.isEmpty) {
      throw const CanteenWriteException('菜品名称不能为空。');
    }
    validatedEntityName(dishName, label: '菜品名称');
    final window =
        await (database.select(database.menuServices)
              ..where((row) => row.id.equals(windowId))
              ..limit(1))
            .getSingleOrNull();
    if (window == null) {
      throw const CanteenWriteException('窗口不存在，可能已被删除。');
    }
    // 2026-11-11 复核：同窗口同名两行会让按名定位（AI 的 window+name、
    // 「直接引用已有供应」）静默选中其中一行——可能写错菜。建菜就拒绝重名。
    final duplicate =
        await (database.select(database.menuItems)
              ..where(
                (row) =>
                    row.serviceId.equals(windowId) &
                    row.displayName.equals(dishName),
              )
              ..limit(1))
            .getSingleOrNull();
    if (duplicate != null) {
      throw CanteenWriteException('这个窗口里已有同名菜品「$dishName」；要补份量/营养请直接改那一条。');
    }
    final now = clock.nowUtc();
    final id = idGenerator.next();
    await database
        .into(database.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: id,
            serviceId: windowId,
            displayName: dishName,
            stationName: Value(stationName?.trim()),
            imagePath: Value(imagePath),
            // 自建目录里菜名是用户输入的事实（不是从 AI 草案猜出来的）。
            evidenceGrade: const Value('C'),
            itemStatus: Value(foodId == null ? 'unresolved' : 'estimated'),
            createdAt: now,
            updatedAt: now,
            foodId: Value(foodId),
            servingGrams: Value(servingGrams),
            servingGramsStatus: Value(
              servingGrams == null
                  ? ServingGramsStatus.unknown.storedValue
                  : (servingGramsStatus ?? ServingGramsStatus.known)
                        .storedValue,
            ),
            servingGramsSource: Value(servingGramsSource.storedValue),
          ),
        );
    return id;
  }

  /// 更新菜品。[setImagePath] 为 false 时照片列不动（用户没碰照片字段）；
  /// 为 true 时按 [imagePath] 覆盖（null＝移除照片），旧文件不同则尽力
  /// 删除（孤儿文件好过写库失败）。
  Future<void> updateDish({
    required String dishId,
    required String name,
    String? imagePath,
    bool setImagePath = false,
  }) async {
    final dishName = name.trim();
    if (dishName.isEmpty) {
      throw const CanteenWriteException('菜品名称不能为空。');
    }
    validatedEntityName(dishName, label: '菜品名称');
    // 2026-11-11 复核：改名撞上同窗口已有名字会造出两行同名，之后按名定位
    // （AI 的 window+name、建菜去重）只能拿到其中一行——静默写错对象。
    final current =
        await (database.select(database.menuItems)
              ..where((row) => row.id.equals(dishId))
              ..limit(1))
            .getSingleOrNull();
    if (current == null) {
      throw const CanteenWriteException('菜品不存在，可能已被删除。');
    }
    if (dishName != current.displayName) {
      final duplicate =
          await (database.select(database.menuItems)
                ..where(
                  (row) =>
                      row.serviceId.equals(current.serviceId) &
                      row.displayName.equals(dishName) &
                      row.id.equals(dishId).not(),
                )
                ..limit(1))
              .getSingleOrNull();
      if (duplicate != null) {
        throw CanteenWriteException('这个窗口里已有同名菜品「$dishName」；换个名字或直接改那一条。');
      }
    }
    if (setImagePath) {
      final old = await (database.select(
        database.menuItems,
      )..where((row) => row.id.equals(dishId))).getSingleOrNull();
      final oldPath = old?.imagePath;
      if (oldPath != imagePath && dishImageStore != null) {
        await dishImageStore!.deleteQuietly(oldPath);
      }
    }
    await (database.update(
      database.menuItems,
    )..where((row) => row.id.equals(dishId))).write(
      MenuItemsCompanion(
        displayName: Value(dishName),
        imagePath: setImagePath ? Value(imagePath) : const Value.absent(),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
  }

  /// 写入结构化标签与配料（docs/40 §2.5）：用户编辑走这条；AI 起草走
  /// [CanteenIngredientInfo.mergeAi] 后同样落这条（用户条目不会被覆盖）。
  Future<void> updateDishTagsAndIngredients({
    required String dishId,
    required List<String> tags,
    required CanteenIngredientInfo ingredients,
    double? servingGrams,
    bool setServingGrams = false,
  }) async {
    await (database.update(
      database.menuItems,
    )..where((row) => row.id.equals(dishId))).write(
      MenuItemsCompanion(
        tagsJson: Value(encodeCanteenTags(tags)),
        ingredientsJson: Value(ingredients.encode()),
        servingGrams: setServingGrams
            ? Value(servingGrams)
            : const Value.absent(),
        servingGramsStatus: setServingGrams
            ? Value(
                servingGrams == null
                    ? ServingGramsStatus.unknown.storedValue
                    : ServingGramsStatus.known.storedValue,
              )
            : const Value.absent(),
        servingGramsSource: setServingGrams
            ? Value(
                servingGrams == null
                    ? ServingGramsSource.legacyUnknown.storedValue
                    : ServingGramsSource.userInput.storedValue,
              )
            : const Value.absent(),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
  }

  /// 唯一的「已确认匹配」写法：先清掉该供应的旧匹配，再写一条 confirmed。
  ///
  /// 权威链接只有 `menu_items.food_id` 一个；匹配表是历史/审计视图。两处写入
  /// 必须共用这一段，避免出现"两条 confirmed 不知用哪条"。
  Future<void> _writeConfirmedMatch({
    required String menuItemId,
    required String foodId,
    required DateTime now,
  }) async {
    await (database.delete(
      database.menuItemFoodMatches,
    )..where((row) => row.menuItemId.equals(menuItemId))).go();
    await database
        .into(database.menuItemFoodMatches)
        .insert(
          MenuItemFoodMatchesCompanion.insert(
            id: idGenerator.next(),
            menuItemId: menuItemId,
            foodId: foodId,
            confidence: const Value(1),
            matchStatus: const Value('confirmed'),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 把供应链接到统一主库的一条食物（docs/67 §3.3、§5.2）。
  ///
  /// 链接后当前营养**从主食物生效修订派生**，不再复制一份到证据表；
  /// 匹配表同时置 confirmed，保证"唯一权威链接"只有一个说法。
  Future<void> linkSupplyToFood({
    required String dishId,
    required String foodId,
  }) async {
    final food =
        await (database.select(database.foods)
              ..where((row) => row.id.equals(foodId))
              ..limit(1))
            .getSingleOrNull();
    if (food == null) {
      throw const CanteenWriteException('要引用的食物不存在。');
    }
    if (food.archivedAt != null) {
      throw const CanteenWriteException('这条食物已归档，不能新挂窗。');
    }
    await database.transaction(() async {
      final updated =
          await (database.update(
            database.menuItems,
          )..where((row) => row.id.equals(dishId))).write(
            MenuItemsCompanion(
              foodId: Value(foodId),
              itemStatus: const Value('estimated'),
              evidenceGrade: const Value('B'),
              updatedAt: Value(clock.nowUtc()),
            ),
          );
      if (updated == 0) {
        throw const CanteenWriteException('菜品不存在，可能已被删除。');
      }
      await _writeConfirmedMatch(
        menuItemId: dishId,
        foodId: foodId,
        now: clock.nowUtc(),
      );
    });
  }

  /// 只改「一份多少克」：不动标签/配料/照片。
  ///
  /// `null` = 清空（回到「按 100g 估算」）；有值时菜品库的「每份」会按
  /// `per100g × grams / 100` 重算。用户不填就保持未知，不替用户编份量。
  Future<void> updateDishServingGrams(String dishId, double? grams) async {
    if (grams != null && (!grams.isFinite || grams <= 0 || grams > 2000)) {
      throw const CanteenWriteException('一份的克数要填 0–2000 之间的数字。');
    }
    final updated =
        await (database.update(
          database.menuItems,
        )..where((row) => row.id.equals(dishId))).write(
          MenuItemsCompanion(
            servingGrams: Value(grams),
            // 用户在这一步亲手填的克数才算"已知"；清空回到 unknown。
            servingGramsStatus: Value(
              grams == null
                  ? ServingGramsStatus.unknown.storedValue
                  : ServingGramsStatus.known.storedValue,
            ),
            servingGramsSource: Value(
              grams == null
                  ? ServingGramsSource.legacyUnknown.storedValue
                  : ServingGramsSource.userInput.storedValue,
            ),
            updatedAt: Value(clock.nowUtc()),
          ),
        );
    if (updated == 0) {
      throw const CanteenWriteException('菜品不存在，可能已被删除。');
    }
  }

  /// 删除菜品：营养证据级联删除；照片文件尽力清理（store 未接线时只
  /// 删行，文件由系统存储清理兜底）。
  Future<void> deleteDish(String dishId) async {
    if (dishImageStore != null) {
      final row = await (database.select(
        database.menuItems,
      )..where((row) => row.id.equals(dishId))).getSingleOrNull();
      await dishImageStore!.deleteQuietly(row?.imagePath);
    }
    await (database.delete(
      database.menuItems,
    )..where((row) => row.id.equals(dishId))).go();
    // 菜品库的同源行跟着删（一个库不留幽灵）。
  }

  /// 该窗口内、尚未做营养分析的菜品（AI 分析入口的输入集合）。
  Future<List<CanteenDish>> listDishesNeedingAnalysis(String windowId) async {
    final dishes = await listDishes(windowId);
    return [
      for (final dish in dishes)
        if (!dish.hasNutrition) dish,
    ];
  }

  /// 写入营养结果：营养证据 + 等级 + 状态。
  ///
  /// 单调递增的 `createdAt` 让「最新证据」在 [listDishes] 里稳定胜出；
  /// 同一菜品重复分析会留下多条历史证据（可追溯），读取只看最新。
  ///
  /// [origin]（docs/40 §3.1 三档来源，2026-10-18 加法）：
  /// * `ai_estimate`（缺省，旧行为逐字不变）——AI 分析；
  /// * `food_library`——引用食物库同名条目的每 100g 事实；
  /// * `user_input`——用户手填（无 AI 可用时的唯一营养来源）。
  /// 三档**不合并**：界面上必须分得开「引用 / 估算 / 自填」。
  Future<void> recordNutrition({
    required String dishId,
    required double kcalPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    required String grade,
    required double confidence,
    double? kcalMin,
    double? kcalMax,
    String? sourceText,
    String origin = 'ai_estimate',
    double? servingGramsEstimate,
  }) async {
    if (!const {'A', 'B', 'C', 'D'}.contains(grade)) {
      throw const CanteenWriteException('证据等级只能是 A/B/C/D。');
    }
    if (!kCanteenNutritionOrigins.contains(origin)) {
      throw const CanteenWriteException('营养来源只能是 AI 估算 / 食物库引用 / 用户输入。');
    }
    final item = await (database.select(
      database.menuItems,
    )..where((row) => row.id.equals(dishId))).getSingleOrNull();
    if (item == null) {
      throw const CanteenWriteException('菜品不存在，可能已被删除。');
    }
    validateDishNutrition(
      name: item.displayName,
      kcal: kcalPer100g,
      proteinG: proteinPer100g,
      carbsG: carbsPer100g,
      fatG: fatPer100g,
    );
    if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      throw const CanteenWriteException('置信度必须在 0–1 之间。');
    }
    // 2026-11-11（用户：「分析完推荐里没有这道菜」）：分析顺带把 AI 估的
    // 每份克数落成 estimated/ai_estimate，让供应有机会进宽松推荐池（显示
    // 「约」）。边界：已有可信份量（称重/用户填写/标签且 known）**不覆盖**
    // ——估算不能把可信事实改小。
    if (servingGramsEstimate != null &&
        (!servingGramsEstimate.isFinite ||
            servingGramsEstimate < 0.1 ||
            servingGramsEstimate > 2000)) {
      throw const CanteenWriteException('每份克数估算必须在 0.1–2000g 之间。');
    }
    if (kcalMin != null &&
        (!kcalMin.isFinite || kcalMin < 0 || kcalMin > 900)) {
      throw const CanteenWriteException('热量下限必须在 0–900 kcal 之间。');
    }
    if (kcalMax != null &&
        (!kcalMax.isFinite || kcalMax < 0 || kcalMax > 900)) {
      throw const CanteenWriteException('热量上限必须在 0–900 kcal 之间。');
    }
    if (kcalMin != null && kcalMax != null && kcalMin > kcalMax) {
      throw const CanteenWriteException('热量下限不能高于上限。');
    }
    final now = clock.nowUtc();
    await database.transaction(() async {
      // 证据时间必须严格晚于已有证据，否则「取最新」会稳定地选错行。
      final latest =
          await (database.select(database.menuItemNutritionEvidence)
                ..where((row) => row.menuItemId.equals(dishId))
                ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      var stamped = now;
      if (latest != null && !stamped.isAfter(latest.createdAt)) {
        stamped = latest.createdAt.add(const Duration(seconds: 1));
      }
      await database
          .into(database.menuItemNutritionEvidence)
          .insert(
            MenuItemNutritionEvidenceCompanion.insert(
              id: idGenerator.next(),
              menuItemId: dishId,
              grade: grade,
              origin: origin,
              kcalMin: Value(kcalMin),
              kcalMax: Value(kcalMax),
              kcalPer100g: Value(kcalPer100g),
              proteinPer100g: Value(proteinPer100g),
              carbsPer100g: Value(carbsPer100g),
              fatPer100g: Value(fatPer100g),
              sourceText: Value(sourceText),
              confidence: Value(confidence),
              createdAt: stamped,
              updatedAt: stamped,
            ),
          );
      // menu_items 没有营养列（营养一律在证据表），所以状态与等级写回
      // menu_items 只是给列表一个可过滤的标签：estimated + grade。
      await (database.update(
        database.menuItems,
      )..where((row) => row.id.equals(dishId))).write(
        MenuItemsCompanion(
          evidenceGrade: Value(grade),
          itemStatus: const Value('estimated'),
          updatedAt: Value(stamped),
        ),
      );

      // 批准后的当前营养只有一个生效位置：主食物的新修订。证据行是分析
      // 记录（可追溯），不是第二个当前事实。同一事务，失败一起回滚。
      final sink = masterNutritionSink;
      if (sink != null) {
        final linked =
            await (database.select(database.menuItems)
                  ..where((row) => row.id.equals(dishId))
                  ..limit(1))
                .getSingleOrNull();
        final values = ApprovedPer100g(
          kcalPer100g: kcalPer100g,
          proteinPer100g: proteinPer100g,
          carbsPer100g: carbsPer100g,
          fatPer100g: fatPer100g,
        );
        var foodId = linked?.foodId;
        if (foodId == null) {
          // 还没有主食物的供应被批准分析：**建库并链接**。否则目录按证据
          // 说「已分析」、记餐/推荐按主库说「待分析」，同一条供应两处读数
          // 打架（docs/67 §6.2）。
          foodId = await sink.createMasterFromAnalysis(
            displayName: linked?.displayName ?? '',
            values: values,
            origin: origin,
            isEstimated: origin == 'ai_estimate',
            rawValuesJson: sourceText,
          );
          if (foodId != null) {
            await (database.update(
              database.menuItems,
            )..where((row) => row.id.equals(dishId))).write(
              MenuItemsCompanion(
                foodId: Value(foodId),
                updatedAt: Value(stamped),
              ),
            );
            await _writeConfirmedMatch(
              menuItemId: dishId,
              foodId: foodId,
              now: stamped,
            );
          }
        } else {
          await sink.applyApprovedNutrition(
            foodId: foodId,
            values: values,
            origin: origin,
            isEstimated: origin == 'ai_estimate',
            rawValuesJson: sourceText,
          );
        }
      }
      // 份量估算与营养写入同一事务：失败一起回滚，不留「有营养没份量」的
      // 半截状态。已有可信份量（known + 称重/用户填写/标签）不覆盖。
      if (servingGramsEstimate != null) {
        // 2026-11-11 复核：状态说 known 但数值缺失（历史/脏数据）不算可信——
        // 否则估算永远写不进去，读侧还会对 null 做 `!`（实测 NPE）。
        final trustedKnown =
            item.servingGrams != null &&
            item.servingGrams! > 0 &&
            ServingGramsStatus.fromStored(item.servingGramsStatus) ==
                ServingGramsStatus.known &&
            ServingGramsSource.fromStored(item.servingGramsSource)
                .isTrustedBasis;
        if (!trustedKnown) {
          await (database.update(
            database.menuItems,
          )..where((row) => row.id.equals(dishId))).write(
            MenuItemsCompanion(
              servingGrams: Value(servingGramsEstimate),
              servingGramsStatus: Value(
                ServingGramsStatus.estimated.storedValue,
              ),
              servingGramsSource: Value(
                ServingGramsSource.aiEstimate.storedValue,
              ),
              updatedAt: Value(stamped),
            ),
          );
        }
      }
    });
  }

  /// 按 id 取一条菜品（含最新营养证据）；不存在返回 null。
  ///
  Future<CanteenDish?> findDish(String dishId) async {
    final row =
        await (database.select(database.menuItems)
              ..where((item) => item.id.equals(dishId))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    final dishes = await _mapDishes([row]);
    return dishes.isEmpty ? null : dishes.first;
  }

  // ── 内部 ────────────────────────────────────────────────────────────

  Future<CampusProfile> _findOrCreateCampus(String name) async {
    final effective = name.isEmpty ? '我的校园' : name;
    final existing =
        await (database.select(database.campusProfiles)
              ..where((row) => row.name.equals(effective))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing;
    final now = clock.nowUtc();
    final id = idGenerator.next();
    await database
        .into(database.campusProfiles)
        .insert(
          CampusProfilesCompanion.insert(
            id: id,
            name: effective,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await (database.select(
      database.campusProfiles,
    )..where((row) => row.id.equals(id))).getSingle());
  }

  Future<Venue> _venueOrThrow(String venueId) async {
    final row =
        await (database.select(database.venues)
              ..where((row) => row.id.equals(venueId))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      throw const CanteenWriteException('地点不存在，可能已被删除。');
    }
    return row;
  }

  /// 建立内部目录快照（窗口/菜品的父节点）。
  ///
  /// 旧的「导入菜单」路径里快照代表某天的来源内容；自建目录没有来源、
  /// 没有当天语义，因此这里写一条**不参与新鲜度**的快照行：
  /// `source_type=manual`、`status=catalog`、业务日期固定为
  /// [catalogBusinessDate]，`expiresAt` 留空（永不自动过期）。
  Future<void> _ensureCatalogSnapshot(String venueId, String campusId) async {
    final snapshotId = catalogSnapshotIdFor(venueId);
    final existing =
        await (database.select(database.menuSnapshots)
              ..where((row) => row.id.equals(snapshotId))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return;
    final now = clock.nowUtc();
    final sourceId = await _ensureCatalogSource(venueId, now);
    await database
        .into(database.menuSnapshots)
        .insert(
          MenuSnapshotsCompanion.insert(
            id: snapshotId,
            sourceId: sourceId,
            venueId: venueId,
            businessDate: catalogBusinessDate,
            contentHash: 'catalog-$venueId',
            status: const Value('catalog'),
            importedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<String> _ensureCatalogSource(String venueId, DateTime now) async {
    final existing =
        await (database.select(database.menuSources)
              ..where(
                (row) =>
                    row.venueId.equals(venueId) &
                    row.sourceType.equals('manual'),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    final id = 'menu-source-catalog-$venueId';
    await database
        .into(database.menuSources)
        .insert(
          MenuSourcesCompanion.insert(
            id: id,
            venueId: venueId,
            sourceType: 'manual',
            // 自建目录由用户输入，无第三方许可（docs/07 §6.1 要求显式记录）。
            license: const Value('user-provided'),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return id;
  }

  static void _requireHhmm(String value, String label) {
    if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
      throw CanteenWriteException('$label要写成 08:30 这样的格式。');
    }
  }

  static int _minuteOf(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}

/// 自建目录快照的固定业务日期：只做外键父节点，不表示任何一天。
const String catalogBusinessDate = '1970-01-01';

class CanteenWriteException implements Exception {
  const CanteenWriteException(this.userMessage);

  final String userMessage;

  @override
  String toString() => 'CanteenWriteException($userMessage)';
}

/// 地点（食堂）视图。
class CanteenVenue {
  const CanteenVenue({
    required this.id,
    required this.campusId,
    required this.campusName,
    required this.name,
    required this.notes,
    required this.windowCount,
    required this.dishCount,
    required this.analyzedCount,
  });

  final String id;
  final String campusId;
  final String campusName;
  final String name;
  final String? notes;
  final int windowCount;
  final int dishCount;
  final int analyzedCount;

  bool get hasDishes => dishCount > 0;
  bool get fullyAnalyzed => dishCount > 0 && analyzedCount == dishCount;
}

/// 窗口视图。
class CanteenWindow {
  const CanteenWindow({
    required this.id,
    required this.venueId,
    required this.name,
    required this.openTime,
    required this.closeTime,
    required this.dishes,
  });

  final String id;
  final String venueId;
  final String name;
  final String openTime;
  final String closeTime;
  final List<CanteenDish> dishes;

  String get windowLabel => '$openTime–$closeTime';

  int get analyzedCount => dishes.where((dish) => dish.hasNutrition).length;
}

/// 菜品视图；[evidence] 是最新一条营养证据。
class CanteenDish {
  const CanteenDish({
    required this.id,
    required this.windowId,
    required this.name,
    required this.evidenceGrade,
    required this.itemStatus,
    required this.evidence,
    this.stationName,
    this.imagePath,
    this.servingGrams,
    this.tags = const [],
    this.ingredients = CanteenIngredientInfo.empty,
    this.foodId,
    this.masterPer100g,
  });

  final String id;
  final String windowId;
  final String name;
  final String evidenceGrade;
  final String itemStatus;
  final MenuItemNutritionEvidenceData? evidence;

  /// 窗口内的档口副行（docs/29 §P7 需求 17：不引入新数据，列本来就在）。
  final String? stationName;

  /// 菜品照片的私有目录路径（docs/29 §P7 需求 16）；null＝无照片，
  /// 读取侧渲染序号圆，不伪造占位图。
  final String? imagePath;

  // ── schema 28（docs/40 §2.1 / §2.5）─────────────────────────────────
  /// 这个窗口一份大概多少克（null = 未知）。
  final double? servingGrams;

  /// 结构化标签（清淡/辣/汤/面/油炸/餐次…）。
  final List<String> tags;

  /// 配料三层来源（用户 > AI > 词典）；过敏原由它推导。
  final CanteenIngredientInfo ingredients;

  /// 权威主引用（docs/67 §3.3）。非空 = 当前营养从主食物生效修订派生。
  final String? foodId;

  /// 所链主食物的每 100g 四项（不完整时为 null）。
  final ({double kcal, double protein, double carbs, double fat})?
  masterPer100g;

  bool get hasPhoto => imagePath != null && imagePath!.isNotEmpty;

  /// 有代表值才算「已分析」：只写了区间的历史行读取侧当无营养（不取中点）。
  ///
  /// 否则只有热量的菜会显示「已分析」却永远进不了菜品库。
  bool get hasNutrition {
    if (masterPer100g != null) return true;
    final value = evidence;
    return value != null &&
        value.kcalPer100g != null &&
        value.proteinPer100g != null &&
        value.carbsPer100g != null &&
        value.fatPer100g != null;
  }

  // 主食物是**当前事实**；证据是分析记录（没有链接时才回退到它）。
  double? get kcalPer100g => masterPer100g?.kcal ?? evidence?.kcalPer100g;
  double? get proteinPer100g =>
      masterPer100g?.protein ?? evidence?.proteinPer100g;
  double? get carbsPer100g => masterPer100g?.carbs ?? evidence?.carbsPer100g;
  double? get fatPer100g => masterPer100g?.fat ?? evidence?.fatPer100g;
}

/// 食堂菜结构化标签的编解码（`menu_items.tags_json`）。
///
/// 值域是开放集合（烹饪/口味/餐次），只做去空白与去重；空值写 `[]`。
String encodeCanteenTags(List<String> tags) {
  final cleaned = <String>[];
  for (final tag in tags) {
    final value = tag.trim();
    if (value.isEmpty || cleaned.contains(value)) continue;
    cleaned.add(value);
  }
  return jsonEncode(cleaned);
}

List<String> decodeCanteenTags(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  } on FormatException {
    return const [];
  }
}
