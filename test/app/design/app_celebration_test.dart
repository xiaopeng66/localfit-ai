import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/app_celebration.dart';

/// docs/21 §2.9 庆祝时刻：全屏 mint 粒子爆发 1.2s（30 粒子、物理下落），
/// 每次会话最多触发 1 次防打扰；减弱动画（disableAnimations）不播放粒子。
void main() {
  group('AppCelebrationGuard（每会话最多 1 次）', () {
    test('guard allows exactly one trigger per session', () {
      AppCelebrationGuard.resetForTest();
      addTearDown(AppCelebrationGuard.resetForTest);
      expect(AppCelebrationGuard.canTrigger, isTrue);
      expect(AppCelebrationGuard.markTriggered(), isTrue);
      expect(AppCelebrationGuard.canTrigger, isFalse);
      expect(AppCelebrationGuard.markTriggered(), isFalse);
      AppCelebrationGuard.resetForTest();
      expect(AppCelebrationGuard.canTrigger, isTrue);
    });
  });

  group('AppCelebrationBurst', () {
    testWidgets('renders particles, stays bounded, calls onDone once', (
      tester,
    ) async {
      var done = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AppCelebrationBurst(onDone: () => done++)),
        ),
      );
      await tester.pump();
      // 粒子层在播（CustomPainter 自绘，零新增依赖）。
      // 框架自身的 CustomPaint（Material 内部）不算粒子层，用 key 定位。
      expect(find.byKey(const Key('app-celebration-painter')), findsOneWidget);
      expect(done, 0);
      // 1.2s 有界动画：pumpAndSettle 能走完。
      await tester.pumpAndSettle();
      expect(done, 1);
      expect(find.byKey(const Key('app-celebration-painter')), findsNothing);
    });

    testWidgets('disableAnimations: no particles, done fires immediately', (
      tester,
    ) async {
      var done = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(body: AppCelebrationBurst(onDone: () => done++)),
          ),
        ),
      );
      await tester.pump();
      // 减弱动画：不播放粒子（直接结束）。框架自身的 CustomPaint 不算。
      expect(find.byKey(const Key('app-celebration-painter')), findsNothing);
      expect(done, 1);
    });
  });

  group('showAppCelebration', () {
    testWidgets('inserts the burst once per session and self-removes', (
      tester,
    ) async {
      AppCelebrationGuard.resetForTest();
      addTearDown(AppCelebrationGuard.resetForTest);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showAppCelebration(context),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.byType(AppCelebrationBurst), findsOneWidget);

      // 播完自动移除。
      await tester.pumpAndSettle();
      expect(find.byType(AppCelebrationBurst), findsNothing);

      // 同一会话第二次不触发（防打扰）。
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.byType(AppCelebrationBurst), findsNothing);
    });
  });
}
