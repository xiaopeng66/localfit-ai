import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

/// 体重卡的周/月视图。
enum WeightRange {
  week('周'),
  month('月');

  const WeightRange(this.label);

  final String label;
}

/// 图表中的一个日槽位。
///
/// 空槽用 [isEmpty] 表示，而不是用 0 值伪造柱。月视图的 [label] 始终保留
/// 完整日期，供语义摘要或调试使用；[axisLabel] 只控制可见横轴标签。
final class WeightChartPoint {
  const WeightChartPoint({
    required this.weightKg,
    required this.label,
    required this.sampleDays,
    this.localDate,
    this.axisLabel,
    this.isEmpty = false,
  });

  const WeightChartPoint.empty({
    required this.label,
    this.localDate,
    this.axisLabel,
  }) : weightKg = 0,
       sampleDays = 0,
       isEmpty = true;

  final double weightKg;

  /// 该槽位对应的本地日期（`yyyy-MM-dd`）。
  ///
  /// 图表需要它来判断「哪一格是今天」（Round7 A `.weight-slot.current`
  /// 用 `--brand` 画今天那一柱）；[label] 是给人看的短标签（「三」/「10/7」），
  /// 不能当日期用。旧调用点手搓的 [WeightChartPoint] 不传时为 null，
  /// 表示「不知道是哪一天」（此时不高亮任何一格）。
  final String? localDate;

  /// 完整的点标签：周视图是星期，月视图是 `月/日`。
  final String label;

  /// 可见横轴标签。为 null 时沿用 [label]；空字符串表示该月槽位不显示标签。
  final String? axisLabel;

  /// 该槽位由几天记录构成。周/月逐日视图的有值槽位均为 1。
  final int sampleDays;

  /// 该槽位没有记录，不得绘制柱。
  final bool isEmpty;

  String get visibleAxisLabel => axisLabel ?? label;
}

/// 周视图槽数恒为七格（周一至周日）。
const int weightWeekSlots = 7;

/// 周的起始日（周一）。
const int weightWeekStartWeekday = DateTime.monday;

/// 构建本月逐日槽位。
///
/// 月视图不再按记录点分箱：本月 1 日到月末每天都有一个槽位。没有记录的日子
/// 返回空槽；同一天多条记录取 `updatedAt` 最新的一条。横轴只显示稀疏标签
/// `{1, 5, 10, 15, 20, 25, 月末}`。
///
/// **2026-10-16 用户实测「月视图横坐标缺失」**：旧口径要求「锚点日**且**当天
/// 有记录」，于是整月只记几天时横轴几乎全空、日期读不出来。现在锚点日无论
/// 有没有记录都显示日号——横轴表达的是**日期**，不是「哪几天有数据」。
List<WeightChartPoint> buildMonthChartPoints(
  List<WeightMeasurement> measurements, {
  required String endLocalDate,
}) {
  final end = parseLocalDate(endLocalDate);
  final daysInMonth = DateTime(end.year, end.month + 1, 0).day;
  final byDate = <String, WeightMeasurement>{};

  for (final item in measurements) {
    final date = parseLocalDate(item.localDate);
    if (!_sameYearMonth(date, end)) continue;
    final existing = byDate[item.localDate];
    if (existing == null || item.updatedAt.isAfter(existing.updatedAt)) {
      byDate[item.localDate] = item;
    }
  }

  return [
    for (var day = 1; day <= daysInMonth; day++)
      () {
        final date = DateTime(end.year, end.month, day);
        final localDate = formatIsoLocalDate(date);
        final record = byDate[localDate];
        final fullLabel = '${date.month}/$day';
        // 2026-10-16 用户：「月视图你要标的是每周一对应的日期，而不是一堆日号」
        // ——横轴只标**每周一**的日期（10/5、10/12…），其余格子不标。
        final showsAxisLabel = date.weekday == weightWeekStartWeekday;
        final axisLabel = showsAxisLabel ? fullLabel : '';
        if (record == null) {
          return WeightChartPoint.empty(
            label: fullLabel,
            localDate: localDate,
            axisLabel: axisLabel,
          );
        }
        return WeightChartPoint(
          weightKg: record.weightKg,
          label: fullLabel,
          localDate: localDate,
          axisLabel: axisLabel,
          sampleDays: 1,
        );
      }(),
  ];
}

bool _sameYearMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

/// 构建本周逐日七格（周一至周日）。
List<WeightChartPoint> buildWeekChartPoints(
  List<WeightMeasurement> measurements, {
  required String endLocalDate,
}) {
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  final end = parseLocalDate(endLocalDate);
  final monday = end.subtract(
    Duration(days: end.weekday - weightWeekStartWeekday),
  );
  final byDate = <String, WeightMeasurement>{};
  for (final item in measurements) {
    final existing = byDate[item.localDate];
    if (existing == null || item.updatedAt.isAfter(existing.updatedAt)) {
      byDate[item.localDate] = item;
    }
  }
  return [
    for (var i = 0; i < weightWeekSlots; i++)
      () {
        final day = monday.add(Duration(days: i));
        final label = weekdays[day.weekday - 1];
        // 2026-10-22 用户：「周视图横坐标是周一~周日，文字全部显示」
        // ——横轴写星期全称（`周一`…`周日`），七天都标满；具体日期由
        // 体重卡上方的周期切换行（`10/20 – 10/26`）承担，两处不重复。
        final axisLabel = '周$label';
        final localDate = formatIsoLocalDate(day);
        final record = byDate[localDate];
        if (record == null) {
          return WeightChartPoint.empty(
            label: label,
            localDate: localDate,
            axisLabel: axisLabel,
          );
        }
        return WeightChartPoint(
          weightKg: record.weightKg,
          label: label,
          localDate: localDate,
          axisLabel: axisLabel,
          sampleDays: 1,
        );
      }(),
  ];
}

/// 按当前分段取柱点。
List<WeightChartPoint> buildWeightChartPoints(
  List<WeightMeasurement> measurements,
  WeightRange range, {
  required String endLocalDate,
}) => switch (range) {
  WeightRange.week => buildWeekChartPoints(
    measurements,
    endLocalDate: endLocalDate,
  ),
  WeightRange.month => buildMonthChartPoints(
    measurements,
    endLocalDate: endLocalDate,
  ),
};
