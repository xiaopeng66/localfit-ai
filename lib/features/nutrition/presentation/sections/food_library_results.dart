import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/text_fit.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_list_states.dart';
import 'package:localfit_ai/utils/number_format.dart';

/// 食物库的结果头（Round7 A `app.js:195` 的 `.section-title.with-link`）：
/// 左端真实计数、右端环的单位，两端对齐。
///
/// 措辞从「全部 N 条 / 搜到 N 条」改成 A 的一种「N 种食物」：A 页面上没有
/// 第二句，且「当前看到几种」在浏览与筛选两种情形下都成立——旧的两种措辞
/// 要求读者自己区分计数覆盖的是全库还是筛选结果，而右侧的胶囊行已经把
/// 筛选状态画在明面上。
///
/// **0 行也照画**（A 的字面：`rows.length` 为 0 时写 0）：旧实现「0 条就不画
/// 计数行」在本轮退役——筛到 0 时页面不会突然少一行，空态也不往上跳。
class FoodLibraryResultsHead extends StatelessWidget {
  const FoodLibraryResultsHead({super.key, required this.total});

  /// 当前查询 + 分类下的真实条数（`COUNT(*)`，不是已加载条数）。
  final int total;

  @override
  Widget build(BuildContext context) {
    final style = LfText.caption.copyWith(color: context.lf.mutedForeground);
    final count = Text(
      '${formatGroupedInt(total)} 种食物',
      key: const Key('food-library-count'),
      style: style,
    );
    // 右端是**单位**不是计数：环的满刻度写在列表头那句里（需求 23），
    // 这里只说这枚环按每 100g 的能量密度画。
    final unit = Text('kcal / 100g', style: style);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LfDimens.pagePadding,
        0,
        LfDimens.pagePadding,
        LfDimens.spaceXSmall,
      ),
      // 两端一行是大字号的溢出点（左端还是变长的计数）：沿用本仓 [fitsRow]
      // 口径，放不下就竖排降级——两段事实都留，不裁也不缩（round7 阶段 3
      // 的 far-jump 用 2.0× 逼出过 `overflowed by 60 pixels`）。
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!fitsRow(
            context,
            available: constraints.maxWidth,
            baseNeed: LfRowBudgets.foodResultsHeader,
          )) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                count,
                const SizedBox(height: LfDimens.spaceXSmall),
                unit,
              ],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [count, unit],
          );
        },
      ),
    );
  }
}

/// 结果为空时的两种空态（A `app.js:198` 按「库里有没有东西」分岔）：
///  **有筛选**（查询词或分类）⇒「没有找到这类食物」+「清除筛选」；
///  **真·空库**（新安装，未导入）⇒「食物库还是空的」+ 导入行动。
///
/// 空态行动一律 B6 文字按钮（docs/21 §3.8，2026-10-03 用户裁决「空态一律用
/// 文字按钮，不用实心或淡底」）——A 这两处画的是 `.btn.small` 与
/// `.btn.outline-brand`（有边框 / 有淡底），按本仓已生效的裁决落成文字钮。
///
/// 空库那枚 A 画的是「导入示例食物」（`import-examples`）：本仓**不搬**演示
/// 数据（D41：不塞演示数据、不假装真实结果），槽位留给「导入食物数据」
/// ——落点是真实的 CSV 导入通路（3-2c 接上），`app.js:198` 的那个位置因此
/// 仍然有得可点，只是点出来的东西会真的进库。
class FoodLibraryEmptyState extends StatelessWidget {
  const FoodLibraryEmptyState({
    super.key,
    required this.filtered,
    this.onClear,
    this.onImport,
  });

  /// 是否有筛选条件（查询词或分类）。false = 真空库。
  final bool filtered;

  /// 「清除筛选」；null = 不渲染该行动（依赖缺失时不给点了没反应的入口）。
  final VoidCallback? onClear;

  /// 空库时的「导入食物数据」；null = 不渲染该行动。
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    if (!filtered) {
      final import = onImport;
      return FoodEmptyHint(
        title: '食物库还是空的',
        subtitle: '新安装时为空库，可导入自己的食物数据。',
        action: import == null
            ? null
            : LfTextButton(
                key: const Key('food-empty-import'),
                label: '导入食物数据',
                onPressed: import,
              ),
      );
    }
    return FoodEmptyHint(
      title: '没有找到这类食物',
      subtitle: '试试其他名称或分类。',
      action: onClear == null
          ? null
          : LfTextButton(
              key: const Key('food-empty-clear'),
              label: '清除筛选',
              onPressed: onClear,
            ),
    );
  }
}
