import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/app_haptics.dart';
import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/presentation/sections/planned_entry_sheet.dart';

/// 手动创建训练计划（docs/30 §2 D7 / 需求 7，2026-10-08）。
///
/// **独立页，不是 AI 页的一个 mode**：两者的表单、阶段机（表单/披露/生成/
/// 预览）与依赖完全不同，塞进一页会让「AI 页」变成两种页面的拼盘。共用的
/// 是**数据契约**：[WorkoutPlanDraft] + [PlannedExerciseDraft] +
/// `create(source: 'manual')`。
///
/// **不依赖 AI 四项依赖**（只要 [ExerciseRepository] + [WorkoutPlanRepository]）
/// ⇒ AI 没配置的用户第一次就能建出**有内容的**计划。
///
/// **为什么不像以前那样「先建空计划再补」**：那会让用户在「新建 → 详情 →
/// 添加动作 → 返回」之间来回跳，而且中途退出就留下一个空计划。这一页把整条
/// 动线收进一屏：**没内容就存不下来**。
class WorkoutPlanManualPage extends StatefulWidget {
  const WorkoutPlanManualPage({
    required this.exerciseRepository,
    required this.workoutPlanRepository,
    this.onCreated,
    super.key,
  });

  final ExerciseRepository exerciseRepository;
  final WorkoutPlanRepository workoutPlanRepository;

  /// 保存成功后的回调（路由层据此返回上一页）。
  final VoidCallback? onCreated;

  @override
  State<WorkoutPlanManualPage> createState() => _WorkoutPlanManualPageState();
}

class _WorkoutPlanManualPageState extends State<WorkoutPlanManualPage> {
  final _nameController = TextEditingController();

  /// 已选训练日（周一到周日任选，可空）。
  final Set<int> _weekdays = <int>{};

  /// 每个训练日已加的动作（按添加顺序）。
  ///
  /// 每条带**显示名**：`PlannedExerciseDraft` 按契约只有 `exerciseId`（它是
  /// 落库形状，AI 路径回来的草稿也没有名字），而草稿列表要让用户认得出是哪
  /// 条动作。名字只活在页面状态里，保存后由仓储按 id 关联——**同一份数据不
  /// 在两处存**。
  ///
  /// 键集**不等于** [_weekdays]：勾了天但还没加动作时这里没有这一项
  /// （`build` 里按 `_entries[weekday] ?? const []` 取）。
  final Map<int, List<_DraftEntry>> _entries = {};

  /// 动作下拉的候选（一次拉够，弹层内不再查库）。
  List<ExerciseRecord> _options = const [];
  bool _loadingOptions = true;

  String? _errorText;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final exercises = await widget.exerciseRepository.search('', limit: null);
      if (!mounted) return;
      setState(() {
        _options = exercises;
        _loadingOptions = false;
      });
    } catch (_) {
      if (!mounted) return;
      // 候选拉不到时页面照常可用，只是「添加动作」会如实说没有可选动作——
      // 不把整页打死（用户还能改名、选训练日，修好后再来）。
      setState(() => _loadingOptions = false);
    }
  }

  /// 总动作数（保存校验与副标题都用它）。
  int get _entryCount =>
      _entries.values.fold(0, (sum, list) => sum + list.length);

  bool get _canSave =>
      !_saving && _nameController.text.trim().isNotEmpty && _entryCount > 0;

  Future<void> _addEntry(int weekday) async {
    if (_loadingOptions) {
      // 「还在读」与「读到了但库是空的」是两件事，说成同一句就是撒谎。
      AppSnackBar.show(context, '正在读取动作库，请稍后再试。', icon: AppSnackBar.errorIcon);
      return;
    }
    if (_options.isEmpty) {
      AppSnackBar.show(
        context,
        '动作库是空的，先确认随包动作库已导入。',
        icon: AppSnackBar.errorIcon,
      );
      return;
    }
    final input = await showPlannedEntrySheet(
      context,
      options: _options,
      initialWeekday: weekday,
      // 从某一天的按钮进去时锁定该天：换天在这里等于给「点错了天」开一条
      // 静默改错的路（数字进的是另一天，页面上没有痕迹）。
      weekdayEditable: false,
    );
    if (input == null || !mounted) return;
    final name = _options
        .firstWhere((option) => option.id == input.entry.exerciseId)
        .name;
    setState(() {
      _entries
          .putIfAbsent(input.weekday, () => [])
          .add(_DraftEntry(entry: input.entry, name: name));
      _errorText = null;
    });
  }

  void _removeEntry(int weekday, int index) {
    setState(() {
      final list = _entries[weekday];
      if (list == null) return;
      list.removeAt(index);
      if (list.isEmpty) _entries.remove(weekday);
    });
  }

  void _toggleWeekday(int weekday) {
    setState(() {
      if (_weekdays.contains(weekday)) {
        _weekdays.remove(weekday);
        // 取消勾选时该天已排的动作一并撤掉：留着一个「未选中但仍有动作」的
        // 天，保存时到底存不存它就没有答案了。
        _entries.remove(weekday);
      } else {
        _weekdays.add(weekday);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '请填写计划名称。');
      return;
    }
    if (_entryCount == 0) {
      // 以前这里是「静默建一个空计划」；现在如实说清并要求先加动作。
      setState(() => _errorText = '至少添加一个动作才能保存。');
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      final weekdays = _entries.keys.toList()..sort();
      await widget.workoutPlanRepository.create(
        WorkoutPlanDraft(
          name: name,
          days: [
            for (final weekday in weekdays)
              WorkoutPlanDayDraft(
                weekday: weekday,
                entries: List.unmodifiable([
                  for (final item in _entries[weekday]!) item.entry,
                ]),
              ),
          ],
        ),
        source: 'manual',
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = error.message;
      });
      return;
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = error.message;
      });
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = error is AppFailure ? error.message : '保存失败，请重试。';
      });
      return;
    }
    if (!mounted) return;
    AppHaptics.success();
    AppSnackBar.show(context, '已保存「$name」。', icon: AppSnackBar.successIcon);
    widget.onCreated?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Scaffold(
      appBar: LfTopBar(title: '手动创建计划'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          LfDimens.pagePadding,
          LfDimens.spaceLarge,
          LfDimens.pagePadding,
          LfDimens.spaceLarge + LfInsets.bottom(context),
        ),
        children: [
          LfTextField(
            fieldKey: const Key('manual-plan-name'),
            label: '计划名称',
            controller: _nameController,
            onChanged: (_) => setState(() => _errorText = null),
          ),
          const SizedBox(height: LfDimens.spaceLarge),
          Text(
            '训练日（周一..周日任选）',
            style: LfText.label.copyWith(color: c.mutedForeground),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          _WeekdayChips(selected: _weekdays, onToggle: _toggleWeekday),
          const SizedBox(height: LfDimens.spaceLarge),
          if (_weekdays.isEmpty)
            // 空态如实说明下一步，而不是留一片空白让用户猜。
            Padding(
              padding: const EdgeInsets.only(bottom: LfDimens.spaceMedium),
              child: Text(
                '先选训练日，再给每天添加动作。',
                key: const Key('manual-plan-empty-hint'),
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            ),
          // **每个已选训练日各有一块**（含空块）：只给「已有动作」的天渲染，
          // 用户勾了新的一天后就找不到地方加动作了——设计稿第 ③ 帧里周三
          // 正是「还没有动作 + 自己的添加按钮」。按 `_weekdays` 迭代而不是按
          // `_entries.keys`，两个集合的差集（勾了但还没动作的天）才不会漏。
          for (final weekday in _weekdays.toList()..sort())
            _DayBlock(
              weekday: weekday,
              entries: _entries[weekday] ?? const [],
              onRemove: (index) => _removeEntry(weekday, index),
              onAdd: () => _addEntry(weekday),
            ),
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: LfDimens.spaceMedium),
              child: AppErrorText(
                _errorText!,
                key: const Key('manual-plan-error'),
              ),
            ),
          const SizedBox(height: LfDimens.spaceLargePlus),
          Row(
            children: [
              Expanded(
                child: LfTextButton(
                  label: '取消',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(width: LfDimens.spaceMedium),
              Expanded(
                flex: 2,
                child: LfConfirmButton(
                  key: const Key('manual-plan-save'),
                  label: '保存计划',
                  // 「没内容就存不下来」：按钮禁用态由真实内容推导，
                  // 而不是等用户点了再报错。
                  onPressed: _canSave ? _save : null,
                  busy: _saving,
                ),
              ),
            ],
          ),
          if (!_canSave && !_saving)
            Padding(
              padding: const EdgeInsets.only(top: LfDimens.spaceSmall),
              child: Text(
                _nameController.text.trim().isEmpty
                    ? '填写名称并添加至少一个动作后可保存。'
                    : '至少添加一个动作才能保存。',
                key: const Key('manual-plan-save-hint'),
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            ),
        ],
      ),
    );
  }
}

/// 训练日 chips（周一到周日，可多选）。
class _WeekdayChips extends StatelessWidget {
  const _WeekdayChips({required this.selected, required this.onToggle});

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final mint = LfColors.mint(brightness);
    return Wrap(
      spacing: LfDimens.spaceSmall,
      runSpacing: LfDimens.spaceSmall,
      children: [
        for (var weekday = 1; weekday <= 7; weekday++)
          Builder(
            builder: (context) {
              final isSelected = selected.contains(weekday);
              return Semantics(
                label: '周${workoutWeekdayLabel(weekday)}',
                selected: isSelected,
                child: InkWell(
                  key: Key('manual-plan-weekday-$weekday'),
                  borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                  onTap: () => onToggle(weekday),
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? mint.tone(100) : c.muted,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      workoutWeekdayLabel(weekday),
                      style: LfText.bodyStrong.copyWith(
                        color: isSelected
                            ? LfColors.mintText(brightness)
                            : c.mutedForeground,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// 一个训练日的动作块：日标题 + 动作行 + 「添加动作」。
class _DayBlock extends StatelessWidget {
  const _DayBlock({
    required this.weekday,
    required this.entries,
    required this.onRemove,
    required this.onAdd,
  });

  final int weekday;
  final List<_DraftEntry> entries;
  final ValueChanged<int> onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.only(bottom: LfDimens.spaceLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '周${workoutWeekdayLabel(weekday)}',
            key: Key('manual-plan-day-$weekday'),
            style: LfText.bodyStrong.copyWith(color: c.cardForeground),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: LfDimens.spaceSmall),
              child: Text(
                '还没有动作——点「添加动作」开始',
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            )
          else
            DesignCard(
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) Divider(height: 1, color: c.border),
                    _EntryRow(
                      item: entries[i],
                      // 逐条移除，`manual-plan-entry-remove-<weekday>-<i>`。
                      removeKey: Key('manual-plan-entry-remove-$weekday-$i'),
                      onRemove: () => onRemove(i),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: LfDimens.spaceSmall),
          LfDashedButton(
            key: Key('manual-plan-day-add-$weekday'),
            label: '添加动作',
            icon: Icons.add,
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

/// 草稿里的一条动作行（与计划详情里的行同形：名称 + 组次×重量 + 移除）。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.item,
    required this.removeKey,
    required this.onRemove,
  });

  final _DraftEntry item;
  final Key removeKey;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceLarge,
        vertical: LfDimens.spaceMedium,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.name,
              style: LfText.body.copyWith(color: c.cardForeground),
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          Text(
            '${item.entry.targetSets} 组 × ${item.entry.targetReps} 次'
            '${item.entry.targetWeightKg == null ? '' : ' · ${_weightText(item.entry.targetWeightKg!)}kg'}',
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
          // 与计划详情里的移除钮同件（§3.8 B4）：features 内不新写裸
          // `IconButton`（`unified_card_button_audit_test.dart` 的预算表就是
          // 拦这个的），而且裸件的 48 方框会把这一行撑高。
          LfCircleIconButton(
            key: removeKey,
            icon: Icons.close,
            iconSize: LfDimens.iconMd,
            tooltip: '移除动作',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  static String _weightText(double weight) =>
      weight == weight.roundToDouble() ? weight.toStringAsFixed(0) : '$weight';
}

/// 手动页草稿里的一条动作：落库形状 + 仅用于显示的 [name]。
final class _DraftEntry {
  const _DraftEntry({required this.entry, required this.name});

  final PlannedExerciseDraft entry;
  final String name;
}
