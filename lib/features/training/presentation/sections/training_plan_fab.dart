import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/pressable_scale.dart';

/// 右下「新建计划」圆钮（docs/21 §5.5 `cta-new-plan`，设计稿
/// `训练.html` §6：`w-12 h-12 rounded-full` + `background: var(--lf-primary)`
/// + `box-shadow: 0 4px 16px primary/40%`）。
///
/// 阴影取 [LfShadows.fabPrimary]——§2.4 的彩色阴影白名单里这一条就是为它
/// 定义的（primary 40%、blur 16、**无负 spread**），与饮食记录页 FAB 的
/// `recordFab`（30%、blur 12）不是同一条，别混用。
class TrainingPlanFab extends StatelessWidget {
  const TrainingPlanFab({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  /// 设计稿 `bottom-[calc(80px_+_env(safe-area-inset-bottom))]`——与记录页 FAB
  /// 同值（栏高 64 + 净上凸 9.5 ≈ 73.5，设计稿取 80 留余量）。
  static const double bottomOffset = 80;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final button = PressableScale(
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          key: const Key('cta-new-plan'),
          color: c.primary,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Tooltip(
              message: '新建计划',
              child: Icon(Icons.add, size: 24, color: c.primaryForeground),
            ),
          ),
        ),
      ),
    );
    // 阴影单独一层：Material 的 elevation 会连带影响 ink 绘制，设计稿的
    // 彩色阴影要精确控制，用 DecoratedBox 包在外层更可控。
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: LfShadows.fabPrimary(c.primary),
      ),
      child: Padding(padding: const EdgeInsets.all(1), child: button),
    );
  }
}

/// 把 [TrainingPlanFab] 定位到页面右下（设计稿 `fixed bottom-[80px] right-4`）。
///
/// 独立成件而不是用 `Scaffold.floatingActionButton`：本页是 shell 分支内的
/// 页面，`extendBody` 后 FAB 的默认 16dp 底边距会落进导航栏体里。
class PositionedTrainingPlanFab extends StatelessWidget {
  const PositionedTrainingPlanFab({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // 与记录页 FAB 同一坑：shell 的 `Scaffold(extendBody:true)` 会把 body 的
    // `padding.bottom` 顶成底栏高度（73.5dp + 手势带），FAB 等于把底栏又加了
    // 一遍、整体漂高 73.5dp。手势带只能问视图（[LfInsets.bottom]）。
    final safeBottom = LfInsets.bottom(context);
    return Positioned(
      right: LfDimens.pagePadding,
      bottom: TrainingPlanFab.bottomOffset + safeBottom,
      child: TrainingPlanFab(onPressed: onPressed),
    );
  }
}
