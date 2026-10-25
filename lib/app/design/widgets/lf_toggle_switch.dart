import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// iOS 风格开关（**呈现件**；docs/32 §3 D18 第 6 条 / §4 T15，需求 74）。
///
/// 46×28 轨道 + 24dp 白色圆钮 + `primary` 选中底，逐值取自设计稿
/// `ui设计/pages/初始引导.html` 的 `.toggle-switch`；未选底取中性 ramp 300
/// （亮 #B8C6C0 / 暗 #2A342F，设计稿 `--lf-neutral-300`）。圆钮恒为白色：
/// 设计稿两套主题都不改它，与 `primaryForeground`（暗色下是深色）不是一件事。
///
/// 【为什么本件不接手势】命中面由**所在行**提供（整行可点、行高 ≥ 44dp）：
/// 这样读屏只有一个开关节点（行的 `Semantics(toggled:)`），也不会出现
/// 「行与开关各触发一次」的双跳。需要独立开关的页面应在外层自行包手势。
///
/// 【动画】轨道取色与圆钮位移走 `AppMotion.base`（250ms / easeOutCubic，
/// 对应设计稿 `.25s cubic-bezier(.4,0,.2,1)`）；减弱动画下直接呈现终态。
final class LfToggleSwitch extends StatelessWidget {
  const LfToggleSwitch({required this.value, super.key});

  final bool value;

  /// 轨道宽（设计稿 46px）。
  static const double width = 46;

  /// 轨道高（设计稿 28px）。
  static const double height = 28;

  /// 圆钮直径（设计稿 24px）。
  static const double thumbSize = 24;

  /// 圆钮与轨道边的水平内衬（(28−24)/2 = 2，与设计稿 `top/left: 2px` 同值）。
  static const double thumbInset = (height - thumbSize) / 2;

  /// 圆钮投影（设计稿 `0 2px 6px rgba(0,0,0,.15)`）。
  static const List<BoxShadow> _thumbShadow = [
    BoxShadow(offset: Offset(0, 2), blurRadius: 6, color: Color(0x26000000)),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.base;
    final track = value
        ? c.primary
        : LfColors.neutral(Theme.of(context).brightness).tone(300);
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: AnimatedContainer(
          duration: duration,
          curve: AppMotion.curve,
          decoration: BoxDecoration(
            color: track,
            borderRadius: BorderRadius.circular(height / 2),
          ),
          child: AnimatedAlign(
            duration: duration,
            curve: AppMotion.curve,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: thumbInset),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: _thumbShadow,
                ),
                child: SizedBox.square(dimension: thumbSize),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
