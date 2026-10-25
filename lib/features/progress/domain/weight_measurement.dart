final class WeightMeasurement {
  const WeightMeasurement({
    required this.id,
    required this.profileId,
    required this.localDate,
    required this.weightKg,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.source,
  });

  final String id;
  final String profileId;
  final String localDate;
  final double weightKg;

  // 体脂率 % 与肌肉量 kg 两个字段随 schema 22 删除（docs/31 S2，需求 45/46）：
  // 用户原话「添加的弹窗卡片去掉体脂率和肌肉量」+「其他所有地方有关于这两个
  // 数据的都删掉」。此处**没有**「保留字段但不用」的中间态——字段还在，
  // 弹层、页面接线与 AI executor 就会跟着复活。
  final String? notes;

  /// 落库来源（`manual` / `ble_scale`，docs/31 S6 需求 47 / D6 ③）。
  /// 旧数据可能为 null（该列早于来源标记存在）；展示层只把它翻译成
  /// 「手输 / 秤同步」，不为 null 猜一个值。
  final String? source;

  final DateTime createdAt;
  final DateTime updatedAt;
}

final class WeightOverview {
  const WeightOverview({
    required this.measurements,
    required this.latest,
    required this.sevenDayAverageKg,
    required this.sampleDays,
  });

  final List<WeightMeasurement> measurements;
  final WeightMeasurement? latest;
  final double? sevenDayAverageKg;
  final int sampleDays;
}

WeightOverview calculateWeightOverview({
  required List<WeightMeasurement> measurements,
  required String endLocalDate,
}) {
  final end = parseLocalDate(endLocalDate);
  final start = end.subtract(const Duration(days: 6));
  final latestByDate = <String, WeightMeasurement>{};
  WeightMeasurement? latest;
  for (final measurement in measurements) {
    final date = parseLocalDate(measurement.localDate);
    if (!date.isBefore(start) && !date.isAfter(end)) {
      final existing = latestByDate[measurement.localDate];
      if (existing == null ||
          measurement.updatedAt.isAfter(existing.updatedAt)) {
        latestByDate[measurement.localDate] = measurement;
      }
    }
    if (!date.isAfter(end) &&
        (latest == null ||
            date.isAfter(parseLocalDate(latest.localDate)) ||
            date.isAtSameMomentAs(parseLocalDate(latest.localDate)) &&
                measurement.updatedAt.isAfter(latest.updatedAt))) {
      latest = measurement;
    }
  }
  final window = latestByDate.values.toList()
    ..sort((a, b) => a.localDate.compareTo(b.localDate));
  final average = window.isEmpty
      ? null
      : window.fold<double>(0, (total, value) => total + value.weightKg) /
            window.length;
  return WeightOverview(
    measurements: List.unmodifiable(window),
    latest: latest,
    sevenDayAverageKg: average,
    sampleDays: window.length,
  );
}

DateTime parseLocalDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) throw const FormatException('日期格式无效。');
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw const FormatException('日期无效。');
  }
  return parsed;
}

/// `yyyy-MM-dd` → `M 月 D 日`（弹层标题与保存提示用，docs/29 §P9 需求 33）。
///
/// 解析失败退回原文：这是给人看的装饰文本，**不许因此在任何地方抛异常**
/// ——但也不吞掉原值，让一个格式坏掉的日期至少可见。
String formatMonthDayLabel(String localDate) {
  try {
    final date = parseLocalDate(localDate);
    return '${date.month} 月 ${date.day} 日';
  } on FormatException {
    return localDate;
  }
}

/// `yyyy-MM-dd` 格式化（与 [parseLocalDate] 同一格式，零依赖）。
String formatIsoLocalDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
