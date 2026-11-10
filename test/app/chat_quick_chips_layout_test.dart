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

  // 8c（docs/60 §3）：**按文字长度调整 chip 宽度**——三个 chip 现在等分（各 1/3），
  // 用户要的是「文字长的宽一点」。上一轮退成等分是为了不溢出（按内容宽 + Wrap
  // 那一版在 320dp × 2.0× 溢出 170px），所以这一轮用的是**有条件下的内容宽**：
  // 够宽就按内容排、居中；不够宽才回落等分。
  group('8c 按文字长度自适应宽度', () {
    testWidgets('390dp：三枚宽度不相等（按内容宽，不再等分）', (tester) async {
      await pump(tester);
      final rects = [
        for (final key in const [
          'ai-chat-chip-remaining',
          'ai-chat-chip-log-meal',
          'ai-chat-chip-ai-create',
        ])
          tester.getRect(find.byKey(Key(key))),
      ];
      expect(
        rects.map((r) => r.width).toSet().length,
        greaterThan(1),
        reason: '三枚等宽 = 没做「按文字长度调整」；「今天还剩多少」6 字、',
      );
      expect(
        rects[0].width,
        greaterThan(rects[1].width),
        reason: '「今天还剩多少」比「记一餐」长，必须更宽',
      );
    });

    testWidgets('390dp：整行居中（左右留白大致相等）', (tester) async {
      await pump(tester);
      final row = tester.getRect(find.byKey(const Key('chat-quick-chips')));
      final first = tester.getRect(
        find.byKey(const Key('ai-chat-chip-remaining')),
      );
      final last = tester.getRect(
        find.byKey(const Key('ai-chat-chip-ai-create')),
      );
      expect(
        (first.left - row.left) - (row.right - last.right),
        closeTo(0, 12),
        reason: '按内容宽排版时必须居中，否则右侧拖一条大空白',
      );
    });

    testWidgets('320dp × 2.0×：不溢出且仍单行居中（回落等分）', (tester) async {
      await pump(tester, scale: 2.0, width: 320);
      expect(
        tester.takeException(),
        isNull,
        reason: '「按内容宽 + Wrap」那一版在这里溢出过 170px，别退回去',
      );
      for (final text in chipTexts(tester)) {
        expect(text.softWrap, isFalse);
        expect(text.textAlign, TextAlign.center);
      }
    });
  });
}
