import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/application/recognize_confirmed_meal_image.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

void main() {
  test(
    'delegates image and cancellation token without extra behavior',
    () async {
      final provider = _Provider();
      final useCase = RecognizeConfirmedMealImage(provider: provider);
      final token = MealRecognitionCancellationToken();
      const image = PreparedMealImage(
        path: 'temporary/meal.jpg',
        width: 100,
        height: 80,
        byteLength: 4,
      );

      await useCase(image, cancellationToken: token);

      expect(provider.image, same(image));
      expect(provider.token, same(token));
    },
  );
}

final class _Provider implements MealRecognitionProvider {
  PreparedMealImage? image;
  MealRecognitionCancellationToken? token;

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage value, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async {
    image = value;
    token = cancellationToken;
    return const MealEstimateDraft(items: [], warnings: [], mealNotes: null);
  }
}
