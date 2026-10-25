import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai/data/ai_protocol_wire.dart';
import 'package:localfit_ai/features/ai/domain/ai_transport.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';

/// Shared HTTP behaviour for all three BYOK protocols: fixed endpoint, header-only
/// key, no redirects, bounded request/response sizes, total deadline, cancellation,
/// and uniform failure classification. Feature providers only build payloads
/// and decode extracted content.
///
/// **协议在请求上**（[AiTransportRequest.protocol]）而不是构造器上：协议来自
/// 每次请求前才读到的用户配置，而 transport 实例是长期持有的。认证头也由
/// 调用方按同一张 wire 表注入，transport 只逐字发出、不做协议猜测。
final class OpenAiCompatibleAiTransport implements AiTransport {
  OpenAiCompatibleAiTransport({
    required this.dio,
    required this.failureMessages,
    this.maxResponseBytes = defaultMaxResponseBytes,
  });

  static const defaultMaxResponseBytes = 128 * 1024;
  // ── 超时预算（2026-10-16 按真实供应商重定）────────────────────────────
  // 旧口径 10 / 30 / 45 / **60** 是照着一个 ~1s 延迟的供应商定的。用户授权
  // 实测 `deepseek-ai/deepseek-v4.1-flash`（BYOK 中转）后实测：TTFB ≈ 11s、
  // 小回复整请求 40–46s、训练计划那种 ~350 token 的回复 **31–55s 且方差大**
  // ——于是 45s 的**空闲接收**先掐断非流式请求（`e2e ④` 实测
  // `NetworkFailure: 计划请求超时`），而流式那条本来还能走满会话服务给的
  // 3 分钟（`maxStreamDuration`）。BYOK 的延迟谱系就是这么宽：上限必须容得下
  // 「慢但活着」的供应商，同时仍是**有界**的（不是无限等），并且用户随时能用
  // 「停止生成」取消（cancel token 一路传到 dio）。
  //
  // 不变量（`open_ai_compatible_transport_test.dart` 的「超时预算自洽」pin
  // 盯着它）：连接 ≤ 发送 ≤ 接收 ≤ 总上限，且 **总上限 ≥ 会话流式上限**。
  static const connectTimeout = Duration(seconds: 10);
  static const sendTimeout = Duration(seconds: 30);
  static const receiveTimeout = Duration(seconds: 120);
  static const totalTimeout = Duration(minutes: 4);

  final Dio dio;
  final AiTransportFailureMessages failureMessages;
  final int maxResponseBytes;

  @override
  Future<AiTransportResponse> complete(
    AiTransportRequest request, {
    AiTransportCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      throw NetworkFailure(
        failureMessages.cancelled,
        kind: NetworkFailureKind.cancelled,
      );
    }
    _validateEndpoint(request.requestUri);
    if (request.requestBytes < 0 ||
        request.requestBytes > request.maxRequestBytes) {
      throw ValidationFailure(failureMessages.requestTooLarge);
    }

    var deadlineExceeded = false;
    final dioCancelToken = CancelToken();
    cancellationToken?.whenCancelled.then((_) {
      dioCancelToken.cancel('ai_transport_cancelled');
    });
    final deadline = Timer(totalTimeout, () {
      deadlineExceeded = true;
      dioCancelToken.cancel('ai_transport_deadline_exceeded');
    });

    try {
      final response = await dio.requestUri<ResponseBody>(
        request.requestUri,
        data: request.body,
        cancelToken: dioCancelToken,
        options: Options(
          method: 'POST',
          headers: {
            Headers.acceptHeader: Headers.jsonContentType,
            // 协议专属认证头由调用方按 wire 表注入（Key 只进头）。
            ...request.headers,
          },
          contentType: Headers.jsonContentType,
          responseType: ResponseType.stream,
          connectTimeout: connectTimeout,
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
          followRedirects: false,
          maxRedirects: 0,
          receiveDataWhenStatusError: false,
          validateStatus: (status) => status == 200,
        ),
      );
      if (response.isRedirect || response.redirects.isNotEmpty) {
        throw _redirectFailure();
      }
      if (response.statusCode != 200 || response.data == null) {
        throw _invalidResponse();
      }
      if (!_isJsonContentType(
        response.headers.value(Headers.contentTypeHeader),
      )) {
        throw _invalidResponse();
      }
      if (_declaredLength(response.headers) > maxResponseBytes) {
        throw _invalidResponse();
      }
      final body = await _readResponse(response.data!.stream);
      final content = _extractContent(request.protocol, _decodeUtf8(body));
      return AiTransportResponse(
        content: content,
        requestBytes: request.requestBytes,
        responseBytes: body.length,
      );
    } on DioException catch (error) {
      throw _mapDioFailure(error, deadlineExceeded: deadlineExceeded);
    } finally {
      deadline.cancel();
    }
  }

  /// 按请求声明的协议从响应里取助手文本；解析失败/形状不符统一报「格式无法
  /// 识别」（docs/24 §5：跨协议的唯一错误口径，不向用户暴露协议细节）。
  String _extractContent(AiProviderProtocol protocol, String responseBody) {
    final Object? decoded;
    try {
      decoded = jsonDecode(responseBody);
    } on FormatException {
      throw _invalidResponse();
    }
    if (decoded is! Map) throw _invalidResponse();
    final normalized = _mapOrNull(decoded);
    if (normalized == null) throw _invalidResponse();
    final content = protocol.extractNonStreamContent(normalized);
    if (content == null) {
      // 先给「只返回了推理、content 为空」一个可解释错误（docs/29 §P4），
      // 再落回「格式无法识别」的通用口径——不允许静默空气泡。
      final hint = protocol.reasoningOnlyHint(normalized);
      if (hint != null) {
        throw NetworkFailure(hint, kind: NetworkFailureKind.invalidResponse);
      }
      throw _invalidResponse();
    }
    return content;
  }

  Map<String, Object?>? _mapOrNull(Object? value) {
    if (value is! Map) return null;
    final out = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) return null;
      out[key] = entry.value;
    }
    return out;
  }

  void _validateEndpoint(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443)) {
      throw const ValidationFailure('AI Base URL 配置无效，请在设置中更新。');
    }
  }

  Future<Uint8List> _readResponse(Stream<Uint8List> stream) async {
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (buffer.length + chunk.length > maxResponseBytes) {
        throw _invalidResponse();
      }
      buffer.add(chunk);
    }
    if (buffer.length == 0) {
      throw _invalidResponse();
    }
    return buffer.takeBytes();
  }

  String _decodeUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw _invalidResponse();
    }
  }

  NetworkFailure _mapDioFailure(
    DioException error, {
    required bool deadlineExceeded,
  }) {
    if (deadlineExceeded ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return NetworkFailure(
        failureMessages.timeout,
        kind: NetworkFailureKind.timeout,
      );
    }
    if (error.type == DioExceptionType.cancel) {
      return NetworkFailure(
        failureMessages.cancelled,
        kind: NetworkFailureKind.cancelled,
      );
    }
    if (error.type == DioExceptionType.badCertificate) {
      return const NetworkFailure(
        '供应商的安全连接无法验证。',
        kind: NetworkFailureKind.secureConnection,
      );
    }
    final status = error.response?.statusCode;
    if (status != null) return _statusFailure(status);
    return const NetworkFailure(
      '网络连接不可用，请检查网络后重试。',
      kind: NetworkFailureKind.connection,
    );
  }

  NetworkFailure _statusFailure(int status) {
    if (status >= 300 && status < 400) {
      return _redirectFailure();
    }
    if (status == 401 || status == 403) {
      return const NetworkFailure(
        'API Key 无效或无权使用该服务。',
        kind: NetworkFailureKind.authentication,
      );
    }
    if (status == 429) {
      return const NetworkFailure(
        '服务请求过于频繁，请稍后手动重试。',
        kind: NetworkFailureKind.rateLimited,
      );
    }
    if (status == 408 || status >= 500) {
      return const NetworkFailure(
        '供应商暂时不可用，请稍后手动重试。',
        kind: NetworkFailureKind.serviceUnavailable,
      );
    }
    return const NetworkFailure(
      '供应商拒绝了该请求。',
      kind: NetworkFailureKind.requestRejected,
    );
  }

  NetworkFailure _redirectFailure() => const NetworkFailure(
    '供应商重定向已被安全策略阻止。',
    kind: NetworkFailureKind.secureConnection,
  );

  NetworkFailure _invalidResponse() => const NetworkFailure(
    '供应商返回格式无法识别。',
    kind: NetworkFailureKind.invalidResponse,
  );

  bool _isJsonContentType(String? contentType) =>
      contentType?.split(';').first.trim().toLowerCase() ==
      Headers.jsonContentType;

  int _declaredLength(Headers headers) {
    final declared = int.tryParse(
      headers.value(Headers.contentLengthHeader) ?? '',
    );
    if (declared == null || declared < 0) return 0;
    return declared;
  }
}
