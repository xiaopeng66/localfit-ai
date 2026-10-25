import 'package:flutter/services.dart';

/// 本机步数读取（docs/29 §P9 需求 34）。
///
/// **不引依赖**：`MainActivity` 上挂一条 `MethodChannel('localfit/steps')`
/// （`TYPE_STEP_COUNTER`，开机累计值），这里只做种类翻译与回落判定。
///
/// 四种结果**不许合并成一种「没有数据」**——它们的用户动作完全不同：
/// 没有传感器＝这台设备永远没有；没授权＝用户点一下就能有；计数器回退＝
/// 设备重启过的正常现象；读到值＝显示步数。
enum StepsAvailability {
  /// 读到累计值。
  available,

  /// 这台设备没有 `TYPE_STEP_COUNTER`（可能只有 `TYPE_STEP_DETECTOR`）。
  noSensor,

  /// API 29+ 未授予 `ACTIVITY_RECOGNITION`。给「去设置」入口。
  denied,

  /// 传感器在但本次读数窗口内没有事件（真机偶发；不是「设备没有」）。
  noReading,

  /// **应用内开关关闭**（2026-10-23 用户：「步数授权取消不掉」）：
  /// 读数与落库都被主动停掉。与 [denied] 分开——权限可能还在系统里，
  /// 用户要做的事也不同（去设置页重新打开，而不是去系统设置授权）。
  disabled,
}

/// 一次读数。
///
/// [counter] 是**开机以来累计值**，不是今日步数——今日步数要靠
/// [StepsBaseline] 做差（见 [resolveTodaySteps]）。
final class StepsReading {
  const StepsReading({
    required this.availability,
    this.counter,
    this.atMs,
    this.reason,
  });

  final StepsAvailability availability;

  /// 开机累计步数（仅 [StepsAvailability.available] 时非 null）。
  final int? counter;

  /// 传感器事件的时间戳（epoch millis）。
  final int? atMs;

  /// 原生给的细分原因（`no_counter_sensor` / `detector_only` / `no_event`），
  /// **原样保留给诊断**，界面不显示这串英文。
  final String? reason;
}

/// 原生 `localfit/steps` 通道的薄封装。
///
/// 通道可注入（[channel]），测试用 `TestDefaultBinaryMessengerBinding` 装
/// fake handler——这样四种状态都能在单测里覆盖，不必有真机传感器。
final class StepsChannel {
  StepsChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'localfit/steps';

  final MethodChannel _channel;

  /// 读一次累计值。**任何原生异常都翻成 [StepsAvailability.noReading]**：
  /// 抛到界面上只会变成一句用户看不懂的红字，而步数卡是可选的锦上添花。
  Future<StepsReading> read() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('read');
      return _parse(raw);
    } catch (_) {
      return const StepsReading(
        availability: StepsAvailability.noReading,
        reason: 'channel_error',
      );
    }
  }

  /// 请求 `ACTIVITY_RECOGNITION`（API 29+）。返回是否已授权。
  ///
  /// **不做假设**：以原生回的 `status` 为准，解析不出来就当作没授权。
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

  /// 打开本应用的系统设置页（权限被拒后的出口）。
  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } catch (_) {
      // 打不开设置不该崩：用户还能自己去系统设置里找。
    }
  }

  static StepsReading _parse(Map<Object?, Object?>? raw) {
    final status = raw?['status'];
    switch (status) {
      case 'ok':
        final counter = raw?['counter'];
        if (counter is! int) {
          return const StepsReading(
            availability: StepsAvailability.noReading,
            reason: 'bad_counter',
          );
        }
        return StepsReading(
          availability: StepsAvailability.available,
          counter: counter,
          atMs: raw?['atMs'] is int ? raw!['atMs'] as int : null,
        );
      case 'denied':
        return const StepsReading(availability: StepsAvailability.denied);
      case 'unavailable':
        final reason = raw?['reason'];
        // **2026-10-16（用户实测「授权后仍识别不了」）**：原先把所有
        // `unavailable` 都当中没有累计计数器，于是原生 read 的 2s 窗口里
        // 没收到事件（`no_event`）时界面写「这台设备没有计步传感器」——
        // 一句假话，还把「再读一次就好」的情况说成了硬件没有。
        // 现在按原因分流：`no_event` = **这次没读到**（可重试）；
        // `no_counter_sensor` / `detector_only` 才是真的没有可用的累计值。
        final unavailableReason = reason is String ? reason : null;
        return StepsReading(
          availability: unavailableReason == 'no_event'
              ? StepsAvailability.noReading
              : StepsAvailability.noSensor,
          reason: unavailableReason,
        );
      default:
        return const StepsReading(
          availability: StepsAvailability.noReading,
          reason: 'unknown_status',
        );
    }
  }
}

/// 重启基线（`TYPE_STEP_COUNTER` 是「开机以来累计」的必然产物）。
///
/// 昨天存的累计值今天会**变小**（设备重启过）——这时差值不是步数，是
/// 一个负数。**不能显示负数、不能显示差值**：只能把今天的基线重设成
/// 当前累计值，今日步数从 0 起算（我们确实不知道重启前走了多少）。
final class StepsBaseline {
  const StepsBaseline({required this.localDate, required this.counter});

  /// 这条基线属于哪一天（`yyyy-MM-dd`）。
  final String localDate;

  /// 那天的开机累计值。
  final int counter;

  Map<String, Object?> toJson() => {'localDate': localDate, 'counter': counter};

  static StepsBaseline? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final date = json['localDate'];
    final counter = json['counter'];
    if (date is! String || counter is! int) return null;
    return StepsBaseline(localDate: date, counter: counter);
  }
}

/// 今日步数 = 当前累计值 − 今天的基线累计值。
///
/// 三种情形都要如实表达，**不许用 0 冒充「没走过」**：
/// - 基线是今天的且 `counter >= baseline`：差值就是今日步数；
/// - 基线是今天的但 `counter < baseline`（重启过）：基线要重设，今日步数
///   从 0 起算（返回 0 并附 [StepsToday.reset] = true，调用方据此回写基线）；
/// - 没有基线（今天第一次读）：以当前累计值作基线，今日步数 0。
final class StepsToday {
  const StepsToday({
    required this.steps,
    required this.baseline,
    this.resetBaseline = false,
  });

  final int steps;

  /// 本次读数后应当落库的基线。
  final StepsBaseline baseline;

  /// true = 检测到计数值回退，调用方**必须**把 [baseline] 覆盖回去。
  final bool resetBaseline;
}

StepsToday resolveTodaySteps({
  required StepsReading reading,
  required String localDate,
  StepsBaseline? baseline,
}) {
  final counter = reading.counter ?? 0;
  final sameDay = baseline != null && baseline.localDate == localDate;
  if (!sameDay) {
    // 跨天或首次：今天的基线就是现在这个累计值，今日从 0 起算。
    return StepsToday(
      steps: 0,
      baseline: StepsBaseline(localDate: localDate, counter: counter),
    );
  }
  if (counter < baseline.counter) {
    // 设备重启：累计值归零重来。**不显示负数**，重设基线。
    return StepsToday(
      steps: 0,
      baseline: StepsBaseline(localDate: localDate, counter: counter),
      resetBaseline: true,
    );
  }
  return StepsToday(steps: counter - baseline.counter, baseline: baseline);
}
