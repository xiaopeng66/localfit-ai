import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai/domain/ai_connectivity_monitor.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';

/// D-2：断网提示条只在有「刚连不上」证据时出现；成功一次即消失。
void main() {
  testWidgets('连接失败后显示提示；成功一次后消失', (tester) async {
    final monitor = AiConnectivityMonitor(
      now: () => DateTime.utc(2026, 10, 21, 4),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: AiOfflineBanner(monitor: monitor)),
      ),
    );
    expect(find.byKey(const Key('ai-chat-offline-note')), findsNothing);

    monitor.record(
      const NetworkFailure('连不上', kind: NetworkFailureKind.connection),
    );
    await tester.pump();
    expect(find.byKey(const Key('ai-chat-offline-note')), findsOneWidget);
    expect(find.textContaining('本地记录、搜索与记忆写入不受影响'), findsOneWidget);

    monitor.recordSuccess();
    await tester.pump();
    expect(find.byKey(const Key('ai-chat-offline-note')), findsNothing);
  });

  testWidgets('超时不算断网：不显示提示', (tester) async {
    final monitor = AiConnectivityMonitor(
      now: () => DateTime.utc(2026, 10, 21, 4),
    );
    monitor.record(
      const NetworkFailure('超时', kind: NetworkFailureKind.timeout),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: AiOfflineBanner(monitor: monitor)),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('ai-chat-offline-note')), findsNothing);
  });
}
