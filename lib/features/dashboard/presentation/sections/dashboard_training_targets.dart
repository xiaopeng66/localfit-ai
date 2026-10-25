import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/features/training/application/training_stats.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/presentation/sections/training_target_indicator.dart';

/// 训练达标指标图示（docs/21 §5.1 第 5 项）：今日 / 本周计划完成进度。
///
/// 只读本地事实，两行都是「已完成 / 计划」的原始计数：
/// - **今日**：当日计划动作里，已记录到组次的数量 / 当日计划动作总数；
/// - **本周**：本周已完成的计划训练日 / 本周已到期的计划训练日
///   （复用 [TrainingStatsCalculator.weeklyCompletion]，与训练页同一算法）。
///
/// 没有计划时不渲染达标状态（不编造 0/0 的进度）。
///
/// 设计稿的今日页没有这一格，按 docs/22 §3 收进二级入口：由训练页的
/// 入口行以底部弹层承载（docs/22 阶段 I 补漏），单元本身按 docs/21
/// 的卡片形态（`DesignCard`）重建。
class DashboardTrainingTargets extends StatefulWidget {
  const DashboardTrainingTargets({
    super.key,
    required this.planRepository,
    required this.sessionRepository,
    required this.localDate,
  });

  final WorkoutPlanRepository planRepository;
  final WorkoutSessionRepository sessionRepository;

  /// 本地日期（`yyyy-MM-dd`）。
  final String localDate;

  @override
  State<DashboardTrainingTargets> createState() =>
      _DashboardTrainingTargetsState();
}

class _DashboardTrainingTargetsState extends State<DashboardTrainingTargets> {
  String? _loadedDate;
  Future<_Targets> _future = Future.value(const _Targets.none());

  /// 按日期缓存 Future：本单元随上游流每次重建都会重新 build，
  /// 在 build 里新建 Future 会重复打查询（与趋势卡/时间线同一做法）。
  void _ensureFuture() {
    if (_loadedDate == widget.localDate) return;
    _loadedDate = widget.localDate;
    _future = _load();
  }

  Future<_Targets> _load() async {
    final summaries = await widget.planRepository.list();
    if (summaries.isEmpty) return const _Targets.none();
    // 列表按创建时间倒序：第一份就是最近创建的计划（当前计划）。
    final plan = await widget.planRepository.getById(summaries.first.id);
    if (plan == null || plan.days.isEmpty) return const _Targets.none();

    final today = _parse(widget.localDate);
    final todayWeekday = today.weekday;
    final plannedToday = plan.days
        .where((day) => day.weekday == todayWeekday)
        .expand((day) => day.entries)
        .toList(growable: false);

    final sessions = await widget.sessionRepository.listFinishedBetween(
      widget.localDate,
      widget.localDate,
    );
    final plannedIds = {for (final entry in plannedToday) entry.id};
    final doneToday = <String>{};
    for (final session in sessions) {
      for (final set in session.sets) {
        final plannedExerciseId = set.plannedExerciseId;
        if (plannedExerciseId != null &&
            plannedIds.contains(plannedExerciseId)) {
          doneToday.add(plannedExerciseId);
        }
      }
    }

    final weekStart = today.subtract(Duration(days: todayWeekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekSessions = await widget.sessionRepository.listFinishedBetween(
      _format(weekStart),
      _format(weekEnd),
    );
    final completion = const TrainingStatsCalculator().weeklyCompletion(
      planId: plan.id,
      planWeekdays: [for (final day in plan.days) day.weekday],
      weekStart: weekStart,
      today: today,
      finishedSessions: weekSessions,
    );

    return _Targets(
      todayDone: doneToday.length,
      todayTotal: plannedToday.length,
      weekDone: completion?.completedDays,
      weekTotal: completion?.scheduledDays,
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensureFuture();
    final c = context.lf;
    return DesignCard(
      key: const Key('dashboard-training-targets'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DesignCardHeader(title: '训练达标'),
          const SizedBox(height: LfDimens.spaceMedium),
          FutureBuilder<_Targets>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const AppErrorText('训练达标加载失败，请重试。');
              }
              final targets = snapshot.data;
              if (targets == null) {
                return const SizedBox(
                  height: 48,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (!targets.hasPlan) {
                return Text(
                  '还没有训练计划。到「训练」页创建后即可查看达标进度。',
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                );
              }
              return Column(
                children: [
                  TrainingTargetIndicator(
                    label: '今日计划',
                    completed: targets.todayDone,
                    total: targets.todayTotal,
                    unit: '个动作',
                  ),
                  if (targets.weekTotal != null) ...[
                    const SizedBox(height: LfDimens.spaceMedium),
                    TrainingTargetIndicator(
                      label: '本周计划',
                      completed: targets.weekDone ?? 0,
                      total: targets.weekTotal!,
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 达标计数的中间结果：`hasPlan == false` 时其余字段无意义。
final class _Targets {
  const _Targets({
    required this.todayDone,
    required this.todayTotal,
    required this.weekDone,
    required this.weekTotal,
  });

  const _Targets.none()
    : todayDone = 0,
      todayTotal = 0,
      weekDone = null,
      weekTotal = null;

  final int todayDone;
  final int todayTotal;
  final int? weekDone;
  final int? weekTotal;

  bool get hasPlan => todayTotal > 0 || weekTotal != null;
}

DateTime _parse(String localDate) {
  final parts = localDate.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

String _format(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
