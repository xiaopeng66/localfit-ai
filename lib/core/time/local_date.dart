/// ISO「本地日」（`yyyy-MM-dd`）校验的唯一事实源。
///
/// 读取侧（训练统计、周报、恢复导入）会严格解析这个格式的文本列；
/// 任何「未加约束的 TextColumn」在读取前都必须先过这里的校验——
/// 脏值在读取侧 build 里炸整页红屏的那类缺陷（docs/11 BUG-15 / §3-F）
/// 统一靠这个入口挡住，不要各处自抄正则。
library;

final RegExp _isoLocalDatePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// `value` 是否是真实存在的日历日期（`2026-02-31` 这类被 DateTime
/// 悄悄滚进 3 月的假日期不算）。
bool isValidIsoLocalDate(String? value) {
  if (value == null) return false;
  final match = _isoLocalDatePattern.firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}
