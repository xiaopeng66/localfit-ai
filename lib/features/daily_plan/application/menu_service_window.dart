import 'package:localfit_ai/data/database/app_database.dart';

/// 菜单服务营业窗口的时间换算（`HH:mm` ↔ 当天分钟数）。
///
/// solver 与决策卡共用：卡片显示窗口文案，solver 用它判定窗口是否可用，
/// 两者必须用同一套解析，否则会出现「显示开着、算成关着」。
extension MenuServiceWindow on MenuService {
  int get openTimeAtMinute => parseHhmmToMinute(openTime);
  int get closeTimeAtMinute => parseHhmmToMinute(closeTime);
  String get windowLabel => '$openTime–$closeTime';
}

/// 解析 `HH:mm`；无法解析时按 0 点处理（不猜测）。
int parseHhmmToMinute(String hhmm) {
  final parts = hhmm.split(':');
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return hour * 60 + minute;
}

/// 分钟数 → `HH:mm`（用于「调整到达时间」的回显）。
String formatMinuteAsHhmm(int minute) {
  final normalized = ((minute % 1440) + 1440) % 1440;
  final hour = (normalized ~/ 60).toString().padLeft(2, '0');
  final rest = (normalized % 60).toString().padLeft(2, '0');
  return '$hour:$rest';
}
