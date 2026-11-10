import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';

/// 趋势卡首次加载的骨架（与真实卡同构，避免加载完跳一下）。
///
/// 从 record_tab.dart 搬出（docs/07 §9.3 的 500 行预算：多选回调与返回
/// 拦截接入后记录页 510 行）。
class RecordTrendCardSkeleton extends StatelessWidget {
  const RecordTrendCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const DesignCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(height: 18, width: 120),
        SizedBox(height: LfDimens.spaceMedium),
        SkeletonBox(height: 120),
      ],
    ),
  );
}
