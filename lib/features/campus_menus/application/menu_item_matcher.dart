import 'package:drift/drift.dart';
import 'package:localfit_ai/core/text/search_text.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_item_matcher_models.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';

/// 2.0-3d：菜单项 → 本地 food alias top-K 匹配（docs/07 §6.3/5.7）。
///
/// 全程本地检索：主库精确/包含匹配（用户自建与种子行）+ 分片 FTS5
/// （[CatalogSearchService]），合并去重打分后取 top-K 写入
/// `menu_item_food_matches`（matchStatus=suggested）。用户确认/拒绝
/// 走 [confirmMatch]/[rejectMatch]：确认 → 行 confirmed 且菜单项
/// itemStatus=matched；拒绝 → 行 rejected，若无剩余 confirmed 则
/// 菜单项回落 unresolved。不联网、不调用 AI。
final class MenuItemMatcher {
  MenuItemMatcher({
    required this.database,
    required List<String> shardPaths,
    int topK = defaultTopK,
  }) : _search = CatalogSearchService(shardPaths: shardPaths),
       _topK = topK.clamp(1, maxTopK);

  static const int maxTopK = 20;
  static const int defaultTopK = 5;

  // 打分常量（确定性，供测试与 UI 展示同一套语义）。
  // docs/07 §5.7 优先级：精确别名（用户维护）> 精确 canonical 名 > 包含 >
  // 分片 FTS 命中衰减。
  static const double confidenceExactManualAlias = 0.98;
  static const double confidenceExactName = 0.95;
  static const double confidenceContains = 0.8;
  static const double confidenceShardFirst = 0.9;
  static const double confidenceShardDecay = 0.05;
  static const double confidenceShardFloor = 0.3;

  final AppDatabase database;
  final CatalogSearchService _search;
  final int _topK;

  /// 为菜单项生成 top-K 候选并写 suggested 行。
  ///
  /// 重新生成时只替换 suggested 行，confirmed/rejected 的用户决策保留。
  Future<List<MenuItemMatchSuggestion>> suggestMatches(
    String menuItemId, {
    int? topK,
  }) async {
    final item = await (database.select(
      database.menuItems,
    )..where((row) => row.id.equals(menuItemId))).getSingleOrNull();
    if (item == null) {
      throw ArgumentError('menu item not found: $menuItemId');
    }

    final effectiveTopK = (topK ?? _topK).clamp(1, maxTopK);
    final query = normalizeMenuText(item.displayName);
    if (query.isEmpty) {
      return const [];
    }

    // 1) 主库：用户别名精确匹配 > canonical 名精确匹配 > 包含匹配。
    final scores = <String, MenuItemMatchSuggestion>{};
    final localFoods = await database.select(database.foods).get();
    for (final food in localFoods) {
      final name = normalizeMenuText(food.name);
      if (name == query) {
        _offer(scores, food.id, food.name, food.state, confidenceExactName);
        continue;
      }
      // 包含匹配只在非精确时给较低分（双向：菜名含 food 名或反之）。
      if (name.contains(query) || query.contains(name)) {
        _offer(scores, food.id, food.name, food.state, confidenceContains);
      }
    }
    final localAliases = await database.select(database.foodAliases).get();
    final foodNameById = {for (final f in localFoods) f.id: f.name};
    for (final alias in localAliases) {
      if (normalizeMenuText(alias.normalizedText) == query) {
        final name = foodNameById[alias.foodId];
        if (name != null) {
          _offer(
            scores,
            alias.foodId,
            name,
            null,
            // 用户维护的别名精确命中按 docs/07 §5.7 优先级最高。
            alias.aliasType == 'manual'
                ? confidenceExactManualAlias
                : confidenceExactName,
          );
        }
      }
    }

    // 2) 分片 FTS5：按命中顺序衰减打分（CatalogSearchService 已跨分片
    // 去重、分页 ≤50）。
    final shardPage = _search.search(item.displayName);
    for (var i = 0; i < shardPage.items.length; i++) {
      final hit = shardPage.items[i];
      final confidence = (confidenceShardFirst - i * confidenceShardDecay)
          .clamp(confidenceShardFloor, confidenceShardFirst);
      _offer(scores, hit.id, hit.name, hit.state, confidence.toDouble());
    }

    // 3) 状态过滤：incomplete/stale 不建议（docs/07 §5.7；stale 需重新确认，
    // user_created 是用户自己的数据可以建议）。
    final candidates =
        scores.values.where((s) {
          final state = s.state;
          return state == 'verified' ||
              state == 'estimated' ||
              state == 'user_created';
        }).toList()..sort((a, b) {
          final byConfidence = b.confidence.compareTo(a.confidence);
          if (byConfidence != 0) return byConfidence;
          return a.foodName.compareTo(b.foodName);
        });
    final top = candidates.take(effectiveTopK).toList();

    await _storeSuggestions(menuItemId, top);
    return top;
  }

  /// 确认匹配：行 confirmed + 菜单项 matched。
  Future<void> confirmMatch(String matchId) =>
      _setMatchStatus(matchId, 'confirmed');

  /// 拒绝匹配：行 rejected；无剩余 confirmed 时菜单项回落 unresolved。
  Future<void> rejectMatch(String matchId) =>
      _setMatchStatus(matchId, 'rejected');

  /// UI 层（2.0-6d）：读取某菜单项当前 suggested 行（新→旧）。
  Future<List<MenuItemMatchSuggestion>> suggestionsFor(
    String menuItemId,
  ) async {
    final rows =
        await (database.select(database.menuItemFoodMatches)
              ..where(
                (row) =>
                    row.menuItemId.equals(menuItemId) &
                    row.matchStatus.equals('suggested'),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
            .get();
    final names = await _foodNames(rows.map((row) => row.foodId));
    return [
      for (final row in rows)
        if (names[row.foodId] != null)
          MenuItemMatchSuggestion(
            foodId: row.foodId,
            foodName: names[row.foodId]!,
            state: 'verified',
            confidence: row.confidence,
          ),
    ];
  }

  /// UI 层：按 (menuItemId, foodId) 确认 suggested 行。
  Future<void> confirmMatchByFood(String menuItemId, String foodId) async {
    final row =
        await (database.select(database.menuItemFoodMatches)
              ..where(
                (row) =>
                    row.menuItemId.equals(menuItemId) &
                    row.foodId.equals(foodId),
              )
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      throw ArgumentError(
        'no match row for item=$menuItemId food=$foodId; '
        'call suggestMatches first',
      );
    }
    await confirmMatch(row.id);
  }

  /// UI 层：拒绝该菜单项全部 confirmed 行 → 菜单项回 unresolved。
  Future<void> rejectConfirmedMatch(String menuItemId) async {
    final rows =
        await (database.select(database.menuItemFoodMatches)..where(
              (row) =>
                  row.menuItemId.equals(menuItemId) &
                  row.matchStatus.equals('confirmed'),
            ))
            .get();
    for (final row in rows) {
      await rejectMatch(row.id);
    }
  }

  Future<Map<String, String>> _foodNames(Iterable<String> foodIds) async {
    final ids = foodIds.toSet();
    if (ids.isEmpty) return const {};
    final rows = await (database.select(
      database.foods,
    )..where((row) => row.id.isIn(ids))).get();
    return {for (final row in rows) row.id: row.name};
  }

  Future<void> _setMatchStatus(String matchId, String status) async {
    final now = DateTime.now().toUtc();
    final match = await (database.select(
      database.menuItemFoodMatches,
    )..where((row) => row.id.equals(matchId))).getSingleOrNull();
    if (match == null) {
      throw ArgumentError('menu item food match not found: $matchId');
    }
    // 匹配行与菜单项状态是同一件事的两半，必须一起提交（docs/11 §3-A）：
    // 只落前一半会让已确认的菜在界面上仍是「待匹配」。
    await database.transaction(() async {
      await (database.update(
        database.menuItemFoodMatches,
      )..where((row) => row.id.equals(matchId))).write(
        MenuItemFoodMatchesCompanion(
          matchStatus: Value(status),
          updatedAt: Value(now),
        ),
      );
      await _refreshItemStatus(match.menuItemId, now);
    });
  }

  Future<void> _refreshItemStatus(String menuItemId, DateTime now) async {
    final rows = await (database.select(
      database.menuItemFoodMatches,
    )..where((row) => row.menuItemId.equals(menuItemId))).get();
    final hasConfirmed = rows.any((row) => row.matchStatus == 'confirmed');
    await (database.update(
      database.menuItems,
    )..where((row) => row.id.equals(menuItemId))).write(
      MenuItemsCompanion(
        itemStatus: Value(hasConfirmed ? 'matched' : 'unresolved'),
        updatedAt: Value(now),
      ),
    );
  }

  Future<void> _storeSuggestions(
    String menuItemId,
    List<MenuItemMatchSuggestion> suggestions,
  ) async {
    final now = DateTime.now().toUtc();
    await database.transaction(() async {
      // 只替换 suggested 行，保留 confirmed/rejected 用户决策。
      await (database.delete(database.menuItemFoodMatches)..where(
            (row) =>
                row.menuItemId.equals(menuItemId) &
                row.matchStatus.equals('suggested'),
          ))
          .go();
      final existing = await (database.select(
        database.menuItemFoodMatches,
      )..where((row) => row.menuItemId.equals(menuItemId))).get();
      final existingFoodIds = existing.map((row) => row.foodId).toSet();
      var counter = 0;
      for (final suggestion in suggestions) {
        if (existingFoodIds.contains(suggestion.foodId)) continue;
        counter++;
        await database
            .into(database.menuItemFoodMatches)
            .insert(
              MenuItemFoodMatchesCompanion.insert(
                id: 'match-$menuItemId-$counter-${now.millisecondsSinceEpoch}',
                menuItemId: menuItemId,
                foodId: suggestion.foodId,
                confidence: Value(suggestion.confidence),
                matchStatus: const Value('suggested'),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });
  }

  /// 合并去重：同一 food 保留更高分。
  void _offer(
    Map<String, MenuItemMatchSuggestion> scores,
    String foodId,
    String foodName,
    String? state,
    double confidence,
  ) {
    final existing = scores[foodId];
    if (existing != null && existing.confidence >= confidence) return;
    scores[foodId] = MenuItemMatchSuggestion(
      foodId: foodId,
      foodName: foodName,
      state: state ?? existing?.state ?? 'verified',
      confidence: confidence,
    );
  }
}

/// 规范化（与 FoodAliases.normalizedText 约定一致）：
/// 去所有空白、全角转半角、统一小写。
String normalizeMenuText(String input) => normalizeSearchText(input);
