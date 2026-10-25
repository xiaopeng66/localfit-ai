import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/application/conversation_controller.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';

/// `RV4-P2-03`（`docs/57` §3 / `docs/56` R14 / D5）：**显示文本与发送文本分离**。
///
/// 现状：`app_router.dart` 把菜名 + `[canteen-dish:<id>]` 拼成一条启动提示词，
/// 随后 `_sendCurrent` 把它原样当**用户消息**发送 ⇒ 聊天气泡里出现一长串
/// 机器 id。模型侧其实不需要（system 快照里已有同样形式）。
///
/// 修法（D5）：显示与发送分离；气泡只显示菜名 + 一行披露，发给模型的那份带 id。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingService service;
  late ConversationController controller;

  setUp(() {
    service = _RecordingService();
    controller = ConversationController(service);
  });

  test('sendMessageWithWire：气泡不含 canteen-dish，模型收到的含', () async {
    await controller.sendMessageWithWire(
      '估算这 2 道菜每 100g 的营养：番茄炒蛋、宫保鸡丁',
      wireText:
          '估算下面这几道菜每 100g 的营养：\n'
          '[canteen-dish:d1] 番茄炒蛋\n'
          '[canteen-dish:d2] 宫保鸡丁',
    );
    await pumpEventQueue();

    final user = controller.state.messages.firstWhere(
      (m) => m.role == ConversationRole.user,
    );
    expect(
      user.text.contains('canteen-dish:'),
      isFalse,
      reason: '用户气泡不得出现机器 id（R14）',
    );
    expect(
      user.textForRequest.contains('[canteen-dish:d1]'),
      isTrue,
      reason: '发给模型的正文必须带定位 id（canteen.dish.nutrition 要它）',
    );

    final sent = service.requests.single;
    final lastUser = sent.lastWhere((m) => m.role == ConversationRole.user);
    expect(lastUser.text.contains('[canteen-dish:d1]'), isTrue);
    expect(lastUser.text.contains('[canteen-dish:d2]'), isTrue);
  });

  test('普通 sendMessage 不受影响（显示 == 发送）', () async {
    await controller.sendMessage('今天吃了什么');
    await pumpEventQueue();
    final user = controller.state.messages.firstWhere(
      (m) => m.role == ConversationRole.user,
    );
    expect(user.text, '今天吃了什么');
    expect(user.wireText, isNull, reason: '两者相同时不记 wireText');
    expect(service.requests.single.last.text, '今天吃了什么');
  });

  test('空正文不发送', () async {
    await controller.sendMessageWithWire('  ', wireText: 'x');
    await pumpEventQueue();
    expect(controller.state.messages, isEmpty);
  });
}

final class _RecordingService implements AiConversationService {
  final List<List<ConversationMessage>> requests = [];

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    requests.add(List.of(messages));
    onProgress('好的');
    yield '好的';
  }
}
