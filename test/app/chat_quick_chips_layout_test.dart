import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_chat_input.dart';

/// **快捷 chip 的文字不换行、水平居中**（2026-10-25 用户）。
///
/// 用户原话：「今天还剩多少的按钮文字换行了，调整一下三个按钮的大小，
/// 根据文字长度来调整，另外让几个按钮的文字水平居中」。
///
/// 踩过的两个坑（都记在这里，避免下次又走一遍）：
/// 1. 「按内容宽度 + Wrap」那一版让「今天还剩多少」在 320dp × 2.0× 下
///    溢出 170px（`Wrap` 不会收缩子项）；
/// 2. 所以布局**保留等分**（`Expanded`，验证过不溢出），只把文字改成
///    单行 + 居中 + `FittedBox.scaleDown` 兜底。
void main() {
  Future<void> pump(
    WidgetTester tester, {
    double scale = 1.0,
    double width = 390,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 640),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(body: ChatQuickChips(onChipTap: (_) {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Iterable<Text> chipTexts(WidgetTester tester) => tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const Key('chat-quick-chips')),
      matching: find.byType(Text),
    ),
  );

  testWidgets('三枚文字都单行不折行（softWrap: false）', (tester) async {
    await pump(tester);
    final texts = chipTexts(tester).toList();
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(
        text.softWrap,
        isFalse,
        reason: '「${text.data}」必须单行——用户实测「今天还剩多少」被挤成两行',
      );
    }
  });

  testWidgets('三枚文字都水平居中', (tester) async {
    await pump(tester);
    for (final text in chipTexts(tester)) {
      expect(text.textAlign, TextAlign.center, reason: '「${text.data}」要居中');
    }
  });

  testWidgets('窄屏 320dp × 2.0 字号：不溢出', (tester) async {
    await pump(tester, scale: 2.0, width: 320);
    expect(
      tester.takeException(),
      isNull,
      reason: '按内容宽 + Wrap 那一版在这里溢出过 170px，别退回去',
    );
  });

  testWidgets('三枚 chip 都存在且可点', (tester) async {
    final tapped = <ChatQuickChip>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: ChatQuickChips(onChipTap: tapped.add)),
      ),
    );
    await tester.pumpAndSettle();
    for (final key in const [
      'ai-chat-chip-remaining',
      'ai-chat-chip-log-meal',
      'ai-chat-chip-ai-create',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget);
    }
    await tester.tap(find.byKey(const Key('ai-chat-chip-remaining')));
    await tester.pumpAndSettle();
    expect(tapped, [ChatQuickChip.remainingToday]);
  });
}
