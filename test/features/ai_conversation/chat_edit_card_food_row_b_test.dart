import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

/// **食材行方案 B**（2026-10-25 用户选定：「食材行选方案 B」）。
///
/// 设计稿 `food-row-formats.html` 的 B 档：
/// * **热量放大右对齐**（一眼看到多少卡）；
/// * **三大宏量用三色点**（蛋白橙 / 碳水黄 / 脂肪紫）——与应用营养卡同一套编码；
/// * 名称单独一行。
///
/// 现状（要改掉的）：`新建食材「鸡蛋水煮」：155 kcal/100g（P13/C1.1/F10.6）`——
/// 名称、热量、三个宏量全挤在一行，只有 1–2px 字号差，用户原话「挤在一起很丑」。
///
/// 本文件钉方案 B 的**可测**特征（不是主观判断）：
/// 1. 热量单独成块且**字号大于**宏量（层级拉开）；
/// 2. 三个宏量各自带**语义颜色**（`LfSemanticColors` 的 protein/carbs/fat）；
/// 3. 宏量不再是 `P13/C1.1/F10.6` 这种压缩写法；
/// 4. 原有 Key 不变（`chat-edit-subitem-title-*` 等），既有测试不受影响。
void main() {
  final registry = ChatEditCommandRegistry();

  ChatEditCommand cmd(String action, Map<String, Object> args) {
    final spec = registry.specOf(action)!;
    return ChatEditCommand(spec: spec, args: validateChatEditArgs(spec, args));
  }

  ChatEditTurn turnWith(ChatEditCommand command) => ChatEditTurn(
    reply: '准备新建食材。',
    rows: [ChatEditTurnItem(index: 0, raw: const {}, command: command)],
  );

  Future<void> pump(WidgetTester tester, ChatEditTurn turn) async {
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
                text: turn.reply,
                kind: ConversationMessageKind.editProposal,
                editTurn: turn,
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
  }

  ChatEditCommand egg() => cmd('food.create', {
    'name': '鸡蛋水煮',
    'kcalPer100g': 155.0,
    'proteinPer100g': 13.0,
    'carbsPer100g': 1.1,
    'fatPer100g': 10.6,
  });

  group('方案 B · 热量放大右对齐', () {
    testWidgets('热量有独立 Key，且字号大于宏量', (tester) async {
      await pump(tester, turnWith(egg()));
      final kcal = find.byKey(const Key('chat-edit-food-kcal-0-0'));
      expect(kcal, findsOneWidget, reason: '热量要能单独定位（方案 B 的放大块）');

      final kcalText = tester.widget<Text>(kcal);
      final kcalSize = kcalText.style!.fontSize!;

      final macro = find.byKey(const Key('chat-edit-food-macro-0-0-0'));
      expect(macro, findsOneWidget);
      final macroSize = tester.widget<Text>(macro).style!.fontSize!;

      expect(
        kcalSize,
        greaterThan(macroSize),
        reason:
            '方案 B 的核心：热量字号($kcalSize)必须大于宏量($macroSize)，'
            '否则「主次没拉开」——用户抱怨的就是这个',
      );
    });

    testWidgets('热量值正确显示（155）', (tester) async {
      await pump(tester, turnWith(egg()));
      final kcal = tester.widget<Text>(
        find.byKey(const Key('chat-edit-food-kcal-0-0')),
      );
      expect(kcal.data, contains('155'));
    });
  });

  group('方案 B · 三色点宏量', () {
    testWidgets('三个宏量各自带语义色（蛋白橙 / 碳水黄 / 脂肪紫）', (tester) async {
      await pump(tester, turnWith(egg()));
      final colors = await tester.runAsync(() async {
        final c = LfSemanticColors.light;
        return (protein: c.protein, carbs: c.carbs, fat: c.fat);
      });
      for (var i = 0; i < 3; i++) {
        final dot = find.byKey(Key('chat-edit-food-dot-0-0-$i'));
        expect(dot, findsOneWidget, reason: '第 $i 个宏量要有色点');
        // Key 就挂在 `DecoratedBox` 本身（它包着 6×6 的 SizedBox）。
        final box = tester.widget<DecoratedBox>(dot);
        final color = (box.decoration as BoxDecoration).color;
        expect(
          [colors!.protein, colors.carbs, colors.fat],
          contains(color),
          reason: '第 $i 个色点($color)必须是三色之一——与营养卡同一套编码',
        );
      }
    });

    testWidgets('宏量文字是「31g」式人话，不是 P31/C0/F3.6 压缩写法', (tester) async {
      await pump(tester, turnWith(egg()));
      final texts = [
        for (var i = 0; i < 3; i++)
          tester
              .widget<Text>(find.byKey(Key('chat-edit-food-macro-0-0-$i')))
              .data!,
      ];
      expect(texts.join(' '), isNot(contains('P13')));
      expect(texts.join(' '), isNot(contains('/C')));
      expect(texts.any((t) => t.contains('13')), isTrue, reason: '蛋白 13g 要在');
    });
  });

  group('方案 B · 不破坏既有 Key 与其它命令', () {
    testWidgets('子条目 Key 仍在（既有测试依赖）', (tester) async {
      await pump(tester, turnWith(egg()));
      expect(find.byKey(const Key('chat-edit-subitem-0-0-0')), findsOneWidget);
      expect(
        find.byKey(const Key('chat-edit-subitem-title-0-0-0')),
        findsOneWidget,
      );
    });

    testWidgets('记餐行仍是「食物 · 克数」（不套食材版式）', (tester) async {
      await pump(
        tester,
        turnWith(
          cmd('meal.create', {
            'slot': 'lunch',
            'items': [
              {'food': '米饭', 'grams': 150.0},
            ],
          }),
        ),
      );
      expect(
        find.byKey(const Key('chat-edit-food-kcal-0-0')),
        findsNothing,
        reason: '记餐行没有热量数据，不该出现食材热量块',
      );
      final title = tester
          .widget<Text>(find.byKey(const Key('chat-edit-subitem-title-0-0-0')))
          .data!;
      expect(title, contains('米饭'));
      expect(title, contains('150'));
    });

    testWidgets('窄屏 320dp × 2.0 不溢出', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 900),
            textScaler: TextScaler.linear(2.0),
          ),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ChatEditCard(
                  index: 0,
                  message: ConversationMessage(
                    id: 'm',
                    role: ConversationRole.assistant,
                    text: 'x',
                    kind: ConversationMessageKind.editProposal,
                    editTurn: turnWith(egg()),
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
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
