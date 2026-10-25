import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/app_haptics.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/presentation/sections/plan_draft_card.dart';

/// 训练计划创建独立页面（docs/21 §4）。
///
/// 将 [TrainingPage] 中的 `_openAiPlanFlow` 提取为独立路由页面，
/// 支持从拍照页、AI 工作台等入口直达，无需先进入训练页。
///
/// 设计：表单 → 披露确认 → 加载 → 预览 → 保存，与原流程一致。
class WorkoutPlanCreatePage extends StatefulWidget {
  const WorkoutPlanCreatePage({
    required this.exerciseRepository,
    required this.workoutPlanRepository,
    required this.workoutPlanProvider,
    required this.loadWorkoutPlanDisclosure,
    this.now,
    super.key,
  });

  final ExerciseRepository exerciseRepository;
  final WorkoutPlanRepository workoutPlanRepository;
  final WorkoutPlanProvider workoutPlanProvider;
  final LoadWorkoutPlanDisclosure loadWorkoutPlanDisclosure;
  final DateTime? now;

  @override
  State<WorkoutPlanCreatePage> createState() => _WorkoutPlanCreatePageState();
}

enum _PlanStage { form, disclosure, loading, preview }

class _WorkoutPlanCreatePageState extends State<WorkoutPlanCreatePage> {
  final _nameController = TextEditingController();
  late final ValueNotifier<int> _days;
  String _goalText = '';
  final _goalController = TextEditingController();
  AiWorkoutPlanDraft? _draft;
  WorkoutPlanDisclosure? _disclosure;
  AppFailure? _failure;
  _PlanStage _stage = _PlanStage.form;
  bool _saving = false;
  bool _inFlight = false;
  List<_ExerciseOption> _options = [];
  final _goalFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _days = ValueNotifier(3);
    _loadOptions();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _goalController.dispose();
    _days.dispose();
    _goalFocus.dispose();
    super.dispose();
  }

  /// 载入**整个动作库**做候选（2026-10-16 用户：「训练计划生成应由 AI
  /// **从动作库中选动作**」）。原先只载 60 条、且请求里只带用户点选的那 1 条
  /// ——AI 根本没得选。库是本地种子（312 条）+ 自建，上限由 domain 的
  /// [AiWorkoutPlanRequest.maxExercises] 把关。
  Future<void> _loadOptions() async {
    try {
      final exercises = await widget.exerciseRepository.search('', limit: null);
      if (!mounted) return;
      setState(() {
        _options = [
          for (final ex in exercises)
            _ExerciseOption(
              id: ex.id,
              name: ex.name,
              equipment: ex.equipment,
              muscleGroup: ex.muscleGroup,
            ),
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e is AppFailure ? e : UnexpectedFailure(e.toString());
        _inFlight = false;
      });
    }
  }

  Future<void> _next() async {
    if (_inFlight) return;
    // 2026-10-23 用户：「先选/填目标关键词，再由 AI 从动作库选动作」——
    // 不再要求先点一个动作；目标仍必填（本地先拦一次，domain 再校验）。
    if (_goalText.trim().isEmpty) {
      _showError('请填写训练目标。');
      return;
    }
    setState(() {
      _inFlight = true;
      _stage = _PlanStage.loading;
      _failure = null;
    });
    try {
      final request = _buildRequest();
      _disclosure = await widget.loadWorkoutPlanDisclosure.call(request);
      if (!mounted) return;
      setState(() {
        _stage = _PlanStage.disclosure;
        _inFlight = false;
      });
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _PlanStage.form;
        _failure = e;
        _inFlight = false;
      });
    }
  }

  Future<void> _generate() async {
    if (_inFlight) return;
    setState(() {
      _inFlight = true;
      _stage = _PlanStage.loading;
      _failure = null;
    });
    try {
      final request = _buildRequest();
      _draft = await widget.workoutPlanProvider.generate(request);
      if (!mounted) return;
      setState(() {
        _stage = _PlanStage.preview;
        _inFlight = false;
      });
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _PlanStage.form;
        _failure = e;
        _inFlight = false;
      });
    }
  }

  AiWorkoutPlanRequest _buildRequest() {
    return AiWorkoutPlanRequest(
      daysPerWeek: _days.value,
      goalText: _goalText,
      // 候选 = **整个动作库**；AI 按目标关键词自己选动作。
      exercises: [
        for (final option in _options)
          ExerciseOption(id: option.id, name: option.name),
      ],
    );
  }

  /// 目标关键词（2026-10-23 用户：「先选/填目标关键词」）。
  ///
  /// 点一下把关键词拼进目标文本（`、` 分隔），再点一下移除——选与填是
  /// 同一个字段，不新增第二套数据源；用户仍可自由输入。
  void _toggleGoalKeyword(String keyword) {
    final current = _goalText
        .split('、')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (current.contains(keyword)) {
      current.remove(keyword);
    } else {
      current.add(keyword);
    }
    final next = current.join('、');
    _goalController.text = next;
    _goalController.selection = TextSelection.collapsed(offset: next.length);
    setState(() => _goalText = next);
  }

  /// 动作 id → 图标（预览用）：取库里那条的器械/肌群；查不到用中性力量图标。
  IconData _exerciseIcon(String exerciseId) {
    for (final option in _options) {
      if (option.id == exerciseId) {
        return workoutExerciseIcon(
          equipment: option.equipment,
          muscleGroup: option.muscleGroup,
        );
      }
    }
    return Icons.fitness_center;
  }

  /// 动作 id → 名称（预览用）。库是本次已载入的整库；查不到就回落 id。
  String _exerciseName(String exerciseId) {
    for (final option in _options) {
      if (option.id == exerciseId) return option.name;
    }
    return exerciseId;
  }

  Future<void> _save() async {
    if (_draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      await widget.workoutPlanRepository.create(
        WorkoutPlanDraft(
          name: _nameController.text.trim().isEmpty
              ? 'AI 生成计划 ${widget.now ?? DateTime.now()}'
              : _nameController.text.trim(),
          days: [
            for (final day in _draft!.days)
              WorkoutPlanDayDraft(weekday: day.weekday, entries: day.entries),
          ],
        ),
        source: 'ai',
      );
      if (!mounted) return;
      AppHaptics.success();
      Navigator.of(context).pop(true);
    } on AppFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _PlanStage.preview;
        _failure = e;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failure = e is AppFailure ? e : UnexpectedFailure(e.toString());
        _saving = false;
      });
    }
  }

  void _showError(String message) {
    // 统一 SnackBar 出口（docs/21 §3.1）：底色/圆角由 `snackBarTheme` 给，
    // 原先手写的 `backgroundColor: error` 是裸 `SnackBar` 的默认方角方盒。
    AppSnackBar.show(context, message, icon: AppSnackBar.errorIcon);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('创建训练计划'),
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_stage) {
      case _PlanStage.form:
        return _FormView(
          nameController: _nameController,
          days: _days,
          goalText: _goalText,
          goalController: _goalController,
          goalFocus: _goalFocus,
          exerciseCount: _options.length,
          failure: _failure,
          onPickGoalKeyword: _toggleGoalKeyword,
          onGoalChanged: (v) => setState(() => _goalText = v),
          onDaysChanged: (v) => _days.value = v,
          onNext: _next,
        );
      case _PlanStage.disclosure:
        return _DisclosureView(
          disclosure: _disclosure!,
          onConfirm: _generate,
          onBack: () => setState(() => _stage = _PlanStage.form),
        );
      case _PlanStage.loading:
        return const Center(child: CircularProgressIndicator());
      case _PlanStage.preview:
        return _PreviewView(
          draft: _draft!,
          nameController: _nameController,
          nameOf: _exerciseName,
          iconOf: _exerciseIcon,
          onSave: _save,
          onRegenerate: _generate,
          onBack: () => setState(() => _stage = _PlanStage.form),
        );
    }
  }
}

// ---- Form view ----

class _FormView extends StatelessWidget {
  const _FormView({
    required this.nameController,
    required this.days,
    required this.goalText,
    required this.goalController,
    required this.goalFocus,
    required this.exerciseCount,
    required this.failure,
    required this.onPickGoalKeyword,
    required this.onGoalChanged,
    required this.onDaysChanged,
    required this.onNext,
  });

  final TextEditingController nameController;
  final ValueNotifier<int> days;
  final String goalText;
  final TextEditingController goalController;
  final FocusNode goalFocus;

  /// 本地动作库条数（「AI 从动作库里选」要说出池子有多大）。
  final int exerciseCount;
  final AppFailure? failure;
  final ValueChanged<String> onPickGoalKeyword;
  final ValueChanged<String> onGoalChanged;
  final VoidCallback onNext;
  final void Function(int) onDaysChanged;

  /// 目标关键词（2026-10-23 用户：「先选/填目标关键词」）。
  static const goalKeywords = ['增肌', '减脂', '力量提升', '塑形', '体能', '康复'];

  bool _keywordSelected(String keyword) =>
      goalText.split('、').map((part) => part.trim()).contains(keyword);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(LfDimens.spaceLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 计划名称
          LfTextField(
            fieldKey: const Key('plan-create-name'),
            label: '计划名称',
            controller: nameController,
            hintText: '例如：胸肌专项训练',
          ),
          const SizedBox(height: LfDimens.spaceLarge),

          // 训练天数
          const AppFieldLabel(label: '训练天数（每天1个动作）'),
          const SizedBox(height: LfDimens.spaceTiny),
          // `RV4-P1-02`：`days` 是 `ValueNotifier`，原来这里**只读 `.value`
          // 没有监听**——点「5天」值变了、界面不重建，胶囊永远停在第 3 天，
          // 而 `_buildRequest()` 读的是新值（界面在骗用户）。
          // 用 `ValueListenableBuilder` 包住整排：值一变这一排就重建。
          ValueListenableBuilder<int>(
            valueListenable: days,
            builder: (context, selectedDays, _) => Row(
              children: [
                // 2026-10-24（R17-a）：取值域 1..7，与
                // `AiWorkoutPlanRequest.maxDays = 7` 对齐（原来只给到 5）。
                for (final d in AiWorkoutPlanRequest.dayOptions)
                  Expanded(
                    // 快捷值一排 = §3.8 B3 小胶囊（原手写 8 圆角块，8 不是本
                    // 设计系统的圆角档；B3 是 full 圆角 + 32 高 + 12 w500）。
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: LfPillButton(
                        key: Key('plan-days-$d'),
                        label: '$d天',
                        selected: selectedDays == d,
                        onPressed: () => onDaysChanged(d),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: LfDimens.spaceLarge),

          // 训练目标
          LfTextField(
            fieldKey: const Key('plan-create-goal'),
            label: '训练目标',
            // 2026-10-16 用户：「根据所填目标（目标不能是可选）」。
            optional: false,
            focusNode: goalFocus,
            controller: goalController,
            onChanged: onGoalChanged,
            hintText: '例如：增肌、减脂、力量提升（点下面的关键词快速填）',
            maxLines: 2,
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          // 目标关键词（2026-10-23 用户：「先选/填目标关键词」）。
          SizedBox(
            width: double.infinity,
            child: Wrap(
              spacing: LfDimens.spaceSmall,
              runSpacing: LfDimens.spaceSmall,
              children: [
                for (final keyword in goalKeywords)
                  LfPillButton(
                    key: Key('plan-goal-keyword-$keyword'),
                    label: keyword,
                    selected: _keywordSelected(keyword),
                    onPressed: () => onPickGoalKeyword(keyword),
                  ),
              ],
            ),
          ),
          const SizedBox(height: LfDimens.spaceLarge),
          // 动作由 AI 从整库选（不再要求用户先点一条）。
          Text(
            'AI 会从本地动作库（$exerciseCount 个动作）里按目标选动作并排成计划。',
            key: const Key('plan-create-exercise-hint'),
            style: LfText.caption.copyWith(color: context.lf.mutedForeground),
          ),
          if (failure != null) ...[
            const SizedBox(height: LfDimens.spaceLarge),
            AppErrorText(failure!.message),
          ],
          const SizedBox(height: LfDimens.spaceLargePlus),
          // 页面内主行动 = §3.8 B1（弹层/固定底栏的确认才是 B2）。
          LfPrimaryButton(
            key: const Key('plan-create-next'),
            label: '下一步：查看披露',
            expand: true,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

// ---- Disclosure view ----

class _DisclosureView extends StatelessWidget {
  const _DisclosureView({
    required this.disclosure,
    required this.onConfirm,
    required this.onBack,
  });

  final WorkoutPlanDisclosure disclosure;
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final request = disclosure.request;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(LfDimens.spaceLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('即将发送以下请求到 AI 服务：', style: LfText.label),
          const SizedBox(height: LfDimens.spaceMedium),
          // 披露块收归 §3.1 的 DesignCard（原手写「card 底 + 1px border +
          // 8 圆角」盒）。
          DesignCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('目标天数：${request.daysPerWeek} 天', style: LfText.body),
                if (request.goalText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('训练目标：${request.goalText}', style: LfText.body),
                ],
                const SizedBox(height: 4),
                Text(
                  '候选动作：全部 ${request.exercises.length} 个本地动作',
                  key: const Key('plan-create-disclosure-exercises'),
                  style: LfText.body,
                ),
                const SizedBox(height: LfDimens.spaceMedium),
                Text('目标模型：${disclosure.model}', style: LfText.bodySmall),
                Text(
                  '端点：${disclosure.destinationHost}',
                  style: LfText.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: LfDimens.spaceLargePlus),
          Row(
            children: [
              Expanded(
                // 弹层行动档（§3.8）：次级返回 = B6，确认生成 = B2。
                child: LfTextButton(onPressed: onBack, label: '返回'),
              ),
              const SizedBox(width: LfDimens.spaceMedium),
              Expanded(
                child: LfConfirmButton(
                  key: const Key('plan-create-generate'),
                  label: '确认生成',
                  onPressed: onConfirm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Preview view ----

class _PreviewView extends StatelessWidget {
  const _PreviewView({
    required this.draft,
    required this.nameController,
    required this.nameOf,
    required this.iconOf,
    required this.onSave,
    required this.onRegenerate,
    required this.onBack,
  });

  final AiWorkoutPlanDraft draft;
  final TextEditingController nameController;

  /// 动作 id → 名称（共享 `PlanDraftCard` 用）。
  final String Function(String exerciseId) nameOf;

  /// 动作 id → 图标（同上；创建页手里有整库，所以能查器械/肌群）。
  final IconData Function(String exerciseId) iconOf;
  final VoidCallback onSave;
  final VoidCallback onRegenerate;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(LfDimens.spaceLarge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行 + 「AI 草案」徽标：2026-10-16 用户要求删掉整段警告，
          // 草案身份改由这枚徽标承担（事实不丢、字少）。
          Row(
            children: [
              const Expanded(child: Text('AI 生成的训练计划草案：', style: LfText.label)),
              LfBadge.outlinedBrand('AI 草案'),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: '输入计划名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: LfDimens.spaceLarge),
          // 草案日卡 = 共享 `PlanDraftCard`（与训练弹层、AI 对话里的同款；
          // 2026-10-16 用户：「卡片式，并能复用在 AI 对话里」）。
          PlanDraftCard(days: draft.days, nameOf: nameOf, iconOf: iconOf),
          const SizedBox(height: LfDimens.spaceLargePlus),
          Row(
            children: [
              Expanded(
                child: LfTextButton(onPressed: onBack, label: '返回修改'),
              ),
              const SizedBox(width: LfDimens.spaceMedium),
              Expanded(
                child: LfPillButton(
                  label: '重新生成',
                  tone: LfPillTone.muted,
                  onPressed: onRegenerate,
                ),
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          SizedBox(
            width: double.infinity,
            child: LfConfirmButton(
              key: const Key('plan-create-save'),
              label: '保存到本地',
              onPressed: onSave,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Helpers ----

class _ExerciseOption {
  const _ExerciseOption({
    required this.id,
    required this.name,
    this.equipment,
    this.muscleGroup,
  });

  final String id;
  final String name;

  /// 器械/肌群：只用于预览行的动作图标（2026-10-16）。
  final Equipment? equipment;
  final MuscleGroup? muscleGroup;
}
