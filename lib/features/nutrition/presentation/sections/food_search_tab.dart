import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_library_header.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_list_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_list_states.dart';

/// 「食物库」tab 的仓库直连搜索（无目录 controller 时的路径）。
///
/// 2.0-6i-3b：从 `nutrition_page.dart` 拆出的 section（docs/07 §9.3）。
/// 有 5 万条目录 controller 时页面走 [FoodLibraryView]，不经过这里
/// （旧数据路径保持不变）。两条路径自 2026-10-03 起共用同一件搜索框
/// （[LfSearchField]）、同一件结果行（[FoodCard]）与同一套骨架/空态
/// （[FoodListSkeleton] / [FoodEmptyHint]），Round7 阶段 3（D36）起也共用
/// 同一层列表卡（[FoodListCard]）——「搜索框长什么样、结果怎么排」只有一份
/// 实现，用户看到的食物列表不再因数据来源而变样。
class FoodSearchTab extends StatelessWidget {
  const FoodSearchTab({
    super.key,
    required this.repository,
    required this.query,
    required this.revision,
    required this.onQueryChanged,
    this.onCreateFood,
  });

  final FoodRepository repository;
  final String query;

  /// 自建食物后递增，用来强制刷新同一条查询的 future。
  final int revision;
  final ValueChanged<String> onQueryChanged;

  /// 自建食物（docs/29 §P8a 需求 29：入口在搜索框右侧）。null = 不渲染。
  final VoidCallback? onCreateFood;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 需求 29/30：与分页浏览路径同一条页头（同一枚 Key —— 两条数据路径
        // 同一时刻只挂载一条）。
        FoodLibraryHeader(
          onQueryChanged: onQueryChanged,
          onCreateFood: onCreateFood,
        ),
        // 需求 23：环的满刻度写在明面上（与分页浏览路径同一句话，两条路径
        // 同一时刻只挂载一条）。
        const FoodLibraryScaleNoteRow(),
        Expanded(
          // 空查询不给默认列表：数千条食物按名称排序的头几条没有浏览意义。
          child: query.trim().isEmpty
              ? const FoodEmptyHint(
                  title: '输入名称搜索食物',
                  subtitle: '也可以点搜索框右边的「+」自建食物。',
                )
              : FutureBuilder<List<FoodRecord>>(
                  key: ValueKey('$query-$revision'),
                  future: repository.search(query),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(child: AppErrorText('食物加载失败，请重试。'));
                    }
                    if (!snapshot.hasData) {
                      return const FoodListSkeleton();
                    }
                    final foods = snapshot.data!;
                    if (foods.isEmpty) {
                      return const FoodEmptyHint(
                        title: '没有找到食物',
                        subtitle: '换个词再试，或点搜索框右边的「+」自建食物。',
                      );
                    }
                    // Round7 阶段 3（D36）：两条数据路径同一套**单卡列表**
                    // （A `app.js:195` 的 `.card.food-list`）——卡面、行的左右
                    // 12 内衬与 1px 分隔线都在 `FoodListCard`/`FoodListRow` 里，
                    // 与分页浏览那条路径逐项同形。
                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          // `RV4-P2-10`：页尾条退役后底栏预留搬到这里
                          // （与分页路径 `FoodLibraryView` 同一口径）。
                          padding: EdgeInsets.fromLTRB(
                            LfDimens.pagePadding,
                            0,
                            LfDimens.pagePadding,
                            LfInsets.navReserve(context) + LfDimens.spaceSmall,
                          ),
                          sliver: FoodListCard(
                            // 行高已知（同分页路径）：搜索结果也走原型量高的
                            // 列表，两种列表的几何只有一份口径。
                            sliver: SliverPrototypeExtentList.builder(
                              prototypeItem: const FoodListRow(
                                child: _FoodRowPrototype(),
                              ),
                              itemCount: foods.length,
                              itemBuilder: (context, index) => FoodListRow(
                                dividerKey: index == foods.length - 1
                                    ? null
                                    : Key(
                                        'food-library-row-divider-'
                                        '${foods[index].id}',
                                      ),
                                child: _card(foods[index]),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// 一行（搜索结果）。搜索结果不套 EntranceItem：查询每敲一键就整体重建
  /// （ValueKey 换代），入场动画会逐键重播成闪烁；即时呈现更符合搜索直觉。
  Widget _card(FoodRecord food) => FoodCard(
    key: Key('food-library-item-${food.id}'),
    id: food.id,
    // 名称清洗在行内做（`splitFoodName`）：传原始 name。
    name: food.name,
    category: FoodCategory.classify(name: food.name),
    isUserCreated: food.isUserCreated,
    brand: food.brand,
    kcalPer100g: food.kcalPer100g,
    proteinPer100g: food.proteinPer100g,
    carbsPer100g: food.carbsPer100g,
    fatPer100g: food.fatPer100g,
  );
}

/// 行高原型（只被量一次，不上屏）。
///
/// 与分页路径同一个理由：搜索结果同样按整行高的列表铺，两种列表的几何（行高
/// 56、行距、行内三件的位置）只有一份口径。
///
/// 它是**一整件真行**（包含分类图标那枚 SVG）：原型只被量高低、从不上屏
/// （`SliverPrototypeExtentList` 的语义，框架原话「essentially [Offstage]：
/// it is not painted」），所以它加载图标没有渲染代价，只保证量出来的高度与
/// 真行逐项一致。渲染树里能看到它 —— 走查/判据要按「不上屏的不是内容」跳过
/// （见 `nutrition_subtab_occlusion_test.dart` 的 `walk`）。
class _FoodRowPrototype extends StatelessWidget {
  const _FoodRowPrototype();

  @override
  Widget build(BuildContext context) => const FoodCard(
    id: 'food-search-row-prototype',
    name: '原型食物名称（只用于量行高）',
    category: FoodCategory.other,
    kcalPer100g: 900,
    canJoinPlan: false,
    onTap: null,
  );
}
