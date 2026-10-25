import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/food_scan/presentation/chat_message_ui.dart';

/// 对话式识别气泡（docs/21 §5.4）。
///
/// 锁住的是「谁能说话、说什么」的语义，而不是颜色本身：
/// - 用户消息靠右、AI 消息靠左（对齐是唯一的方向线索）；
/// - 五种消息类型都能渲染且不抛异常（含 error 的兜底文案）；
/// - 相对时间文案边界正确（刚刚 / 分钟 / 小时 / 天）。
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    bool dark = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('用户消息靠右，AI 消息靠左', (tester) async {
    await pump(
      tester,
      const ChatMessageUI(message: '这是我拍的午餐', type: MessageType.user),
    );
    final userAlign = tester.widget<Align>(
      find
          .ancestor(of: find.text('这是我拍的午餐'), matching: find.byType(Align))
          .first,
    );
    expect(userAlign.alignment, Alignment.centerRight);

    await pump(
      tester,
      const ChatMessageUI(message: '识别到红烧排骨', type: MessageType.ai),
    );
    final aiAlign = tester.widget<Align>(
      find
          .ancestor(of: find.text('识别到红烧排骨'), matching: find.byType(Align))
          .first,
    );
    expect(aiAlign.alignment, Alignment.centerLeft);
  });

  testWidgets('AI 消息带头像标签，可关闭头像', (tester) async {
    await pump(
      tester,
      const ChatMessageUI(message: '结果如下', type: MessageType.ai),
    );
    expect(find.text('AI 助手'), findsOneWidget);
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);

    await pump(
      tester,
      const ChatMessageUI(
        message: '结果如下',
        type: MessageType.ai,
        showAvatar: false,
      ),
    );
    expect(find.text('AI 助手'), findsNothing);
  });

  testWidgets('错误类型在没有 errorMessage 时回落到 message', (tester) async {
    await pump(
      tester,
      const ChatMessageUI(message: '网络连接不可用。', type: MessageType.error),
    );
    expect(find.text('网络连接不可用。'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('错误类型优先显示 errorMessage', (tester) async {
    await pump(
      tester,
      const ChatMessageUI(
        message: '忽略我',
        errorMessage: '真实原因在这里。',
        type: MessageType.error,
      ),
    );
    expect(find.text('真实原因在这里。'), findsOneWidget);
    expect(find.text('忽略我'), findsNothing);
  });

  testWidgets('加载类型有进度指示，aiTyping 也显示输入中', (tester) async {
    // 转圈动画是无限循环，pumpAndSettle 永远不会 settle —— 这两条用 pump。
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ChatMessageUI(message: '正在分析…', type: MessageType.loading),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: ChatMessageUI(
            message: '请稍候',
            type: MessageType.ai,
            aiTyping: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('AI 正在输入…'), findsOneWidget);
  });

  testWidgets('系统消息居中渲染', (tester) async {
    await pump(
      tester,
      const ChatMessageUI(message: '已切换到手动记餐。', type: MessageType.system),
    );
    expect(find.text('已切换到手动记餐。'), findsOneWidget);
  });

  testWidgets('带时间戳时显示相对时间', (tester) async {
    await pump(
      tester,
      ChatMessageUI(
        message: '刚拍的',
        type: MessageType.user,
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    );
    expect(find.text('5 分钟前'), findsOneWidget);
  });

  group('相对时间文案', () {
    final now = DateTime(2026, 9, 22, 12);

    test('一分钟内是「刚刚」', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(seconds: 30)), now: now),
        '刚刚',
      );
    });

    test('一小时以内按分钟', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(minutes: 42)), now: now),
        '42 分钟前',
      );
    });

    test('一天以内按小时', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(hours: 5)), now: now),
        '5 小时前',
      );
    });

    test('超过一天按天', () {
      expect(
        formatRelativeTime(now.subtract(const Duration(days: 3)), now: now),
        '3 天前',
      );
    });
  });

  testWidgets('用户气泡用品牌色实底（语义层 primary）', (tester) async {
    await pump(
      tester,
      const ChatMessageUI(message: '你好', type: MessageType.user),
    );
    final box = tester.widget<Container>(
      find
          .ancestor(of: find.text('你好'), matching: find.byType(Container))
          .first,
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(
      decoration.color,
      LfSemanticColors.light.primary,
      reason: '用户气泡应取品牌 500 档（语义层 primary 的亮色值）',
    );
    // 字色也必须走 token：设计稿是 `var(--lf-primary-foreground)`；写死
    // `Colors.white` 会在暗色主题下与主题给的 primaryForeground 不一致。
    expect(
      tester.widget<Text>(find.text('你好')).style?.color,
      LfSemanticColors.light.primaryForeground,
    );
  });

  testWidgets('暗色下用户气泡字色仍是主题给的 primaryForeground（不是写死白）', (tester) async {
    // 亮色 primaryForeground 恰好就是纯白，写死 `Colors.white` 在亮色下是
    // **等价变异**（观测不到差别）；只有暗色档（近黑 #0F1412）才把它区分开——
    // 所以这条断言必须挂在暗色宿主上。
    await pump(
      tester,
      const ChatMessageUI(message: '你好', type: MessageType.user),
      dark: true,
    );
    final bubbleColor = tester.widget<Text>(find.text('你好')).style?.color;
    expect(bubbleColor, LfSemanticColors.dark.primaryForeground);
    expect(bubbleColor, isNot(Colors.white));
  });
}
