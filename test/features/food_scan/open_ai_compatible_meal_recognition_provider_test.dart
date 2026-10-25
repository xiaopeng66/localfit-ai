import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/logging/privacy_logger.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/features/food_scan/data/meal_estimate_json_decoder.dart';
import 'package:localfit_ai/features/food_scan/data/open_ai_compatible_meal_recognition_provider.dart';
import 'package:localfit_ai/features/food_scan/data/prepared_meal_image_bytes_reader.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';

void main() {
  const apiKey = 'test-secret-key';
  const hostileResponse = 'provider raw response must stay private';
  const imagePath = '/private/meal.jpg';
  final imageBytes = Uint8List.fromList([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9]);
  final image = PreparedMealImage(
    path: imagePath,
    width: 1600,
    height: 1200,
    byteLength: imageBytes.length,
  );

  _TestHarness createHarness({
    String baseUrl = 'https://api.example.com/v1',
    String? storedKey = apiKey,
    Uint8List? bytes,
    ResponseBody? response,
    DioExceptionType? failure,
  }) {
    final adapter = _RecordingAdapter(response: response, failure: failure);
    final logs = <String>[];
    final provider = OpenAiCompatibleMealRecognitionProvider(
      dio: Dio(),
      configurationReader: _ConfigurationReader(
        AiProviderConfiguration(baseUrl: baseUrl, model: 'vision-model'),
      ),
      apiKeyStore: AiApiKeyStore(
        store: _MemorySecureStore()
          ..values[AiApiKeyStore.storageKey] = storedKey,
      ),
      imageBytesReader: _ImageBytesReader(bytes ?? imageBytes),
      decoder: const MealEstimateJsonDecoder(),
      logger: PrivacyLogger(writer: logs.add),
    );
    provider.dio.httpClientAdapter = adapter;
    return _TestHarness(provider, adapter, logs);
  }

  test('散文 + 围栏包裹时：抢救出那一个 JSON（真机实测的模型习惯）', () async {
    // 与计划出口同源的问题：模型先说一句、再贴 JSON，严格解码器一律判
    // 「供应商返回格式无法识别。」（2026-10-16 真机实测）。
    final chatty =
        '我看了一下这张图，大概是：\n```json\n'
        '$_validDraft\n```';
    final harness = createHarness(response: _jsonResponse(_envelope(chatty)));
    final draft = await harness.provider.recognize(image);
    expect(draft.items.single.name, '米饭');
  });

  test('posts only to fixed endpoint with a header-only API key', () async {
    final harness = createHarness(response: _jsonResponse(_validEnvelope));

    final draft = await harness.provider.recognize(image);

    expect(draft.items.single.name, '米饭');
    expect(harness.adapter.requests, hasLength(1));
    final request = harness.adapter.requests.single;
    expect(
      request.uri.toString(),
      'https://api.example.com/v1/chat/completions',
    );
    expect(request.method, 'POST');
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
    expect(request.connectTimeout, isNot(Duration.zero));
    expect(request.sendTimeout, isNot(Duration.zero));
    expect(request.receiveTimeout, isNot(Duration.zero));
    expect(request.headers['authorization'], 'Bearer $apiKey');
    expect(request.headers[Headers.acceptHeader], Headers.jsonContentType);
    expect(harness.adapter.bodies.single, isNot(contains(apiKey)));
    expect(harness.adapter.bodies.single, isNot(contains(imagePath)));
    final payload =
        jsonDecode(harness.adapter.bodies.single) as Map<String, Object?>;
    final messages = payload['messages'] as List<Object?>;
    final content =
        (messages.single as Map<String, Object?>)['content'] as List<Object?>;
    final imageUrl =
        ((content.last as Map<String, Object?>)['image_url']
                as Map<String, Object?>)['url']
            as String;
    expect(imageUrl, 'data:image/jpeg;base64,${base64Encode(imageBytes)}');
  });

  test('does not send when local configuration or key is invalid', () async {
    final invalidUrl = createHarness(
      baseUrl: 'https://api.example.com/v1/../admin',
      response: _jsonResponse(_validEnvelope),
    );
    await expectLater(
      invalidUrl.provider.recognize(image),
      throwsA(isA<ValidationFailure>()),
    );
    expect(invalidUrl.adapter.requests, isEmpty);

    final noKey = createHarness(
      storedKey: null,
      response: _jsonResponse(_validEnvelope),
    );
    await expectLater(
      noKey.provider.recognize(image),
      throwsA(isA<ValidationFailure>()),
    );
    expect(noKey.adapter.requests, isEmpty);
  });

  test(
    'classifies status failures without leaking response data or key',
    () async {
      final harness = createHarness(
        response: _jsonResponse(hostileResponse, statusCode: 401),
      );

      await expectLater(
        harness.provider.recognize(image),
        throwsA(
          isA<NetworkFailure>()
              .having(
                (failure) => failure.kind,
                'kind',
                NetworkFailureKind.authentication,
              )
              .having(
                (failure) => failure.message,
                'message',
                isNot(contains(hostileResponse)),
              )
              .having(
                (failure) => failure.message,
                'message',
                isNot(contains(apiKey)),
              ),
        ),
      );
      expect(harness.adapter.requests, hasLength(1));
      expect(harness.logs.join(), isNot(contains(apiKey)));
      expect(harness.logs.join(), isNot(contains(hostileResponse)));
      expect(harness.logs.join(), isNot(contains(imagePath)));
    },
  );

  test(
    'rejects redirects, malformed envelopes, and markdown content safely',
    () async {
      final redirect = createHarness(
        response: _jsonResponse(
          _validEnvelope,
          statusCode: 302,
          isRedirect: true,
        ),
      );
      await _expectNetworkKind(
        redirect.provider.recognize(image),
        NetworkFailureKind.secureConnection,
      );

      final malformed = createHarness(
        response: _jsonResponse('{"choices":[]}'),
      );
      await _expectNetworkKind(
        malformed.provider.recognize(image),
        NetworkFailureKind.invalidResponse,
      );

      final markdown = createHarness(
        response: _jsonResponse(_envelope('```json\n{}\n```')),
      );
      await _expectNetworkKind(
        markdown.provider.recognize(image),
        NetworkFailureKind.invalidResponse,
      );
    },
  );

  test('preserves empty result and sends no automatic retries', () async {
    final harness = createHarness(
      response: _jsonResponse(_envelope(_emptyDraft)),
    );

    await expectLater(
      harness.provider.recognize(image),
      throwsA(isA<MealEstimateEmptyResult>()),
    );
    expect(harness.adapter.requests, hasLength(1));
  });

  test('maps Dio timeout and cancellation safely without retry', () async {
    final timeout = createHarness(
      failure: DioExceptionType.receiveTimeout,
      response: _jsonResponse(_validEnvelope),
    );
    await _expectNetworkKind(
      timeout.provider.recognize(image),
      NetworkFailureKind.timeout,
    );
    expect(timeout.adapter.requests, hasLength(1));

    final cancelled = createHarness(response: _jsonResponse(_validEnvelope));
    final token = MealRecognitionCancellationToken()..cancel();
    await _expectNetworkKind(
      cancelled.provider.recognize(image, cancellationToken: token),
      NetworkFailureKind.cancelled,
    );
    expect(cancelled.adapter.requests, isEmpty);
  });

  test('rejects invalid image bytes before network access', () async {
    final badImage = createHarness(
      bytes: Uint8List.fromList([1, 2, 3]),
      response: _jsonResponse(_validEnvelope),
    );
    final invalid = PreparedMealImage(
      path: imagePath,
      width: 1600,
      height: 1200,
      byteLength: 3,
    );

    await expectLater(
      badImage.provider.recognize(invalid),
      throwsA(isA<ValidationFailure>()),
    );
    expect(badImage.adapter.requests, isEmpty);
  });
}

Future<void> _expectNetworkKind(
  Future<Object?> future,
  NetworkFailureKind kind,
) => expectLater(
  future,
  throwsA(
    isA<NetworkFailure>().having((failure) => failure.kind, 'kind', kind),
  ),
);

ResponseBody _jsonResponse(
  String body, {
  int statusCode = 200,
  bool isRedirect = false,
}) => ResponseBody.fromString(
  body,
  statusCode,
  isRedirect: isRedirect,
  headers: const {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

final class _TestHarness {
  const _TestHarness(this.provider, this.adapter, this.logs);

  final OpenAiCompatibleMealRecognitionProvider provider;
  final _RecordingAdapter adapter;
  final List<String> logs;
}

final class _ConfigurationReader implements AiProviderConfigurationReader {
  const _ConfigurationReader(this.configuration);

  final AiProviderConfiguration? configuration;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => configuration;
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String?>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _ImageBytesReader implements PreparedMealImageBytesReader {
  const _ImageBytesReader(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> read(PreparedMealImage image) async => bytes;
}

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.response, this.failure});

  final ResponseBody? response;
  final DioExceptionType? failure;
  final requests = <RequestOptions>[];
  final bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final chunks = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
    }
    bodies.add(utf8.decode(chunks));
    if (failure != null) {
      throw DioException(
        requestOptions: options,
        type: failure!,
        error: 'transport failure',
      );
    }
    return response!;
  }

  @override
  void close({bool force = false}) {}
}

const _validDraft = '''
{"schema_version":1,"items":[{"name":"米饭","estimated_grams":180,"grams_range":{"min":140,"max":220},"cooking_method":"蒸煮","ingredients":["大米"],"confidence":0.78,"needs_confirmation":false,"questions":[]}],"meal_notes":"午餐","warnings":[]}
''';

const _emptyDraft =
    '{"schema_version":1,"items":[],"meal_notes":"","warnings":[]}';

String _envelope(String content) => jsonEncode({
  'choices': [
    {
      'message': {'content': content},
    },
  ],
});

final String _validEnvelope = _envelope(_validDraft);
