import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

enum LocalFoodMatchStatus { exact, suggestion, ambiguous, unmatched, selected }

final class LocalFoodMatch {
  const LocalFoodMatch({
    required this.status,
    required this.suggestions,
    this.selectedFood,
  });

  final LocalFoodMatchStatus status;
  final List<FoodRecord> suggestions;
  final FoodRecord? selectedFood;
}

final class MealScanCandidate {
  const MealScanCandidate({
    required this.estimate,
    required this.grams,
    required this.match,
    this.autoCollected = false,
  });

  factory MealScanCandidate.fromEstimate(
    MealEstimateItem estimate,
    LocalFoodMatch match,
  ) => MealScanCandidate(
    estimate: estimate,
    grams: estimate.estimatedGrams,
    match: match,
  );

  final MealEstimateItem estimate;
  final double grams;
  final LocalFoodMatch match;

  /// 本地没有匹配项、由 AI 估算营养自动建档收录（`selectedFood` 指向
  /// 新收录的用户自建食物）。
  final bool autoCollected;

  FoodRecord? get selectedFood => match.selectedFood;

  /// AI 整份营养按确认克数等比缩放；本地无匹配时的营养兜底。
  MealItemDraft? get aiNutrition {
    final nutrition = estimate.nutrition;
    if (nutrition == null || !grams.isFinite || grams <= 0) return null;
    final estimated = estimate.estimatedGrams;
    if (!estimated.isFinite || estimated <= 0) return null;
    final factor = grams / estimated;
    return MealItemDraft(
      foodName: estimate.name,
      grams: grams,
      nutrition: NutritionValues(
        kcal: nutrition.kcal * factor,
        proteinGrams: nutrition.proteinGrams * factor,
        carbsGrams: nutrition.carbsGrams * factor,
        fatGrams: nutrition.fatGrams * factor,
      ),
    );
  }

  /// 营养来源：选中的本地食物优先，其次 AI 估算兜底。
  MealItemDraft? get localNutrition {
    final food = selectedFood;
    if (food != null) {
      if (!grams.isFinite || grams <= 0) return null;
      return MealItemDraft.fromFood(food, grams);
    }
    return aiNutrition;
  }

  /// 未匹配本地食物、营养完全依赖 AI 估算（编辑器据此标注来源）。
  bool get usesAiEstimate => selectedFood == null && aiNutrition != null;

  MealScanCandidate withGrams(double value) => MealScanCandidate(
    estimate: estimate,
    grams: value,
    match: match,
    autoCollected: autoCollected,
  );

  MealScanCandidate withSelectedFood(
    FoodRecord food, {
    bool autoCollected = false,
  }) => MealScanCandidate(
    estimate: estimate,
    grams: grams,
    autoCollected: autoCollected,
    match: LocalFoodMatch(
      status: LocalFoodMatchStatus.selected,
      selectedFood: food,
      suggestions: match.suggestions,
    ),
  );
}

final class MealScanCandidateDraft {
  const MealScanCandidateDraft({
    required this.items,
    required this.slot,
    required this.notes,
    required this.warnings,
  });

  final List<MealScanCandidate> items;
  final MealSlot slot;
  final String? notes;
  final List<String> warnings;

  List<MealItemDraft> get resolvedItems => items
      .map((item) => item.localNutrition)
      .whereType<MealItemDraft>()
      .toList(growable: false);

  NutritionValues get nutrition => resolvedItems.fold(
    NutritionValues.zero,
    (total, item) => total + item.nutrition,
  );

  bool get hasUnresolvedItems =>
      items.any((item) => item.localNutrition == null);

  MealScanCandidateDraft replaceItem(int index, MealScanCandidate value) {
    final next = List<MealScanCandidate>.of(items);
    next[index] = value;
    return copyWith(items: next);
  }

  MealScanCandidateDraft removeItem(int index) {
    final next = List<MealScanCandidate>.of(items)..removeAt(index);
    return copyWith(items: next);
  }

  MealScanCandidateDraft copyWith({
    List<MealScanCandidate>? items,
    MealSlot? slot,
    String? notes,
    bool clearNotes = false,
    List<String>? warnings,
  }) => MealScanCandidateDraft(
    items: items ?? this.items,
    slot: slot ?? this.slot,
    notes: clearNotes ? null : notes ?? this.notes,
    warnings: warnings ?? this.warnings,
  );
}
