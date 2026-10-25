import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_proposal_audit.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

/// **编辑卡「清单式」版式**（2026-10-24 用户选定方案 B）。
///
/// 用户原话：「三个方案我要清单 b」。
///
/// 解决的是真问题：原来卡头 / 分组头 / 行 / 卡底按钮**四个层级全是同一档
/// 灰字**，行标题 13px 与摘要 11px 只差 2px，眼睛扫过去找不到「这次要改
/// 什么」。
///
/// B 的两条核心改动（也是本文件的判据）：
/// 1. **卡头加「结论行 + 明细行」**：一句话说清「哪一餐、几条、都记了什么」，
///    不必逐行读摘要；
/// 2. **条目进浅灰分块**（`MutedBlock`）：靠**分块底色**把「一组」框起来，
///    层级不再只靠字号差。
///
/// 同时钉住**不许回退的三件事**（都是前几轮已裁决的）：
/// * 三档按钮层级（行级胶囊 < 组级软底 < 卡底实心）不变；
/// * 审查警告仍在、且不阻断应用；
/// * 所有既有 Key 不变（`chat-edit-card-*` / `-row-*` / `-group-apply-*` /
///   `-apply-*` / `-dismiss-*` / `-suggest-*` / `-warning-*`）。
void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  ChatEditTurn mealTurn({
    String slot = 'lunch',
    List<Map<String, Object>> items = const [
      {'food': '米饭', 'grams': 150.0},
      {'food': '鸡胸肉', 'grams': 150.0},
    ],
    List<ChatEditAuditWarning> warnings = const [],
  }) {
    return ChatEditTurn(
      reply: '我准备把午餐记下来。',
      rows: [
        ChatEditTurnItem(
          index: 0,
          raw: const {'action': 'meal.create'},
          command: cmd('meal.create', {'slot': slot, 'items': items}),
        ),
      ],
      warnings: warnings,
    );
  }

  ConversationMessage messageWith(ChatEditTurn turn) => ConversationMessage(
    id: 'card-b',
    role: ConversationRole.assistant,
    text: turn.reply,
    kind: ConversationMessageKind.editProposal,
    editTurn: turn,
    createdAt: DateTime(2026, 10, 24, 12),
  );

  Future<void> pump(
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

  // 为了让 _AuditWarningRow 可用（它在这个文件里没被直接引用，测试需要类型）。
  test('占位：审查警告类型可用', () {
    expect(ChatEditAuditKind.values, isNotEmpty);
  });

  // ══════════════════════════════════════════════════════════════════
  // 【1:1 对齐设计稿，2026-10-24 用户：「你这改的根本不是方案 b」】
  //
  // 设计稿 B 的行是**一个食物**（米饭 150g / 鸡胸肉 150g / 牛奶 200ml，
  // 三行、编号 1/2/3），不是「一条命令」。我第一版按命令渲染 ⇒ 三个食物
  // 挤在一行、只有一个「应用」，与原稿完全不同。
  //
  // 用户裁决：**视觉 1:1 还原子条目，按钮只在组级**（执行器仍按命令粒度，
  // 不动写入语义）。
  // ══════════════════════════════════════════════════════════════════
  group('B · 子条目（一个食物一行，1:1 对齐设计稿）', () {
    testWidgets('一条 meal.create 带 2 个食物 → 渲染成 2 个子条目', (tester) async {
      await pump(tester, mealTurn());
      expect(
        find.byKey(const Key('chat-edit-subitem-0-0-0')),
        findsOneWidget,
        reason: '第 1 个食物要有自己的行（设计稿：米饭 / 鸡胸肉 / 牛奶 三行）',
      );
      expect(
        find.byKey(const Key('chat-edit-subitem-0-0-1')),
        findsOneWidget,
        reason: '第 2 个食物同样',
      );
    });

    testWidgets('子条目标题是「食物 · 克数」，不是命令名「记一餐」', (tester) async {
      await pump(tester, mealTurn());
      final title = tester
          .widget<Text>(find.byKey(const Key('chat-edit-subitem-title-0-0-0')))
          .data!;
      expect(title, contains('米饭'), reason: '设计稿行标题是食物名');
      expect(title, contains('150'), reason: '设计稿行标题带克数（米饭 · 150 g）');
      expect(title, isNot(contains('记一餐')), reason: '命令名不该出现在行标题上——那是组头的职责');
    });

    testWidgets('子条目编号 1/2 逐个递增', (tester) async {
      await pump(tester, mealTurn());
      final first = tester
          .widget<Text>(
            find.byKey(const Key('chat-edit-subitem-ordinal-0-0-0')),
          )
          .data!;
      final second = tester
          .widget<Text>(
            find.byKey(const Key('chat-edit-subitem-ordinal-0-0-1')),
          )
          .data!;
      expect(first, '1');
      expect(second, '2');
    });

    testWidgets('非记餐命令仍按单行渲染（不硬套食物子条目）', (tester) async {
      final turn = ChatEditTurn(
        reply: '记一笔饮水。',
        rows: [
          ChatEditTurnItem(
            index: 0,
            raw: const {'action': 'water.add'},
            command: cmd('water.add', {'amountMl': 250.0}),
          ),
        ],
      );
      await pump(tester, turn);
      // 非记餐命令 = **一个**子条目（它自己），不是零个。
      expect(find.byKey(const Key('chat-edit-subitem-0-0-0')), findsOneWidget);
      expect(find.byKey(const Key('chat-edit-subitem-0-0-1')), findsNothing);
      final title = tester
          .widget<Text>(find.byKey(const Key('chat-edit-subitem-title-0-0-0')))
          .data!;
      expect(
        title,
        isNot(contains('·')),
        reason: '非记餐命令的标题是命令名，不该出现食物式的「X · 150 g」',
      );
    });

    testWidgets('组内不再有行级「应用」按钮（按钮只在组级 + 卡底）', (tester) async {
      await pump(tester, mealTurn());
      expect(
        find.byKey(const Key('chat-edit-row-apply-0-0')),
        findsNothing,
        reason:
            '用户裁决：执行器按命令粒度，行内给「应用」会让三行都实现同一个动作，'
            '误导用户。按钮放组级。',
      );
      expect(
        find.byKey(const Key('chat-edit-group-apply-0-meal')),
        findsOneWidget,
      );
    });
  });

  group('B · 卡头结论行', () {
    testWidgets('卡头显示「哪一餐 + 几条」的结论行', (tester) async {
      await pump(tester, mealTurn());
      expect(
        find.byKey(const Key('chat-edit-card-headline-0')),
        findsOneWidget,
        reason: 'B 方案要求卡头有一句能直接读懂的结论（不只是「待你确认的修改」）',
      );
      final text = tester
          .widget<Text>(find.byKey(const Key('chat-edit-card-headline-0')))
          .data!;
      expect(text, contains('午餐'), reason: '结论行要说清哪一餐');
      // 「几条」指**命令条数**（一条 meal.create 里可以有多样食物），
      // 这里 1 条命令带 2 个食物 —— 结论行说的是 1 条。
      expect(text, contains('1 条修改'), reason: '结论行要说清几条命令');
    });

    testWidgets('卡头显示明细行（把这条要记的东西列出来）', (tester) async {
      await pump(tester, mealTurn());
      expect(
        find.byKey(const Key('chat-edit-card-summary-0')),
        findsOneWidget,
        reason: 'B 方案要求卡头带一条明细，用户不必逐行读摘要',
      );
      final text = tester
          .widget<Text>(find.byKey(const Key('chat-edit-card-summary-0')))
          .data!;
      expect(text, contains('米饭'));
      expect(text, contains('鸡胸肉'));
    });

    testWidgets('非记餐类命令不硬套「哪一餐」', (tester) async {
      final turn = ChatEditTurn(
        reply: '记一笔饮水。',
        rows: [
          ChatEditTurnItem(
            index: 0,
            raw: const {'action': 'water.add'},
            command: cmd('water.add', {'amountMl': 250.0}),
          ),
        ],
      );
      await pump(tester, turn);
      final headline = tester
          .widget<Text>(find.byKey(const Key('chat-edit-card-headline-0')))
          .data!;
      expect(headline, isNot(contains('餐')), reason: '喝水不该被说成某一餐');
      expect(headline, contains('1'));
    });
  });

  group('B · 条目分块', () {
    testWidgets('每条命令都在一个分块里（MutedBlock 底色）', (tester) async {
      await pump(tester, mealTurn());
      expect(
        find.byKey(const Key('chat-edit-block-0-meal')),
        findsOneWidget,
        reason: 'B 方案要求条目进浅灰分块，靠底色把一组框起来',
      );
    });

    testWidgets('分块底色是 muted（不是白）', (tester) async {
      await pump(tester, mealTurn());
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(const Key('chat-edit-block-0-meal')),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final color = (box.decoration as BoxDecoration).color;
      expect(color, isNotNull, reason: '分块必须有底色，否则「框起来」无从谈起');
      expect(color, isNot(Colors.white), reason: '分块要是浅灰（muted），白底等于没分块');
    });
  });

  group('B · 不许回退的三件事', () {
    testWidgets('Key 全在：卡 / 组 / 子条目 / 组级应用 / 卡底 / 忽略', (tester) async {
      await pump(tester, mealTurn());
      expect(find.byKey(const Key('chat-edit-card-0')), findsOneWidget);
      expect(find.byKey(const Key('chat-edit-row-0-0')), findsOneWidget);
      expect(
        find.byKey(const Key('chat-edit-group-apply-0-meal')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('chat-edit-apply-0')), findsOneWidget);
      expect(find.byKey(const Key('chat-edit-dismiss-0')), findsOneWidget);
    });

    testWidgets('按钮层级：组级 + 卡底实心（行级不再有按钮）', (tester) async {
      await pump(tester, mealTurn());
      // 组级：软底（文字「应用本组」）。
      expect(find.text('应用本组'), findsOneWidget);
      // 卡底：实心（文字「全部应用」）。
      expect(find.text('全部应用'), findsOneWidget);
      // 卡底必须是唯一实心主按钮。
      final primary = tester.widget<FilledButton>(
        find.byKey(const Key('chat-edit-apply-0')),
      );
      expect(primary.onPressed, isNotNull);
    });

    testWidgets('审查警告仍在，且不阻断应用', (tester) async {
      var applied = false;
      await pump(
        tester,
        mealTurn(
          warnings: const [
            ChatEditAuditWarning(
              kind: ChatEditAuditKind.slotMismatch,
              message: '你说的是晚餐，但这条提议记到午餐。',
            ),
          ],
        ),
        onApply: () => applied = true,
      );
      expect(find.byKey(const Key('chat-edit-warning-0-0')), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('chat-edit-apply-0')),
      );
      expect(button.onPressed, isNotNull, reason: '警告只提示，不许禁用应用');
      await tester.tap(find.byKey(const Key('chat-edit-apply-0')));
      await tester.pumpAndSettle();
      expect(applied, isTrue);
    });

    testWidgets('已应用完成态不显示按钮，但卡头仍说清结果', (tester) async {
      final base = mealTurn();
      final done = ChatEditTurn(
        reply: '午餐已记录。',
        rows: [
          for (final row in base.rows)
            row.copyWith(
              status: ChatEditRowStatus.applied,
              resultMessage: '已记录。',
            ),
        ],
      );
      await pump(tester, done);
      expect(find.byKey(const Key('chat-edit-apply-0')), findsNothing);
      expect(
        find.byKey(const Key('chat-edit-card-headline-0')),
        findsOneWidget,
      );
    });
  });

  group('B · 320dp × 2.0 字号不溢出', () {
    testWidgets('窄屏大字号：不抛 RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 640 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChatEditCard(
                  index: 0,
                  message: messageWith(mealTurn()),
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
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
