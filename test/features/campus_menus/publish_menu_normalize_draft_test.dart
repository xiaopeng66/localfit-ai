import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_import_publisher.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_snapshot_store.dart';
import 'package:localfit_ai/features/campus_menus/application/publish_menu_normalize_draft.dart';
import 'package:localfit_ai/features/menu_normalize/data/menu_normalize_json_decoder.dart';

/// 2.0-6h-3a：AI 菜单草案 → 正式菜单快照（docs/07 §6.3）。
/// 草案只是草案；写入必须走这里，且不碰 meals（推荐不写已吃）。
void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 9, 15, 8);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
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
  });

  tearDown(() => database.close());

  PublishMenuNormalizeDraft publisher() => PublishMenuNormalizeDraft(
    database: database,
    idGenerator: _Ids(),
    clock: FixedAppClock(now),
  );

  MenuNormalizeDraft draft({String venueName = '东区食堂'}) =>
      const MenuNormalizeJsonDecoder().decode('''
{"schema_version":1,"source_date":"2026-09-15","venue_name":"$venueName",
 "services":[{"service_name":"一楼窗口","open_time":"10:30","close_time":"13:30",
  "items":[{"display_name":"鸡蛋炒饭","price_minor":800,
   "needs_confirmation":true,"questions":[]}]}],
 "warnings":[]}
''');

  test(
    'publishes the draft as an active snapshot for its venue/date',
    () async {
      final result = await publisher().call(draft());

      expect(result.snapshotId, isNotNull);
      final snapshot = await MenuSnapshotStore(database: database)
          .activeSnapshotFor(venueId: 'venue-1', businessDate: '2026-09-15');
      expect(snapshot, isNotNull);
      expect(snapshot!.venueId, 'venue-1');

      final services = await database.select(database.menuServices).get();
      expect(services.single.name, '一楼窗口');
      final items = await database.select(database.menuItems).get();
      expect(items.single.displayName, '鸡蛋炒饭');
      // 草案描述的是菜单，不是已吃记录。
      expect(await database.select(database.mealItems).get(), isEmpty);
    },
  );

  test('records an ai/pasted_text source bound to the venue', () async {
    await publisher().call(draft());
    final sources = await database.select(database.menuSources).get();
    expect(sources, hasLength(1));
    expect(sources.single.venueId, 'venue-1');
    expect(sources.single.sourceType, 'pasted_text');
    // docs/07 §6.1：来源行要记录许可证/条款状态。粘贴文本是用户自己提供的，
    // 没有第三方许可；留空会让审计以为「这一行的来源已经审过了」。
    expect(sources.single.license, 'user-provided');
  });

  test('same content is idempotent (no superseded pair)', () async {
    final first = await publisher().call(draft());
    final second = await publisher().call(draft());

    expect(second.snapshotId, isNull);
    expect(second.duplicateOf, first.snapshotId);
    final snapshots = await database.select(database.menuSnapshots).get();
    expect(snapshots, hasLength(1));
  });

  test(
    'unknown venue name creates the venue under the single campus',
    () async {
      final result = await publisher().call(draft(venueName: '西区食堂'));

      expect(result.snapshotId, isNotNull);
      final venues = await database.select(database.venues).get();
      expect(venues.map((row) => row.name), containsAll(['东区食堂', '西区食堂']));
    },
  );

  test('no campus configured fails with an actionable message', () async {
    await (database.delete(database.venues)).go();
    await (database.delete(database.campusProfiles)).go();

    await expectLater(
      publisher().call(draft()),
      throwsA(
        isA<MenuPublishException>().having(
          (error) => error.userMessage ?? '',
          'userMessage',
          contains('校园'),
        ),
      ),
    );
    expect(await database.select(database.menuSnapshots).get(), isEmpty);
  });

  test(
    'blank venue name never reaches publishing (decoder rejects it)',
    () async {
      // 空食堂名在 decoder 就被挡下，写库入口不接收这种草案。
      expect(
        () => draft(venueName: ' '),
        throwsA(isA<MenuNormalizeFormatException>()),
      );
      expect(await database.select(database.menuSnapshots).get(), isEmpty);
    },
  );
}

final class _Ids implements IdGenerator {
  int _next = 1;
  @override
  String next() => 'id-${_next++}';
}
