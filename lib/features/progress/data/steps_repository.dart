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
    final now = clock.nowUtc();
    await database.transaction(() async {
      // 一天一行：冲突目标必须是 `localDate` 的 UNIQUE（不是 id——id 每次都
      // 是新生成的，按 id upsert 等于没有 upsert，第二次同步当天就会撞
      // `UNIQUE constraint failed: steps_daily.local_date`）。
      final existing =
          await (database.select(database.stepsDaily)
                ..where((row) => row.localDate.equals(localDate))
                ..limit(1))
              .getSingleOrNull();
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
      // 基线只在「跨天 / 重启」时才需要重写；同一天同一基线反复写是白写。
      final baselineChanged =
          previous == null ||
          previous.localDate != today.baseline.localDate ||
          previous.counter != today.baseline.counter;
      if (baselineChanged) {
        await database
            .into(database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: baselineKey,
                value: _encodeBaseline(today.baseline),
              ),
            );
      }
    });
    return StepsSyncResult(
      reading: reading,
      saved: true,
      steps: today.steps,
      resetBaseline: today.resetBaseline,
    );
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
  Future<int?> stepsForDate(String localDate) async {
    final row =
        await (database.select(database.stepsDaily)
              ..where((row) => row.localDate.equals(localDate))
              ..limit(1))
            .getSingleOrNull();
    return row?.steps;
  }

  /// 监听某一天的步数（首页步数卡用；写入即推送）。
  Stream<int?> watchDate(String localDate) {
    final query = database.select(database.stepsDaily)
      ..where((row) => row.localDate.equals(localDate))
      ..limit(1);
    return query.watchSingleOrNull().map((row) => row?.steps);
  }

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
  });

  final StepsReading reading;

  /// 是否真的落库了（不可用时为 false）。
  final bool saved;

  /// 落库的今日步数；[saved] 为 false 时是 null。
  final int? steps;

  /// 本次检测到计数值回退（设备重启），基线已重设。
  final bool resetBaseline;

  StepsAvailability get availability => reading.availability;
}
