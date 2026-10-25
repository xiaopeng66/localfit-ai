import 'package:localfit_ai/features/food_scan/application/meal_scan_candidate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 对话式识别修正（2.0-6h）。
///
/// 用户编辑 AI 候选：改名、调克数、或从本地食物库换一个。
/// 操作仅在本地草案发生，可信结果来自用户选定的本地食物
///（本地重算优先于 AI 估算）。不写 DB，草案值永远只是草案。
final class ConversationalRecognitionCorrection {
  const ConversationalRecognitionCorrection({
    required this.candidate,
    required this.searchFoods,
  });

  final MealScanCandidate candidate;
  final Future<List<FoodRecord>> Function(String query) searchFoods;

  /// 改克数：校验后等比缩放营养，本地食物优先、AI 估算兜底。
  CorrectionResult<MealScanCandidate> correctGrams(double grams) {
    if (!_isValidGrams(grams)) {
      return CorrectionResult.rejected('克数必须是正数（不能为 0、负数、NaN 或无穷）。');
    }
    return CorrectionResult.accepted(candidate.withGrams(grams));
  }

  /// 改名称：标签修改本地事实，不影响克数/营养源。
  CorrectionResult<MealScanCandidate> correctName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return CorrectionResult.rejected('名称不能为空。');
    }
    return CorrectionResult.accepted(
      MealScanCandidate(
        estimate: MealEstimateItem(
          name: trimmed,
          estimatedGrams: candidate.estimate.estimatedGrams,
          gramsRange: candidate.estimate.gramsRange,
          confidence: candidate.estimate.confidence,
          ingredients: candidate.estimate.ingredients,
          needsConfirmation: candidate.estimate.needsConfirmation,
          questions: candidate.estimate.questions,
          cookingMethod: candidate.estimate.cookingMethod,
          nutrition: candidate.estimate.nutrition,
        ),
        grams: candidate.grams,
        match: candidate.match,
        autoCollected: candidate.autoCollected,
      ),
    );
  }

  /// 从本地食物库选择一项作为匹配食物。
  Future<CorrectionResult<MealScanCandidate>> selectFood(String name) async {
    final trimmed = name.trim();
    final foods = await searchFoods(trimmed);
    if (foods.isEmpty) {
      return CorrectionResult.rejected('未找到本地食物：$trimmed。');
    }
    FoodRecord? match = foods.firstWhere(
      (food) => food.name == trimmed,
      orElse: () => foods.firstWhere(
        (food) => food.name.contains(trimmed),
        orElse: () => foods.first,
      ),
    );
    return CorrectionResult.accepted(candidate.withSelectedFood(match));
  }

  bool _isValidGrams(double grams) =>
      grams.isFinite && grams > 0 && !grams.isInfinite && !grams.isNaN;
}

/// 修正结果：接受（recomputed）或拒绝（带本地文案）。
final class CorrectionResult<T> {
  const CorrectionResult.accepted(this.value)
    : isRejected = false,
      rejection = null;

  const CorrectionResult.rejected(this.rejection)
    : isRejected = true,
      value = null;

  final bool isRejected;
  final T? value;
  final String? rejection;
}
