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
    this.bandStart,
    this.bandEnd,
    this.bandColor,
    this.pointerRatio,
    this.pointerColor,
  });

  final Color track;
  final Color progress;

  /// 0..1，超出范围由调用方先 clamp（这里只按给定值画）。
  final double ratio;
  final double radius;
  final double stroke;

  // ── 区间带 + 指针（需求 1，2026-10-25）────────────────────────────────
  //
  // 【为什么不只是「把 ratio 换成带」】用户要的是「区间」这件事在环上**看得
  // 见**：绿带 = 目标区间（下限→上限），指针 = 你现在在哪。单值进度弧只能
  // 回答「离上限还有多远」，回答不了「有没有进区间」。
  //
  // 三个都给了才画带；[pointerRatio] 非空则画指针（替代进度弧）。

  /// 带起点（0..1，相对**上限**的刻度）。
  final double? bandStart;

  /// 带终点（0..1）。与 [bandStart] 一起给才生效。
  final double? bandEnd;

  /// 带的颜色（区间用品牌绿；**超上界时调用方换暖色**）。
  final Color? bandColor;

  /// 当前位置（0..1，相对上限）。
  final double? pointerRatio;

  /// 指针颜色。
  final Color? pointerColor;

  /// 指针角度换算（暴露给测试）：0..1 → 弧度。恰好 1.0 画在圆环终点。
  static double pointerAngle(double ratio) {
    final clamped = ratio.clamp(0.0, 1.0);
    return -math.pi / 2 + 2 * math.pi * (clamped >= 1.0 ? 0.9999 : clamped);
  }

  /// 指针圆钮半径（暴露给测试）：随轨道线宽走，下限 5dp。
  ///
  /// 2026-10-29 用户「区间在环上根本看不见」：旧版指针是 `stroke/3`（10dp
  /// 轨道上只有 ~3px）的径向细刻度，被区间带吞掉；改成圆钮后
  /// `10 → 8.5`（直径 17dp），压在带上仍有清晰轮廓（外圈轨道色描边）。
  static double knobRadius(double stroke) => math.max(stroke * 0.85, 5.0);

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
    final bandFrom = bandStart;
    final bandTo = bandEnd;
    if (bandFrom != null && bandTo != null && bandTo > bandFrom) {
      // 【2026-10-31 用户定稿】浅色区间带与圆环**同宽**（不是早期那版
      // stroke×1.9 的加宽淡带——用户：「浅色带能不能跟圆环一样宽，别搞那么
      // 宽行不行」）。它只做「目标区间在哪」的位置标记：band 色 22% 透明度
      // 铺在轨道上，深色进度弧画在其上层；弧走进带内即「在区间中」。
      final arcRect = Rect.fromCircle(center: center, radius: radius);
      final fromAngle = -math.pi / 2 + 2 * math.pi * bandFrom.clamp(0.0, 1.0);
      final sweep =
          2 * math.pi * (bandTo.clamp(0.0, 1.0) - bandFrom.clamp(0.0, 1.0));
      canvas.drawArc(
        arcRect,
        fromAngle,
        sweep,
        false,
        Paint()
          ..color = (bandColor ?? progress).withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
    }
    // 【2026-10-31 实机缺陷（用户：7150 kcal 只显示上边一点点）】旧逻辑在
    // 「有区间带」时**只画带内芯、不画进度弧**——超上限（ratio 夹到 1.0）
    // 时芯只有带那一小段，整条进度弧消失。现在进度弧**无条件**从 0 画到
    // [ratio]（超上限即满圈，暖色由调用方经 [progress] 传入），淡带在外圈
    // 露出的部分就是「目标区间」的标识。
    if (ratio > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * ratio.clamp(0.0, 1.0),
        false,
        Paint()
          ..color = progress
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    final pointer = pointerRatio;
    // 指针只在**弧的中段**（0 < 位置 < 1）出现：0% 没有可指的位置（用户：
    // 「大黑点又是什么」），满圈时圆头弧本身已经标到顶，再画一颗钮反而挡住
    // 「超上限」的完整填充。
    if (pointer != null && pointer > 0 && pointer < 1) {
      // 指针 = 一枚**圆钮**（骑在轨道上），比旧版「stroke/3 细径向刻度」醒目
      // 得多：2026-10-29 用户「区间在环上根本看不见」——旧刻度只有 ~3px 宽，
      // 压在绿带上几乎不可辨，用户把区间带误读成进度弧。
      //
      // 【2026-10-29 实机缺陷】刻度是环形的：`1.0` 的角度与 `0.0` 完全重合
      // （都回到 12 点钟方向）——消耗 6690 kcal（359%）时指针被夹到 1.0，
      // 看起来像「零进度」。把恰好到顶的指针画在**圆环终点**（略差于整圈），
      // 与带的终点重合，语义是「顶满并超出」。
      final angle = pointerAngle(pointer);
      final direction = Offset(math.cos(angle), math.sin(angle));
      final position = center + direction * radius;
      final knobRadius = LfRingPainter.knobRadius(stroke);
      // 外圈一道轨道色细描边：圆钮压在区间带上时仍有清晰轮廓。
      canvas.drawCircle(
        position,
        knobRadius + 1.25,
        Paint()
          ..color = track
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(
        position,
        knobRadius,
        Paint()..color = pointerColor ?? progress,
      );
    }
  }

  @override
  bool shouldRepaint(LfRingPainter oldDelegate) =>
      oldDelegate.track != track ||
      oldDelegate.progress != progress ||
      oldDelegate.ratio != ratio ||
      oldDelegate.radius != radius ||
      oldDelegate.stroke != stroke ||
      oldDelegate.bandStart != bandStart ||
      oldDelegate.bandEnd != bandEnd ||
      oldDelegate.bandColor != bandColor ||
      oldDelegate.pointerRatio != pointerRatio ||
      oldDelegate.pointerColor != pointerColor;
}
