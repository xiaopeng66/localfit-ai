/// 菜单服务营业窗口的时间换算（`HH:mm` → 当天分钟数）。
///
/// 「这个窗口现在开着吗」在推荐与匹配两处都要算，必须用同一套解析，
/// 否则会出现「显示开着、算成关着」。
///
/// 2026-11-09 全量审查：删掉了同文件的 `MenuServiceWindow` extension
/// （`openTimeAtMinute` / `closeTimeAtMinute` / `windowLabel` 三个成员零调用；
/// 窗口文案在 `CanteenWindow.windowLabel` 另有一份实现）与文件尾那行指向
/// 已删函数的悬空注释。
library;

/// 解析 `HH:mm`；无法解析时按 0 点处理（不猜测）。
int parseHhmmToMinute(String hhmm) {
  final parts = hhmm.split(':');
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return hour * 60 + minute;
}
