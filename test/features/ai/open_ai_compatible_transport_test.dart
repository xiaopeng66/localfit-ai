import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai/data/ai_protocol_wire.dart';
import 'package:localfit_ai/features/ai/data/open_ai_compatible_transport.dart';
import 'package:localfit_ai/features/ai/domain/ai_transport.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';

void main() {
  const apiKey = 'test-secret-key';
  const endpoint = 'https://api.example.com/v1/chat/completions';
  const messages = AiTransportFailureMessages(
    timeout: '测试超时。',
    cancelled: '测试已取消。',
    requestTooLarge: '测试请求过大。',
  );

  AiTransportRequest request({
    String body = '{"model":"m","messages":[]}',
    int maxRequestBytes = 64 * 1024,
    Uri? requestUri,
    AiProviderProtocol protocol = AiProviderProtocol.chatCompletions,
    Map<String, String>? headers,
  }) {
    final resolvedBody = body;
    return AiTransportRequest(
      requestUri: requestUri ?? Uri.parse(endpoint),
      body: resolvedBody,
      requestBytes: utf8.encode(resolvedBody).length,
      maxRequestBytes: maxRequestBytes,
      // 认证头由调用方按协议 wire 表注入（生产里各出口就是这么传的）。
      headers: headers ?? protocol.authHeaders(apiKey),
      protocol: protocol,
    );
  }

  (OpenAiCompatibleAiTransport, _RecordingAdapter) createTransport({
    ResponseBody? response,
    DioExceptionType? failure,
    bool throwOnCancel = false,
  }) {
    final adapter = _RecordingAdapter(
      response: response,
      failure: failure,
      throwOnCancel: throwOnCancel,
    );
    final transport = OpenAiCompatibleAiTransport(
      dio: Dio(),
      failureMessages: messages,
    );
    transport.dio.httpClientAdapter = adapter;
    return (transport, adapter);
  }

  test(
    'sends a header-only JSON POST without redirects or key in body',
    () async {
      final (transport, adapter) = createTransport(
        response: _jsonResponse(_envelope(_validContent)),
      );

      final response = await transport.complete(request());

      expect(response.content, _validContent);
      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single;
      expect(sent.uri.toString(), endpoint);
      expect(sent.method, 'POST');
      expect(sent.followRedirects, isFalse);
      expect(sent.maxRedirects, 0);
      expect(sent.connectTimeout, isNot(Duration.zero));
      expect(sent.sendTimeout, isNot(Duration.zero));
      expect(sent.receiveTimeout, isNot(Duration.zero));
      expect(sent.headers['authorization'], 'Bearer $apiKey');
      expect(sent.headers[Headers.acceptHeader], Headers.jsonContentType);
      expect(adapter.bodies.single, isNot(contains(apiKey)));
      expect(response.requestBytes, utf8.encode(request().body).length);
      expect(response.responseBytes, _envelope(_validContent).length);
    },
  );

  test('超时预算自洽：连接 ≤ 发送 ≤ 接收 ≤ 总上限，且总上限 ≥ 会话流式上限', () {
    // 2026-10-16 真实供应商实测（用户授权后）：`deepseek-ai/deepseek-v4.1-flash`
    // 单请求 TTFB ≈ 11s、小回复整请求 40–46s、训练计划那种 ~350 token 的回复
    // 31–55s（方差大）。旧口径是 连接 10 / 发送 30 / **接收 45** / **总 60**，
    // 于是非流式的计划请求在 45s 的**空闲接收**上先超时
    // （`e2e ④ NetworkFailure: 计划请求超时` 实测），而流式那条本可以走满
    // 会话服务给的 3 分钟。
    //
    // 这条判据把「总上限 ≥ 会话流式上限」钉成不变量：传输层的总 deadline
    // 不该比它下面那一层声明的流式预算还短，否则后者形同虚设
    // （改回 60s 会立刻变红——本判据的隔离变异见证）。它同时约束层级顺序，
    // 防止「接收 45 但发送 60」这类反直觉组合再回来。
    expect(
      OpenAiCompatibleAiTransport.connectTimeout <=
          OpenAiCompatibleAiTransport.sendTimeout,
      isTrue,
    );
    expect(
      OpenAiCompatibleAiTransport.sendTimeout <=
          OpenAiCompatibleAiTransport.receiveTimeout,
      isTrue,
    );
    expect(
      OpenAiCompatibleAiTransport.receiveTimeout <=
          OpenAiCompatibleAiTransport.totalTimeout,
      isTrue,
    );
    final conversationService = OpenAiCompatibleConversationService(
      dio: Dio(),
      configurationReader: _NullConfigurationReader(),
      apiKeyStore: AiApiKeyStore(store: _EmptySecureStore()),
    );
    expect(
      OpenAiCompatibleAiTransport.totalTimeout >=
          conversationService.maxStreamDuration,
      isTrue,
      reason: '传输总上限短于会话流式上限 ⇒ 慢供应商永远走不到那一层预算',
    );
  });

  test('推理型模型的空 content：报可解释错误而不是「格式无法识别」', () async {
    // docs/29 §P4：choices[0].message 只有 reasoning_content、content 为空
    // ⇒ NetworkFailure 携带可解释文案（不是 invalidResponse 的通用口径），
    // UI 上显示的就是这句话而不是「返回格式无法识别」。
    final (transport, adapter) = createTransport(
      response: _jsonResponse(
        jsonEncode({
          'choices': [
            {
              'message': {'content': null, 'reasoning_content': '推理了一长段'},
            },
          ],
        }),
      ),
    );

    await expectLater(
      transport.complete(request()),
      throwsA(
        isA<NetworkFailure>().having(
          (failure) => failure.message,
          'message',
          '模型只返回了推理内容，请在设置里关闭推理或增大输出上限。',
        ),
      ),
    );
    expect(adapter.requests, hasLength(1));
  });

  test('rejects oversized request bodies without sending', () async {
    final (transport, adapter) = createTransport();

    await expectLater(
      transport.complete(request(body: 'x' * 10, maxRequestBytes: 5)),
      throwsA(
        isA<ValidationFailure>().having(
          (failure) => failure.message,
          'message',
          messages.requestTooLarge,
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('rejects insecure endpoint URIs without sending', () async {
    for (final insecure in [
      'http://api.example.com/v1/chat/completions',
      'https://api.example.com:80/v1/chat/completions',
      'https://api.example.com/v1/chat/completions?debug=1',
      'https://api.example.com/v1/chat/completions#fragment',
      'https://user@api.example.com/v1/chat/completions',
    ]) {
      final (transport, adapter) = createTransport();

      await expectLater(
        transport.complete(request(requestUri: Uri.parse(insecure))),
        throwsA(isA<ValidationFailure>()),
        reason: insecure,
      );
      expect(adapter.requests, isEmpty, reason: insecure);
    }
  });

  test('rejects empty and oversized responses safely', () async {
    final empty = createTransport(response: _jsonResponse(''));
    await _expectInvalidResponse(empty.$1.complete(request()));
    expect(empty.$2.requests, hasLength(1));

    final declaredTooLarge = createTransport(
      response: ResponseBody.fromString(
        _envelope(_validContent),
        200,
        headers: const {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          Headers.contentLengthHeader: ['${128 * 1024 + 1}'],
        },
      ),
    );
    await _expectInvalidResponse(declaredTooLarge.$1.complete(request()));

    final streamedTooLarge = createTransport(
      response: ResponseBody(
        Stream<Uint8List>.fromIterable([
          Uint8List.fromList(List.filled(128 * 1024 + 1, 0x78)),
        ]),
        200,
        headers: const {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    await _expectInvalidResponse(streamedTooLarge.$1.complete(request()));
  });

  test('rejects redirects and classifies HTTP status failures', () async {
    final redirect = createTransport(
      response: _jsonResponse(_envelope(_validContent), statusCode: 302),
    );
    await _expectKind(
      redirect.$1.complete(request()),
      NetworkFailureKind.secureConnection,
    );

    for (final (status, kind) in [
      (401, NetworkFailureKind.authentication),
      (403, NetworkFailureKind.authentication),
      (429, NetworkFailureKind.rateLimited),
      (408, NetworkFailureKind.serviceUnavailable),
      (500, NetworkFailureKind.serviceUnavailable),
      (400, NetworkFailureKind.requestRejected),
    ]) {
      final (transport, _) = createTransport(
        response: _jsonResponse(_envelope(_validContent), statusCode: status),
      );
      await _expectKind(transport.complete(request()), kind, reason: '$status');
    }
  });

  test('maps timeout, cancellation, and connection failures', () async {
    for (final (failure, kind) in [
      (DioExceptionType.connectionTimeout, NetworkFailureKind.timeout),
      (DioExceptionType.sendTimeout, NetworkFailureKind.timeout),
      (DioExceptionType.receiveTimeout, NetworkFailureKind.timeout),
      (DioExceptionType.cancel, NetworkFailureKind.cancelled),
      (DioExceptionType.badCertificate, NetworkFailureKind.secureConnection),
      (DioExceptionType.connectionError, NetworkFailureKind.connection),
    ]) {
      final (transport, _) = createTransport(failure: failure);
      await _expectKind(
        transport.complete(request()),
        kind,
        reason: '$failure',
      );
    }
  });

  test('honours caller cancellation without sending', () async {
    final (transport, adapter) = createTransport();

    final token = AiTransportCancellationToken()..cancel();
    await _expectKind(
      transport.complete(request(), cancellationToken: token),
      NetworkFailureKind.cancelled,
    );
    expect(adapter.requests, isEmpty);
  });

  test('forwards caller cancellation to the in-flight request', () async {
    final (transport, _) = createTransport(throwOnCancel: true);

    final token = AiTransportCancellationToken();
    final future = transport.complete(request(), cancellationToken: token);
    token.cancel();

    await _expectKind(future, NetworkFailureKind.cancelled);
  });

  test('returns per-instance timeout and cancelled messages', () async {
    final timeout = createTransport(failure: DioExceptionType.receiveTimeout);
    await expectLater(
      timeout.$1.complete(request()),
      throwsA(
        isA<NetworkFailure>()
            .having((f) => f.kind, 'kind', NetworkFailureKind.timeout)
            .having((f) => f.message, 'message', messages.timeout),
      ),
    );

    final cancelled = createTransport(failure: DioExceptionType.cancel);
    await expectLater(
      cancelled.$1.complete(request()),
      throwsA(
        isA<NetworkFailure>()
            .having((f) => f.kind, 'kind', NetworkFailureKind.cancelled)
            .having((f) => f.message, 'message', messages.cancelled),
      ),
    );
  });

  test('按请求声明的协议提取响应（三种协议各一次）', () async {
    // Responses：output[].content[].text
    final responses = createTransport(
      response: _jsonResponse(
        jsonEncode({
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': '来自 Responses'},
              ],
            },
          ],
        }),
      ),
    );
    final responsesResult = await responses.$1.complete(
      request(protocol: AiProviderProtocol.responses),
    );
    expect(responsesResult.content, '来自 Responses');

    // Anthropic：content[].text
    final anthropic = createTransport(
      response: _jsonResponse(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': '来自 Anthropic'},
          ],
        }),
      ),
    );
    final anthropicResult = await anthropic.$1.complete(
      request(protocol: AiProviderProtocol.anthropicMessages),
    );
    expect(anthropicResult.content, '来自 Anthropic');

    // 同一个响应体、不同协议声明 → chat 形状认不出来就该报格式错
    // （这条是「协议不能靠猜」的证据：别家字段不会被当自己家的）。
    final crossed = createTransport(
      response: _jsonResponse(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': '来自 Anthropic'},
          ],
        }),
      ),
    );
    await _expectInvalidResponse(
      crossed.$1.complete(
        request(protocol: AiProviderProtocol.chatCompletions),
      ),
    );
  });

  test('认证头由请求携带：Anthropic 不发 Bearer', () async {
    final (transport, adapter) = createTransport(
      response: _jsonResponse(
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'ok'},
          ],
        }),
      ),
    );

    await transport.complete(
      request(protocol: AiProviderProtocol.anthropicMessages),
    );

    final sent = adapter.requests.single;
    expect(sent.headers['x-api-key'], apiKey);
    expect(sent.headers['anthropic-version'], '2023-06-01');
    expect(sent.headers.containsKey('authorization'), isFalse);
    // Key 仍不许进正文。
    expect(adapter.bodies.single, isNot(contains(apiKey)));
  });

  test('rejects non-JSON responses and invalid envelopes', () async {
    final text = createTransport(
      response: ResponseBody.fromString(
        _envelope(_validContent),
        200,
        headers: const {
          Headers.contentTypeHeader: ['text/plain'],
        },
      ),
    );
    await _expectInvalidResponse(text.$1.complete(request()));

    final invalidEnvelope = createTransport(
      response: _jsonResponse('{"choices":[]}'),
    );
    await _expectInvalidResponse(invalidEnvelope.$1.complete(request()));
  });
}

Future<void> _expectKind(
  Future<Object?> future,
  NetworkFailureKind kind, {
  String? reason,
}) => expectLater(
  future,
  throwsA(isA<NetworkFailure>().having((f) => f.kind, 'kind', kind)),
  reason: reason,
);

Future<void> _expectInvalidResponse(Future<Object?> future) =>
    _expectKind(future, NetworkFailureKind.invalidResponse);

ResponseBody _jsonResponse(String body, {int statusCode = 200}) =>
    ResponseBody.fromString(
      body,
      statusCode,
      headers: const {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

String _envelope(String content) => jsonEncode({
  'choices': [
    {
      'message': {'content': content},
    },
  ],
});

const _validContent = '{"schema_version":1,"items":[],"warnings":[]}';

final class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.response, this.failure, this.throwOnCancel = false});

  final ResponseBody? response;
  final DioExceptionType? failure;
  final bool throwOnCancel;
  final requests = <RequestOptions>[];
  final bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      await for (final _ in requestStream) {}
    }
    if (throwOnCancel && cancelFuture != null) {
      await cancelFuture;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
      );
    }
    final failure = this.failure;
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure);
    }
    final data = options.data;
    if (data is String) bodies.add(data);
    final response = this.response;
    if (response == null) {
      throw StateError('no response configured');
    }
    return response;
  }

  @override
  void close({bool force = false}) {}
}

/// 只为构造会话服务、读出它的默认流式预算；本文件不通过它发请求。
final class _NullConfigurationReader implements AiProviderConfigurationReader {
  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => null;
}

final class _EmptySecureStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}
