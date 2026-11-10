import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_float_actions.dart';
import 'package:localfit_ai/app/design/widgets/record_fab.dart';

/// 训练页右下浮钮簇（2026-11-02 用户裁决）。
///
/// **形态**：
/// * ➕ 常驻最下，直接复用记录页的 [RecordFab]——同一枚 48dp 实心圆、
///   同一套彩色阴影、无描边（此前训练页自绘浮钮被点名「还有白边」）；
/// * ➕ 上方一枚 **48dp 深绿**「上拉三角」（2026-11-03 用户：圆的大小与
///   水平位置都要和加号一致）；平时只露这一枚，点开后向上展开
///   **训练统计 / 训练达标 / 动作库** 三枚同款深绿圆钮，再点三角或页面
///   空白处收回；
/// * 展开时铺一层全屏透明挡板：点任何非按钮区域都只做「收回」，不会误触
///   页面内容（用户要求「点击到别的地方的时候就恢复收回的状态」）。
///
/// **为什么自绘 Positioned 而不是 `Scaffold.floatingActionButton`**：本页住在
/// shell 的分支导航器里（`extendBody`），FAB 默认 16dp 底边距会落进底栏；
/// 仍按 [LfInsets.bottom] 抬到导航栏之上，与记录页同一几何。
class TrainingFloatingActions extends StatefulWidget {
  const TrainingFloatingActions({
    super.key,
    required this.onNewPlan,
    required this.onExerciseLibrary,
    this.onTrainingTargets,
    this.onStatistics,
  });

  final VoidCallback onNewPlan;
  final VoidCallback onExerciseLibrary;

  /// 训练达标（需要会话仓储）。null = 不渲染该入口。
  final VoidCallback? onTrainingTargets;

  /// 训练统计（需要会话仓储）。null = 不渲染该入口。
  final VoidCallback? onStatistics;

  /// 收缩态 + 展开态里最高的一列（统计/达标/动作库 + 三角 + ➕）。
  ///
  /// 页面列表用它留底距：展开时内容必须还能滚到浮层之上，而不是被三枚
  /// 圆钮盖住最后一行（与 `RecordFab.contentClearance` 同一命题）。
  static double contentClearance(BuildContext context) {
    const expanded =
        RecordFab.footprint +
        _gap +
        _toggleSize +
        _gap +
        3 * _actionSize +
        2 * _gap;
    final reserve = LfInsets.navReserve(context);
    final above = LfInsets.bottom(context) + RecordFab.bottomOffset + expanded;
    return above > reserve ? above : reserve;
  }

  static const double _gap = 10;

  /// 三角与加号同一枚 48dp 圆（2026-11-03 用户：圆形大小要和加号一样）。
  static const double _toggleSize = 48;
  static const double _actionSize = 48;

  @override
  State<TrainingFloatingActions> createState() =>
      _TrainingFloatingActionsState();
}

class _TrainingFloatingActionsState extends State<TrainingFloatingActions> {
  bool _expanded = false;

  void _collapse() {
    if (_expanded) setState(() => _expanded = false);
  }

  void _activate(VoidCallback action) {
    if (!mounted) return;
    setState(() => _expanded = false);
    action();
  }

  @override
  Widget build(BuildContext context) {
    final safeBottom = LfInsets.bottom(context);
    final actions = <LfFloatingAction>[
      if (widget.onStatistics != null)
        LfFloatingAction(
          actionKey: const Key('training-stats'),
          icon: Icons.assessment_outlined,
          semanticLabel: '训练统计',
          onPressed: () => _activate(widget.onStatistics!),
        ),
      if (widget.onTrainingTargets != null)
        LfFloatingAction(
          actionKey: const Key('training-target-progress'),
          icon: Icons.flag_outlined,
          semanticLabel: '训练达标',
          onPressed: () => _activate(widget.onTrainingTargets!),
        ),
      LfFloatingAction(
        actionKey: const Key('training-exercise-library'),
        icon: Icons.fitness_center,
        semanticLabel: '动作库',
        onPressed: () => _activate(widget.onExerciseLibrary),
      ),
    ];
    return Positioned.fill(
      child: Stack(
        children: [
          // 展开态挡板：透明，但吃掉点击 —— 点页面任何地方只做「收回」。
          if (_expanded)
            Positioned.fill(
              child: ExcludeSemantics(
                child: GestureDetector(
                  key: const Key('training-actions-scrim'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _collapse,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          Positioned(
            right: LfDimens.pagePadding,
            bottom: RecordFab.bottomOffset + safeBottom,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_expanded) ...[
                    LfFloatingActions(actions: actions),
                    const SizedBox(height: TrainingFloatingActions._gap),
                  ],
                  _ToggleFab(
                    expanded: _expanded,
                    onTap: () {
                      setState(() => _expanded = !_expanded);
                    },
                  ),
                  const SizedBox(height: TrainingFloatingActions._gap),
                  // 【2026-11-03 用户：饮食和训练的加号位置有一点偏移】
                  // 旧稿这里有一层 `Transform.translate(Offset(1, 0))`，把训练
                  // 页的加号整体右移了 1dp；删掉后两页的 RecordFab 都落在
                  // `right: pagePadding`，圆面右缘完全同一条线。
                  RecordFab(
                    buttonKey: const Key('cta-new-plan'),
                    tooltip: '新建计划',
                    onPressed: () => _activate(widget.onNewPlan),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「上拉三角」触发器：与加号同一枚 48dp 深绿实心圆，展开后箭头朝下。
///
/// 【2026-11-03 用户】三角圆的大小、水平位置都要和加号一致，且整簇按钮
/// 统一用加号的深绿底（旧稿是 44dp mint-100 浅底）。外层右内衬 1dp 是为了
/// 抵消 `RecordFab` 的 1dp 阴影内衬——两者圆面右缘才会落在同一条线。
class _ToggleFab extends StatelessWidget {
  const _ToggleFab({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final label = expanded ? '收起训练操作' : '更多训练操作';
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(right: 1),
          child: Material(
            key: const Key('training-actions-toggle'),
            color: LfColors.brandStrong(brightness),
            shape: const CircleBorder(),
            elevation: 0,
            child: InkWell(
              key: const Key('training-actions-toggle-ink'),
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: TrainingFloatingActions._toggleSize,
                height: TrainingFloatingActions._toggleSize,
                child: Icon(
                  expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  size: 22,
                  color: LfColors.onBrandStrong(brightness),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
