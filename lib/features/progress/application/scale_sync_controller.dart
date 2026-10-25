import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/scale_channel.dart';
import 'package:localfit_ai/features/progress/data/scale_reading_source.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

export 'package:localfit_ai/features/progress/data/scale_channel.dart';

/// 一次「授权并同步」的结局（docs/31 S6 需求 47 / D6）。
///
/// 密封类：界面按结局给**不同的下一句话**，不许合并成「同步失败」——
/// 「秤没唤醒」「没授权」「今天已有手输值」的用户动作完全不同。
sealed class ScaleSyncOutcome {
  const ScaleSyncOutcome();
}

/// 读到且落了库（当天原本没有记录）。
final class ScaleSyncSaved extends ScaleSyncOutcome {
  const ScaleSyncSaved({required this.weightKg, required this.measurement});

  final double weightKg;
  final WeightMeasurement measurement;
}

/// 同日已有记录：**默认不覆盖**（D6 ③），把两边数值交给界面让用户明确选；
/// 用户选覆盖后走 [ScaleSyncController.overwriteSameDay]。
final class ScaleSyncConflict extends ScaleSyncOutcome {
  const ScaleSyncConflict({
    required this.scaleWeightKg,
    required this.existing,
  });

  final double scaleWeightKg;
  final WeightMeasurement existing;
}

/// 10 秒内没发现广播标准体重秤服务的设备（秤没唤醒 / 私有协议）。
final class ScaleSyncNoScale extends ScaleSyncOutcome {
  const ScaleSyncNoScale();
}

/// 连上了秤但窗口内没等到体重测量通知。
final class ScaleSyncTimeout extends ScaleSyncOutcome {
  const ScaleSyncTimeout();
}

/// 缺蓝牙运行时权限（用户在系统对话框里拒了）。
final class ScaleSyncPermissionDenied extends ScaleSyncOutcome {
  const ScaleSyncPermissionDenied();
}

/// 这台设备不支持（API ≤ 30 或没有蓝牙适配器；D6 备注的诚实降级）。
final class ScaleSyncUnsupported extends ScaleSyncOutcome {
  const ScaleSyncUnsupported();
}

/// 读数超出本应用体重口径（35–300 kg），不落库。
final class ScaleSyncOutOfRange extends ScaleSyncOutcome {
  const ScaleSyncOutOfRange(this.weightKg);

  final double weightKg;
}

/// 电子体重秤同步编排（设置页行 → 弹层的背后）。
///
/// 只做**编排与判定**：读数来自 [ScaleReadingSource] 抽象（标准协议 /
/// 将来的私有协议都只是它的不同实现，D16），落库与不覆盖规则在
/// [MeasurementRepository.saveScaleWeight]，这里不碰 SQL 也不碰平台通道
/// 细节——三层各自可测（D6 ⑤ 的验收上限就是这三层的假设备单测）。
final class ScaleSyncController {
  const ScaleSyncController({
    required this.source,
    required this.repository,
    required this.clock,
  });

  final ScaleReadingSource source;
  final MeasurementRepository repository;
  final AppClock clock;

  /// 同步日的 `yyyy-MM-dd`（本地时区；秤读数落的是「今天」的体重）。
  String todayLocalDate() => formatIsoLocalDate(clock.nowUtc().toLocal());

  /// 设置行状态（不缓存：每次进设置页都重查，权限可能刚被用户改过）。
  Future<ScaleAvailability> availability() => source.check();

  /// 用户点了「授权并开始同步」：请求权限 → 前台扫描一次 → 按落地规则处置。
  Future<ScaleSyncOutcome> sync() async {
    final availability = await source.check();
    if (availability == ScaleAvailability.unsupported) {
      return const ScaleSyncUnsupported();
    }
    final granted = await source.requestPermission();
    if (!granted) return const ScaleSyncPermissionDenied();

    final reading = await source.readOnce();
    switch (reading.status) {
      case ScaleReadStatus.ok:
        final weightKg = reading.grams! / 1000;
        if (weightKg < 35 || weightKg > 300) {
          return ScaleSyncOutOfRange(weightKg);
        }
        final localDate = todayLocalDate();
        final existing = await repository.findByDate(localDate);
        if (existing != null) {
          // 同日已有记录：一个字都不写，交回界面让用户选（默认保留）。
          return ScaleSyncConflict(scaleWeightKg: weightKg, existing: existing);
        }
        final saved = await repository.saveScaleWeight(
          localDate: localDate,
          weightKg: weightKg,
          overwriteSameDay: false,
        );
        return ScaleSyncSaved(
          weightKg: weightKg,
          measurement: saved.measurement,
        );
      case ScaleReadStatus.noScale:
        return const ScaleSyncNoScale();
      case ScaleReadStatus.timeout:
        return const ScaleSyncTimeout();
      case ScaleReadStatus.denied:
        return const ScaleSyncPermissionDenied();
      case ScaleReadStatus.unsupported:
        return const ScaleSyncUnsupported();
    }
  }

  /// 用户在冲突弹层里**明确**选了「用秤读数覆盖」。
  Future<WeightMeasurement> overwriteSameDay({
    required double scaleWeightKg,
  }) async {
    final saved = await repository.saveScaleWeight(
      localDate: todayLocalDate(),
      weightKg: scaleWeightKg,
      overwriteSameDay: true,
    );
    return saved.measurement;
  }
}
