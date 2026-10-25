import 'package:flutter/material.dart';

/// 常显、可拖动的滚动条（docs/28 §8.3，用户点名的「滑条」）。
///
/// 一件事只做一次：把 `Scrollbar` 的默认值收到一处——**常显**
/// （`thumbVisibility: true`）且**可拖动**（`interactive: true`）。挂在长列表
/// 上（食物库 4.9 万条、动作库约 300 条、记录页）时，用户看得到「还有多少」，
/// 也能一把拖到任意位置。
///
/// 两种用法：
///  * 传 [controller]（与列表同一个）——需要按拖动落点做事的页面用这种，
///    例如食物库跨过未加载区间时优先加载落点那一页；
///  * 不传——本件自己养一个 controller 并经 `PrimaryScrollController` 交给
///    子滚动视图（子列表不写 `controller` 时默认继承），调用点只需一行包裹。
///
/// 之所以要有「本件自己养 controller」这档：`thumbVisibility: true` 的
/// `Scrollbar` 必须能拿到一个附着在滚动位置上的 controller，否则运行期断言
/// 失败；有些列表（如动作库的网格）不值得为此升 StatefulWidget，包一层就够。
class LfScrollbar extends StatefulWidget {
  const LfScrollbar({required this.child, this.controller, super.key});

  final Widget child;

  /// 与子滚动视图共用的 controller。给 null 时本件自建（见类文档）。
  final ScrollController? controller;

  @override
  State<LfScrollbar> createState() => _LfScrollbarState();
}

class _LfScrollbarState extends State<LfScrollbar> {
  ScrollController? _owned;

  ScrollController get _controller =>
      widget.controller ?? (_owned ??= ScrollController());

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrollbar = Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      interactive: true,
      child: widget.child,
    );
    // 自建 controller 时，用 PrimaryScrollController 把它交给子滚动视图；
    // 子列表自己不写 controller 就会继承它，滑条因此有位置可挂。
    if (widget.controller != null) return scrollbar;
    return PrimaryScrollController(controller: _controller, child: scrollbar);
  }
}
