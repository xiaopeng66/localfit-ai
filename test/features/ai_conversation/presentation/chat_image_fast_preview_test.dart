// 图片多选 + 「选中即显示」乐观预览（2026-11-07 用户反馈）。
//
// 原链路：读字节 → isolate 解码 → 缩放重编码 → 写文档副本 → 才上屏（约 1 秒）。
// 现在：先拿路径**立刻**挂预览，重活后台做，完成后再换成本地副本；发送前等
// 副本就绪（聊天记录不能存系统缓存的临时路径）。
//
// 【2026-11-07 用户改成更直接的方案】副本未就绪时**发送键置灰不可点**
// （就绪后自动恢复），不再依赖「点了挂起等就绪」的时序——那条时序在测试里
// 跨 zone 不可控，置灰是可观测、可测的。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/application/pick_chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';

final class _MultiPicker implements MealImagePicker, PathMealImagePicker {
  _MultiPicker(this.refs);

  final List<SelectedMealImageRef> refs;

  @override
  Future<SelectedMealImage?> pick(MealImageSource source) async => null;

  @override
  Future<SelectedMealImage?> recoverLost() async => null;

  @override
  Future<List<SelectedMealImageRef>> pickRefs(
    MealImageSource source, {
    int limit = 9,
  }) async => refs.take(limit).toList();
}

/// 可门控的处理器：测试用 Completer 把「后台处理」停在半路。
final class _GatedProcessor implements MealImageProcessor {
  final gate = Completer<void>();

  @override
  Future<ProcessedMealImage> process(SelectedMealImage selected) async {
    await gate.future;
    return ProcessedMealImage(bytes: selected.bytes, width: 80, height: 60);
  }
}

/// 内存图片仓：保存返回副本路径（`/docs/chat_N.jpg`）。
final class _MemoryStore implements ChatImageStore {
  final List<String> saved = [];
  int _n = 0;

  @override
  Future<ChatImage> save(
    ProcessedMealImage image, {
    required DateTime createdAt,
  }) async {
    final name = 'chat_${_n++}.jpg';
    saved.add(name);
    return ChatImage(
      path: '/docs/$name',
      fileName: name,
      width: image.width,
      height: image.height,
    );
  }

  @override
  Future<void> delete(String filePath) async {}

  @override
  Future<bool> exists(String filePath) async => true;

  @override
  Future<void> clearAll() async {}
}

final class _StubService implements AiConversationService {
  final List<List<ConversationMessage>> calls = [];

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    calls.add(messages);
  }
}

void main() {
  late Directory tempDir;
  late List<SelectedMealImageRef> refs;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('chat-fast-');
    refs = [];
    for (var i = 0; i < 3; i++) {
      final file = File('${tempDir.path}/picked_$i.jpg')
        ..writeAsBytesSync(Uint8List.fromList(const [1, 2, 3]));

      refs.add(
        SelectedMealImageRef(
          path: file.path,
          fileName: 'picked_$i.jpg',
          source: MealImageSource.gallery,
        ),
      );
    }
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester, Widget page) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(Duration.zero);
    }
  }

  /// 等**真实文件 IO** 落地：materialize 会 `readAsBytes` 原图，
  /// widget 测试的 FakeAsync 不推进真异步，必须借 runAsync。
  Future<void> drainIo(WidgetTester tester) async {
    for (var round = 0; round < 15; round++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  testWidgets('一次选 3 张：预览立刻出现，不等后台处理', (tester) async {
    final processor = _GatedProcessor();
    final store = _MemoryStore();
    final picker = PickChatImage(
      picker: _MultiPicker(refs),
      processor: processor,
      store: store,
      clock: const SystemAppClock(),
    );
    await pumpPage(
      tester,
      AiConversationPage(service: _StubService(), chatImagePicker: picker),
    );

    await tester.tap(find.byKey(const Key('btn-image-upload')));
    // 弹层有进入动画：等它落定再点，否则 tap 落空（hitTest 警告）。
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-pick-gallery')));
    await settle(tester);

    // 处理还没完成（门没开），但三张预览已经在输入区上方。
    expect(processor.gate.isCompleted, isFalse);
    expect(find.byKey(const Key('image-preview-thumb-0')), findsOneWidget);
    expect(find.byKey(const Key('image-preview-thumb-1')), findsOneWidget);
    expect(find.byKey(const Key('image-preview-thumb-2')), findsOneWidget);

    // 放行后台处理 → 换成副本路径（文档目录），原图路径不再被引用。
    processor.gate.complete();
    await drainIo(tester);
    expect(store.saved, hasLength(3));
    expect(find.byKey(const Key('image-preview-thumb-2')), findsOneWidget);
  });

  testWidgets('副本未就绪时发送键置灰不可点；就绪后恢复可点', (tester) async {
    final processor = _GatedProcessor();
    final store = _MemoryStore();
    final service = _StubService();
    final picker = PickChatImage(
      picker: _MultiPicker(refs),
      processor: processor,
      store: store,
      clock: const SystemAppClock(),
    );
    await pumpPage(
      tester,
      AiConversationPage(service: service, chatImagePicker: picker),
    );

    await tester.tap(find.byKey(const Key('btn-image-upload')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-pick-gallery')));
    await tester.pumpAndSettle();

    // 处理中：按钮灰、不可点。
    await tester.enterText(
      find.byKey(const Key('ai-chat-text-input')),
      '看看这三张',
    );
    await settle(tester);
    final disabled = tester.widget<LfCircleIconButton>(
      find.byKey(const Key('btn-send')),
    );
    expect(disabled.onPressed, isNull, reason: '副本未就绪 ⇒ 发送键禁用（置灰）');
    expect(disabled.background, isNot(disabled.iconColor));
    await tester.tap(find.byKey(const Key('btn-send')));
    await settle(tester);
    expect(service.calls, isEmpty, reason: '禁用时点了也不发请求');
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '看看这三张',
      reason: '输入内容不能被吞掉',
    );

    // 就绪后：按钮恢复，能正常发出。
    processor.gate.complete();
    await drainIo(tester);
    final enabled = tester.widget<LfCircleIconButton>(
      find.byKey(const Key('btn-send')),
    );
    expect(enabled.onPressed, isNotNull, reason: '副本就绪 ⇒ 发送键恢复');
    await tester.tap(find.byKey(const Key('btn-send')));
    await drainIo(tester);
    expect(service.calls, hasLength(1));
  });

  testWidgets('多选一次发出，消息里存的是文档目录副本（不是系统缓存路径）', (tester) async {
    final processor = _GatedProcessor();
    final store = _MemoryStore();
    final service = _StubService();
    final picker = PickChatImage(
      picker: _MultiPicker(refs),
      processor: processor,
      store: store,
      clock: const SystemAppClock(),
    );
    await pumpPage(
      tester,
      AiConversationPage(service: service, chatImagePicker: picker),
    );

    await tester.tap(find.byKey(const Key('btn-image-upload')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('attachment-pick-gallery')));
    await tester.pumpAndSettle();
    // 放行后台处理（真实文件 IO 要用 runAsync 推进）→ 占位换成副本。
    processor.gate.complete();
    await drainIo(tester);
    expect(store.saved, hasLength(3));

    await tester.enterText(
      find.byKey(const Key('ai-chat-text-input')),
      '看看这三张',
    );
    await tester.tap(find.byKey(const Key('btn-send')));
    await drainIo(tester);

    expect(service.calls, hasLength(1), reason: '三张图 = 一次请求');
    final sent = service.calls.single;
    final imagePaths = [
      for (final message in sent)
        if (message.kind == ConversationMessageKind.image) message.imagePath,
    ];
    expect(imagePaths, hasLength(3), reason: '三张图一起发出（多选）');
    for (final path in imagePaths) {
      expect(path, startsWith('/docs/chat_'), reason: '发出去的是文档目录副本');
      expect(path, isNot(contains('picked_')), reason: '不是系统缓存里的原图路径');
    }
  });
}
