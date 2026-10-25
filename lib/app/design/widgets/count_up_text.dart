import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/app_motion.dart';

/// 数字 count-up（docs/21 §3）：数值变化时 800ms easeOutExpo 从旧显示值
/// 滚到新值，中间值随动画渐进展示。
///
/// **首帧直显终值**：首次 build 不跑入场 count-up（首绘已有扫环/入场动画，
/// 数字再滚一遍是叠加噪声），只在 didUpdateWidget 检测到数值变化时滚动。
/// 「减弱动画」开启时直接显示新值。
class CountUpText extends StatefulWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    this.style,
  });

  final double value;

  /// 展示格式（如整数/一位小数 + 单位）；首帧与动画终值都用它渲染。
  final String Function(double value) format;
  final TextStyle? style;

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  late double _displayed = widget.value;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.countUp,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.countUpCurve,
  );
  Tween<double> _tween = Tween<double>(begin: 0, end: 0);

  @override
  void initState() {
    super.initState();
    // 动画结束把终值写回 _displayed：回落到「直显」分支时文本不再跳变。
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _displayed = widget.value);
      }
    });
  }

  @override
  void didUpdateWidget(CountUpText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    if (AppMotion.reduced(context)) {
      _controller.stop();
      setState(() => _displayed = widget.value);
      return;
    }
    // 滚动中再次刷新：从当前显示值续滚（不跳回旧值）。
    final current = _controller.isAnimating
        ? _tween.evaluate(_curve)
        : _displayed;
    setState(() {
      _tween = Tween<double>(begin: current, end: widget.value);
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isAnimating) {
      return Text(widget.format(_displayed), style: widget.style);
    }
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) =>
          Text(widget.format(_tween.evaluate(_curve)), style: widget.style),
    );
  }
}
