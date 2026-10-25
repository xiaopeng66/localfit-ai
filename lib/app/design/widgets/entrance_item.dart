import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/app_motion.dart';

/// 列表项入场：淡入 + 8dp 上移，与页面转场同曲线（docs/21 §2.9）。
///
/// 按 [index] 错峰（相邻 30ms，前 [AppMotion.maxStaggerItems] 项封顶），
/// 懒加载滚动进来的新行以 index 0 时长轻量入场。
/// 「减弱动画」或 [enabled] = false 时直通。
class EntranceItem extends StatefulWidget {
  const EntranceItem({
    super.key,
    required this.index,
    required this.child,
    this.enabled = true,
  });

  final int index;
  final Widget child;
  final bool enabled;

  @override
  State<EntranceItem> createState() => _EntranceItemState();
}

class _EntranceItemState extends State<EntranceItem>
    with SingleTickerProviderStateMixin {
  // 控制器跑满「错峰窗口 + 单件时长」，保证每项实际动画都是完整 250ms。
  static final Duration _total =
      AppMotion.base + AppMotion.stagger * AppMotion.maxStaggerItems;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _total,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || AppMotion.reduced(context)) {
      return widget.child;
    }
    final staggerIndex = widget.index
        .clamp(0, AppMotion.maxStaggerItems - 1)
        .toInt();
    final start =
        (staggerIndex * AppMotion.stagger.inMilliseconds) /
        _total.inMilliseconds;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        start,
        start + AppMotion.base.inMilliseconds / _total.inMilliseconds,
        curve: AppMotion.curve,
      ),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
