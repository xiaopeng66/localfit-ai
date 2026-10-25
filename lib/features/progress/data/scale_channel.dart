import 'package:flutter/services.dart';

/// 电子体重秤（docs/31 S6，需求 47 / D6）。
///
/// **不引依赖**：`MainActivity` 上挂一条 `MethodChannel('localfit/scale')`。
/// 与步数通道同一条纪律：四种状态**不许合并成一种「不行」**——「这台设备
/// 永远不支持」（API ≤ 30，D6 备注不加定位权限后的诚实降级）、「点一下就
/// 能有」（未授权）、「现在就能扫」（已授权）的用户动作完全不同。
enum ScaleAvailability {
  /// API 31+ 且蓝牙适配器在、权限已授予：可以前台扫描。
  ready,

  /// API 31+ 但缺 `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`。
  denied,

  /// 这台设备不支持（API ≤ 30：扫描需要定位权限，D6 默认不加 ⇒ 不支持；
  /// 或没有蓝牙适配器）。
  unsupported,
}

/// 一次前台「扫描 + 连接 + 读一次」的结果。
///
/// 各状态**不合并**：没找到秤（可能秤没唤醒）、超时（找到了没读到数）、
/// 被拒、超范围，各自的下一句话不同。
enum ScaleReadStatus {
  /// 读到一次体重（[ScaleReading.grams] 非 null）。
  ok,

  /// 10 秒扫描窗口内没有发现广播标准体重秤服务（0x181D）的设备。
  noScale,

  /// 发现并连上了秤，但窗口内没等到一次体重测量通知。
  timeout,

  /// 缺蓝牙运行时权限。
  denied,

  /// API ≤ 30 或没有蓝牙适配器。
  unsupported,
}

final class ScaleReading {
  const ScaleReading({
    required this.status,
    this.grams,
    this.atMs,
    this.reason,
  });

  final ScaleReadStatus status;

  /// 秤读数（克，整数）。标准体重测量特征（0x2A9D）的 IEEE-11073 SFLOAT
  /// 最小分辨率 0.005 kg，用**克**做整数传输，Dart 侧不再碰浮点解析。
  /// 仅 [ScaleReadStatus.ok] 时非 null。
  final int? grams;

  /// 原生读到数值的时刻（epoch millis）。
  final int? atMs;

  /// 原生细分原因（`no_adapter` / `scan_error` / `gatt_error` …），原样保留
  /// 给诊断，界面不显示这串英文。
  final String? reason;
}

/// 原生 `localfit/scale` 通道的薄封装。
///
/// 通道可注入（[channel]），测试用 `TestDefaultBinaryMessengerBinding` 装
/// fake handler——不需要真秤就能覆盖全部状态（D6 ⑤ 的验收上限）。
final class ScaleChannel {
  ScaleChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'localfit/scale';

  final MethodChannel _channel;

  /// 查询当前能力（API 版本 + 蓝牙适配器 + 运行时权限）。
  ///
  /// **不做假设**：解析不出来就当作不支持——把「不确定」报成「能扫」会
  /// 让用户在老设备上白站 10 秒。
  Future<ScaleAvailability> check() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('check');
      return _parseAvailability(raw?['status']);
    } catch (_) {
      return ScaleAvailability.unsupported;
    }
  }

  /// 请求 `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`（API 31+）。返回是否已授权。
  Future<bool> requestPermission() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'requestPermission',
      );
      return raw?['status'] == 'granted';
    } catch (_) {
      return false;
    }
  }

  /// 前台扫描一次（原生侧固定 10 秒窗口）：发现广播标准体重秤服务的设备
  /// → 连接 → 订阅体重测量通知 → 读一次就断开。
  Future<ScaleReading> scanOnce() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'scanOnce',
      );
      return _parseReading(raw);
    } catch (_) {
      return const ScaleReading(
        status: ScaleReadStatus.timeout,
        reason: 'channel_error',
      );
    }
  }

  /// 打开本应用的系统设置页（权限被拒后的出口）。
  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {
      // 打不开设置不该崩：用户还能自己去系统设置里找。
    }
  }

  static ScaleAvailability _parseAvailability(Object? status) {
    switch (status) {
      case 'ready':
        return ScaleAvailability.ready;
      case 'denied':
        return ScaleAvailability.denied;
      default:
        return ScaleAvailability.unsupported;
    }
  }

  static ScaleReading _parseReading(Map<Object?, Object?>? raw) {
    switch (raw?['status']) {
      case 'ok':
        final grams = raw?['grams'];
        if (grams is! int) {
          return const ScaleReading(
            status: ScaleReadStatus.timeout,
            reason: 'bad_grams',
          );
        }
        return ScaleReading(
          status: ScaleReadStatus.ok,
          grams: grams,
          atMs: raw?['atMs'] is int ? raw!['atMs'] as int : null,
        );
      case 'no_scale':
        return ScaleReading(
          status: ScaleReadStatus.noScale,
          reason: raw?['reason'] is String ? raw!['reason'] as String : null,
        );
      case 'timeout':
        return ScaleReading(
          status: ScaleReadStatus.timeout,
          reason: raw?['reason'] is String ? raw!['reason'] as String : null,
        );
      case 'denied':
        return const ScaleReading(status: ScaleReadStatus.denied);
      case 'unsupported':
        return const ScaleReading(status: ScaleReadStatus.unsupported);
      default:
        return const ScaleReading(
          status: ScaleReadStatus.timeout,
          reason: 'unknown_status',
        );
    }
  }
}
