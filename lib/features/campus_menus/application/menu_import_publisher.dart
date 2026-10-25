import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/menu_normalize/data/menu_normalize_json_decoder.dart';

/// 菜单导入发布失败。
class MenuPublishException implements Exception {
  const MenuPublishException(this.errors, {this.userMessage});

  final List<String> errors;

  /// 可上屏文案（本地撰写、可行动）。null = 本异常只有开发者文本
  /// （英文、可能含驱动异常原文），调用方必须用自己的固定兜底文案，
  /// 绝不回显 [errors]（docs/11 §3-B 错误出口白名单化）。
  final String? userMessage;

  @override
  String toString() => 'MenuPublishException: ${errors.join('; ')}';
}

class MenuPublishResult {
  const MenuPublishResult({
    required this.jobId,
    this.snapshotId,
    this.duplicateOf,
  });

  final String jobId;

  /// 成功发布时的新快照 id。
  final String? snapshotId;

  /// skipIfHashMatches 命中重复内容时指向既有快照。
  final String? duplicateOf;
}

/// 把 [MenuNormalizeDraft] 发布为正式 `MenuSnapshot`（docs/07 §6.3）。
///
/// - 事务内写 import job → snapshot → services → items；
/// - 同 venue+businessDate 的旧 active 快照标记 superseded；
/// - 内容 hash 幂等（同日期同内容直接返回既有快照）；
/// - 任何校验失败：job 标记 failed、异常上抛、旧快照不动。
final class MenuImportPublisher {
  MenuImportPublisher({required this.database});

  final AppDatabase database;
  final Sha256 _sha256 = Sha256();

  Future<MenuPublishResult> publishDraft({
    required String venueId,
    required String sourceId,
    required String businessDate,
    required MenuNormalizeDraft draft,
    bool skipIfHashMatches = false,
    DateTime? now,
  }) async {
    final contentHash = await _hashDraft(draft);
    // 入库时间戳可注入：调用方给了时刻（导入链路共用一个时钟）就用它。
    final stamp = (now ?? DateTime.now()).toUtc();
    final jobId = await _uniqueId('menu_import_jobs', 'menu-job', stamp);

    await database
        .into(database.menuImportJobs)
        .insert(
          MenuImportJobsCompanion.insert(
            id: jobId,
            sourceId: sourceId,
            status: 'validating',
            startedAt: stamp,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );

    try {
      // 运行时校验：任何失败都让 job=failed 且旧快照不动。
      if (draft.venueName.trim().isEmpty) {
        throw const MenuPublishException(['draft venue_name is empty']);
      }
      if (!_isoDate.hasMatch(businessDate)) {
        throw MenuPublishException([
          'businessDate must be an ISO-8601 date: $businessDate',
        ]);
      }
      // 内容 hash 幂等：同 venue+日期+内容已存在 active 快照则跳过。
      if (skipIfHashMatches) {
        final existing =
            await (database.select(database.menuSnapshots)
                  ..where(
                    (row) =>
                        row.venueId.equals(venueId) &
                        row.businessDate.equals(businessDate) &
                        row.status.equals('active') &
                        row.contentHash.equals(contentHash),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (existing != null) {
          await _finishJob(
            jobId,
            'completed',
            parsedItems: _itemCount(draft),
            snapshotId: existing.id,
            now: stamp,
          );
          return MenuPublishResult(jobId: jobId, duplicateOf: existing.id);
        }
      }

      final snapshotId = await _uniqueId('menu_snapshots', 'snapshot', stamp);
      await database.transaction(() async {
        // 旧 active 快照退位。
        await (database.update(database.menuSnapshots)..where(
              (row) =>
                  row.venueId.equals(venueId) &
                  row.businessDate.equals(businessDate) &
                  row.status.equals('active'),
            ))
            .write(const MenuSnapshotsCompanion(status: Value('superseded')));

        await database
            .into(database.menuSnapshots)
            .insert(
              MenuSnapshotsCompanion.insert(
                id: snapshotId,
                sourceId: sourceId,
                venueId: venueId,
                businessDate: businessDate,
                contentHash: contentHash,
                importedAt: stamp,
                createdAt: stamp,
                updatedAt: stamp,
              ),
            );

        var itemCount = 0;
        for (final service in draft.services) {
          final serviceId = 'service-$snapshotId-${_slug(service.serviceName)}';
          await database
              .into(database.menuServices)
              .insert(
                MenuServicesCompanion.insert(
                  id: serviceId,
                  snapshotId: snapshotId,
                  name: service.serviceName,
                  openTime: service.openTime,
                  closeTime: service.closeTime,
                  createdAt: stamp,
                  updatedAt: stamp,
                ),
              );
          for (final item in service.items) {
            await database
                .into(database.menuItems)
                .insert(
                  MenuItemsCompanion.insert(
                    id: 'item-$snapshotId-$itemCount',
                    serviceId: serviceId,
                    displayName: item.displayName,
                    stationName: Value.absentIfNull(item.stationName),
                    // AI 草案无本地营养证据 → D 级、待匹配（docs/07 §6.4）。
                    evidenceGrade: const Value('D'),
                    itemStatus: const Value('unresolved'),
                    createdAt: stamp,
                    updatedAt: stamp,
                  ),
                );
            itemCount += 1;
          }
        }

        await (database.update(
          database.menuImportJobs,
        )..where((row) => row.id.equals(jobId))).write(
          MenuImportJobsCompanion(
            status: const Value('completed'),
            parsedItemCount: Value(itemCount),
            snapshotId: Value(snapshotId),
            finishedAt: Value(stamp),
            updatedAt: Value(stamp),
          ),
        );
      });

      return MenuPublishResult(jobId: jobId, snapshotId: snapshotId);
    } on MenuPublishException {
      await _finishJob(jobId, 'failed', parseErrors: 1, now: stamp);
      rethrow;
    } catch (error) {
      await _finishJob(jobId, 'failed', parseErrors: 1, now: stamp);
      throw MenuPublishException(['publish failed: $error']);
    }
  }

  /// 记一条解析失败的 job（docs/07 §6.2：导入过程可观测）。解析在草案阶段就失败、
  /// 还没走到发布，所以这条 job 由调用方直接落库；[message] 只用于断言，不上屏。
  Future<void> recordFailedJob({
    required String sourceId,
    required String message,
    DateTime? now,
  }) async {
    assert(message.isNotEmpty);
    final stamp = (now ?? DateTime.now()).toUtc();
    await database
        .into(database.menuImportJobs)
        .insert(
          MenuImportJobsCompanion.insert(
            id: await _uniqueId('menu_import_jobs', 'menu-job', stamp),
            sourceId: sourceId,
            status: 'failed',
            parseErrorCount: const Value(1),
            startedAt: stamp,
            finishedAt: Value(stamp),
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
  }

  /// 生成一个库里还没用过的 id。
  ///
  /// id 用时间戳构造（可读、按导入时间有序），但毫秒级时间戳**不保证唯一**：
  /// 同一毫秒内连着导入两次，或测试注入固定时钟，都会撞主键（2.0-1j 的
  /// 幂等用例真的撞出了 `UNIQUE constraint failed: menu_import_jobs.id`）。
  /// 撞了就加序号继续找，序号只影响重复时刻的 id 可读性，不影响按时间排序。
  Future<String> _uniqueId(String table, String prefix, DateTime stamp) async {
    final base = '$prefix-${stamp.millisecondsSinceEpoch}';
    var candidate = base;
    var suffix = 0;
    while (await _idTaken(table, candidate)) {
      suffix += 1;
      candidate = '$base-$suffix';
    }
    return candidate;
  }

  Future<bool> _idTaken(String table, String id) async =>
      (await database
          .customSelect(
            'SELECT 1 AS present FROM $table WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingleOrNull()) !=
      null;

  Future<void> _finishJob(
    String jobId,
    String status, {
    int parsedItems = 0,
    int parseErrors = 0,
    String? snapshotId,
    DateTime? now,
  }) async {
    final stamp = (now ?? DateTime.now()).toUtc();
    await (database.update(
      database.menuImportJobs,
    )..where((row) => row.id.equals(jobId))).write(
      MenuImportJobsCompanion(
        status: Value(status),
        parsedItemCount: Value(parsedItems),
        parseErrorCount: Value(parseErrors),
        snapshotId: Value.absentIfNull(snapshotId),
        finishedAt: Value(stamp),
        updatedAt: Value(stamp),
      ),
    );
  }

  int _itemCount(MenuNormalizeDraft draft) =>
      draft.services.fold(0, (sum, s) => sum + s.items.length);

  Future<String> _hashDraft(MenuNormalizeDraft draft) async {
    // 归一化 JSON 序列化保证同内容同 hash。
    final canonical = jsonEncode({
      'venue': draft.venueName.trim(),
      'date': draft.sourceDate,
      'services': [
        for (final service in draft.services)
          {
            'name': service.serviceName.trim(),
            'open': service.openTime,
            'close': service.closeTime,
            'items': [
              for (final item in service.items)
                {'name': item.displayName.trim()},
            ],
          },
      ],
    });
    final digest = await _sha256.hash(utf8.encode(canonical));
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _slug(String raw) =>
      raw.replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');
}

final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
