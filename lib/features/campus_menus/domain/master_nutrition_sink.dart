/// 食堂域 → 统一主库的**端口**（docs/67 §3.2、§6.2）。
///
/// 食堂目录里"批准一份每 100g 分析"这件事，最终必须落到**主食物的生效修订**
/// 上——否则食堂证据编辑器和主库编辑器就在各自维护一组当前值，正是本方案
/// 要消灭的那种双事实。
///
/// 端口定义在食堂域、实现在营养域（`FoodCatalogService`）：依赖方向仍然是
/// campus_menus → 自己的 domain，不认识 nutrition 的仓储。
library;

/// 一份已批准的每 100g 营养事实。
final class ApprovedPer100g {
  const ApprovedPer100g({
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
  });

  final double kcalPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
}

abstract interface class MasterNutritionSink {
  /// 把批准的营养写成该主食物的**新修订**并切换生效指针。
  ///
  /// 由调用方（食堂仓储）放在同一个事务里：证据行、供应状态与主修订要么
  /// 一起成立，要么一起回滚。
  Future<void> applyApprovedNutrition({
    required String foodId,
    required ApprovedPer100g values,
    required String origin,
    required bool isEstimated,
    String? rawValuesJson,
  });

  /// 还没有主食物的供应被批准分析时，**建一条主食物**并返回 id。
  ///
  /// 为什么必须建：否则食堂目录按证据显示「已分析」，而记餐搜索/推荐/快照
  /// 按主库判定「待分析，不能直接记餐」——同一条供应两处读数打架
  /// （docs/67 §6.2「批准后调用主营养修订服务」）。
  ///
  /// 返回 null = 未接线（只写证据，不做链接）。
  Future<String?> createMasterFromAnalysis({
    required String displayName,
    required ApprovedPer100g values,
    required String origin,
    required bool isEstimated,
    String? rawValuesJson,
  });
}
