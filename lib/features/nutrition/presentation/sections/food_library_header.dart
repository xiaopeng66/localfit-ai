import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/lf_food_kcal_ring.dart';
import 'package:localfit_ai/app/design/widgets/lf_search_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_legacy_tab_shell.dart';

/// 食物库 tab 的**页头**（搜索字段 + 自建食物入口），两条数据路径共用。
///
/// 需求 29/30（docs/29 §P8a）：这一行取代了原先 60dp 的细顶栏——「食物库」
/// 标题与返回键整条撤掉，添加按钮从顶栏右上角搬到搜索框右侧（它服务的对象
/// 就在旁边）。撤的是**食物库那一条的渲染**（`NutritionLegacyTabShell` 的
/// `showBack/showTitle`），共享件 `LfTopBar` 本身不动。
///
/// 为什么独立成件：分页浏览（`FoodLibraryView`）与仓库直搜（`FoodSearchTab`）
/// 各挂一份，两条路径同一时刻只挂载一条（所以 [NutritionTabs.foodLibraryHeaderKey]
/// 在页面上恒为唯一）。此前两处各写一遍，改一处漏一处的风险由这一件兜住。
class FoodLibraryHeader extends StatelessWidget {
  const FoodLibraryHeader({
    super.key,
    required this.onQueryChanged,
    this.hintText = '搜索本地食物',
    this.onCreateFood,
    this.searchController,
  });

  final ValueChanged<String> onQueryChanged;
  final String hintText;

  /// 输入框控制器；给得出的一方可以**程序化清空**搜索词（食物库的
  /// 「清除筛选」空态行动要连框里的字一起清，不然框里写着「米饭」、
  /// 列表却是全部）。不传则维持非受控（仓库直搜路径）。
  final TextEditingController? searchController;

  /// 自建食物；null = 不渲染入口（无宿主动作的测试台架）。
  final VoidCallback? onCreateFood;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 跨页位置契约（`nutrition_subtab_position_test`）按它量「页头紧接
      // 胶囊行下缘」——Key 挂在最外层盒子上，不许挪到 Row 里。
      key: NutritionTabs.foodLibraryHeaderKey,
      // 横向用页边距（A `.page{padding:12px 16px 28px}`）：搜索行、分类胶囊行
      // （Round7 阶段 3 新增）与下方列表的左缘必须同在 16 上，否则搜索框比
      // 列表缩进 8dp，一眼就是没对齐。纵向仍留 8（A 的 12 会把页头撑松）。
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.pagePadding,
        vertical: LfDimens.spaceSmall,
      ),
      child: Row(
        children: [
          Expanded(
            child: LfSearchField(
              fieldKey: const Key('food-library-search'),
              hintText: hintText,
              controller: searchController,
              onChanged: onQueryChanged,
            ),
          ),
          if (onCreateFood != null) ...[
            const SizedBox(width: LfDimens.spaceSmall),
            // 命中盒 44 / 视觉圆 36（docs/21 §3.8 B4）：裸 IconButton 的
            // 48 方框会把这一行撑高。
            LfCircleIconButton(
              key: const Key('cta-new-food'),
              tooltip: '自建食物',
              icon: Icons.add,
              onPressed: onCreateFood,
            ),
          ],
        ],
      ),
    );
  }
}

/// 列表头的一行说明：环的满刻度是什么（需求 23）。
///
/// 只写一次、不逐卡重复：同一常量在列表里印几十遍只是噪声，还要跟食物名
/// 抢宽度；环下那格只承担「每行都会变」的单位。
class FoodLibraryScaleNoteRow extends StatelessWidget {
  const FoodLibraryScaleNoteRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        LfDimens.pagePadding,
        0,
        LfDimens.pagePadding,
        LfDimens.spaceXSmall,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FoodDensityScaleNote(),
      ),
    );
  }
}
