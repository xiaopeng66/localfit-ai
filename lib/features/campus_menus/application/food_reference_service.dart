import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_item_matcher.dart';

/// 建食堂菜时的「参考食物库」候选（docs/40 §3.1 / docs/41 D 系裁决）。
final class FoodReferenceCandidate {
  const FoodReferenceCandidate({
    required this.foodId,
    required this.foodName,
    this.brand,
    required this.state,
    required this.confidence,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
  });

  final String foodId;
  final String foodName;

  /// 品牌（RV2 用户：引用食物库必须显示品牌）。可空——很多散装食材没有。
  final String? brand;

  /// `verified` | `estimated` | `user_created`（matcher 建议阶段已滤掉
  /// incomplete/stale）。
  final String state;

  /// 本地确定性打分（与匹配 UI 同一套语义）。
  final double confidence;

  /// 食物库的每 100g 事实——「引用」就是把这份值写进证据表。
  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;

  /// docs/40 §3.1：精确同名且来源可靠（verified/导入库）⇒ 默认建议「引用」。
  bool get recommendAdopt =>
      state == 'verified' &&
      confidence >= MenuItemMatcher.confidenceExactName - 0.0001;
}

/// 建菜/改名后的本地食物库匹配：**给建议，不静默填**。
///
/// 复用 [MenuItemMatcher] 的候选与打分（不写第二套检索），再补上食物库的
/// 每 100g 数值——「引用食物库」动作需要的正是这些数值。全程本地、不调 AI。
final class FoodReferenceService {
  const FoodReferenceService({required this.database, required this.matcher});

  final AppDatabase database;
  final MenuItemMatcher matcher;

  /// 为一道食堂菜取 top-K 候选（默认 3；UI 的三选一弹层用前 3 条）。
  ///
  /// 返回按置信度降序；食物行已删除的候选被如实丢弃（链接不悬空）。
  /// 确认「引用」：把 (menuItem, food) 的建议行置 confirmed
  /// （docs/40 §3.1：引用时链接 confirmed，不只是填数）。
  Future<void> confirmAdoption(String menuItemId, String foodId) =>
      matcher.confirmMatchByFood(menuItemId, foodId);

  Future<List<FoodReferenceCandidate>> suggestForDish(
    String menuItemId, {
    // 2026-10-22 用户：不再只给前 3 条，把包含匹配的候选都列出来供自选。
    int limit = 12,
  }) async {
    final suggestions = await matcher.suggestMatches(menuItemId, topK: limit);
    if (suggestions.isEmpty) return const [];
    final rows =
        await (database.select(database.foods)..where(
              (row) => row.id.isIn([
                for (final suggestion in suggestions) suggestion.foodId,
              ]),
            ))
            .get();
    final byId = {for (final row in rows) row.id: row};
    final result = <FoodReferenceCandidate>[];
    for (final suggestion in suggestions) {
      final row = byId[suggestion.foodId];
      if (row == null) continue;
      result.add(
        FoodReferenceCandidate(
          foodId: row.id,
          foodName: row.name,
          brand: row.brand,
          state: suggestion.state,
          confidence: suggestion.confidence,
          kcalPer100g: row.kcalPer100g,
          proteinPer100g: row.proteinPer100g,
          carbsPer100g: row.carbsPer100g,
          fatPer100g: row.fatPer100g,
        ),
      );
    }
    return result;
  }
}
