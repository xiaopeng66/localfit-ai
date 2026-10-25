import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 庆祝粒子爆发（docs/21 §2.9）：全屏 mint 粒子 1.2s（30 粒子、
/// 物理下落、CustomPainter 自绘，零新增依赖）+ 弹性展示总结卡。
/// 每次会话最多触发 1 次防打扰（[AppCelebrationGuard]，触发点由调用方
/// 决定——如训练结束总结、达成当日目标）。减弱动画（disableAnimations）
/// 时不播放粒子，直接结束。
///
/// 设计层通用件：不含任何业务逻辑；弹层总结卡仍由调用方（AppSheet）
/// 呈现，本组件只负责粒子层。
abstract final class AppCelebrationGuard {
  static bool _shownThisSession = false;

  /// 本会话是否还能触发。
  static bool get canTrigger => !_shownThisSession;

  /// 标记触发；返回是否真的触发了（false＝本会话已经放过）。
  static bool markTriggered() {
    if (_shownThisSession) return false;
    _shownThisSession = true;
    return true;
  }

  @visibleForTesting
  static void resetForTest() => _shownThisSession = false;
}

/// 在最近 Overlay 上插入一次庆祝粒子爆发；每会话最多 1 次。
/// 返回是否真的触发了。粒子播完自动移除。
bool showAppCelebration(BuildContext context) {
  if (!AppCelebrationGuard.markTriggered()) return false;
  var removed = false;
  // 闭包不能引用自己的初始化表达式，分两步声明。
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => AppCelebrationBurst(
      onDone: () {
        if (removed) return;
        removed = true;
        entry.remove();
      },
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return true;
}

/// 全屏粒子层：IgnorePointer + ExcludeSemantics（纯装饰）。
/// 1.2s 有界动画，播完回调 [AppCelebration.onDone]。
class AppCelebrationBurst extends StatefulWidget {
  const AppCelebrationBurst({super.key, this.onDone});

  final VoidCallback? onDone;

  static const Duration duration = Duration(milliseconds: 1200);
  static const int particleCount = 30;

  @override
  State<AppCelebrationBurst> createState() => _AppCelebrationBurstState();
}

class _AppCelebrationBurstState extends State<AppCelebrationBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppCelebrationBurst.duration,
  );
  var _started = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDone?.call();
        // 播完把粒子层从树上撤下（painter 在 progress>=1 不再绘制）。
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.disableAnimationsOf(context)) {
      _controller.forward();
    } else {
      // 减弱动画：不播放粒子，直接结束（下一帧移除）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onDone?.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) || _controller.isCompleted) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            key: const Key('app-celebration-painter'),
            size: MediaQuery.sizeOf(context),
            painter: _CelebrationPainter(_controller.value),
          ),
        ),
      ),
    );
  }
}

/// 粒子物理：从画面中下方炸开后受重力下落，末 30% 淡出。
/// 粒子参数全部确定性推导（同帧同画面结果一致），颜色取 mint 系 +
/// 蜜黄/珊瑚点缀（纯色粒子，不新增渐变）。
class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter(this.progress);

  final double progress;

  /// 装饰性彩屑：设计稿未规定暗色彩屑，两套主题共用亮色 ramp 锚点
  /// （粒子是叠加层，不参与表面层级）。
  static final _palette = <Color>[
    LfColors.mintLight.tone(400),
    LfColors.mintLight.tone(500),
    LfColors.mintLight.tone(700),
    LfColors.carbsLight,
    LfColors.proteinLight,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final origin = Offset(size.width / 2, size.height * 0.62);
    final spread = math.min(size.width, size.height) * 0.55;
    final paint = Paint()..style = PaintingStyle.fill;
    final fade = progress < 0.7 ? 1.0 : 1.0 - (progress - 0.7) / 0.3;
    for (var i = 0; i < AppCelebrationBurst.particleCount; i++) {
      final angle =
          2 * math.pi * (i / AppCelebrationBurst.particleCount) + i * 0.13;
      final speed = 0.7 + 0.6 * ((i * 37 % 10) / 10);
      final t = progress;
      final x = origin.dx + math.cos(angle) * speed * spread * t;
      // 先向上炸开（sin<0 的粒子向上），再受重力加速下落。
      final y =
          origin.dy +
          math.sin(angle) * speed * spread * t +
          0.9 * spread * t * t;
      paint.color = _palette[i % _palette.length].withValues(alpha: fade);
      final side = 3.0 + (i % 4) * 1.5;
      if (i.isEven) {
        canvas.drawCircle(Offset(x, y), side / 2, paint);
      } else {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(angle + t * 2);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: side, height: side * 0.6),
          paint,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_CelebrationPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
