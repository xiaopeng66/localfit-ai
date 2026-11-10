import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';

/// 菜品动作弹层（docs/21 §3.6 弹层）：AI 分析 · 改名/改价 · 手动填营养 · 删除。
///
/// 从 `menu_tab_view.dart` 拆出来的一件纯表现件——动作项与 key 是它的全部
/// 内容，编排（拿到结果后调哪个仓库）仍在页面里。
///
/// 【2026-10-29（R-11，用户：四个按钮很丑、四排文字）】重排为**主次分明**：
/// * 主行动 = 「AI 分析这道菜」实心 B2（这是这枚弹层的存在理由——食堂菜
///   价值最高的一步），通宽；未接线（`showAnalyze == false`）时退化为
///   「手动填写营养」居主，弹层永远有一个显眼的主行动；
/// * 次行动 = 「改名/改价」「手动填写营养」两枚**并排软底**（B3 胶囊）；
/// * 破坏性 = 「删除」独立在底部（B6 字型 error 口径），不与常规动作同排。
/// Key 一字不动（`canteen-dish-*` 契约 + `key_contract_test`）。
///
/// 关闭用自身 `context`：本件渲染在 `AppSheet` 的子树里（弹层挂在根导航器
/// 上），因此直接 `Navigator.of(context).pop` 弹的就是这个弹层。
class CanteenDishActionsSheet extends StatelessWidget {
  const CanteenDishActionsSheet({required this.showAnalyze, super.key});

  /// 未分析营养且接线方提供了 AI 回调时才给「AI 分析这道菜」。
  final bool showAnalyze;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 主行动：实心通宽（没有 AI 入口时主行动让位给「手动填写营养」）。
        if (showAnalyze)
          LfConfirmButton(
            key: const Key('canteen-dish-analyze'),
            label: 'AI 分析这道菜',
            expand: true,
            icon: Icons.auto_awesome,
            onPressed: () => Navigator.of(context).pop('analyze'),
          )
        else
          LfConfirmButton(
            key: const Key('canteen-dish-manual-nutrition'),
            label: '手动填写营养（每 100g）',
            expand: true,
            icon: Icons.edit_note,
            onPressed: () => Navigator.of(context).pop('manual'),
          ),
        if (showAnalyze) ...[
          const SizedBox(height: LfDimens.spaceSmall),
          Row(
            children: [
              Expanded(
                child: LfSoftButton(
                  key: const Key('canteen-dish-edit'),
                  label: '改名 / 改价',
                  icon: Icons.edit_outlined,
                  onPressed: () => Navigator.of(context).pop('edit'),
                ),
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              Expanded(
                child: LfSoftButton(
                  key: const Key('canteen-dish-manual-nutrition'),
                  label: '手动填营养',
                  icon: Icons.edit_note_outlined,
                  onPressed: () => Navigator.of(context).pop('manual'),
                ),
              ),
            ],
          ),
        ] else ...[
          const SizedBox(height: LfDimens.spaceSmall),
          // 没有分析入口时「改名/改价」单独一行（软底），保持触达 44。
          LfSoftButton(
            key: const Key('canteen-dish-edit'),
            label: '改名 / 改价',
            icon: Icons.edit_outlined,
            onPressed: () => Navigator.of(context).pop('edit'),
          ),
        ],
        const SizedBox(height: LfDimens.spaceLarge),
        // 破坏性动作独立在底部（§3.8 B7 字型 error；确认由下游确认弹层承担，
        // 这里只导航）。用共享件而不是手写 TextButton——按钮审计只减不增。
        Center(
          child: LfDangerButton(
            key: const Key('canteen-dish-delete'),
            label: '删除这道菜',
            icon: Icons.delete_outline,
            onPressed: () => Navigator.of(context).pop('delete'),
          ),
        ),
      ],
    );
  }
}
