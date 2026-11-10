import 'dart:async';

import 'package:drift/drift.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart'
    show decodeCanteenTags;

/// 一条**食堂供应**在统一主库视角下的样子（docs/67 §3.3）。
///
/// 关键点：营养不在这里存第二份。`*Per100g` 全部来自所链主食物的当前值，
/// 主食物没链接或营养不完整时它们是 null——不是 0。
final class SupplyCatalogItem {
  const SupplyCatalogItem({
    required this.id,
    required this.displayName,
    required this.windowId,
    required this.windowName,
    required this.openTime,
    required this.closeTime,
    required this.venueId,
    required this.venueName,
    required this.servingGramsStatus,
    required this.servingGramsSource,
    this.foodId,
    this.foodName,
    this.foodArchived = false,
    this.foodBrand,
    this.kcalPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.revisionId,
    this.servingGrams,
    this.imagePath,
    this.stationName,
    this.evidenceGrade = 'D',
    this.itemStatus = 'unresolved',
    this.tags = const [],
  });

  final String id;
  final String displayName;
  final String windowId;
  final String windowName;

  /// 窗口营业时段（HH:MM）。推荐按它判断"这个餐位是否供应"。
  final String openTime;
  final String closeTime;

  final String venueId;
  final String venueName;

  /// 权威主引用（空 = 待分析供应）。
  final String? foodId;
  final String? foodName;
  final String? foodBrand;
  final bool foodArchived;

  /// 每 100g 事实（来自主食物）；不完整时全为 null。
  final double? kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;

  /// 主食物的生效修订 id。
  final String? revisionId;

  /// 该供应自己的每份克数。
  final double? servingGrams;
  final ServingGramsStatus servingGramsStatus;
  final ServingGramsSource servingGramsSource;

  final String? imagePath;
  final String? stationName;
  final String evidenceGrade;
  final String itemStatus;
  final List<String> tags;

  /// 四层可见状态：待分析 / 已链接·份量未知 / 已链接·份量估计 / 已链接·份量已知。
  SupplyNutritionState get state {
    if (foodId == null || !hasCompleteNutrition) {
      return SupplyNutritionState.needsAnalysis;
    }
    return switch (servingGramsStatus) {
      ServingGramsStatus.known => SupplyNutritionState.servingKnown,
      ServingGramsStatus.estimated => SupplyNutritionState.servingEstimated,
      ServingGramsStatus.unknown => SupplyNutritionState.servingUnknown,
    };
  }

  bool get hasCompleteNutrition => isCompleteNutrition(
    kcalPer100g: kcalPer100g,
    proteinPer100g: proteinPer100g,
    carbsPer100g: carbsPer100g,
    fatPer100g: fatPer100g,
  );

  bool get isAnalyzable => foodId != null && hasCompleteNutrition;

  /// 能不能按"份"记餐（要可信份量；估计份量需用户显式接受）。
  bool get canRecordByServing =>
      isAnalyzable &&
      servingGrams != null &&
      servingGrams! > 0 &&
      servingGramsStatus != ServingGramsStatus.unknown;

  /// 自动推荐只接受完整营养 + 可信份量（docs/67 §6.5）。
  bool get isAutoRecommendable =>
      isAnalyzable &&
      foodArchived == false &&
      servingGrams != null &&
      servingGrams! > 0 &&
      servingGramsStatus == ServingGramsStatus.known &&
      servingGramsSource.isTrustedBasis;

  /// 一份多少千卡（份量不可信时 null，不编造）。
  double? get kcalPerServing => canRecordByServing
      ? perServingFromPer100g(per100g: kcalPer100g!, servingGrams: servingGrams)
      : null;

  String get windowLabel => '$venueName · $windowName';

  /// 供应时段（与旧菜品库的 `servingWindow` 同构，供推荐按窗口判断）。
  String get servingWindow => '$openTime-$closeTime';
}

/// 供应的四种可见状态（docs/67 §3.3）。
enum SupplyNutritionState {
  /// 无主链接 / 营养不完整：可展示、可补资料，不显示 0 千卡，不进预算。
  needsAnalysis,

  /// 已链接、份量未知：可显示每 100g，按明确克数记餐。
  servingUnknown,

  /// 已链接、份量为估计：显示"约 X g／份"，需用户接受。
  servingEstimated,

  /// 已链接、份量已知：可按份派生。
  servingKnown,
}

/// 供应的统一读取口（食堂目录、记餐搜索、AI 快照共用）。
///
/// 批量读取按固定几条查询完成，不随供应条数增加查询次数（N+1 回归在
/// `test/features/nutrition/supply_catalog_repository_test.dart` 钉住）。
final class SupplyCatalogRepository {
  const SupplyCatalogRepository({required this.database});

  final AppDatabase database;

  /// 目录/记餐页的刷新信号：供应、证据、窗口、场所任一变化都算。
  Stream<void> watchChanges() => database
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          database.menuItems,
          database.menuServices,
          database.menuSnapshots,
          database.venues,
          database.foods,
        ]),
      )
      .asyncMap((_) {});

  /// 展示流不做营养/份量过滤：待分析与份量未知也是真实存在的供应。
  Stream<List<SupplyCatalogItem>> watchAll() => _watch(analyzableOnly: false);

  /// 兼容原来的可分析流。推荐门槛由消费者另行裁定。
  Stream<List<SupplyCatalogItem>> watchAnalyzable() =>
      _watch(analyzableOnly: true);

  /// 订阅变化后立刻读取现值，首屏不依赖写库，也不漏掉初次查询中的更新。
  /// 取消后在途查询不再 emit，并释放数据库订阅。
  Stream<List<SupplyCatalogItem>> _watch({required bool analyzableOnly}) {
    late StreamController<List<SupplyCatalogItem>> controller;
    StreamSubscription<void>? changes;
    var closed = false;

    Future<void> emit() async {
      try {
        final items = await listAll(analyzableOnly: analyzableOnly);
        if (!closed) controller.add(items);
      } on Object catch (error, stack) {
        if (!closed) controller.addError(error, stack);
      }
    }

    controller = StreamController<List<SupplyCatalogItem>>(
      onListen: () {
        changes = watchChanges().listen(
          (_) => unawaited(emit()),
          onError: (Object error, StackTrace stack) {
            if (!closed) controller.addError(error, stack);
          },
        );
        unawaited(emit());
      },
      onCancel: () async {
        closed = true;
        await changes?.cancel();
        changes = null;
      },
    );
    return controller.stream;
  }

  Future<SupplyCatalogItem?> getById(String id) async {
    final items = await _load();
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<List<SupplyCatalogItem>> listAll({bool analyzableOnly = false}) async {
    final items = await _load();
    if (!analyzableOnly) return items;
    return items.where((item) => item.isAnalyzable).toList(growable: false);
  }

  /// 按名字/主食物名检索（只做检索，不裁定身份）。
  Future<List<SupplyCatalogItem>> search(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    final items = await _load();
    if (trimmed.isEmpty) return items.take(limit).toList(growable: false);
    final needle = trimmed.toLowerCase();
    return items
        .where(
          (item) =>
              item.displayName.toLowerCase().contains(needle) ||
              (item.foodName?.toLowerCase().contains(needle) ?? false),
        )
        .take(limit)
        .toList(growable: false);
  }

  Future<List<SupplyCatalogItem>> _load() async {
    final items = await database.select(database.menuItems).get();
    if (items.isEmpty) return const [];

    final services = await database.select(database.menuServices).get();
    final snapshots = await database.select(database.menuSnapshots).get();
    final venues = await database.select(database.venues).get();
    final serviceById = {for (final row in services) row.id: row};
    final snapshotById = {for (final row in snapshots) row.id: row};
    final venueById = {for (final row in venues) row.id: row};

    final foodIds = {
      for (final item in items)
        if (item.foodId != null) item.foodId!,
    };
    final foods = foodIds.isEmpty
        ? const <Food>[]
        : await (database.select(
            database.foods,
          )..where((t) => t.id.isIn(foodIds))).get();
    final foodById = {for (final food in foods) food.id: food};

    return [
      for (final item in items)
        _map(
          item: item,
          service: serviceById[item.serviceId],
          snapshot: snapshotById[serviceById[item.serviceId]?.snapshotId],
          venue:
              venueById[snapshotById[serviceById[item.serviceId]?.snapshotId]
                  ?.venueId],
          food: item.foodId == null ? null : foodById[item.foodId],
        ),
    ];
  }

  SupplyCatalogItem _map({
    required MenuItem item,
    required MenuService? service,
    required MenuSnapshot? snapshot,
    required Venue? venue,
    required Food? food,
  }) {
    final status = ServingGramsStatus.fromStored(item.servingGramsStatus);
    final completeFood =
        food != null &&
        isCompleteNutrition(
          kcalPer100g: food.kcalPer100g,
          proteinPer100g: food.proteinPer100g,
          carbsPer100g: food.carbsPer100g,
          fatPer100g: food.fatPer100g,
        );
    return SupplyCatalogItem(
      id: item.id,
      displayName: item.displayName,
      windowId: item.serviceId,
      windowName: service?.name ?? '窗口',
      openTime: service?.openTime ?? '00:00',
      closeTime: service?.closeTime ?? '23:59',
      venueId: venue?.id ?? snapshot?.venueId ?? '',
      venueName: venue?.name ?? '食堂',
      foodId: item.foodId,
      foodName: food?.name,
      foodBrand: food?.brand,
      foodArchived: food?.archivedAt != null,
      kcalPer100g: completeFood ? food.kcalPer100g : null,
      proteinPer100g: completeFood ? food.proteinPer100g : null,
      carbsPer100g: completeFood ? food.carbsPer100g : null,
      fatPer100g: completeFood ? food.fatPer100g : null,
      revisionId: food?.currentRevisionId,
      servingGrams: item.servingGrams,
      servingGramsStatus: status,
      servingGramsSource: ServingGramsSource.fromStored(
        item.servingGramsSource,
      ),
      imagePath: item.imagePath,
      stationName: item.stationName,
      evidenceGrade: item.evidenceGrade,
      itemStatus: item.itemStatus,
      tags: decodeCanteenTags(item.tagsJson),
    );
  }
}
