import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 「今天」跨零点刷新：被混入的页面常驻 IndexedStack，跨天后不会自然
/// 重建，导致卡片与保存目标仍落在昨天。本 mixin 在 resumed 与本地零点
/// 触发 [onNewDay]（默认 setState），并由子类按需刷新自己的「今天」。
mixin DailyRollover<T extends StatefulWidget> on State<T> {
  late final _RolloverObserver _observer = _RolloverObserver(this);
  DateTime _observedDay = DateTime.now();
  Timer? _midnightTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_observer);
    _scheduleMidnightTick();
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(_observer);
    super.dispose();
  }

  /// 当前观察到的「今天」，跨天时由 [onNewDay] 推进。
  DateTime get observedToday => _observedDay;

  void _scheduleMidnightTick() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(nextMidnight.difference(now), () {
      if (!mounted) return;
      _checkDayRollover();
      _scheduleMidnightTick();
    });
  }

  void _checkDayRollover() {
    final now = DateTime.now();
    if (now.year == _observedDay.year &&
        now.month == _observedDay.month &&
        now.day == _observedDay.day) {
      return;
    }
    final previousDay = _observedDay;
    _observedDay = now;
    void fire() {
      if (mounted) onNewDay(previousDay);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fire());
    } else {
      fire();
    }
  }

  /// 跨天后的刷新钩子，参数是上一次观察到的日期；默认触发一次重建。
  @protected
  void onNewDay(DateTime previousDay) => setState(() {});

  /// 仅供测试：把观察日回拨到 [previousDay] 并立即检查一次跨天，
  /// 用于在不等待真实零点的情况下验证 [onNewDay] 的触发与参数。
  @visibleForTesting
  void debugRollover(DateTime previousDay) {
    _observedDay = previousDay;
    _checkDayRollover();
  }
}

/// 私有观察者：只关心 resumed，避免让宿主 State 直接实现整个
/// WidgetsBindingObserver 接口。
final class _RolloverObserver implements WidgetsBindingObserver {
  const _RolloverObserver(this.owner);

  final dynamic owner;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      owner._checkDayRollover();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
