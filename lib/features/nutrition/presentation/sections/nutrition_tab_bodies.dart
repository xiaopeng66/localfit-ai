import 'package:flutter/material.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_library_view.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_search_tab.dart';

// 设计稿未画的那枚 tab（食物库）的**内容**，从 `nutrition_page.dart` 拆出
// （docs/07 §9.3 行数预算）。
//
// 页面负责持有状态（搜索词、revision）与动作层；这里只做布局。
//
// 2026-10-04 W4：计划 / 食谱两枚 tab 随功能一起删除（docs/28 §6），
// 本文件只剩食物库一块。

/// 食物库 tab：有目录 controller 时走主库 + 分片合并分页，否则保持
/// 既有 repository-only 搜索（旧数据路径不破坏，2.0-6f）。
///
/// 页尾（A `app.js:201` 的 `.library-footer`）挂在**这一层**：它是页尾而不是
/// 列表的一部分（加载态、空库态、错误态都要在），而两条数据路径共用同一枚
/// （2026-10-04 W5 的教训：只接一条路径的入口会半边失效）。
class NutritionFoodLibraryTabBody extends StatelessWidget {
  const NutritionFoodLibraryTabBody({
    super.key,
    required this.repository,
    required this.query,
    required this.revision,
    required this.onQueryChanged,
    this.controller,
    this.onCreateFood,
    this.onImportFoods,
  });

  final FoodRepository repository;
  final FoodLibraryController? controller;
  final String query;
  final int revision;
  final ValueChanged<String> onQueryChanged;

  /// 自建食物（docs/29 §P8a 需求 29）。两条数据路径都收：入口挂在搜索框右侧，
  /// 与走哪条路径无关（2026-10-04 W5 的教训：只接一条路径的入口会半边失效）。
  final VoidCallback? onCreateFood;

  /// 「导入食物数据」（**只在真空库空态里**，`docs/56` R9 第 4 条）：
  /// 空库时它是唯一自助路径，所以留着；页尾那条常驻链已随 R9 退役
  /// （与设置页「添加食物数据」重复）。null = 不渲染该钮。
  final VoidCallback? onImportFoods;

  @override
  Widget build(BuildContext context) {
    final libraryController = controller;
    // 「自建食物」入口在两条路径各自的搜索行右侧（`FoodLibraryView` /
    // `FoodSearchTab` 的 `onCreateFood`）。
    // 两条路径都要收 `revision`：它是「自建食物落库了」的唯一信号
    // （2026-10-04 W5 设备走查抓到的缺口——只传给旧搜索路径时，
    // 分页视图的计数行与已缓存的第一页在自建后一直是旧数据）。
    final body = libraryController != null
        ? FoodLibraryView(
            controller: libraryController,
            revision: revision,
            onCreateFood: onCreateFood,
            onImportFoods: onImportFoods,
          )
        : FoodSearchTab(
            repository: repository,
            query: query,
            revision: revision,
            onQueryChanged: onQueryChanged,
            onCreateFood: onCreateFood,
          );
    // `RV4-P2-10`：页尾条退役（`docs/56` R9）。它原来还承担**底栏预留**，
    // 这份预留已搬进两条列表路径各自的末尾 `SliverPadding(bottom: navReserve)`
    // （见 `FoodLibraryView._body` 与 `FoodSearchTab`）。
    return body;
  }
}
