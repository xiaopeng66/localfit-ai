import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_energy_card.dart';

/// 记录页的热量卡区块。
///
/// 从 `record_tab.dart` 拆出仅为遵守每文件 ≤500 行预算；数据流、错误态与
/// 目标回调保持原样。目标仍由父级持有，热量卡、趋势卡、分析卡因此共享
/// 同一份快照，不会各读一条流后出现一帧不一致。
class RecordEnergySection extends StatelessWidget {
  const RecordEnergySection({
    super.key,
    required this.repository,
    required this.localDate,
    required this.selectedDate,
    required this.now,
    required this.onTargetChanged,
    this.onEditTarget,
  });

  final MealRepository repository;
  final String localDate;
  final DateTime selectedDate;
  final DateTime now;
  final void Function(double? minKcal, double? maxKcal) onTargetChanged;
  final VoidCallback? onEditTarget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: LfDimens.pagePadding),
      child: StreamBuilder<DailyNutritionSummary>(
        stream: repository.watchNutritionForDate(localDate),
        builder: (context, snapshot) {
          final summary = snapshot.data;
          if (snapshot.hasData) {
            final target = summary?.target;
            onTargetChanged(target?.calorieMinKcal, target?.calorieMaxKcal);
          }
          if (snapshot.hasError) {
            return const Padding(
              padding: EdgeInsets.all(LfDimens.pagePadding),
              child: AppErrorText('当日营养加载失败。'),
            );
          }
          return NutritionRecordEnergyCard(
            consumed:
                summary?.consumed ??
                const NutritionValues(
                  kcal: 0,
                  proteinGrams: 0,
                  carbsGrams: 0,
                  fatGrams: 0,
                ),
            target: summary?.target,
            selectedDate: selectedDate,
            now: now,
            onEditTarget: onEditTarget,
          );
        },
      ),
    );
  }
}
