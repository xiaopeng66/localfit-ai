import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/validation/entity_name.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/dish_image_store.dart';
import 'package:localfit_ai/features/campus_menus/domain/ingredients.dart';

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
    this.onDishUpserted,
    this.onDishDeleted,
  });

  static const _catalogSnapshotSuffix = 'canteen-catalog';

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 菜品照片的文件清理（docs/29 §P7 需求 16）；null＝不清理（测试或
  /// 未接线的装配），只影响孤儿文件，不影响数据正确性。
  final DishImageStore? dishImageStore;

  /// 菜品**写入/更新**后的同步钩子（2026-10-24 用户：「加入菜品目录里不能
  /// 自动加入菜品库吗…我希望他们就是一个库，不要分开，不要自己加入」）。
  ///
  /// 组合根（`main.dart`）注入成「把这条菜自动写进菜品库」；默认 null =
  /// 不同步（单测直接构造仓储时的旧行为逐字不变）。
  ///
  /// 钩在这里而不是各调用点：写入口有建菜 / 改名 / 换照片 / 改份量 / 写营养
  /// 五处，漏一处就是「用户改了、菜品库没跟上」；而 campus_menus **不能**
  /// import nutrition（分层门禁冻结了跨 feature 边），所以依赖方向由回调
  /// 反转，不在数据层新增任何 import。
  final Future<void> Function(String dishId)? onDishUpserted;

  /// 菜品**删除**后的同步钩子：菜品库里的同源行跟随删除，一个库不留幽灵。
  final Future<void> Function(String dishId)? onDishDeleted;

  /// 调同步钩子；异常吞掉并如实记录取舍：同步的是**派生视图**，它失败不该
  /// 让用户看到「菜没建成」的假象。下一次写入、或重新分析，会再同步一次。
  Future<void> _notifyUpserted(String dishId) async {
    final hook = onDishUpserted;
    if (hook == null) return;
    try {
      await hook(dishId);
    } on Object {
      // 见上：派生视图同步失败不阻断目录写入。
    }
  }

  Future<void> _notifyDeleted(String dishId) async {
    final hook = onDishDeleted;
    if (hook == null) return;
    try {
      await hook(dishId);
    } on Object {
      // 同 `_notifyUpserted`。
    }
  }

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
    for (final row in dishRows) {
      (dishesByWindow[row.serviceId] ??= []).add(
        CanteenDish(
          id: row.id,
          windowId: row.serviceId,
          name: row.displayName,
          stationName: row.stationName,
          imagePath: row.imagePath,
          evidenceGrade: row.evidenceGrade,
          itemStatus: row.itemStatus,
          evidence: evidenceByItem[row.id],
          servingGrams: row.servingGrams,
          tags: decodeCanteenTags(row.tagsJson),
          ingredients: CanteenIngredientInfo.decode(row.ingredientsJson),
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

  /// 删除地点：窗口/菜品/证据/内部目录快照随外键级联删除。
  ///
  /// venues 被 menu_snapshots.venueId 引用（无级联），所以先删快照行——
  /// 它是本仓库为地点建的父节点，不是用户数据。
  Future<void> deleteVenue(String venueId) async {
    // 菜品库的同源行要跟着走（一个库），所以先把这道地点下的菜品 id 收好。
    final dishIds = await _dishIdsForVenue(venueId);
    await database.transaction(() async {
      final snapshotId = catalogSnapshotIdFor(venueId);
      await (database.delete(
        database.menuSnapshots,
      )..where((row) => row.id.equals(snapshotId))).go();
      await (database.delete(
        database.venues,
      )..where((row) => row.id.equals(venueId))).go();
    });
    for (final dishId in dishIds) {
      await _notifyDeleted(dishId);
    }
  }

  Future<List<String>> _dishIdsForVenue(String venueId) async {
    final windows =
        await (database.select(database.menuServices)..where(
              (row) => row.snapshotId.equals(catalogSnapshotIdFor(venueId)),
            ))
            .get();
    if (windows.isEmpty) return const [];
    final rows =
        await (database.select(database.menuItems)..where(
              (row) => row.serviceId.isIn(windows.map((w) => w.id).toList()),
            ))
            .get();
    return [for (final row in rows) row.id];
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
    final dishes = await (database.select(
      database.menuItems,
    )..where((row) => row.serviceId.equals(windowId))).get();
    await (database.delete(
      database.menuServices,
    )..where((row) => row.id.equals(windowId))).go();
    for (final dish in dishes) {
      await _notifyDeleted(dish.id);
    }
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
    return [
      for (final row in rows)
        CanteenDish(
          id: row.id,
          windowId: row.serviceId,
          name: row.displayName,
          stationName: row.stationName,
          imagePath: row.imagePath,
          evidenceGrade: row.evidenceGrade,
          itemStatus: row.itemStatus,
          evidence: evidenceByItem[row.id],
          servingGrams: row.servingGrams,
          tags: decodeCanteenTags(row.tagsJson),
          ingredients: CanteenIngredientInfo.decode(row.ingredientsJson),
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
            itemStatus: const Value('unresolved'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    // 自动同步（2026-10-24）：此刻多半还没有营养，钩子是空操作；一旦这道菜
    // 已有营养（例如测试预置了证据），它立刻出现在菜品库里。
    await _notifyUpserted(id);
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
    // 改名/换照片后同步：菜品库那一行跟着改，不新增第二张卡。
    await _notifyUpserted(dishId);
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
        updatedAt: Value(clock.nowUtc()),
      ),
    );
    // 份量改了 ⇒ 菜品库那一行的「每份」值要跟着重算（每份 = per100g × 克数）。
    await _notifyUpserted(dishId);
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
    await _notifyDeleted(dishId);
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
  }) async {
    if (!const {'A', 'B', 'C', 'D'}.contains(grade)) {
      throw const CanteenWriteException('证据等级只能是 A/B/C/D。');
    }
    if (!kCanteenNutritionOrigins.contains(origin)) {
      throw const CanteenWriteException('营养来源只能是 AI 估算 / 食物库引用 / 用户输入。');
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
    });
    // 营养写完 ⇒ 自动进菜品库（2026-10-24 用户：「就是一个库，不要自己加入」）。
    await _notifyUpserted(dishId);
  }

  /// 按 id 取一条菜品（含最新营养证据）；不存在返回 null。
  ///
  /// 自动同步用它把刚写完的那条菜读回来（`createDish` 只回 id）。
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

  bool get hasPhoto => imagePath != null && imagePath!.isNotEmpty;

  /// 有代表值才算「已分析」：只写了区间的历史行读取侧当无营养（不取中点）。
  bool get hasNutrition => evidence?.kcalPer100g != null;

  double? get kcalPer100g => evidence?.kcalPer100g;
  double? get proteinPer100g => evidence?.proteinPer100g;
  double? get carbsPer100g => evidence?.carbsPer100g;
  double? get fatPer100g => evidence?.fatPer100g;
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
