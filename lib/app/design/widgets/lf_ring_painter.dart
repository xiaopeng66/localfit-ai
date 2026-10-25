import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 圆环描边（docs/21 §3.2 的「轨道 = muted、进度 = primary、
/// `stroke-linecap=round`、从 -90° 起」）——两件环共用这一段弧线数学。
///
/// 抽出共享件的原因：今日页的 [LfCalorieRing]（120dp / r=52 / stroke 10）与
/// 食物卡的 `LfFoodKcalRing`（44dp）半径与口径完全不同，但「从 12 点方向
/// 顺时针画 ratio 圈」的实现只该有一份——两处各写一遍就会出现「一个从 12 点、
/// 一个从 3 点」这种肉眼难查但读起来别扭的漂移。
class LfRingPainter extends CustomPainter {
  const LfRingPainter({
    required this.track,
    required this.progress,
    required this.ratio,
    required this.radius,
    required this.stroke,
  });

  final Color track;
  final Color progress;

  /// 0..1，超出范围由调用方先 clamp（这里只按给定值画）。
  final double ratio;
  final double radius;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (ratio <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * ratio,
      false,
      Paint()
        ..color = progress
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(LfRingPainter oldDelegate) =>
      oldDelegate.track != track ||
      oldDelegate.progress != progress ||
      oldDelegate.ratio != ratio ||
      oldDelegate.radius != radius ||
      oldDelegate.stroke != stroke;
}
