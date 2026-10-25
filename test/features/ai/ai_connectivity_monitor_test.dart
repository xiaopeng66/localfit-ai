import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai/domain/ai_connectivity_monitor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/degradation_matrix.dart';

/// D-2（2026-10-21 裁决 A）：不新增 connectivity 依赖，用**真实的连接失败
/// 证据**判「无网」，并把结果接进降级矩阵。
void main() {
  late DateTime now;
  late AiConnectivityMonitor monitor;

  setUp(() {
    now = DateTime.utc(2026, 10, 21, 4);
    monitor = AiConnectivityMonitor(now: () => now);
  });

  test('只有 connection 失败算断网证据；超时不算', () {
    monitor.record(
      const NetworkFailure('连不上', kind: NetworkFailureKind.timeout),
    );
    expect(monitor.isOffline, isFalse);

    monitor.record(
      const NetworkFailure('连不上', kind: NetworkFailureKind.connection),
    );
    expect(monitor.isOffline, isTrue);
  });

  test('成功一次即清除证据（恢复网络后提示要消失）', () {
    monitor.record(
      const NetworkFailure('连不上', kind: NetworkFailureKind.connection),
    );
    expect(monitor.isOffline, isTrue);
    monitor.recordSuccess();
    expect(monitor.isOffline, isFalse);
  });

  test('证据超过 10 分钟窗口自动失效', () {
    monitor.record(
      const NetworkFailure('连不上', kind: NetworkFailureKind.connection),
    );
    now = now.add(const Duration(minutes: 9));
    expect(monitor.isOffline, isTrue);
    now = now.add(const Duration(minutes: 2));
    expect(monitor.isOffline, isFalse);
  });

  test('矩阵推导：未配置优先，配置后按证据判离线', () {
    expect(
      degradationRowFor(aiConfigured: false, offline: true),
      DegradationRow.aiNotConfigured,
      reason: '没配置 AI 时用户该做的是去配置，不是查网络',
    );
    expect(
      degradationRowFor(aiConfigured: true, offline: true),
      DegradationRow.offline,
    );
    expect(
      degradationRowFor(aiConfigured: true, offline: false),
      DegradationRow.chatModelUnavailable,
    );
  });

  test('无网行的搜索格：本地语义可用 ⇒ 不标注降级', () {
    expect(
      degradationNotice(DegradationRow.offline, DegradationColumn.search),
      isEmpty,
      reason: '端上向量不需要网络，断网不该说搜索降级',
    );
    expect(
      kDegradationMatrix[DegradationRow.offline]![DegradationColumn.search]!
          .behavior,
      contains('端上语义'),
    );
  });
}
