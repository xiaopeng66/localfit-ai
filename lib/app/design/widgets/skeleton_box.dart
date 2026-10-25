import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';

/// 骨架屏占位块（docs/21 §3.7：1200ms 呼吸——正反各 600ms easeInOut 透明度起落，
/// 圆角与真实卡一致；列表页加载一律骨架屏）。减弱动画时静止在中调不跑呼吸层。
final class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    this.width = double.infinity,
    required this.height,
    this.borderRadius,
    super.key,
  });

  final double width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  // 呼吸半周期 600ms：正反各 600ms 组成 1200ms 一个完整呼吸周期。
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    reverseDuration: const Duration(milliseconds: 600),
  );

  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final component = context.lfc;
    final radius =
        widget.borderRadius ?? BorderRadius.circular(LfDimens.radiusMd);
    // 骨架块是纯装饰占位，加载文案由页面提供；不进入语义树。
    return ExcludeSemantics(
      child: _reduced
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                color: Color.lerp(
                  component.skeletonBase,
                  component.skeletonHighlight,
                  0.5,
                ),
              ),
              child: SizedBox(width: widget.width, height: widget.height),
            )
          : FadeTransition(
              opacity: CurvedAnimation(
                parent: _breath,
                curve: Curves.easeInOut,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: component.skeletonBase,
                ),
                child: SizedBox(width: widget.width, height: widget.height),
              ),
            ),
    );
  }
}

/// 列表加载用的骨架卡片：数量 [count] 张，每张由 [builder] 描述内部结构，
/// 外层圆角/边距与真实卡一致，避免加载前后布局跳动。
final class SkeletonCardList extends StatelessWidget {
  const SkeletonCardList({
    required this.count,
    required this.cardBuilder,
    super.key,
  });

  final int count;
  final Widget Function(BuildContext context) cardBuilder;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.fromLTRB(
      LfDimens.pagePadding,
      0,
      LfDimens.pagePadding,
      LfDimens.spaceLarge,
    ),
    itemCount: count,
    itemBuilder: (context, index) => Padding(
      padding: const EdgeInsets.only(bottom: LfDimens.spaceMedium),
      child: cardBuilder(context),
    ),
  );
}
