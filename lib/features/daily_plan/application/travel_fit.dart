// 2026-10-24：`DailyPlanEngine` 随「下一餐」整族退役；本文件保留（`travel_fit_test`
// 仍覆盖算法，且它是纯函数、无 UI 依赖）。
/// solver 的 `travelFit`（docs/07 §7.4 的 `distanceOrTravelFit` 权重）。
///
/// 该权重的输入源（用户手动分钟数 + 单次路线查询）已在 Round 5 T8 随整条
/// 纵切下线（docs/32 §3 D10）。**参数保留、取值恒为 [neutral]**：solver 的
/// 契约与权重表不动，也不对任何候选做时间维度的加减分——下线前「输入未知」
/// 档就是 0.5，因此行为与历史的中性档完全一致。
abstract final class TravelFit {
  /// 恒定中性值（与下线前的「未知」档一致）。
  static const double neutral = 0.5;
}
