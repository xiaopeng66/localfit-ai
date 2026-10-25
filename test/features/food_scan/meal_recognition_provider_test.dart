import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/food_scan/data/meal_estimate_json_decoder.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

void main() {
  test(
    'fake provider returns the decoded draft and records its prepared image',
    () async {
      final provider = _FakeMealRecognitionProvider(
        decoder: const MealEstimateJsonDecoder(),
        fixture: _validFixture,
      );
      const image = PreparedMealImage(
        path: 'temporary/meal.jpg',
        width: 1600,
        height: 1200,
        byteLength: 200000,
      );

      final draft = await provider.recognize(image);

      expect(provider.images, [same(image)]);
      expect(draft.items.single.name, '米饭');
      expect(draft.items.single.estimatedGrams, 180);
    },
  );

  test(
    'fake provider passes through its configured recognition failure',
    () async {
      const failure = MealEstimateEmptyResult('没有识别到食物。');
      final provider = _FakeMealRecognitionProvider(failure: failure);

      await expectLater(
        provider.recognize(
          const PreparedMealImage(
            path: 'temporary/meal.jpg',
            width: 1,
            height: 1,
            byteLength: 1,
          ),
        ),
        throwsA(same(failure)),
      );
    },
  );
}

final class _FakeMealRecognitionProvider implements MealRecognitionProvider {
  _FakeMealRecognitionProvider({this.decoder, this.fixture, this.failure})
    : assert(fixture != null || failure != null);

  final MealEstimateJsonDecoder? decoder;
  final String? fixture;
  final Object? failure;
  final images = <PreparedMealImage>[];

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async {
    images.add(image);
    if (failure case final Object error?) throw error;
    return decoder!.decode(fixture!);
  }
}

const _validFixture = '''
{
  "schema_version": 1,
  "items": [
    {
      "name": "米饭",
      "estimated_grams": 180,
      "grams_range": {"min": 140, "max": 220},
      "cooking_method": "蒸煮",
      "ingredients": ["大米"],
      "confidence": 0.78,
      "needs_confirmation": false,
      "questions": []
    }
  ],
  "meal_notes": "午餐",
  "warnings": []
}
''';
