import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 新设计进度条（docs/21 §3.2 改造）：统一 6px 全圆角；
/// 信息由相邻文字承载，进度条本身 `ExcludeSemantics`。
class LfProgressBar extends StatelessWidget {
  const LfProgressBar({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
  });

  /// 0..1。
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final ratio = value.clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            children: [
              ColoredBox(color: c.muted, child: const SizedBox.expand()),
              FractionallySizedBox(
                widthFactor: ratio,
                child: ColoredBox(
                  color: color ?? c.primary,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
