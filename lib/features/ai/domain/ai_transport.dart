import 'dart:async';

import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';

/// Cancellation handle for an in-flight AI transport request. Mirrors the
/// per-feature tokens so task adapters can forward user cancellation.
final class AiTransportCancellationToken {
  AiTransportCancellationToken();

  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// A fully resolved AI request. The API key lives in memory only and must
/// never be logged or embedded in the body.
final class AiTransportRequest {
  const AiTransportRequest({
    required this.requestUri,
    required this.body,
    required this.requestBytes,
    required this.maxRequestBytes,
    this.headers = const {},
    this.protocol = AiProviderProtocol.chatCompletions,
  });

  final Uri requestUri;

  /// UTF-8 encoded JSON request body.
  final String body;

  /// Size of [body] in bytes, computed by the caller that built it.
  final int requestBytes;

  /// Upper bound enforced by the transport before anything is sent.
  final int maxRequestBytes;

  /// 协议专属请求头（认证方式与版本头，见 `AiProtocolWire.authHeaders`）。
  ///
  /// 由**构建请求体的调用方**注入：协议是它选的，transport 只负责逐字发出。
  /// 默认空 map 保留给不关心协议的测试构造点。
  final Map<String, String> headers;

  /// 该请求按哪种协议解析响应（transport 不做协议猜测）。
  ///
  /// 放在请求上而不是 transport 构造器上：协议来自**每次请求前才读到的用户
  /// 配置**，transport 实例是长期持有的。
  final AiProviderProtocol protocol;
}

final class AiTransportResponse {
  const AiTransportResponse({
    required this.content,
    required this.requestBytes,
    required this.responseBytes,
  });

  /// 由协议 wire 从响应里提取出的助手文本（三种协议的形状差异见
  /// `AiProtocolWire.extractNonStreamContent`）。空/形状不符由提取侧抛
  /// 「供应商返回格式无法识别」。
  final String content;

  final int requestBytes;
  final int responseBytes;
}

/// User-facing failure texts that legitimately differ per AI feature; shared
/// HTTP classification texts live in the transport implementation.
final class AiTransportFailureMessages {
  const AiTransportFailureMessages({
    required this.timeout,
    required this.cancelled,
    required this.requestTooLarge,
  });

  final String timeout;
  final String cancelled;
  final String requestTooLarge;
}

abstract interface class AiTransport {
  Future<AiTransportResponse> complete(
    AiTransportRequest request, {
    AiTransportCancellationToken? cancellationToken,
  });
}
