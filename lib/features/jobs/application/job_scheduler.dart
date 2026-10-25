import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';

/// 任务的运行条件（docs/41 §9.7 / G11）：**充电 + 空闲**才跑，可暂停。
///
/// 把「什么时候允许跑」与「跑什么」分开：
/// * [state] 是外部世界的快照（充电/屏幕/空闲），由平台层填；
/// * [JobScheduler] 只做门控、串行执行、暂停/恢复与进度上报。
///
/// 断点续跑：任务被中断时 `background_jobs` 里仍是 `processing`（进程被杀）
/// 或 `pending`（调度器暂停）；下次启动先 `recoverInterrupted()` 再继续。
final class JobRunConditions {
  const JobRunConditions({
    required this.charging,
    required this.idle,
    this.networkAvailable = true,
  });

  /// 是否在充电（docs/41 G11：充电是硬条件，避免耗电）。
  final bool charging;

  /// 是否空闲（无前台交互/低负载）。
  final bool idle;

  /// 需要联网的任务额外看这条（本地任务不看）。
  final bool networkAvailable;

  /// 是否允许跑「索引重建」这类重任务。
  bool get canRunHeavy => charging && idle;

  /// 是否允许跑轻任务（打标/AI 分析）：空闲即可，不必充电。
  bool get canRunLight => idle;
}

/// 一次调度循环的结果（测试与调试面板读它）。
final class SchedulerTick {
  const SchedulerTick({
    required this.ran,
    required this.completed,
    required this.failed,
    required this.skippedReason,
  });

  final int ran;
  final int completed;
  final int failed;

  /// 没跑的原因（`paused` / `notCharging` / `notIdle` / `empty`）。
  final String? skippedReason;
}

/// 任务处理器：返回 `true` = 成功（删除任务），`false` = 失败（可重试）。
typedef JobHandler = Future<bool> Function(JobRecord job);

/// 这些类型进 `background_jobs` 只是**借它的存储**等人确认，不是待执行工作。
///
/// `memoryExtraction`（docs/43 B8）把候选存在 payload、`state=pending` 表示
/// 「等用户在记忆页确认」——调度器若当普通任务领取，会因没有处理器标 failed，
/// 待确认队列整批丢失。它们**永不**被调度器领取。
const Set<String> kUserConfirmedJobTypes = {'memoryExtraction'};

/// 任务调度器（单执行器；端上只有一个前台 isolate）。
///
/// 纪律：
/// * **可暂停**：`pause()` 之后不再领取新任务；正在跑的那条跑完为止
///   （不打断写入，避免半条数据）。
/// * **门控**：`heavy` 任务要求充电 + 空闲；轻任务只要空闲。
/// * **断点**：`start()` 先 `recoverInterrupted()`，把上次进程留下的
///   `processing` 放回 `pending`，所以「重开 App 继续跑」是默认行为。
final class JobScheduler {
  JobScheduler({
    required this.repository,
    required this.conditions,
    required this.handlers,
    this.maxTasksPerTick = 8,
  });

  final BackgroundJobRepository repository;

  /// 条件读取是**每次 tick 现取**（充电状态会变，不能构造时缓存）。
  final JobRunConditions Function() conditions;

  /// 任务类型 → 处理器。没有处理器的类型不会被领取（留给自己实现）。
  final Map<String, JobHandler> handlers;

  /// 一次 tick 最多跑几条（限流，避免长时间占用）。
  final int maxTasksPerTick;

  bool _paused = false;
  bool _running = false;

  bool get isPaused => _paused;
  bool get isRunning => _running;

  void pause() => _paused = true;
  void resume() => _paused = false;

  /// 跑一轮（不阻塞 UI；调用方在空闲时机调用）。
  Future<SchedulerTick> tick() async {
    if (_paused) {
      return const SchedulerTick(
        ran: 0,
        completed: 0,
        failed: 0,
        skippedReason: 'paused',
      );
    }
    if (_running) {
      return const SchedulerTick(
        ran: 0,
        completed: 0,
        failed: 0,
        skippedReason: 'alreadyRunning',
      );
    }
    final current = conditions();
    if (!current.canRunLight) {
      return const SchedulerTick(
        ran: 0,
        completed: 0,
        failed: 0,
        skippedReason: 'notIdle',
      );
    }
    _running = true;
    var ran = 0;
    var completed = 0;
    var failed = 0;
    try {
      // 断点续跑：先把上次进程留下的 processing 放回 pending。
      await repository.recoverInterrupted();
      while (ran < maxTasksPerTick && !_paused) {
        // **每条领取前重读条件**（docs/43 A3）：应用回到前台后不再领取
        // 新任务；已经领取的那条会跑完（不打断写入）。
        final live = conditions();
        if (!live.canRunLight) {
          return SchedulerTick(
            ran: ran,
            completed: completed,
            failed: failed,
            skippedReason: 'notIdle',
          );
        }
        final job = await repository.claimNext();
        if (job == null) break;
        if (kUserConfirmedJobTypes.contains(job.type)) {
          // 放回 pending 并结束本轮（它不是可跑任务；继续循环会无限自旋）。
          await repository.requeue(job.id);
          return SchedulerTick(
            ran: ran,
            completed: completed,
            failed: failed,
            skippedReason: 'awaitingUser',
          );
        }
        final handler = handlers[job.type];
        if (handler == null) {
          // 没有处理器：如实标失败（不静默丢、不空转）。
          await repository.fail(job.id, error: '未注册处理器：${job.type}');
          failed++;
          continue;
        }
        if (_requiresCharging(job.type) && !live.canRunHeavy) {
          // 重任务在非充电时**只**把这一条放回 pending，等下次。
          await repository.requeue(job.id);
          return SchedulerTick(
            ran: ran,
            completed: completed,
            failed: failed,
            skippedReason: 'notCharging',
          );
        }
        ran++;
        try {
          final ok = await handler(job);
          if (ok) {
            await repository.complete(job.id);
            completed++;
          } else {
            await repository.fail(job.id, error: '任务返回失败');
            failed++;
          }
        } on Object catch (error) {
          await repository.fail(job.id, error: '$error');
          failed++;
        }
      }
      return SchedulerTick(
        ran: ran,
        completed: completed,
        failed: failed,
        skippedReason: ran == 0 ? 'empty' : null,
      );
    } finally {
      _running = false;
    }
  }

  /// 需要充电的重任务（索引重建 / 批量打标）。
  bool _requiresCharging(String type) =>
      type == 'indexRebuild' || type == 'ingredientTagging';
}
