import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 用户**手动指定**的每日营养目标（2026-10-26 用户：「营养摄入自己不能改」）。
///
/// 背景：热量/宏量目标原本只由 `NutritionTargetCalculator` 从身体数据算出来，
/// 全应用没有任何覆盖入口。这里给一条**显式**的手动通道——它不改公式、不改
/// 身体数据，只回答「从某天起，按我给的区间算」。
///
/// 【为什么带生效日期】目标是按天生效的（`DailyTargets.effectiveDate` 同一
/// 口径）：今天改目标不该把过去几天的判定改掉。所以手动目标也带一个生效日，
/// 早于它的日期仍走原来的行。
///
/// 【为什么 goalType 用 `manual`】卡上要标**依据**：数字是用户填的，就不能
/// 再声称「按 Mifflin–St Jeor 算的」——那是句假话。
final class NutritionTargetOverride {
  const NutritionTargetOverride({
    required this.effectiveDate,
    required this.calorieMinKcal,
    required this.calorieMaxKcal,
    required this.proteinMinGrams,
    required this.proteinMaxGrams,
    required this.carbsMinGrams,
    required this.carbsMaxGrams,
    required this.fatMinGrams,
    required this.fatMaxGrams,
  });

  /// `DailyNutritionTarget.goalType` 的取值：手动目标。
  static const goalType = 'manual';

  /// `AppSettings` 里的键（值 = JSON）。
  static const settingsKey = 'nutrition_target_manual';

  final String effectiveDate;
  final double calorieMinKcal;
  final double calorieMaxKcal;
  final double proteinMinGrams;
  final double proteinMaxGrams;
  final double carbsMinGrams;
  final double carbsMaxGrams;
  final double fatMinGrams;
  final double fatMaxGrams;

  /// 合理区间（只挡明显打错的值，不替用户改数字）。
  static const minCalorieKcal = 500.0;
  static const maxCalorieKcal = 10000.0;
  static const maxMacroGrams = 1000.0;

  /// 校验通过就返回 null；否则返回一句人话（弹层直接显示）。
  String? validate() {
    if (!_isValidDate(effectiveDate)) return '生效日期格式不对（应为 yyyy-MM-dd）。';
    final ranges = <String, (double, double, double, double)>{
      '热量': (calorieMinKcal, calorieMaxKcal, minCalorieKcal, maxCalorieKcal),
      '蛋白质': (proteinMinGrams, proteinMaxGrams, 0, maxMacroGrams),
      '碳水': (carbsMinGrams, carbsMaxGrams, 0, maxMacroGrams),
      '脂肪': (fatMinGrams, fatMaxGrams, 0, maxMacroGrams),
    };
    for (final entry in ranges.entries) {
      final (min, max, floor, ceiling) = entry.value;
      if (!min.isFinite || !max.isFinite || min < floor || max > ceiling) {
        return '${entry.key}区间超出合理范围。';
      }
      if (min > max) return '${entry.key}的下限不能大于上限。';
    }
    return null;
  }

  DailyNutritionTarget toTarget() => DailyNutritionTarget(
    goalType: goalType,
    calorieMinKcal: calorieMinKcal,
    calorieMaxKcal: calorieMaxKcal,
    proteinMinGrams: proteinMinGrams,
    proteinMaxGrams: proteinMaxGrams,
    carbsMinGrams: carbsMinGrams,
    carbsMaxGrams: carbsMaxGrams,
    fatMinGrams: fatMinGrams,
    fatMaxGrams: fatMaxGrams,
  );

  Map<String, Object?> toJson() => {
    'effectiveDate': effectiveDate,
    'calorieMinKcal': calorieMinKcal,
    'calorieMaxKcal': calorieMaxKcal,
    'proteinMinGrams': proteinMinGrams,
    'proteinMaxGrams': proteinMaxGrams,
    'carbsMinGrams': carbsMinGrams,
    'carbsMaxGrams': carbsMaxGrams,
    'fatMinGrams': fatMinGrams,
    'fatMaxGrams': fatMaxGrams,
  };

  /// 坏值/缺键都返回 null（当作「没有手动目标」）：一个存坏的设置不该让整张
  /// 营养卡读不出目标。
  static NutritionTargetOverride? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final date = json['effectiveDate'];
    if (date is! String || !_isValidDate(date)) return null;
    double? number(String key) {
      final value = json[key];
      return value is num ? value.toDouble() : null;
    }

    final calorieMin = number('calorieMinKcal');
    final calorieMax = number('calorieMaxKcal');
    final proteinMin = number('proteinMinGrams');
    final proteinMax = number('proteinMaxGrams');
    final carbsMin = number('carbsMinGrams');
    final carbsMax = number('carbsMaxGrams');
    final fatMin = number('fatMinGrams');
    final fatMax = number('fatMaxGrams');
    if (calorieMin == null ||
        calorieMax == null ||
        proteinMin == null ||
        proteinMax == null ||
        carbsMin == null ||
        carbsMax == null ||
        fatMin == null ||
        fatMax == null) {
      return null;
    }
    final value = NutritionTargetOverride(
      effectiveDate: date,
      calorieMinKcal: calorieMin,
      calorieMaxKcal: calorieMax,
      proteinMinGrams: proteinMin,
      proteinMaxGrams: proteinMax,
      carbsMinGrams: carbsMin,
      carbsMaxGrams: carbsMax,
      fatMinGrams: fatMin,
      fatMaxGrams: fatMax,
    );
    return value.validate() == null ? value : null;
  }

  static bool _isValidDate(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return false;
    return value.length == 10 &&
        value[4] == '-' &&
        value[7] == '-' &&
        parsed.year > 1900;
  }
}
