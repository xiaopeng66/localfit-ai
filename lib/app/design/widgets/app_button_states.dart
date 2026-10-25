import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/app_motion.dart';

/// 按钮加载/成功态（docs/21 §3.7）：胶囊内三点跳动 + ✓ 打勾 300ms。
/// 减弱动画（disableAnimations）退化为静态三点/直显。

/// 三点跳动加载指示（按钮/行内联）：三点依次上浮（相位差 2π/3，仅上浮不
/// 下沉），600ms 一个循环；颜色默认取环境 IconTheme——按钮内即前景色、
/// 行内即默认图标色。
class AppButtonDotsLoader extends StatefulWidget {
  const AppButtonDotsLoader({super.key});

  @override
  State<AppButtonDotsLoader> createState() => _AppButtonDotsLoaderState();
}

class _AppButtonDotsLoaderState extends State<AppButtonDotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _bounce.stop();
    } else if (!_bounce.isAnimating) {
      _bounce.repeat();
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          AnimatedBuilder(
            animation: _bounce,
            builder: (context, _) {
              // 仅上浮：负半周钳到 0（点不下沉）。
              final lift = math.max(
                0.0,
                math.sin(2 * math.pi * _bounce.value - i * 2 * math.pi / 3),
              );
              return Transform.translate(
                offset: Offset(0, -AppMotion.dotsLift * lift),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

/// 成功态 ✓ 打勾（docs/21 §3）：出现时 300ms 弹簧缩放（easeOutBack），
/// 减弱动画直显。
class AppSuccessCheck extends StatefulWidget {
  const AppSuccessCheck({required this.icon, super.key});

  final Widget icon;

  @override
  State<AppSuccessCheck> createState() => _AppSuccessCheckState();
}

class _AppSuccessCheckState extends State<AppSuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );

  bool _armed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    _armed = true;
    if (!AppMotion.reduced(context)) {
      _pop.forward();
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return widget.icon;
    return ScaleTransition(
      scale: CurvedAnimation(parent: _pop, curve: Curves.easeOutBack),
      child: widget.icon,
    );
  }
}
