import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';

/// 后台任务状态（docs/41 G16）。状态机：
/// `pending` → `processing` →（成功 ⇒ 删除）/（失败 ⇒ `failed`，可重试）。
enum BackgroundJobState {
  pending,
  processing,
  failed;

  static BackgroundJobState parse(String raw) => values.firstWhere(
    (value) => value.name == raw,
    orElse: () => BackgroundJobState.pending,
  );
}

/// 一条后台任务的只读视图。
final class JobRecord {
  const JobRecord({
    required this.id,
    required this.type,
    required this.state,
    required this.attempts,
    required this.payload,
    required this.progress,
    this.lastError,
    this.dedupeKey,
  });

  final String id;
  final String type;
  final BackgroundJobState state;
  final int attempts;
  final Map<String, Object?> payload;
  final int? progress;
  final String? lastError;
  final String? dedupeKey;

  bool get isRetryable => state == BackgroundJobState.failed;
}

/// 通用任务队列底座（docs/41 G16）：状态/重试/**断点续跑**/限流由调用侧配。
///
/// 设计要点：
/// * **幂等入队**：同一 [dedupeKey] 的未完成任务不重复入队（返回既有 id）；
/// * **可重试**：`fail()` 记 attempts 与 lastError，`retryAllFailed()` /
///   `requeue()` 把它放回 pending——断点续跑就是「重启后重跑 pending+failed」；
/// * **心跳**：`touch()` 更新 `updatedAt`，调用侧据此发现僵死任务；
/// * **不进备份**（派生状态，docs/41 §11）。
final class BackgroundJobRepository {
  const BackgroundJobRepository({
    required this.database,
    required this.clock,
    required this.idGenerator,
  });

  final AppDatabase database;
  final AppClock clock;
  final IdGenerator idGenerator;

  Future<int> count({BackgroundJobState? state, String? type}) async {
    final query = database.selectOnly(database.backgroundJobs)
      ..addColumns([database.backgroundJobs.id.count()]);
    if (state != null) {
      query.where(database.backgroundJobs.state.equals(state.name));
    }
    if (type != null) {
      query.where(database.backgroundJobs.type.equals(type));
    }
    final row = await query.getSingle();
    return row.read(database.backgroundJobs.id.count()) ?? 0;
  }

  /// 入队（幂等）。返回任务 id；同 [dedupeKey] 已有未完成任务时返回它。
  Future<String> enqueue({
    required String type,
    Map<String, Object?> payload = const {},
    String? dedupeKey,
  }) async {
    if (dedupeKey != null) {
      final existing =
          await (database.select(database.backgroundJobs)..where(
                (row) =>
                    row.dedupeKey.equals(dedupeKey) &
                    row.state.isNotValue(BackgroundJobState.failed.name),
              ))
              .getSingleOrNull();
      if (existing != null) return existing.id;
    }
    final now = clock.nowUtc();
    final id = idGenerator.next();
    await database
        .into(database.backgroundJobs)
        .insert(
          BackgroundJobsCompanion.insert(
            id: id,
            type: type,
            payloadJson: Value(jsonEncode(payload)),
            dedupeKey: Value(dedupeKey),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// 取一条可跑任务并原子标成 `processing`（简单领取；并发调用方由
  /// 调用侧串行化——端上只有一个执行器）。
  Future<JobRecord?> claimNext({String? type}) async {
    final query = database.select(database.backgroundJobs)
      ..where((row) => row.state.equals(BackgroundJobState.pending.name))
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
      ..limit(1);
    if (type != null) {
      query.where((row) => row.type.equals(type));
    }
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    await (database.update(
      database.backgroundJobs,
    )..where((r) => r.id.equals(row.id))).write(
      BackgroundJobsCompanion(
        state: Value(BackgroundJobState.processing.name),
        attempts: Value(row.attempts + 1),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
    return JobRecord(
      id: row.id,
      type: row.type,
      state: BackgroundJobState.processing,
      attempts: row.attempts + 1,
      payload: _decode(row.payloadJson),
      progress: row.progress,
      lastError: row.lastError,
      dedupeKey: row.dedupeKey,
    );
  }

  /// 按 id 读一条（待确认队列改写 payload 前重读，避免用陈旧副本覆盖）。
  Future<JobRecord?> byId(String id) async {
    final row = await (database.select(
      database.backgroundJobs,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row == null ? null : _map(row);
  }

  /// 按 id 领取（会话结束提炼要「入队后立即执行这一条」，不能误领别人的）。
  /// 只有 `pending` 可领；已被领走/已完成返回 null。
  Future<JobRecord?> claimById(String id) async {
    final row = await (database.select(
      database.backgroundJobs,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (row == null || row.state != BackgroundJobState.pending.name) {
      return null;
    }
    await (database.update(
      database.backgroundJobs,
    )..where((r) => r.id.equals(id))).write(
      BackgroundJobsCompanion(
        state: Value(BackgroundJobState.processing.name),
        attempts: Value(row.attempts + 1),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
    return JobRecord(
      id: row.id,
      type: row.type,
      state: BackgroundJobState.processing,
      attempts: row.attempts + 1,
      payload: _decode(row.payloadJson),
      progress: row.progress,
      lastError: row.lastError,
      dedupeKey: row.dedupeKey,
    );
  }

  /// 覆盖 payload（待确认队列：候选存这里，处理一条就改写一次）。
  Future<void> updatePayload(String id, Map<String, Object?> payload) async {
    await (database.update(
      database.backgroundJobs,
    )..where((row) => row.id.equals(id))).write(
      BackgroundJobsCompanion(
        payloadJson: Value(jsonEncode(payload)),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
  }

  /// 成功：删行（任务的产物应当由任务自己写进正表）。
  Future<void> complete(String id) async {
    await (database.delete(
      database.backgroundJobs,
    )..where((row) => row.id.equals(id))).go();
  }

  /// 失败：记 attempts 与原因，状态 `failed`（可重试）。
  Future<void> fail(String id, {required String error}) async {
    await (database.update(
      database.backgroundJobs,
    )..where((row) => row.id.equals(id))).write(
      BackgroundJobsCompanion(
        state: Value(BackgroundJobState.failed.name),
        lastError: Value(error),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
  }

  /// 进度（0–100）。
  Future<void> reportProgress(String id, int progress) async {
    await (database.update(
      database.backgroundJobs,
    )..where((row) => row.id.equals(id))).write(
      BackgroundJobsCompanion(
        progress: Value(progress.clamp(0, 100)),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
  }

  /// 心跳（僵死检测用）。
  Future<void> touch(String id) async {
    await (database.update(database.backgroundJobs)
          ..where((row) => row.id.equals(id)))
        .write(BackgroundJobsCompanion(updatedAt: Value(clock.nowUtc())));
  }

  /// 把**单条**任务放回 pending（门控不满足/被抢占时用；不碰其它任务）。
  Future<void> requeue(String id) async {
    await (database.update(
      database.backgroundJobs,
    )..where((row) => row.id.equals(id))).write(
      BackgroundJobsCompanion(
        state: Value(BackgroundJobState.pending.name),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
  }

  /// 把失败任务放回 pending（重试一次）；返回受影响行数。
  Future<int> retryFailed({String? type}) {
    final query = database.update(database.backgroundJobs)
      ..where((row) => row.state.equals(BackgroundJobState.failed.name));
    if (type != null) {
      query.where((row) => row.type.equals(type));
    }
    return query.write(
      BackgroundJobsCompanion(
        state: Value(BackgroundJobState.pending.name),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
  }

  /// 断点续跑：把 `processing`（上次进程被杀留下的）放回 pending。
  /// 返回受影响行数。
  Future<int> recoverInterrupted() {
    return (database.update(
          database.backgroundJobs,
        )..where((row) => row.state.equals(BackgroundJobState.processing.name)))
        .write(
          BackgroundJobsCompanion(
            state: Value(BackgroundJobState.pending.name),
            updatedAt: Value(clock.nowUtc()),
          ),
        );
  }

  /// 列出任务（调试面板/进度展示用）。
  Future<List<JobRecord>> list({BackgroundJobState? state}) async {
    final query = database.select(database.backgroundJobs)
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    if (state != null) {
      query.where((row) => row.state.equals(state.name));
    }
    final rows = await query.get();
    return [for (final row in rows) _map(row)];
  }

  Future<int> clearAll() => database.delete(database.backgroundJobs).go();

  JobRecord _map(BackgroundJob row) => JobRecord(
    id: row.id,
    type: row.type,
    state: BackgroundJobState.parse(row.state),
    attempts: row.attempts,
    payload: _decode(row.payloadJson),
    progress: row.progress,
    lastError: row.lastError,
    dedupeKey: row.dedupeKey,
  );

  Map<String, Object?> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}
