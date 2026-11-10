import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_ring_painter.dart';

/// 【2026-10-30 实机反馈（用户三连问）】
///
/// > 「为什么圆环这么丑，而且摄入为 0 的时候，还有一小格，另外那个大黑点
/// > 又是什么，我不是让你加上摄入目标的区间吗。」
///
/// 三件事其实是同一个根因：区间带被画成**与进度同色的一条实弧**，0 摄入时
/// 看起来就是「已经吃了一小段」；指针又是深色圆钮停在起点，像坏点。修法：
///  1. 区间带 = **同宽淡带**（band 25% 透明、宽 = 轨道 10dp；2026-10-31
///     用户：「浅色带能不能跟圆环一样宽，别搞那么宽行不行」）：位置和宽度
///     表达「目标区间在哪」，与「已吃多少」不是同一条视觉通道；
///  2. 带内的**实色芯**只在摄入进入区间后才出现，长度 = 进入区间后的推进量，
///     摄入 0 时芯长 0；
///  3. 指针颜色改品牌深绿（不再是黑点），且 `pointer == 0` 时不画。
void main() {
  LfRingPainter painter({
    required int consumed,
    required int max,
    required int min,
  }) {
    final target = max > 0 ? max : 0;
    final bandMin = min > 0 ? min : null;
    final ratio = target > 0 ? (consumed / target).clamp(0.0, 1.0) : 0.0;
    return LfRingPainter(
      track: const Color(0xFFEFF3F1),
      progress: const Color(0xFF2FBE8F),
      ratio: ratio,
      radius: 52,
      stroke: 10,
      bandStart: bandMin == null ? null : (bandMin / target).clamp(0.0, 1.0),
      bandEnd: bandMin == null ? null : 1.0,
      bandColor: const Color(0xFF2FBE8F),
      pointerRatio: bandMin == null ? null : ratio,
      pointerColor: const Color(0xFF187653),
    );
  }

  /// 记录一次 paint 里画了几段弧、每段的颜色与宽度。
  List<({Color color, double width, double sweep})> arcsOf(
    LfRingPainter painter,
  ) {
    final canvas = _RecordingCanvas();
    painter.paint(canvas, const Size(120, 120));
    return canvas.arcs;
  }

  test('摄入 0：区间带仍在，但带内没有实色芯（不会像「已经吃了一小格」）', () {
    final arcs = arcsOf(painter(consumed: 0, max: 1844, min: 1669));
    // 轨道是用 drawCircle(stroke) 画的（不在 arcs 里）；0 摄入只该有
    // **淡带一段**，没有实色芯、也没有指针。
    expect(arcs, hasLength(1), reason: '0 摄入只该有淡带：$arcs');
    // 【2026-10-31 用户：带与环同宽】带宽 = 轨道 10dp，不再是 19。
    expect(arcs.last.width, closeTo(10, 0.001));
    // 淡带与实色芯是同色不同透明度：0 摄入时不该出现不透明的带。
    expect(
      arcs.any((a) => a.color.a > 0.5 && a.width == 10),
      isFalse,
      reason: '0 摄入时不该有 10dp 实弧（那会被读成已吃）',
    );
  });

  test('摄入进入区间：进度弧从 0 画满到当前位置（不是只画带内一小段）', () {
    // 【2026-10-31 用户实机：7150 kcal 只显示上边一点点】旧版在有带时只画
    // 「带内芯」——超上限时芯只有带那一小段。现在进度弧无条件从 0 画。
    final arcs = arcsOf(painter(consumed: 1750, max: 1844, min: 1669));
    // 淡带 + 进度弧 = 2 段（轨道走 drawCircle，不在 arcs 里）。
    expect(arcs, hasLength(2), reason: '$arcs');
    final progressArc = arcs.last;
    expect(progressArc.width, 10);
    expect(progressArc.color.a, 1.0);
    expect(
      progressArc.sweep,
      closeTo((1750 / 1844) * 2 * 3.141592653589793, 0.01),
      reason: '进度弧从 12 点画到当前位置（不是只画带内部分）',
    );
  });

  test('超上限：进度弧满圈（不是只有带那一小段）', () {
    final arcs = arcsOf(painter(consumed: 7150, max: 1560, min: 1412));
    final progressArc = arcs.last;
    expect(
      progressArc.sweep,
      closeTo(2 * 3.141592653589793, 0.001),
      reason: '超上限 = 满圈实弧',
    );
  });

  test('未进区间（低于下限）：进度弧照常从 0 画，终点不越过带起点', () {
    final arcs = arcsOf(painter(consumed: 1000, max: 1844, min: 1669));
    final progressArc = arcs.last;
    expect(progressArc.width, 10);
    expect(
      progressArc.sweep,
      closeTo((1000 / 1844) * 2 * 3.141592653589793, 0.01),
    );
  });

  test('摄入 0 不画指针（大黑点消失）', () {
    final painter0 = painter(consumed: 0, max: 1844, min: 1669);
    final canvas = _RecordingCanvas();
    painter0.paint(canvas, const Size(120, 120));
    // 轨道（描边圆）可以画；0% 时不该有**实心圆**（指针）。
    expect(
      canvas.circles.where((c) => c.filled),
      isEmpty,
      reason: '0% 时不该画指针圆钮',
    );
  });

  test('有摄入时指针用品牌深绿（不是黑）', () {
    final painter1 = painter(consumed: 1750, max: 1844, min: 1669);
    final canvas = _RecordingCanvas();
    painter1.paint(canvas, const Size(120, 120));
    final filled = canvas.circles.where((c) => c.filled).toList();
    expect(filled, isNotEmpty, reason: '有摄入时要画指针');
    // 用 ARGB 比：Color 的 == 受 colorSpace 影响（同一个 sRGB 值可能不相等）。
    expect(
      filled.last.color.toARGB32(),
      LfColors.brandStrong(Brightness.light).toARGB32(),
      reason: '指针是品牌色圆钮，不是「大黑点」',
    );
  });
}

/// 只记录弧与圆的画布（不真画）。
class _RecordingCanvas implements Canvas {
  final arcs = <({Color color, double width, double sweep})>[];
  final circles = <({Color color, double radius, bool filled})>[];

  @override
  void drawArc(
    Rect rect,
    double startAngle,
    double sweepAngle,
    bool useCenter,
    Paint paint,
  ) {
    arcs.add((color: paint.color, width: paint.strokeWidth, sweep: sweepAngle));
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    circles.add((
      color: paint.color,
      radius: radius,
      filled: paint.style == PaintingStyle.fill,
    ));
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}
