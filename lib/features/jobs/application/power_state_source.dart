import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/widgets.dart';

import 'package:localfit_ai/features/jobs/application/job_scheduler.dart';

/// 设备电源/空闲状态来源（docs/43 A3 / docs/41 G11）。
///
/// 只暴露三件事：是否充电、充电状态变化流、是否空闲。**调度器不认平台细节**，
/// 所以换实现（battery_plus / 后台近似）不改 `JobScheduler`。
///
/// 决策点 D1（是否新增 `battery_plus`）未答复前使用
/// [BackgroundOnlyPowerStateSource]（实现 B）：不判断充电，只用「应用在后台」
/// 近似空闲，并在调试面板如实标注「未接充电判定」。
abstract interface class PowerStateSource {
  Future<bool> isCharging();

  /// 充电状态变化（true = 开始充电）。实现 B 永远不发事件。
  Stream<bool> watchCharging();

  /// 应用在后台 / 屏幕关闭（docs/43：实现 B 用「应用在后台」近似）。
  Future<bool> isIdle();
}

/// 如实标注（实现 B）：没有充电判定。
const String kPowerStateNoteB = '未接充电判定：应用在后台近似空闲（重任务暂不自动跑）';

/// 如实标注（实现 A，默认装配）：battery_plus 读取真实充电状态；
/// `isIdle` 仍是「应用在后台」近似（docs/43 A3 的口径）。
const String kPowerStateNote = '充电判定：已接线（battery_plus）；空闲 = 应用在后台';

/// 实现 A（默认装配）：battery_plus 读真实充电状态。
///
/// * `isCharging` 按 battery_plus 的 `BatteryState` 判定（charging /
///   full 都算「插着电」——full 时也在充电器上，重任务跑它无妨）；
/// * `watchCharging` 订阅 `onBatteryStateChanged`，并**立即发一个当前值**
///   （流式 API 只在变化时发事件，订阅者要知道初值）；
/// * 平台异常（无电池的桌面/模拟器）按「未充电」处理——保守方向。
///
/// `isIdle` 仍由 [JobDispatchController] 的生命周期观察给出，本类不管。
final class BatteryPlusPowerStateSource implements PowerStateSource {
  BatteryPlusPowerStateSource({Battery? battery})
    : _battery = battery ?? Battery();

  final Battery _battery;

  @override
  Future<bool> isCharging() async {
    try {
      return switch (await _battery.batteryState) {
        BatteryState.charging || BatteryState.full => true,
        _ => false,
      };
    } on Object {
      return false;
    }
  }

  @override
  Stream<bool> watchCharging() async* {
    // 先给初值：onBatteryStateChanged 只在变化时发事件。
    yield await isCharging();
    try {
      await for (final state in _battery.onBatteryStateChanged) {
        yield state == BatteryState.charging || state == BatteryState.full;
      }
    } on Object {
      // 平台通道失败：流终止（调度器按最后一次的值继续用）。
      return;
    }
  }

  @override
  Future<bool> isIdle() async => false; // 由生命周期观察者负责；这里不参与
}

/// 实现 B（不加依赖）：不判断充电，只用「应用在后台」近似空闲。
///
/// * [isCharging] 恒为 false——**未知按未充电处理**，这是保守方向：
///   重任务（索引重建/批量打标）不会在未确认充电时耗电；
/// * [watchCharging] 不发事件（没有可观察的充电状态）；
/// * [isIdle] = 当前不在前台（`paused` / `hidden` / `detached`）。
///
/// 生命周期变化由 [JobDispatchController] 观察，不需要本类额外暴露流。
final class BackgroundOnlyPowerStateSource implements PowerStateSource {
  bool _foreground = true;

  /// 当前是否在前台（供调度器同步判断「还该不该领取下一条」）。
  bool get isForeground => _foreground;

  void updateLifecycle(AppLifecycleState state) {
    _foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  @override
  Future<bool> isCharging() async => false;

  @override
  Stream<bool> watchCharging() => const Stream<bool>.empty();

  @override
  Future<bool> isIdle() async => !_foreground;
}

/// 把「什么时候允许跑」接到调度器（docs/43 A3 接线）。
///
/// 纪律：
/// * **前台不领取新任务**：每次领取前重读条件（[JobScheduler] 在循环里
///   复查 `conditions()`）；已领取的任务跑完，不打断；
/// * **15 分钟兜底 tick**：即使没有充电/生命周期事件也会到点看一眼；
/// * **暂停/恢复**透传给调度器（用户可停）。
final class JobDispatchController with WidgetsBindingObserver {
  JobDispatchController({
    required this.scheduler,
    required this.power,
    this.fallbackInterval = const Duration(minutes: 15),
  });

  final JobScheduler scheduler;
  final PowerStateSource power;

  /// 兜底 tick 间隔（docs/43 A3：15 分钟）。
  final Duration fallbackInterval;

  Timer? _fallbackTimer;
  StreamSubscription<bool>? _chargingSubscription;
  bool _started = false;

  /// 调度器读条件的唯一入口：**同步**读缓存（生命周期事件维护），
  /// 避免在领取循环里等异步平台调用。
  JobRunConditions get conditions =>
      JobRunConditions(charging: _charging, idle: _idle);

  bool _charging = false;
  bool _idle = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _applyLifecycle(state ?? AppLifecycleState.resumed);
    _chargingSubscription = power.watchCharging().listen(
      (value) {
        _charging = value;
        if (value) unawaited(maybeTick());
      },
      onError: (Object _) {
        // 充电流读不到不是错误：按未充电处理（保守）。
        _charging = false;
      },
    );
    _fallbackTimer = Timer.periodic(fallbackInterval, (_) {
      unawaited(maybeTick());
    });
    // 启动时也看一眼：如果启动即在后台（少见），允许领一次。
    unawaited(maybeTick());
  }

  void pause() => scheduler.pause();
  void resume() => scheduler.resume();

  /// 条件满足才 tick（前台 / 未空闲直接跳过）。
  Future<void> maybeTick() async {
    if (scheduler.isPaused) return;
    _charging = await power.isCharging();
    _idle = await power.isIdle();
    if (!conditions.canRunLight) return;
    await scheduler.tick();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applyLifecycle(state);
    if (_idle) unawaited(maybeTick());
  }

  void _applyLifecycle(AppLifecycleState state) {
    _idle =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (power is BackgroundOnlyPowerStateSource) {
      (power as BackgroundOnlyPowerStateSource).updateLifecycle(state);
    }
  }

  void dispose() {
    _fallbackTimer?.cancel();
    unawaited(_chargingSubscription?.cancel());
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }
}
