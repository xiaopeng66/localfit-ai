import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_proposal_audit.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

/// **审查警告上屏**（2026-10-24）。
///
/// 用户要求「要有自己的去重和检测遗漏的机制」。审查器算出问题后必须让用户
/// 在点「应用」**之前**看见——否则等于没做。
///
/// 三条判据：
/// 1. 有警告 → 卡片上出现对应文案（Key `chat-edit-warning-<卡>-<序>`）；
/// 2. 没警告 → 一条都不出现（不许凭空多一块灰底）；
/// 3. **警告不阻断应用**——「全部应用」按钮照常可点（这是「只提示不改数据」
///    的另一半：App 不替用户决定）。
void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  ChatEditTurn turnWith(List<ChatEditAuditWarning> warnings) {
    final command = cmd('meal.create', {
      'slot': 'lunch',
      'items': [
        {'food': '米饭', 'grams': 150.0},
      ],
    });
    return ChatEditTurn(
      reply: '我准备把午餐记为米饭 150g。',
      rows: [
        ChatEditTurnItem(
          index: 0,
          raw: {'action': 'meal.create'},
          command: command,
        ),
      ],
      warnings: warnings,
    );
  }

  ConversationMessage messageWith(ChatEditTurn turn) => ConversationMessage(
    id: 'card-1',
    role: ConversationRole.assistant,
    text: turn.reply,
    kind: ConversationMessageKind.editProposal,
    editTurn: turn,
    createdAt: DateTime(2026, 10, 24, 12),
  );

  Future<void> pumpCard(
    WidgetTester tester,
    ChatEditTurn turn, {
    VoidCallback? onApply,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatEditCard(
              index: 0,
              message: messageWith(turn),
              onApply: onApply ?? () {},
              onApplyRows: (_) {},
              onDismiss: () {},
              onApplySuggestion: (_) {},
              onRepair: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('有警告 → 卡片上出现警告文案', (tester) async {
    await pumpCard(
      tester,
      turnWith(const [
        ChatEditAuditWarning(
          kind: ChatEditAuditKind.slotMismatch,
          message: '你说的是晚餐，但这条提议记到午餐——应用前请确认。',
        ),
      ]),
    );
    expect(find.byKey(const Key('chat-edit-warning-0-0')), findsOneWidget);
    expect(find.textContaining('你说的是晚餐'), findsOneWidget);
  });

  testWidgets('多条警告 → 逐条都上屏', (tester) async {
    await pumpCard(
      tester,
      turnWith(const [
        ChatEditAuditWarning(
          kind: ChatEditAuditKind.slotMismatch,
          message: '你说的是晚餐，但这条提议记到午餐。',
        ),
        ChatEditAuditWarning(
          kind: ChatEditAuditKind.duplicateFood,
          message: '同一餐里重复提到了「米饭」。',
        ),
      ]),
    );
    expect(find.byKey(const Key('chat-edit-warning-0-0')), findsOneWidget);
    expect(find.byKey(const Key('chat-edit-warning-0-1')), findsOneWidget);
    expect(find.textContaining('重复提到了'), findsOneWidget);
  });

  testWidgets('没警告 → 一条警告都不出现', (tester) async {
    await pumpCard(tester, turnWith(const []));
    expect(find.byKey(const Key('chat-edit-warning-0-0')), findsNothing);
  });

  testWidgets('警告不阻断应用：「全部应用」照常可点', (tester) async {
    var applied = false;
    await pumpCard(
      tester,
      turnWith(const [
        ChatEditAuditWarning(
          kind: ChatEditAuditKind.missingFood,
          message: '你提到了「鸡蛋」，但这条提议里没有。',
        ),
      ]),
      onApply: () => applied = true,
    );
    final button = find.byKey(const Key('chat-edit-apply-0'));
    expect(button, findsOneWidget);
    // key 直接挂在 LfPrimaryButton 内部的 FilledButton 上（`_innerKey`），
    // 所以按 key 取到的就是那个 FilledButton 本身。
    final widget = tester.widget<FilledButton>(button);
    expect(widget.onPressed, isNotNull, reason: '警告只提示，不许把用户的应用按钮禁掉——改不改由用户决定');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(applied, isTrue);
  });
}
