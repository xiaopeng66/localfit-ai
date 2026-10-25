import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/application/local_food_search.dart';
import 'package:localfit_ai/features/food_scan/application/meal_scan_candidate.dart';
import 'package:localfit_ai/features/food_scan/application/resolve_meal_scan_candidates.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

void main() {
  test(
    'selects one normalized exact local food and derives nutrition locally',
    () {
      const food = FoodRecord(
        id: 'rice',
        name: '米饭',
        kcalPer100g: 116,
        proteinPer100g: 2.6,
        carbsPer100g: 25.9,
        fatPer100g: 0.3,
        isUserCreated: false,
      );

      final match = LocalFoodMatcher.match(' 米 饭 ', [food]);
      final candidate = MealScanCandidate.fromEstimate(_estimate('米饭'), match);

      expect(match.status, LocalFoodMatchStatus.exact);
      expect(match.selectedFood, same(food));
      expect(candidate.localNutrition!.nutrition.kcal, 208.8);
      expect(candidate.localNutrition!.nutrition.proteinGrams, 4.68);
      expect(candidate.localNutrition!.nutrition.carbsGrams, 46.62);
      expect(candidate.localNutrition!.nutrition.fatGrams, 0.54);
    },
  );

  test(
    'resolves a parenthetical local food through conservative base-name lookup',
    () async {
      const cookedRice = FoodRecord(
        id: 'cooked-rice',
        name: '米饭（一碗）',
        kcalPer100g: 116,
        proteinPer100g: 2.6,
        carbsPer100g: 25.9,
        fatPer100g: 0.3,
        isUserCreated: false,
      );
      final search = _FoodSearch({
        // 原始估算名（带括号）本身没有直接命中，靠去掉括号的基础名兜底。
        '米饭（一碗）': const [],
        '米饭': [cookedRice],
      });

      final draft = await ResolveMealScanCandidates(foodSearch: search)(
        MealEstimateDraft(
          items: [_estimate('米饭（一碗）')],
          warnings: const [],
          mealNotes: null,
        ),
      );

      expect(search.queries, ['米饭（一碗）', '米饭']);
      expect(draft.items.single.match.status, LocalFoodMatchStatus.exact);
      expect(draft.items.single.selectedFood, same(cookedRice));
    },
  );

  test(
    'keeps equal strong matches ambiguous instead of selecting by SQL order',
    () {
      final match = LocalFoodMatcher.match('米饭', [
        _food(id: 'a', name: '米饭'),
        _food(id: 'b', name: '米饭'),
      ]);

      expect(match.status, LocalFoodMatchStatus.ambiguous);
      expect(match.selectedFood, isNull);
    },
  );

  test(
    'prefers one user-created equal match without relying on result order',
    () {
      final userFood = _food(id: 'user', name: '米饭', isUserCreated: true);
      final match = LocalFoodMatcher.match('米饭', [
        _food(id: 'seed', name: '米饭'),
        userFood,
      ]);

      expect(match.status, LocalFoodMatchStatus.exact);
      expect(match.selectedFood, same(userFood));
    },
  );

  test('keeps weak containment and no matches unresolved', () {
    final weak = LocalFoodMatcher.match('鸡胸', [
      _food(id: 'chicken', name: '鸡胸肉（熟）'),
    ]);
    final none = LocalFoodMatcher.match('未知食物', [
      _food(id: 'rice', name: '米饭'),
    ]);

    expect(weak.status, LocalFoodMatchStatus.suggestion);
    expect(weak.selectedFood, isNull);
    expect(none.status, LocalFoodMatchStatus.unmatched);
    expect(none.selectedFood, isNull);
  });

  test(
    'keeps an out-of-range AI estimate unresolved but still counted',
    () async {
      // 可达性证据（D4）：AI 折算出的每 100g 营养超出本地边界（kcal > 1000）时
      // `_autoResolve` 拒绝自动收录、`selectedFood` 保持 null；但 `aiNutrition`
      // 仍在，于是这一项照样进合计、照样被保存——编辑器必须如实说明来源，
      // 不能说「无法计算营养」。
      final search = _FoodSearch({'未知食物': const []});
      final draft =
          await ResolveMealScanCandidates(
            foodSearch: search,
            createFood: (food) async =>
                throw const FormatException('每 100 克营养数值超出合理范围。'),
          )(
            MealEstimateDraft(
              items: [
                _estimate(
                  '未知食物',
                  nutrition: const MealEstimateNutrition(
                    // 180g 一份报 6000 kcal → 3333 kcal/100g，远超 1000 上限。
                    kcal: 6000,
                    proteinGrams: 10,
                    carbsGrams: 20,
                    fatGrams: 5,
                  ),
                ),
              ],
              warnings: const [],
              mealNotes: null,
            ),
          );

      final item = draft.items.single;
      expect(item.selectedFood, isNull, reason: '自动收录被超界营养拒绝');
      expect(item.usesAiEstimate, isTrue, reason: 'AI 估算仍在，卡片必须如实标注来源');
      expect(item.localNutrition, isNotNull, reason: '这一项照样进合计');
      expect(draft.resolvedItems, hasLength(1));
      expect(draft.nutrition.kcal, 6000);
      expect(draft.hasUnresolvedItems, isFalse);
    },
  );

  test(
    'candidate drafts update local totals and can explicitly clear notes',
    () {
      final food = _food(id: 'rice', name: '米饭');
      final item = MealScanCandidate.fromEstimate(
        _estimate('米饭'),
        LocalFoodMatch(
          status: LocalFoodMatchStatus.exact,
          selectedFood: food,
          suggestions: [food],
        ),
      );
      final draft = MealScanCandidateDraft(
        items: [item],
        slot: _slot,
        notes: '少油',
        warnings: const [],
      );

      final updated = draft.replaceItem(0, item.withGrams(200));
      final cleared = updated.copyWith(clearNotes: true);

      expect(updated.nutrition.kcal, 232);
      expect(updated.resolvedItems.single.foodId, food.id);
      expect(cleared.notes, isNull);
    },
  );
}

const _slot = MealSlot.lunch;

MealEstimateItem _estimate(String name, {MealEstimateNutrition? nutrition}) =>
    MealEstimateItem(
      name: name,
      estimatedGrams: 180,
      gramsRange: const GramRange(min: 140, max: 220),
      confidence: 0.8,
      ingredients: const [],
      needsConfirmation: false,
      questions: const [],
      cookingMethod: '蒸煮',
      nutrition: nutrition,
    );

FoodRecord _food({
  required String id,
  required String name,
  bool isUserCreated = false,
}) => FoodRecord(
  id: id,
  name: name,
  kcalPer100g: 116,
  proteinPer100g: 2.6,
  carbsPer100g: 25.9,
  fatPer100g: 0.3,
  isUserCreated: isUserCreated,
);

final class _FoodSearch implements LocalFoodSearch {
  _FoodSearch(this.responses);

  final Map<String, List<FoodRecord>> responses;
  final queries = <String>[];

  @override
  Future<List<FoodRecord>> search(String query, {int limit = 30}) async {
    queries.add(query);
    return responses[query] ?? const [];
  }
}
