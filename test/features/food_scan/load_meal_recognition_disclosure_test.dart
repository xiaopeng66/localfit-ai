import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/food_scan/application/load_meal_recognition_disclosure.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';

void main() {
  test('returns only normalized non-secret disclosure details', () async {
    final disclosure = await LoadMealRecognitionDisclosure(
      configurationReader: const _Reader(
        AiProviderConfiguration(
          baseUrl: 'https://API.example.com/v1',
          model: 'vision-model',
        ),
      ),
    )();

    expect(disclosure.destinationHost, 'api.example.com');
    expect(disclosure.baseUrl, 'https://api.example.com/v1/');
    expect(disclosure.model, 'vision-model');
  });

  test(
    'rejects missing or invalid local configuration before recognition',
    () async {
      await expectLater(
        LoadMealRecognitionDisclosure(
          configurationReader: const _Reader(null),
        )(),
        throwsA(isA<ValidationFailure>()),
      );
      await expectLater(
        LoadMealRecognitionDisclosure(
          configurationReader: const _Reader(
            AiProviderConfiguration(
              baseUrl: 'http://example.com',
              model: 'vision',
            ),
          ),
        )(),
        throwsA(isA<ValidationFailure>()),
      );
    },
  );
}

final class _Reader implements AiProviderConfigurationReader {
  const _Reader(this.configuration);

  final AiProviderConfiguration? configuration;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => configuration;
}
