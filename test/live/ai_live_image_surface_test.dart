import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/food_scan/data/open_ai_compatible_meal_recognition_provider.dart';
import 'package:localfit_ai/features/food_scan/data/prepared_meal_image_bytes_reader.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';

/// 检查生产出口真的携带合成图；上游拒图的明确降级不算视觉识别成功。
/// 只记录分支布尔值，不输出回复、图片字节或凭据。默认无配置不外呼。
void main() {
  final env = Platform.environment;
  final key = env['LF_LIVE_KEY'] ?? '';
  final base = env['LF_LIVE_BASE'] ?? '';
  final model = env['LF_LIVE_MODEL'] ?? '';
  final enabled = key.isNotEmpty && base.isNotEmpty && model.isNotEmpty;
  final configuration = _LiveConfiguration(
    AiProviderConfiguration(
      baseUrl: base,
      model: model,
      protocol: AiProviderProtocol.fromStorage(env['LF_LIVE_PROTOCOL']),
    ),
  );
  final apiKeyStore = AiApiKeyStore(store: _LiveKey(key));
  final image = File('E:/AI/Zcode/tmp/frames/synth/vision-probe.jpg');

  test(
    'AI 合成图片：对话首请求携图，识图与供应商拒图降级分别记录',
    () async {
      final bytes = await image.readAsBytes();
      final tracker = _ImageRequestTracker(bytes);
      final dio = Dio()..interceptors.add(tracker);
      addTearDown(() => dio.close(force: true));
      final service = OpenAiCompatibleConversationService(
        dio: dio,
        configurationReader: configuration,
        apiKeyStore: apiKeyStore,
      );
      final reply = StringBuffer();
      await service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'synthetic-image-live',
                role: ConversationRole.user,
                text: '这张图里写了什么？只回图上的文字。',
                kind: ConversationMessageKind.image,
                imagePath: image.path,
                createdAt: DateTime.utc(2026, 11, 10, 12),
              ),
            ],
            onProgress: reply.write,
          )
          .drain<void>();
      final text = reply.toString();
      final fallback = text.contains(
        OpenAiCompatibleConversationService.imageRejectionNote,
      );
      final visual =
          !fallback &&
          (text.toUpperCase().contains('BANANA') || text.contains('香蕉'));
      debugPrint('[IMAGE-LIVE] chat_image_request=${tracker.firstWasImage}');
      debugPrint('[IMAGE-LIVE] chat_visual_success=$visual');
      debugPrint('[IMAGE-LIVE] chat_explicit_fallback=$fallback');
      expect(tracker.firstWasImage, isTrue);
      expect(tracker.imageRequests, 1);
      expect(tracker.requests, lessThanOrEqualTo(2));
      expect(text.trim(), isNotEmpty);
      expect(visual || fallback, isTrue);
      if (fallback) {
        expect(tracker.requests, 2);
        expect(
          text
              .replaceAll(
                OpenAiCompatibleConversationService.imageRejectionNote,
                '',
              )
              .trim(),
          isNotEmpty,
        );
      }
    },
    skip: enabled ? false : '未注入 LF_LIVE_KEY/BASE/MODEL，不外呼',
    timeout: const Timeout(Duration(minutes: 6)),
  );

  test(
    'AI 合成图片：识餐实际携图，结构化结果与可行动失败分别记录',
    () async {
      final bytes = await image.readAsBytes();
      final tracker = _ImageRequestTracker(bytes);
      final dio = Dio()..interceptors.add(tracker);
      addTearDown(() => dio.close(force: true));
      final provider = OpenAiCompatibleMealRecognitionProvider(
        dio: dio,
        configurationReader: configuration,
        apiKeyStore: apiKeyStore,
        imageBytesReader: _BytesReader(bytes),
      );
      var returnedEstimate = false;
      var actionableFailure = false;
      try {
        final draft = await provider.recognize(
          PreparedMealImage(
            path: image.path,
            width: 900,
            height: 600,
            byteLength: bytes.length,
          ),
        );
        expect(draft.items, isNotEmpty);
        for (final item in draft.items) {
          expect(item.name.trim(), isNotEmpty);
          expect(item.estimatedGrams, greaterThan(0));
        }
        returnedEstimate = true;
      } on AppFailure catch (failure) {
        expect(failure.message.trim(), isNotEmpty);
        expect(failure.message, isNot(contains('Exception')));
        actionableFailure = true;
      }
      debugPrint('[IMAGE-LIVE] scan_image_request=${tracker.firstWasImage}');
      debugPrint('[IMAGE-LIVE] scan_returned_estimate=$returnedEstimate');
      debugPrint('[IMAGE-LIVE] scan_actionable_failure=$actionableFailure');
      expect(tracker.firstWasImage, isTrue);
      expect(tracker.imageRequests, 1);
      expect(tracker.requests, 1);
      expect(returnedEstimate || actionableFailure, isTrue);
    },
    skip: enabled ? false : '未注入 LF_LIVE_KEY/BASE/MODEL，不外呼',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

final class _ImageRequestTracker extends Interceptor {
  _ImageRequestTracker(Uint8List bytes)
    : dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';

  final String dataUrl;
  var requests = 0;
  var imageRequests = 0;
  var firstWasImage = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final data = options.data;
    final body = data is String ? jsonDecode(data) : data;
    final hasImage = _hasImage(body);
    if (requests == 0) firstWasImage = hasImage;
    requests++;
    if (hasImage) imageRequests++;
    handler.next(options);
  }

  bool _hasImage(Object? value) {
    if (value is Map) {
      if (value['type'] == 'input_image' && value['image_url'] == dataUrl) {
        return true;
      }
      return value.values.any(_hasImage);
    }
    return value is List && value.any(_hasImage);
  }
}

final class _LiveConfiguration implements AiProviderConfigurationReader {
  const _LiveConfiguration(this.configuration);

  final AiProviderConfiguration configuration;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => configuration;
}

final class _LiveKey implements SecureKeyValueStore {
  const _LiveKey(this.key);

  final String key;

  @override
  Future<String?> read(String key) async =>
      key == AiApiKeyStore.storageKey ? this.key : null;

  @override
  Future<void> write(String key, String value) async =>
      throw UnsupportedError('Read-only live fixture');

  @override
  Future<void> delete(String key) async =>
      throw UnsupportedError('Read-only live fixture');
}

final class _BytesReader implements PreparedMealImageBytesReader {
  const _BytesReader(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> read(PreparedMealImage image) async => bytes;
}
