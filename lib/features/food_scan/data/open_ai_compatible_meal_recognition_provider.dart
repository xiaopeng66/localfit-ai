import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai/data/ai_json_object_salvage.dart';
import 'package:localfit_ai/core/logging/privacy_logger.dart';
import 'package:localfit_ai/features/ai/data/ai_protocol_wire.dart';
import 'package:localfit_ai/features/ai/data/open_ai_compatible_transport.dart';
import 'package:localfit_ai/features/ai/domain/ai_transport.dart';
import 'package:localfit_ai/features/food_scan/data/meal_estimate_json_decoder.dart';
import 'package:localfit_ai/features/food_scan/data/prepared_meal_image_bytes_reader.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/open_ai_compatible_endpoint.dart';

/// Task adapter for meal-estimate.v1: owns the vision payload and local image
/// validation, and delegates every HTTP concern to the shared
/// [OpenAiCompatibleAiTransport].
final class OpenAiCompatibleMealRecognitionProvider
    implements MealRecognitionProvider {
  OpenAiCompatibleMealRecognitionProvider({
    required this.dio,
    required this.configurationReader,
    required this.apiKeyStore,
    required this.imageBytesReader,
    this.decoder = const MealEstimateJsonDecoder(),
    this.logger,
  });

  static const maxImageBytes = 5 * 1024 * 1024;
  static const maxRequestBytes = 7 * 1024 * 1024;
  static const maxImageDimension = 1600;
  static const maxModelLength = 256;
  static const maxOutputTokens = 1200;

  static const _instruction =
      '''Return only a JSON object matching this exact meal-estimate schema version 1. Do not use Markdown or prose. Estimate only foods visible in the image. If no food is visible, return {"schema_version":1,"items":[],"meal_notes":"","warnings":[]}. Each non-empty item must include name, estimated_grams, grams_range with min/max, cooking_method, ingredients, confidence, needs_confirmation, questions, and nutrition estimates for the estimated_grams: kcal, protein_g, carbs_g, fat_g (numbers, may be 0 when truly unestimable). All human-readable values (name, cooking_method, ingredients, meal_notes, warnings, questions) MUST be written in Simplified Chinese. Keep JSON keys exactly as specified. Example of a valid non-empty response: {"schema_version":1,"items":[{"name":"香蕉","estimated_grams":330,"grams_range":{"min":280,"max":380},"cooking_method":"生食","ingredients":["香蕉"],"confidence":0.95,"needs_confirmation":false,"questions":[],"kcal":306.9,"protein_g":3.63,"carbs_g":75.9,"fat_g":0.99}],"meal_notes":"","warnings":[]} If the image shows any food or text naming a food, items MUST be non-empty. The example above shows the exact shape of a valid item.''';

  final Dio dio;
  final AiProviderConfigurationReader configurationReader;
  final AiApiKeyStore apiKeyStore;
  final PreparedMealImageBytesReader imageBytesReader;
  final MealEstimateJsonDecoder decoder;
  final PrivacyLogger? logger;

  late final AiTransport transport = OpenAiCompatibleAiTransport(
    dio: dio,
    failureMessages: const AiTransportFailureMessages(
      timeout: '识别请求超时，请稍后重试。',
      cancelled: '识别已取消。',
      requestTooLarge: '处理后的图片过大，无法安全发送。',
    ),
  );

  @override
  Future<MealEstimateDraft> recognize(
    PreparedMealImage image, {
    MealRecognitionCancellationToken? cancellationToken,
  }) async {
    final startedAt = DateTime.now();
    var requestBytes = 0;
    var responseBytes = 0;
    try {
      final configuration = await _loadConfiguration();
      _throwIfCancelled(cancellationToken);
      final protocol = configuration.protocol;
      final endpoint = _parseEndpoint(configuration);
      final bytes = await _readAndValidateImage(image);
      _throwIfCancelled(cancellationToken);
      final apiKey = await _readApiKey();
      _throwIfCancelled(cancellationToken);
      final payload = protocol.visionRequestBody(
        model: configuration.model,
        maxTokens: maxOutputTokens,
        instruction: _instruction,
        jpegBytes: bytes,
        reasoning: configuration.reasoning,
      );
      final requestBody = jsonEncode(payload);
      requestBytes = utf8.encode(requestBody).length;

      final response = await transport.complete(
        AiTransportRequest(
          requestUri: endpoint.requestUri,
          body: requestBody,
          requestBytes: requestBytes,
          maxRequestBytes: maxRequestBytes,
          headers: protocol.authHeaders(apiKey),
          protocol: protocol,
        ),
        cancellationToken: _bridgeToken(cancellationToken),
      );
      responseBytes = response.responseBytes;

      // 与计划出口同源（2026-10-16 真机实测）：模型会先说明再贴 JSON、
      // 还爱包 ```json 围栏 ⇒ 用共享兜底抠出那一个 JSON 对象再交给严格解码器。
      final draft = decoder.decode(
        normalizeJsonEnvelopeContent(response.content),
      );
      _logCompletion(
        kind: 'success',
        startedAt: startedAt,
        requestBytes: requestBytes,
        responseBytes: responseBytes,
      );
      return draft;
    } on MealEstimateEmptyResult {
      _logCompletion(
        kind: 'empty_result',
        startedAt: startedAt,
        requestBytes: requestBytes,
        responseBytes: responseBytes,
      );
      rethrow;
    } on AppFailure catch (failure) {
      _logCompletion(
        kind: failure is NetworkFailure ? failure.kind.name : 'local_failure',
        startedAt: startedAt,
        requestBytes: requestBytes,
        responseBytes: responseBytes,
      );
      rethrow;
    } on MealImageFailure {
      _logCompletion(
        kind: 'image_failure',
        startedAt: startedAt,
        requestBytes: requestBytes,
        responseBytes: responseBytes,
      );
      rethrow;
    } on FormatException {
      const failure = NetworkFailure(
        '供应商返回格式无法识别。',
        kind: NetworkFailureKind.invalidResponse,
      );
      _logCompletion(
        kind: failure.kind.name,
        startedAt: startedAt,
        requestBytes: requestBytes,
        responseBytes: responseBytes,
      );
      throw failure;
    } catch (_) {
      const failure = NetworkFailure(
        '识别请求未能完成，请稍后重试或改为手动记录。',
        kind: NetworkFailureKind.connection,
      );
      _logCompletion(
        kind: failure.kind.name,
        startedAt: startedAt,
        requestBytes: requestBytes,
        responseBytes: responseBytes,
      );
      throw failure;
    }
  }

  AiTransportCancellationToken? _bridgeToken(
    MealRecognitionCancellationToken? token,
  ) {
    if (token == null) return null;
    final bridged = AiTransportCancellationToken();
    if (token.isCancelled) {
      bridged.cancel();
    } else {
      token.whenCancelled.then((_) => bridged.cancel());
    }
    return bridged;
  }

  OpenAiCompatibleEndpoint _parseEndpoint(
    AiProviderConfiguration configuration,
  ) {
    final endpoint = OpenAiCompatibleEndpoint.tryParse(
      configuration.baseUrl,
      protocol: configuration.protocol,
    );
    if (endpoint == null) {
      throw const ValidationFailure('AI Base URL 配置无效，请在设置中更新。');
    }
    return endpoint;
  }

  Future<AiProviderConfiguration> _loadConfiguration() async {
    final configuration = await configurationReader.loadConfiguration();
    if (configuration == null) {
      throw const ValidationFailure('请先在设置中保存 AI 配置。');
    }
    if (configuration.model.trim().isEmpty ||
        configuration.model.trim().length > maxModelLength) {
      throw const ValidationFailure('AI 模型配置无效，请在设置中更新。');
    }
    return configuration;
  }

  Future<String> _readApiKey() async {
    final apiKey = await apiKeyStore.read();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw const ValidationFailure('请先在设置中保存 API Key。');
    }
    return apiKey.trim();
  }

  Future<Uint8List> _readAndValidateImage(PreparedMealImage image) async {
    if (image.width <= 0 ||
        image.height <= 0 ||
        image.width > maxImageDimension ||
        image.height > maxImageDimension ||
        image.byteLength <= 0 ||
        image.byteLength > maxImageBytes) {
      throw const ValidationFailure('已处理的餐食图片无效或过大。');
    }
    try {
      final bytes = await imageBytesReader.read(image);
      if (bytes.length != image.byteLength ||
          bytes.length > maxImageBytes ||
          !_isJpeg(bytes)) {
        throw const ValidationFailure('已处理的餐食图片无效或过大。');
      }
      return bytes;
    } on MealImageFailure {
      rethrow;
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const MealImageFailure('无法读取已处理的餐食图片。');
    }
  }

  void _throwIfCancelled(MealRecognitionCancellationToken? token) {
    if (token?.isCancelled ?? false) {
      throw const NetworkFailure('识别已取消。', kind: NetworkFailureKind.cancelled);
    }
  }

  bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[bytes.length - 2] == 0xff &&
      bytes[bytes.length - 1] == 0xd9;

  void _logCompletion({
    required String kind,
    required DateTime startedAt,
    required int requestBytes,
    required int responseBytes,
  }) {
    logger?.log(
      LogLevel.info,
      'meal_recognition_finished',
      fields: {
        'resultKind': kind,
        'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        'requestBytes': requestBytes,
        'responseBytes': responseBytes,
      },
    );
  }
}
