import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/data/steps_channel.dart';

// 通道类型（读数与口径）一并从这里转出：界面与测试只 import 仓储这一个文件，
// 不必知道「读取靠通道、落库靠仓储」这层分工。
export 'package:localfit_ai/features/progress/data/steps_channel.dart';

/// 每日本机步数（docs/29 §P9 需求 34；表在 schema 21 预置）。
///
/// 一天一行（`localDate` 唯一），当日重复同步按行覆盖。**只写本机传感器
/// 读到的值**：`source` 恒为 `device_counter`，将来接健康平台聚合数据时
/// 用另一个 source，统计口径不混。
///
/// 基线（`StepsBaseline`）存在 `AppSettings` 键值里而不是新表：它是**单一
/// 标量**（今天的开机累计值），不是按天的历史——多存一天的历史只会让
/// 「哪条基线是对的」变成一个需要裁决的问题。
final class StepsRepository {
  const StepsRepository({
    required this.database,
    required this.channel,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final StepsChannel channel;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 基线在 `AppSettings` 里的键（值 = JSON `{localDate, counter}`）。
  static const baselineKey = 'steps_baseline';

  /// 每日步数目标在 `AppSettings` 里的键（值 = 十进制整数字符串）。
  ///
  /// 存键值而不是新表 / 新列（docs/32 §3 D11）：它是**单一标量**，
  /// 没有按天的历史语义——历史步数记录里也不需要「那天目标是多少」。
  static const dailyGoalKey = 'steps_daily_goal';

  /// 未设置时的目标（= 2026-10 之前硬编码在步数卡里的那个常量，
  /// 保证旧行为逐字不变；docs/32 §3 D11）。
  static const defaultDailyGoal = 10000;

  /// 应用内「读取本机步数」开关（2026-10-23 用户：「步数授权取消不掉」）。
  ///
  /// Android 的运行时权限只能由用户在系统设置里撤销，应用内的开关撤不掉
  /// 权限本身——但它能**真的停掉读数**（[syncToday] 与步数卡都看它）。
  /// 界面必须把两件事分开说：「应用内已停止读取」≠「系统权限已撤销」。
  static const enabledKey = 'steps_enabled';

  /// 目标的可写范围（docs/32 §3 D11）。越界不被静默收敛成边界值——
  /// 收敛等于替用户改了他的输入，他会以为「60000 存进去了」。
  static const minDailyGoal = 1000;
  static const maxDailyGoal = 50000;

  /// 写入来源标记（`StepsDaily.source`）。
  static const sourceDeviceCounter = 'device_counter';

  /// 用户手动录入（2026-10-26）：当天按「用户说的是事实」处理，传感器不再覆盖。
  static const sourceManual = 'manual';

  /// 手动步数的上限（一天 20 万步已经远超任何真实活动量；再大就是打错了）。
  static const maxManualSteps = 200000;

  /// 读当前步数目标。**缺键 / 坏值 / 越界都返回默认值**（[defaultDailyGoal]）
  /// 而不抛：步数卡随时可能在读，为一个设置值把整张卡打死（与
  /// [readBaseline] 的「坏值当作没有」同一取舍）代价远大于收益。
  /// 读的时候也不纠正写回——读操作有写副作用会让「读」不再安全。
  Future<int> readDailyGoal() async {
    final row = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(dailyGoalKey))).getSingleOrNull();
    return _parseDailyGoal(row?.value);
  }

  /// 订阅步数目标（设置页改完，今日页步数卡不用等重建/重进就跟着变）。
  Stream<int> watchDailyGoal() {
    final query = database.select(database.appSettings)
      ..where((row) => row.key.equals(dailyGoalKey));
    return query.watchSingleOrNull().map((row) => _parseDailyGoal(row?.value));
  }

  /// 写步数目标；越界直接拒绝（界面 `validator` 还会再拦一次，见 D11 范围）。
  Future<void> updateDailyGoal(int goal) async {
    if (goal < minDailyGoal || goal > maxDailyGoal) {
      throw ArgumentError.value(
        goal,
        'goal',
        '步数目标必须在 $minDailyGoal–$maxDailyGoal 之间',
      );
    }
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: dailyGoalKey, value: '$goal'),
        );
  }

  static int _parseDailyGoal(String? raw) {
    if (raw == null) return defaultDailyGoal;
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) return defaultDailyGoal;
    if (parsed < minDailyGoal || parsed > maxDailyGoal) return defaultDailyGoal;
    return parsed;
  }

  /// 应用内开关当前值；缺键/坏值 = **开启**（旧行为：装了就读）。
  Future<bool> readEnabled() async {
    final row = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(enabledKey))).getSingleOrNull();
    return row?.value.trim() != 'false';
  }

  /// 订阅开关（设置页改完，今日页步数卡立刻跟着变）。
  Stream<bool> watchEnabled() {
    final query = database.select(database.appSettings)
      ..where((row) => row.key.equals(enabledKey));
    return query.watchSingleOrNull().map((row) => row?.value.trim() != 'false');
  }

  /// 写应用内开关。关闭后 [syncToday] 不再读数、不再落库。
  Future<void> setEnabled(bool enabled) async {
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: enabledKey,
            value: enabled ? 'true' : 'false',
          ),
        );
  }

  /// 同步某一天：读传感器 → 与基线做差 → 落库。返回本次的结果。
  ///
  /// **不可用时一个字都不写**：没有传感器 / 没授权 / 没读到值都不该在
  /// 步数表里留下一行——留下 `steps: 0` 就是把「没读成」记成「没走过」。
  ///
  /// **当天第一次读只立基线，不写行**（2026-10-26，用户：「步数它读不到系统
  /// 数据」）：此刻累计值就是基线，「今日步数」还不存在——原来会落一行 0，
  /// 卡上显示「0 / 10,000 步」，用户以为读数坏了。现在把基线落好、先不出数，
  /// 第二次同步才有可信差值。
  ///
  /// **手动记录优先**：某天是用户自己填的（`source = manual`）⇒ 传感器不覆盖
  /// 它（用户原话：「也不能自己输入」，填了就该算数）。要交还给传感器就用
  /// [clearManualSteps]。
  Future<StepsSyncResult> syncToday(String localDate) async {
    // 应用内开关关闭 = 不读、不写（2026-10-23 用户：「授权取消不掉」）。
    if (!await readEnabled()) {
      return const StepsSyncResult(
        reading: StepsReading(availability: StepsAvailability.disabled),
        saved: false,
        steps: null,
      );
    }
    final reading = await channel.read();
    if (reading.availability != StepsAvailability.available) {
      return StepsSyncResult(reading: reading, saved: false, steps: null);
    }
    final previous = await readBaseline();
    final today = resolveTodaySteps(
      reading: reading,
      localDate: localDate,
      baseline: previous,
    );
    final baselineIsNew = previous == null || previous.localDate != localDate;
    final existing = await _readRow(localDate);
    final now = clock.nowUtc();
    await database.transaction(() async {
      // 手动记录优先：不写步数行，但基线照常跟进（清掉手动后能立刻算差值）。
      if (existing?.source == sourceManual) {
        await _writeBaselineIfChanged(previous, today.baseline);
        return;
      }
      // 当天第一次读 = 只立基线：不落 0（0 不是「还没读到」的事实）。
      if (baselineIsNew) {
        await _writeBaselineIfChanged(previous, today.baseline);
        return;
      }
      // 一天一行：冲突目标必须是 `localDate` 的 UNIQUE（不是 id——id 每次都
      // 是新生成的，按 id upsert 等于没有 upsert，第二次同步当天就会撞
      // `UNIQUE constraint failed: steps_daily.local_date`）。
      if (existing == null) {
        await database
            .into(database.stepsDaily)
            .insert(
              StepsDailyCompanion.insert(
                id: idGenerator.next(),
                localDate: localDate,
                steps: today.steps,
                source: sourceDeviceCounter,
                recordedAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (database.update(
          database.stepsDaily,
        )..where((row) => row.localDate.equals(localDate))).write(
          StepsDailyCompanion(
            steps: Value(today.steps),
            source: Value(sourceDeviceCounter),
            recordedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
      await _writeBaselineIfChanged(previous, today.baseline);
    });
    if (existing?.source == sourceManual) {
      return StepsSyncResult(
        reading: reading,
        saved: false,
        steps: null,
        manualKept: true,
      );
    }
    if (baselineIsNew) {
      return StepsSyncResult(
        reading: reading,
        saved: false,
        steps: null,
        baselineEstablished: true,
      );
    }
    return StepsSyncResult(
      reading: reading,
      saved: true,
      steps: today.steps,
      resetBaseline: today.resetBaseline,
    );
  }

  /// 基线只在「跨天 / 重启」时才需要重写；同一天同一基线反复写是白写。
  Future<void> _writeBaselineIfChanged(
    StepsBaseline? previous,
    StepsBaseline next,
  ) async {
    if (previous != null &&
        previous.localDate == next.localDate &&
        previous.counter == next.counter) {
      return;
    }
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: baselineKey,
            value: _encodeBaseline(next),
          ),
        );
  }

  /// 手动记录某天的步数（覆盖当天行，`source = manual`）。
  ///
  /// 为什么允许：没有计步传感器、或系统权限/读数一直拿不到的设备上，用户
  /// 仍然知道自己走了多少——「读不到」不该等于「记不了」（用户 2026-10-26
  /// 原话：「也不能自己输入」）。
  Future<void> saveManualSteps({
    required String localDate,
    required int steps,
  }) async {
    if (steps < 0 || steps > maxManualSteps) {
      throw const FormatException('步数需在 0–200,000 之间。');
    }
    final now = clock.nowUtc();
    await database.transaction(() async {
      final existing = await _readRow(localDate);
      if (existing == null) {
        await database
            .into(database.stepsDaily)
            .insert(
              StepsDailyCompanion.insert(
                id: idGenerator.next(),
                localDate: localDate,
                steps: steps,
                source: sourceManual,
                recordedAt: now,
                createdAt: now,
                updatedAt: now,
              ),
            );
      } else {
        await (database.update(
          database.stepsDaily,
        )..where((row) => row.localDate.equals(localDate))).write(
          StepsDailyCompanion(
            steps: Value(steps),
            source: Value(sourceManual),
            recordedAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// 清掉某天的手动记录（让传感器重新接管）。
  ///
  /// **只删手动行**：传感器写的行不是用户的手动记录，删了就是抹掉真实数据。
  Future<void> clearManualSteps(String localDate) async {
    final existing = await _readRow(localDate);
    if (existing?.source != sourceManual) return;
    await (database.delete(
      database.stepsDaily,
    )..where((row) => row.localDate.equals(localDate))).go();
  }

  /// 读取基线；没有 / 坏值都返回 null（当作首次）。
  Future<StepsBaseline?> readBaseline() async {
    final row = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(baselineKey))).getSingleOrNull();
    final raw = row?.value;
    if (raw == null) return null;
    return StepsBaseline.fromJson(_decodeBaseline(raw));
  }

  /// 某一天已落库的步数（null = 那天没有行）。
  Future<int?> stepsForDate(String localDate) async =>
      (await readDay(localDate))?.steps;

  /// 某一天的步数 + 来源（界面据此标「手动」；null = 那天没有行）。
  Future<StepsDayValue?> readDay(String localDate) async {
    final row = await _readRow(localDate);
    if (row == null) return null;
    return StepsDayValue(steps: row.steps, source: row.source);
  }

  /// 监听某一天的步数（首页步数卡用；写入即推送）。
  Stream<int?> watchDate(String localDate) =>
      watchDay(localDate).map((value) => value?.steps);

  /// 监听某一天的步数 + 来源（步数卡要能标出「手动」这一事实）。
  Stream<StepsDayValue?> watchDay(String localDate) {
    final query = database.select(database.stepsDaily)
      ..where((row) => row.localDate.equals(localDate))
      ..limit(1);
    return query.watchSingleOrNull().map(
      (row) => row == null
          ? null
          : StepsDayValue(steps: row.steps, source: row.source),
    );
  }

  Future<StepsDailyEntry?> _readRow(String localDate) =>
      (database.select(database.stepsDaily)
            ..where((row) => row.localDate.equals(localDate))
            ..limit(1))
          .getSingleOrNull();

  /// 删除某一天的步数行（用户清空当日数据时用）。
  Future<void> clearDate(String localDate) async {
    await (database.delete(
      database.stepsDaily,
    )..where((row) => row.localDate.equals(localDate))).go();
  }

  /// 只探一次「现在能不能读」（设置页的授权行用，docs/30 §2 D9）。
  ///
  /// **不落库、不改基线**——与 [syncToday] 分开正是为了这个：设置页问的是
  /// 「权限/传感器现在什么状态」，不是「今天走了多少」。用 [syncToday] 去
  /// 顺带取状态会在设置页产生写副作用（重设基线、写入 0 步行）。
  Future<StepsAvailability> readAvailability() async =>
      (await channel.read()).availability;

  /// 申请「身体活动」权限（API 29+）。返回是否已授权。
  ///
  /// 转发到通道而不是让界面直接持 [StepsChannel]：界面只认仓储，
  /// 通道换实现（比如将来改 EventChannel）时界面不用动。
  Future<bool> requestPermission() => channel.requestPermission();

  /// 打开本应用的系统设置页（权限被拒后的出口）。
  Future<void> openAppSettings() => channel.openAppSettings();

  /// 基线存 JSON 字符串（而不是两个键）——`localDate` 与 `counter` 必须同时
  /// 有效，拆成两个键就可能读到「A 日的 counter 配 B 日的日期」。
  static String _encodeBaseline(StepsBaseline baseline) =>
      jsonEncode(baseline.toJson());

  static Map<String, Object?>? _decodeBaseline(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      // 坏值当作「没有基线」：重设基线的代价只是今日从 0 起算，
      // 比抛异常把整个步数卡打死小得多。
      return null;
    }
  }
}

/// 一次同步的结果（界面据此决定画哪个态）。
final class StepsSyncResult {
  const StepsSyncResult({
    required this.reading,
    required this.saved,
    required this.steps,
    this.resetBaseline = false,
    this.baselineEstablished = false,
    this.manualKept = false,
  });

  final StepsReading reading;

  /// 是否真的落库了（不可用时为 false）。
  final bool saved;

  /// 落库的今日步数；[saved] 为 false 时是 null。
  final int? steps;

  /// 本次检测到计数值回退（设备重启），基线已重设。
  final bool resetBaseline;

  /// 当天第一次读：**只立了基线、没有落步数**（2026-10-26）。
  ///
  /// 界面据此说「刚开始读，走几步后再看」，而不是拿一个 0 当「今天没走」。
  final bool baselineEstablished;

  /// 当天是手动记录：传感器这次**没有覆盖**它（用户填的数优先）。
  final bool manualKept;

  StepsAvailability get availability => reading.availability;
}

/// 某一天的步数 + 来源（步数卡要能如实标出「手动」）。
final class StepsDayValue {
  const StepsDayValue({required this.steps, required this.source});

  final int steps;

  /// [StepsRepository.sourceDeviceCounter] | [StepsRepository.sourceManual]
  final String source;

  bool get isManual => source == StepsRepository.sourceManual;
}
