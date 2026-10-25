import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show formatLocalDate;
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// A 的参考摄入基数（`app.js` 字面量 2200 kcal）。
///
/// 周条短条**恒**以它为分母（真实数值由每天的语义标签给出）；趋势纵轴的取法
/// 见 [buildCalorieTrendBars]。
const double kTrendBaseKcal = 2200;

/// 近 7 日热量趋势的柱图数据（docs/21 §5.2 `nutrition-record-trend-chart`）。
///
/// 纯函数、无 IO：柱高比例、达标判定、星期标签都在这里算完，页面只负责画。
/// 这样「今天是不是最后一柱」「达标怎么判定」这类易错点可以脱离 widget 测试。
final class CalorieTrendBars {
  const CalorieTrendBars({
    required this.dates,
    required this.weekdayLabels,
    required this.fractions,
    required this.kcalByDay,
    required this.hitCount,
    required this.trackedDays,
    required this.scaleMaxKcal,
    this.belowMinCount,
  });

  /// 7 个本地日期（`yyyy-MM-dd`，升序，末位 = 窗口最后一天）。
  final List<String> dates;

  /// 7 个星期字（一/二/…/日），**按 [dates] 的真实星期推导**。
  ///
  /// docs/21 §6.2 裁决：设计稿里「今天」恒落在周二是因为它是 demo 数据，
  /// 实现必须按真实日期算，不得把星期写死成设计稿那一列。
  final List<String> weekdayLabels;

  /// 每柱高度比例（0..1），[scaleMaxKcal] 为分母。
  final List<double> fractions;

  /// 每柱的原始摄入（无记录日为 null）。柱图 tooltip 与文字等价物都用它。
  final List<double?> kcalByDay;

  /// 未超上限的天数（有记录且 `kcal <= calorieMax`）；无目标时为 null
  /// （不编达标数）。
  ///
  /// **2026-10-23 用户**：「今日达标但没变 0/7」。原口径要求落在
  /// `[calorieMin, calorieMax]`，而目标区间是中心值 ±5%：摄入在 95% 上限
  /// 附近时「目标达成率」看起来已经达标，达标天数却仍是 0。现在达标按
  /// **不超过上限**判定；低于下限的日子由 [belowMinCount] 单独计数并在
  /// 洞察里如实提示——不把「吃太少」混进达标，也不让它静默消失。
  final int? hitCount;

  /// 低于目标下限的天数（有记录且 `kcal < calorieMin`）；无下界/无目标时
  /// 为 null。与 [hitCount] 分开：两者回答的是不同问题。
  final int? belowMinCount;

  /// 窗口内有记录的天数。
  final int trackedDays;

  /// 纵轴上限：`max(kTrendBaseKcal, 目标, 窗口峰值)`（A 口径，见 D17）。
  ///
  /// 不用「峰值 × 1.1」：低摄入日会把上界压到 330 这类值，柱子个个顶天，
  /// 读起来像「吃了满满一天」。2200 是 A 给的参考基数，周条 mini 条与趋势
  /// 柱共用同一个口径（两处同源，不各算各的）。
  final double scaleMaxKcal;
}

/// 日摄入 kJ 记录 + 目标区间 → 柱图数据。
///
/// [records] 是窗口内**有记录**的日（`IntakeTrend.records` 的形态），
/// 缺记录的日子按「无记录」处理（柱高 4dp 的 muted 短柱），不补 0——
/// 「那天没吃」与「那天吃了 0 kcal」是两件事。
CalorieTrendBars buildCalorieTrendBars({
  required List<DailyIntakeRecord> records,
  required DateTime endDate,
  double? targetMinKcal,
  double? targetMaxKcal,
  int days = 7,
}) {
  assert(days > 0);
  final end = DateTime(endDate.year, endDate.month, endDate.day);
  final dates = [
    for (var i = days - 1; i >= 0; i--)
      formatLocalDate(end.subtract(Duration(days: i))),
  ];
  final byDay = {for (final record in records) record.localDate: record.kcal};
  final kcalByDay = [for (final date in dates) byDay[date]];

  final target = targetMaxKcal;
  final peak = kcalByDay.whereType<double>().fold<double>(
    0,
    (a, b) => a > b ? a : b,
  );
  // A 的口径（D17）：三条基准线取大者。2200 恒在场，所以分母永不为 0，
  // 无需再兜 1.0——全空窗口的比例全是 0（柱高由画法给 3% 短柱）。
  final scaleMax = [
    kTrendBaseKcal,
    ?target,
    peak,
  ].reduce((a, b) => a > b ? a : b);

  return CalorieTrendBars(
    dates: dates,
    weekdayLabels: [for (final date in dates) _weekdayLabel(date)],
    fractions: [
      for (final kcal in kcalByDay)
        kcal == null ? 0 : (kcal / scaleMax).clamp(0.0, 1.0),
    ],
    kcalByDay: kcalByDay,
    // 无上界 = 没有目标 = 达标无从谈起（返回 null，界面不编分母）。
    // 达标按「未超上限」判定（2026-10-23 用户反馈）；低于下限另计，
    // 由洞察提示，不参与达标判定。
    hitCount: target == null
        ? null
        : kcalByDay.whereType<double>().where((kcal) => kcal <= target).length,
    belowMinCount: target == null || targetMinKcal == null
        ? null
        : kcalByDay
              .whereType<double>()
              .where((kcal) => kcal < targetMinKcal)
              .length,
    trackedDays: kcalByDay.whereType<double>().length,
    scaleMaxKcal: scaleMax,
  );
}

/// `yyyy-MM-dd` → 星期字（一..日）。
String _weekdayLabel(String localDate) {
  const labels = ['一', '二', '三', '四', '五', '六', '日'];
  final parts = localDate.split('-');
  final date = DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  return labels[date.weekday - 1];
}
