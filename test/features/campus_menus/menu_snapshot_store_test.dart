import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_snapshot_store.dart';

/// 2.0-3e：快照过期/superseded 语义（docs/07 §6.5/7.3）。
/// 过期快照仍可查看（历史），但不进入「今日推荐」（activeSnapshotFor）；
/// 过期判定会同步把快照状态与条目 itemStatus 标为 expired。
void main() {
  late AppDatabase database;
  late MenuSnapshotStore store;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = MenuSnapshotStore(database: database);
    final now = DateTime.now().toUtc();
    await database
        .into(database.campusProfiles)
        .insert(
          CampusProfilesCompanion.insert(
            id: 'campus-1',
            name: '示范大学',
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
            name: '东区食堂',
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
            sourceType: 'paste_text',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  /// 直插快照（绕过 publisher，精确控制 expiresAt）。
  Future<String> insertSnapshot({
    required String id,
    required String businessDate,
    String status = 'active',
    DateTime? expiresAt,
    DateTime? importedAt,
  }) async {
    final now = importedAt ?? DateTime.now().toUtc();
    await database
        .into(database.menuSnapshots)
        .insert(
          MenuSnapshotsCompanion.insert(
            id: id,
            sourceId: 'source-1',
            venueId: 'venue-1',
            businessDate: businessDate,
            contentHash: id.hashCode.toRadixString(16).padLeft(64, '0'),
            status: Value(status),
            importedAt: now,
            expiresAt: Value(expiresAt),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final serviceId = 'svc-$id';
    await database
        .into(database.menuServices)
        .insert(
          MenuServicesCompanion.insert(
            id: serviceId,
            snapshotId: id,
            name: '一楼窗口',
            openTime: '10:30',
            closeTime: '13:30',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuItems)
        .insert(
          MenuItemsCompanion.insert(
            id: 'item-$id',
            serviceId: serviceId,
            displayName: '鸡蛋炒饭',
            itemStatus: const Value('matched'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  group('today snapshot lookup', () {
    test('returns the active snapshot for the venue and date', () async {
      await insertSnapshot(id: 'snap-a', businessDate: '2026-09-15');
      final snapshot = await store.activeSnapshotFor(
        venueId: 'venue-1',
        businessDate: '2026-09-15',
      );
      expect(snapshot?.id, 'snap-a');
    });

    test('excludes superseded snapshots from today lookup', () async {
      await insertSnapshot(
        id: 'snap-old',
        businessDate: '2026-09-15',
        status: 'superseded',
      );
      final snapshot = await store.activeSnapshotFor(
        venueId: 'venue-1',
        businessDate: '2026-09-15',
      );
      expect(snapshot, isNull);
    });

    test('excludes expired snapshots from today lookup but keeps them '
        'viewable in history', () async {
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      await insertSnapshot(
        id: 'snap-exp',
        businessDate: '2026-09-15',
        expiresAt: past,
      );
      final snapshot = await store.activeSnapshotFor(
        venueId: 'venue-1',
        businessDate: '2026-09-15',
      );
      expect(snapshot, isNull);

      // 历史仍可查看（superseded/expired 都在）。
      final history = await store.historyFor(
        venueId: 'venue-1',
        businessDate: '2026-09-15',
      );
      expect(history.map((s) => s.id), contains('snap-exp'));
    });

    test('prefers the latest active snapshot when multiple exist', () async {
      final now = DateTime.now().toUtc();
      await insertSnapshot(
        id: 'snap-1',
        businessDate: '2026-09-15',
        importedAt: now.subtract(const Duration(hours: 1)),
      );
      await insertSnapshot(
        id: 'snap-2',
        businessDate: '2026-09-15',
        importedAt: now,
      );
      final snapshot = await store.activeSnapshotFor(
        venueId: 'venue-1',
        businessDate: '2026-09-15',
      );
      // 数据异常出现两个 active 时取 importedAt 最新者。
      expect(snapshot?.id, 'snap-2');
    });
  });

  group('expiry marking', () {
    test('markExpiredSnapshots flips expired actives to expired status '
        'and their items to expired', () async {
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      await insertSnapshot(
        id: 'snap-dead',
        businessDate: '2026-09-15',
        expiresAt: past,
      );
      final untouchedFuture = DateTime.now().toUtc().add(
        const Duration(days: 1),
      );
      await insertSnapshot(
        id: 'snap-live',
        businessDate: '2026-09-15',
        expiresAt: untouchedFuture,
      );

      final changed = await store.markExpiredSnapshots();
      expect(changed, contains('snap-dead'));
      expect(changed, isNot(contains('snap-live')));

      final dead = await (database.select(
        database.menuSnapshots,
      )..where((s) => s.id.equals('snap-dead'))).getSingle();
      expect(dead.status, 'expired');
      final deadItem = await (database.select(
        database.menuItems,
      )..where((i) => i.id.equals('item-snap-dead'))).getSingle();
      expect(deadItem.itemStatus, 'expired');

      final live = await (database.select(
        database.menuSnapshots,
      )..where((s) => s.id.equals('snap-live'))).getSingle();
      expect(live.status, 'active');
      final liveItem = await (database.select(
        database.menuItems,
      )..where((i) => i.id.equals('item-snap-live'))).getSingle();
      expect(liveItem.itemStatus, 'matched');
    });

    test('markExpiredSnapshots is idempotent', () async {
      final past = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
      await insertSnapshot(
        id: 'snap-dead',
        businessDate: '2026-09-15',
        expiresAt: past,
      );
      await store.markExpiredSnapshots();
      final second = await store.markExpiredSnapshots();
      expect(second, isEmpty);
    });
  });
}
