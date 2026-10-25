import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';

/// 菜单页搜索的**状态机**（docs/43 A1）：防抖、语义名次、结果。
///
/// 从 [MenuDishList] 抽出来有两个理由：页面只留「输入框 + 状态」两行接线，
/// 且防抖/竞态（慢的语义名次回来时已有更新的查询）可以单独测。
///
/// 纪律：
/// * 语义不可用（未接线/模型失败/索引为空）⇒ 名次为 null，结果照常出
///   （关键词 + 标签），**不弹错**（docs/41 §10 降级矩阵）；
/// * 清空 ⇒ 立刻回到推荐区，不保留搜索结果（docs/43 A1）。
final class MenuSearchController extends ChangeNotifier {
  MenuSearchController({
    required this.searchService,
    required this.semantic,
    this.debounce = const Duration(milliseconds: 200),
  });

  final DishSearchService searchService;
  final SemanticRuntime? semantic;
  final Duration debounce;

  Timer? _timer;
  int _seq = 0;

  String _query = '';
  RetrievalResult? _result;

  /// 本轮查询是否请求了语义路却拿不到名次（RV-P1-09）。
  ///
  /// 只记「语义不可用」这一个事实；文案由页面从降级矩阵取，**页面不另写一份**。
  bool semanticUnavailable = false;

  /// 语义引擎可用、但候选都不过阈值（与「引擎不可用」分开标注）。
  bool semanticBelowThreshold = false;

  /// 已生效的查询（防抖之后）；空 = 显示推荐区。
  String get query => _query;

  /// 当前查询的结果；null = 还没跑（或已清空）。
  RetrievalResult? get result => _result;

  bool get isSearching => _query.isNotEmpty && _result != null;

  /// 输入回调（200ms 防抖）。[dishes] 由页面在数据流更新时传入。
  void onQueryChanged(String value, List<DishRecord> dishes) {
    final query = value.trim();
    _timer?.cancel();
    if (query.isEmpty) {
      _seq++;
      _query = '';
      _result = null;
      semanticUnavailable = false;
      semanticBelowThreshold = false;
      notifyListeners();
      return;
    }
    _timer = Timer(debounce, () => unawaited(run(query, dishes)));
  }

  /// 立即跑一次（测试/「重试」用）。
  Future<void> run(String query, List<DishRecord> dishes) async {
    final seq = ++_seq;
    final runtime = semantic;
    final ranking = await runtime?.rankDishes(query, dishes);
    if (seq != _seq) return;
    // 请求了语义却拿到 null ⇒ 如实标注（docs/41 §10）。
    semanticUnavailable = runtime != null && ranking == null;
    semanticBelowThreshold =
        semanticUnavailable &&
        (runtime?.lastRankError ?? '').startsWith('没有足够相关');
    _query = query;
    _result = searchService.search(
      query: query,
      dishes: dishes,
      semanticRanking: ranking,
    );
    notifyListeners();
  }

  /// 菜品数据变了（流更新）：保持当前查询，重跑结果。
  void refresh(List<DishRecord> dishes) {
    if (_query.isEmpty) return;
    unawaited(run(_query, dishes));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 段头下方的搜索框（Key `nutrition-menu-search`）。
class MenuSearchField extends StatelessWidget {
  const MenuSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.hasText = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('nutrition-menu-search'),
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: '搜菜名、口味、窗口…',
        isDense: true,
        // 清空用共享圆钮（裸 IconButton 在「裸按钮只减不增」审计里是预算 0）。
        suffixIcon: !hasText
            ? null
            : Padding(
                padding: const EdgeInsets.all(6),
                child: LfIconButton(
                  key: const Key('nutrition-menu-search-clear'),
                  icon: Icons.clear,
                  semanticLabel: '清空',
                  onPressed: onClear,
                ),
              ),
      ),
      onChanged: onChanged,
    );
  }
}

/// 搜索框的 sliver 包装（与结果区共用页边距）。
SliverPadding menuSearchFieldSliver({required Widget child}) => SliverPadding(
  padding: const EdgeInsets.fromLTRB(
    LfDimens.pagePadding,
    LfDimens.cardGap,
    LfDimens.pagePadding,
    0,
  ),
  sliver: SliverToBoxAdapter(child: child),
);
