import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/lf_empty_state.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_list_card.dart';

/// 食物结果列表的加载/空态件：食物库（[FoodLibraryView]）与仓库直连搜索
/// （[FoodSearchTab]）共用，避免两条路径各画一套骨架与空态。
///
/// 两者共用同一件 [FoodCard]（Round7 阶段 3 起是**行**）与同一层列表卡
/// （[FoodListCard]），骨架也必须与真行同构——否则加载完成时列表会整体跳一下。

/// 行式骨架（与 [FoodCard] 同构：图标 + 名称 + 右端能量环）。
///
/// 2026-10-08（docs/30 §2 D1）：卡由五段压成**单行三件**，骨架同步压成一行
/// ——**行数/顺序/间距必须与真行逐项对应**，否则「加载完成时列表跳一下」的
/// 老毛病会原路回来（2026-10-04 就是因为骨架与真卡差几十像素才改成同构）。
///
/// 2026-10-14（Round7 阶段 3 · D36）：真行搬进单卡列表（A `.food-row`），骨架
/// 同步去掉每行自己的卡面与左右内衬（左右 12 由列表卡给），段距改 A 的
/// 10 / 14。内边距与真行同为「上下 8、左右 0」，行高同样 56。
class FoodCardSkeleton extends StatelessWidget {
  const FoodCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: LfDimens.spaceSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SkeletonBox(
            width: LfDimens.foodCardIconSize,
            height: LfDimens.foodCardIconSize,
            borderRadius: BorderRadius.all(Radius.circular(LfDimens.radiusMd)),
          ),
          SizedBox(width: LfDimens.spaceSmallPlus),
          Expanded(child: SkeletonBox(height: 16, width: 160)),
          // 环用**小档** 36dp（真行同）：写成 44 会让骨架比真行高 8dp。
          // 环前的段距也与真行同（10 + `.food-density{margin-left:4px}` = 14）。
          SizedBox(width: LfDimens.spaceSmallPlus + LfDimens.spaceXSmall),
          SkeletonBox(
            width: LfDimens.foodKcalRingSmallSize,
            height: LfDimens.foodKcalRingSmallSize,
            borderRadius: BorderRadius.all(
              Radius.circular(LfDimens.radiusFull),
            ),
          ),
        ],
      ),
    );
  }
}

/// 列表首次加载的骨架（[count] 行 [FoodCardSkeleton]），形态与真列表逐项同构：
/// 同一层列表卡（[FoodListCard]）、同样的行内衬与分隔线（末行没有）。
///
/// 行高与真列表一样**已知**（`SliverPrototypeExtentList` + 真骨架当原型）：
/// 骨架阶段拖动滑条也不会触发「逐行实体化」的卡死路径（那一课见
/// `food_library_far_jump_test.dart`）。
class FoodListSkeleton extends StatelessWidget {
  const FoodListSkeleton({this.count = 6, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          // 底栏预留由页尾条承担（Round7 阶段 3 · 3-2c 的 D44）：骨架与真列表
          // 同尾距，加载完成时不跳。
          padding: const EdgeInsets.fromLTRB(
            LfDimens.pagePadding,
            0,
            LfDimens.pagePadding,
            LfDimens.spaceSmall,
          ),
          sliver: FoodListCard(
            sliver: SliverPrototypeExtentList.builder(
              prototypeItem: const FoodListRow(child: FoodCardSkeleton()),
              itemCount: count,
              itemBuilder: (context, index) => FoodListRow(
                dividerKey: index == count - 1
                    ? null
                    : Key('food-library-row-divider-skeleton-$index'),
                child: const FoodCardSkeleton(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 食物列表的空态：食物库与仓库直搜两条路径共用。
///
/// Round7 阶段 3（D41）起**退成 [`LfEmptyState`] 的薄壳**——形态全部来自
/// 共享件（A `.empty-state`：52 R18 brand-soft 图标块 + 14 w600 标题 +
/// 12/1.8 说明）。旧形态是「`search_off` 大图标 + 标题 + 说明」的居中列，
/// 与 A 的图标块不是一套语言，而且是同一条列表的第三套空态样式。
///
/// 本壳只剩三件本域的事：默认图标（A 食物列表空态用的是 `search`）、
/// 「标题/说明」这组语义命名（调用点已有 3 处，改名只会增加 diff 噪声），
/// 以及**可滚宿主**（3-2c 的实测缺陷，见下）。
///
/// 【可滚宿主（Round7 阶段 3 · 3-2c 缺陷 ⑬）】空态是**降级布局**，必须比它所
/// 替代的列表更能屈能伸：320dp 宽 + 2.0× 系统字号时（`large_font_layout_audit`
/// 的视口）页尾条要占 8 + 122.4 + 85.5 ≈ 216dp，留给本件的只剩 ≈ 142dp，而
/// 「图标块 + 标题 + 两行说明 + 行动钮」实测 200.5dp ⇒ 溢出 **58px**（真凭实据：
/// `test/app/large_font_layout_audit_test.dart` 与 `test/app/stress_ui_test.dart`
/// 同一条「饮食·食物库」报 `RenderFlex overflowed by 58 pixels on the bottom`，
/// 错误点直指 `lf_empty_state.dart` 的 `Column`）。修法沿用本仓既有裁决
/// （`AppEmptyState` 为横屏矮视口做的同一件事）：`Center + SingleChildScrollView`
/// ——放得下时收缩到内容高度、由 Center 居中（与原来逐像素一致），放不下时取满
/// 可用高度并可滚（行动钮滚得到，不裁字、不缩小字号）。
class FoodEmptyHint extends StatelessWidget {
  const FoodEmptyHint({
    required this.title,
    required this.subtitle,
    this.action,
    super.key,
  });

  final String title;
  final String subtitle;

  /// 空态行动（A 的空态行动按本仓裁决一律 B6 文字按钮，docs/21 §3.8）。
  final Widget? action;

  /// 空态可滚宿主的 Key（矮视口下的回归判据按它定位这条滚动体）。
  static const Key scrollKey = Key('food-empty-scroll');

  @override
  Widget build(BuildContext context) {
    // 空态是**降级布局**，必须比它所替代的列表更能屈能伸：320dp 宽 + 2.0×
    // 系统字号时（`large_font_layout_audit` 的视口）页尾条要占
    // 8 + 122.4 + 85.5 ≈ 216dp，留给本件的只剩 ≈ 142dp，而「图标块 + 标题 +
    // 两行说明 + 行动钮」实测 200.5dp —— 溢出 58px（真凭实据见类文档）。
    // 修法沿用本仓既有裁决（`AppEmptyState` 为横屏矮视口做的同一件事）：
    // 放得下时滚动视图收缩到内容高度、由 Center 居中（与原来逐像素一致），
    // 放不下时取满可用高度并可滚（行动钮滚得到，不裁字、不缩小字号）。
    return Center(
      child: SingleChildScrollView(
        key: scrollKey,
        child: LfEmptyState(
          icon: Icons.search,
          title: title,
          message: subtitle,
          action: action,
        ),
      ),
    );
  }
}
