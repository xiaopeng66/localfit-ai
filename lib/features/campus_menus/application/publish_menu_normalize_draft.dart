import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_import_publisher.dart';
import 'package:localfit_ai/features/campus_menus/domain/menu_source_license.dart';
import 'package:localfit_ai/features/menu_normalize/data/menu_normalize_json_decoder.dart';

/// 把 AI 菜单草案（menu-normalize）发布为正式快照（2.0-6h-3a，docs/07 §6.3）。
///
/// - 按草案 `venue_name` 匹配既有食堂；无匹配但校园存在 → 在该校园下
///   自动创建食堂（2.0 范围单校区）；无校园 → 抛可行动错误。
/// - 来源行用 `pasted_text` 类型（草案来自粘贴文本），find-or-create；
///   条款状态记为 `user-provided`（用户自己提供，没有第三方许可）。
/// - 幂等：同 venue+日期+内容命中既有 active 快照 → 返回 duplicateOf。
///
/// 草案只是草案：本服务是写入正式事实的唯一入口，且只写菜单，
/// 绝不写 meals（推荐不写已吃）。
class PublishMenuNormalizeDraft {
  PublishMenuNormalizeDraft({
    required this._database,
    required this._idGenerator,
    required this._clock,
  });

  final AppDatabase _database;
  final IdGenerator _idGenerator;
  final AppClock _clock;
  late final MenuImportPublisher _publisher = MenuImportPublisher(
    database: _database,
  );

  Future<MenuPublishResult> call(MenuNormalizeDraft draft) async {
    final venueName = draft.venueName.trim();
    if (venueName.isEmpty) {
      throw const MenuPublishException([
        'draft venue_name is empty',
      ], userMessage: '菜单草案缺少食堂名称（venue_name）。');
    }
    final now = _clock.nowUtc();
    final venue = await _findOrCreateVenue(venueName, now);
    final sourceId = await _findOrCreateSource(venue.id, now);
    return _publisher.publishDraft(
      venueId: venue.id,
      sourceId: sourceId,
      businessDate: draft.sourceDate,
      draft: draft,
      skipIfHashMatches: true,
    );
  }

  Future<Venue> _findOrCreateVenue(String name, DateTime now) async {
    final existing =
        await (_database.select(_database.venues)
              ..where((row) => row.name.equals(name))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing;

    final campus = await (_database.select(
      _database.campusProfiles,
    )..limit(1)).getSingleOrNull();
    if (campus == null) {
      throw const MenuPublishException([
        'no campus profile configured',
      ], userMessage: '还没有建立校园。请先在菜单页添加食堂地点（可一并填写学校/园区）。');
    }
    final venueId = _idGenerator.next();
    await _database
        .into(_database.venues)
        .insert(
          VenuesCompanion.insert(
            id: venueId,
            campusId: campus.id,
            name: name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await (_database.select(_database.venues)
          ..where((row) => row.id.equals(venueId))
          ..limit(1))
        .getSingle());
  }

  Future<String> _findOrCreateSource(String venueId, DateTime now) async {
    final existing =
        await (_database.select(_database.menuSources)
              ..where(
                (row) =>
                    row.venueId.equals(venueId) &
                    row.sourceType.equals(MenuSourceType.pastedText),
              )
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    final id = 'menu-source-ai-$venueId';
    await _database
        .into(_database.menuSources)
        .insert(
          MenuSourcesCompanion.insert(
            id: id,
            venueId: venueId,
            sourceType: MenuSourceType.pastedText,
            // docs/07 §6.1：来源行要记录条款状态；粘贴文本是用户自己提供的，
            // 没有第三方许可（留空会让审计以为这一行的来源已经审过）。
            license: const Value(MenuSourceLicense.userProvided),
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return id;
  }
}
