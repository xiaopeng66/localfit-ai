// 餐食卡骨架（记录页加载态）。
//
// **2026-10-15 死代码清理**：本文件原有一枚完整的 `MealCard`（ slot emoji
// 渐变顶 + 三宏量圆点），记录页 2B 重写后已无任何调用点（Round7 逐页对账
// 批次 6 清理时经全仓词边界扫描确认零引用）⇒ 整类删除；只留下记录页
// 仍在用的骨架。骨架与真卡的"同构"契约由 2B 步骤 5 的帧对账承担。
import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';

/// 餐食卡骨架（记录页加载态）：与真记录卡同构（2B 步骤 5 帧对账的契约）。
class MealCardSkeleton extends StatelessWidget {
  const MealCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => DesignCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SkeletonBox(
              width: 44,
              height: 44,
              borderRadius: BorderRadius.all(Radius.circular(22)),
            ),
            const SizedBox(width: LfDimens.spaceMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(height: 18, width: 96),
                  SizedBox(height: 6),
                  SkeletonBox(height: 14),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SkeletonBox(height: 22, width: 64),
          ],
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        const SkeletonBox(height: 6),
      ],
    ),
  );
}
