import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/goal_big_card.dart';
import 'package:localfit_ai/app/design/widgets/user_avatar.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/fixed_bottom_primary_action.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show formatLocalDate;
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/application/pick_and_store_avatar.dart';
import 'package:localfit_ai/features/settings/data/pick_avatar.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';

/// 我的-编辑个人资料页（2.0-6f；docs/29 §P1 扩为「训练目标 + 身体指标」）。
///
/// 本页由「我的」页身份卡的 `cta-edit-profile` **push** 进来（docs/29 §P1 / D2），
/// 退出只有 `onClose` 一条出口：AppBar 右侧关闭钮，以及保存成功后。
///
/// 2026-10-13（docs/32 §3 D11 / §4 T9 需求 64/72）：新增「每日目标」分组——
/// 步数目标（`AppSettings.steps_daily_goal`）与水分目标（`DailyTargets` 的
/// 版本化写入）。两行都**只在对应依赖注入时渲染**（未接线就整行不出现，
/// 与设置页未接线的动作行同一口径）。
class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({
    super.key,
    required this.repository,
    required this.currentGoal,
    required this.onClose,
    this.now,
    this.stepsRepository,
    this.updateWaterTargetMl,
    this.pickAvatar,
  });

  final ProfileIdentityRepository repository;
  final HealthGoal? currentGoal;
  final VoidCallback onClose;

  /// 计算「年龄 → 出生年」用的当前时间；测试注入固定值，生产走 `DateTime.now()`。
  final DateTime? now;

  /// 步数目标读写（docs/32 §3 D11）。null ＝ 不渲染「步数目标」行。
  final StepsRepository? stepsRepository;

  /// 水分目标写入（docs/32 §3 D11）。null ＝ 不渲染「水分目标」行。
  final UpdateWaterTargetMl? updateWaterTargetMl;

  /// 选头像（2026-10-16，S6：头像与昵称统一在本页改）。null ＝ 头像不可点。
  final PickAvatar? pickAvatar;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();

  /// 身份事实（昵称 / 头像路径）——2026-10-16（S6）起**本页**是改它们的地方
  /// （原先在设置页身份卡上就地改）。
  IdentityProfile? _identity;

  final _targetWeightController = TextEditingController();
  final _heightController = TextEditingController();
  final _ageController = TextEditingController();
  final _stepsGoalController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _waterTargetController = TextEditingController();

  late HealthGoal _selectedGoal;

  /// 未填写 / 无法识别时为 null（界面不预选、保存时原样写回 null），
  /// **不拿 `female` 当缺省冒充用户事实**。
  BiologicalSex? _sex;
  bool _isLoading = false;

  /// 载入时的步数目标 / 水分目标（ml）。保存时**只在真的改了才写**：
  /// 水分目标每次写都会在 `DailyTargets` 里落一条新版本行（D11 的版本化
  /// 语义），「没改也写」等于每点一次保存就多一条无意义的版本。
  int? _loadedStepGoal;
  double? _loadedWaterTargetMl;

  DateTime get _now => widget.now ?? DateTime.now();

  String get _today => formatLocalDate(_now);

  @override
  void initState() {
    super.initState();
    _selectedGoal = widget.currentGoal ?? HealthGoal.maintain;
    _loadCurrentProfile();
    _loadIdentity();
    _loadDailyGoals();
  }

  @override
  void dispose() {
    _targetWeightController.dispose();
    _heightController.dispose();
    _ageController.dispose();
    _stepsGoalController.dispose();
    _displayNameController.dispose();
    _waterTargetController.dispose();
    super.dispose();
  }

  /// 回填已建档的当前档案（目标 + 目标体重 + 身体指标，docs/29 §P1）。
  ///
  /// **必须回填目标与目标体重**：页面默认「维持」、目标体重留空，若不回填，
  /// 保存时 `updateGoal` 会把用户的真实目标与目标体重静默覆盖成「维持 / 无」。
  /// 未建档时各项保持默认/空白，不做任何伪造。
  Future<void> _loadCurrentProfile() async {
    final body = await widget.repository.loadBodyProfile();
    final goal = await widget.repository.loadGoalProfile();
    if (!mounted) return;
    setState(() {
      // `?goal=` 显式传入时以传入值为准，否则用库里的当前目标回填。
      if (goal != null) {
        if (widget.currentGoal == null) _selectedGoal = goal.goal;
        final targetWeight = goal.targetWeightKg;
        if (targetWeight != null) {
          _targetWeightController.text = _formatNumber(targetWeight);
        }
      }
      if (body != null) {
        if (body.heightCm != null) {
          _heightController.text = _formatNumber(body.heightCm!);
        }
        if (body.birthYear != null) {
          final age = _now.year - body.birthYear!;
          if (age >= 0) _ageController.text = '$age';
        }
        _sex = _parseSex(body.biologicalSex);
      }
    });
  }

  /// 回填「每日目标」两行（docs/32 §4 T9）。缺键/没有生效行时留空——
  /// 空框在保存时**不写任何东西**（这两个字段无「null」语义，见 `_save`）。
  Future<void> _loadDailyGoals() async {
    final stepsRepository = widget.stepsRepository;
    final waterTarget = widget.updateWaterTargetMl;
    final goal = stepsRepository == null
        ? null
        : await stepsRepository.readDailyGoal();
    final waterMl = waterTarget == null
        ? null
        : await waterTarget.readCurrentMl(_today);
    if (!mounted) return;
    setState(() {
      if (goal != null) {
        _loadedStepGoal = goal;
        _stepsGoalController.text = '$goal';
      }
      if (waterMl != null) {
        _loadedWaterTargetMl = waterMl;
        _waterTargetController.text = _formatLiters(waterMl);
      }
    });
  }

  /// 回填身份（昵称）。头像由 `UserAvatar` 直接读库值（路径字符串）。
  Future<void> _loadIdentity() async {
    final identity = await widget.repository.loadIdentity();
    if (!mounted) return;
    setState(() {
      _identity = identity;
      final name = identity?.displayName;
      if (name != null && name.isNotEmpty) {
        _displayNameController.text = name;
      }
    });
  }

  /// 换头像（2026-10-16：入口从设置页身份卡迁到本页；即选即存，与 D9 一致）。
  Future<void> _pickAvatar() async {
    final picker = widget.pickAvatar;
    if (picker == null) return;
    final result = await pickAndStoreAvatar(
      repository: widget.repository,
      picker: picker,
      oldPath: _identity?.avatarPath,
    );
    if (!mounted) return;
    switch (result.status) {
      case AvatarUpdateStatus.updated:
        await _loadIdentity();
        if (mounted) {
          AppSnackBar.show(context, '头像已更新', icon: AppSnackBar.successIcon);
        }
      case AvatarUpdateStatus.cancelled:
        break;
      case AvatarUpdateStatus.failed:
        AppSnackBar.show(
          context,
          result.message ?? '头像更新失败，请重试。',
          icon: AppSnackBar.errorIcon,
        );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final targetWeight = double.tryParse(_targetWeightController.text);
    final height = double.tryParse(_heightController.text);
    final age = int.tryParse(_ageController.text);
    final stepGoal = int.tryParse(_stepsGoalController.text.trim());
    final waterLiters = double.tryParse(_waterTargetController.text.trim());
    // 二次确认弹窗（2.0-6f）
    final confirmed =
        await AppSheet.show<bool>(
          context,
          title: '确认更新个人资料？',
          content: Text(
            '目标模式：${_goalLabel(_selectedGoal)}'
            '${targetWeight != null ? ' · 目标体重 ${targetWeight.round()}kg' : ''}'
            '${height != null ? ' · 身高 ${_formatNumber(height)}cm' : ''}'
            '${stepGoal != null ? ' · 步数目标 $stepGoal步' : ''}'
            '${waterLiters != null ? ' · 水分目标 ${_formatLiters(waterLiters * 1000)}L' : ''}',
          ),
          // 行动档（§3.4/§3.8）：次级取消 = B6、终端确认 = B2
          // （`expand: false` ——B2 默认撑满，在 Row 里会请求无限宽）。
          //
          // 必须用弹层内 context 弹：`AppSheet` 走根导航器，而本页挂在
          // shell 分支导航器上；用页面 context `pop` 会把编辑页弹掉、
          // 弹层还留着（与食堂删除确认同一个坑，2026-10-23）。
          actions: Builder(
            builder: (sheetContext) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                LfTextButton(
                  label: '取消',
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                ),
                LfConfirmButton(
                  expand: false,
                  label: '确认',
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _isLoading = true);
    try {
      await widget.repository.updateGoal(
        goal: _selectedGoal,
        targetWeightKg: targetWeight,
      );
      // 昵称：有值就写，空值 = 清除（与设置页原来的语义一致，不假装写入）。
      final displayName = _displayNameController.text.trim();
      if (displayName.isEmpty) {
        await widget.repository.clearDisplayName();
      } else {
        await widget.repository.updateDisplayName(displayName);
      }
      await widget.repository.updateBodyProfile(
        heightCm: height,
        // 年龄按「当前年 − 出生年」的逆运算落库，与 `complete_onboarding.dart`
        // 建档时的口径一致；没填年龄就写回 null，不保留旧值也不伪造。
        birthYear: age == null ? null : _now.year - age,
        biologicalSex: _sex?.name,
      );
      // 每日目标：**只在值真的存在且与载入值不同时**才写。
      // 空框 = 保持库里原值（这两个字段没有「null」语义：步数目标未设置
      // 时是默认 10000，水分目标是 NOT NULL 的列——写不了 null 就不假装写）。
      final stepsRepository = widget.stepsRepository;
      if (stepsRepository != null &&
          stepGoal != null &&
          stepGoal != _loadedStepGoal) {
        await stepsRepository.updateDailyGoal(stepGoal);
        _loadedStepGoal = stepGoal;
      }
      final waterTarget = widget.updateWaterTargetMl;
      final waterMl = waterLiters == null ? null : waterLiters * 1000;
      if (waterTarget != null &&
          waterMl != null &&
          waterMl != _loadedWaterTargetMl) {
        await waterTarget.run(targetMl: waterMl, today: _today);
        _loadedWaterTargetMl = waterMl;
      }
      if (mounted) {
        AppSnackBar.show(context, '个人资料已更新', icon: AppSnackBar.successIcon);
      }
      // 唯一出口（docs/29 §P1 / D2）：不再叠一次裸 `Navigator.pop`——`push`
      // 进来时那次 pop 正是 `GoError: There is nothing to pop` 的另一半来源。
      widget.onClose();
    } catch (e) {
      if (mounted) {
        AppSnackBar.show(context, '更新失败：$e', icon: AppSnackBar.errorIcon);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 三张大卡的顺序：与引导页逐格一致（减脂 / 增肌 / 维持）。
  static const _goalCardOrder = [
    HealthGoal.loseFat,
    HealthGoal.gainMuscle,
    HealthGoal.maintain,
  ];

  /// 与引导页同一套图标（同一件事在两页长一个样）。
  IconData _goalIcon(HealthGoal goal) => switch (goal) {
    HealthGoal.loseFat => Icons.local_fire_department_outlined,
    HealthGoal.gainMuscle => Icons.fitness_center_outlined,
    HealthGoal.maintain => Icons.eco_outlined,
  };

  String _goalLabel(HealthGoal goal) {
    return switch (goal) {
      HealthGoal.loseFat => '减脂',
      HealthGoal.maintain => '维持',
      HealthGoal.gainMuscle => '增肌',
    };
  }

  BiologicalSex? _parseSex(String? raw) {
    if (raw == null) return null;
    for (final sex in BiologicalSex.values) {
      if (sex.name == raw) return sex;
    }
    return null;
  }

  /// 整数就不显示小数尾巴（戳 170.0 的出生数据不该在输入框里写成「170.0」）。
  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return '${value.round()}';
    return '$value';
  }

  /// ml → L 的显示串：2000 mg ⇒ `2`、2500 ⇒ `2.5`、1250 ⇒ `1.25`
  /// （最多两位小数、去掉尾零；用户填的就是这些位数里的值）。
  String _formatLiters(double ml) {
    final liters = ml / 1000;
    var text = liters.toStringAsFixed(2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text;
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: LfText.title.copyWith(color: context.lf.cardForeground),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑个人资料'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: LfCircleIconButton(
              key: const Key('profile-edit-close'),
              icon: Icons.close,
              tooltip: '关闭',
              onPressed: widget.onClose,
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 章节标题走设计系统的字阶与色（原来只给了字号 ⇒ 落到 `TextTheme`
            // 默认的纯黑，暗色主题下是纯白）。
            // ── 身份（2026-10-16，S6）───────────────────────────────
            // 用户要求「头像和昵称应统一在『编辑资料』界面里更改」：本页现在
            // 是**唯一**改它们的地方（设置页身份卡只展示 + 一个进本页的入口）。
            _sectionTitle('头像与昵称'),
            const SizedBox(height: 8),
            Row(
              children: [
                Semantics(
                  button: widget.pickAvatar != null,
                  label: widget.pickAvatar == null ? '用户头像' : '更换头像',
                  child: GestureDetector(
                    key: const Key('profile-avatar'),
                    onTap: widget.pickAvatar == null ? null : _pickAvatar,
                    child: UserAvatar(
                      displayName: _displayNameController.text,
                      avatarPath: _identity?.avatarPath,
                      size: 56,
                      imageKey: const Key('profile-avatar-image'),
                      initialKey: const Key('profile-avatar-initial'),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: LfTextField(
                    fieldKey: const Key('profile-display-name'),
                    label: '昵称',
                    optional: true,
                    controller: _displayNameController,
                    maxLength: 20,
                    hintText: '留空则用默认称呼',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionTitle('训练目标'),
            const SizedBox(height: 8),
            // 2026-10-16 用户：「编辑资料里的训练目标做成引导页那种形式」
            // ——三行 `RadioListTile` 换成**引导页同款的三张大卡**
            // （公共件 `GoalBigCard`，引导页与这里共用同一件）。
            Row(
              children: [
                for (final goal in _goalCardOrder)
                  GoalBigCard(
                    key: Key('profile-goal-${goal.name}'),
                    icon: _goalIcon(goal),
                    label: _goalLabel(goal),
                    selected: _selectedGoal == goal,
                    onTap: () => setState(() => _selectedGoal = goal),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AppNumberField(
              fieldKey: const Key('profile-target-weight'),
              label: '目标体重',
              unit: 'kg',
              optional: true,
              controller: _targetWeightController,
              hintText: '例如：65',
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final n = double.tryParse(value);
                  if (n == null || n <= 0) return '请输入有效体重';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            _sectionTitle('身体数据'),
            const SizedBox(height: 8),
            // 身高是本次新增的可编辑项（docs/29 §P1：用户点名「无法调身高」）。
            // 写入 `Profiles.heightCm`，与建案同列 ⇒ BMI 派生逻辑零改动。
            AppNumberField(
              fieldKey: const Key('profile-height'),
              label: '身高',
              unit: 'cm',
              optional: true,
              controller: _heightController,
              hintText: '例如：170',
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final n = double.tryParse(value);
                  if (n == null || !n.isFinite || n <= 0) return '请输入有效身高';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            AppNumberField(
              fieldKey: const Key('profile-age'),
              label: '年龄',
              unit: '岁',
              optional: true,
              integerOnly: true,
              controller: _ageController,
              hintText: '例如：28',
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final n = int.tryParse(value.trim());
                  if (n == null || n <= 0) return '年龄必须是正整数';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            const AppFieldLabel(label: '生理性别', optional: true),
            const SizedBox(height: LfDimens.spaceTiny),
            // 与 onboarding「基本信息」卡同一控件与文案（`BiologicalSex`）。
            // 允许空选：没填过时没有任何预选，不拿 `female` 冒充事实。
            SegmentedButton<BiologicalSex>(
              key: const Key('profile-sex'),
              segments: const [
                ButtonSegment(value: BiologicalSex.female, label: Text('女性')),
                ButtonSegment(value: BiologicalSex.male, label: Text('男性')),
              ],
              selected: {?_sex},
              emptySelectionAllowed: true,
              onSelectionChanged: (value) =>
                  setState(() => _sex = value.isEmpty ? null : value.first),
            ),
            // 「每日目标」（docs/32 §4 T9 / §3 D11 需求 64/72）：步数目标与
            // 水分目标。**未接线时整行不渲染**（不画一个点了没反应的输入框，
            // 与设置页未接线的动作行同一口径）。
            if (widget.stepsRepository != null ||
                widget.updateWaterTargetMl != null) ...[
              const SizedBox(height: 24),
              _sectionTitle('每日目标'),
              const SizedBox(height: 8),
            ],
            if (widget.stepsRepository != null)
              AppNumberField(
                fieldKey: const Key('profile-steps-goal'),
                label: '步数目标',
                unit: '步',
                integerOnly: true,
                controller: _stepsGoalController,
                hintText: '例如：10000',
                validator: (value) {
                  final raw = value?.trim() ?? '';
                  if (raw.isEmpty) return null; // 空 = 不改（保持库里的值）
                  final n = int.tryParse(raw);
                  if (n == null ||
                      n < StepsRepository.minDailyGoal ||
                      n > StepsRepository.maxDailyGoal) {
                    return '步数目标需在 ${StepsRepository.minDailyGoal}–'
                        '${StepsRepository.maxDailyGoal} 之间';
                  }
                  return null;
                },
              ),
            if (widget.stepsRepository != null &&
                widget.updateWaterTargetMl != null)
              const SizedBox(height: 16),
            if (widget.updateWaterTargetMl != null)
              AppNumberField(
                fieldKey: const Key('profile-water-target'),
                label: '水分目标',
                unit: 'L',
                controller: _waterTargetController,
                hintText: '例如：2',
                validator: (value) {
                  final raw = value?.trim() ?? '';
                  if (raw.isEmpty) return null; // 空 = 不改（保持库里的值）
                  final n = double.tryParse(raw);
                  if (n == null ||
                      !n.isFinite ||
                      n < kMinWaterTargetLiters ||
                      n > kMaxWaterTargetLiters) {
                    return '水分目标需在 $kMinWaterTargetLiters–'
                        '${kMaxWaterTargetLiters.toStringAsFixed(1)} L 之间';
                  }
                  return null;
                },
              ),
          ],
        ),
      ),
      // 用 FixedBottomPrimaryAction 而不是手写 SafeArea+Padding：本页有
      // AppNumberField，键盘弹起时手写版本会把「保存」留在原位被键盘盖住
      // （2026-09-26 实测按钮底边 814、可视边界 544，盖住 270dp）。
      // 该组件内含 viewInsets 底部内边距，正是 docs/21 §5.8.3「底部元素始终可点」。
      bottomNavigationBar: FixedBottomPrimaryAction(
        child: SizedBox(
          width: double.infinity,
          // 固定底栏的终端确认 = §3.8 B2（h48 / full 圆角 + 主色阴影）；
          // `busy` 走既有的三点跳动加载件，与其余主行动一致。
          child: LfConfirmButton(
            label: '保存',
            busy: _isLoading,
            onPressed: _isLoading ? null : _save,
          ),
        ),
      ),
    );
  }
}
