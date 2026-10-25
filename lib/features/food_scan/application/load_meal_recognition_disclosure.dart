import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/open_ai_compatible_endpoint.dart';

final class MealRecognitionDisclosure {
  const MealRecognitionDisclosure({
    required this.destinationHost,
    required this.baseUrl,
    required this.model,
  });

  final String destinationHost;
  final String baseUrl;
  final String model;
}

final class LoadMealRecognitionDisclosure {
  const LoadMealRecognitionDisclosure({required this.configurationReader});

  static const maxModelLength = 256;

  final AiProviderConfigurationReader configurationReader;

  Future<MealRecognitionDisclosure> call() async {
    final configuration = await configurationReader.loadConfiguration();
    if (configuration == null) {
      throw const ValidationFailure('请先在设置中保存 AI 配置。');
    }

    final endpoint = OpenAiCompatibleEndpoint.tryParse(
      configuration.baseUrl,
      protocol: configuration.protocol,
    );
    if (endpoint == null) {
      throw const ValidationFailure('AI Base URL 配置无效，请在设置中更新。');
    }

    final model = configuration.model.trim();
    if (model.isEmpty || model.length > maxModelLength) {
      throw const ValidationFailure('AI 模型配置无效，请在设置中更新。');
    }

    return MealRecognitionDisclosure(
      destinationHost: endpoint.requestUri.host,
      baseUrl: endpoint.baseUrl,
      model: model,
    );
  }
}
