import 'package:localfit_ai/features/food_scan/application/local_food_search.dart';
import 'package:localfit_ai/features/food_scan/application/meal_scan_candidate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

final class ResolveMealScanCandidates {
  const ResolveMealScanCandidates({required this.foodSearch, this.createFood});

  final LocalFoodSearch foodSearch;

  /// 本地无匹配时的自动收录回调（接 FoodRepository.create）。为空或
  /// AI 没给营养估算时，未匹配项保持未解析（走既有手动路径）。
  final Future<FoodRecord> Function(NewFood food)? createFood;

  Future<List<FoodRecord>> search(String query, {int limit = 10}) =>
      foodSearch.search(query, limit: limit);

  Future<MealScanCandidateDraft> call(MealEstimateDraft draft) async {
    final candidates = <MealScanCandidate>[];
    // 同一次识别里同名未匹配项只收录一次（按归一名去重，复用同一条）。
    final collected = <String, FoodRecord>{};
    for (final estimate in draft.items) {
      final foodsById = <String, FoodRecord>{};
      for (final query in LocalFoodMatcher.searchQueries(estimate.name)) {
        for (final food in await foodSearch.search(query, limit: 10)) {
          foodsById.putIfAbsent(food.id, () => food);
        }
      }
      final foods = foodsById.values.toList(growable: false);
      var candidate = MealScanCandidate.fromEstimate(
        estimate,
        LocalFoodMatcher.match(estimate.name, foods),
      );
      candidate = await _autoResolve(candidate, collected);
      candidates.add(candidate);
    }
    return MealScanCandidateDraft(
      items: candidates,
      slot: MealSlot.lunch,
      notes: _optionalText(draft.mealNotes),
      warnings: draft.warnings,
    );
  }

  /// 自动解析：本地有候选 → 自动选中排名最高的一条（编辑器仍可改）；
  /// 本地没有且 AI 给了营养估算 → 折算每 100g 自动建档收录。
  Future<MealScanCandidate> _autoResolve(
    MealScanCandidate candidate,
    Map<String, FoodRecord> collected,
  ) async {
    if (candidate.selectedFood != null) return candidate;
    final suggestions = candidate.match.suggestions;
    if (suggestions.isNotEmpty) {
      return candidate.withSelectedFood(suggestions.first);
    }
    final nutrition = candidate.estimate.nutrition;
    final createFood = this.createFood;
    if (nutrition == null || createFood == null) return candidate;
    final estimated = candidate.estimate.estimatedGrams;
    if (!estimated.isFinite || estimated <= 0) return candidate;

    final key = LocalFoodMatcher.normalizeName(candidate.estimate.name);
    final existing = collected[key];
    if (existing != null) {
      return candidate.withSelectedFood(existing, autoCollected: true);
    }
    double per100(double value) => value / estimated * 100;
    final FoodRecord created;
    try {
      created = await createFood(
        NewFood(
          name: candidate.estimate.name,
          kcalPer100g: per100(nutrition.kcal),
          proteinPer100g: per100(nutrition.proteinGrams),
          carbsPer100g: per100(nutrition.carbsGrams),
          fatPer100g: per100(nutrition.fatGrams),
          defaultServingGrams: estimated,
        ),
      );
    } on FormatException {
      // AI 折算出超界营养（乱报）→ 保持未解析，走既有手动路径。
      return candidate;
    }
    collected[key] = created;
    return candidate.withSelectedFood(created, autoCollected: true);
  }

  String? _optionalText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

final class LocalFoodMatcher {
  const LocalFoodMatcher._();

  static List<String> searchQueries(String aiName) {
    final full = aiName.trim();
    // 空名（AI 返回畸形条目）不应触发无条件的兜底搜索——那会拉回
    // 10 条任意食物作为候选；保持 unmatched 即可。
    if (full.isEmpty) return const [];
    final base = _withoutParenthetical(full).trim();
    if (base.isEmpty || base == full) return [full];
    return [full, base];
  }

  static LocalFoodMatch match(String aiName, List<FoodRecord> foods) {
    final query = _normalize(aiName);
    if (query.isEmpty) {
      return const LocalFoodMatch(
        status: LocalFoodMatchStatus.unmatched,
        suggestions: [],
      );
    }

    final ranked =
        foods
            .map((food) => _RankedFood(food, _rank(query, food.name)))
            .where((item) => item.rank > 0)
            .toList()
          ..sort(_compare);
    final suggestions = ranked
        .map((item) => item.food)
        .take(5)
        .toList(growable: false);
    if (ranked.isEmpty) {
      return const LocalFoodMatch(
        status: LocalFoodMatchStatus.unmatched,
        suggestions: [],
      );
    }

    final bestRank = ranked.first.rank;
    final topIsUserCreated = ranked.first.food.isUserCreated;
    final best = ranked
        .where(
          (item) =>
              item.rank == bestRank &&
              item.food.isUserCreated == topIsUserCreated,
        )
        .toList(growable: false);
    if (bestRank >= 2 && best.length == 1) {
      return LocalFoodMatch(
        status: LocalFoodMatchStatus.exact,
        selectedFood: best.single.food,
        suggestions: suggestions,
      );
    }
    return LocalFoodMatch(
      status: best.length > 1
          ? LocalFoodMatchStatus.ambiguous
          : LocalFoodMatchStatus.suggestion,
      suggestions: suggestions,
    );
  }

  static int _rank(String query, String foodName) {
    final full = _normalize(foodName);
    if (full == query) return 3;
    if (_baseName(foodName) == query) return 2;
    if (full.contains(query) || query.contains(full)) return 1;
    return 0;
  }

  static int _compare(_RankedFood left, _RankedFood right) {
    final byRank = right.rank.compareTo(left.rank);
    if (byRank != 0) return byRank;
    final byUserCreated = right.food.isUserCreated == left.food.isUserCreated
        ? 0
        : right.food.isUserCreated
        ? 1
        : -1;
    if (byUserCreated != 0) return byUserCreated;
    return left.food.name.compareTo(right.food.name);
  }

  static String _baseName(String value) =>
      _normalize(_withoutParenthetical(value));

  /// 归一名（同匹配排名用的规则）：收录去重按它判断同名。
  static String normalizeName(String value) => _normalize(value);

  static String _withoutParenthetical(String value) =>
      value.replaceAll(RegExp(r'[（(][^（）()]*[）)]'), '');

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s（）()\[\]【】]'), '');
}

final class _RankedFood {
  const _RankedFood(this.food, this.rank);

  final FoodRecord food;
  final int rank;
}
