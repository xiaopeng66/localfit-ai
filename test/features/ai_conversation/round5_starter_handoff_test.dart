import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart' show AppDatabase;
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';

/// T6b（docs/32 §4 T6b / §3 D5）：AI 创作卡 → 对话分支的**预填 + 自动发送**。
///
/// 四条验收语句：
///  ① 画廊卡生成 → 落在对话分支且消息**已自动发送**；
///  ② `isReplying` 时不自动发送（只预填 + 提示）；
///  ③ 冷启动（对话分支此前未建）pending 不丢；
///  ④ pending **只消费一次**。
void main() {
  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light(), home: child);

  final sent = <String>[];

  testWidgets('① 画廊卡生成 → 对话分支的输入被自动发送', (tester) async {
    sent.clear();
    final notifier = ValueNotifier<({String display, String send})?>(null);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      host(
        AiConversationPage(
          service: _FakeConversationService(onSend: sent.add),
          pendingStarter: notifier,
        ),
      ),
    );
    await tester.pumpAndSettle();

    notifier.value = (
      display: '按我描述的目标生成训练计划并保存：\n\n一周 4 练，增肌',
      send: '按我描述的目标生成训练计划并保存：\n\n一周 4 练，增肌',
    );
    await tester.pumpAndSettle();

    expect(sent, hasLength(1), reason: '空闲时应自动发送一次');
    expect(sent.single, contains('一周 4 练，增肌'));
    expect(notifier.value, isNull, reason: 'pending 消费即清空');
  });

  testWidgets('③ 冷启动：pending 先于页面创建，仍自动发送', (tester) async {
    sent.clear();
    const coldText = '按我的目标和今天已吃的，帮我搭配今天剩下几餐：\n\n随便';
    final notifier = ValueNotifier<({String display, String send})?>((
      display: coldText,
      send: coldText,
    ));
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      host(
        AiConversationPage(
          service: _FakeConversationService(onSend: sent.add),
          pendingStarter: notifier,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(sent, hasLength(1), reason: '冷启动时 pending 不丢');
    expect(sent.single, contains('帮我搭配今天剩下几餐'));
    expect(notifier.value, isNull, reason: '消费即清空');
  });

  testWidgets('④ 清空 pending 不触发发送（只消费一次）', (tester) async {
    sent.clear();
    final notifier = ValueNotifier<({String display, String send})?>(null);
    addTearDown(notifier.dispose);
    await tester.pumpWidget(
      host(
        AiConversationPage(
          service: _FakeConversationService(onSend: sent.add),
          pendingStarter: notifier,
        ),
      ),
    );
    await tester.pumpAndSettle();

    notifier.value = (display: '第一次请求', send: '第一次请求');
    await tester.pumpAndSettle();
    expect(sent, hasLength(1));

    // 消费后页面已清空：不重发。
    await tester.pumpAndSettle();
    expect(sent, hasLength(1), reason: '清空不应触发发送');
  });

  testWidgets('② isReplying 时只预填不发送（守卫）', (tester) async {
    sent.clear();
    final notifier = ValueNotifier<({String display, String send})?>(null);
    addTearDown(notifier.dispose);
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    await tester.pumpWidget(
      host(
        AiConversationPage(
          service: _FakeConversationService(
            onSend: sent.add,
            gate: gate.future,
          ),
          pendingStarter: notifier,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 第一条：进入回复中（流被 gate 挂起）。
    notifier.value = (display: '第一条请求', send: '第一条请求');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sent, hasLength(1));

    // 回复中再来一条：只预填。回复挂起 ⇒ 用定次数 pump（不能用 settle）。
    notifier.value = (display: '第二条请求（回复中到达）', send: '第二条请求（回复中到达）');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(sent, hasLength(1), reason: 'isReplying 时不得自动发送（避免打断进行中的回复）');
    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(
      fields.any((f) => f.controller?.text == '第二条请求（回复中到达）'),
      isTrue,
      reason: '守卫路径应把内容填进输入框交给用户',
    );

    gate.complete();
    await tester.pumpAndSettle();
  });

  group('食堂分析 · 真实路由图片交接', () {
    late AppDatabase database;
    late CanteenRepository canteen;
    late _PendingConversationService service;
    late Directory imageDirectory;
    final clock = FixedAppClock(DateTime.utc(2026, 11, 10, 4));

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      canteen = CanteenRepository(
        database: database,
        idGenerator: _HandoffIds(),
        clock: clock,
      );
      final imageBase = Directory('E:/AI/Zcode/tmp/localfit-image-handoff');
      imageBase.createSync(recursive: true);
      imageDirectory = imageBase.createTempSync('lf-router-starter-');
      addTearDown(() => imageDirectory.deleteSync(recursive: true));
      service = _PendingConversationService();
      addTearDown(service.close);
    });

    // 文件读取与图片解码是真异步，不能只推进 widget 测试的虚拟时钟。
    Future<void> drainIo(WidgetTester tester) async {
      for (var round = 0; round < 20; round++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<File> createPhoto(WidgetTester tester) async {
      final file = File('${imageDirectory.path}/dish.png');
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 2, 2),
          Paint()..color = const Color(0xFF112233),
        );
        final image = await recorder.endRecording().toImage(2, 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      return file;
    }

    Future<String> openDishActions(
      WidgetTester tester, {
      required bool warmAi,
      String? imagePath,
    }) async {
      final venueId = await canteen.createVenue(
        name: '东区食堂',
        campusName: '示范大学',
      );
      final windowId = await canteen.createWindow(
        venueId: venueId,
        name: '一楼快餐',
        openTime: '08:00',
        closeTime: '20:00',
      );
      final dishId = await canteen.createDish(
        windowId: windowId,
        name: '番茄炒蛋',
        imagePath: imagePath,
      );
      final GoRouter router = createAppRouter(
        initialLocation: AppRoutes.nutrition,
        foodRepository: FoodRepository(
          database: database,
          idGenerator: _HandoffIds(),
          clock: clock,
        ),
        canteenRepository: canteen,
        conversationService: service,
        now: DateTime(2026, 11, 10, 12),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(430, 932);
      addTearDown(tester.view.reset);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
      });
      await tester.pumpWidget(
        MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      );
      await tester.pumpAndSettle();

      if (warmAi) {
        await tester.tap(find.byKey(const Key('nav-ai-workbench')));
        await tester.pumpAndSettle();
        final aiState = tester.state(find.byType(AiConversationPage));
        await tester.tap(find.byKey(const Key('nav-nutrition')));
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(AiConversationPage, skipOffstage: false)),
          same(aiState),
          reason: '热页必须保留 IndexedStack 中已经监听 pending 的 AI 页面',
        );
      } else {
        expect(
          find.byType(AiConversationPage, skipOffstage: false),
          findsNothing,
          reason: '冷启动分析前不应提前创建 AI 分支',
        );
      }

      await tester.tap(find.byKey(const Key('nutrition-tab-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cta-manage-canteen')));
      await tester.pumpAndSettle();
      await drainIo(tester);
      final row = find.byKey(Key('canteen-dish-$dishId'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('canteen-dish-analyze')), findsOneWidget);
      expect(service.requests, isEmpty);
      return dishId;
    }

    testWidgets('热 AI 页：食堂带照片分析首个且唯一请求必须带图', (tester) async {
      // 回归点：路由若先发布文字再发布照片，热页会先发纯文、把照片留在输入区。
      final photo = await createPhoto(tester);
      final dishId = await openDishActions(
        tester,
        warmAi: true,
        imagePath: photo.path,
      );
      await tester.tap(find.byKey(const Key('canteen-dish-analyze')));
      await drainIo(tester);

      expect(service.requests, hasLength(1), reason: '一次分析只能发出一个请求');
      final turn = service.requests.first.singleWhere(
        (message) => message.role == ConversationRole.user,
      );
      expect(
        turn.kind,
        ConversationMessageKind.image,
        reason: '首个请求必须已经带图，不能先发纯文再补发图片',
      );
      expect(turn.imagePath, isNotEmpty);
      expect(turn.imagePath, photo.path);
      expect(turn.textForRequest, contains('[canteen-dish:$dishId]'));
      expect(find.byKey(const Key('ai-chat-image-0')), findsOneWidget);
      expect(find.byKey(const Key('image-preview-bar')), findsNothing);
      expect(find.byKey(const Key('btn-remove-image')), findsNothing);
      expect(find.text('估算这 1 道菜每 100g 的营养：番茄炒蛋'), findsOneWidget);
      expect(find.textContaining('canteen-dish:'), findsNothing);
      final page = tester.widget<AiConversationPage>(
        find.byType(AiConversationPage),
      );
      expect(page.pendingStarter!.value, isNull);
      expect(page.pendingStarterImage!.value, isNull);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-chat-text-input')))
            .controller!
            .text,
        isEmpty,
      );

      await tester.tap(find.byKey(const Key('nav-nutrition')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('nav-ai-workbench')));
      await drainIo(tester);
      expect(service.requests, hasLength(1), reason: '回到 AI 页不能再次发送或补发');
      expect(find.byKey(const Key('image-preview-bar')), findsNothing);
    });

    testWidgets('冷 AI 页：食堂带照片分析一次发送图片与定位正文', (tester) async {
      final photo = await createPhoto(tester);
      final dishId = await openDishActions(
        tester,
        warmAi: false,
        imagePath: photo.path,
      );
      await tester.tap(find.byKey(const Key('canteen-dish-analyze')));
      await drainIo(tester);

      expect(service.requests, hasLength(1));
      final turn = service.requests.single.singleWhere(
        (message) => message.role == ConversationRole.user,
      );
      expect(turn.kind, ConversationMessageKind.image);
      expect(turn.imagePath, photo.path);
      expect(turn.textForRequest, contains('[canteen-dish:$dishId]'));
      expect(find.byKey(const Key('ai-chat-image-0')), findsOneWidget);
      expect(find.byKey(const Key('image-preview-bar')), findsNothing);
      expect(find.text('估算这 1 道菜每 100g 的营养：番茄炒蛋'), findsOneWidget);
      expect(find.textContaining('canteen-dish:'), findsNothing);
      final page = tester.widget<AiConversationPage>(
        find.byType(AiConversationPage),
      );
      expect(page.pendingStarter!.value, isNull);
      expect(page.pendingStarterImage!.value, isNull);
    });

    for (final warmAi in [true, false]) {
      testWidgets('${warmAi ? '热' : '冷'} AI 页：无照片食堂菜仍只发送一次纯文', (tester) async {
        final dishId = await openDishActions(tester, warmAi: warmAi);
        await tester.tap(find.byKey(const Key('canteen-dish-analyze')));
        await drainIo(tester);

        expect(service.requests, hasLength(1));
        final turn = service.requests.single.singleWhere(
          (message) => message.role == ConversationRole.user,
        );
        expect(turn.kind, ConversationMessageKind.text);
        expect(turn.imagePath, isNull);
        expect(turn.textForRequest, contains('[canteen-dish:$dishId]'));
        expect(turn.textForRequest, isNot(contains('附了一张图片')));
        expect(find.byKey(const Key('ai-chat-image-0')), findsNothing);
        expect(find.byKey(const Key('image-preview-bar')), findsNothing);
        expect(find.text('估算这 1 道菜每 100g 的营养：番茄炒蛋'), findsOneWidget);
        expect(find.textContaining('canteen-dish:'), findsNothing);
      });
    }

    testWidgets('热 AI 页：照片不可读沿用文字降级，但须明示且不谎报附图', (tester) async {
      // 既有行为的边界记录：本次只修通知顺序，不把读图失败改成假图或静默成功。
      final dishId = await openDishActions(
        tester,
        warmAi: true,
        imagePath: '${imageDirectory.path}/missing.png',
      );
      await tester.tap(find.byKey(const Key('canteen-dish-analyze')));
      await drainIo(tester);

      expect(service.requests, hasLength(1));
      final turn = service.requests.single.singleWhere(
        (message) => message.role == ConversationRole.user,
      );
      expect(turn.kind, ConversationMessageKind.text);
      expect(turn.imagePath, isNull);
      expect(turn.textForRequest, contains('[canteen-dish:$dishId]'));
      expect(turn.textForRequest, isNot(contains('附了一张图片')));
      expect(find.text('这道菜的照片读不到了，这次只发文字。'), findsOneWidget);
      expect(find.byKey(const Key('image-preview-bar')), findsNothing);
      expect(find.byKey(const Key('ai-chat-image-0')), findsNothing);
      expect(find.textContaining('canteen-dish:'), findsNothing);
    });
  });
}

final class _HandoffIds implements IdGenerator {
  int _next = 0;

  @override
  String next() => 'handoff-${_next++}';
}

/// 只替换模型边界：让回复保持在途，避免路由接线的建议请求混入分析请求。
final class _PendingConversationService implements AiConversationService {
  final requests = <List<ConversationMessage>>[];
  final _response = StreamController<String>.broadcast();

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) {
    requests.add(List<ConversationMessage>.of(messages));
    return _response.stream;
  }

  Future<void> close() => _response.close();
}

/// 假服务（按真实 [AiConversationService] 接口）：记录发出的用户文本，
/// 并可用 [gate] 挂起流式回复（模拟 isReplying）。
class _FakeConversationService implements AiConversationService {
  _FakeConversationService({required this.onSend, this.gate});

  final void Function(String) onSend;
  final Future<void>? gate;

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    final last = messages.lastWhere(
      (m) => m.role == ConversationRole.user,
      orElse: () => messages.last,
    );
    onSend(last.text);
    if (gate != null) await gate;
    onProgress('收到。');
    yield '收到。';
  }
}
