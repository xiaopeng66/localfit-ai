import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

/// **食物单位的显示判据**（2026-10-25 用户实测缺陷）。
///
/// 用户原话：「鸡蛋 100，记成了 100ml」。
///
/// 根因：`_isLiquid` 用 `foodName.contains('水')` 判断液体，而「鸡蛋**水**煮」
/// 里含「水」⇒ 被判成液体 ⇒ 显示「鸡蛋水煮 · 100 ml」。
/// 同类误判还有「水煮蛋」「油麦菜」（前面有「油」）、「汤面」（含「汤」）。
///
/// 修法：改成**结尾**匹配（液体词只在词尾成立）。
void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  ChatEditTurn turnWithFood(String food, double grams) => ChatEditTurn(
    reply: '准备记一条。',
    rows: [
      ChatEditTurnItem(
        index: 0,
        raw: const {'action': 'meal.create'},
        command: cmd('meal.create', {
          'slot': 'breakfast',
          'items': [
            {'food': food, 'grams': grams},
          ],
        }),
      ),
    ],
  );

  Future<String> titleOf(WidgetTester tester, String food) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ChatEditCard(
              index: 0,
              message: ConversationMessage(
                id: 'm',
                role: ConversationRole.assistant,
                text: '准备记一条。',
                kind: ConversationMessageKind.editProposal,
                editTurn: turnWithFood(food, 100),
                createdAt: DateTime(2026, 10, 25),
              ),
              onApply: () {},
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
    return tester
        .widget<Text>(find.byKey(const Key('chat-edit-subitem-title-0-0-0')))
        .data!;
  }

  group('固体不该显示成 ml（用户实测：鸡蛋水煮 100 → ml）', () {
    testWidgets('「鸡蛋水煮」100g → 显示 100 g', (tester) async {
      final title = await titleOf(tester, '鸡蛋水煮');
      expect(title, contains('100 g'), reason: '「鸡蛋水煮」是固体，含「水」字不代表是液体');
      expect(title, isNot(contains('ml')));
    });

    testWidgets('「水煮蛋」→ g 不是 ml', (tester) async {
      final title = await titleOf(tester, '水煮蛋');
      expect(title, isNot(contains('ml')), reason: '名字**开头**有「水」不是液体');
    });

    testWidgets('「油麦菜」→ g 不是 ml', (tester) async {
      final title = await titleOf(tester, '油麦菜');
      expect(title, isNot(contains('ml')), reason: '开头有「油」不是液体');
    });

    testWidgets('「汤面」→ g 不是 ml', (tester) async {
      final title = await titleOf(tester, '汤面');
      expect(title, isNot(contains('ml')), reason: '含「汤」但在中间，是面不是汤');
    });
  });

  group('液体仍显示 ml', () {
    testWidgets('「牛奶」→ 200 ml', (tester) async {
      final title = await titleOf(tester, '牛奶');
      expect(title, contains('100 ml'));
    });

    testWidgets('「豆浆」→ ml', (tester) async {
      final title = await titleOf(tester, '豆浆');
      expect(title, contains('ml'));
    });

    testWidgets('「橙汁」→ ml', (tester) async {
      final title = await titleOf(tester, '橙汁');
      expect(title, contains('ml'));
    });

    testWidgets('「白开水」→ ml', (tester) async {
      final title = await titleOf(tester, '白开水');
      expect(title, contains('ml'));
    });

    testWidgets('「紫菜汤」→ ml', (tester) async {
      final title = await titleOf(tester, '紫菜汤');
      expect(title, contains('ml'), reason: '结尾是「汤」= 液体');
    });
  });
}
