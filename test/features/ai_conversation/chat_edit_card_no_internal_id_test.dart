import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

/// **卡片上不该出现内部 id**（2026-10-25 用户实测）。
///
/// 用户原话：「食堂目录里的菜品 AI 分析的时候，还是会在卡片上输出一堆食材 ID」。
///
/// 根因有 12 处：多国命令的 `summarize()` 把快照 id 直接拼进文案
/// （`删除饮水记录 water-3f2a9b`、`[canteen-dish:mx-3] 每 100g…`）。
/// 修法：菜品营养从源头去掉 id；其余统一在卡片出口剥引用 + 裸 id 换短尾号。
void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  Future<String> subtitleOf(
    WidgetTester tester,
    ChatEditCommand command,
  ) async {
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
                text: '准备修改。',
                kind: ConversationMessageKind.editProposal,
                editTurn: ChatEditTurn(
                  reply: '准备修改。',
                  rows: [
                    ChatEditTurnItem(index: 0, raw: const {}, command: command),
                  ],
                ),
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
    // 非记餐命令只有一个子条目；副标题就是 summarize 的清洗结果。
    final texts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(const Key('chat-edit-subitem-0-0-0')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data ?? '')
        .toList();
    return texts.join(' | ');
  }

  group('食堂菜品营养分析：卡片上不出现 dish id', () {
    testWidgets('canteen.dish.nutrition 的摘要不含 dishId / canteen-dish', (
      tester,
    ) async {
      final subtitle = await subtitleOf(
        tester,
        cmd('canteen.dish.nutrition', {
          'dishId': '[canteen-dish:mx-3]',
          'kcalPer100g': 45.0,
          'proteinPer100g': 1.5,
          'carbsPer100g': 5.0,
          'fatPer100g': 2.0,
        }),
      );
      expect(subtitle, isNot(contains('canteen-dish')));
      expect(subtitle, isNot(contains('mx-3')));
      // 但营养数值必须在（用户要知道分析结果）。
      expect(subtitle, contains('45'));
      expect(subtitle, contains('每 100g'));
    });
  });

  group('其它命令的裸 id：保留可辨认的短尾号，不露内部格式', () {
    testWidgets('删除饮水记录：显示 …尾号，不是完整 id', (tester) async {
      final subtitle = await subtitleOf(
        tester,
        cmd('water.delete', {'waterId': 'water-3f2a9b'}),
      );
      expect(subtitle, isNot(contains('water-3f2a9b')));
      expect(subtitle, contains('…3f2a9b'), reason: '保留尾号，用户还能对上是哪条');
      expect(subtitle, contains('删除饮水记录'));
    });

    testWidgets('删除餐：同样只留尾号', (tester) async {
      final subtitle = await subtitleOf(
        tester,
        cmd('meal.delete', {'mealId': 'meal-1a2b3c4d'}),
      );
      expect(subtitle, isNot(contains('meal-1a2b3c4d')));
      expect(subtitle, contains('…2b3c4d'));
    });
  });

  group('正常文案不被误伤', () {
    testWidgets('记一餐的子条目仍是「食物 · 克数」', (tester) async {
      final subtitle = await subtitleOf(
        tester,
        cmd('meal.create', {
          'slot': 'lunch',
          'items': [
            {'food': '鸡胸肉', 'grams': 150.0},
            {'food': '米饭', 'grams': 150.0},
          ],
        }),
      );
      expect(subtitle, contains('鸡胸肉'));
      expect(subtitle, contains('150'));
      expect(subtitle, isNot(contains('…')), reason: '纯中文食物名不该被当成 id');
    });
  });
}
