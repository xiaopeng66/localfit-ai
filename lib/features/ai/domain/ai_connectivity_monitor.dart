import 'package:flutter/foundation.dart';

import 'package:localfit_ai/core/errors/app_failure.dart';

/// 「最近一次 AI 请求连不上」的证据（2026-10-21 裁决 D-2，选项 A）。
///
/// **为什么不加 connectivity 依赖**：docs/45 §2.3「需要新增第三方依赖——除非
/// 阻塞 P0，否则不新增」。这里只需要回答「刚刚是不是连不上」，一次真实的
/// 连接失败就是最硬的证据；没调用过 AI 的用户不会看到断网提示（这正是
/// 「有证据才说」）。
///
/// 纪律：
/// * 只认 [NetworkFailureKind.connection]（超时可能是上游慢，不是断网）；
/// * 成功一次即清除（恢复网络后提示要消失，不能靠计时器猜）；
/// * 只存内存，不落库、不上报。
final class AiConnectivityMonitor extends ChangeNotifier {
  AiConnectivityMonitor({
    DateTime Function()? now,
    this.window = const Duration(minutes: 10),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// 断网证据的有效窗口。超过它自动视为「未知」，不再显示断网提示。
  final Duration window;

  DateTime? _lastConnectionFailureAt;

  /// 最近一次连接失败的时刻（UTC）；null = 没有证据。
  DateTime? get lastConnectionFailureAt => _lastConnectionFailureAt;

  /// 当前是否按「无网」处理。
  bool get isOffline {
    final at = _lastConnectionFailureAt;
    if (at == null) return false;
    return _now().toUtc().difference(at) < window;
  }

  /// 记录一次请求失败；只有「连不上」才算断网证据。
  void record(Object error) {
    if (error is! NetworkFailure) return;
    if (error.kind != NetworkFailureKind.connection) return;
    _lastConnectionFailureAt = _now().toUtc();
    notifyListeners();
  }

  /// 一次成功请求 ⇒ 网络可用，清掉旧证据。
  void recordSuccess() {
    if (_lastConnectionFailureAt == null) return;
    _lastConnectionFailureAt = null;
    notifyListeners();
  }
}
