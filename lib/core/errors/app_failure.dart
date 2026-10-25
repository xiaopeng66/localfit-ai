sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.cause});
}

final class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.cause});
}

enum NetworkFailureKind {
  cancelled,
  timeout,
  connection,
  secureConnection,
  authentication,
  rateLimited,
  serviceUnavailable,
  requestRejected,
  invalidResponse,
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure(
    super.message, {
    this.kind = NetworkFailureKind.connection,
    super.cause,
  });

  final NetworkFailureKind kind;
}

final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure(super.message, {super.cause});
}

/// 「错误 → 用户可见文本」的唯一安全出口（docs/11 §3-B）。
///
/// 只有本地代码自己撰写的 [AppFailure.message] 可以直接上屏：它经过
/// 「可行动且不泄漏」的评审，用户看了能知道下一步做什么。其它异常
/// （Dio / drift / dart:io / FormatException…）的 `toString()` 可能带
/// 完整 URL、本机绝对路径、SQL 语句或模型原文——一律映射为调用方
/// 给定的固定兜底文案。原始异常只允许进 [PrivacyLogger] 白名单指标。
String safeFailureText(Object error, {required String fallback}) =>
    error is AppFailure ? error.message : fallback;
