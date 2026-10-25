@Tags(['capture'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_proposal_audit.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

import 'support/round7_render.dart';

/// **编辑卡方案 B 实帧**（2026-10-24 用户选定「清单式」）。
///
/// 产出三张 2× PNG（与其它 capture 套件同口径，走 `LF_ROUND7_CAPTURE_DIR`）：
/// * `01-card-b-meal`：记一餐 3 条（正常态，看卡头结论行 + 分块 + 编号）；
/// * `02-card-b-warning`：带审查警告（晚餐被记成午餐 + 重复食物）；
/// * `03-card-b-dark`：深色主题。
void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  ChatEditTurn mealTurn({List<ChatEditAuditWarning> warnings = const []}) {
    return ChatEditTurn(
      reply: '按常见份量估算好了，确认后我就记下来。',
      rows: [
        ChatEditTurnItem(
          index: 0,
          raw: const {'action': 'meal.create'},
          command: cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
              {'food': '鸡胸肉', 'grams': 150.0},
              {'food': '牛奶', 'grams': 200.0},
            ],
          }),
        ),
      ],
      warnings: warnings,
    );
  }

  ConversationMessage messageWith(ChatEditTurn turn) => ConversationMessage(
    id: 'card',
    role: ConversationRole.assistant,
    text: turn.reply,
    kind: ConversationMessageKind.editProposal,
    editTurn: turn,
    createdAt: DateTime(2026, 10, 24, 12),
  );

  Future<void> render(
    WidgetTester tester,
    ChatEditTurn turn,
    Brightness brightness,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        home: RepaintBoundary(
          key: round7Boundary,
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: ChatEditCard(
                    index: 0,
                    message: messageWith(turn),
                    onApply: () {},
                    onApplyRows: (_) {},
                    onDismiss: () {},
                    onApplySuggestion: (_) {},
                    onRepair: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUpAll(() async {
    await loadRound7Fonts();
  });

  testWidgets('编辑卡 B · 记一餐（亮）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await render(tester, mealTurn(), Brightness.light);
    await captureRound7(tester, '01-card-b-meal');
  });

  testWidgets('编辑卡 B · 带审查警告（亮）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await render(
      tester,
      mealTurn(
        warnings: const [
          ChatEditAuditWarning(
            kind: ChatEditAuditKind.slotMismatch,
            message: '你说的是晚餐，但这条提议记到午餐——应用前请确认要改餐次还是就这样记。',
          ),
          ChatEditAuditWarning(
            kind: ChatEditAuditKind.duplicateFood,
            message: '同一餐里重复提到了「米饭」——应用时会按一条记，克数以先出现的为准。',
          ),
        ],
      ),
      Brightness.light,
    );
    await captureRound7(tester, '02-card-b-warning');
  });

  testWidgets('编辑卡 B · 新建食材（方案 B：大热量 + 三色点）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final turn = ChatEditTurn(
      reply: '按常见值估算好了。',
      rows: [
        ChatEditTurnItem(
          index: 0,
          raw: const {'action': 'food.create'},
          command: cmd('food.create', {
            'name': '鸡蛋水煮',
            'kcalPer100g': 155.0,
            'proteinPer100g': 13.0,
            'carbsPer100g': 1.1,
            'fatPer100g': 10.6,
          }),
        ),
      ],
    );
    await render(tester, turn, Brightness.light);
    await captureRound7(tester, '04-card-b-food-row');
  });

  testWidgets('编辑卡 B · 记一餐（深色）', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await render(tester, mealTurn(), Brightness.dark);
    await captureRound7(tester, '03-card-b-dark');
  });
}
