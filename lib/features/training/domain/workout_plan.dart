import 'dart:async';

import 'package:flutter/material.dart';

import 'package:localfit_ai/features/ai/domain/prompt_catalog.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';

/// workout-plan.v1 的 prompt 模板（**单一来源**）。
///
/// 正文里的占位符由 [OpenAiCompatibleWorkoutPlanProvider] 渲染成实际请求
/// （`days_per_week`/`exercise_library`/`goal_guidance`）；披露事实
/// （sendsWhat 等）渲染到「训练计划」任务卡。docs/11 P3：prompt 正文
/// 原先内联在 provider 里、目录守护扫不到——现在目录与正文同源，
/// egress 固定评测集钉住模板哈希。
const workoutPlanPromptTemplate = PromptTemplate(
  taskId: 'workout-plan',
  promptVersion: 'workout-plan-prompt-1',
  template:
      'Return only a JSON object matching workout-plan schema version 1. '
      'Do not use Markdown or prose. The JSON must contain schema_version, '
      'name, days, and warnings. Each day has weekday (1..7) and exercises. '
      'Each exercise must use an exercise_id copied exactly from the '
      'provided library list, plus target_sets (1..20), target_reps (1..100), '
      'and optional target_weight_kg (0..500). Never invent exercise ids. '
      'This is an unverified draft only.\n'
      'Generate a plan with exactly {days_per_week} day(s) per week.\n'
      'Exercise library (use these exercise_id values only):\n'
      '{exercise_library}{goal_guidance}\n'
      'All human-readable values in the JSON (name, warnings) MUST be '
      'written in Simplified Chinese. Keep JSON keys and the exercise_id '
      'values copied exactly as provided.',
  sendsWhat: '训练天数、目标描述与本地动作 allow-list（id 与名称）',
  neverSends: '完整食物目录、健康档案、训练历史与体测数据',
  destinationHint: '设置中的 BYOK AI 供应商主机',
);

final class PlannedExerciseDraft {
  const PlannedExerciseDraft({
    required this.exerciseId,
    required this.targetSets,
    required this.targetReps,
    this.targetWeightKg,
  });

  final String exerciseId;
  final int targetSets;
  final int targetReps;
  final double? targetWeightKg;
}

final class WorkoutPlanDayDraft {
  const WorkoutPlanDayDraft({required this.weekday, required this.entries});

  final int weekday;
  final List<PlannedExerciseDraft> entries;
}

final class WorkoutPlanDraft {
  const WorkoutPlanDraft({required this.name, required this.days});

  final String name;
  final List<WorkoutPlanDayDraft> days;
}

final class PlannedExerciseRecord {
  const PlannedExerciseRecord({
    required this.id,
    required this.exerciseId,
    required this.exerciseName,
    required this.equipment,
    required this.sortOrder,
    required this.targetSets,
    required this.targetReps,
    required this.targetWeightKg,
  });

  final String id;
  final String exerciseId;
  final String exerciseName;
  final Equipment equipment;
  final int sortOrder;
  final int targetSets;
  final int targetReps;
  final double? targetWeightKg;
}

final class WorkoutPlanDayRecord {
  const WorkoutPlanDayRecord({
    required this.id,
    required this.weekday,
    required this.entries,
  });

  final String id;
  final int weekday;
  final List<PlannedExerciseRecord> entries;
}

final class WorkoutPlanRecord {
  const WorkoutPlanRecord({
    required this.id,
    required this.name,
    required this.status,
    required this.source,
    required this.revision,
    required this.days,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String status;

  /// 计划来源（`WorkoutPlans.source`，`'ai'` / `'manual'`，docs/30 §2 D7）。
  ///
  /// **详情要如实说来历**：AI 排的计划改起来与手动计划没有区别，但用户有权
  /// 知道「这些动作是 AI 排的还是我自己挑的」——来源标签就是这句话。
  final String source;
  final int revision;
  final List<WorkoutPlanDayRecord> days;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class WorkoutPlanSummary {
  const WorkoutPlanSummary({
    required this.id,
    required this.name,
    required this.entryCount,
    required this.revision,
  });

  final String id;
  final String name;
  final int entryCount;
  final int revision;
}

const workoutWeekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

String workoutWeekdayLabel(int weekday) => workoutWeekdayLabels[weekday - 1];

/// 「周一 / 周二 / … / 周日」（2026-10-16 用户：「标的那个一、二、三什么的
/// 就不能变成周一之类的吗」）。
///
/// 与 [workoutWeekdayLabel] 的分工：**七枚日签**那种一格一个字的地方仍用
/// 单字（宽度只够一个字）；计划卡标题、计划页日卡、AI 草案预览这些有整行
/// 空间的地方用本函数。
String workoutWeekdayName(int weekday) =>
    '周${workoutWeekdayLabels[weekday - 1]}';

/// 计划行里动作的图标（2026-10-16 用户：「动作的图标也没有」）。
///
/// 依据是**动作库里的器械/肌群**（`ExerciseRecord`），不是猜名字：器械优先
/// （杠铃/哑铃/器械/绳索→力量，自重→徒手，有氧→跑动），器械缺省时看肌群
/// （核心→核心训练图标）。库里查不到（AI 对话里只有名字）时用中性力量图标。
IconData workoutExerciseIcon({Equipment? equipment, MuscleGroup? muscleGroup}) {
  switch (equipment) {
    case Equipment.barbell:
    case Equipment.dumbbell:
    case Equipment.machine:
    case Equipment.cable:
      return Icons.fitness_center;
    case Equipment.bodyweight:
      return Icons.accessibility_new;
    case Equipment.other:
    case null:
      break;
  }
  switch (muscleGroup) {
    case MuscleGroup.core:
      return Icons.self_improvement;
    case MuscleGroup.fullBody:
      return Icons.directions_run;
    case null:
    case MuscleGroup.chest:
    case MuscleGroup.back:
    case MuscleGroup.legs:
    case MuscleGroup.shoulders:
    case MuscleGroup.arms:
      return Icons.fitness_center;
  }
}

/// 计划来源的中文标签（`WorkoutPlans.source`，docs/30 §2 D7 第 ⑥ 帧）。
///
/// **不认识的值原样透出**：`source` 是自由文本列，将来多出一个来源时，把它
/// 显示成上次匹配到的那个中文词就是编造。宁可让用户看到 `ai_chat` 这样的
/// 原值，也不要让他看到一句错的说明。
String workoutPlanSourceLabel(String source) => switch (source) {
  'ai' => 'AI 生成',
  'manual' => '手动创建',
  _ => source,
};

final class ExerciseOption {
  const ExerciseOption({required this.id, required this.name});

  final String id;
  final String name;
}

final class AiWorkoutPlanRequest {
  const AiWorkoutPlanRequest({
    required this.daysPerWeek,
    required this.goalText,
    required this.exercises,
  });

  static const maxDays = 7;

  /// 界面可选的天数（1..[maxDays]）。**单一事实源**：训练页的胶囊从这份列表
  /// 生成——两边不会各写一套数字（2026-10-24 `RV4-P1-02` / R17-a：界面原先只
  /// 给到 5，而 `maxDays = 7`，用户选不到 6/7 天）。
  static const dayOptions = [1, 2, 3, 4, 5, 6, 7];

  static const maxGoalLength = 300;

  /// allow-list 上限：种子动作库 312 条 + 自建，留出余量。
  /// 2026-10-16（用户：「AI 从动作库中选动作」）从 60 提到 400——60 会把
  /// 整库砍成前 60 条，AI 看不到剩下的动作。
  static const maxExercises = 400;

  final int daysPerWeek;
  final String goalText;
  final List<ExerciseOption> exercises;

  void validate() {
    if (daysPerWeek < 1 || daysPerWeek > maxDays) {
      throw const FormatException('训练天数必须在 1 到 7 之间。');
    }
    // 2026-10-16 用户：「目标不能是可选」——空目标不再合法。
    if (goalText.trim().isEmpty) {
      throw const FormatException('请填写训练目标。');
    }
    if (goalText.length > maxGoalLength) {
      throw const FormatException('目标描述过长，请控制在 300 字以内。');
    }
    if (exercises.isEmpty || exercises.length > maxExercises) {
      throw FormatException('请提供 1 到 $maxExercises 个本地动作。');
    }
    if (exercises.any((exercise) => exercise.id.isEmpty)) {
      throw const FormatException('动作信息无效。');
    }
    if (exercises.map((exercise) => exercise.id).toSet().length !=
        exercises.length) {
      throw const FormatException('动作列表包含重复项。');
    }
  }
}

final class AiWorkoutPlanDayDraft {
  const AiWorkoutPlanDayDraft({required this.weekday, required this.entries});

  final int weekday;
  final List<PlannedExerciseDraft> entries;
}

final class AiWorkoutPlanDraft {
  const AiWorkoutPlanDraft({
    required this.name,
    required this.days,
    required this.warnings,
  });

  final String name;
  final List<AiWorkoutPlanDayDraft> days;
  final List<String> warnings;
}

final class WorkoutPlanCancellationToken {
  WorkoutPlanCancellationToken();

  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

abstract interface class WorkoutPlanProvider {
  Future<AiWorkoutPlanDraft> generate(
    AiWorkoutPlanRequest request, {
    WorkoutPlanCancellationToken? cancellationToken,
  });
}
