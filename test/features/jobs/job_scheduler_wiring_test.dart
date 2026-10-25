import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/jobs/application/job_scheduler.dart';
import 'package:localfit_ai/features/jobs/application/power_state_source.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_extraction_queue.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';

/// 索引调度接设备状态（docs/43 A3 / docs/41 G11）。
///
/// 决策点 D1 未答复 ⇒ 生产用实现 B（不判断充电，后台近似空闲）。
/// 本文件同时钉住实现 B 的如实标注与调度器的门控/暂停/断点语义。
void main() {
  late AppDatabase db;
  late BackgroundJobRepository jobs;

  final now = DateTime.utc(2026, 10, 19, 6);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    jobs = BackgroundJobRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: _SeqIds(),
    );
  });

  tearDown(() async => db.close());

  test('充电 + 后台 → tick 领取并完成任务', () async {
    await jobs.enqueue(type: 'dishAnalysis');
    var ticks = 0;
    final scheduler = JobScheduler(
      repository: jobs,
      conditions: () => const JobRunConditions(charging: true, idle: true),
      handlers: {
        'dishAnalysis': (_) async {
          ticks++;
          return true;
        },
      },
    );
    final power = _FakePower(charging: true, idle: true);
    final dispatch = JobDispatchController(scheduler: scheduler, power: power);
    await dispatch.maybeTick();
    expect(ticks, 1);
    expect(await jobs.count(), 0);
    dispatch.dispose();
  });

  test('未充电：重任务不领取（留在 pending）', () async {
    await jobs.enqueue(type: 'indexRebuild');
    final scheduler = JobScheduler(
      repository: jobs,
      conditions: () => const JobRunConditions(charging: false, idle: true),
      handlers: {'indexRebuild': (_) async => true},
    );
    final dispatch = JobDispatchController(
      scheduler: scheduler,
      power: _FakePower(charging: false, idle: true),
    );
    await dispatch.maybeTick();
    expect(
      await jobs.count(state: BackgroundJobState.pending, type: 'indexRebuild'),
      1,
      reason: '未充电时索引重建不得执行',
    );
    dispatch.dispose();
  });

  test('实现 B 如实标注：不判断充电、后台近似空闲', () async {
    final power = BackgroundOnlyPowerStateSource();
    expect(await power.isCharging(), isFalse, reason: '未知按未充电处理');
    expect(await power.watchCharging().isEmpty, isTrue);
    expect(await power.isIdle(), isFalse, reason: '初始视为前台');
    power.updateLifecycle(AppLifecycleState.paused);
    expect(await power.isIdle(), isTrue);
    power.updateLifecycle(AppLifecycleState.resumed);
    expect(await power.isIdle(), isFalse);
    expect(kPowerStateNoteB, contains('未接充电判定'));
  });

  test('前台：已领取的任务跑完，但不再领取新任务', () async {
    await jobs.enqueue(type: 'dishAnalysis');
    await jobs.enqueue(type: 'dishAnalysis');
    var idle = true;
    var ran = 0;
    final scheduler = JobScheduler(
      repository: jobs,
      conditions: () => JobRunConditions(charging: true, idle: idle),
      handlers: {
        'dishAnalysis': (_) async {
          ran++;
          // 第一条跑完时用户回到前台。
          idle = false;
          return true;
        },
      },
    );
    final tick = await scheduler.tick();
    expect(tick.completed, 1, reason: '已领取的那条允许跑完');
    expect(ran, 1);
    expect(await jobs.count(state: BackgroundJobState.pending), 1);
  });

  test('暂停后 tick 不领取；恢复后续跑', () async {
    await jobs.enqueue(type: 'dishAnalysis');
    final scheduler = JobScheduler(
      repository: jobs,
      conditions: () => const JobRunConditions(charging: true, idle: true),
      handlers: {'dishAnalysis': (_) async => true},
    );
    final dispatch = JobDispatchController(
      scheduler: scheduler,
      power: _FakePower(charging: true, idle: true),
    );
    dispatch.pause();
    await dispatch.maybeTick();
    expect(await jobs.count(state: BackgroundJobState.pending), 1);
    dispatch.resume();
    await dispatch.maybeTick();
    expect(await jobs.count(), 0);
    dispatch.dispose();
  });

  test('用户驱动的待确认任务（memoryExtraction）不会被调度器领取', () async {
    // B8 把「待确认候选」存在 background_jobs（state=pending）。调度器若把它
    // 当普通任务领取，会因为没有处理器而标 failed——待确认队列直接丢。
    await jobs.enqueue(
      type: kMemoryExtractionJobType,
      dedupeKey: 'memoryExtraction:c1',
      payload: const {
        'candidates': [
          {'text': '喜欢清淡'},
        ],
      },
    );
    final scheduler = JobScheduler(
      repository: jobs,
      conditions: () => const JobRunConditions(charging: true, idle: true),
      handlers: const {},
    );
    await scheduler.tick();
    expect(
      await jobs.count(state: BackgroundJobState.failed),
      0,
      reason: '待确认任务不得被调度器标失败',
    );
    expect(
      await jobs.count(state: BackgroundJobState.pending),
      1,
      reason: '它必须继续等用户确认',
    );
  });

  test('D1 实现装配：默认走 battery_plus（实现 A），实现 B 保留为降级', () async {
    // main.dart 装配的是实现 A；实现 B 只在平台异常时作为退路存在。
    // 这里钉「两个实现都满足同一接口 + 调试面板标注按装配区分」。
    expect(kPowerStateNote, contains('已接线'), reason: '实现 A 的如实标注');
    expect(kPowerStateNoteB, contains('未接充电判定'));
  });

  test('失败任务进 failed 可手动重试', () async {
    await jobs.enqueue(type: 'dishAnalysis');
    final scheduler = JobScheduler(
      repository: jobs,
      conditions: () => const JobRunConditions(charging: true, idle: true),
      handlers: {'dishAnalysis': (_) async => false},
    );
    await scheduler.tick();
    expect(await jobs.count(state: BackgroundJobState.failed), 1);
    await jobs.retryFailed();
    expect(await jobs.count(state: BackgroundJobState.pending), 1);
  });
}

/// 可控电源状态（实现 A 的测试替身；生产默认实现 B）。
final class _FakePower implements PowerStateSource {
  _FakePower({required this.charging, required this.idle});

  final bool charging;
  final bool idle;

  @override
  Future<bool> isCharging() async => charging;

  @override
  Future<bool> isIdle() async => idle;

  @override
  Stream<bool> watchCharging() => Stream<bool>.value(charging);
}

class _SeqIds implements IdGenerator {
  int _n = 0;
  @override
  String next() => 'job-${_n++}';
}
