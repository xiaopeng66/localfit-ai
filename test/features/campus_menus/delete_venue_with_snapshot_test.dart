import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';

/// RV-P1-03：地点名下有**非 catalog** 快照（AI 发布/文件导入）时，
/// `deleteVenue` 必须能删掉整个地点，而不是抛外键异常。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late CanteenRepository repository;
  final now = DateTime.utc(2026, 10, 20, 4);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = CanteenRepository(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  test('地点下的全部快照随地点一起删除', () async {
    final venueId = await repository.createVenue(
      name: '三食堂',
      campusName: '南校区',
    );
    // 模拟 AI 发布 / 文件导入产生的快照（不是 catalogSnapshotIdFor 那一条）。
    final sourceId = 'source-1';
    await database
        .into(database.menuSources)
        .insert(
          MenuSourcesCompanion.insert(
            id: sourceId,
            venueId: venueId,
            sourceType: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.menuSnapshots)
        .insert(
          MenuSnapshotsCompanion.insert(
            id: 'snapshot-ai-1',
            sourceId: sourceId,
            venueId: venueId,
            businessDate: '2026-10-20',
            contentHash: 'hash-1',
            importedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

    await repository.deleteVenue(venueId);

    expect(await database.select(database.venues).get(), isEmpty);
    expect(
      await database.select(database.menuSnapshots).get(),
      isEmpty,
      reason: '地点删除必须带走它名下的全部快照（否则外键挡住删除）',
    );
  });
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
