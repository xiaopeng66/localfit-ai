import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

/// 2026-11-06 用户复核的三条：
///
/// 1. 「克数换第二行加餐后边，根本看不见」——标题只留食物名，克数挪到
///    第二行的餐次后面；
/// 2. 「新建标签和状态能不能做成上下两行」——两个徽标竖排在行尾，名称
///    独占剩余宽度；
/// 3. 「为啥应用之后，有的下边有绿色描述，有的没有」——结果是命令粒度，
///    旧实现只挂在第一条食材下。现在放在**分组底部**，组内每行只保留
///    状态徽标。
void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  ConversationMessage messageWith(ChatEditTurn turn) => ConversationMessage(
    id: 'card-row-result',
    role: ConversationRole.assistant,
    text: turn.reply,
    kind: ConversationMessageKind.editProposal,
    editTurn: turn,
    createdAt: DateTime(2026, 11, 6, 12),
  );

  Future<void> pump(WidgetTester tester, ChatEditTurn turn) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
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
    );
    await tester.pumpAndSettle();
  }

  ChatEditTurn longNameTurn() => ChatEditTurn(
    reply: '早餐记米饭和抹茶曲奇，曲奇要先新建。',
    rows: [
      ChatEditTurnItem(
        index: 0,
        raw: const {'action': 'meal.create'},
        command: cmd('meal.create', {
          'slot': 'breakfast',
          'items': [
            {'food': '米饭', 'grams': 150.0},
            {'food': '抹茶曲奇（梅花形）', 'grams': 30.0},
          ],
        }),
      ),
      ChatEditTurnItem(
        index: 1,
        raw: const {'action': 'food.create'},
        command: cmd('food.create', {
          'name': '抹茶曲奇（梅花形）',
          'kcalPer100g': 480.0,
          'proteinPer100g': 5.0,
          'carbsPer100g': 60.0,
          'fatPer100g': 25.0,
        }),
      ),
    ],
  );

  testWidgets('标题只放食物名，克数在第二行餐次后；新建与状态竖排在行尾', (tester) async {
    await pump(tester, longNameTurn());

    expect(
      tester
          .widget<Text>(find.byKey(const Key('chat-edit-subitem-title-0-0-1')))
          .data,
      '抹茶曲奇（梅花形）',
      reason: '标题不再拼「· 30 g」，长名字才完整',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const Key('chat-edit-subitem-summary-0-0-1')),
          )
          .data,
      '早餐 · 30 g',
      reason: '克数换到第二行，跟在餐次后面',
    );

    final newBadge = find.byKey(const Key('chat-edit-subitem-new-0-0-1'));
    final statusBadge = find.byKey(const Key('chat-edit-subitem-status-0-0-1'));
    expect(newBadge, findsOneWidget);
    expect(statusBadge, findsOneWidget);
    expect(
      tester.getTopLeft(newBadge).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(statusBadge).dy),
      reason: '状态在上、「新建」在下，不再各占一段横向宽度',
    );
    expect(
      tester.getTopRight(statusBadge).dx,
      closeTo(tester.getTopRight(newBadge).dx, 0.1),
      reason: '两个徽标同属行尾竖列，右边缘对齐',
    );
  });

  testWidgets('全部行失败：卡头是中性「未应用」，不是绿色「已完成」', (tester) async {
    final turn = ChatEditTurn(
      reply: '这两条都没成。',
      rows: [
        ChatEditTurnItem(
          index: 0,
          raw: const {'action': 'water.add'},
          command: cmd('water.add', {'amountMl': 250.0}),
        ).copyWith(
          status: ChatEditRowStatus.failed,
          resultMessage: '这条写入失败，请重试。',
        ),
        ChatEditTurnItem(
          index: 1,
          raw: const {'action': 'weight.log'},
          command: cmd('weight.log', {'weightKg': 72.5}),
        ).copyWith(
          status: ChatEditRowStatus.failed,
          resultMessage: '请先完成本地建档。',
        ),
      ],
    );
    await pump(tester, turn);

    expect(find.text('未应用'), findsOneWidget);
    expect(find.text('已完成'), findsNothing, reason: '全失败不能显示绿色已完成');
  });

  testWidgets('部分应用 + 部分失败：仍显示「已完成」', (tester) async {
    final turn = ChatEditTurn(
      reply: '一条成一条败。',
      rows: [
        ChatEditTurnItem(
          index: 0,
          raw: const {'action': 'water.add'},
          command: cmd('water.add', {'amountMl': 250.0}),
        ).copyWith(status: ChatEditRowStatus.applied, resultMessage: '饮水已记录。'),
        ChatEditTurnItem(
          index: 1,
          raw: const {'action': 'weight.log'},
          command: cmd('weight.log', {'weightKg': 72.5}),
        ).copyWith(
          status: ChatEditRowStatus.failed,
          resultMessage: '请先完成本地建档。',
        ),
      ],
    );
    await pump(tester, turn);

    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('未应用'), findsNothing, reason: '有成功的行就不算「未应用」');
  });

  testWidgets('记餐应用后：每样食物下面各有自己的说明，卡片末尾不再堆汇总绿字', (tester) async {
    ChatEditTurnItem applied({
      required int index,
      required String slot,
      required List<Map<String, Object>> items,
      required Map<String, String> notes,
    }) {
      final base = ChatEditTurnItem(
        index: index,
        raw: const {'action': 'meal.create'},
        command: cmd('meal.create', {'slot': slot, 'items': items}),
      );
      return base.copyWith(
        status: ChatEditRowStatus.applied,
        resultMessage: '已记录这一餐。',
        itemNotes: notes,
      );
    }

    final turn = ChatEditTurn(
      reply: '早餐和午餐都记好了。',
      rows: [
        applied(
          index: 0,
          slot: 'breakfast',
          items: [
            {'food': '米饭', 'grams': 150.0},
            {'food': '鸡蛋', 'grams': 100.0},
          ],
          notes: const {'米饭': '已记入今天的早餐', '鸡蛋': '已记入今天的早餐'},
        ),
        applied(
          index: 1,
          slot: 'lunch',
          items: [
            {'food': '鸡胸肉', 'grams': 150.0},
            {'food': '牛奶', 'grams': 200.0},
          ],
          notes: const {'鸡胸肉': '已记入今天的午餐', '牛奶': '今天已记过，没有重复算'},
        ),
      ],
    );

    await pump(tester, turn);

    // 每样食物行下都有各自的说明（key 带子条目下标）。
    expect(find.text('已记入今天的早餐'), findsNWidgets(2));
    expect(find.text('已记入今天的午餐'), findsOneWidget);
    expect(find.text('今天已记过，没有重复算'), findsOneWidget);
    for (final key in const [
      'chat-edit-row-result-0-0-0',
      'chat-edit-row-result-0-0-1',
      'chat-edit-row-result-0-1-0',
      'chat-edit-row-result-0-1-1',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    // 命令粒度的汇总行不再堆在分组底部。
    expect(
      find.byKey(const Key('chat-edit-group-result-0-meal-0')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('chat-edit-group-result-0-meal-1')),
      findsNothing,
    );

    // 说明紧贴在自己那行标题的下方（同列、在下）。
    final riceTitle = tester.getBottomLeft(
      find.byKey(const Key('chat-edit-subitem-title-0-0-0')),
    );
    final riceNote = tester.getTopLeft(
      find.byKey(const Key('chat-edit-row-result-0-0-0')),
    );
    expect(riceNote.dy, greaterThan(riceTitle.dy));
    final milkTitle = tester.getBottomLeft(
      find.byKey(const Key('chat-edit-subitem-title-0-1-1')),
    );
    final milkNote = tester.getTopLeft(
      find.byKey(const Key('chat-edit-row-result-0-1-1')),
    );
    expect(milkNote.dy, greaterThan(milkTitle.dy));
  });

  testWidgets('单条命令（记一笔饮水）的结果挂在自己那行下面', (tester) async {
    final turn = ChatEditTurn(
      reply: '记好了。',
      rows: [
        ChatEditTurnItem(
          index: 0,
          raw: const {'action': 'water.add'},
          command: cmd('water.add', {'amountMl': 250.0}),
        ).copyWith(status: ChatEditRowStatus.applied, resultMessage: '饮水已记录。'),
      ],
    );

    await pump(tester, turn);

    expect(find.byKey(const Key('chat-edit-row-result-0-0-0')), findsOneWidget);
    expect(find.text('饮水已记录。'), findsOneWidget);
    expect(
      find.byKey(const Key('chat-edit-group-result-0-other-0')),
      findsNothing,
      reason: '单行命令的结果不该再出现在组尾',
    );
  });

  testWidgets('没有按食物拆分的多食物失败：仍留在组尾（fallback）', (tester) async {
    final turn = ChatEditTurn(
      reply: '这一餐没记上。',
      rows: [
        ChatEditTurnItem(
          index: 0,
          raw: const {'action': 'meal.create'},
          command: cmd('meal.create', {
            'slot': 'dinner',
            'items': [
              {'food': '米饭', 'grams': 150.0},
              {'food': '鸡蛋', 'grams': 100.0},
            ],
          }),
        ).copyWith(
          status: ChatEditRowStatus.failed,
          resultMessage: '食物库里没有「鸡蛋」；可以先创建它，或换一个已有食材。',
        ),
      ],
    );

    await pump(tester, turn);

    // 没有 itemNotes ⇒ 不在食物行下挂说明；组尾保留整条失败原因。
    expect(find.byKey(const Key('chat-edit-row-result-0-0-0')), findsNothing);
    expect(find.byKey(const Key('chat-edit-row-result-0-0-1')), findsNothing);
    expect(
      find.byKey(const Key('chat-edit-group-result-0-meal-0')),
      findsOneWidget,
    );
    expect(find.text('食物库里没有「鸡蛋」；可以先创建它，或换一个已有食材。'), findsOneWidget);
  });
}
