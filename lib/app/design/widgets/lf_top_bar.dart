import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';

/// 二级页顶栏（docs/21 §3.6 **新建**）。
///
/// 几何与配色逐值取自设计稿（`拍照识餐.html` 与 `AI 工作.html` 两处顶栏
/// 结构一致）：`px-4 py-3` + `gap-3` + `border-b`，返回与动作都是
/// `w-9 h-9 rounded-full` 的 muted 底圆形钮，标题 `flex-1` **左对齐**
/// （不是居中）。无阴影、无渐变，与页面同底色。
///
/// 【规范正文与设计源的差异】docs/21 §3.6 正文写「居中标题」，而设计稿的
/// 实际 DOM 是 `flex-1` 左对齐。按 §1.1 的优先级（HTML 不可推翻），取
/// **左对齐**。
///
/// 【36dp 视觉 / 44dp 触达】设计稿 `w-9 h-9` 是 36dp，低于 §5.8.3 的 44dp
/// 触达要求。做法是**视觉圆 36、命中盒 44**——圆形墨迹画在 36dp 上，外面
/// 套 44dp 的触达框，两者不冲突。
class LfTopBar extends StatelessWidget implements PreferredSizeWidget {
  const LfTopBar({
    super.key,
    required this.title,
    this.actions,
    this.onBack,
    this.backKey,
    this.titleKey,
    this.titleLeading,
    this.respectTopInset = true,
    this.showBack = true,
    this.showTitle = true,
    this.subtitle,
    this.subtitleKey,
  });

  final String title;

  /// 标题下的副题（Round7 逐页对账批次 2：A `app.js:207` 的
  /// `head('AI 助手', '一起把计划，变得可执行')` 是「标题 + 副题」两行）。
  ///
  /// **只在把本件当普通容器用（页面 Column 的一行）时才完全自适应**：那种
  /// 用法下栏高由内容撑开。当 `Scaffold.appBar` 用时 `preferredSize` 会随
  /// 副题增高（60 → 66），大字档不再额外自适应——当前唯一使用者是 AI 对话页
  /// 的 `_header`（容器用法）。
  final String? subtitle;

  /// 副题的测试 Key（如 `ai-chat-subtitle`）。
  final Key? subtitleKey;

  /// 右侧动作（如 `cta-rescan`）。每项应是 36dp 圆形钮或等宽控件。
  final List<Widget>? actions;

  /// 标题前的装饰件（AI 对话页的 32dp 吉祥物头像，docs/21 §5.7）。
  final Widget? titleLeading;

  /// 缺省 = `Navigator.maybePop`。
  final VoidCallback? onBack;

  /// 返回键的 Key。缺省 `top-bar-back`（既有调用点与测试依赖该默认值）。
  final Key? backKey;

  final Key? titleKey;

  /// 顶栏是否自己吃掉顶部系统叠层（docs/21 §5.8.5）。
  ///
  /// 顶栏与页面同底色、只多一条下边框，所以把叠层算进栏高才是对的——
  /// 边框线正好落在状态栏之下，标题与返回键不会被时钟压住。
  ///
  /// **作为 `Scaffold.appBar` 用时不要关掉**：Scaffold 给的槽位高度本来就是
  /// `preferredSize + padding.top`，栏填满槽位后内容正好落在状态栏之下，
  /// 不会双倍预留；反之关掉就会把内容画进状态栏带里（阶段 J 实测：
  /// 拍照识餐/食堂目录/下一餐推荐/动作库 4 页的返回键 `y=20..135`，
  /// 状态栏是 `0..128`）。
  final bool respectTopInset;

  /// 是否渲染返回键（docs/29 §P8a 需求 30：「删掉上边标题和左边返回按钮」）。
  ///
  /// **默认 `true` = 现状不变**。需求 30 说的是饮食页里那枚「食物库」tab 的
  /// 栏——那一栏是页面内的 tab 头，没有可返回的上一级，返回键在那里不仅没用
  /// 还会误导（按了弹到别处）。**共享件不能全局删**：同一条顶栏还被拍照识餐、
  /// 食堂目录、下一餐推荐、动作库、AI 对话五处当二级页头用，那些页都要返回键。
  final bool showBack;

  /// 是否渲染标题（同需求 30）。默认 `true`；`false` 时标题不占位，
  /// 右侧动作与返回键的间距规则不变。
  final bool showTitle;

  /// `py-3` 上下各 12 + 内容行 36（圆形钮是行内最高元素）。
  static const double _barHeight = 60;

  /// 带副题时的栏高：标题 16×1.3 + 间距 2 + 副题 12×1.4 = 39.6 ⇒
  /// 12 + 39.6 + 12 ≈ 63.6，取 66 留一点余量。
  static const double _barHeightWithSubtitle = 66;

  @override
  Size get preferredSize =>
      Size.fromHeight(subtitle == null ? _barHeight : _barHeightWithSubtitle);

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final inset = respectTopInset ? LfInsets.top(context) : 0.0;
    return Container(
      constraints: BoxConstraints(minHeight: _barHeight + inset),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          LfDimens.spaceLarge,
          inset,
          LfDimens.spaceLarge,
          0,
        ),
        child: Row(
          children: [
            if (showBack) ...[
              LfCircleIconButton(
                key: backKey ?? const Key('top-bar-back'),
                icon: Icons.chevron_left,
                tooltip: '返回',
                onPressed: onBack ?? () => Navigator.maybePop(context),
              ),
              const SizedBox(width: LfDimens.spaceMedium),
            ],
            if (titleLeading != null) ...[
              titleLeading!,
              const SizedBox(width: LfDimens.spaceSmall),
            ],
            if (showTitle)
              Expanded(
                child: subtitle == null
                    ? Text(
                        title,
                        key: titleKey,
                        style: LfText.titleLarge.copyWith(color: c.foreground),
                        softWrap: true,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            key: titleKey,
                            style: LfText.titleLarge.copyWith(
                              color: c.foreground,
                            ),
                            softWrap: true,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            key: subtitleKey,
                            style: LfText.caption.copyWith(
                              color: c.mutedForeground,
                            ),
                            softWrap: true,
                          ),
                        ],
                      ),
              )
            else
              // 标题不画时也要撑开：否则右侧动作会贴着返回键（或左内边距）
              // 排，与「动作恒靠右」的其余五处顶栏不一致。
              const Spacer(),
            ...?actions,
          ],
        ),
      ),
    );
  }
}

/// 圆形图标钮的三档底色（docs/21 §3.8 B4）。
enum LfCircleIconButtonVariant {
  /// `muted` 底 + `foreground` 图标：顶栏返回、输入栏添加图片/麦克风。
  muted,

  /// 品牌实心底 + `primaryForeground` 图标：输入栏发送、录音发送。
  /// **无阴影**——设计稿的 `btn-voice-send` 明确不带 shadow。
  primary,

  /// `card`@90% 底 + `foreground` 图标：压在照片上的「重拍」。
  overlay,
}

/// 顶栏圆形图标钮（设计稿 `w-9 h-9 rounded-full` + muted 底）。
///
/// 视觉圆 36dp、命中盒 [LfDimens.minTouchTarget]（44dp）——见 [LfTopBar] 头注释。
/// 三态见 [LfCircleIconButtonVariant]（docs/21 §3.8 B4）。
class LfCircleIconButton extends StatelessWidget {
  const LfCircleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.iconSize,
    this.variant = LfCircleIconButtonVariant.muted,
    this.background,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double? iconSize;

  /// 底色档位（§3.8 B4）。[background]/[iconColor] 显式传入时优先于它。
  final LfCircleIconButtonVariant variant;

  /// 圆形底色；缺省按 [variant] 取（`muted` = 顶栏与输入栏的次要动作）。
  final Color? background;

  /// 图标色；缺省按 [variant] 取（禁用时一律 `mutedForeground`）。主按钮
  /// （输入栏发送/录音发送）可用 `variant: primary`，或显式传
  /// `primaryForeground`。
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final (variantBackground, variantIcon) = switch (variant) {
      LfCircleIconButtonVariant.muted => (c.muted, c.foreground),
      LfCircleIconButtonVariant.primary => (
        lfSolidButtonFill(context),
        c.primaryForeground,
      ),
      LfCircleIconButtonVariant.overlay => (
        // 压在照片上的「重拍」类按钮（`bg-[var(--lf-card)]/90`）。
        c.card.withValues(alpha: 0.9),
        c.foreground,
      ),
    };
    final circle = Material(
      color: background ?? variantBackground,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: iconSize ?? LfDimens.iconMd,
            color: onPressed == null
                ? c.mutedForeground
                : (iconColor ?? variantIcon),
          ),
        ),
      ),
    );
    // 命中盒 44、视觉圆 36：外层只扩触达，**不再叠一个 InkWell**——两个
    // 嵌套 InkWell 会画出比视觉圆更大的第二层涟漪，也会让「视觉圆 36dp」
    // 这一契约在查内部 InkWell 时失真（实测拿到 44）。墨迹仍由内层 36dp
    // 圆承载，语义也仍是单一节点。
    final sized = GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onPressed,
      child: SizedBox(
        width: LfDimens.minTouchTarget,
        height: LfDimens.minTouchTarget,
        child: Center(child: circle),
      ),
    );
    // 图标钮必须有 tooltip（§5.8.3）。
    return tooltip == null ? sized : Tooltip(message: tooltip!, child: sized);
  }
}
