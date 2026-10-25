import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 饮食页 sub-tab 分段行（docs/21 §4.3）：Round7 A `.tabs`
/// （`design/round7/styles.css:158-160` + `refinement.css:3`）——一条
/// `--track` 轨道里嵌三段**等宽**段（`gap 5`、段 `min-height 44`、圆角 9），
/// 选中段 = `--card` 底 + `--fg` + w600，未选中段 = 透明底 + `--muted`
/// 13px 字。
///
/// 【位置契约，2026-10-03 用户走查】「五个菜单按钮能不能移动到顶部，不然每个
/// 界面的位置都不在一个地方」。旧实现把同一条胶囊行分三个渲染点画：记录页在
/// hero 与趋势卡之下（实测 y≈300）、菜单页在 hero 之下（y≈139）、剩下几个 tab
/// 在细顶栏之下（y≈60）——切一次 tab 就要重新找按钮，也永远对不齐。
/// （当时的 tab 清单是五项「记录/计划/菜单/食谱/食物库」；2026-10-04 起为
/// 三项「记录/菜单/食物库」，docs/28 §6.1。）
///
/// 现在由 `NutritionPage` 在**全部 sub-tab 内容之上**渲染唯一一份：底色从
/// 屏幕物理顶边铺起（把设计稿的 `sticky top-0` 实物化），内容躲开状态栏，
/// 下缘即各 tab 页头之上。位置与 tab、与滚动位置都无关，逐像素恒定
/// （回归见 `nutrition_subtab_position_test`）。
///
/// 两处显式取舍（用户点名，docs/27 §R2 记裁定）：
///  * **记录/菜单的 hero 不再从屏幕物理顶边开始**——它从本行下缘开始。
///    hero 自身的渐变、只圆下角、内边距、字阶全部未变（`respectTopInset`
///    改为 false，叠层由本行统一消费，避免双倍预留）。
///  * 记录页的趋势卡相应落到胶囊行之下。
///
/// 【阶段 2B 形态迁移（D15）】旧件是三颗可横滑的独立胶囊（选中 = primary
/// 实心 + 白字），配 `Scrollable.ensureVisible` 保证选中枚完整可见——那是
/// 「五枚 chip 总宽超出 320dp」时代的补丁。A 的形态是**轨道 + 等宽三段**：
/// ① 三段等宽 ⇒ 任何目标字号下都完整可见，横滑与 `ensureVisible` 退场；
/// ② 段 `min-height 44` 且随文字自然增高 ⇒ 不再裁字（旧件行高固定 54、内容槽
/// 30：2.0× 文字自然行高 34，16dp 笔画被 ListView 视口裁掉——阶段 2A 的帧
/// `renders/2a/crops/_rec32020_top.png` 抓到的原始缺陷）。行为契约不变：
/// 三枚 `nutrition-tab-*` Key、页级唯一实例、`nutrition-subtab-bar` 锚点。
class NutritionSubTabChips extends StatelessWidget {
  const NutritionSubTabChips({
    super.key,
    required this.labels,
    required this.keys,
    required this.selected,
    required this.onSelected,
    this.respectTopInset = true,
  });

  final List<String> labels;
  final List<String> keys;
  final int selected;
  final ValueChanged<int> onSelected;

  /// 是否让本行的**内容**躲开顶部系统叠层（docs/21 §5.8.5）。
  ///
  /// 作为页面最顶行时必须开：底色铺到屏幕物理顶边、只有内容下移
  /// `LfInsets.top`。页面若在它上方还有消费了叠层的元素，则关掉以免双倍预留。
  final bool respectTopInset;

  /// 行高（A `.tabs`：轨道内衬 4 + 段 `min-height 44` + 4 = 52），**不含**顶部叠层。
  static const double barHeight = 52;

  /// 整行（含叠层）的稳定 Key：位置回归测试按它量。
  static const Key barKey = Key('nutrition-subtab-bar');

  /// 轨道的稳定 Key：形态回归（底色/圆角/内衬）按它量。
  static const Key trackKey = Key('nutrition-subtab-track');

  /// 轨道圆角（A：`refinement.css:3` 覆盖 `styles.css:158` 的 28）。
  static const double trackRadius = 12;

  /// 选中段圆角（A `refinement.css:3` `.tabs button{border-radius:9px}`）。
  static const double segmentRadius = 9;

  /// 轨道内衬（A `.tabs{padding:4px}`）。
  static const double trackInset = 4;

  /// 段间距（A `.tabs{gap:5px}`）。
  static const double segmentGap = 5;

  /// 段最小高（A `.tabs button{min-height:44px}`）：既是设计值也是触达下限。
  static const double segmentMinHeight = 44;

  /// 含叠层的整行高度。
  static double heightFor(
    BuildContext context, {
    bool respectTopInset = true,
  }) => barHeightFor(context) + (respectTopInset ? LfInsets.top(context) : 0);

  /// 当前字号下的行高：段高 = max(44, 13px 文字的自然行高)，再加轨道上下 4dp。
  ///
  /// 只增高、不缩字号、不裁字（A 的 `min-height` 语义：内容超出时盒随内容长）。
  static double barHeightFor(BuildContext context) {
    final line = MediaQuery.textScalerOf(context).scale(13) * 1.4;
    final segment = line > segmentMinHeight ? line : segmentMinHeight;
    return segment + 2 * trackInset;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    assert(labels.length == keys.length, '每枚 chip 都要有稳定 Key');
    final inset = respectTopInset ? LfInsets.top(context) : 0.0;
    return Container(
      key: barKey,
      height: barHeightFor(context) + inset,
      // 内容从叠层之下开始；底色（页面底色）本身铺到屏幕物理顶边。
      padding: EdgeInsets.only(
        top: inset,
        left: LfDimens.pagePadding,
        right: LfDimens.pagePadding,
      ),
      color: c.background,
      child: Container(
        key: trackKey,
        padding: const EdgeInsets.all(trackInset),
        decoration: BoxDecoration(
          color: context.lfc.ringTrack,
          borderRadius: BorderRadius.circular(trackRadius),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: segmentGap),
              Expanded(child: _segment(context, i)),
            ],
          ],
        ),
      ),
    );
  }

  /// 一段：`Material` 承载「选中 = card 底」的滑块（`InkWell` 需要 Material
  /// 祖先，同时它也是被断言的那层盒子），`ConstrainedBox` 给 44 触达下限并
  /// 随文字自然增高。
  Widget _segment(BuildContext context, int index) {
    final c = context.lf;
    final isSelected = index == selected;
    return Semantics(
      button: true,
      selected: isSelected,
      child: Material(
        key: Key(keys[index]),
        color: isSelected ? c.card : Colors.transparent,
        borderRadius: BorderRadius.circular(segmentRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(segmentRadius),
          onTap: () => onSelected(index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: segmentMinHeight),
            child: Center(
              child: Text(
                labels[index],
                textAlign: TextAlign.center,
                style: LfText.bodySmall.copyWith(
                  color: isSelected ? c.foreground : c.mutedForeground,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
