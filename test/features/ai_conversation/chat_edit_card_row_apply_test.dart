/// **行级应用：UI 已退役，能力保留**（2026-10-24 用户裁决）。
///
/// 历史：`RV4-P2-07`（2026-10-23）给每行加了「应用」胶囊。
/// **本轮退役**：用户选定编辑卡方案 B 后明确裁决——
///
/// > 「改成子条目展示，但按钮只在组级」
///
/// 理由（写进裁决不删）：执行器的最小粒度是**命令**，而方案 B 把一条
/// `meal.create` 展开成「米饭 / 鸡胸肉 / 牛奶」三行子条目。如果每行都给
/// 一个「应用」，用户会以为能单独应用其中一个食物——**点哪个都是整条写入**。
/// 那是界面对用户说谎，比不给按钮更糟。
///
/// 因此：
/// * 行内不再有「应用」（本文件钉住「没有」）；
/// * **控制器与执行器的行级能力一行未改**（`applyEdits(rowIndexes:)` 仍在用，
///   组级「应用本组」走的就是它）——所以这不是功能删减，是 UI 收口。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

/// `RV4-P2-07`（`docs/57` §3 / `docs/56` R15）：**编辑卡每个条目可单独应用**。
///
/// 现状：行状态只有一枚 `LfBadge.neutral('待应用')`，可点动作只有组头
/// 「应用本组」与卡底「全部应用 / 忽略」。执行器与控制器**早已支持按行**
/// （`onApplyRows(Set<int>)` → `applyEdits(..., rowIndexes:)`）⇒ 缺的只是
/// 「行级」这一层 UI。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 10, 24, 2);

  ChatEditTurn turnWithTwoEdits() => parseChatEditTurn(
    jsonEncode({
      'reply': '准备记录两条',
      'edits': [
        {
          'action': 'water.add',
          'args': {'amountMl': 300},
        },
        {
          'action': 'water.add',
          'args': {'amountMl': 500},
        },
      ],
    }),
    ChatEditCommandRegistry(),
  )!;

  Widget host(ChatEditCard card) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: card),
  );

  ChatEditCard card({
    required ChatEditTurn turn,
    required ValueChanged<Set<int>> onApplyRows,
    bool applying = false,
  }) => ChatEditCard(
    index: 0,
    message: ConversationMessage(
      id: 'edit',
      role: ConversationRole.assistant,
      text: '准备记录两条',
      createdAt: now,
      kind: ConversationMessageKind.editProposal,
      editTurn: applying
          ? ChatEditTurn(
              reply: turn.reply,
              rows: [
                for (final row in turn.rows)
                  row.copyWith(status: ChatEditRowStatus.applying),
              ],
              suggestions: turn.suggestions,
            )
          : turn,
    ),
    onApply: () {},
    onApplyRows: onApplyRows,
    onDismiss: () {},
    onApplySuggestion: (_) {},
    onRepair: (_) {},
  );

  testWidgets('行内**没有**「应用」按钮（方案 B 裁决：按钮只在组级）', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(card(turn: turnWithTwoEdits(), onApplyRows: (_) {})),
    );
    await tester.pumpAndSettle();

    for (var row = 0; row < 2; row++) {
      expect(
        find.byKey(Key('chat-edit-row-apply-0-$row')),
        findsNothing,
        reason:
            '第 $row 行不该有行级「应用」：执行器按命令粒度，行内按钮会让用户'
            '以为能单独应用某个食物，实际是整条写入（2026-10-24 用户裁决）',
      );
    }
  });

  testWidgets('组级「应用本组」仍只提交本组（行级能力经由它保留）', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var received = <int>{};
    await tester.pumpWidget(
      host(
        card(turn: turnWithTwoEdits(), onApplyRows: (rows) => received = rows),
      ),
    );
    await tester.pumpAndSettle();

    // 这两条是 `water.add` ⇒ 归到「其他修改」组（kind = other）。
    await tester.tap(find.byKey(const Key('chat-edit-group-apply-0-other')));
    await tester.pumpAndSettle();

    expect(
      received,
      {0, 1},
      reason:
          '行级能力没删：`applyEdits(rowIndexes:)` 仍在用，组级按钮走的就是它。'
          '这里钉住「组级提交的是本组全部待应用行」。',
    );
  });

  testWidgets('忙碌时不给可点的行级按钮（避免并发写）', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var taps = 0;
    await tester.pumpWidget(
      host(
        card(
          turn: turnWithTwoEdits(),
          onApplyRows: (_) => taps++,
          applying: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 忙碌时行状态是 `applying`，行级按钮按设计不渲染（连带 `_busy` 双保险）。
    // 判据是「点不到」而不是「某个具体 widget 消失」——所以先确认没有可点的
    // `chat-edit-row-apply-*`，再确认即便强行点也不写。
    final button = find.byKey(const Key('chat-edit-row-apply-0-0'));
    if (button.evaluate().isNotEmpty) {
      expect(
        tester.widget<TextButton>(button).onPressed,
        isNull,
        reason: '`_turn.isApplying` 时整卡行级按钮一起禁用',
      );
      await tester.tap(button, warnIfMissed: false);
      await tester.pumpAndSettle();
    }
    expect(taps, 0, reason: '忙碌时不得产生任何应用调用');
    expect(find.text('应用中…'), findsWidgets);
  });

  testWidgets('已应用的行显示「已应用」徽标，不再有应用按钮', (tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final turn = turnWithTwoEdits();
    final applied = ChatEditTurn(
      reply: turn.reply,
      rows: [
        turn.rows.first.copyWith(status: ChatEditRowStatus.applied),
        turn.rows.last,
      ],
      suggestions: turn.suggestions,
    );
    await tester.pumpWidget(host(card(turn: applied, onApplyRows: (_) {})));
    await tester.pumpAndSettle();

    // 行内**永远**不再有应用按钮（方案 B 裁决），所以这里只钉状态徽标：
    // 已应用的那行显示「已应用」，未应用的那行显示「待应用」。
    expect(find.text('已应用'), findsOneWidget);
    expect(find.text('待应用'), findsOneWidget);
    expect(
      find.byKey(const Key('chat-edit-row-apply-0-0')),
      findsNothing,
      reason: '行级按钮已退役',
    );
    expect(
      find.byKey(const Key('chat-edit-row-apply-0-1')),
      findsNothing,
      reason: '行级按钮已退役（不管是否已应用）',
    );
  });
}
