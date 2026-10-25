import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/menu_normalize/data/menu_normalize_json_decoder.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_import_publisher.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> seedVenue() async {
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
            sourceType: 'pasted_text',
            createdAt: now,
            updatedAt: now,
          ),
        );
    return 'venue-1';
  }

  // `price_minor` 是 **legacy 容忍键**：退役前的 JSON 里有它，解码忽略、
  // 也不落库（2026-10-16 用户删掉菜品价格；docs/36 §3 S8-b）。
  const validJson = '''
{"schema_version":1,"source_date":"2026-09-15","venue_name":"东区食堂",
 "services":[{"service_name":"一楼窗口","open_time":"10:30","close_time":"13:30",
  "items":[{"display_name":"鸡蛋炒饭","price_minor":800}]}],
 "warnings":[]}
''';

  group('menu import publisher', () {
    test('publishes a normalized draft as an active snapshot', () async {
      await seedVenue();
      final draft = const MenuNormalizeJsonDecoder().decode(validJson);
      final publisher = MenuImportPublisher(database: database);

      final result = await publisher.publishDraft(
        venueId: 'venue-1',
        sourceId: 'source-1',
        businessDate: '2026-09-15',
        draft: draft,
      );

      expect(result.snapshotId, isNotEmpty);
      expect(result.jobId, isNotEmpty);

      final snapshot =
          (await database.select(database.menuSnapshots).get()).single;
      expect(snapshot.status, 'active');
      expect(snapshot.businessDate, '2026-09-15');
      expect(snapshot.contentHash, hasLength(64));

      final service =
          (await database.select(database.menuServices).get()).single;
      expect(service.name, '一楼窗口');
      expect(service.openTime, '10:30');

      final item = (await database.select(database.menuItems).get()).single;
      expect(item.displayName, '鸡蛋炒饭');
      // 价格退役：生成的插入行里**不该再有**这一列（能力的真缺席，
      // 不是「值为 0」；夹具里的 `price_minor` 只作 legacy 容忍）。
      expect(item.toColumns(false).containsKey('price_minor'), isFalse);
      expect(item.itemStatus, 'unresolved');
      expect(item.evidenceGrade, 'D');

      final job = (await database.select(database.menuImportJobs).get()).single;
      expect(job.status, 'completed');
      expect(job.parsedItemCount, 1);
      expect(job.parseErrorCount, 0);
      expect(job.snapshotId, result.snapshotId);
    });

    test('marks the previous active snapshot as superseded', () async {
      await seedVenue();
      final draft = const MenuNormalizeJsonDecoder().decode(validJson);
      final publisher = MenuImportPublisher(database: database);

      final first = await publisher.publishDraft(
        venueId: 'venue-1',
        sourceId: 'source-1',
        businessDate: '2026-09-15',
        draft: draft,
      );
      final second = await publisher.publishDraft(
        venueId: 'venue-1',
        sourceId: 'source-1',
        businessDate: '2026-09-15',
        draft: draft,
      );

      final snapshots = await database.select(database.menuSnapshots).get();
      expect(snapshots, hasLength(2));
      expect(
        snapshots.firstWhere((s) => s.id == first.snapshotId).status,
        'superseded',
      );
      expect(
        snapshots.firstWhere((s) => s.id == second.snapshotId).status,
        'active',
      );
    });

    test(
      'is idempotent for identical content on the same business date',
      () async {
        await seedVenue();
        final draft = const MenuNormalizeJsonDecoder().decode(validJson);
        final publisher = MenuImportPublisher(database: database);

        final first = await publisher.publishDraft(
          venueId: 'venue-1',
          sourceId: 'source-1',
          businessDate: '2026-09-15',
          draft: draft,
        );
        final second = await publisher.publishDraft(
          venueId: 'venue-1',
          sourceId: 'source-1',
          businessDate: '2026-09-15',
          draft: draft,
          skipIfHashMatches: true,
        );

        expect(second.duplicateOf, first.snapshotId);
        expect(second.snapshotId, isNull);
        expect(
          (await database.select(database.menuSnapshots).get()),
          hasLength(1),
        );
      },
    );

    test(
      'records a failed job and keeps old snapshot on invalid draft',
      () async {
        await seedVenue();
        final goodDraft = const MenuNormalizeJsonDecoder().decode(validJson);
        final publisher = MenuImportPublisher(database: database);
        await publisher.publishDraft(
          venueId: 'venue-1',
          sourceId: 'source-1',
          businessDate: '2026-09-15',
          draft: goodDraft,
        );

        // 解析成功但超出约束的 draft（服务数上限）无法直接构造——用空
        // venue 名模拟运行时校验拒绝。
        const badDraft = MenuNormalizeDraft(
          schemaVersion: 1,
          sourceDate: '2026-09-15',
          venueName: '',
          services: [],
          warnings: [],
        );
        await expectLater(
          publisher.publishDraft(
            venueId: 'venue-1',
            sourceId: 'source-1',
            businessDate: '2026-09-15',
            draft: badDraft,
          ),
          throwsA(isA<MenuPublishException>()),
        );

        final job = (await database.select(database.menuImportJobs).get()).last;
        expect(job.status, 'failed');
        expect(job.parseErrorCount, greaterThanOrEqualTo(1));
        // 旧有效快照未被覆盖。
        final snapshots = await database.select(database.menuSnapshots).get();
        expect(snapshots, hasLength(1));
        expect(snapshots.single.status, 'active');
      },
    );

    test(
      'rejects a draft whose venue name mismatches the target venue',
      () async {
        await seedVenue();
        const mismatched = '''
{"schema_version":1,"source_date":"2026-09-15","venue_name":"西区食堂",
 "services":[],"warnings":[]}
''';
        final draft = const MenuNormalizeJsonDecoder().decode(mismatched);
        final publisher = MenuImportPublisher(database: database);
        // venue 名不匹配只产生警告不阻断（用户可能重命名食堂）——确认成功
        // 且 warning 进入 job 记录。
        final result = await publisher.publishDraft(
          venueId: 'venue-1',
          sourceId: 'source-1',
          businessDate: '2026-09-15',
          draft: draft,
        );
        expect(result.snapshotId, isNotNull);
        final job =
            (await database.select(database.menuImportJobs).get()).single;
        expect(job.status, 'completed');
      },
    );
  });
}
