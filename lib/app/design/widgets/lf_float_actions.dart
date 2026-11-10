import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/pressable_scale.dart';

/// 右下角**浮动动作**（需求 13a / 13b，2026-10-25）：
/// 两页共用同一个组件与同一套几何，不再各写一份。
///
/// **13a**「管理食堂目录」从菜单页页尾的 `.list-link` 行挪到右下浮动按钮；
/// **13b** 训练页把「训练达标 / 动作库 / ➕」收成右下**一列**三枚。
///
/// 【为什么自绘而不是 `Scaffold.floatingActionButton`】两页都住在 shell 的
/// 分支导航器里（`extendBody`），`FloatingActionButton` 的默认 16dp 底边距
/// 会落进导航栏体里——必须自己按 [LfInsets.navReserve] 抬起来
/// （与既有 `PositionedTrainingPlanFab` 同一条实测结论）。
///
/// 【两档样式】
/// * [LfFloatingAction.emphasized]（默认）：48dp 实心主色圆 + 彩色阴影 =
///   页面**主行动**（训练页的 ➕）；
/// * 非 emphasized（纯图标）：同样 48dp **深绿实心圆 + 反白图标**
///   （2026-11-03 用户：几个按钮都做成加号的深绿色背景）。
///   2026-10-28 曾用 mint-100 浅底区分主次；用户 2026-11-03 明确要求整簇
///   统一深绿，遂改为与 ➕ 同底同尺寸，靠位置（在 ➕ 上方）区分层级。
/// * 带字档（`label != null`）仍走白卡 + 描边 + 表面阴影：它是菜单页的
///   唯一入口，文字已经承担识别，底色不必再叠一层品牌色。
final class LfFloatingAction {
  const LfFloatingAction({
    required this.actionKey,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.emphasized = false,
    this.label,
  });

  /// 稳定 Key（既有 Key 全部沿用：`cta-new-plan` / `training-target-progress`
  /// / `training-exercise-library` / `cta-manage-canteen`）。
  final Key actionKey;

  final IconData icon;

  /// tooltip 与读屏标签（纯图标钮必须给，§5.8.3）。
  final String semanticLabel;

  final VoidCallback? onPressed;

  /// true = 实心主色（主行动）。
  final bool emphasized;

  /// 可见文字（Material 的「extended FAB」形态）；null = 纯图标圆钮。
  ///
  /// 【什么时候给】入口**只有一枚**、且语义无法从图标一眼看出时给
  /// （菜单页的「管理食堂目录」）。图标钮的可发现性天生弱于带字钮：用户
  /// 反馈里点名要它「挪到右下」，不是要它变成一枚看不懂的图标。
  /// 训练页那三枚（达标 / 动作库 / ➕）是图标语义明确的常用动作，保持圆钮
  /// 一排——三枚带字会横着吃掉半屏。
  final String? label;
}

/// 一列浮动动作（**从上到下**给，主行动放最后 = 最下面）。
class LfFloatingActions extends StatelessWidget {
  const LfFloatingActions({super.key, required this.actions});

  final List<LfFloatingAction> actions;

  /// 两枚之间的间距。
  static const double gap = 12;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          _LfFloatingActionButton(action: actions[i]),
        ],
      ],
    );
  }
}

/// 把 [LfFloatingActions] 定位到右下（`fixed right-4 bottom-[80px]`）。
class PositionedLfFloatingActions extends StatelessWidget {
  const PositionedLfFloatingActions({
    super.key,
    required this.actions,
    this.bottomOffset = defaultBottomOffset,
  });

  final List<LfFloatingAction> actions;

  /// 底边距（不含手势带）。【2026-10-31 用户：两页加号位置要一致】
  /// 80 → **96**，与 `RecordFab.bottomOffset` 同值——训练页/菜单页/记录页
  /// 的最下那枚浮钮现在永远在同一高度。
  final double bottomOffset;

  static const double defaultBottomOffset = 96;

  /// 训练页一列三枚沿用的底边距（列从下往上长，底边距不变主行动不漂）。
  static const double columnBottomOffset = 96;

  /// 滚动容器末尾至少要留出的高度：**让最后一行内容能滚出这列浮钮的覆盖带**
  /// （与 `RecordFab.contentClearance` 同一命题；2026-10-31 用户实机：2.0×
  /// 字号下「训练历史」被这列浮钮盖住）。
  ///
  /// 占位 = 各枚直径（统一 48）+ 每枚阴影按盒外沿绘制（无内衬）+ 枚间 12dp，
  /// 再加底边距；与 `navReserve` 取较大值（手势带很大时也不少于底栏预留）。
  static double columnContentClearance(
    BuildContext context, {
    int emphasized = 0,
    int plain = 0,
  }) {
    final count = emphasized + plain;
    final column =
        emphasized * 48 + plain * 48 + (count - 1) * LfFloatingActions.gap;
    final reserve = LfInsets.navReserve(context);
    final above = LfInsets.bottom(context) + columnBottomOffset + column;
    return above > reserve ? above : reserve;
  }

  @override
  Widget build(BuildContext context) {
    // shell 的 `Scaffold(extendBody:true)` 会把 body 的 padding.bottom 顶成
    // 底栏高度（73.5 + 手势带），照抄会让整列再漂高一个底栏；手势带只能问视图。
    final safeBottom = LfInsets.bottom(context);
    return Positioned(
      right: LfDimens.pagePadding,
      bottom: bottomOffset + safeBottom,
      child: LfFloatingActions(actions: actions),
    );
  }
}

class _LfFloatingActionButton extends StatelessWidget {
  const _LfFloatingActionButton({required this.action});

  final LfFloatingAction action;

  /// 圆钮直径——**全部档位统一 48**（2026-10-31 用户：训练页与饮食页的
  /// 加号/次级钮大小不一致；与 `RecordFab` 同一实测值）。
  static const double primarySize = 48;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final emphasized = action.emphasized;
    final size = primarySize;
    final label = action.label;
    // 纯图标次级：与主行动同一枚深绿实心圆（2026-11-03 用户：几个按钮都
    // 做成加号的深绿色背景）。旧稿 mint-100 浅底是为了「不抢戏」，但用户
    // 明确要求整簇统一深绿；图标改用 onBrandStrong 保证对比度。
    final soft = !emphasized && label == null;
    final fill = emphasized
        ? LfColors.brandStrong(brightness)
        : soft
        ? LfColors.brandStrong(brightness)
        : c.card;
    final foreground = emphasized
        ? LfColors.onBrandStrong(brightness)
        : soft
        ? LfColors.onBrandStrong(brightness)
        : c.mutedForeground;
    // 【白边修复（2026-11-02 用户再次点名「训练页加号还有白边」）】
    // 纯图标档只有**非 emphasised 的软底次级**用无描边圆；emphasised 落到
    // 下面的三元里又吃了一圈 `c.border`——浅色页面上就是 1px 白边。
    // 实心主行动与软底次级一样，圆形本身就是边界，不需要描边。
    final shape = label == null
        ? const CircleBorder()
        : StadiumBorder(
            side: emphasized ? BorderSide.none : BorderSide(color: c.border),
          );
    final visible = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          action.icon,
          size: emphasized ? 24 : (soft ? 22 : 20),
          color: foreground,
        ),
        if (label != null) ...[
          const SizedBox(width: LfDimens.spaceSmall),
          Text(
            label,
            style: LfText.captionStrong.copyWith(
              color: emphasized
                  ? LfColors.onBrandStrong(brightness)
                  : c.cardForeground,
            ),
          ),
        ],
      ],
    );
    final inner = Semantics(
      button: true,
      label: action.semanticLabel,
      onTap: action.onPressed,
      container: true,
      child: visible,
    );
    final button = PressableScale(
      child: label == null
          ? SizedBox(
              width: size,
              height: size,
              child: Material(
                key: action.actionKey,
                color: fill,
                shape: shape,
                elevation: 0,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: action.onPressed,
                  child: Tooltip(
                    message: action.semanticLabel,
                    // 标签由 `Semantics` 提供，tooltip 不重复挂同名节点。
                    excludeFromSemantics: true,
                    // 【图标必须居中】2026-10-28 用户实机截图：纯图标档的
                    // Row 默认左对齐，flag/哑铃这类宽窄不一的字形在圆里
                    // 明显偏左。`Center` 兜底（`widthFactor: 1` 让 Row 仍
                    // 只占图标宽，不撑满 SizedBox）。
                    child: Center(widthFactor: 1, child: inner),
                  ),
                ),
              ),
            )
          // 带字档：宽度随文字（`minWidth` 保 48 触达），高度仍是 48。
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: primarySize),
              child: Material(
                key: action.actionKey,
                color: fill,
                shape: shape,
                elevation: 0,
                child: InkWell(
                  customBorder: shape,
                  onTap: action.onPressed,
                  child: Tooltip(
                    message: action.semanticLabel,
                    excludeFromSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LfDimens.spaceMedium,
                        vertical: LfDimens.spaceSmall,
                      ),
                      child: inner,
                    ),
                  ),
                ),
              ),
            ),
    );
    // 阴影单独一层：Material 的 elevation 会连带影响 ink 绘制。
    // 【2026-10-31 用户统一】三档全部同一套彩色浮起阴影——此前次级软底档
    // 无阴影，用户：「动作库和训练达标的按钮没有同样的悬浮效果」。
    //
    // 【白边修复（用户：训练页的按钮有一个白边）】原实现给 DecoratedBox 加
    // 1dp 内衬再缩按钮——内衬区透明，浅底页面上就是一圈白边。改为
    // DecoratedBox 直接填与按钮同色（阴影画在盒外沿，不再依赖内衬兜底），
    // 内衬删除。
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: label == null ? null : BorderRadius.circular(999),
        shape: label == null ? BoxShape.circle : BoxShape.rectangle,
        boxShadow: LfShadows.fabPrimary(c.primary),
      ),
      child: button,
    );
  }
}
