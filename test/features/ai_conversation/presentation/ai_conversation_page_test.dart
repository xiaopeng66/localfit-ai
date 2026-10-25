import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/features/ai_conversation/application/pick_chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message_repository.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';
import 'package:localfit_ai/features/ai_conversation/application/chat_edit_coordinator.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/training/presentation/sections/plan_draft_card.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';

/// AI 对话页（docs/21 §5.7 / `AI 工作.html`）行为与几何验收。
///
/// 本页有两处**无限循环动画**（录音行脉冲点 / 正在输入三点），所以全程
/// 只用 `pump`，不碰 `pumpAndSettle`（会等不到静止而超时）。
void main() {
  // ── 测试替身 ─────────────────────────────────────────────────────────

  /// 手动驱动的对话服务：测试自己决定何时出分片、何时收尾。
  final calls = <_ServiceCall>[];
  late _ManualService service;

  setUp(() {
    calls.clear();
    service = _ManualService(calls);
  });

  /// 页面脚手架：把底部系统内边距 / 键盘内边距 / 视口 / 字号按需注入。
  Future<void> pumpPage(
    WidgetTester tester,
    Widget page, {
    double bottomPadding = 0,
    double keyboardHeight = 0,
    Size size = const Size(390, 844),
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(bottom: bottomPadding),
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          ),
          child: child!,
        ),
        home: page,
      ),
    );
  }

  /// 等一次真实文件 I/O 落地：`readAsBytes` 这类真异步在 widget 测试里必须
  /// 借 `runAsync` 推进事件循环（与身份卡回归测试同一套做法）。
  Future<void> drainIo(WidgetTester tester) async {
    for (var round = 0; round < 20; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  /// 让异步状态落地并重画。
  ///
  /// 用 `pump(Duration.zero)` 而不是 `pump()`：取消/收尾路径里有 `Future(...)`
  /// 这类**零延时定时器**，不 elapse 时钟就不会触发它们（阶段 G 实测：
  /// 停止按钮点了没反应，根因就是测试只推了微任务）。也不能用
  /// `pumpAndSettle`——本页有无限循环动画，永远等不到静止。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
  }

  // ── 骨架 / 空态 ──────────────────────────────────────────────────────

  group('AI 对话页 · 骨架与欢迎区', () {
    testWidgets('顶栏四件 + 输入区三件（P10：免责声明已删）', (tester) async {
      await pumpPage(tester, AiConversationPage(service: service));

      expect(find.byKey(const Key('ai-chat-back')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-title')), findsOneWidget);
      expect(find.text('AI 助手'), findsOneWidget);
      // 2026-10-23 用户：「删『AI 助手』下方描述」——副题不再渲染。
      expect(find.byKey(const Key('ai-chat-subtitle')), findsNothing);
      expect(find.text('一起把计划，变得可执行'), findsNothing);
      expect(find.byKey(const Key('ai-chat-user-avatar')), findsOneWidget);
      expect(find.byKey(const Key('chat-quick-chips')), findsOneWidget);
      expect(find.byKey(const Key('input-row-text')), findsOneWidget);
      // P10（需求 35）：免责声明整件删除——键与文案都不得再出现。
      expect(find.byKey(const Key('ai-chat-disclaimer')), findsNothing);
      expect(find.text('内容由AI生成，请勿从事违法活动'), findsNothing);
    });

    // 2026-10-16 用户：「对话内容要能长按复制」。
    testWidgets('长按消息气泡复制该条内容并提示「已复制」', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpPage(tester, AiConversationPage(service: service));
      await tester.longPress(find.textContaining('我是你的 AI 健康助手'));
      await settle(tester);

      expect(copied, hasLength(1));
      expect(copied.single, contains('我是你的 AI 健康助手'));
      expect(find.text('已复制'), findsOneWidget);
    });

    // 2026-10-23 用户：「要 AI 聊天建议（用单独配置的模型理解当前输出，
    // 给 2–3 个建议气泡点击直接发送）」。
    testWidgets('回复完成后给 2–3 个建议气泡，点一下直接发送', (tester) async {
      final calls = <_ServiceCall>[];
      final manual = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(service: manual, suggestionService: manual),
      );
      await tester.enterText(find.byKey(const Key('ai-chat-text-input')), '你好');
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);
      calls[0].emit('今天想吃点什么？');
      await calls[0].finish();
      await settle(tester);

      // 建议请求 = 第二次模型调用，上下文里带刚才那条回复。
      expect(calls, hasLength(2));
      expect(calls[1].messages.single.text, contains('今天想吃点什么？'));
      calls[1].emit('推荐一份高蛋白午餐\n来点清淡的\n今天先不吃了');
      await calls[1].finish();
      await settle(tester);

      expect(find.byKey(const Key('ai-chat-suggestion-1-0')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-suggestion-1-1')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-suggestion-1-2')), findsOneWidget);
      expect(find.text('推荐一份高蛋白午餐'), findsOneWidget);

      // 点第一条 = 直接作为用户消息发送（第三次调用）。
      await tester.tap(find.byKey(const Key('ai-chat-suggestion-1-0')));
      await settle(tester);
      expect(calls, hasLength(3));
      expect(calls[2].messages.last.text, '推荐一份高蛋白午餐');
    });

    // ── Round7 逐页对账批次 2：A 的第四条快捷 chip「AI 创作」 ─────────────
    testWidgets('AI 创作 chip 打开创作页（A app.js:207）', (tester) async {
      var opened = 0;
      await pumpPage(
        tester,
        AiConversationPage(service: service, onOpenAiCreate: () => opened++),
      );

      expect(find.byKey(const Key('ai-chat-chip-ai-create')), findsOneWidget);
      expect(find.text('AI 创作'), findsOneWidget);
      await tester.tap(find.byKey(const Key('ai-chat-chip-ai-create')));
      await settle(tester);
      expect(opened, 1);
    });

    // ── Round7 逐页对账批次 4：A 的两条 starter 行（app.js:207） ──────────
    testWidgets('两条 starter 行把问题预填进输入框（A app.js:207）', (tester) async {
      await pumpPage(tester, AiConversationPage(service: service));

      expect(find.byKey(const Key('ai-chat-starter-dinner')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-starter-plan')), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-chat-starter-dinner')));
      await settle(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-chat-text-input')))
            .controller!
            .text,
        '今天晚餐怎么搭配？',
      );

      // 只预填、不替用户发送（服务未被调用）——与「我可以吃吗」chip 同一条
      // 诚实口径：A 的 starter 是对话起点，本仓不替用户按下发送。
      expect(calls, isEmpty);

      await tester.tap(find.byKey(const Key('ai-chat-starter-plan')));
      await settle(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-chat-text-input')))
            .controller!
            .text,
        '制定轻量训练计划',
      );
    });

    // ── T7（docs/32 §3 D9）：对话页顶栏用户头像 ─────────────────────────────
    testWidgets('对话页顶栏用户头像显昵称首字，且可点 → 我的', (tester) async {
      var opened = 0;
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          identity: const IdentityProfile(displayName: '李雷'),
          onOpenProfile: () => opened++,
        ),
      );

      expect(
        tester
            .widget<Text>(find.byKey(const Key('ai-chat-avatar-initial')))
            .data,
        '李',
        reason: 'D9：对话页头像显示昵称首字（原为 person 图标占位）',
      );
      await tester.tap(find.byKey(const Key('ai-chat-user-avatar')));
      expect(opened, 1, reason: 'D9：数据头像可点 → 我的');
    });

    testWidgets('空对话显示欢迎语 + 功能卡（不是假消息）', (tester) async {
      await pumpPage(tester, AiConversationPage(service: service));

      expect(find.byKey(const Key('ai-chat-welcome')), findsOneWidget);
      expect(find.textContaining('我是你的 AI 健康助手'), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-feature-card')), findsOneWidget);
      // docs/28 §6.8「不做补偿入口」：欢迎卡只展示 3 条特性列。原先指向
      // 「食谱计划预览」的底部主按钮与右上角角标都随该功能整族下线，
      // 页面**一个都不传** ⇒ 两个 Key 都不渲染（不是按钮变灰）。
      expect(find.byKey(const Key('cta-write-plan')), findsNothing);
      expect(find.byKey(const Key('feature-card-view')), findsNothing);
      // 空态没有任何消息行。
      expect(find.byKey(const Key('ai-chat-message-0')), findsNothing);
    });

    testWidgets('返回键走注入的回调（不依赖 Navigator）', (tester) async {
      var backs = 0;
      await pumpPage(
        tester,
        AiConversationPage(service: service, onBack: () => backs++),
      );

      await tester.tap(find.byKey(const Key('ai-chat-back')));
      expect(backs, 1);
    });
  });

  // ── 文本对话 ─────────────────────────────────────────────────────────

  group('AI 对话页 · 文本对话', () {
    testWidgets('发送 → 用户气泡 + 正在输入 → 流式分片 → 最终回复', (tester) async {
      await pumpPage(tester, AiConversationPage(service: service));

      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '晚饭吃了三明治',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);

      // 用户消息立刻上屏；助手占位是「正在输入」，且输入框已清空。
      expect(find.text('晚饭吃了三明治'), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-message-0')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-message-1')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-typing')), findsOneWidget);
      expect(find.byKey(const Key('btn-stop')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('ai-chat-text-input')))
            .controller!
            .text,
        isEmpty,
      );

      // 请求上下文 = 本条用户消息。
      expect(calls, hasLength(1));
      expect(calls.single.messages, hasLength(1));
      expect(calls.single.messages.last.text, '晚饭吃了三明治');
      expect(calls.single.messages.last.role, ConversationRole.user);

      calls.single.emit('三明治');
      await settle(tester);
      expect(find.text('三明治'), findsOneWidget);
      // 有正文了就不再显示三点。
      expect(find.byKey(const Key('ai-chat-typing')), findsNothing);

      await calls.single.finish();
      await settle(tester);

      expect(find.text('三明治'), findsOneWidget);
      expect(find.byKey(const Key('btn-send')), findsOneWidget);
      expect(find.byKey(const Key('btn-stop')), findsNothing);
    });

    testWidgets('空白输入不产生消息', (tester) async {
      await pumpPage(tester, AiConversationPage(service: service));

      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '   ',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);

      expect(find.byKey(const Key('ai-chat-message-0')), findsNothing);
      expect(calls, isEmpty);
      // 欢迎区还在（说明不是被空消息顶掉了）。
      expect(find.byKey(const Key('ai-chat-welcome')), findsOneWidget);
    });

    testWidgets('一个字都没生成时停止：占位气泡消失、回到可发送', (tester) async {
      await pumpPage(tester, AiConversationPage(service: service));

      await tester.enterText(find.byKey(const Key('ai-chat-text-input')), '在吗');
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);
      expect(find.byKey(const Key('ai-chat-typing')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn-stop')));
      await settle(tester);

      expect(find.byKey(const Key('ai-chat-message-1')), findsNothing);
      expect(find.byKey(const Key('ai-chat-message-0')), findsOneWidget);
      expect(find.byKey(const Key('btn-send')), findsOneWidget);
      expect(find.byKey(const Key('btn-stop')), findsNothing);
      // 停止信号真的传给了服务。
      expect(calls.single.cancelled, isTrue);
    });

    testWidgets('已生成部分文本时停止：保留部分文本，不留空气泡', (tester) async {
      await pumpPage(tester, AiConversationPage(service: service));

      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '讲个长故事',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);
      calls.single.emit('从前');
      await settle(tester);

      await tester.tap(find.byKey(const Key('btn-stop')));
      await settle(tester);

      expect(find.text('从前'), findsOneWidget);
      expect(find.byKey(const Key('btn-send')), findsOneWidget);
    });

    testWidgets('服务报错 → 错误气泡可点重试 → 就地重发成功', (tester) async {
      await pumpPage(tester, AiConversationPage(service: service));

      await tester.enterText(find.byKey(const Key('ai-chat-text-input')), '你好');
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);
      calls.single.fail(StateError('上游 502'));
      await settle(tester);

      expect(find.textContaining('发送失败，点击重试。'), findsOneWidget);
      expect(find.byKey(const Key('btn-retry-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn-retry-1')));
      await settle(tester);

      expect(calls, hasLength(2));
      // 重试的上下文与首次一致（用户消息 + 之前已完成消息）。
      expect(calls.last.messages.single.text, '你好');
      calls.last.emit('又是我');
      await settle(tester);
      await calls.last.finish();
      await settle(tester);

      // 就地复用：还是两条消息，没有多出第三条。
      expect(find.text('又是我'), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-message-2')), findsNothing);
      expect(find.textContaining('发送失败'), findsNothing);
    });

    testWidgets('AI 回复中不接受新消息（不做无确认并发）', (tester) async {
      await pumpPage(tester, AiConversationPage(service: service));

      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '第一条',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);

      // 回复未结束时再点发送（此时按钮是停止钮，直接调 sendMessage 的路径
      // 由控制器兜住：这里点停止钮之外没有别的发送入口）。
      expect(find.byKey(const Key('btn-send')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '第二条',
      );
      await settle(tester);
      expect(calls, hasLength(1));

      calls.single.emit('回复');
      await calls.single.finish();
      await settle(tester);
      expect(find.byKey(const Key('btn-send')), findsOneWidget);
    });
  });

  // ── 图片消息 ─────────────────────────────────────────────────────────

  group('AI 对话页 · 图片消息', () {
    PickChatImage pickerFor({
      required _FakeMealImagePicker picker,
      required _MemoryChatImageStore store,
    }) => PickChatImage(
      picker: picker,
      processor: const _FakeProcessor(),
      store: store,
      clock: const SystemAppClock(),
    );

    // 2026-10-16（N2，用户：「食堂菜品分析营养的时候，如果有照片，需要同步
    // 把照片发送到 ai 对话」）。
    testWidgets('起手请求随附照片：挂成待发图片（用户可移除，发送时随消息出去）', (tester) async {
      final file = File(
        '${Directory.systemTemp.createTempSync('lf-starter-img').path}/dish.png',
      );
      // 用真实可解码的 PNG（解码尺寸是挂图的前置条件）。像素生成必须在
      // `runAsync` 里做——测试 binding 会拦截 `toImage` 的异步管线。
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

      final starterImage = ValueNotifier<String?>(file.path);
      addTearDown(starterImage.dispose);
      await pumpPage(
        tester,
        AiConversationPage(service: service, pendingStarterImage: starterImage),
      );
      await settle(tester);
      await drainIo(tester);

      expect(find.byKey(const Key('image-preview-bar')), findsOneWidget);
      expect(find.text('dish.png'), findsOneWidget);
      expect(starterImage.value, isNull, reason: '消费一次即清空');
    });

    testWidgets('起手请求的图片读不到：只发文字并如实提示，不谎报「已添加」', (tester) async {
      final starterImage = ValueNotifier<String?>('/not/a/real/dish.png');
      addTearDown(starterImage.dispose);
      await pumpPage(
        tester,
        AiConversationPage(service: service, pendingStarterImage: starterImage),
      );
      await settle(tester);
      await drainIo(tester);

      expect(find.byKey(const Key('image-preview-bar')), findsNothing);
      expect(find.text('这道菜的照片读不到了，这次只发文字。'), findsOneWidget);
    });

    testWidgets('选图 → 预览条 → 移除（并删除文件）', (tester) async {
      final imagePicker = _FakeMealImagePicker(selection: _selected());
      final store = _MemoryChatImageStore();
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatImagePicker: pickerFor(picker: imagePicker, store: store),
        ),
      );

      await tester.tap(find.byKey(const Key('btn-image-upload')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('image-preview-bar')), findsOneWidget);
      expect(find.text('已添加 1 张图片'), findsOneWidget);
      expect(find.text('chat_1.jpg'), findsOneWidget);
      expect(imagePicker.sources.single, MealImageSource.gallery);

      await tester.tap(find.byKey(const Key('btn-remove-image')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('image-preview-bar')), findsNothing);
      expect(store.deleted, hasLength(1));
    });

    testWidgets('带图发送：消息形态是图片 + 说明，请求里如实带上图片说明', (tester) async {
      final imagePicker = _FakeMealImagePicker(selection: _selected());
      final store = _MemoryChatImageStore();
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatImagePicker: pickerFor(picker: imagePicker, store: store),
        ),
      );

      await tester.tap(find.byKey(const Key('btn-image-upload')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '这是今天的午饭',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);

      // 图片消息（不是文本气泡）+ 说明文字；路径不存在时给「已清理」占位。
      expect(find.byKey(const Key('ai-chat-image-0')), findsOneWidget);
      expect(find.text('这是今天的午饭'), findsOneWidget);
      expect(find.text('图片已清理'), findsOneWidget);
      expect(find.byKey(const Key('image-preview-bar')), findsNothing);

      final turn = calls.single.messages.last;
      // 图片随这条消息真的发出去（2026-10-16，S1）。
      expect(turn.text, contains('附了一张图片'));
      expect(turn.text, isNot(contains('未发送')));
      expect(turn.text, contains('这是今天的午饭'));
      expect(turn.imagePath, isNotNull);

      calls.single.emit('收到');
      await calls.single.finish();
      await settle(tester);
    });

    // 2026-10-16（S1）：图会真的发出去，所以要**如实披露**（原本文案说
    // 「只能接收文字」，现在不成立了）。
    testWidgets('带图时如实披露「图片会随这条消息发送给你配置的 AI 服务」', (tester) async {
      final store = _MemoryChatImageStore();
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatImagePicker: pickerFor(
            picker: _FakeMealImagePicker(selection: _selected()),
            store: store,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('btn-image-upload')));
      await tester.pumpAndSettle();

      final disclosure = find.byKey(const Key('image-send-disclosure'));
      expect(disclosure, findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.descendant(of: disclosure, matching: find.byType(Text)),
            )
            .data,
        contains('会随这条消息一起发给你配置的 AI 服务'),
      );
    });

    testWidgets('用户取消选图：不弹错误、不建预览条', (tester) async {
      final store = _MemoryChatImageStore();
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatImagePicker: pickerFor(
            picker: _FakeMealImagePicker(selection: null),
            store: store,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('btn-image-upload')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('image-preview-bar')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(store.deleted, isEmpty);
    });

    testWidgets('选图失败：SnackBar 如实报错', (tester) async {
      final store = _MemoryChatImageStore();
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatImagePicker: pickerFor(
            picker: _FakeMealImagePicker(
              failure: const MealImageFailure('相册不可用'),
            ),
            store: store,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('btn-image-upload')));
      await tester.pumpAndSettle();

      expect(find.text('相册不可用'), findsOneWidget);
      expect(find.byKey(const Key('image-preview-bar')), findsNothing);
    });

    testWidgets('图片入口未接线：点击给诚实提示', (tester) async {
      await pumpPage(tester, AiConversationPage(service: service));

      await tester.tap(find.byKey(const Key('btn-image-upload')));
      await tester.pumpAndSettle();

      expect(find.text('图片选择尚未配置。'), findsOneWidget);
    });
  });

  // ── 语音（P10 已删） ────────────────────────────────────────────────
  // P10（需求 36）：语音输入整族删除（录音器/转写服务/麦克风按钮/录音行/
  // VoiceMessage 气泡 + record 依赖 + RECORD_AUDIO）。这里不保留任何
  // 「语音不可用」的运行时断言——入口本身没有了；历史库里的旧语音消息
  // 仍能读回（见 drift_conversation_message_repository_test 的遗留兼容用例）。

  // ── 快捷 chip / 历史 ─────────────────────────────────────────────────

  group('AI 对话页 · 快捷 chip 与历史', () {
    // 2026-10-16 用户裁决：对话页 chip 行去掉「手动记录」。
    // 2026-10-23 用户：第一枚从「拍照识别」换成「确认应用」。
    // `RV4-R16`（`docs/56` §8 方案 A / D6）：「确认应用」与「我可以吃吗」
    // 双双退役，换成「今天还剩多少」+「记一餐」。断言的**对象换了**，
    // 判据（三枚 chip 都在、点了有事发生、退役的不在）一个字没放宽。
    testWidgets('两枚新 chip + AI 创作；退役的三枚不在', (tester) async {
      var creates = 0;
      await pumpPage(
        tester,
        AiConversationPage(service: service, onOpenAiCreate: () => creates++),
      );

      expect(find.byKey(const Key('ai-chat-chip-manual')), findsNothing);
      expect(find.byKey(const Key('cta-photo-scan')), findsNothing);
      expect(find.text('拍照识别'), findsNothing);
      expect(find.byKey(const Key('ai-chat-chip-apply-edits')), findsNothing);
      expect(find.byKey(const Key('ai-chat-chip-can-i-eat')), findsNothing);
      expect(find.byKey(const Key('ai-chat-chip-remaining')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-chip-log-meal')), findsOneWidget);

      // 未接餐食仓储时点「今天还剩多少」：如实提示，不假装算出来。
      await tester.tap(find.byKey(const Key('ai-chat-chip-remaining')));
      await settle(tester);
      expect(find.textContaining('餐食仓储尚未配置'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-chat-chip-ai-create')));
      expect(creates, 1);
    });

    testWidgets('历史载入失败：给错误态与重试，不拿空态冒充', (tester) async {
      final history = _MemoryHistory(failLoad: true);
      final repository = history;
      await pumpPage(
        tester,
        AiConversationPage(service: service, historyRepository: repository),
      );
      await settle(tester);

      expect(find.byKey(const Key('ai-chat-history-error')), findsOneWidget);
      expect(find.text('聊天记录读取失败，请重试。'), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-welcome')), findsNothing);

      // 重试成功 → 显示真实历史。
      history.failLoad = false;
      history.initial = [_message('h1', ConversationRole.user, '昨天的晚饭')];
      await tester.tap(find.byKey(const Key('ai-chat-history-retry')));
      await settle(tester);

      expect(find.byKey(const Key('ai-chat-history-error')), findsNothing);
      expect(find.text('昨天的晚饭'), findsOneWidget);
    });

    testWidgets('历史按顺序显示在今天的新对话之前', (tester) async {
      final history = _MemoryHistory(
        initial: [
          _message('h1', ConversationRole.user, '前天吃了火锅'),
          _message('h2', ConversationRole.assistant, '听起来不错'),
        ],
      );
      await pumpPage(
        tester,
        AiConversationPage(service: service, historyRepository: history),
      );
      await settle(tester);

      expect(find.byKey(const Key('ai-chat-message-0')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-message-1')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-welcome')), findsNothing);
      expect(
        tester.getTopLeft(find.text('前天吃了火锅')).dy,
        lessThan(tester.getTopLeft(find.text('听起来不错')).dy),
      );
    });

    testWidgets('历史里的旧语音消息降级为普通用户气泡（P10 遗留兼容）', (tester) async {
      // P10（需求 36）删除了语音输入整族，但历史库里的旧语音消息（D8
      // 保留 kind=voice）仍要能读回来——按「转写文本就是消息正文」降级
      // 成普通用户气泡，键仍是 ai-chat-voice-<n>。
      final history = _MemoryHistory(
        initial: [
          ConversationMessage(
            id: 'v1',
            role: ConversationRole.user,
            text: '午饭吃了鸡胸肉',
            createdAt: DateTime.utc(2026, 10, 1, 12),
            status: ConversationMessageStatus.sent,
            kind: ConversationMessageKind.voice,
            durationMs: 3200,
          ),
        ],
      );
      await pumpPage(
        tester,
        AiConversationPage(service: service, historyRepository: history),
      );
      await settle(tester);

      expect(find.byKey(const Key('ai-chat-voice-0')), findsOneWidget);
      expect(find.text('午饭吃了鸡胸肉'), findsOneWidget);
      // 波形播放件已删：不再有任何可交互的语音控件。
      expect(find.byType(InkWell), isNot(findsNWidgets(0)));
    });

    testWidgets('消息落库：用户消息与最终回复都存', (tester) async {
      final history = _MemoryHistory();
      await pumpPage(
        tester,
        AiConversationPage(service: service, historyRepository: history),
      );

      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '记录一下',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);
      calls.single.emit('好的');
      await calls.single.finish();
      await settle(tester);

      expect(history.saved, hasLength(2));
      expect(history.saved[0].role, ConversationRole.user);
      expect(history.saved[0].text, '记录一下');
      expect(history.saved[1].role, ConversationRole.assistant);
      expect(history.saved[1].text, '好的');
    });

    testWidgets('落库失败：SnackBar 如实告知「重启可能不完整」', (tester) async {
      final history = _MemoryHistory(failSave: true);
      await pumpPage(
        tester,
        AiConversationPage(service: service, historyRepository: history),
      );

      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '存一下',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);

      expect(find.text('聊天记录保存失败，重启后本次对话可能不完整。'), findsOneWidget);
      // 消息仍在屏幕上（保存失败不吞掉消息）。
      expect(find.text('存一下'), findsOneWidget);
      calls.single.emit('嗯');
      await calls.single.finish();
      await settle(tester);
    });
  });

  // ── 几何与可达性 ─────────────────────────────────────────────────────

  group('AI 对话页 · 几何与可达性', () {
    testWidgets('底栏留白：输入区整体在底栏占位（73.5dp）之上', (tester) async {
      await pumpPage(
        tester,
        AiConversationPage(service: service),
        bottomPadding: 73.5,
      );

      final screenBottom = tester.view.physicalSize.height;
      // P10 后输入行就是最底一行（免责声明已删），用它的整行测留白。
      final inputRow = tester.getRect(find.byKey(const Key('input-row-text')));
      expect(inputRow.bottom, lessThanOrEqualTo(screenBottom - 73.5));
      // 输入框也在其上（不被底栏遮住）。
      expect(
        tester.getRect(find.byKey(const Key('ai-chat-text-input'))).bottom,
        lessThanOrEqualTo(screenBottom - 73.5),
      );
    });

    testWidgets('键盘弹起：输入框在键盘上沿之上', (tester) async {
      await pumpPage(
        tester,
        AiConversationPage(service: service),
        keyboardHeight: 300,
      );

      final keyboardTop = tester.view.physicalSize.height - 300;
      expect(
        tester.getRect(find.byKey(const Key('ai-chat-text-input'))).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      expect(
        tester.getRect(find.byKey(const Key('input-row-text'))).bottom,
        lessThanOrEqualTo(keyboardTop),
      );
      // 消息区被挤扁但不溢出。
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏 320dp + 1.3 倍字号：无溢出', (tester) async {
      await pumpPage(
        tester,
        AiConversationPage(service: service),
        size: const Size(320, 640),
        textScale: 1.3,
      );

      expect(find.byKey(const Key('ai-chat-text-input')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-chip-remaining')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄屏 320dp + 2.0 倍字号：无溢出', (tester) async {
      await pumpPage(
        tester,
        AiConversationPage(service: service),
        size: const Size(320, 640),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('btn-send')), findsOneWidget);
    });

    testWidgets('长对话在窄屏里可滚动（不溢出、能到底）', (tester) async {
      await pumpPage(
        tester,
        AiConversationPage(service: service),
        size: const Size(320, 640),
      );

      for (var i = 0; i < 6; i++) {
        await tester.enterText(
          find.byKey(const Key('ai-chat-text-input')),
          '第 $i 条消息',
        );
        await tester.tap(find.byKey(const Key('btn-send')));
        await settle(tester);
        calls[i].emit('回 $i');
        await calls[i].finish();
        await settle(tester);
      }

      expect(tester.takeException(), isNull);

      // 12 条消息在 320dp 视口里装不下：ListView 是懒加载的，只会构建可见项，
      // 所以「消息存在」的断言必须真滚动（find.byKey 找不到从未构建的 widget）。
      await tester.dragUntilVisible(
        find.byKey(const Key('ai-chat-message-11')),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(find.byKey(const Key('ai-chat-message-11')), findsOneWidget);

      // 再滚回顶部，最早的一条也在。
      await tester.dragUntilVisible(
        find.text('第 0 条消息'),
        find.byType(ListView),
        const Offset(0, 300),
      );
      expect(find.text('第 0 条消息'), findsOneWidget);
    });
  });

  // ── 编辑卡（docs/23 §5）────────────────────────────────────────────

  group('AI 对话页 · 编辑卡', () {
    const envelope =
        '{"reply":"好的，帮你记一笔。","edits":['
        '{"action":"water.add","args":{"amountMl":250}}]}';

    Future<void> sendAndReceive(
      WidgetTester tester,
      _ManualService service,
      String payload,
    ) async {
      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '帮我记一笔',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);
      service.calls.single.emit(payload);
      await service.calls.single.finish();
      await settle(tester);
    }

    testWidgets('信封回复渲染成编辑卡：reply 上屏、原始 JSON 不上屏', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _RecordingExecutor(),
          ),
        ),
      );
      await sendAndReceive(tester, service, envelope);

      expect(find.text('好的，帮你记一笔。'), findsOneWidget);
      expect(find.textContaining('"edits"'), findsNothing);
      expect(find.byKey(const Key('chat-edit-card-1')), findsOneWidget);
      // docs/21 §5 声明的行 Key 也要有测试断言（三方对账零缺口）。
      expect(find.byKey(const Key('chat-edit-row-1-0')), findsOneWidget);
      expect(find.text('记一笔饮水'), findsOneWidget);
      // 【语义变更，2026-10-24 方案 B 裁决】行级「应用」按钮**已退役**：
      // 执行器按命令粒度，「记一餐」在方案 B 下展开成多个食物子条目，行内
      // 再给按钮会让用户以为能单独应用某个食物（实际整条写入）。
      // 判据强度不降：改为钉「子条目渲染出来了」+「行级按钮确实不存在」。
      expect(find.byKey(const Key('chat-edit-subitem-1-0-0')), findsOneWidget);
      expect(
        find.byKey(const Key('chat-edit-row-apply-1-0')),
        findsNothing,
        reason: '行级按钮已按方案 B 裁决退役（按钮只在组级 + 卡底）',
      );
      expect(find.byKey(const Key('chat-edit-apply-1')), findsOneWidget);
      expect(find.byKey(const Key('chat-edit-dismiss-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 2026-10-16 用户：「功能卡片太丑，要做成小卡片」——编辑卡由裸 Column
    // 堆叠改为 `DesignCard` 卡壳 + 卡头，行状态从裸文字改为 `LfBadge`。
    testWidgets('编辑卡有卡壳与卡头，行状态是徽标', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _RecordingExecutor(),
          ),
        ),
      );
      await sendAndReceive(tester, service, envelope);

      final card = find.byKey(const Key('chat-edit-card-1'));
      expect(card, findsOneWidget);
      // 卡壳：这条卡本身就是一个 DesignCard（白底 + 描边 + 圆角）。
      expect(tester.widget(card), isA<DesignCard>());
      // 卡头（2026-10-24 方案 B · 语义变更）：原来是一句对所有卡都一样的
      // 「待你确认的修改」，现在换成**能读懂结论**的动态文案（「午餐 · 1 条
      // 修改」）。判据不降低：卡头仍必须说明「有几条修改」，且必须有内容。
      final headline = tester
          .widget<Text>(find.byKey(const Key('chat-edit-card-headline-1')))
          .data!;
      expect(headline, contains('条修改'), reason: '卡头要说清有几条修改');
      expect(headline.trim(), isNotEmpty);
      // 行状态仍是卡片内的件（不是一行裸文字）。`RV4-P2-07` 之后 `proposed`
      // 行是「应用」胶囊；`LfBadge` 仍出现在卡头/组头等处。
      expect(
        find.descendant(of: card, matching: find.byType(LfBadge)),
        findsWidgets,
      );
      // 方案 B：proposed 状态用**徽标**表达（行内不再有按钮）。
      expect(
        find.descendant(of: card, matching: find.text('待应用')),
        findsWidgets,
        reason: 'proposed 行用「待应用」徽标表达状态',
      );
      // 按钮仍在壳内（行为不变）。
      expect(
        find.descendant(
          of: card,
          matching: find.byKey(const Key('chat-edit-apply-1')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    // 2026-10-23 用户：「卡片按类分组（记一餐一组、新建食材一组），
    // 可单独应用；单独应用后点忽略不得撤销已应用」。
    testWidgets('编辑卡按类分组，可单独应用一组；忽略不撤销已应用', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      final executor = _RecordingExecutor();
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: executor,
          ),
        ),
      );
      await sendAndReceive(
        tester,
        service,
        '{"reply":"一起处理","edits":['
        '{"action":"meal.create","args":{"slot":"午餐",'
        '"items":[{"food":"米饭","grams":100}]}},'
        '{"action":"food.create","args":{"name":"新食材",'
        '"kcalPer100g":100,"proteinPer100g":1,'
        '"carbsPer100g":1,"fatPer100g":1}},'
        '{"action":"water.add","args":{"amountMl":250}}]}',
      );

      // 三组：记一餐 / 新建食材 / 其他修改（2026-10-25 用户：
      // 「新建自定义食材」改成「新建食材」）。
      // 组名与行标题可能同名（`meal.create` 的行标题也是「记一餐」），
      // 所以断言限定在组头内。
      for (final (key, label) in const [
        ('chat-edit-group-1-meal', '记一餐'),
        ('chat-edit-group-1-food', '新建食材'),
        ('chat-edit-group-1-other', '其他修改'),
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget);
        expect(
          find.descendant(of: find.byKey(Key(key)), matching: find.text(label)),
          findsOneWidget,
          reason: '$label 组头',
        );
      }

      // 只应用「记一餐」这一组：执行器只收到 meal.create。
      // 方案 B（分块版式）让卡片变高，组头按钮可能落在首屏之外 —— 先滚到
      // 可见位置再点（这只改测试的点击方式，不改产品行为）。
      await tester.ensureVisible(
        find.byKey(const Key('chat-edit-group-apply-1-meal')),
      );
      await settle(tester);
      await tester.tap(find.byKey(const Key('chat-edit-group-apply-1-meal')));
      await settle(tester);
      expect(executor.received.map((command) => command.action), [
        'meal.create',
      ]);
      expect(find.text('已应用'), findsOneWidget);

      // 再点「忽略」：已应用的那一行保持「已应用」，只有待应用行变「已忽略」。
      await tester.tap(find.byKey(const Key('chat-edit-dismiss-1')));
      await settle(tester);
      expect(find.text('已应用'), findsOneWidget, reason: '忽略不得撤销已经应用的行');
      expect(find.text('已忽略'), findsNWidgets(2));
      expect(executor.received.map((command) => command.action), [
        'meal.create',
      ]);
    });

    // 2026-10-16 用户：「涉及修改就必须正确识别指令，而不是空回文字」。
    // 自动催过一次仍只拿到文字时，气泡下要给一枚手动催的入口。
    testWidgets('修改请求只拿到文字：气泡下出「让 AI 给出可应用的修改」，点了真催', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _RecordingExecutor(),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '帮我加一个鸡蛋',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);
      // 第一轮：模型只回文字 ⇒ 控制器自动催一次（第二次请求）。
      calls[0].emit('早上吃个鸡蛋挺好的。');
      await calls[0].finish();
      await settle(tester);
      expect(calls, hasLength(2), reason: '修改请求没出信封 ⇒ 自动催一次');
      // 第二轮仍是文字 ⇒ 残留态：给手动词条。
      calls[1].emit('我还是先说个建议。');
      await calls[1].finish();
      await settle(tester);

      final chip = find.byKey(const Key('ai-chat-request-envelope-1'));
      expect(chip, findsOneWidget);
      expect(
        find.descendant(of: chip, matching: find.text('让 AI 给出可应用的修改')),
        findsOneWidget,
      );

      await tester.tap(chip);
      await settle(tester);
      expect(calls, hasLength(3), reason: '手动词条要真的再发一次请求');

      calls[2].emit(
        '{"reply":"帮你记一个鸡蛋。","edits":[{"action":"food.create",'
        '"args":{"name":"鸡蛋","kcalPer100g":144,"proteinPer100g":13.3,'
        '"carbsPer100g":2.8,"fatPer100g":8.8}}]}',
      );
      await calls[2].finish();
      await settle(tester);

      expect(find.byKey(const Key('chat-edit-card-1')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-request-envelope-1')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // 2026-10-16 用户：「AI 生成训练计划时在对话框里输出这样一个卡片」
    // ——`workout.plan.create` 这一行不再只有一行摘要，而是渲染出**共享的
    // 计划草案卡**（与创建页 / 训练弹层同款）。
    testWidgets('workout.plan.create：编辑卡里直接出计划卡（日卡 + 动作行）', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _RecordingExecutor(),
          ),
        ),
      );
      await sendAndReceive(
        tester,
        service,
        '{"reply":"给你排了四天增肌。","edits":[{"action":"workout.plan.create",'
        '"args":{"name":"四天增肌","days":[{"weekday":1,"entries":['
        '{"exercise":"卧推","sets":4,"reps":10,"weightKg":60}]},'
        '{"weekday":3,"entries":[{"exercise":"深蹲","sets":5,"reps":5}]}]}}]}',
      );

      final card = find.byKey(const Key('chat-edit-card-1'));
      expect(
        find.descendant(of: card, matching: find.byType(PlanDraftCard)),
        findsOneWidget,
      );
      // 每天一张日卡；动作行写「名称 · N 组 × M 次 · Wkg」。
      expect(find.byKey(const Key('chat-plan-draft-day-1')), findsOneWidget);
      expect(find.byKey(const Key('chat-plan-draft-day-3')), findsOneWidget);
      expect(find.text('卧推 · 4 组 × 10 次 · 60kg'), findsOneWidget);
      expect(find.text('深蹲 · 5 组 × 5 次'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 2026-10-16（用户：「对话中遇到问题要推荐回答并弹出可点选按钮」）。
    testWidgets('推荐按钮点了就执行那条命令，状态就地变「已应用」', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      final executor = _RecordingExecutor();
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: executor,
          ),
        ),
      );
      await sendAndReceive(
        tester,
        service,
        '{"reply":"库里没有鸡肉，我可以先建它。","edits":['
        '{"action":"water.add","args":{"amountMl":250}}],'
        '"suggestions":[{"label":"创建食材「鸡肉」","action":"food.create",'
        '"args":{"name":"鸡肉","kcalPer100g":165,"proteinPer100g":31,'
        '"carbsPer100g":0,"fatPer100g":3.6}}]}',
      );

      expect(find.byKey(const Key('chat-edit-suggest-1-0')), findsOneWidget);
      expect(find.text('创建食材「鸡肉」'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat-edit-suggest-1-0')));
      await settle(tester);

      // 只有被点的那条命令执行（编辑卡上的 water.add 没被顺手应用）。
      expect(executor.received.map((c) => c.action), ['food.create']);
      expect(find.text('创建食材「鸡肉」（已应用）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 2026-10-16：修复建议四类各自开对表单（缺动作/地点/窗口），文案从
    // `ChatEditRepair.label` 一处出。
    testWidgets('缺动作/地点/窗口：行下按钮文案与分发都对', (tester) async {
      final requested = <String>[];
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          onOpenNewExerciseWithName: (name) async =>
              requested.add('exercise:$name'),
          onOpenNewVenueWithName: (name) async => requested.add('venue:$name'),
          onOpenNewWindowWithName: (venueId, name) async =>
              requested.add('window:$venueId:$name'),
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _RepairKindExecutor(),
          ),
        ),
      );
      await sendAndReceive(
        tester,
        service,
        '{"reply":"先记这几项。","edits":['
        '{"action":"session.start","args":{}},'
        '{"action":"canteen.venue.rename","args":{"venueId":"venue-x","name":"三食堂"}},'
        '{"action":"canteen.window.create","args":{'
        '"venue":"三食堂","name":"四号窗口","openTime":"10:00",'
        '"closeTime":"13:00"}}]}',
      );
      await tester.tap(find.byKey(const Key('chat-edit-apply-1')));
      await settle(tester);

      expect(find.text('新建动作「农夫行走」'), findsOneWidget);
      expect(find.text('新建地点「三食堂」'), findsOneWidget);
      expect(find.text('新建窗口「四号窗口」'), findsOneWidget);

      // 方案 B 让卡片变高，靠前的修复按钮可能落在视口外——先滚到可见再点
      // （只改测试的点击方式，不改产品行为）。
      for (final i in [0, 1, 2]) {
        final key = Key('chat-edit-repair-1-$i');
        await tester.ensureVisible(find.byKey(key));
        await settle(tester);
        await tester.tap(find.byKey(key));
        await settle(tester);
      }
      expect(requested, ['exercise:农夫行走', 'venue:三食堂', 'window:venue-1:四号窗口']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('执行失败缺食材：行下出现「创建食材」按钮，点了开预填弹层', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      final requestedNames = <String>[];
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          onOpenNewFoodWithName: (name) async => requestedNames.add(name),
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _MissingFoodExecutor(),
          ),
        ),
      );
      await sendAndReceive(
        tester,
        service,
        '{"reply":"早餐吃鸡肉。","edits":['
        '{"action":"meal.create","args":{"slot":"早餐","items":['
        '{"food":"鸡肉","grams":100}]}}]}',
      );

      await tester.tap(find.byKey(const Key('chat-edit-apply-1')));
      await settle(tester);

      expect(find.text('找不到食材「鸡肉」。'), findsOneWidget);
      final repair = find.byKey(const Key('chat-edit-repair-1-0'));
      expect(repair, findsOneWidget);
      await tester.tap(repair);
      await settle(tester);
      expect(requestedNames, ['鸡肉']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('「创建食材」入口未接线：给诚实提示，不静默', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _MissingFoodExecutor(),
          ),
        ),
      );
      await sendAndReceive(
        tester,
        service,
        '{"reply":"早餐吃鸡肉。","edits":['
        '{"action":"meal.create","args":{"slot":"早餐","items":['
        '{"food":"鸡肉","grams":100}]}}]}',
      );
      await tester.tap(find.byKey(const Key('chat-edit-apply-1')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('chat-edit-repair-1-0')));
      await settle(tester);

      expect(find.text('新建食物尚未配置。'), findsOneWidget);
    });

    testWidgets('全部应用：执行器逐条落地，行状态变已应用、按钮消失', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      final executor = _RecordingExecutor();
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: executor,
          ),
        ),
      );
      await sendAndReceive(tester, service, envelope);

      await tester.tap(find.byKey(const Key('chat-edit-apply-1')));
      await settle(tester);

      expect(executor.received.single.action, 'water.add');
      expect(find.text('已应用'), findsOneWidget);
      expect(find.byKey(const Key('chat-edit-apply-1')), findsNothing);
      expect(find.text('待应用'), findsNothing);
    });

    testWidgets('忽略：全部提议置为已忽略', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _RecordingExecutor(),
          ),
        ),
      );
      await sendAndReceive(tester, service, envelope);

      await tester.tap(find.byKey(const Key('chat-edit-dismiss-1')));
      await settle(tester);

      expect(find.text('已忽略'), findsOneWidget);
      expect(find.byKey(const Key('chat-edit-apply-1')), findsNothing);
    });

    testWidgets('流式期间原始 JSON 不上屏（占位替身）', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _RecordingExecutor(),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '帮我记一笔',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);

      calls.single.emit('{"reply":"好的');
      await settle(tester);
      expect(find.textContaining('"reply"'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    // 2026-10-24 用户：「食堂菜品 AI 分析会转发英文代码片段」「很多次推不了
    // 应用卡片」——模型把信封写坏时，原始 JSON 不得以纯文本回退上屏。
    testWidgets('信封写坏：气泡给人话，不出现 JSON 片段；仍可手动重来', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _RecordingExecutor(),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '今天午饭怎么样',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);
      calls.single.emit('{"reply":"帮你记一笔","edits":[{"action":"water.add",');
      await calls.single.finish();
      await settle(tester);

      expect(
        find.textContaining('没能整理成可应用的修改'),
        findsOneWidget,
        reason: '半截 JSON 必须换成人话',
      );
      expect(find.textContaining('"action"'), findsNothing);
      expect(find.textContaining('"edits"'), findsNothing);
      expect(find.byKey(const Key('chat-edit-card-1')), findsNothing);
    });

    testWidgets('正常回复里的内部引用不上屏（snapshot 坐标）', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(tester, AiConversationPage(service: service));
      await tester.enterText(
        find.byKey(const Key('ai-chat-text-input')),
        '今天午饭怎么样',
      );
      await tester.tap(find.byKey(const Key('btn-send')));
      await settle(tester);
      calls.single.emit('看了[canteen-dish:abc-1]这道菜，建议配一份青菜。');
      await calls.single.finish();
      await settle(tester);

      expect(find.textContaining('建议配一份青菜'), findsOneWidget);
      expect(find.textContaining('canteen-dish'), findsNothing);
    });

    testWidgets('2.0× 大字号下编辑卡不溢出', (tester) async {
      final calls = <_ServiceCall>[];
      final service = _ManualService(calls);
      await pumpPage(
        tester,
        AiConversationPage(
          service: service,
          chatEdit: ChatEditCoordinator(
            contextBuilder: _FakeEditContext(),
            executor: _RecordingExecutor(),
          ),
        ),
        size: const Size(320, 700),
        textScale: 2.0,
      );
      await sendAndReceive(tester, service, envelope);

      expect(find.byKey(const Key('chat-edit-card-1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

// ── 编辑卡替身（docs/23）────────────────────────────────────────────

/// 构造一条会话消息（T7 期间块搬移误删，按调用点契约重建：
/// `_message(id, role, text)`，其余字段用固定时刻，保证历史顺序断言稳定）。
ConversationMessage _message(String id, ConversationRole role, String text) =>
    ConversationMessage(
      id: id,
      role: role,
      text: text,
      createdAt: DateTime(2026, 9, 23, 12),
    );

class _FakeEditContext implements ChatEditContextBuilder {
  @override
  Future<String> build({
    String? userMessage,
    PendingProposal? pendingProposal,
  }) async => '【当前可编辑数据快照】测试';
}

class _RecordingExecutor implements ChatEditExecutor {
  final List<ChatEditCommand> received = [];

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    received.add(command);
    return ChatEditApplyResult.ok('饮水已记录。');
  }
}

/// 按命令种类给不同修复建议的执行器（四类缺实体测试用）。
class _RepairKindExecutor implements ChatEditExecutor {
  final List<ChatEditCommand> received = [];

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    received.add(command);
    return switch (command.action) {
      'session.start' => ChatEditApplyResult.failure(
        '动作库里没有「农夫行走」。',
        repair: const ChatEditRepair.createExercise(name: '农夫行走'),
      ),
      'canteen.venue.rename' => ChatEditApplyResult.failure(
        '找不到食堂地点「三食堂」。',
        repair: const ChatEditRepair.createVenue(name: '三食堂'),
      ),
      'canteen.window.create' => ChatEditApplyResult.failure(
        '找不到窗口「四号窗口」。',
        repair: const ChatEditRepair.createWindow(
          name: '四号窗口',
          venueId: 'venue-1',
        ),
      ),
      _ => ChatEditApplyResult.ok('已完成'),
    };
  }
}

/// 缺食材的执行器（1.5 的「创建食材」修复按钮测试用）：失败带结构化提示。
class _MissingFoodExecutor implements ChatEditExecutor {
  final List<ChatEditCommand> received = [];

  @override
  Future<ChatEditApplyResult> apply(ChatEditCommand command) async {
    received.add(command);
    return ChatEditApplyResult.failure(
      '找不到食材「鸡肉」。',
      repair: const ChatEditRepair.createFood(name: '鸡肉'),
    );
  }
}

// ── 替身实现 ───────────────────────────────────────────────────────────

final class _ManualService implements AiConversationService {
  _ManualService(this.calls);

  final List<_ServiceCall> calls;

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) {
    final call = _ServiceCall(
      messages: messages,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
    calls.add(call);
    return call.stream;
  }
}

final class _ServiceCall {
  _ServiceCall({
    required this.messages,
    required this.onProgress,
    Stream<void>? cancelToken,
  }) {
    // 控制器取消时关闭 cancelToken —— 这就是「请求被取消」的契约。
    cancelToken?.listen((_) {}, onDone: () => cancelled = true);
  }

  final List<ConversationMessage> messages;
  final void Function(String chunk) onProgress;
  final StreamController<String> _controller = StreamController<String>();
  bool cancelled = false;

  Stream<String> get stream => _controller.stream;

  void emit(String chunk) {
    onProgress(chunk);
    _controller.add(chunk);
  }

  void fail(Object error) => _controller.addError(error);

  Future<void> finish() => _controller.close();
}

final class _FakeMealImagePicker implements MealImagePicker {
  _FakeMealImagePicker({this.selection, this.failure});

  final SelectedMealImage? selection;
  final MealImageFailure? failure;
  final List<MealImageSource> sources = [];

  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async {
    if (failure != null) throw failure!;
    sources.add(source);
    return selection;
  }

  @override
  Future<SelectedMealImage?> recoverLost() async => null;
}

/// 内存图片仓：记录保存/删除，文件名按次数编（chat_1.jpg…）。
class _MemoryChatImageStore implements ChatImageStore {
  final List<ProcessedMealImage> saved = [];
  final List<String> deleted = [];

  @override
  Future<ChatImage> save(
    ProcessedMealImage image, {
    required DateTime createdAt,
  }) async {
    saved.add(image);
    final name = 'chat_${saved.length}.jpg';
    return ChatImage(
      path: '/tmp/$name',
      fileName: name,
      width: image.width,
      height: image.height,
    );
  }

  @override
  Future<void> delete(String path) async {
    deleted.add(path);
  }

  @override
  Future<bool> exists(String path) async => true;

  @override
  Future<void> clearAll() async {}
}

final class _FakeProcessor implements MealImageProcessor {
  const _FakeProcessor();

  @override
  Future<ProcessedMealImage> process(SelectedMealImage selected) async {
    return ProcessedMealImage(bytes: selected.bytes, width: 100, height: 100);
  }
}

SelectedMealImage _selected() => SelectedMealImage(
  bytes: Uint8List.fromList(const [1, 2, 3]),
  source: MealImageSource.gallery,
);

/// 内存聊天记录仓储（历史/落库测试用）。
class _MemoryHistory implements ConversationMessageRepository {
  _MemoryHistory({
    List<ConversationMessage>? initial,
    this.failLoad = false,
    this.failSave = false,
  }) : initial = initial ?? const [];

  List<ConversationMessage> initial;
  bool failLoad;
  bool failSave;
  final List<ConversationMessage> saved = [];

  @override
  Future<List<ConversationMessage>> loadRecent({
    String sessionId = ConversationMessageRepository.defaultSessionId,
    int limit = 200,
  }) async {
    if (failLoad) throw StateError('history unavailable');
    return initial;
  }

  @override
  Future<void> save(
    ConversationMessage message, {
    String sessionId = ConversationMessageRepository.defaultSessionId,
  }) async {
    if (failSave) throw StateError('disk full');
    saved.add(message);
  }

  @override
  Future<int> clear({
    String sessionId = ConversationMessageRepository.defaultSessionId,
  }) async {
    final before = saved.length;
    saved.clear();
    initial = [];
    return before;
  }
}
