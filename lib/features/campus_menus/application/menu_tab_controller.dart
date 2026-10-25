import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_file_importer.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_import_publisher.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_item_matcher.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_item_matcher_models.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_snapshot_store.dart';
import 'package:localfit_ai/features/campus_menus/domain/menu_raw_content_store.dart';
import 'package:localfit_ai/features/campus_menus/domain/menu_source_license.dart';

/// 菜单 tab 状态（2.0-6c）：由 [MenuTabController.load] 从本地事实构建，
/// 页面只渲染，不做 SQL/IO。
class MenuTabState {
  const MenuTabState({
    this.campusName,
    this.venueName,
    this.snapshot,
    this.sourceType,
    this.license,
    this.services = const <MenuTabService>[],
  });

  final String? campusName;
  final String? venueName;
  final MenuSnapshotView? snapshot;

  /// active 快照的来源类型与许可证（docs/07 §6.1/§6.3）；来源行还没记录
  /// 许可证时是 null，界面显示「未记录」而不是猜一个。
  final String? sourceType;
  final String? license;
  final List<MenuTabService> services;
}

/// 服务（窗口）分组：名称 + 营业时间文本 + 条目。
class MenuTabService {
  const MenuTabService({
    required this.name,
    required this.openCloseText,
    required this.items,
  });

  final String name;
  final String openCloseText;
  final List<MenuTabItem> items;
}

/// 单个菜单条目视图（docs/07 §6.5：来源等级、更新状态、已匹配/待确认）。
class MenuTabItem {
  const MenuTabItem({
    required this.id,
    required this.displayName,
    required this.evidenceGrade,
    required this.itemStatus,
    this.matchedFoodName,
  });

  final String id;
  final String displayName;
  final String evidenceGrade;
  final String itemStatus;
  final String? matchedFoodName;
}

/// 菜单 tab 控制器（application 层）：
/// - [load]：markExpired → 取唯一食堂/食堂（2.0 范围单校区单食堂，
///   多食堂选择归后续）→ active 快照 → 服务/条目分组。
/// - [importFrom]：find-or-create 手动导入 source → [MenuFileImporter]。
class MenuTabController {
  MenuTabController({
    required AppDatabase database,
    MenuRawContentStore? rawContentStore,
    List<String> shardPaths = const [],
  }) : _database = database,
       _matcher = MenuItemMatcher(database: database, shardPaths: shardPaths),
       _importer = rawContentStore == null
           ? null
           : MenuFileImporter(
               database: database,
               rawContentStore: rawContentStore,
             );

  final AppDatabase _database;
  final MenuFileImporter? _importer;
  final MenuItemMatcher _matcher;
  late final MenuSnapshotStore _store = MenuSnapshotStore(database: _database);

  /// 为菜单项生成 top-K 匹配建议（本地确定性打分；docs/07 §5.7）。
  Future<List<MenuItemMatchSuggestion>> suggestFor(
    String menuItemId, {
    int? topK,
  }) => _matcher.suggestMatches(menuItemId, topK: topK);

  /// 读取某菜单项当前的建议（suggested 行）。
  Future<List<MenuItemMatchSuggestion>> suggestionsFor(String menuItemId) =>
      _matcher.suggestionsFor(menuItemId);

  /// 确认某建议 → 行 confirmed + 菜单项 matched。
  Future<void> confirmSuggestion(String menuItemId, String foodId) =>
      _matcher.confirmMatchByFood(menuItemId, foodId);

  /// 拒绝该菜单项的 confirmed 行 → 回 unresolved（可重新建议）。
  Future<void> rejectConfirmed(String menuItemId) =>
      _matcher.rejectConfirmedMatch(menuItemId);

  Future<MenuTabState> load({DateTime? now}) async {
    await _store.markExpiredSnapshots();
    final venueRow = await _venueQuery().getSingleOrNull();
    if (venueRow == null) {
      return const MenuTabState();
    }
    final campusRow =
        await (_database.select(_database.campusProfiles)
              ..where((row) => row.id.equals(venueRow.campusId))
              ..limit(1))
            .getSingleOrNull();
    final businessDate = _todayIso(now);
    final snapshot = await _store.activeSnapshotFor(
      venueId: venueRow.id,
      businessDate: businessDate,
    );
    final source = snapshot == null
        ? null
        : await (_database.select(_database.menuSources)
                ..where((row) => row.id.equals(snapshot.sourceId))
                ..limit(1))
              .getSingleOrNull();
    final services = snapshot == null
        ? const <MenuTabService>[]
        : await _servicesFor(snapshot.id);
    return MenuTabState(
      campusName: campusRow?.name,
      venueName: venueRow.name,
      snapshot: snapshot,
      sourceType: source?.sourceType,
      license: source?.license,
      services: services,
    );
  }

  /// 导入本地菜单文件（TXT/CSV/JSON）。返回 publisher 结果
  /// （published=false 表示 hash 幂等跳过）。
  Future<MenuPublishResult> importFrom(String filePath, {DateTime? now}) async {
    final importer = _importer;
    if (importer == null) {
      throw StateError('MenuTabController.importFrom requires rawContentStore');
    }
    final venue = await _venueQuery().getSingleOrNull();
    if (venue == null) {
      throw StateError('no campus venue configured');
    }
    final sourceId = await _findOrCreateManualSource(venue.id, now: now);
    return importer.importFile(
      venueId: venue.id,
      sourceId: sourceId,
      filePath: filePath,
      // UI 导入默认幂等：同一份文件重复选择不产生退位对。
      skipIfHashMatches: true,
      // 时间可注入：load(now:) 用哪个时刻查，导入就用哪个时刻写
      // （否则业务日期来自真实时钟，跨日之后 load 就找不到刚导入的快照）。
      now: now,
    );
  }

  Selectable<Venue> _venueQuery() =>
      (_database.select(_database.venues)..limit(1));

  /// 手动导入共用一个 source 行（file_txt_csv_json 类型）。
  Future<String> _findOrCreateManualSource(
    String venueId, {
    DateTime? now,
  }) async {
    final ts = now ?? DateTime.now().toUtc();
    final existing =
        await (_database.select(_database.menuSources)
              ..where(
                (row) =>
                    row.venueId.equals(venueId) &
                    row.sourceType.equals(MenuSourceType.fileTxtCsvJson),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    final id = 'menu-source-manual-$venueId';
    await _database
        .into(_database.menuSources)
        .insert(
          MenuSourcesCompanion.insert(
            id: id,
            venueId: venueId,
            sourceType: MenuSourceType.fileTxtCsvJson,
            // docs/07 §6.1：来源行记录条款状态（用户自己导入的文件，
            // 没有第三方许可）；留空会让审计以为来源已经审过。
            license: const Value(MenuSourceLicense.userFile),
            createdAt: ts,
            updatedAt: ts,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return id;
  }

  Future<List<MenuTabService>> _servicesFor(String snapshotId) async {
    final serviceRows =
        await (_database.select(_database.menuServices)
              ..where((row) => row.snapshotId.equals(snapshotId))
              ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
            .get();
    final result = <MenuTabService>[];
    for (final service in serviceRows) {
      final itemRows =
          await (_database.select(_database.menuItems)
                ..where((row) => row.serviceId.equals(service.id))
                ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
              .get();
      final items = <MenuTabItem>[];
      for (final item in itemRows) {
        final matchRow =
            await (_database.select(_database.menuItemFoodMatches)
                  ..where(
                    (row) =>
                        row.menuItemId.equals(item.id) &
                        row.matchStatus.equals('confirmed'),
                  )
                  ..limit(1))
                .getSingleOrNull();
        String? foodName;
        if (matchRow != null) {
          final food =
              await (_database.select(_database.foods)
                    ..where((row) => row.id.equals(matchRow.foodId))
                    ..limit(1))
                  .getSingleOrNull();
          foodName = food?.name;
        }
        items.add(
          MenuTabItem(
            id: item.id,
            displayName: item.displayName,
            evidenceGrade: item.evidenceGrade,
            itemStatus: item.itemStatus,
            matchedFoodName: foodName,
          ),
        );
      }
      result.add(
        MenuTabService(
          name: service.name,
          openCloseText: '${service.openTime}–${service.closeTime}',
          items: items,
        ),
      );
    }
    return result;
  }

  String _todayIso([DateTime? now]) {
    final local = (now ?? DateTime.now()).toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
