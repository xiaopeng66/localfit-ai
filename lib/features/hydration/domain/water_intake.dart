import 'package:localfit_ai/features/progress/domain/weight_measurement.dart'
    show parseLocalDate;

/// 一条饮水记录（docs/21 §7.2 `WaterIntakes`）。
final class WaterIntakeRecord {
  const WaterIntakeRecord({
    required this.id,
    required this.localDate,
    required this.amountMl,
    required this.recordedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String localDate;
  final double amountMl;
  final DateTime recordedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// 一天（或某窗口）的饮水汇总。
///
/// `targetMl` 为 null = 未设定目标：此时「达标 N%」必须显示占位而非拿
/// 0 或示例值冒充（docs/21 §6.1 诚实规则）。
final class WaterSummary {
  const WaterSummary({
    required this.consumedMl,
    required this.targetMl,
    required this.records,
  });

  static const empty = WaterSummary(consumedMl: 0, targetMl: null, records: []);

  final double consumedMl;
  final double? targetMl;
  final List<WaterIntakeRecord> records;

  /// 达标百分比（0..100 的整数）；无目标或目标非正时返回 null。
  int? get percent {
    final target = targetMl;
    if (target == null || target <= 0) return null;
    return (consumedMl / target * 100).round().clamp(0, 999);
  }

  /// 0..1 的进度（进度条宽度）；无目标时 0。
  double get progress {
    final target = targetMl;
    if (target == null || target <= 0) return 0;
    return (consumedMl / target).clamp(0.0, 1.0);
  }

  /// 还差多少毫升达标；已达标或未设目标返回 null。
  double? get remainingMl {
    final target = targetMl;
    if (target == null || target <= 0) return null;
    final gap = target - consumedMl;
    return gap > 0 ? gap : null;
  }

  /// 「1.5 / 2.0 L」里的升数文案（保留一位小数）。
  String get consumedLitersLabel => (consumedMl / 1000).toStringAsFixed(1);

  String get targetLitersLabel =>
      targetMl == null ? '--' : (targetMl! / 1000).toStringAsFixed(1);
}

/// 加水的快捷量（docs/21 §5.1 饮水卡：+250ml 等）。
///
/// 只放常用杯型；用户名下的任意数值走 `add(amountMl)`。
const waterQuickAmountsMl = <double>[250, 350, 500];

/// 校验一次加水的量。
///
/// 上限 5000ml：单次记录超过这个数几乎必是误输入（把 L 当 ml 填），
/// 与其静默入库让「达标 5000%」这种脏数据进统计，不如拒掉。
double validateWaterAmountMl(double value) {
  if (!value.isFinite || value <= 0) {
    throw const FormatException('饮水量必须大于 0。');
  }
  if (value > 5000) {
    throw const FormatException('单次饮水记录不能超过 5000 ml。');
  }
  return value;
}

/// 校验 localDate 形状（与其它仓储同口径）。
void validateWaterLocalDate(String value) {
  parseLocalDate(value);
}
