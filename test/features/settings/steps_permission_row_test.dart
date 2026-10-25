import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

/// 设置页「步数与身体活动」授权行（docs/30 §2 D9 / 用户需求 3）。
///
/// 用户原话是「步数的授权需要在设置页面可以取消」。这条需求有一个**容易做错
/// 的地方**：Android 的运行时权限只能由用户在系统设置里撤销，应用内做一个
/// 「取消授权」的开关只能停用读数、撤不掉权限本身。所以本文件的断言围绕
/// 两件事：
///
/// ① 设置页**如实说出**当前状态（四态各自不同的话），不猜、不合并；
/// ② 唯一动作是**把用户送到系统设置页**（`openAppSettings`），
///    并且**没有任何**会写库的副作用。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/steps');
  Object? readReply;

  /// `openAppSettings` 被调的次数（唯一出口，测它真的被调到了）。
  var openSettingsCalls = 0;

  setUp(() {
    readReply = null;
    openSettingsCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'read':
              return readReply;
            case 'requestPermission':
              return <Object?, Object?>{'status': 'denied'};
            case 'openAppSettings':
              openSettingsCalls++;
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  StepsRepository repository() => StepsRepository(
    database: database,
    channel: StepsChannel(),
    idGenerator: _Ids(),
    clock: FixedAppClock(DateTime(2026, 10, 8, 9).toUtc()),
  );

  /// 只挂设置页（不挂整 App）：本行是设置页自己的组件，页面其余部分需要
  /// 一大堆可选依赖，全塞进来只会让失败原因变模糊。
  ///
  /// **不套 `Scaffold` / 滚动容器**：`SettingsPage` 自己就带 `Scaffold` +
  /// `ListView`（`settings_page.dart:268`），再套一层会得到无界高度约束
  /// （`RenderCustomMultiChildLayoutBox object was given an infinite size`）。
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light(), home: child);

  /// 滚到某个节点出现为止（`ListView` 懒构建，屏幕外的行不在树上）。
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
  }

  /// 设置页很长，本行在「数据管理」组里；滚到它出现为止再返回。
  Future<void> pumpSettings(WidgetTester tester, StepsRepository repo) async {
    await tester.pumpWidget(
      host(SettingsPage(stepsRepository: repo, now: DateTime(2026, 10, 8))),
    );
    await tester.pumpAndSettle();
    final finder = find.byKey(const Key('settings-steps-permission'));
    await scrollTo(tester, finder);
    expect(finder, findsOneWidget, reason: '数据管理组里的步数授权行没出现');
  }

  Future<void> closeDatabase(WidgetTester tester) async {
    // 先卸载再关库：drift 的流注销排在 0ms timer 上，活着订阅时 close 会把
    // timer 留在 fake_async 里挂死整个用例。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  }

  group('设置页步数授权行（docs/30 D9）', () {
    testWidgets('未接线（stepsRepository == null）：整组渲染但这一行不渲染', (tester) async {
      // **必须让「数据管理」组本身在场**（这里靠注入开关存储把组撑起来），
      // 否则整组不渲染时下面的断言会因为「组都没了」而恒真——那证明不了
      // 是「这一行」按 null 判定隐藏的。
      await tester.pumpWidget(
        host(
          SettingsPage(
            appSettingsRepository: AppSettingsRepository(database: database),
            now: DateTime(2026, 10, 8),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // 组在页面下半部分，先滚到它出现（懒构建）。
      await scrollTo(tester, find.byKey(const Key('settings-group-data')));

      expect(
        find.byKey(const Key('settings-group-data')),
        findsOneWidget,
        reason: '先确认组在场，负断言才有意义',
      );
      expect(
        find.byKey(const Key('settings-steps-permission')),
        findsNothing,
        reason: '未接线时不渲染该行（与 settings-scale-row 同约定）',
      );
    });

    testWidgets('已授权：短词「已授权」+ mint 档徽章', (tester) async {
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 8432,
        'atMs': 1,
      };
      await pumpSettings(tester, repository());

      expect(
        find.byKey(const Key('settings-steps-permission')),
        findsOneWidget,
      );
      expect(find.text('步数与身体活动'), findsOneWidget);
      expect(find.text('已授权'), findsOneWidget);

      final badge = tester.widget<LfBadge>(
        find.descendant(
          of: find.byKey(const Key('settings-steps-permission')),
          matching: find.byType(LfBadge),
        ),
      );
      expect(
        badge.variant,
        LfBadgeVariant.mint,
        reason: '「已授权」是「一切正常」态，用品牌浅底档',
      );

      await closeDatabase(tester);
    });

    testWidgets('未授权：短词「未授权」+ honey 档徽章（与已授权不同档）', (tester) async {
      readReply = <Object?, Object?>{'status': 'denied'};
      await pumpSettings(tester, repository());

      expect(find.text('未授权'), findsOneWidget);
      // 「已授权」四个字里含「授权」，用精确匹配确认没写成「已授权」。
      expect(find.text('已授权'), findsNothing);

      final badge = tester.widget<LfBadge>(
        find.descendant(
          of: find.byKey(const Key('settings-steps-permission')),
          matching: find.byType(LfBadge),
        ),
      );
      expect(
        badge.variant,
        LfBadgeVariant.honey,
        reason: '「未授权」要「用户点一下就能改」的提示色，不是 muted',
      );

      await closeDatabase(tester);
    });

    testWidgets('无传感器：说「设备不支持」，不说「未授权」', (tester) async {
      readReply = <Object?, Object?>{
        'status': 'unavailable',
        'reason': 'no_counter_sensor',
      };
      await pumpSettings(tester, repository());

      expect(find.text('设备不支持'), findsOneWidget);
      expect(
        find.text('未授权'),
        findsNothing,
        reason: '这台设备永远读不到 ≠ 用户没授权（用户动作完全不同）',
      );

      await closeDatabase(tester);
    });

    testWidgets('读数失败（noReading）：说「状态未知」，不冒充已授权', (tester) async {
      // 通道回了 px 解析不出的状态 ⇒ StepsChannel 翻成 noReading。
      readReply = <Object?, Object?>{'status': 'something_new'};
      await pumpSettings(tester, repository());

      expect(find.text('状态未知'), findsOneWidget);
      expect(find.text('已授权'), findsNothing, reason: '读不到就是读不到，不许拿一个乐观默认值顶替');

      await closeDatabase(tester);
    });

    testWidgets('探状态**不写库**：行读完之后步数表仍是空的', (tester) async {
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 8432,
        'atMs': 1,
      };
      final repo = repository();
      await pumpSettings(tester, repo);

      // 授权行只问「能不能读」，不该在设置页产生任何落库副作用——包括
      // 不要把「今天 0 步」写进表里，也不该动基线。
      expect(
        await repo.stepsForDate('2026-10-08'),
        isNull,
        reason: '设置页只是看状态；写库是今日页步数卡的事',
      );
      expect(
        await repo.readBaseline(),
        isNull,
        reason: '基线也不该被设置页立起来（那会让今日页的首读语义变形）',
      );

      await closeDatabase(tester);
    });

    testWidgets('点整行 → 说明弹层：正文说清「去系统设置」，且此刻还没跳', (tester) async {
      readReply = <Object?, Object?>{'status': 'denied'};
      await pumpSettings(tester, repository());

      expect(openSettingsCalls, 0, reason: '点之前不该有任何跳转');
      await tester.tap(find.byKey(const Key('settings-steps-permission')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('steps-permission-sheet-body')),
        findsOneWidget,
      );
      // 弹层正文必须同时说清「在哪取消」与「取消后会怎样」。
      expect(find.textContaining('在系统设置里关闭「身体活动」权限'), findsOneWidget);
      expect(find.textContaining('步数卡显示「未授权」'), findsOneWidget);
      expect(find.textContaining('其余功能不受影响'), findsOneWidget);
      expect(openSettingsCalls, 0, reason: '只是打开说明弹层，还没到跳转那一步');

      await closeDatabase(tester);
    });

    testWidgets('弹层「去系统设置」→ 真的调 openAppSettings，且弹层已关', (tester) async {
      readReply = <Object?, Object?>{'status': 'denied'};
      await pumpSettings(tester, repository());

      await tester.tap(find.byKey(const Key('settings-steps-permission')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cta-open-app-settings')));
      await tester.pumpAndSettle();

      expect(openSettingsCalls, 1, reason: '「去系统设置」是本需求的唯一出口，必须真的调到原生');
      expect(
        find.byKey(const Key('steps-permission-sheet-body')),
        findsNothing,
        reason: '跳转前要先关弹层（否则用户从系统设置回来会看到弹层还压着）',
      );

      await closeDatabase(tester);
    });

    // 2026-10-23 用户：「步数授权取消不掉」——弹层里加应用内开关：
    // 关掉后真的停读停写；系统权限仍要用户自己去系统设置撤销（两件事
    // 分开说，不把开关说成「已取消授权」）。
    testWidgets('应用内开关：关闭 → enabled=false，再点 → 恢复', (tester) async {
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 5000,
        'atMs': 1,
      };
      final repo = repository();
      await pumpSettings(tester, repo);

      await tester.tap(find.byKey(const Key('settings-steps-permission')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('steps-enabled-switch')), findsOneWidget);
      expect(find.byKey(const Key('steps-enabled-note')), findsOneWidget);
      expect(
        find.textContaining('系统里的「身体活动」权限仍要在系统设置里单独撤销'),
        findsOneWidget,
        reason: '开关 ≠ 撤销系统权限，这句必须写清楚',
      );
      expect(await repo.readEnabled(), isTrue, reason: '默认开启');

      await tester.tap(find.byKey(const Key('steps-enabled-switch')));
      await tester.pumpAndSettle();
      expect(await repo.readEnabled(), isFalse);

      await tester.tap(find.byKey(const Key('steps-enabled-switch')));
      await tester.pumpAndSettle();
      expect(await repo.readEnabled(), isTrue);

      await closeDatabase(tester);
    });

    testWidgets('弹层「取消」→ 不跳转、弹层关闭', (tester) async {
      readReply = <Object?, Object?>{'status': 'denied'};
      await pumpSettings(tester, repository());

      await tester.tap(find.byKey(const Key('settings-steps-permission')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(openSettingsCalls, 0);
      expect(
        find.byKey(const Key('steps-permission-sheet-body')),
        findsNothing,
      );

      await closeDatabase(tester);
    });

    testWidgets('已授权时也保留「去系统设置」入口（它是「去撤销」的路）', (tester) async {
      readReply = <Object?, Object?>{'status': 'ok', 'counter': 1, 'atMs': 1};
      await pumpSettings(tester, repository());

      await tester.tap(find.byKey(const Key('settings-steps-permission')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('cta-open-app-settings')),
        findsOneWidget,
        reason: '用户点这一行就是想改权限；授权了就藏按钮等于把撤销路堵死',
      );

      await closeDatabase(tester);
    });

    testWidgets('授权行不做任何写动作：整屏没有 Switch，也没有「取消授权」这种假开关', (tester) async {
      readReply = <Object?, Object?>{'status': 'ok', 'counter': 1, 'atMs': 1};
      await pumpSettings(tester, repository());

      expect(
        find.byType(Switch),
        findsNothing,
        reason: '应用内开关撤不掉系统权限，只停用读数 ⇒ 与诚实条款冲突',
      );
      expect(find.text('取消授权'), findsNothing);
    });
  });
}

class _Ids implements IdGenerator {
  var _value = 0;

  @override
  String next() => 'r6-id-${++_value}';
}
