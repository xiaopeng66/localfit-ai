import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';

/// 饮食页 sub-tab 的**单一事实源**（文案 + 稳定 Key + 菜单下标）。
///
/// 定义在这里而不是页面里：胶囊行的文案 / Key 被页面、动作层与跨页意图
/// （「查看菜单」）共用，散在页面里迟早出现「某处漏改一个 Key」。
///
/// 2026-10-04（docs/28 §6.1）：原五项（记录 / 计划 / 菜单 / 食谱 / 食物库）
/// 收敛为**三项**（记录 / 菜单 / 食物库）——计划与食谱两个 tab 随
/// 「食谱 / 计划」整族下线，对应的 `planIndex` / `recipeIndex` 一并删除。
/// **下标是单一事实源**：菜单从 2 变成 1，页面 switch 与跨页意图都读这里。
abstract final class NutritionTabs {
  static const labels = ['记录', '菜单', '食物库'];

  /// 每个 tab 的稳定 Key（docs/21 §5：`tab-*` → `nutrition-tab-*`）。
  /// Key 不跟着文案走，改文案不会换锚点。
  static const keys = [
    'nutrition-tab-record',
    'nutrition-tab-menu',
    'nutrition-tab-foodlib',
  ];

  static const recordIndex = 0;
  static const menuIndex = 1;
  static const foodLibraryIndex = 2;

  /// 食物库 tab 页头的 Key：**搜索行**（需求 29/30 把顶栏撤掉之后，紧接胶囊
  /// 行下缘的第一个元素就是它）。跨页位置契约
  /// （`nutrition_subtab_position_test`）按它量「页头紧接胶囊行」。
  ///
  /// 两个子视图（分页浏览 / 仓库直搜）各自渲染自己的搜索行，但同一时刻只会
  /// 挂载一个，所以这个 Key 在页面上恒为唯一。
  static const Key foodLibraryHeaderKey = Key('nutrition-foodlib-search-row');
}

/// 设计稿未画的那枚 tab（食物库）的外壳：细顶栏 + 内容。
///
/// 胶囊行**不在这里**：它是页级唯一实例（`NutritionPage` 画在本外壳之上，
/// 用户 2026-10-03 要求各界面位置一致），所以本外壳从顶栏开始。
///
/// 从 `nutrition_page.dart` 拆出（docs/07 §9.3 的行数预算）。
///
/// 2026-10-05（docs/29 §P8a 需求 29/30）：食物库这一枚的顶栏整条撤掉——
/// 自建食物入口搬到搜索框右侧（需求 29），标题与返回键都删（需求 30）。
/// `LfTopBar` 是**共享件**（拍照识餐 / 食堂目录 / 下一餐推荐 / 动作库 /
/// AI 对话五处二级页都要返回键），所以撤的是**本外壳**的渲染，不是组件本身：
/// `LfTopBar` 照旧支持标题与返回键的开关（默认保持现状），这里只是不再需要
/// 一条什么都画不出来的 60dp 空白带（还带一条下边框）。
class NutritionLegacyTabShell extends StatelessWidget {
  const NutritionLegacyTabShell({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.showBack = true,
    this.showTitle = true,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  /// 见 [LfTopBar.showBack]。默认 `true` = 现状不变。
  final bool showBack;

  /// 见 [LfTopBar.showTitle]。默认 `true` = 现状不变。
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    // 标题与返回都关掉、又没有动作 ⇒ 这条栏没有任何可渲染的东西。
    final hasTopBar = showBack || showTitle || actions.isNotEmpty;
    return Column(
      children: [
        if (hasTopBar)
          // 顶部叠层已由页级胶囊行消费，这里不能再吃一次（docs/21 §5.8.5），
          // 否则标题与返回键会被推到两倍状态栏高度之下。
          LfTopBar(
            key: Key('nutrition-legacy-bar-$title'),
            title: title,
            actions: actions,
            showBack: showBack,
            showTitle: showTitle,
            respectTopInset: false,
          ),
        Expanded(child: child),
      ],
    );
  }
}
