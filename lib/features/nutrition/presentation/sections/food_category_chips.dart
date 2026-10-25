import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/lf_filter_chips.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';

/// 食物库的分类胶囊行（Round7 A `.food-category-row`，`app.js:201`：紧跟在
/// 搜索行之后、结果头之前）。
///
/// **标签集合用本仓真实分类域**（全部 + `FoodCategory.values` 十档）：A 的
/// 8 枚演示标签（肉类/蛋类/…）既不覆盖本仓十档、内部还互相重叠（肉类与蛋类
/// 在 A 的演示数据里都落到同一格），照抄会造出一个和数据库对不上的筛选器。
///
/// **筛选判据是落库的枚举 id**（控制器 `_applyCategory` 用
/// `FoodCategory.tryFromId`），不是关键词猜分类——CSV 导入（ADR-036 官方 9 列）的
/// 每一行都带合法 id（无法映射的行整行拒收，docs/31 §S5），落库分类是事实；id 不认识
/// 的行（旧目录分片原串、AI 建的行）不进任何分类，只留在「全部」里。
class FoodCategoryChipRow extends StatelessWidget {
  const FoodCategoryChipRow({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// 当前选中的分类；null = 「全部」（不过滤）。
  final FoodCategory? selected;

  /// 选中回调：null 表示「全部」。
  final ValueChanged<FoodCategory?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LfDimens.pagePadding),
      child: LfFilterChipRow(
        key: const Key('food-library-category-row'),
        chips: [
          LfFilterChip(
            key: const Key('food-category-chip-all'),
            label: '全部',
            selected: selected == null,
            onPressed: () => onChanged(null),
          ),
          for (final category in FoodCategory.values)
            LfFilterChip(
              key: Key('food-category-chip-${category.id}'),
              label: category.label,
              selected: selected == category,
              onPressed: () => onChanged(category),
            ),
        ],
      ),
    );
  }
}
