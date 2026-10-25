import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:localfit_ai/app/design/app_motion.dart';

/// 统一按压反馈（docs/21 §2.3 按压变形）：可点卡片/行按下时以 springQuick
/// 弹簧压到 0.97，释放回弹到 1，带真实惯性。
///
/// 不接管点击——onTap 仍由外层（ListTile / InkWell / GestureDetector）处理，
/// 本组件只监听指针事件切换缩放状态；「减弱动画」开启时直通不缩放。
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressScale = 0.97,
  });

  final Widget child;

  /// false 时完全直通（用于滚动拖拽等不应缩放的宿主）。
  final bool enabled;

  /// 按压目标缩放（docs/21 §2.3：0.97）。
  final double pressScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale>
    with SingleTickerProviderStateMixin {
  // unbounded：弹簧目标在 0.97~1 之间，但控制器不许把值夹到 [0,1]。
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  void _to(double target) {
    _controller.animateWith(
      SpringSimulation(AppMotion.springQuick, _controller.value, target, 0),
    );
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
    return Listener(
      onPointerDown: (_) => _to(widget.pressScale),
      onPointerUp: (_) => _to(1),
      onPointerCancel: (_) => _to(1),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) =>
            Transform.scale(scale: _controller.value, child: child),
        child: widget.child,
      ),
    );
  }
}
