import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// AI 训练计划草案的**共享卡片**（2026-10-16 用户：「生成的计划界面太丑 ⇒
/// 卡片式，并能复用在 AI 对话里」）。
///
/// 三处宿主共用这一件，**不再各画一份**：
///  * 训练计划创建页的预览（`/workout-plan-create`）；
///  * 训练页「AI 排计划」弹层里的预览；
///  * AI 对话编辑卡里的 `workout.plan.create` 行（对话里直接看到卡片）。
///
/// 形态：每天一张 `DesignCard`（星期标题 + 动作行），动作行写
/// 「**动作名** · N 组 × M 次 · W kg」。动作名由 [nameOf] 解析（库是调用方
/// 手里那份整库）；查不到时回落到 id——诚实：至少能对上，不编一个名字。
class PlanDraftCard extends StatelessWidget {
  const PlanDraftCard({
    super.key,
    required this.days,
    required this.nameOf,
    this.iconOf,
    this.keyPrefix = 'plan-draft-day',
    this.dense = false,
  });

  final List<AiWorkoutPlanDayDraft> days;

  /// 动作 id → 名称（查不到请回落 id 本身）。
  final String Function(String exerciseId) nameOf;

  /// 动作 id → 图标（2026-10-16 用户：「动作的图标也没有」）。缺省用中性
  /// 力量图标——AI 对话里的计划只有名字，没有库记录可查。
  final IconData Function(String exerciseId)? iconOf;

  /// 每张日卡的 Key 前缀：`<prefix>-<weekday>`。
  final String keyPrefix;

  /// 紧凑档（对话卡里用）：内边距更小、标题更小一档。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in days)
          Padding(
            padding: EdgeInsets.only(
              bottom: dense ? LfDimens.spaceSmall : LfDimens.spaceMedium,
            ),
            child: DesignCard(
              key: Key('$keyPrefix-${day.weekday}'),
              padding: EdgeInsets.all(
                dense ? LfDimens.spaceMedium : LfDimens.spaceLarge,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // 2026-10-16 用户：「标的那个一、二、三什么的就不能变成
                    // 周一之类的吗」——计划卡的日标题用「周一」。
                    workoutWeekdayName(day.weekday),
                    style: (dense ? LfText.title : LfText.headline).copyWith(
                      color: mint.tone(700),
                    ),
                  ),
                  SizedBox(
                    height: dense ? LfDimens.spaceSmall : LfDimens.spaceMedium,
                  ),
                  for (final entry in day.entries)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: LfDimens.spaceMicro,
                      ),
                      child: Text(
                        _entryLine(entry),
                        style: (dense ? LfText.caption : LfText.body).copyWith(
                          color: c.cardForeground,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _entryLine(PlannedExerciseDraft entry) {
    final weight = entry.targetWeightKg;
    final weightText = weight == null ? '' : ' · ${_trim(weight)}kg';
    return '${nameOf(entry.exerciseId)} · ${entry.targetSets} 组 × '
        '${entry.targetReps} 次$weightText';
  }
}

/// 重量显示：整数不拖 `.0`（与训练页其余克数/公斤显示同口径）。
String _trim(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
