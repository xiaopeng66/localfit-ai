import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/app_haptics.dart';
import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';

/// 休息倒计时横幅（docs/21 §3）：大号环形倒计时（环心 display 档数字）+
/// 最后 3 秒脉冲放大 + 结束轻震。
///
/// 刻意做成训练记录弹层内的常驻横幅而非全屏遮断：休息期间还要继续
/// 记组（docs/21 字面「全屏环形倒计时」与本应用交互冲突，决策记
/// STATUS/证据）。业务文案「休息 Ns」与 key `training-rest-countdown`
/// 逐字保留；减弱动画下脉冲层退化为静止，触觉不是动画照常触发。
class RestCountdown extends StatefulWidget {
  const RestCountdown({
    super.key,
    required this.restEnd,
    required this.total,
    this.clock = _defaultClock,
  });

  final DateTime restEnd;

  /// 本轮休息总时长（环的满刻度）。
  final Duration total;

  /// 测试注入时钟；默认本地现在。
  final DateTime Function() clock;

  static DateTime _defaultClock() => DateTime.now();

  @override
  State<RestCountdown> createState() => _RestCountdownState();
}

class _RestCountdownState extends State<RestCountdown>
    with SingleTickerProviderStateMixin {
  static const _pulsePeriod = Duration(milliseconds: 600);

  Timer? _timer;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: _pulsePeriod,
  );
  bool _endHapticFired = false;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(RestCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新一组记录会把 restEnd 向后推；计时器可能已在上一轮归零时取消，
    // 必须在 restEnd 变化时重新挂载，否则倒计时永久冻结。
    if (widget.restEnd != oldWidget.restEnd) {
      _timer?.cancel();
      _endHapticFired = false;
      _arm();
    }
  }

  void _arm() {
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final wasRunning = _remaining > 0;
    final left = restSecondsRemaining(widget.restEnd, widget.clock());
    setState(() => _remaining = left);
    if (left == 0) {
      _timer?.cancel();
      _pulse.stop();
      if (wasRunning && !_endHapticFired) {
        _endHapticFired = true;
        AppHaptics.light();
      }
    } else if (left <= 3) {
      if (!AppMotion.reduced(context) && !_pulse.isAnimating) {
        _pulse.repeat();
      }
    } else {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining == 0) return const SizedBox.shrink();

    Widget ring = SizedBox(
      width: 88,
      height: 88,
      child: CustomPaint(
        painter: RestRingPainter(
          remainingSeconds: _remaining,
          totalSeconds: widget.total.inSeconds,
          trackColor: context.lf.card,
          progressColor: context.lf.primary,
        ),
        child: Center(
          child: ExcludeSemantics(
            child: Text(
              '$_remaining',
              style: LfText.displayHero.copyWith(
                color: LfColors.mint(Theme.of(context).brightness).tone(700),
              ),
            ),
          ),
        ),
      ),
    );
    // 最后 3 秒脉冲放大：正弦一升一降（600ms 一个周期，峰 1.06）。
    if (!AppMotion.reduced(context) && _remaining <= 3) {
      ring = AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final scale = 1.0 + 0.06 * math.sin(math.pi * _pulse.value);
          return Transform.scale(scale: scale, child: child);
        },
        child: ring,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceLarge,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: LfColors.mint(Theme.of(context).brightness).tone(100),
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
      ),
      child: Row(
        children: [
          ring,
          const SizedBox(width: LfDimens.spaceLarge),
          Icon(
            Icons.timer_outlined,
            size: 20,
            color: LfColors.mintText(Theme.of(context).brightness),
            semanticLabel: '休息计时',
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              // 倒计时逐秒变化，标记为 live region 让屏幕阅读器播报剩余时间。
              liveRegion: true,
              child: Text(
                '休息 ${_remaining}s',
                key: const Key('training-rest-countdown'),
                style: LfText.bodySmall.copyWith(
                  color: LfColors.mint(Theme.of(context).brightness).tone(700),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 休息环：track（卡片色）+ primary 进度弧，从顶部顺时针收缩。
/// 字段公开以便测试直接断言进度，避免碰 painter 私有成员。
class RestRingPainter extends CustomPainter {
  RestRingPainter({
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.trackColor,
    required this.progressColor,
  });

  final int remainingSeconds;
  final int totalSeconds;

  /// 取色必须由调用方注入（CustomPainter 拿不到 BuildContext），
  /// 否则暗色主题下轨道/进度弧会停在亮色值。
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    const stroke = 6.0;
    final arcRect = Rect.fromCircle(
      center: center,
      radius: radius - stroke / 2,
    );

    canvas.drawCircle(
      center,
      radius - stroke / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    final progress = totalSeconds <= 0 ? 0.0 : remainingSeconds / totalSeconds;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = progressColor,
    );
  }

  @override
  bool shouldRepaint(RestRingPainter oldDelegate) =>
      oldDelegate.remainingSeconds != remainingSeconds ||
      oldDelegate.totalSeconds != totalSeconds ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}
