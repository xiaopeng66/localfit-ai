import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';

/// 记录页的多选操作条（docs/21 §3）：已选计数 + 删除所选（0 项禁用）+ 取消。
///
/// 从 `record_tab.dart` 拆出（docs/07 §9.3 的 500 行预算：阶段 2B 步骤 4
/// 接入页级置信摘要后记录页 506 行，超预算）。拆出的边界是**语义完整的一块**
/// ——一条与列表多选状态解耦的操作条，只吃计数与三个回调。
class NutritionRecordSelectionBar extends StatelessWidget {
  const NutritionRecordSelectionBar({
    super.key,
    required this.count,
    required this.onDelete,
    required this.onCancel,
  });

  final int count;
  final VoidCallback? onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LfDimens.pagePadding,
          vertical: LfDimens.spaceSmall,
        ),
        color: c.card,
        child: Row(
          children: [
            Text(
              '已选 $count 项',
              style: LfText.body.copyWith(color: c.cardForeground),
            ),
            const Spacer(),
            // 固定操作条里的原地动作归 B1（h40/16 圆角），终端确认才用 B2；
            // 「取消」一律 B6（§3.8）。
            LfPrimaryButton(
              key: const Key('meals-bulk-delete'),
              label: '删除所选',
              onPressed: onDelete,
            ),
            const SizedBox(width: LfDimens.spaceSmall),
            LfTextButton(
              key: const Key('meals-selection-cancel'),
              label: '取消',
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}
