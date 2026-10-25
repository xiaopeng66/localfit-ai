import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';

/// 固定底部主操作条（docs/21 §3 `FixedBottomPrimaryAction`）。
///
/// 拍照识餐确认、训练会话操作等 route-level 页面用它把主操作钉在底部：
/// 内容区在 `SafeArea` 之上滚动，操作条自带安全区避让，键盘弹起时随
/// `MediaQuery.viewInsets` 上移，因此底部元素**始终可点**（docs/21 §5.8.3 验收项）。
///
/// 用 [Scaffold.bottomNavigationBar] 或 `Column` 末尾承载；不要放进
/// `Stack` 里靠 `Positioned` 悬停——那样会被软键盘盖住。
final class FixedBottomPrimaryAction extends StatelessWidget {
  const FixedBottomPrimaryAction({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      LfDimens.pagePadding,
      LfDimens.spaceMedium,
      LfDimens.pagePadding,
      LfDimens.spaceMedium,
    ),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final semantic = context.lf;
    // 键盘弹起时把操作条顶上去（docs/21 §5.8.3「底部元素始终可点」）。挂在
    // `Scaffold.bottomNavigationBar` 时 Scaffold 会按 viewInsets 收缩 body，
    // 但操作条本身仍贴在收缩后的底边——不显式加这段底部内边距，按钮会被
    // 软键盘盖住（route_keyboard_avoidance_test 量过矩形）。
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final resolved = padding.resolve(Directionality.of(context));
    return Material(
      color: semantic.card,
      elevation: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: semantic.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: resolved + EdgeInsets.only(bottom: keyboardInset),
            child: child,
          ),
        ),
      ),
    );
  }
}
