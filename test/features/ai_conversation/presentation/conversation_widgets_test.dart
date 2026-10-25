import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/lf_chat_bubbles.dart';
import 'package:localfit_ai/app/design/widgets/lf_chat_input.dart';

/// AI 对话页的视觉构件（docs/21 §3.4 / §5.7）。
///
/// 这些件是**受控组件**：页面持有状态，组件只负责几何与 Key。所以这里
/// 全部用 `MaterialApp(home:)` 直挂（`context.lf` 在裸 MaterialApp 下会退化
/// 到 light 语义色，足以断言结构与文案）。
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  double screenCenterX(WidgetTester tester) =>
      tester.view.physicalSize.width / tester.view.devicePixelRatio / 2;

  group('消息气泡（docs/21 §3.4）', () {
    testWidgets('AI 气泡左对齐、渲染正文', (tester) async {
      await pump(tester, const AiMessageBubble(text: '你好呀'));

      expect(find.text('你好呀'), findsOneWidget);
      expect(
        tester.getCenter(find.text('你好呀')).dx,
        lessThan(screenCenterX(tester)),
      );
    });

    testWidgets('用户气泡右对齐、可带 trailing', (tester) async {
      await pump(
        tester,
        const UserMessageBubble(
          text: '我午饭吃了鸡胸肉',
          trailing: SizedBox(key: Key('trailing-slot'), height: 10),
        ),
      );

      expect(find.text('我午饭吃了鸡胸肉'), findsOneWidget);
      expect(find.byKey(const Key('trailing-slot')), findsOneWidget);
      expect(
        tester.getCenter(find.text('我午饭吃了鸡胸肉')).dx,
        greaterThan(screenCenterX(tester)),
      );
    });

    // 2026-10-16 用户：「对话内容要能长按复制」——气泡自身不碰剪贴板，只把
    // 长按交给页面（页面拿剪贴板 + 提示）。
    testWidgets('AI / 用户气泡长按都回调（复制入口）', (tester) async {
      var ai = 0;
      var user = 0;
      await pump(tester, AiMessageBubble(text: '长按我', onLongPress: () => ai++));
      await tester.longPress(find.text('长按我'));
      expect(ai, 1);

      await pump(
        tester,
        UserMessageBubble(text: '我也能长按', onLongPress: () => user++),
      );
      await tester.longPress(find.text('我也能长按'));
      expect(user, 1);
    });

    testWidgets('AiMessageRow 带头像，内容在同一行', (tester) async {
      await pump(
        tester,
        const AiMessageRow(child: AiMessageBubble(text: '带头像的消息')),
      );

      expect(find.byType(AiMascotAvatar), findsOneWidget);
      expect(find.text('带头像的消息'), findsOneWidget);
      final avatar = tester.getRect(find.byType(AiMascotAvatar));
      final bubble = tester.getRect(find.byType(AiMessageBubble));
      expect(avatar.right, lessThanOrEqualTo(bubble.left));
      expect(avatar.width, 36);
      expect(avatar.height, 36);
    });

    testWidgets('正在输入：默认 Key 是 ai-chat-typing，三个点', (tester) async {
      await pump(tester, const TypingIndicator());

      expect(find.byKey(const Key('ai-chat-typing')), findsOneWidget);
      final dots = find.descendant(
        of: find.byType(TypingIndicator),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxWidth == 6,
        ),
      );
      expect(dots, findsNWidgets(3));
    });

    // 2026-10-16 用户：「功能卡片太丑，要做成小卡片」——三格由「大圆图标 +
    // 文案」竖排堆叠改为**三张紧凑小卡横排**（图标块 + 文案同一行）。
    testWidgets('功能卡：三张小卡横排、等宽、明显更矮', (tester) async {
      // 真实用法是「对话滚动区里的一块」：套 `SingleChildScrollView` 才是
      // 无界高度，直接挂 Scaffold 会被 Column 的 max 撑满整屏、量不到块高。
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FeatureCardMessage(
                features: [
                  (Icons.restaurant, '饮食'),
                  (Icons.fitness_center, '训练'),
                  (Icons.insights, '趋势'),
                ],
              ),
            ),
          ),
        ),
      );

      final card = find.byKey(const Key('ai-chat-feature-card'));
      expect(card, findsOneWidget);
      final rects = [
        for (final label in ['饮食', '训练', '趋势'])
          tester.getRect(find.text(label)),
      ];
      // 同一行：三条文案的 y 中心一致（不再各占一列的上下堆叠）。
      expect(rects[0].center.dy, closeTo(rects[1].center.dy, 0.5));
      expect(rects[1].center.dy, closeTo(rects[2].center.dy, 0.5));
      // 等宽分栏：相邻文案中心间距相等。
      expect(
        rects[1].center.dx - rects[0].center.dx,
        closeTo(rects[2].center.dx - rects[1].center.dx, 0.5),
      );
      // 图标与文案**同一行**（左图标 + 右文案）——旧形态是图标在上、
      // 文案在下。
      for (final (icon, label) in const [
        (Icons.restaurant, '饮食'),
        (Icons.fitness_center, '训练'),
        (Icons.insights, '趋势'),
      ]) {
        final iconRect = tester.getRect(find.byIcon(icon));
        final labelRect = tester.getRect(find.text(label));
        expect(
          iconRect.center.dy,
          closeTo(labelRect.center.dy, 1.5),
          reason: label,
        );
        expect(
          iconRect.right,
          lessThanOrEqualTo(labelRect.left + 1),
          reason: label,
        );
      }
      // 紧凑：整块高度远低于「40 圆图标 + 6 间距 + 一行文案 + 上下 12」的
      // 竖排堆叠（≥ 88dp）。
      expect(tester.getSize(card).height, lessThan(88));
    });

    testWidgets('功能卡：默认 Key + 两个可点区（点击查看 / 主按钮）', (tester) async {
      var primaryTaps = 0;
      var trailingTaps = 0;
      await pump(
        tester,
        FeatureCardMessage(
          features: const [
            (Icons.restaurant, '饮食'),
            (Icons.fitness_center, '训练'),
            (Icons.insights, '趋势'),
          ],
          onPrimaryTap: () => primaryTaps++,
          onTrailingTap: () => trailingTaps++,
        ),
      );

      expect(find.byKey(const Key('ai-chat-feature-card')), findsOneWidget);
      expect(find.text('立即查看专属理想方案'), findsOneWidget);
      for (final label in ['饮食', '训练', '趋势']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.byKey(const Key('cta-write-plan')));
      await tester.tap(find.byKey(const Key('feature-card-view')));
      expect(primaryTaps, 1);
      expect(trailingTaps, 1);
    });

    testWidgets('图片消息：180×140 缩略 + 文件名药丸 + 对勾徽章 + 说明文字', (tester) async {
      await pump(
        tester,
        ImageMessage(
          image: const SizedBox.expand(key: Key('fake-thumb')),
          fileName: 'photo_20261001_120000_ab12.jpg',
          caption: '这是午饭',
          sent: true,
        ),
      );

      expect(find.byKey(const Key('fake-thumb')), findsOneWidget);
      expect(find.text('photo_20261001_120000_ab12.jpg'), findsOneWidget);
      expect(find.text('这是午饭'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      final thumb = tester.getRect(find.byKey(const Key('fake-thumb')));
      expect(thumb.width, 180);
      expect(thumb.height, 140);
      expect(thumb.right, greaterThan(screenCenterX(tester)));
    });

    testWidgets('图片消息：发送中不显示对勾徽章', (tester) async {
      await pump(
        tester,
        ImageMessage(
          image: const SizedBox.expand(),
          fileName: 'a.jpg',
          sent: false,
        ),
      );

      expect(find.byIcon(Icons.check), findsNothing);
    });
  });

  group('输入栏（P10：语音已删，单状态）', () {
    testWidgets('默认行：图片 / 文字输入 / 发送 三件齐备，无麦克风', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(
        tester,
        ChatInputBar(
          controller: controller,
          onSendText: (_) {},
          onPickImage: () {},
        ),
      );

      expect(find.byKey(const Key('input-row-text')), findsOneWidget);
      expect(find.byKey(const Key('input-row-voice')), findsNothing);
      expect(find.byKey(const Key('btn-image-upload')), findsOneWidget);
      // P10（需求 36）：麦克风按钮与录音行整族删除。
      expect(find.byKey(const Key('btn-voice-input')), findsNothing);
      expect(find.text('对话记录饮食和运动'), findsOneWidget);
    });

    testWidgets('发送按钮回传输入框当前文本', (tester) async {
      final controller = TextEditingController(text: '晚饭吃了三明治');
      addTearDown(controller.dispose);
      String? sent;
      await pump(
        tester,
        ChatInputBar(controller: controller, onSendText: (text) => sent = text),
      );

      await tester.tap(find.byKey(const Key('btn-send')));
      expect(sent, '晚饭吃了三明治');
    });

    testWidgets('AI 回复中：发送钮变停止钮，点击触发停止', (tester) async {
      final controller = TextEditingController(text: '在吗');
      addTearDown(controller.dispose);
      var stops = 0;
      await pump(
        tester,
        ChatInputBar(
          controller: controller,
          sending: true,
          onStop: () => stops++,
          onSendText: (_) {},
        ),
      );

      expect(find.byKey(const Key('btn-stop')), findsOneWidget);
      expect(find.byKey(const Key('btn-send')), findsNothing);

      await tester.tap(find.byKey(const Key('btn-stop')));
      expect(stops, 1);
    });
  });

  group('快捷 chip / 图片预览条', () {
    // 2026-10-16 用户裁决：「手动记录」这枚 chip 下线，保留其余三枚并
    // **等宽占满一整行**（原先是四枚横滑）。判据随之改写为新事实。
    // 2026-10-23 用户：第一枚「拍照识别」→「确认应用」。
    testWidgets('三枚 chip 等宽铺满整行、Key 与回传枚举', (tester) async {
      final taps = <ChatQuickChip>[];
      await pump(tester, ChatQuickChips(onChipTap: taps.add));

      // `RV4-R16`（`docs/56` §8 方案 A）：前两枚换成「今天还剩多少 / 记一餐」，
      // 「确认应用」与「我可以吃吗」退役（前者在 R15 行级应用后多余，
      // 后者只是把 5 个字塞进输入框）。
      expect(find.byKey(const Key('ai-chat-chip-remaining')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-chip-log-meal')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-chip-ai-create')), findsOneWidget);
      expect(find.byKey(const Key('ai-chat-chip-apply-edits')), findsNothing);
      expect(find.byKey(const Key('ai-chat-chip-can-i-eat')), findsNothing);
      expect(find.byKey(const Key('ai-chat-chip-manual')), findsNothing);
      expect(find.byKey(const Key('cta-photo-scan')), findsNothing);
      expect(find.text('手动记录'), findsNothing);
      expect(find.text('拍照识别'), findsNothing);
      expect(find.text('确认应用'), findsNothing);
      expect(find.text('我可以吃吗'), findsNothing);
      expect(find.text('今天还剩多少'), findsOneWidget);
      expect(find.text('记一餐'), findsOneWidget);
      expect(find.text('AI 创作'), findsOneWidget);

      // 等宽 + 铺满：三枚各占「内容宽 − 2 个间距」的三分之一
      // （内容宽 = 行宽 − 左右 spaceMedium）。
      const keys = [
        'ai-chat-chip-remaining',
        'ai-chat-chip-log-meal',
        'ai-chat-chip-ai-create',
      ];
      final barWidth = tester
          .getSize(find.byKey(const Key('chat-quick-chips')))
          .width;
      final expected =
          (barWidth - 2 * LfDimens.spaceMedium - 2 * LfDimens.spaceSmall) / 3;
      for (final key in keys) {
        final pill = tester.getSize(find.byKey(Key(key)));
        expect(pill.width, closeTo(expected, 0.5), reason: key);
      }
      // 三枚同一行：y 中心一致（不再横滑）。
      final centers = keys
          .map((k) => tester.getCenter(find.byKey(Key(k))).dy)
          .toList();
      expect(centers[0], closeTo(centers[1], 0.5));
      expect(centers[1], closeTo(centers[2], 0.5));

      await tester.tap(find.byKey(const Key('ai-chat-chip-remaining')));
      await tester.tap(find.byKey(const Key('ai-chat-chip-log-meal')));
      await tester.tap(find.byKey(const Key('ai-chat-chip-ai-create')));
      expect(taps, [
        ChatQuickChip.remainingToday,
        ChatQuickChip.logMeal,
        ChatQuickChip.aiCreate,
      ]);
    });

    testWidgets('预览条：一张图的文件名 + 移除/添加回调', (tester) async {
      var removes = 0;
      var adds = 0;
      await pump(
        tester,
        ImagePreviewStrip(
          fileName: 'photo_20261001_120000_ab12.jpg',
          thumbnail: const SizedBox.expand(),
          onRemove: () => removes++,
          onAdd: () => adds++,
        ),
      );

      expect(find.byKey(const Key('image-preview-bar')), findsOneWidget);
      expect(find.text('已添加 1 张图片'), findsOneWidget);
      expect(find.text('photo_20261001_120000_ab12.jpg'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn-remove-image')));
      await tester.tap(find.byKey(const Key('add-image')));
      expect(removes, 1);
      expect(adds, 1);
    });

    testWidgets('免责声明已删：ChatDisclaimer 不存在（P10 需求 35）', (tester) async {
      // P10：免责声明整件从 lf_chat_input.dart 删除。
      // 静态守卫：类不存在 ⇒ 引用即编译失败；运行时守卫见
      // ai_conversation_page_test 的「顶栏四件 + 输入区三件」。
      expect(find.byKey(const Key('ai-chat-disclaimer')), findsNothing);
      expect(find.text('内容由AI生成，请勿从事违法活动'), findsNothing);
    });
  });
}
