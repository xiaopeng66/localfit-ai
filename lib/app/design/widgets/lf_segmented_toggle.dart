import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 分段切换：**统一轨道 + 内嵌滑块**（docs/31 §2 D2，2026-10-09 需求 39）。
///
/// 【形态来源】用户发的第二张图 = R2 稿的「改造前」帧：一条灰轨道里浮着一颗
/// 白色滑块，两段文字直接在轨道上。用户要的是这个**形态**。
///
/// 【为什么不是两颗独立胶囊】R2 曾把切换做成两颗各成一体的 [LfPillButton]
/// （「周」「月」各一块浅底），用户 2026-10-08 嫌「太大了，上下宽度也很大」
/// ——嫌的是**尺寸**（那对胶囊的布局盒各 48dp）。2026-10-09 又发了第二张图
/// 指出要**形态**。两者不矛盾：形状照第二张图（统一轨道），尺寸按第三轮
/// 意见压小。2026-10-14 Round7 A 把有效几何定为 `refinement.css:5` 的
/// `.mini-tabs{height:36px;padding:0 2px}` + `.mini-tabs button
/// {height:44px;width:44px;font-size:12px}`（`polish.css:17` 复核宽度）+
/// 选中块 `inset:8px 1px;background:var(--card);box-shadow:0 1px 3px
/// #10271D0A`——即轨道视觉高 36、滑块 42×28、每段命中 44×44。
///
/// 【几何】轨道视觉高 36dp、滑块 28dp（上下各 8 内衬）、每段 44dp 宽。
/// **布局盒 = 命中盒 = ≥44dp 高**（Flutter 父级 `hitTest` 先查
/// `size.contains`，超出布局盒的点击传不进来），视觉块在命中盒里垂直居中。
///
/// 【动效】滑块在段落间平滑位移（[AppMotion.fast]）；「减弱动画」开启时
/// 直显终态。键盘/读屏侧每段仍是独立的可点 target（`Semantics(selected:)`）。
class LfSegmentedToggle extends StatelessWidget {
  const LfSegmentedToggle({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.segmentKeys,
    this.semanticLabel,
  });

  /// 段标签（按显示顺序）。通常 2 段。
  final List<String> segments;

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// 各段的 widget key（可选，长度须与 [segments] 一致）。
  ///
  /// 调用方常有「按段定位」的既有 Key 契约（如体重卡的
  /// `dashboard-weight-range-week` / `-month` 写在 `docs/21 §5` 表里），
  /// 那些 Key 必须落在**段本身**上，测试才点得到。不给则由本件生成
  /// 位置型 ValueKey。
  final List<Key>? segmentKeys;

  /// 整组的读屏标签；缺省不额外包一层语义。
  final String? semanticLabel;

  /// 轨道视觉高（dp）：A 有效值 `refinement.css:5` `.mini-tabs{height:36px}`。
  static const double trackHeight = 36;

  /// 每段视觉宽（dp）：`width:44px;min-width:44px`（也正好等于触达下限）。
  static const double segmentWidth = 44;

  /// 滑块视觉高（dp）：`::before{inset:8px 1px}` 落在 44dp 高的段上。
  static const double thumbHeight = trackHeight - 8;

  /// 滑块视觉宽（dp）：段宽减左右各 1dp 内衬。
  static const double thumbWidth = segmentWidth - 2;

  /// 轨道横向内衬（A `padding:0 2px`）。
  static const double _trackInsetX = 2;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final reduced = AppMotion.reduced(context);
    // 大字体降级：文字行高超过滑块内高时只**增高**滑块与轨道（不缩小用户
    // 字号，也不藏文字）。
    final scaledLine = MediaQuery.textScalerOf(context).scale(12) * 1.4;
    final effectiveThumbHeight = (scaledLine + 4).clamp(
      thumbHeight,
      double.infinity,
    );
    final effectiveTrackHeight = effectiveThumbHeight + 8;
    final targetHeight = effectiveTrackHeight.clamp(
      LfDimens.minTouchTarget,
      double.infinity,
    );
    final trackWidth = segmentWidth * segments.length + 4;
    final track = SizedBox(
      key: const Key('lf-segmented-track'),
      width: trackWidth,
      height: effectiveTrackHeight,
      child: Stack(
        children: [
          // 轨道底：A `--track`（亮 EFF3F1 / 暗 26332C），圆角 20。
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.lfc.ringTrack,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          // 滑块：位置随选中段（段宽 44、左右各 1dp 内衬）。
          AnimatedPositioned(
            key: const Key('lf-segmented-thumb'),
            duration: reduced ? Duration.zero : AppMotion.fast,
            curve: AppMotion.curve,
            left: _trackInsetX + 1 + selectedIndex * segmentWidth,
            top: 4,
            width: thumbWidth,
            height: effectiveThumbHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // A 的选中块两主题都取 `--card`（暗色的卡面 `171E1A` 与轨道
                // `26332C` 仍可辨，无需特判提亮）。
                color: c.card,
                borderRadius: BorderRadius.circular(14),
                boxShadow: reduced
                    ? const []
                    : const [
                        BoxShadow(
                          color: Color(0x0A10271D),
                          offset: Offset(0, 1),
                          blurRadius: 3,
                        ),
                      ],
              ),
            ),
          ),
          // 段文字（在滑块之上）。
          Positioned(
            left: _trackInsetX,
            right: _trackInsetX,
            top: 4,
            bottom: 4,
            child: Row(
              children: [
                for (var i = 0; i < segments.length; i++)
                  SizedBox(
                    width: segmentWidth,
                    child: Center(
                      child: Text(
                        segments[i],
                        style: LfText.captionStrong.copyWith(
                          color: i == selectedIndex
                              ? LfColors.mintText(brightness)
                              : c.mutedForeground,
                          fontWeight: i == selectedIndex
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    // 命中盒：整组至少 44 高（视觉轨道 36 在中间）。每段各自可点，
    // 用 Row 均分命中区，于是「点哪一段就切到哪一段」的直觉成立。
    final hitRow = SizedBox(
      height: targetHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < segments.length; i++)
            _SegmentTarget(
              key: segmentKeys != null && i < segmentKeys!.length
                  ? segmentKeys![i]
                  : ValueKey<int>(i),
              label: segments[i],
              selected: i == selectedIndex,
              onTap: i == selectedIndex ? null : () => onChanged(i),
              child: SizedBox(width: segmentWidth, height: targetHeight),
            ),
        ],
      ),
    );
    final content = _Overlap(
      base: hitRow,
      overlay: IgnorePointer(child: Center(child: track)),
    );
    return semanticLabel == null
        ? content
        : Semantics(label: semanticLabel, container: true, child: content);
  }
}

/// 触达盒高（与 [LfDimens.minTouchTarget] 同值；本文件内的命中行按动态
/// 高度计算，该常量保留给既有外部引用）。
const double minTouchTargetSafe = LfDimens.minTouchTarget;

/// 一段的可点 target：语义上是一个「选中态按钮」。
class _SegmentTarget extends StatelessWidget {
  const _SegmentTarget({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

/// 把一个 widget 叠在另一个上面，**尺寸由 base 决定**。
///
/// 用来实现「命中盒 ≥44 高、视觉轨道在中间」：base 是命中行，
/// overlay 是不吃事件的视觉轨道；base 恒不低于 overlay 高度。
class _Overlap extends StatelessWidget {
  const _Overlap({required this.base, required this.overlay});

  final Widget base;
  final Widget overlay;

  @override
  Widget build(BuildContext context) =>
      Stack(alignment: Alignment.center, children: [base, overlay]);
}
