import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/dashed_border.dart';

/// 内容卡的描边 / 圆角 / 阴影（docs/21 §3.1 的唯一卡片形态）。
///
/// **单源**：`DesignCard`（底色由 `Material` 画，[color] 传 null）与
/// `DecoratedSliver` 形态的列表卡（`FoodListCard`：sliver 没有 `Material` 外
/// 壳，底色必须由装饰自己画，[color] 传 `--card`）共用同一份数值——两处各写
/// 一份，改了一处另一处就悄悄漂掉。
BoxDecoration lfCardDecoration(
  BuildContext context, {
  bool dashed = false,
  Color? color,
}) {
  final c = context.lf;
  final isLight = Theme.of(context).brightness == Brightness.light;
  return BoxDecoration(
    color: dashed ? null : color,
    borderRadius: BorderRadius.circular(LfDimens.radiusLg),
    border: Border.all(
      color: isLight && !dashed ? Colors.transparent : c.border,
    ),
    boxShadow: dashed || !isLight
        ? const <BoxShadow>[]
        : const [
            BoxShadow(
              color: Color(0x051A201D),
              offset: Offset(0, 1),
              blurRadius: 3,
            ),
          ],
  );
}

/// 新设计唯一卡片形态（docs/21 §3.1）：白底 + 1px 描边 + 16 圆角 +
/// `--lf-shadow-1` + 内边距 16。
///
/// [dashed] 变体：虚线描边（`border-dashed` 4/4），用于「计划态」
/// （今日页晚餐时间线、AI 页「添加」按钮）。虚线模式无阴影、底色透明，
/// 与设计稿的 dashed 卡一致。
class DesignCard extends StatelessWidget {
  const DesignCard({
    super.key,
    required this.child,
    this.dashed = false,
    this.padding = const EdgeInsets.all(LfDimens.cardPadding),
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
  });

  final Widget child;
  final bool dashed;
  final EdgeInsetsGeometry padding;

  /// 传入则整卡可点（Pressable 语义 + ink 响应）。
  final VoidCallback? onTap;

  /// 传入则整卡可长按（docs/21 §3 长按多选）。与 [onTap] 并存时短按走
  /// [onTap]、按住不放走本回调——两者是同一个 [InkWell] 上互相独立的
  /// 识别器，不会彼此吞掉。
  final VoidCallback? onLongPress;

  /// 读屏标签（设计稿卡片无可访问名称时由调用方补）。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final borderRadius = BorderRadius.circular(LfDimens.radiusLg);
    final card = Material(
      color: dashed ? Colors.transparent : c.card,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(padding: padding, child: child),
      ),
    );
    final content = DecoratedBox(
      // 底色由上面的 `Material` 画（[lfCardDecoration] 的 color 传 null），
      // 装饰只负责描边、圆角与阴影。
      decoration: lfCardDecoration(context, dashed: dashed),
      child: dashed
          ? CustomPaint(
              foregroundPainter: DashedBorderPainter(color: c.border),
              child: card,
            )
          : card,
    );
    // 2026-10-10（docs/31 S8）：semanticLabel 曾是死参数——构造函数收了、
    // build 从不用（体重卡/快捷统计卡传的读屏标签全被静默丢弃）。现在接入
    // 语义树：container: true 让整卡一个语义节点带标签、子节点照常可读，
    // 与 lf_segmented_toggle 同一形态。
    return semanticLabel == null
        ? content
        : Semantics(label: semanticLabel, container: true, child: content);
  }
}

/// 卡片头（docs/21 §3.1）：标题 15 w600 + 可选副标题 12 muted + 可选尾部徽章。
class DesignCardHeader extends StatelessWidget {
  const DesignCardHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: LfText.title.copyWith(color: c.cardForeground),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: LfDimens.spaceMicro),
                  child: Text(
                    subtitle!,
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// 嵌套块（docs/21 §3.1）：muted 底 + 16 圆角 + 内边距 12。
/// **不是白卡**——设计稿卡内子块用 muted 底色，不用第二层白卡。
class MutedBlock extends StatelessWidget {
  const MutedBlock({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(LfDimens.spaceMedium),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.lf.muted,
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// hero 渐变容器（docs/21 §3.1）。圆角分两种，**不可混用**：
///  * [HeroShape.bottomOnly]：训练页暗色 hero（`rounded-b-[16px]`，只圆下角）；
///  * [HeroShape.all]：今日页 AI 卡（全角 16）。
/// `rounded-[20px]` 在设计稿中出现 0 次。
///
/// **2026-10-08（docs/30 §2 D4/D5/D6）后的剩余使用者只有今日页 AI 入口卡**
/// （`dashboard_ai_entry_card.dart`）：记录 / 菜单 / 我的身份卡 / 训练页四处
/// 已按用户「大色块数据卡太丑」的反馈改成标准 [DesignCard]。别因为这里还留着
/// 两种 shape 就以为渐变 hero 仍是主流形态。
enum HeroShape { bottomOnly, all }

class HeroSection extends StatelessWidget {
  const HeroSection({
    super.key,
    required this.child,
    this.shape = HeroShape.bottomOnly,
    this.respectTopInset = false,
    this.padding = const EdgeInsets.fromLTRB(
      LfDimens.spaceLargePlus,
      LfDimens.spaceLargePlus,
      LfDimens.spaceLargePlus,
      LfDimens.spaceLargePlus,
    ),
  });

  final Widget child;
  final HeroShape shape;

  /// 是否让**内容**躲开顶部系统叠层（docs/21 §5.8.5）。
  ///
  /// 只对**页面贴顶的 hero** 置 true：此时渐变必须铺到屏幕物理顶边（设计稿
  /// 的渐变从屏幕顶边开始），只有内容整体下移 `LfInsets.top`。**不要改成给
  /// 整个 hero 套 `SafeArea`**——那会把渐变一起推下去，屏幕顶部留出一条页面
  /// 底色带，而那在设计稿里不存在。
  ///
  /// 页内的 hero（如今日页的 AI 入口卡）保持 false：它的上方还有其他内容，
  /// 叠层已由页面级留白处理。
  final bool respectTopInset;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final component = context.lfc;
    final radius = shape == HeroShape.bottomOnly
        ? const BorderRadius.vertical(
            bottom: Radius.circular(LfDimens.radiusLg),
          )
        : BorderRadius.circular(LfDimens.radiusLg);
    final effectivePadding = respectTopInset
        ? padding.add(EdgeInsets.only(top: LfInsets.top(context)))
        : padding;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: component.heroGradient,
          stops: component.heroStops,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: effectivePadding,
          child: DefaultTextStyle.merge(
            // 浅 mint 渐变淡端近白（#ECFBF5），白字对比最低 ~1.1:1——
            // hero 文字默认用前景墨色；暗主题渐变本身为深色、前景为浅色，
            // 同一规则两态成立（docs/27 §R2）。
            style: LfText.body.copyWith(color: c.foreground),
            child: child,
          ),
        ),
      ),
    );
  }
}
