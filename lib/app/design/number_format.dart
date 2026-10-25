/// 整数千分位（`8432` → `8,432`）。
///
/// 手写而不引 `intl`：全仓零 `intl` 依赖（pubspec 里没有，P9 也不新增），
/// 而这一步只需要在整数里插逗号——`NumberFormat` 的收益抵不上一个新依赖。
///
/// 2026-10-11（docs/32 T2）从 `dashboard_quick_stats_row.dart` 提为共享件：
/// 目标确认抽屉的热量区间也要千分位，两处各写一份会让格式漂移。
String withThousandsSeparator(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
