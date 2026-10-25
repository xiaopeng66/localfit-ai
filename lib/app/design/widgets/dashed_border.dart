import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';

/// 虚线描边 painter（CSS `border-dashed` 的 4/4 等效物）。
///
/// Flutter 没有内建虚线边框。三处需要它：`DesignCard.dashed`（docs/21 §3.1
/// 「计划态」卡片）、`LfDashedButton`（§3.8 B5「添加」类）、
/// `LfBadge.dashed`（§3.9「晚餐 · 计划」）。原先只有 `design_card.dart`
/// 里一份私有实现，出现第 2、3 个用例时收敛到这里。
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    this.radius = LfDimens.radiusLg,
    this.strokeWidth = 1,
    this.dash = 4,
    this.gap = 4,
  });

  final Color color;

  /// 圆角。要画成**胶囊**时传半高（如 28 高的按钮传 14）——`BorderRadius`
  /// 的半径超过半高时 Flutter 会自动钳到半高，所以传大值也是安全的。
  final double radius;

  final double strokeWidth;

  /// 实线段与间隔长度（设计稿的 `border-dashed` 即 4/4）。
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var draw = true;
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        if (draw) {
          dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        }
        draw = !draw;
        distance = next + gap;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dash != dash ||
      oldDelegate.gap != gap;
}
