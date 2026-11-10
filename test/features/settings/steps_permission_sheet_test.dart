import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/presentation/steps_permission_sheet.dart';

/// 需求 2（docs/60 §0 的「步数检测无法使用」）：弹层要**先回答「到底是哪一种」**。
///
/// docs/59 §1 的三种可能（未授权 / 设备不支持 / 状态未知）**修法不同**，所以
/// 用户看到的必须分得清；并且每一态都要给**能做的事**：
/// * 未授权 → 「去系统设置」（既有入口）；
/// * 设备不支持 → 明说（不显示假的 0 步）；
/// * 这次没读到 / 状态未知 → 「重试」（以前没有，只能重启 App）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/steps');
  late AppDatabase database;
  final now = DateTime(2026, 10, 25, 10);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await database.close();
  });

  StepsRepository repository() => StepsRepository(
    database: database,
    channel: StepsChannel(),
    idGenerator: _Ids(),
    clock: FixedAppClock(now),
  );

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showStepsPermissionSheet(context, repository()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  void stubRead(Object? Function() payload) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') return payload();
          return null;
        });
  }

  group('重新读取的忙碌态（2026-10-31）', _refreshBusyMain);

  testWidgets('未授权：说清「未授权」并给「去系统设置」', (tester) async {
    stubRead(() => <Object?, Object?>{'status': 'denied'});
    await pumpSheet(tester);
    expect(find.textContaining('未授权'), findsWidgets);
    expect(find.byKey(const Key('cta-open-app-settings')), findsOneWidget);
    expect(
      find.byKey(const Key('steps-retry')),
      findsNothing,
      reason: '未授权是权限问题，重试读不出权限来——给重试是假动作',
    );
  });

  testWidgets('设备不支持：明说没有传感器（不显示假的 0 步）', (tester) async {
    stubRead(
      () => <Object?, Object?>{
        'status': 'unavailable',
        'reason': 'no_counter_sensor',
      },
    );
    await pumpSheet(tester);
    // 【v2（design/round8/steps-sheet-v2.html）】说明文字压缩：状态一句话
    // 「设备不支持计步」+ 一行提示「这台设备没有计步传感器，手动记录不受影响」。
    expect(find.textContaining('设备不支持'), findsWidgets);
    expect(find.textContaining('没有计步传感器'), findsWidgets);
  });

  testWidgets('这次没读到：给「重试」（可自己救回来）', (tester) async {
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') {
            reads++;
            return <Object?, Object?>{
              'status': 'unavailable',
              'reason': 'no_event',
            };
          }
          return null;
        });
    await pumpSheet(tester);
    expect(find.textContaining('这次没读到'), findsWidgets);
    final retry = find.byKey(const Key('steps-retry'));
    expect(retry, findsOneWidget, reason: '「这次没读到」必须给重试');

    final before = reads;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(reads, greaterThan(before), reason: '点重试要真的再读一次');
  });

  testWidgets('已授权：说清已连接（不再误导用户去找权限）', (tester) async {
    stubRead(
      () => <Object?, Object?>{'status': 'ok', 'counter': 8432, 'atMs': 1},
    );
    await pumpSheet(tester);
    // 【v2】状态句从「已授权：正在读取…」压成「已连接 · 自动读取中」；
    // 「已授权」这个说法只在设置页的状态行保留（那里是权限视角）。
    expect(find.textContaining('已连接'), findsWidgets);
    expect(
      find.byKey(const Key('cta-open-app-settings')),
      findsOneWidget,
      reason: '已授权时「去系统设置」仍是「去撤销」的入口（v2 按状态出现）',
    );
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'steps-${_value++}';
}

/// 2026-10-31 用户：「步数点击重新读取要显示动画或读取状态」。
///
/// 判据三条，都在「重新读取」这颗按钮上：
/// 1. 点下去立刻变忙碌态（文案「读取中…」+ 禁用），不是点了没反应；
/// 2. 忙碌期间连点**不会**再发一次传感器读（两次读争同一基线会算出错差值）；
/// 3. 同步结束（无论成功还是抛异常）按钮都恢复可点——异常把它永久卡在
///    禁用态，就是另一种「点了没反应」。
void _refreshBusyMain() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/steps');
  late AppDatabase database;
  final now = DateTime(2026, 10, 25, 10);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await database.close();
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = StepsRepository(
      database: database,
      channel: StepsChannel(),
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showStepsPermissionSheet(
                  context,
                  repository,
                  localDate: '2026-10-25',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('重新读取：点击后进入「读取中…」忙碌态，且连点不重复读', (tester) async {
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') {
            reads++;
            // 前两次读都立刻返回（弹层加载状态那一次 + 「重新读取」点下去后
            // 同步自带的那一次读数）；之后才卡住——忙碌态在「重读弹层字段」
            // 这段里稳定存在，正是用户能看到的那段。
            if (reads <= 2) {
              return <Object?, Object?>{
                'status': 'ok',
                'counter': 9000,
                'atMs': 1,
              };
            }
            return Future<Object?>.delayed(
              const Duration(seconds: 30),
              () => <Object?, Object?>{
                'status': 'ok',
                'counter': 9500,
                'atMs': 2,
              },
            );
          }
          return null;
        });
    await pumpSheet(tester);

    final refresh = find.byKey(const Key('steps-refresh'));
    expect(refresh, findsOneWidget, reason: '已授权态必须有「重新读取」');
    await tester.tap(refresh);
    await tester.pump();

    expect(find.text('读取中…'), findsOneWidget, reason: '点击后必须立刻给出读取状态');
    final before = reads;
    await tester.tap(refresh);
    await tester.tap(refresh);
    await tester.pump();
    expect(reads, before, reason: '忙碌期间连点不得再发一次传感器读');

    // 让挂起的读完成，按钮恢复。
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('重新读取'), findsOneWidget, reason: '读完后按钮必须恢复');
  });

  testWidgets('重新读取抛异常：按钮仍恢复可点（不被永久卡在禁用态）', (tester) async {
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') {
            reads++;
            if (reads == 1) {
              return <Object?, Object?>{
                'status': 'ok',
                'counter': 9000,
                'atMs': 1,
              };
            }
            throw PlatformException(code: 'boom');
          }
          return null;
        });
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('steps-refresh')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('重新读取'), findsOneWidget, reason: '异常后按钮必须恢复可点');
    expect(tester.takeException(), isNull);
  });
}
