import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';

/// 快照行视图（2.0-3e）：只暴露 UI/推荐层需要的字段。
class MenuSnapshotView {
  const MenuSnapshotView({
    required this.id,
    required this.venueId,
    required this.sourceId,
    required this.businessDate,
    required this.status,
    required this.importedAt,
    this.expiresAt,
  });

  final String id;
  final String venueId;

  /// 来源行 id：界面显示「来源/许可证」时按它读 `menu_sources`
  /// （docs/07 §6.3：所有菜单显示来源、导入时间、业务日期、过期状态）。
  final String sourceId;
  final String businessDate;
  final String status;
  final DateTime importedAt;
  final DateTime? expiresAt;
}

/// 2.0-3e：快照过期/superseded 语义（docs/07 §6.5/7.3）。
///
/// 「今日推荐」只能用 [activeSnapshotFor]（active 且未过期，同日同食堂
/// 至多一个）；历史查看走 [historyFor]（含 superseded/expired，规范
/// 「过期快照仍可查看」）。[markExpiredSnapshots] 把已过 active 期快照
/// 翻成 expired 并同步条目 itemStatus=expired，可重复调用（幂等）。
final class MenuSnapshotStore {
  MenuSnapshotStore({required this.database});

  final AppDatabase database;

  /// 今日推荐入口：同 venue+businessDate 的 active 快照；expiresAt 已过
  /// 的不算（先调 [markExpiredSnapshots] 的调用方也可直接依赖本过滤）。
  /// 多个 active 属数据异常，取 importedAt 最新。
  Future<MenuSnapshotView?> activeSnapshotFor({
    required String venueId,
    required String businessDate,
  }) async {
    final now = DateTime.now().toUtc();
    final rows =
        await (database.select(database.menuSnapshots)
              ..where(
                (row) =>
                    row.venueId.equals(venueId) &
                    row.businessDate.equals(businessDate) &
                    row.status.equals('active') &
                    (row.expiresAt.isNull() |
                        row.expiresAt.isBiggerThanValue(now)),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.importedAt)])
              ..limit(1))
            .get();
    return rows.isEmpty ? null : _view(rows.first);
  }

  /// 历史（docs/07 §6.5「过期快照仍可查看」）：任何状态的快照，新的在前。
  Future<List<MenuSnapshotView>> historyFor({
    required String venueId,
    required String businessDate,
  }) async {
    final rows =
        await (database.select(database.menuSnapshots)
              ..where(
                (row) =>
                    row.venueId.equals(venueId) &
                    row.businessDate.equals(businessDate),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.importedAt)]))
            .get();
    return [for (final row in rows) _view(row)];
  }

  /// 过期判定：active 且 expiresAt ≤ now → status=expired，条目
  /// itemStatus=expired（原 matched/estimated/unresolved 都翻）。返回
  /// 本次翻动的 snapshot id（幂等：已 expired 的不再出现）。
  Future<List<String>> markExpiredSnapshots() async {
    final now = DateTime.now().toUtc();
    final expired =
        await (database.select(database.menuSnapshots)..where(
              (row) =>
                  row.status.equals('active') &
                  row.expiresAt.isNotNull() &
                  row.expiresAt.isSmallerOrEqualValue(now),
            ))
            .get();
    if (expired.isEmpty) return const [];
    final ids = expired.map((row) => row.id).toList();
    await database.transaction(() async {
      await (database.update(
        database.menuSnapshots,
      )..where((row) => row.id.isIn(ids) & row.status.equals('active'))).write(
        MenuSnapshotsCompanion(
          status: const Value('expired'),
          updatedAt: Value(now),
        ),
      );
      // 条目过期：只翻未终态的条目（closed 等终态不动）。
      await database.customUpdate(
        "UPDATE menu_items SET item_status = 'expired', updated_at = ?"
        " WHERE service_id IN"
        " (SELECT id FROM menu_services WHERE snapshot_id IN"
        ' (${ids.map((_) => '?').join(',')})'
        " AND item_status IN ('matched', 'estimated', 'unresolved'))",
        variables: [
          Variable.withDateTime(now),
          for (final id in ids) Variable.withString(id),
        ],
      );
    });
    return ids;
  }

  MenuSnapshotView _view(MenuSnapshot row) => MenuSnapshotView(
    id: row.id,
    venueId: row.venueId,
    sourceId: row.sourceId,
    businessDate: row.businessDate,
    status: row.status,
    importedAt: row.importedAt,
    expiresAt: row.expiresAt,
  );
}
