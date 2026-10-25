import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';

/// 水分目标的合法范围（升）。界面以 L 输入、库里以 ml 存
/// （`DailyTargets.waterTargetMl`），这一对数字是**唯一口径源**：
/// 界面 `validator` 与这里的写入校验都从它来，避免两处各写一套。
const double kMinWaterTargetLiters = 0.5;
const double kMaxWaterTargetLiters = 6.0;

/// 写入被拒绝（越界 / 没有可依附的每日目标行）。
///
/// 用**具名异常**而不是 `ArgumentError`：界面对「用户填的数不对」与
/// 「这条记录压根不该存在」要给不同的话（前者是校验、后者是环境事实），
/// 调用方靠类型区分这两种失败。
final class WaterTargetException implements Exception {
  const WaterTargetException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 「我的 → 编辑资料」页的水分目标写入口（docs/32 §3 D11 / §4 T9）。
///
/// **版本化语义**（`DailyTargets` 是按 `effectiveDate` 生效的行序列）：
/// - 读「当日生效行」= `effectiveDate <= today` 里 `effectiveDate` 最大的那条，
///   与 `WaterRepository.watchDay` / `MealRepository` 的取值口径一致；
/// - 写：**该行就是今天的行 ⇒ 就地更新**（今天还没有历史，改它不篡改任何已发生的口径）；
///   **否则插一条新版本行**（`effectiveDate = today`，其余列逐字复制、`updatedAt` 刷新），
///   于是今天之前的日期仍读它们各自生效的那条 —— 历史口径一个字不改。
///
/// 不复制其余列的话，新行会拿 schema 默认值冒充热量/宏量目标（编事实）；
/// 所以「没有可依附的生效行」时**直接拒绝**而不是造一行出来。
final class UpdateWaterTargetMl {
  const UpdateWaterTargetMl({
    required this.database,
    required this.idGenerator,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;

  /// 读 [today] 生效的水分目标（ml）；没有生效行返回 null（不拿默认值冒充）。
  Future<double?> readCurrentMl(String today) async {
    final row = await _currentEffectiveRow(today);
    return row?.waterTargetMl;
  }

  /// 把 [today] 起生效的水分目标写成 [targetMl]。
  ///
  /// [targetMl] 越界 / 非有限 ⇒ [WaterTargetException]；没有生效行 ⇒
  /// [WaterTargetException]（未建档的库不该有编辑入口）。
  Future<void> run({required double targetMl, required String today}) async {
    if (!targetMl.isFinite ||
        targetMl < kMinWaterTargetLiters * 1000 ||
        targetMl > kMaxWaterTargetLiters * 1000) {
      throw const WaterTargetException('水分目标需在 0.5–6.0 L 之间');
    }
    final now = clock.nowUtc();
    await database.transaction(() async {
      final current = await _currentEffectiveRow(today);
      if (current == null) {
        throw const WaterTargetException('尚未建立每日目标，无法设置水分目标');
      }
      if (current.effectiveDate == today) {
        await (database.update(
          database.dailyTargets,
        )..where((row) => row.id.equals(current.id))).write(
          DailyTargetsCompanion(
            waterTargetMl: Value(targetMl),
            updatedAt: Value(now),
          ),
        );
        return;
      }
      await database
          .into(database.dailyTargets)
          .insert(
            DailyTargetsCompanion.insert(
              id: idGenerator.next(),
              goalId: current.goalId,
              effectiveDate: today,
              calorieMinKcal: current.calorieMinKcal,
              calorieMaxKcal: current.calorieMaxKcal,
              proteinMinGrams: current.proteinMinGrams,
              proteinMaxGrams: current.proteinMaxGrams,
              carbsMinGrams: current.carbsMinGrams,
              carbsMaxGrams: current.carbsMaxGrams,
              fatMinGrams: current.fatMinGrams,
              fatMaxGrams: current.fatMaxGrams,
              waterTargetMl: Value(targetMl),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
  }

  Future<DailyTarget?> _currentEffectiveRow(String today) {
    return (database.select(database.dailyTargets)
          ..where((row) => row.effectiveDate.isSmallerOrEqualValue(today))
          ..orderBy([(row) => OrderingTerm.desc(row.effectiveDate)])
          ..limit(1))
        .getSingleOrNull();
  }
}
