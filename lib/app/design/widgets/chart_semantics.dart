import 'package:flutter/material.dart';

/// 图表容器 + 语义摘要（docs/21 §3「图表容器和图表 Semantics 摘要」，
/// docs/21 §5.8.3「图表有文字摘要，不依赖颜色或图形 alone」）。
///
/// 用法：把 painter / fl_chart 画布放进 [child]，把同义文字摘要传给
/// [summary]。摘要经 [Semantics.label] 播报，图形本身 `excludeSemantics`
/// 排除，因此 TalkBack 读到的是完整句子而不是散落的图例。
///
/// 页面必须同时把摘要以可见文字渲染出来（通常放在图表下方的 caption），
/// 本组件只负责无障碍侧的等价表达。
final class ChartSemantics extends StatelessWidget {
  const ChartSemantics({required this.summary, required this.child, super.key});

  /// 图表的完整文字摘要，如「近 7 日体重：69.4 公斤，比周初下降 0.8 公斤」。
  final String summary;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: summary,
      container: true,
      excludeSemantics: true,
      child: ExcludeSemantics(child: child),
    );
  }
}
