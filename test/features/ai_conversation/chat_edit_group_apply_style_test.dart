import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_conversation/presentation/chat_edit_card.dart';

/// 组头「应用本组」的样式契约（2026-10-24，**两轮演变，如实记录**）。
///
/// **第一轮**（用户：「要应用本组，但是按钮样式要显眼一些，现在纯文本看着
/// 难受」）⇒ 从 `LfTextButton`（透明底）改成 `LfSoftButton`（brandSoft 软底）。
///
/// **第二轮**（用户选定编辑卡方案 B：「你这改的根本不是方案 b，能不能 1:1
/// 对应修改」）⇒ 设计稿 B 的组级按钮是 `.mini`：**白底 + 1px mint-300 描边
/// + 12px w600 品牌字**，不是软底块。已按稿实现。
///
/// 两轮的共同要求没变，本文件钉住的仍是这些**可测**判据：
/// 1. **有可见底色或描边**（不是透明空底）——「看着难受」的根因是纯文本；
/// 2. **可点面积 ≥ 44dp**（`LfDimens.minTouchTarget`，视觉可以小、命中不能小）；
/// 3. **视觉层级低于主行动**：卡底「全部应用」是唯一实心主钮；
/// 4. Key 契约不变（`chat-edit-group-apply-<card>-<kind>`），点击只应用本组。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 10, 24, 2);

  /// 三组各一条（meal / food / other），只用来渲染组头。
  ChatEditTurn turn() => parseChatEditTurn(
    jsonEncode({
      'reply': '准备记录',
      'edits': [
        {
          'action': 'meal.create',
          // 与 `ai_conversation_page_test` 同一份信封口径：`items[].food`
          // 是食物名（不是 `foodName`），缺了会被解码器判「缺食物名」。
          'args': {
            'slot': '午餐',
            'items': [
              {'food': '米饭', 'grams': 100},
            ],
          },
        },
        {
          'action': 'food.create',
          'args': {
            'name': '自制酱',
            'kcalPer100g': 100,
            'proteinPer100g': 1,
            'carbsPer100g': 1,
            'fatPer100g': 1,
          },
        },
        {
          'action': 'water.add',
          'args': {'amountMl': 250},
        },
      ],
    }),
    ChatEditCommandRegistry(),
  )!;

  Widget host(ChatEditCard card) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: card)),
  );

  ChatEditCard card({
    ValueChanged<Set<int>>? onApplyRows,
    bool applying = false,
  }) {
    final t = turn();
    return ChatEditCard(
      index: 0,
      message: ConversationMessage(
        id: 'edit',
        role: ConversationRole.assistant,
        text: '准备记录',
        createdAt: now,
        kind: ConversationMessageKind.editProposal,
        editTurn: applying
            ? ChatEditTurn(
                reply: t.reply,
                rows: [
                  for (final row in t.rows)
                    row.copyWith(status: ChatEditRowStatus.applying),
                ],
                suggestions: t.suggestions,
              )
            : t,
      ),
      onApply: () {},
      onApplyRows: onApplyRows ?? (_) {},
      onDismiss: () {},
      onApplySuggestion: (_) {},
      onRepair: (_) {},
    );
  }

  const mealGroupKey = Key('chat-edit-group-apply-0-meal');

  /// 取组头按钮的**可见装饰**（设计稿 `.mini` = 带描边的 Container）。
  BoxDecoration groupApplyDecoration(WidgetTester tester) {
    final container = find.descendant(
      of: find.byKey(mealGroupKey),
      matching: find.byType(Container),
    );
    final widget = tester.widget<Container>(container.first);
    return widget.decoration! as BoxDecoration;
  }

  group('组头「应用本组」要显眼（不是纯文本）', () {
    testWidgets('有可见底色（不再是透明空底）', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(card()));
      await tester.pumpAndSettle();

      final button = find.byKey(mealGroupKey);
      expect(button, findsOneWidget, reason: '组头按钮仍要在（用户要保留本组应用）');

      // 设计稿 `.mini`：白底 + mint-300 描边。判据取**渲染出来的装饰**——
      // 底色非全透明 **且** 有可见描边（只靠底色在白卡上会看不见）。
      final decoration = groupApplyDecoration(tester);
      final bg = decoration.color;
      final border = decoration.border;
      expect(bg, isNotNull, reason: '「应用本组」必须有自己的底色（纯文本看着难受）');
      expect(bg!.a, greaterThan(0), reason: '底色不得全透明（alpha=${bg.a}）');
      expect(
        border,
        isNotNull,
        reason: '设计稿 .mini 是**描边**钮：白底 + 1px mint-300，缺描边就不是这个档',
      );
    });

    testWidgets('可点面积 ≥ 44dp', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(card()));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byKey(mealGroupKey));
      expect(
        size.height,
        greaterThanOrEqualTo(LfDimens.minTouchTarget - 0.5),
        reason: '组级批量动作的命中高度 ${size.height} < 44（触达线）',
      );
    });

    testWidgets('取 mini 描边档（白底 + 品牌字），不与实心主钮抢层级', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(card()));
      await tester.pumpAndSettle();

      final decoration = groupApplyDecoration(tester);
      // 底色是**卡片白**（不是品牌软底）：设计稿 .mini 背景 = #fff。
      expect(
        decoration.color,
        const Color(0xFFFFFFFF),
        reason: '设计稿 .mini：白底。软底块是上一轮的方案，已按稿改回描边钮',
      );
      // 描边是 mint-300。
      final side = (decoration.border! as Border).top;
      expect(
        side.color,
        LfColors.mint(Brightness.light).tone(300),
        reason: '设计稿 .mini：border 1px mint-300',
      );
      // 文字是品牌色。
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(mealGroupKey),
          matching: find.text('应用本组'),
        ),
      );
      expect(text.style?.color, LfColors.mintText(Brightness.light));
      // 明确**不是**主行动：卡底「全部应用」仍是实心 FilledButton。
      expect(
        find.descendant(
          of: find.byKey(const Key('chat-edit-card-0')),
          matching: find.byType(FilledButton),
        ),
        findsWidgets,
        reason: '卡底「全部应用」应仍是实心主钮（组级动作不抢它）',
      );
    });

    testWidgets('点击仍只应用本组（行为不变）', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var received = <int>{};
      await tester.pumpWidget(
        host(card(onApplyRows: (rows) => received = rows)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(mealGroupKey));
      await tester.pumpAndSettle();

      expect(received, {0}, reason: '组级应用仍只提交本组索引（行为不能因换样式而变）');
    });

    testWidgets('忙碌时组头按钮不渲染（与行级一致）', (tester) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(card(applying: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(mealGroupKey), findsNothing);
    });
  });
}
