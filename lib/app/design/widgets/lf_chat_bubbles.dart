import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_markdown.dart';

/// AI 对话消息形态（docs/21 §3.4）。
///
/// AI 侧：白底 + 描边 + 16 圆角（左上角 4），14px。

/// AI 吉祥物头像（AI 工作.html：36px `mint-100` 圆 + primary 色 sprout）。
///
/// 设计源用 lucide `sprout`；Material 图标集里最接近的叶芽是 `Icons.eco`
/// （同一 mint 家族下形状语义一致）。顶栏用 [AiMascotAvatar.size] = 32。
class AiMascotAvatar extends StatelessWidget {
  const AiMascotAvatar({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: mint.tone(100), shape: BoxShape.circle),
      // 纯装饰：旁边就是消息气泡的语义内容，不重复播报（§5.8.3）。
      child: ExcludeSemantics(
        child: Icon(Icons.eco, size: size * 0.56, color: c.primary),
      ),
    );
  }
}

/// AI 消息行：头像 + 内容（docs/21 §5.7 六种形态的左列）。
///
/// 一条消息一行，Key 由页面给（`ai-chat-message-<n>`）；头像不参与语义树。
class AiMessageRow extends StatelessWidget {
  const AiMessageRow({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AiMascotAvatar(),
        const SizedBox(width: LfDimens.spaceSmall),
        Flexible(child: child),
      ],
    );
  }
}

/// AI 气泡（白底 + 描边 + 16 圆角，左上角 4）。
///
/// [onLongPress]：长按整条气泡（2026-10-16 用户「对话内容要能长按复制」）。
/// 气泡自身**不碰剪贴板**——它只把长按转给页面，剪贴板与提示由页面负责
/// （与其它受控件的分工一致）。
///
/// [footer]（docs/66 §6.1）：气泡内**底行、右对齐**的插槽（「生成应用卡片」
/// 按钮挂在这里，视觉上属于内容卡）。null = 不占位（既有形态逐字节不变）。
/// 长按复制由外层手势处理，footer 里的按钮点击优先命中（内层子树先收到）。
class AiMessageBubble extends StatelessWidget {
  const AiMessageBubble({
    super.key,
    required this.text,
    this.onLongPress,
    this.markdown = true,
    this.footer,
  });

  final String text;
  final VoidCallback? onLongPress;

  /// 是否按 Markdown 渲染（`RV4-P2-02` / `docs/56` R13）。
  ///
  /// 默认 true：AI 回复里的 `**粗体**`/列表/代码块按形态渲染，而不是把符号
  /// 原样堆上屏。**图片/语音这类非文本消息**由调用方传 false 走纯 `Text`。
  /// 调用方必须**先清洗**（`replyTextForDisplay`）再交给本件——顺序写在这里，
  /// 测试 `chat_reply_display_test` 钉住。
  final bool markdown;

  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(LfDimens.spaceMediumPlus),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(LfDimens.radiusLg),
              bottomLeft: Radius.circular(LfDimens.radiusLg),
              bottomRight: Radius.circular(LfDimens.radiusLg),
            ),
            border: Border.all(color: c.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              markdown
                  ? LfMarkdown(
                      text: text,
                      baseStyle: LfText.body.copyWith(color: c.cardForeground),
                    )
                  : Text(
                      text,
                      style: LfText.body.copyWith(color: c.cardForeground),
                    ),
              if (footer != null) ...[
                const SizedBox(height: 4),
                Align(alignment: Alignment.centerRight, child: footer),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 用户侧：135° 渐变（mint-400→mint-500）底 + 白字 + 16 圆角（右上角 4）
/// + **右下 45° 旋转小方块尾角**。14px。
///
/// [onLongPress] 同 [AiMessageBubble]（长按转给页面，这里不碰剪贴板）。
class UserMessageBubble extends StatelessWidget {
  const UserMessageBubble({
    super.key,
    required this.text,
    this.trailing,
    this.onLongPress,
  });

  final String text;

  /// 气泡内右下的附加内容（语音条等）。
  final Widget? trailing;

  /// 长按整条气泡（复制入口，见 [AiMessageBubble.onLongPress]）。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final gradient = LfGradients.userBubble(Theme.of(context).brightness);
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.all(LfDimens.spaceMediumPlus),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(LfDimens.radiusLg),
                  topRight: Radius.circular(4),
                  bottomLeft: Radius.circular(LfDimens.radiusLg),
                  bottomRight: Radius.circular(LfDimens.radiusLg),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: LfText.body.copyWith(color: LfColors.onMedia),
                  ),
                  ?trailing,
                ],
              ),
            ),
            // 45° 旋转小方块尾角（右下）。
            Positioned(
              right: -3,
              bottom: -2,
              child: Transform.rotate(
                angle: 45 * 3.141592653589793 / 180,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    gradient: gradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 全屏看大图层（需求 3）：黑底 + `InteractiveViewer`（双指缩放/拖动）
/// + 右上关闭键（44dp 触达）+ 点空白处关闭。
///
/// 【为什么是 `InteractiveViewer` 而不是静态大图】用户要看的是菜名与份量，
/// 那些细节在 180×140 缩略里必然糊；只有能放大才叫「看清」。
///
/// 【关闭有三条路】右上关闭键（明确）、点背景（习惯动作）、系统返回键
/// （`Navigator.pop` 天然支持）。三条都不必二次确认——这是只读查看，
/// 没有可丢的东西。
///
/// 【Key 约定】全屏层本身用 `ai-chat-image-zoom-<index>`（页面传入），
/// 内部关闭键固定 `ai-chat-image-zoom-close`。
class ChatImageZoomView extends StatelessWidget {
  const ChatImageZoomView({super.key, required this.image, this.caption});

  /// 图片本体（与缩略图同一个 builder，保证两处看到的是同一张）。
  final Widget image;

  /// 说明文字（用户输入的原话）；显示在图片下方，便于对照。
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final captionText = caption?.trim() ?? '';
    return ColoredBox(
      // 看图就该是黑底：白底会让照片周围的边框抢注意力，也让亮照片刺眼。
      color: LfColors.scrimSolid,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              // 点背景关闭：`opaque` 保证空白处的点击也命中这里
              // （否则点到图片外的区域什么都不会发生）。
              key: const Key('ai-chat-image-zoom-backdrop'),
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) => image,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: LfDimens.spaceSmall,
            top: LfDimens.spaceSmall,
            child: SafeArea(
              child: Semantics(
                button: true,
                label: '关闭大图',
                // `Material` 必须自己给：本件会被放进**裸 `showDialog`**（不是
                // `Scaffold`/`Dialog`），树里没有 Material 祖先，`InkWell` 会在
                // 构建期直接抛断言。透明 Material 只提供墨水层，不画底色。
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    key: const Key('ai-chat-image-zoom-close'),
                    onTap: () => Navigator.of(context).maybePop(),
                    customBorder: const CircleBorder(),
                    child: const SizedBox(
                      width: LfDimens.minTouchTarget,
                      height: LfDimens.minTouchTarget,
                      child: Center(
                        child: Icon(
                          Icons.close,
                          size: LfDimens.iconMd,
                          color: LfColors.onMedia,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (captionText.isNotEmpty)
            Positioned(
              left: LfDimens.spaceMedium,
              right: LfDimens.spaceMedium,
              bottom: LfDimens.spaceMedium,
              child: SafeArea(
                child: Text(
                  captionText,
                  textAlign: TextAlign.center,
                  style: LfText.caption.copyWith(color: LfColors.onMedia),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 用户消息带图（2026-10-31 用户重定稿）：**只留图**——原始宽高比完整
/// 显示（contain，不裁剪；宽上限 232dp、高上限 280dp），无放大角标、无
/// 文件名药丸、无对勾徽章；右下 45° 旋转小方块尾角与用户文本气泡同一
/// 口径；用户输入的说明文字在图片下方右对齐（保留：那是消息正文的一部分）。
///
/// 图片本体由页面给（`Image.file` + contain；文件被系统清掉时给缺失占位）。
///
/// [onZoom] 非空 ⇒ 整图可点（页面打开全屏 `InteractiveViewer`）；为空 ⇒
/// 不可点（不摆可点态，与全仓「不给点了没反应的入口」同一纪律）。
class ImageMessage extends StatelessWidget {
  const ImageMessage({
    super.key,
    required this.image,
    this.caption,
    this.onZoom,
  });

  /// 图片本体（页面负责 contain 与错误占位）。
  final Widget image;

  /// 图片下方的说明文字（用户输入的原话）；空/null = 不显示。
  final String? caption;

  /// 点图（打开全屏大图）。null = 不可点。
  final VoidCallback? onZoom;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    final captionText = caption?.trim() ?? '';
    final zoom = onZoom;
    final imageBody = zoom == null
        ? image
        : Material(
            color: Colors.transparent,
            child: InkWell(
              // 可测性：点击目标就是这枚 InkWell（与整图同尺寸）。
              key: const Key('ai-chat-image-zoom-tap'),
              onTap: zoom,
              child: image,
            ),
          );
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(LfDimens.radiusLg),
                child: ConstrainedBox(
                  // 原始宽高比 contain：宽上限 232、高上限 280，不裁剪。
                  constraints: const BoxConstraints(
                    maxWidth: 232,
                    maxHeight: 280,
                  ),
                  child: imageBody,
                ),
              ),
              // 45° 旋转小方块尾角（右下，与用户文本气泡同一口径）。
              Positioned(
                key: const Key('ai-chat-image-tail'),
                right: -3,
                bottom: -2,
                child: Transform.rotate(
                  angle: 45 * 3.141592653589793 / 180,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: mint.tone(500),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (captionText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                captionText,
                textAlign: TextAlign.right,
                style: LfText.micro.copyWith(color: c.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}

/// AI 消息内的富文本卡（docs/21 §3.4）：三个「小卡」横排（图标块 + 文案
/// 同一行）+ 右上「点击查看」药丸徽章（protein-100 底 + protein 色字 +
/// chevron）+ AI 主按钮「立即查看专属理想方案」（底色同用户气泡渐变）。
///
/// **2026-10-16 用户裁决**：「功能卡片太丑，要做成小卡片，而不是堆在下边」
/// ——原形态是 muted 底大块 + 三列「40×40 圆图标 + 文案」上下堆叠（整块
/// ≥ 92dp），改为三张 `DesignCard` 小卡：小圆角图标块（24dp，mint-50 底 +
/// 14dp primary 图标）+ 右侧一行文案，整块降到约 44dp。列仍等宽
/// （`Expanded`），2.0 倍字号下文案折行而不是溢出。
///
/// 两个可点区**都是可选的**（docs/28 §6.4）：原先它们都指向「食谱计划」，
/// 该功能在 W4 整族下线后已无可跳转的页面，所以欢迎卡只留 3 个特性小卡
/// ——`onPrimaryTap == null` 时主按钮不渲染，两个回调都为 null 时
/// 「点击查看」徽章也不渲染（徽章是导航暗示，没有去处就不该出现）。
class FeatureCardMessage extends StatelessWidget {
  const FeatureCardMessage({
    super.key,
    required this.features,
    this.onPrimaryTap,
    this.primaryLabel = '立即查看专属理想方案',
    this.onTrailingTap,
  });

  /// 3 个特性列：(图标, 标签)。
  final List<(IconData, String)> features;

  /// 主按钮回调。null＝不渲染主按钮（见类文档）。
  final VoidCallback? onPrimaryTap;
  final String primaryLabel;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final mint = LfColors.mint(Theme.of(context).brightness);
    final primaryTap = onPrimaryTap;
    final trailingTap = onTrailingTap ?? primaryTap;
    return SizedBox(
      key: const Key('ai-chat-feature-card'),
      width: double.infinity,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 三张小卡横排；2.0 倍字号下文案折行（等宽列），不溢出。
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < features.take(3).length; i++) ...[
                      if (i > 0) const SizedBox(width: LfDimens.spaceSmall),
                      Expanded(
                        child: _FeatureTile(
                          icon: features[i].$1,
                          label: features[i].$2,
                          mint: mint,
                          foreground: c.cardForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (primaryTap != null) ...[
                const SizedBox(height: LfDimens.spaceMedium),
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LfGradients.userBubble(
                        isLight ? Brightness.light : Brightness.dark,
                      ),
                      borderRadius: BorderRadius.circular(LfDimens.radiusLg),
                      boxShadow: LfShadows.aiPrimaryCta(c.primary),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const Key('cta-write-plan'),
                        onTap: primaryTap,
                        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            primaryLabel,
                            textAlign: TextAlign.center,
                            style: LfText.bodyStrong.copyWith(
                              color: LfColors.onMedia,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // 徽章放在最后 = 画在最上层：大字号下它与图标列位置重叠时不会被盖住。
          if (trailingTap != null)
            Positioned(
              right: 0,
              top: 0,
              child: InkWell(
                key: const Key('feature-card-view'),
                onTap: trailingTap,
                borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: c.protein100,
                    borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '点击查看',
                        style: LfText.microStrong.copyWith(
                          color: c.cardForeground,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: c.cardForeground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 功能卡里的一张「小卡」：白底 `DesignCard` + 24dp 圆角图标块 + 一行文案。
final class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.label,
    required this.mint,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final TonalRamp mint;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DesignCard(
      // 内距/图标块收紧到 8+20+4：360dp 下三张卡各得 ≈101dp，而 A 的标签是
      // 5 个字（「三餐控热量」）——24dp 图标块 + 10dp 内距会让末字折行
      // （首拍帧里 `三餐控热/量` 就是这么来的）。320dp 仍会折行：那是
      // 窄屏大字的必然，按仓内策略**折行不缩字**。
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: mint.tone(50),
              borderRadius: BorderRadius.circular(LfDimens.radiusSm),
            ),
            child: Icon(icon, size: 13, color: c.primary),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: LfText.microStrong.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI 正在输入（docs/21 §2.9 `.typing-dot`）：三点跳动 1.4s 无限循环，
/// 三点 delay 0/0.2/0.4s；减弱动画时静止。
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final c = context.lf;
    if (reduced) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('ai-chat-typing'),
        padding: const EdgeInsets.symmetric(
          horizontal: LfDimens.spaceMedium,
          vertical: LfDimens.spaceSmall,
        ),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(LfDimens.radiusLg),
            bottomLeft: Radius.circular(LfDimens.radiusLg),
            bottomRight: Radius.circular(LfDimens.radiusLg),
          ),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: reduced
                    ? _dot(context, c, i, const AlwaysStoppedAnimation(0.3))
                    : AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          // 1.4s 循环，第 i 点相位偏移 0.2s。
                          final t = ((_controller.value + i * 0.2 / 1.4) % 1.0);
                          // opacity .3→1（正弦半周期）。
                          final opacity = 0.3 + 0.7 * _halfWave(t);
                          // scale .8→1.15。
                          final scale = 0.8 + 0.35 * _halfWave(t);
                          return _dot(
                            context,
                            c,
                            i,
                            AlwaysStoppedAnimation(opacity),
                            scale,
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }

  double _halfWave(double t) {
    // 0→1→0 的半正弦（ease-in-out 感）。
    return (1 - (2 * t - 1).abs()) * (1 - (2 * t - 1).abs());
  }

  Widget _dot(
    BuildContext context,
    LfSemanticColors c,
    int index,
    Animation<double> opacity, [
    double scale = 1.0,
  ]) {
    return Opacity(
      opacity: opacity.value.clamp(0, 1),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: c.mutedForeground,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// 对话起手行（Round7 逐页对账批次 4，A `app.js:207` 的
/// `.conversation-starters`）：整行可点——左图标（品牌强调色）+ 一句起手问题
/// + 右箭头（muted），卡片底 + 1px 描边 + R13 + 最小高 51。
///
/// 点它的动作由调用方决定：AI 对话页用它**只预填输入框**（不替用户发送）。
class AiStarterRow extends StatelessWidget {
  const AiStarterRow({
    super.key,
    required this.rowKey,
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final Key rowKey;
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        key: rowKey,
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          constraints: const BoxConstraints(minHeight: 51),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: LfColors.mintText(Theme.of(context).brightness),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: LfText.caption.copyWith(color: c.cardForeground),
                ),
              ),
              Icon(Icons.chevron_right, size: 15, color: c.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}
