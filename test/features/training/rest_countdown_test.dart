import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/features/training/presentation/rest_countdown.dart';

void main() {
  test('rest countdown counts down from wall-clock end time', () {
    final now = DateTime.utc(2026, 9, 12, 10, 0, 0);
    final restEnd = now.add(const Duration(seconds: 90));

    expect(restSecondsRemaining(restEnd, now), 90);
    expect(
      restSecondsRemaining(restEnd, now.add(const Duration(seconds: 30))),
      60,
    );
    expect(
      restSecondsRemaining(restEnd, now.add(const Duration(minutes: 5))),
      0,
    );
  });

  group('weekdayOfLocalDate（docs/11 §3-F：存库日期可能畸形）', () {
    test('解析合法日期为星期几（1 = 周一）', () {
      // 2026-09-07 是周一。
      expect(weekdayOfLocalDate('2026-09-07'), 1);
      expect(weekdayOfLocalDate('2026-09-13'), 7);
    });

    test('非日期文本返回 null 而不是抛异常', () {
      for (final value in [
        'not-a-date',
        '',
        '2026-09',
        '2026-09-07-extra',
        'yyyy-mm-dd',
        '2026/09/07',
      ]) {
        expect(weekdayOfLocalDate(value), isNull, reason: value);
      }
    });

    test('被 DateTime 归一化的日期视为非法', () {
      // 2026-02-31 不存在；DateTime 会悄悄滚到 03-03，不能当成合法日期。
      expect(weekdayOfLocalDate('2026-02-31'), isNull);
      expect(weekdayOfLocalDate('2026-13-01'), isNull);
    });
  });

  group('RestCountdown 组件（docs/21 §3：环形倒计时 + 最后 3 秒脉冲 + 结束轻震）', () {
    final base = DateTime(2026, 9, 19, 12);

    /// 可控时钟：pump 推进的假时间映射到墙钟。
    DateTime Function() testClock(DateTime base, WidgetTester tester) {
      final start = tester.binding.clock.now();
      return () => base.add(tester.binding.clock.now().difference(start));
    }

    Widget harness(WidgetTester tester, {required DateTime restEnd}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: RestCountdown(
              restEnd: restEnd,
              total: const Duration(seconds: 90),
              clock: testClock(base, tester),
            ),
          ),
        ),
      );
    }

    RestRingPainter painterOf(WidgetTester tester) =>
        tester
                .widget<CustomPaint>(
                  find.byWidgetPredicate(
                    (w) => w is CustomPaint && w.painter is RestRingPainter,
                  ),
                )
                .painter!
            as RestRingPainter;

    void captureHaptics(List<String> haptics) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      // 新版 Flutter 里 selectionClick 也走 'HapticFeedback.vibrate'
      // 方法，类型在 arguments 里（nav_bar_2_0_test 同款模式）。
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
    }

    testWidgets('横幅：环 painter + display 档数字 + 原文案/key 保留', (tester) async {
      await tester.pumpWidget(
        harness(tester, restEnd: base.add(const Duration(seconds: 90))),
      );
      await tester.pump();

      // 业务文案与 key 逐字不变（既有页面级测试断言依赖）。
      expect(find.text('休息 90s'), findsOneWidget);
      expect(find.byKey(const Key('training-rest-countdown')), findsOneWidget);

      // 环形 painter：满环起步（90/90）。
      final painter = painterOf(tester);
      expect(painter.remainingSeconds, 90);
      expect(painter.totalSeconds, 90);

      // 环心数字走 display 档（40/w800/tabular）。
      final number = tester.widget<Text>(find.text('90'));
      expect(number.style!.fontSize, LfText.displayHero.fontSize);
      expect(number.style!.fontWeight, LfText.displayHero.fontWeight);
      expect(number.style!.fontFeatures, LfText.displayHero.fontFeatures);
    });

    testWidgets('中途：环随剩余秒数收缩（45/90），无脉冲', (tester) async {
      await tester.pumpWidget(
        harness(tester, restEnd: base.add(const Duration(seconds: 90))),
      );
      await tester.pump(const Duration(seconds: 45));

      expect(painterOf(tester).remainingSeconds, 45);
      expect(find.text('休息 45s'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('45'), matching: find.byType(Transform)),
        findsNothing,
        reason: '剩 3 秒以上不跑脉冲',
      );
    });

    testWidgets('最后 3 秒：环脉冲放大（scale > 1），到点隐藏', (tester) async {
      await tester.pumpWidget(
        harness(tester, restEnd: base.add(const Duration(seconds: 5))),
      );
      // 推进到剩 2s，停在脉冲周期的中点（scale 峰值附近）。
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 150));

      final transform = tester.widget<Transform>(
        find
            .ancestor(of: find.text('2'), matching: find.byType(Transform))
            .first,
      );
      expect(
        transform.transform.storage[0],
        greaterThan(1.0),
        reason: '脉冲中点 scale > 1',
      );

      // 到点后脉冲停止、横幅隐藏。
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('休息 2s'), findsNothing);
    });

    testWidgets('结束轻震：归零只 light 触觉一次', (tester) async {
      final haptics = <String>[];
      captureHaptics(haptics);

      await tester.pumpWidget(
        harness(tester, restEnd: base.add(const Duration(seconds: 90))),
      );
      await tester.pump();
      expect(haptics, isEmpty);

      // 一路推进到归零（Timer.periodic 每秒触发一次 _tick）。
      await tester.pump(const Duration(seconds: 89));
      expect(haptics, isEmpty, reason: '倒计时未结束不触觉');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(haptics, hasLength(1), reason: '结束轻震恰好一次');

      // 多泵不再补发。
      await tester.pump(const Duration(seconds: 3));
      expect(haptics, hasLength(1));
    });

    testWidgets('减弱动画：脉冲层退化为静止（触觉不是动画，照常触发）', (tester) async {
      final haptics = <String>[];
      captureHaptics(haptics);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: harness(tester, restEnd: base.add(const Duration(seconds: 5))),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        find.ancestor(of: find.text('2'), matching: find.byType(Transform)),
        findsNothing,
        reason: '减弱动画下不跑脉冲缩放',
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(haptics, hasLength(1));
    });
  });
}
