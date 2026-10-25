import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/pressable_scale.dart';

/// 横滑筛选胶囊（Round7 A `.food-category-row`，`styles.css:270–273` +
/// `polish.css:44–46`）。
///
/// **为什么不复用 [LfPillButton]（B3 胶囊）**：B3 是「卡片内的轻强调」——默认
/// h32、`muted` 底、`captionStrong` 12/w500；A 的筛选胶囊是**页面级筛选器**：
/// `min-height:44`（A 的触达线）、未选中**透明底 + 透明描边**（`polish.css:44`
/// 把 styles 的 1px `--border` 也设成透明）、选中 brand-soft 底 + brand-strong
/// 字 + **w600**（`polish.css:45`）。三处都不是 B3 档的值，套进去就得把 B3 的
/// 定义改掉，而 B3 被 11 处页面用着 ⇒ 另起一件，只服务筛选器。
///
/// 圆角用 `StadiumBorder`：A 是 `border-radius:24px` 配 44 高（22 = 高的一半），
/// 两者在同高下等价，取主题里已有的胶囊形状而不是再写一个半径。
class LfFilterChip extends StatelessWidget {
  const LfFilterChip({
    Key? key,
    required this.label,
    required this.selected,
    this.onPressed,
  }) : _innerKey = key,
       super(key: null);

  final Key? _innerKey;

  final String label;
  final bool selected;

  /// null = 不可点（依赖缺失时宁可没有入口，也不给点了没反应的胶囊）。
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final fg = selected ? LfColors.mintText(brightness) : c.mutedForeground;
    return Semantics(
      selected: selected,
      child: PressableScale(
        child: TextButton(
          key: _innerKey,
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: selected
                ? LfColors.brandSoft(brightness)
                : Colors.transparent,
            foregroundColor: fg,
            // A 的 `min-height:44`；横向内距 12（`polish.css:44` 的
            // `padding:0 12px`）。
            minimumSize: const Size(0, LfDimens.minTouchTarget),
            // `shrinkWrap` 是必须的：Material 默认的 `padded` 会把**布局盒**
            // 撑到至少 48（视觉仍是 44，多出来的 4dp 是透明热区），而 A 的
            // 胶囊是 44 连着热区一起（`min-height:44px`）⇒ 不写会让行高凭空
            // 多 4dp、整页往下挪。44 本身就是本仓的触达线
            // （`LfDimens.minTouchTarget`，与 A 同一档）。
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(
              horizontal: LfDimens.spaceMedium,
            ),
            shape: const StadiumBorder(),
            // 描边恒透明（A 的选中态改用底色表达，不靠描边）。
            side: const BorderSide(color: Colors.transparent),
            // 标签字体随主题：与 `lf_buttons.dart` 的 `_lfButtonLabel` 同一口径
            // （`Theme.of(context).textTheme.bodyMedium.merge(…样式)`）。
            //
            // **为什么非并不可**：`ButtonStyleButton` 把这份样式**替换**进环境的
            // `DefaultTextStyle`（不是合并），而 `LfText.caption` 不带字体族 ⇒
            // 族就成了 null。真机上 null 落到平台默认族、CJK 有系统兜底，看不出
            // 问题；测试引擎没有兜底，帧里渲染成 .notdef 空方框（2026-10-14 阶段 3
            // 步骤 2b 渲染审看抓到，六件按钮家族在阶段 1 已这样修过，胶囊漏了）。
            // 尺寸/字重仍由 `LfText.caption` 说了算（merge 只补族与小量字距）。
            textStyle: Theme.of(context).textTheme.bodyMedium!.merge(
              LfText.caption.copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

/// 胶囊行：横滑、间距 4（A `.food-category-row{gap:4px}`，`polish.css:44`）。
///
/// 行高恒等于一枚胶囊的 44：**不折行**——A 也是横滑（`overflow-x:auto`），
/// 11 枚在 320dp 上必然超出，折行会把整页往下推、还会让选中的那一枚掉到
/// 第二行看不见。行内第一枚贴着页内容左缘（A refinement 把负外边距清零）。
class LfFilterChipRow extends StatelessWidget {
  const LfFilterChipRow({super.key, this.chips = const []});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      // 内容比视口短时不要居中/拉伸：胶囊永远从左边开始（A 的 flex 布局）。
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: LfDimens.spaceXSmall),
            chips[i],
          ],
        ],
      ),
    );
  }
}
