import 'dart:async';

import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

final class GramRange {
  const GramRange({required this.min, required this.max});

  final double min;
  final double max;
}

/// AI 对该条目按 estimated_grams 给出的整份营养估算（可选字段）。
///
/// 这是「本地食物库没有匹配项」时的营养兜底来源，也是自动收录
/// 用户自建食物（折算每 100g）的数据来源。
final class MealEstimateNutrition {
  const MealEstimateNutrition({
    required this.kcal,
    required this.proteinGrams,
    required this.carbsGrams,
    required this.fatGrams,
  });

  final double kcal;
  final double proteinGrams;
  final double carbsGrams;
  final double fatGrams;
}

final class MealEstimateItem {
  const MealEstimateItem({
    required this.name,
    required this.estimatedGrams,
    required this.gramsRange,
    required this.confidence,
    required this.ingredients,
    required this.needsConfirmation,
    required this.questions,
    required this.cookingMethod,
    this.nutrition,
  });

  final String name;
  final double estimatedGrams;
  final GramRange gramsRange;
  final String? cookingMethod;
  final List<String> ingredients;
  final double confidence;
  final bool needsConfirmation;
  final List<String> questions;

  /// AI 整份营养估算；旧供应商/旧版本可能不返回（保持可选）。
  final MealEstimateNutrition? nutrition;
}

final class MealEstimateDraft {
  const MealEstimateDraft({
    required this.items,
    required this.warnings,
    required this.mealNotes,
  });

  final List<MealEstimateItem> items;
  final String? mealNotes;
  final List<String> warnings;
}

final class MealEstimateEmptyResult implements Exception {
  const MealEstimateEmptyResult([this.message = '未识别出可供确认的食物，请改为手动记录或重试。']);

  final String message;

  @override
  String toString() => message;
}

final class MealRecognitionCancellationToken {
  MealRecognitionCancellationToken();

  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

abstract interface class MealRecognitionProvider {
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  });
}
