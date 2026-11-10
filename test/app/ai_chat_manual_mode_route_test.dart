// docs/66 §10：正式入口必须显式拿到 `manualCardGeneration: true`。
//
// 防的是「测试全绿、线上仍走旧路径」：页面构造参数默认 false（回滚开关），
// 只有 app_router 显式传 true，新交互才真正上线。本测试直接构建路由并
// 检查 ai-chat 分支里真实构造出来的 AiConversationPage。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/ai_conversation_page.dart';

final class _StubConversationService implements AiConversationService {
  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app_router 给 ai-chat 分支的页面显式启用新模式', (tester) async {
    final router = createAppRouter(
      initialLocation: AppRoutes.aiChat,
      conversationService: _StubConversationService(),
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();

    final page = tester.widget<AiConversationPage>(
      find.byType(AiConversationPage),
    );
    expect(
      page.manualCardGeneration,
      isTrue,
      reason: 'docs/66 §10：正式入口显式传 true，否则升级后线上仍走旧自动弹卡',
    );
  });
}
