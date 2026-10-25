import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 分段控件的一段（值 + 文案）。
@immutable
final class LfSegment<T> {
  const LfSegment({required this.value, required this.label});

  final T value;
  final String label;
}

/// 自绘分段控件（docs/32 §3 D18 第 5 条 / §4 T15，需求 74；2026-10-14
/// Round7 A 复核几何与取色）。
///
/// 【形态来源】A 的 `.tabs`（`styles.css:158-160` + `refinement.css:2`）：
/// 轨道 `padding:4px`、`gap:5px`、`border-radius:12px`、底色 `--track`，
/// 段 `min-height:44px`、`border-radius:9px`、`font-size:13px`（未选
/// `--muted`，选中 `--card` 底 + `--fg` 字 w600）。4 + 44 + 4 = 52dp 轨道，
/// 因此段本身就有 44dp 命中，**不再需要虚设外框**。
///
/// 【为什么不复用 M3 `SegmentedButton`】它自带 outline 描边与固定高度，
/// 取色/几何都不可控，且与本轮 T4 收敛的 `LfSelectField`（「框外标签 +
/// 自绘控件」）不是同一套语言。2–3 段互斥选择自绘更省、更好测。
///
/// 【大字体】文字行高超过 4 + 44 + 4 时只**增高**轨道（按两行预算），
/// 段内文字换行居中、不缩字号；320dp × 2.0× 的窄宽会让长标签折成两行。
///
/// 【读屏】每段一个按钮节点（`selected` + `inMutuallyExclusiveGroup`），
/// 视觉文字 `ExcludeSemantics`；段是互斥选择，不播报「开关」语义。
final class LfSegmentControl<T> extends StatelessWidget {
  const LfSegmentControl({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.segmentKeys = const {},
    super.key,
  });

  /// 段定义（按显示顺序）。
  final List<LfSegment<T>> segments;

  /// 当前选中值。
  final T selected;

  /// 点了**另一段**时回调。
  final ValueChanged<T> onChanged;

  /// 每段可点控件上的 Key（测试定位用；缺省不挂）。
  final Map<T, Key> segmentKeys;

  /// 轨道高（dp）：A `.tabs` 的 4 + 44 + 4。
  static const double trackHeight = 52;

  /// 内衬（A `padding:4px`）。
  static const double inset = 4;

  /// 段间距（A `gap:5px`）。
  static const double gap = 5;

  /// 段圆角（A `.tabs button{border-radius:9px}`）。
  static const double segmentRadius = 9;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.base;
    // 两行文字预算：字号 13 × 行高 1.4 × 2 + 上下内衬；1× 下回落到 52。
    final scaledLine = MediaQuery.textScalerOf(context).scale(13) * 1.4;
    final effectiveHeight = (scaledLine * 2 + inset * 2).clamp(
      trackHeight,
      double.infinity,
    );
    return Container(
      height: effectiveHeight,
      padding: const EdgeInsets.all(inset),
      decoration: BoxDecoration(
        color: context.lfc.ringTrack,
        borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      ),
      child: Row(
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Expanded(
              child: _Segment(
                key: segmentKeys[segments[i].value],
                label: segments[i].label,
                selected: segments[i].value == selected,
                duration: duration,
                onTap: segments[i].value == selected
                    ? null
                    : () => onChanged(segments[i].value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.duration,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: duration,
            curve: AppMotion.curve,
            alignment: Alignment.center,
            // 段本身 ≥44（52 − 上下各 4 内衬），大字体下随轨道同步增高。
            constraints: const BoxConstraints(
              minHeight: LfDimens.minTouchTarget,
            ),
            decoration: BoxDecoration(
              // A：选中 = `--card` 底 + `--fg` 字（无阴影）。
              color: selected ? c.card : Colors.transparent,
              borderRadius: BorderRadius.circular(
                LfSegmentControl.segmentRadius,
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: LfText.bodySmall.copyWith(
                color: selected ? c.foreground : c.mutedForeground,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
