import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/back_navigation.dart';

/// 【2026-10-31 用户】返回手势体系：
/// 1. 页内可取消状态（如记录页多选）经 [AppBackInterceptors] 被返回手势
///    取消，而不是把应用退到桌面；
/// 2. 没有可取消状态时，**双击返回才退出应用**——第一击只提示，2 秒内
///    第二击才真退（用户：手势退出软件需要二次滑动的限制）。
void main() {
  tearDown(() => AppExitGate.resetForTest());

  group('AppBackInterceptors（页内可取消状态，LIFO）', () {
    test('后注册的先被问；消费后不再往下走', () {
      final calls = <String>[];
      final unregisterA = AppBackInterceptors.register(() {
        calls.add('a');
        return false;
      });
      final unregisterB = AppBackInterceptors.register(() {
        calls.add('b');
        return true;
      });
      expect(AppBackInterceptors.maybeHandle(), isTrue);
      expect(calls, ['b'], reason: '后注册（更靠近当前状态）先问');
      expect(AppBackInterceptors.maybeHandle(), isTrue);
      expect(calls, ['b', 'b'], reason: '消费后即止，不落到 a');
      unregisterB();
      expect(AppBackInterceptors.maybeHandle(), isFalse);
      expect(calls, ['b', 'b', 'a'], reason: 'b 注销后轮到 a；a 返回 false ⇒ 未消费');
      unregisterA();
    });

    test('注销函数可安全重复调用', () {
      final unregister = AppBackInterceptors.register(() => true);
      unregister();
      unregister();
      expect(AppBackInterceptors.maybeHandle(), isFalse);
    });
  });

  group('AppExitGate（双击返回才退出应用）', () {
    Widget host(WidgetTester tester) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => AppExitGate.handleShellBack(context),
              child: const Text('back'),
            ),
          ),
        ),
      ),
    );

    testWidgets('第一击只提示，不退出；窗口内第二击才真退', (tester) async {
      var exited = 0;
      AppExitGate.onExit = () async => exited++;
      var now = DateTime(2026, 10, 31, 12);
      AppExitGate.clock = () => now;

      await tester.pumpWidget(host(tester));

      await tester.tap(find.text('back'));
      await tester.pump();
      expect(exited, 0, reason: '第一击只提示');
      expect(find.text('再按一次返回键退出'), findsOneWidget);

      now = now.add(const Duration(seconds: 1)); // 窗口内
      await tester.tap(find.text('back'));
      await tester.pump();
      expect(exited, 1, reason: '2 秒窗口内的第二击真正退出');
    });

    testWidgets('超过窗口的第二击不退出，重新提示（再等第三击）', (tester) async {
      var exited = 0;
      AppExitGate.onExit = () async => exited++;
      var now = DateTime(2026, 10, 31, 12);
      AppExitGate.clock = () => now;

      await tester.pumpWidget(host(tester));

      await tester.tap(find.text('back'));
      await tester.pump();
      expect(find.text('再按一次返回键退出'), findsOneWidget);

      now = now.add(const Duration(seconds: 3)); // 已出窗口
      await tester.tap(find.text('back'));
      await tester.pump();
      expect(exited, 0, reason: '窗口外的第二击仍是「提示」，不退出');
      expect(find.text('再按一次返回键退出'), findsOneWidget);

      now = now.add(const Duration(seconds: 1));
      await tester.tap(find.text('back'));
      await tester.pump();
      expect(exited, 1, reason: '重新计时的窗口内第三击退出');
    });

    testWidgets('拦截器消费过的返回不触发退出提示（多选优先）', (tester) async {
      var exited = 0;
      AppExitGate.onExit = () async => exited++;
      var consumed = false;
      final unregister = AppBackInterceptors.register(() => consumed = true);

      await tester.pumpWidget(host(tester));
      await tester.tap(find.text('back'));
      await tester.pump();

      expect(consumed, isTrue);
      expect(exited, 0, reason: '被拦截器消费的返回不走退出通道');
      expect(find.text('再按一次返回键退出'), findsNothing);
      unregister();
    });
  });
}
