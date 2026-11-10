import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/lf_chat_bubbles.dart';

/// 需求 3（docs/60 §6）：**聊天里的图片要能点开看大图**。
///
/// 现状：`ImageMessage` 只渲染 180×140 缩略，**没有点击**（全仓
/// `InteractiveViewer` 0 命中）——用户收到 AI 分析用的菜照时看不清细节。
///
/// 方案（照 docs/60 §6）：点缩略图 → 全屏 `InteractiveViewer`（双指缩放），
/// 点背景/下滑关闭；全屏层的 Key 是 `ai-chat-image-zoom-<index>`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double scale = 1.0,
    double width = 390,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 700),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('点缩略图 → 全屏 InteractiveViewer（可缩放）', (tester) async {
    var zoomOpened = 0;
    await pump(
      tester,
      ImageMessage(
        key: const Key('ai-chat-image-0'),
        image: const SizedBox(
          key: Key('fake-thumb'),
          width: 100,
          height: 80,
          child: ColoredBox(color: Color(0xFF00FF00)),
        ),
        caption: '这是午饭',
        onZoom: () => zoomOpened++,
      ),
    );

    expect(
      find.byKey(const Key('ai-chat-image-zoom-0')),
      findsNothing,
      reason: '点之前不该有全屏层',
    );
    // 量的是缩略图本体（180×140 那块）：点它的正中央必须命中。
    await tester.tap(find.byKey(const Key('ai-chat-image-zoom-tap')));
    await tester.pumpAndSettle();
    // 回调必须真的被触发（页面据此打开全屏层）。
    expect(zoomOpened, 1, reason: '点缩略图没有反应——用户看不了大图');
  });

  testWidgets('未接线（onZoom 为 null）时不该有假的可点态', (tester) async {
    await pump(
      tester,
      ImageMessage(
        key: const Key('ai-chat-image-0'),
        image: const SizedBox(
          width: 100,
          height: 80,
          child: ColoredBox(color: Color(0xFF00FF00)),
        ),
      ),
    );
    expect(
      find.byKey(const Key('ai-chat-image-zoom-tap')),
      findsNothing,
      reason: 'onZoom 为空时不摆可点态（同一纪律：不给点了没反应的入口）',
    );
    expect(
      find.byIcon(Icons.zoom_out_map),
      findsNothing,
      reason: '不画放大角标——那是一句「这里能点」的承诺',
    );
  });

  testWidgets('可点态不再画角标（2026-10-31 用户：图片消息只留图）', (tester) async {
    await pump(
      tester,
      ImageMessage(
        key: const Key('ai-chat-image-0'),
        image: const SizedBox(
          width: 100,
          height: 80,
          child: ColoredBox(color: Color(0xFF00FF00)),
        ),
        onZoom: () {},
      ),
    );
    expect(
      find.byIcon(Icons.zoom_out_map),
      findsNothing,
      reason: '角标已随「只留图」退役；可点性由整图 InkWell 承担',
    );
    expect(find.byKey(const Key('ai-chat-image-zoom-tap')), findsOneWidget);
  });

  testWidgets('全屏查看层：InteractiveViewer + 可关闭 + 按屏尺寸铺满', (tester) async {
    await pump(
      tester,
      const ChatImageZoomView(
        key: Key('ai-chat-image-zoom-0'),
        image: ColoredBox(color: Color(0xFF00FF00)),
      ),
    );

    expect(
      find.byType(InteractiveViewer),
      findsOneWidget,
      reason: '全屏层必须可缩放（双指）——静态大图看细节仍然不够',
    );
    final viewer = tester.getRect(find.byType(InteractiveViewer));
    expect(viewer.width, greaterThan(200));
    // 关闭按钮（点击背景也能关，但背景是黑底，给一枚明确的关闭键）。
    expect(find.byKey(const Key('ai-chat-image-zoom-close')), findsOneWidget);
  });

  testWidgets('320dp × 2.0×：全屏层不溢出', (tester) async {
    await pump(
      tester,
      const ChatImageZoomView(
        key: Key('ai-chat-image-zoom-0'),
        image: ColoredBox(color: Color(0xFF00FF00)),
      ),
      scale: 2.0,
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('全屏层关闭键达到最小触达 44dp', (tester) async {
    await pump(
      tester,
      const ChatImageZoomView(
        key: Key('ai-chat-image-zoom-0'),
        image: ColoredBox(color: Color(0xFF00FF00)),
      ),
    );
    final close = tester.getRect(
      find.byKey(const Key('ai-chat-image-zoom-close')),
    );
    expect(close.width, greaterThanOrEqualTo(LfDimens.minTouchTarget));
    expect(close.height, greaterThanOrEqualTo(LfDimens.minTouchTarget));
  });
}
