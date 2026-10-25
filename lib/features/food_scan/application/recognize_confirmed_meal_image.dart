import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

final class RecognizeConfirmedMealImage {
  const RecognizeConfirmedMealImage({required this.provider});

  final MealRecognitionProvider provider;

  Future<MealEstimateDraft> call(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) => provider.recognize(image, cancellationToken: cancellationToken);
}
