import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';

/// 一次「往训练日里加一个动作」的输入结果（docs/30 §2 D7）。
///
/// 从既有 `TrainingPage._openEntryDialog` 提炼出来：**同一份数据在两处输入**
/// （训练页计划详情的「添加动作」、新建手动计划页的「添加动作」），校验与提示
/// 必须同源——抄一份出来的结果是「两处迟早漂」，而漂了之后用户看到的是
/// 同一件事在两张页面上说法不同。
final class PlannedEntryInput {
  const PlannedEntryInput({required this.weekday, required this.entry});

  final int weekday;
  final PlannedExerciseDraft entry;
}

/// 「添加动作」表单弹层（docs/30 §2 D7：字段与训练页详情**逐一对齐**）。
///
/// 字段 Key 与既有弹层完全一致：`training-entry-weekday` / `-exercise` /
/// `-sets` / `-reps` / `-weight`，保存 `training-entry-save`。**不新造一套
/// 字段名**——测试与用户看到的都是同一套。
///
/// [initialWeekday]：手动计划页从某一天的「添加动作」进去时把该天设为默认，
/// 不强迫用户再选一次；为 null 时默认周一。
/// [weekdayEditable]：**手动计划页把它设为 false**——那一页的每个「添加动作」
/// 按钮本来就长在某一天下面，让用户在这里换天等于给「点错了天」开一条静默
/// 改错的路（换完数字进的是另一天，页面上没有任何痕迹）。
/// [onSubmit]：**需要「保存失败不关窗」的调用方传它**。返回 `null` = 成功
/// （弹层关闭）；返回字符串 = 这条错误留在弹层里显示，用户填的内容不丢。
/// 不传则校验通过即返回值给调用方（手动页把动作先收进内存草稿，落库在整单
/// 保存时做，弹层里没有可失败的事）。
Future<PlannedEntryInput?> showPlannedEntrySheet(
  BuildContext context, {
  required List<ExerciseRecord> options,
  int? initialWeekday,
  bool weekdayEditable = true,
  Future<String?> Function(PlannedEntryInput input)? onSubmit,
}) {
  var weekday = initialWeekday ?? 1;
  String? exerciseId;
  var sets = '';
  var reps = '';
  var weight = '';
  String? errorText;
  var saving = false;

  return AppSheet.showStateful<PlannedEntryInput>(
    context,
    title: '添加动作',
    bodyBuilder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) {
        exerciseId ??= options.isEmpty ? null : options.first.id;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppFieldLabel(label: '训练日'),
            const SizedBox(height: LfDimens.spaceTiny),
            if (weekdayEditable)
              LfSelectField<int>(
                fieldKey: const Key('training-entry-weekday'),
                label: '训练日',
                value: weekday,
                options: [for (var value = 1; value <= 7; value++) value],
                optionLabel: (value) => '周${workoutWeekdayLabel(value)}',
                onChanged: (value) => setSheetState(() => weekday = value),
              )
            else
              // 锁定态仍渲染**同一个 Key 的 Text**：断言与读屏都还能拿到
              // 「这一条是几号训练日」这个事实，只是没有下拉。
              Text(
                '周${workoutWeekdayLabel(weekday)}',
                key: const Key('training-entry-weekday'),
                style: Theme.of(sheetContext).textTheme.bodyLarge,
              ),
            const AppFieldLabel(label: '动作'),
            const SizedBox(height: LfDimens.spaceTiny),
            LfSelectField<String>(
              fieldKey: const Key('training-entry-exercise'),
              label: '动作',
              value: exerciseId,
              options: [for (final option in options) option.id],
              optionLabel: (id) =>
                  options.firstWhere((option) => option.id == id).name,
              onChanged: (value) => setSheetState(() => exerciseId = value),
            ),
            AppNumberField(
              fieldKey: const Key('training-entry-sets'),
              label: '目标组数',
              unit: '组',
              integerOnly: true,
              onChanged: (value) => sets = value,
            ),
            const SizedBox(height: 8),
            AppNumberField(
              fieldKey: const Key('training-entry-reps'),
              label: '目标次数',
              unit: '次',
              integerOnly: true,
              onChanged: (value) => reps = value,
            ),
            const SizedBox(height: 8),
            // 目标重量可选：自重动作（俯卧撑、引体）没有重量，留空写 null，
            // 列表行里就不显示「· 60kg」那一段。
            AppNumberField(
              fieldKey: const Key('training-entry-weight'),
              label: '目标重量',
              unit: 'kg',
              optional: true,
              onChanged: (value) => weight = value,
            ),
            if (errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  errorText!,
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                LfTextButton(
                  label: '取消',
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
                LfConfirmButton(
                  key: const Key('training-entry-save'),
                  label: '保存',
                  expand: false,
                  busy: saving,
                  onPressed: () async {
                    if (saving) return;
                    final parsedSets = int.tryParse(sets.trim());
                    final parsedReps = int.tryParse(reps.trim());
                    final parsedWeight = double.tryParse(weight.trim());
                    if (exerciseId == null ||
                        parsedSets == null ||
                        parsedReps == null) {
                      setSheetState(() => errorText = '请选择动作并填写正整数组次。');
                      return;
                    }
                    final input = PlannedEntryInput(
                      weekday: weekday,
                      entry: PlannedExerciseDraft(
                        exerciseId: exerciseId!,
                        targetSets: parsedSets,
                        targetReps: parsedReps,
                        targetWeightKg: parsedWeight,
                      ),
                    );
                    if (onSubmit == null) {
                      // 校验只做「能不能构成一条记录」，落库交给调用方：
                      // 手动页走内存草稿，整单保存时才落库。
                      Navigator.of(sheetContext).pop(input);
                      return;
                    }
                    setSheetState(() => saving = true);
                    final failure = await onSubmit(input);
                    if (!sheetContext.mounted) return;
                    if (failure != null) {
                      // 【不关窗】保存失败时错误留在弹层内，用户填的内容不丢。
                      // 弹层挂在根导航器上盖住整页，先 pop 再报错的页面级
                      // snackbar 物理上看不见（AppSheet.showSubmitForm 的既有
                      // 口径）。
                      setSheetState(() {
                        saving = false;
                        errorText = failure;
                      });
                      return;
                    }
                    Navigator.of(sheetContext).pop(input);
                  },
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
