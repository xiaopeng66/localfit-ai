import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_import_publisher.dart';
import 'package:localfit_ai/features/menu_normalize/data/menu_normalize_json_decoder.dart';

/// 2.0-3 收尾边界（docs/07 §8 退出条件：有效导入、重复导入幂等、解析失败
/// 可恢复；清除边界覆盖 Menu v1 九表）。
void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
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

  MenuNormalizeDraft buildDraft() => const MenuNormalizeJsonDecoder().decode('''
{"schema_version":1,"source_date":"2026-09-15","venue_name":"东区食堂",
 "services":[{"service_name":"一楼窗口","open_time":"10:30","close_time":"13:30",
  "items":[{"display_name":"鸡蛋炒饭","price_minor":800}]}]}
''');

  group('duplicate import idempotency', () {
    test(
      'same content twice with skipIfHashMatches keeps one snapshot',
      () async {
        final publisher = MenuImportPublisher(database: database);
        final first = await publisher.publishDraft(
          venueId: 'venue-1',
          sourceId: 'source-1',
          businessDate: '2026-09-15',
          draft: buildDraft(),
          skipIfHashMatches: true,
        );
        final second = await publisher.publishDraft(
          venueId: 'venue-1',
          sourceId: 'source-1',
          businessDate: '2026-09-15',
          draft: buildDraft(),
          skipIfHashMatches: true,
        );

        expect(first.snapshotId, isNotNull);
        expect(second.snapshotId, isNull);
        expect(second.duplicateOf, first.snapshotId);

        final snapshots = await database.select(database.menuSnapshots).get();
        expect(snapshots, hasLength(1));
        expect(snapshots.single.status, 'active');
        final items = await database.select(database.menuItems).get();
        expect(items, hasLength(1));
      },
    );

    test(
      're-import without skip creates a superseding snapshot pair',
      () async {
        final publisher = MenuImportPublisher(database: database);
        await publisher.publishDraft(
          venueId: 'venue-1',
          sourceId: 'source-1',
          businessDate: '2026-09-15',
          draft: buildDraft(),
        );
        await publisher.publishDraft(
          venueId: 'venue-1',
          sourceId: 'source-1',
          businessDate: '2026-09-15',
          draft: buildDraft(),
        );

        final snapshots = await database.select(database.menuSnapshots).get();
        expect(snapshots, hasLength(2));
        expect(snapshots.map((s) => s.status).toSet(), {
          'superseded',
          'active',
        });
      },
    );
  });

  group('clear boundary covers Menu v1 tables', () {
    test('clearDatabaseRowsOnly empties all nine menu tables', () async {
      final publisher = MenuImportPublisher(database: database);
      await publisher.publishDraft(
        venueId: 'venue-1',
        sourceId: 'source-1',
        businessDate: '2026-09-15',
        draft: buildDraft(),
      );

      expect(await database.select(database.menuSnapshots).get(), isNotEmpty);
      expect(await database.select(database.menuServices).get(), isNotEmpty);
      expect(await database.select(database.menuItems).get(), isNotEmpty);
      expect(await database.select(database.menuImportJobs).get(), isNotEmpty);

      await ClearAllLocalData(database).clearDatabaseRowsOnly();

      final expectedEmpty = <String, List<DataClass>>{
        'campus_profiles': await database.select(database.campusProfiles).get(),
        'venues': await database.select(database.venues).get(),
        'menu_sources': await database.select(database.menuSources).get(),
        'menu_snapshots': await database.select(database.menuSnapshots).get(),
        'menu_services': await database.select(database.menuServices).get(),
        'menu_items': await database.select(database.menuItems).get(),
        'menu_item_food_matches': await database
            .select(database.menuItemFoodMatches)
            .get(),
        'menu_item_nutrition_evidence': await database
            .select(database.menuItemNutritionEvidence)
            .get(),
        'menu_import_jobs': await database
            .select(database.menuImportJobs)
            .get(),
      };
      expectedEmpty.forEach((name, rows) {
        expect(rows, isEmpty, reason: '$name must be cleared');
      });
      // 恢复语义（ADR-012）：恢复仅清行，媒体文件与 AI Key 不动。
      expect(await database.select(database.profiles).get(), isEmpty);
      expect(await database.select(database.foods).get(), isEmpty);
    });

    test('full clear removes menu rows alongside user data', () async {
      final publisher = MenuImportPublisher(database: database);
      await publisher.publishDraft(
        venueId: 'venue-1',
        sourceId: 'source-1',
        businessDate: '2026-09-15',
        draft: buildDraft(),
      );

      await ClearAllLocalData(database).clear();

      expect(await database.select(database.menuSnapshots).get(), isEmpty);
      expect(await database.select(database.campusProfiles).get(), isEmpty);
    });
  });
}
