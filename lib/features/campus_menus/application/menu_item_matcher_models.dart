/// 菜单项 ↔ 本地 food 匹配候选（2.0-3d）。
///
/// 纯数据视图：不绑定数据库行，suggestion 打分只在本机计算。
class MenuItemMatchSuggestion {
  const MenuItemMatchSuggestion({
    required this.foodId,
    required this.foodName,
    required this.state,
    required this.confidence,
  });

  final String foodId;
  final String foodName;

  /// foods.state：verified | estimated | user_created（incomplete/stale
  /// 在建议阶段被过滤，不会出现在此列表）。
  final String state;

  /// 本地确定性打分：0.95 精确名/别名、0.8 包含、分片 FTS 按序衰减
  /// （0.9 起、每名次 -0.05、下限 0.3）。
  final double confidence;
}
