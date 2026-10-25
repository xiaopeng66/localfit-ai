import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 图片占位（docs/21 §2.5 / §3.1：**不用生成式纹理**）。
///
/// 设计稿的封面一律是「图片占位渐变 + 图标」：AI 工作页用固定暖色三停靠，
/// 菜单页按营养色系三选一。本件是这两条口径的通用容器，色系由调用方传入
/// （`LfGradients.warmPlaceholder` / `proteinPlaceholder` / `mintPlaceholder` /
/// `fatPlaceholder`），**不伪造菜品照片**（§6.1）。
///
/// 取代旧生成式封面 `AppCoverArt`（5 种 pattern + 6 组封面渐变 + 大 emoji），
/// 后者按 §3.1 于阶段 I-2c 删除。整件不进语义树（纯装饰，语义由相邻的
/// 菜名/标题文字承担）。
class LfCoverPlaceholder extends StatelessWidget {
  const LfCoverPlaceholder({
    super.key,
    required this.gradient,
    this.icon = Icons.restaurant_outlined,
    this.aspectRatio,
    this.borderRadius = 0,
    this.iconSize = 24,
  });

  /// 占位渐变（docs/21 §2.5 的 9 条渐变定义之一，不新增）。
  final LinearGradient gradient;

  /// 占位图标。
  final IconData icon;

  /// 给定高宽比（如 4:3 传 `4 / 3`）；null = 取满父级（外层已定尺寸时用）。
  final double? aspectRatio;

  /// 圆角；外层已有裁剪时传 0（默认）。
  final double borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final content = ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: gradient),
        child: Center(
          child: Icon(
            icon,
            size: iconSize,
            color: context.lf.cardForeground.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
    final aspectRatio = this.aspectRatio;
    final sized = aspectRatio == null
        ? content
        : AspectRatio(aspectRatio: aspectRatio, child: content);
    if (borderRadius <= 0) return sized;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: sized,
    );
  }
}
