import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/goal_big_card.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:go_router/go_router.dart';
import 'package:localfit_ai/app/design/app_haptics.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_celebration.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/fixed_bottom_primary_action.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_segment_control.dart';
import 'package:localfit_ai/app/design/widgets/lf_toggle_switch.dart';
import 'package:localfit_ai/app/design/widgets/target_range_bar.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({required this.completeOnboarding, super.key});

  final Future<NutritionTarget> Function(OnboardingInput input)
  completeOnboarding;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  /// 阶段条的段数（docs/32 §3 D18 第 1 条：4 段 24×4 胶囊）。
  static const int _stepCount = 4;

  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _age = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _targetWeight = TextEditingController();
  BiologicalSex _sex = BiologicalSex.female;
  ActivityLevel _activity = ActivityLevel.lightlyActive;
  HealthGoal _goal = HealthGoal.loseFat;
  bool _isPregnantOrBreastfeeding = false;
  bool _hasChronicCondition = false;
  bool _hasEatingDisorderRisk = false;
  bool _saving = false;

  /// 当前阶段（0 起）。**只是视觉进度**，不拆步、不与校验状态绑定
  /// （docs/32 §8.3 定案）。
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateStep);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_updateStep)
      ..dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    _targetWeight.dispose();
    super.dispose();
  }

  /// 阶段条按滚动位置推进（docs/32 §3 D18 第 1–2 条）：归一进度
  /// `p = pixels / maxScrollExtent` 映射到 4 段
  /// （`<.25 → 1`、`<.5 → 2`、`<.75 → 3`、`else → 4`）。
  ///
  /// 内容不足一屏（`maxScrollExtent == 0`）时恒为第 1 段——那种情况下
  /// 全部内容都可见，谎报「已到第 3 步」比不动更糟。单页滚动被看成
  /// 4 个信息分区，滚动位置就是唯一的进度信号。
  void _updateStep() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final ratio = max <= 0
        ? 0.0
        : (_scroll.position.pixels / max).clamp(0.0, 1.0);
    final step = ratio < 0.25
        ? 0
        : ratio < 0.5
        ? 1
        : ratio < 0.75
        ? 2
        : 3;
    if (step != _step) setState(() => _step = step);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('建立本地档案')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 阶段条钉在正文之上、不参与滚动：它是「我在第几段」的指示器，
              // 滚到底时恰好最需要它（合并稿 frame ③ 也是这么画的）。
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  LfDimens.pagePadding,
                  8,
                  LfDimens.pagePadding,
                  LfDimens.spaceLarge,
                ),
                child: _stepHeader(),
              ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                    LfDimens.pagePadding,
                    0,
                    LfDimens.pagePadding,
                    LfDimens.spaceLargePlus,
                  ),
                  children: [
                    Text('设定你的起点', style: LfText.displayLarge),
                    const SizedBox(height: 8),
                    Text(
                      '资料只保存在本机，用于估算初始营养目标。',
                      style: LfText.bodySmall.copyWith(
                        color: context.lf.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '结果仅供日常健康管理参考，不能替代医生、营养师或专业教练。',
                      style: LfText.bodySmall.copyWith(
                        color: context.lf.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: LfDimens.spaceLargePlus),
                    _basicInfoCard(),
                    const SizedBox(height: LfDimens.spaceLarge),
                    _goalSectionCard(),
                    const SizedBox(height: LfDimens.spaceLarge),
                    _safetyCard(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // docs/32 §3 D18 第 7 条 / §8.3 定案：主行动**固定在可视区底部**
      // （不随内容滚动），高度取现有 token h48（不采设计稿 52dp）。
      // 用 `bottomNavigationBar` 而不是 `Stack` + `Positioned`：键盘弹起时
      // 随 `viewInsets` 上移，底部元素始终可点（docs/21 §5.8.3）。
      bottomNavigationBar: FixedBottomPrimaryAction(
        // 表单主行动 = §3.8 B2（h48 / full 圆角 + 主色阴影）。原先裸
        // `FilledButton` 走的是主题的 B1 档（h48 但 16 圆角、无阴影），
        // 与「流程末端确认」的形态不一致。
        child: LfConfirmButton(
          key: const Key('onboarding-submit'),
          label: _saving ? '正在保存…' : '计算并确认目标',
          busy: _saving,
          onPressed: _saving ? null : _reviewAndSave,
        ),
      ),
    );
  }

  /// 阶段条 + 微标签（docs/32 §3 D18 第 1–2 条）。
  ///
  /// 已过的段累计填充（设计稿 `STEP 3 / 4` 时亮 3 段）；胶囊本身
  /// `ExcludeSemantics`——进度由下面的微标签逐字承载，与 `LfProgressBar`
  /// 同口径（「信息由相邻文字承载」）。
  Widget _stepHeader() {
    final c = context.lf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Row(
            key: const Key('onboarding-progress'),
            children: [
              for (var i = 0; i < _stepCount; i++) ...[
                if (i > 0) const SizedBox(width: LfDimens.spaceTiny),
                Container(
                  width: 24,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _step ? c.primary : c.border,
                    borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Text(
          'STEP ${_step + 1} / $_stepCount · 建立档案',
          key: const Key('onboarding-progress-label'),
          style: LfText.label.copyWith(
            color: c.primary,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  // 三张卡原先都是裸 `Card` + 手写 16dp Padding：圆角/描边/阴影与其余页面的
  // 卡片（`DesignCard` = card 底 + 1px 描边 + surface 阴影 + 16 圆角）不是
  // 同一套形态语言，收敛到共享件。
  Widget _basicInfoCard() => DesignCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('基本信息', style: LfText.headline),
        const SizedBox(height: LfDimens.spaceXSmall),
        // 分组卡说明副文案（docs/32 §3 D18 第 3 条）。
        Text(
          '用于计算基础代谢率与营养分配',
          style: LfText.caption.copyWith(color: context.lf.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceLargePlus),
        _numberField(_age, '年龄', '岁', integerOnly: true),
        const SizedBox(height: LfDimens.spaceMedium),
        // docs/32 §3 D18 第 5 条：M3 `SegmentedButton` → 自绘 48dp 分段控件
        // （3dp 内衬 / 选中白底 + 主色字 + 阴影）。
        const AppFieldLabel(label: '性别'),
        const SizedBox(height: LfDimens.spaceTiny),
        LfSegmentControl<BiologicalSex>(
          segments: const [
            LfSegment(value: BiologicalSex.female, label: '女性'),
            LfSegment(value: BiologicalSex.male, label: '男性'),
          ],
          selected: _sex,
          segmentKeys: const {
            BiologicalSex.female: Key('onboarding-sex-female'),
            BiologicalSex.male: Key('onboarding-sex-male'),
          },
          onChanged: (value) => setState(() => _sex = value),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        _numberField(_height, '身高', 'cm'),
        const SizedBox(height: LfDimens.spaceMedium),
        _numberField(_weight, '当前体重', 'kg'),
        const SizedBox(height: LfDimens.spaceMedium),
        // 标签与输入框同源：DropdownButtonFormField 不是文本框，用框外标签
        // （§3.10），不再借 `labelText` 的浮动标签。
        // docs/32 §3 D7（需求 66）：统一下拉 LfSelectField（输入框形 + AppSheet 单选列表）。
        LfSelectField<ActivityLevel>(
          fieldKey: const Key('onboarding-日常活动程度'),
          label: '日常活动程度',
          value: _activity,
          options: ActivityLevel.values,
          // docs/32 §3 D18 第 4 条：档位数仍以 `ActivityLevel` 4 值为准，
          // 只把纯标签换成设计稿的描述式写法。
          optionLabel: _activityLabel,
          onChanged: (value) => setState(() => _activity = value),
        ),
      ],
    ),
  );

  Widget _goalSectionCard() => DesignCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('你的目标', style: LfText.headline),
        const SizedBox(height: LfDimens.spaceXSmall),
        // 分组卡说明副文案（docs/32 §3 D18 第 3 条）。
        Text(
          '选择主要方向，系统将据此调整营养与训练计划',
          style: LfText.caption.copyWith(color: context.lf.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceLargePlus),
        Row(
          children: [
            GoalBigCard(
              icon: Icons.local_fire_department_outlined,
              label: '减脂',
              selected: _goal == HealthGoal.loseFat,
              onTap: () => setState(() => _goal = HealthGoal.loseFat),
            ),
            GoalBigCard(
              icon: Icons.fitness_center_outlined,
              label: '增肌',
              selected: _goal == HealthGoal.gainMuscle,
              onTap: () => setState(() => _goal = HealthGoal.gainMuscle),
            ),
            GoalBigCard(
              icon: Icons.eco_outlined,
              // 与资料页/AI 协议统一用「维持」（`maintain` 的中文口径
              // 三处一致，见 chat_edit_registry 的标签映射）。
              label: '维持',
              selected: _goal == HealthGoal.maintain,
              onTap: () => setState(() => _goal = HealthGoal.maintain),
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        _numberField(_targetWeight, '目标体重', 'kg', required: false),
      ],
    ),
  );

  /// 安全筛查：行式布局 + iOS 风格 46×28 开关 + 行间 1px 分隔线
  /// （docs/32 §3 D18 第 6 条）。
  ///
  /// 三个 Key、三个开关的语义与回调**都不变**（`docs/32 §4 T15` 验收）：
  /// 只把 M3 `SwitchListTile` 换成同语义的行式自绘，命中面从「开关 + 标题」
  /// 收敛为**整行**（行高 ≥ 44dp），避免「必须点中 46×28」的窄命中。
  Widget _safetyCard() => DesignCard(
    key: const Key('onboarding-safety-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('安全筛查', style: LfText.headline),
        const SizedBox(height: 4),
        Text(
          '以下信息仅用于判断是否适合自动计算目标，不会保存。',
          style: LfText.bodySmall.copyWith(color: context.lf.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceXSmall),
        _safetyRow(
          rowKey: const Key('onboarding-pregnancy-risk'),
          question: '正在孕期或哺乳期',
          value: _isPregnantOrBreastfeeding,
          onChanged: (value) =>
              setState(() => _isPregnantOrBreastfeeding = value),
        ),
        Divider(height: 1, thickness: 1, color: context.lf.border),
        _safetyRow(
          rowKey: const Key('onboarding-chronic-risk'),
          question: '存在需饮食或运动管理的慢性疾病',
          value: _hasChronicCondition,
          onChanged: (value) => setState(() => _hasChronicCondition = value),
        ),
        Divider(height: 1, thickness: 1, color: context.lf.border),
        _safetyRow(
          rowKey: const Key('onboarding-eating-risk'),
          question: '当前或既往存在进食障碍风险',
          value: _hasEatingDisorderRisk,
          onChanged: (value) => setState(() => _hasEatingDisorderRisk = value),
        ),
      ],
    ),
  );

  /// 一行安全筛查：左问题文本（可换行）+ 右 [LfToggleSwitch]，**整行可点**。
  ///
  /// 开关本身是呈现件（不接手势），语义挂在本行：读屏只有一个开关节点，
  /// 也不会出现「行与开关各触发一次」的双跳。
  Widget _safetyRow({
    required Key rowKey,
    required String question,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final c = context.lf;
    return Semantics(
      toggled: value,
      child: GestureDetector(
        key: rowKey,
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Container(
          constraints: const BoxConstraints(minHeight: LfDimens.minTouchTarget),
          padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceMedium),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  question,
                  style: LfText.body.copyWith(color: c.foreground),
                ),
              ),
              const SizedBox(width: LfDimens.spaceMedium),
              LfToggleSwitch(value: value),
            ],
          ),
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
    String unit, {
    bool required = true,
    bool integerOnly = false,
    Key? fieldKey,
  }) {
    return AppNumberField(
      fieldKey: fieldKey ?? Key('onboarding-$label'),
      label: label,
      unit: unit,
      optional: !required,
      controller: controller,
      integerOnly: integerOnly,
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return required ? '请填写$label' : null;
        // 年龄等整数字段若放过小数/科学计数法，int.parse 会抛英文内部错误。
        if (integerOnly) {
          return int.tryParse(text) == null ? '$label必须是整数' : null;
        }
        final number = double.tryParse(text);
        if (number == null || !number.isFinite) return '请输入有效数值';
        return null;
      },
    );
  }

  Future<void> _reviewAndSave() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final input = _input();
      validateOnboardingSafety(input);
      final target = const NutritionTargetCalculator().calculate(
        NutritionTargetInput(
          age: input.age,
          biologicalSex: input.biologicalSex,
          heightCm: input.heightCm,
          weightKg: input.weightKg,
          activityLevel: input.activityLevel,
          goal: input.goal,
        ),
      );
      if (!await _confirmTarget(target) || !mounted) return;
      setState(() => _saving = true);
      await widget.completeOnboarding(input);
      if (!mounted) return;
      // docs/21 §2.9：完成本地档案 = 全 App 首个庆祝时刻
      // （AppCelebrationGuard 每会话最多 1 次）+ 主按钮成功触觉；
      // 庆祝层挂在根 Overlay 上，随后的路由切换不会打断它。
      AppHaptics.success();
      showAppCelebration(context);
      if (mounted) context.go('/today');
    } on OnboardingSafetyException catch (error) {
      await _showSafetyGuidance(error.message);
    } on FormatException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  OnboardingInput _input() => OnboardingInput(
    age: int.parse(_age.text.trim()),
    biologicalSex: _sex,
    heightCm: double.parse(_height.text),
    weightKg: double.parse(_weight.text),
    activityLevel: _activity,
    goal: _goal,
    targetWeightKg: _targetWeight.text.trim().isEmpty
        ? null
        : double.parse(_targetWeight.text.trim()),
    isPregnantOrBreastfeeding: _isPregnantOrBreastfeeding,
    hasChronicCondition: _hasChronicCondition,
    hasEatingDisorderRisk: _hasEatingDisorderRisk,
  );

  Future<bool> _confirmTarget(NutritionTarget target) async =>
      await AppSheet.show<bool>(
        context,
        title: '确认每日目标',
        // docs/32 §3 D4（需求 59）：四行纯文本 → 图形化。
        // 热量升为主行（大号区间 + 主绿范围条），三个宏量各一行
        // （数据色圆点 + 名称 + 区间 + 范围条）。范围条只画位置、不画完成度。
        content: _TargetSummary(target: target),
        // 用弹层内 context 弹：`AppSheet` 走根导航器，页面 context 的
        // `pop` 在分支导航器上可能弹掉页面而不是弹层（食堂删除确认同坑）。
        actions: Builder(
          builder: (sheetContext) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 弹层行动档（§3.8）：次级 = B6，终端确认 = B2（`expand: false`
              // ——B2 默认撑满，在 `OverflowBar`/Row 里会请求无限宽）。
              LfTextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                label: '返回修改',
              ),
              LfConfirmButton(
                expand: false,
                onPressed: () => Navigator.pop(sheetContext, true),
                label: '确认保存',
              ),
            ],
          ),
        ),
      ) ??
      false;

  Future<void> _showSafetyGuidance(String message) => AppSheet.show<void>(
    context,
    title: '请先寻求专业帮助',
    content: Text(message),
    actions: LfConfirmButton(
      key: const Key('onboarding-safety-close'),
      label: '我知道了',
      onPressed: () => Navigator.pop(context),
    ),
  );

  void _showError(String message) {
    if (!mounted) return;
    AppSnackBar.show(context, message, icon: AppSnackBar.errorIcon);
  }
}

/// 活动档的描述式标签（docs/32 §3 D18 第 4 条，需求 74）。
///
/// 档位数**仍以 `ActivityLevel` 现有 4 值为准**：设计稿的 5 档（含
/// 「极高 — 体力劳动或每日训练」）不采纳——新增枚举值要动领域模型与
/// 目标计算，超出「借布局与文案」的范围。只把纯标签换成「档位 — 描述」。
String _activityLabel(ActivityLevel level) => switch (level) {
  ActivityLevel.sedentary => '久坐 — 几乎不运动',
  ActivityLevel.lightlyActive => '轻度 — 每周 1-2 次低强度',
  ActivityLevel.moderatelyActive => '中度 — 每周 3-4 次中等强度',
  ActivityLevel.veryActive => '高强度 — 每周 5-6 次较高强度',
};

/// 目标确认抽屉的内容（docs/32 §3 D4 / 需求 59）。
///
/// 热量是主行：30px 大号区间 + 主绿范围条 + 量程刻度（0 与 max×1.2）；
/// 三个宏量各一行：数据色圆点 + 名称 + 区间 + 范围条（蛋白橙 / 碳水黄 / 脂肪紫）。
/// 两条口径：范围条只画位置（不显示百分比/完成度）；数值与
/// `NutritionTargetCalculator` 输出逐字一致（不做二次取整）。
class _TargetSummary extends StatelessWidget {
  const _TargetSummary({required this.target});

  final NutritionTarget target;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final mint = LfColors.mint(brightness);
    final calorieScale = (target.calorieMaxKcal * TargetRangeBar.headroom)
        .round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已按你的资料估算出每日目标范围',
          style: LfText.bodySmall.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        DecoratedBox(
          decoration: BoxDecoration(
            color: mint.tone(50),
            border: Border.all(color: mint.tone(100)),
            borderRadius: BorderRadius.circular(LfDimens.radiusMd),
          ),
          child: Padding(
            padding: const EdgeInsets.all(LfDimens.spaceMediumPlus),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每日热量',
                  key: const Key('target-summary-calorie-label'),
                  style: LfText.label.copyWith(
                    color: LfColors.mintText(brightness),
                  ),
                ),
                const SizedBox(height: LfDimens.spaceXSmall),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${withThousandsSeparator(target.calorieMinKcal)}–'
                          '${withThousandsSeparator(target.calorieMaxKcal)}',
                          key: const Key('target-summary-calorie-value'),
                          style: LfText.displayLarge.copyWith(
                            color: c.cardForeground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: LfDimens.spaceXSmall),
                    Text(
                      'kcal',
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                  ],
                ),
                const SizedBox(height: LfDimens.spaceMedium),
                TargetRangeBar(
                  key: const Key('target-summary-calorie-bar'),
                  min: target.calorieMinKcal,
                  max: target.calorieMaxKcal,
                  color: mint.tone(500),
                  height: 8,
                ),
                const SizedBox(height: LfDimens.spaceTiny),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '0',
                      style: LfText.micro.copyWith(color: c.mutedForeground),
                    ),
                    Text(
                      withThousandsSeparator(calorieScale),
                      style: LfText.micro.copyWith(color: c.mutedForeground),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: LfDimens.spaceMediumPlus),
        TargetRangeRow(
          key: const Key('target-summary-protein'),
          label: '蛋白质',
          color: c.protein,
          min: target.proteinMinGrams,
          max: target.proteinMaxGrams,
        ),
        const SizedBox(height: LfDimens.spaceMediumPlus),
        TargetRangeRow(
          key: const Key('target-summary-carbs'),
          label: '碳水',
          color: c.carbs,
          min: target.carbsMinGrams,
          max: target.carbsMaxGrams,
        ),
        const SizedBox(height: LfDimens.spaceMediumPlus),
        TargetRangeRow(
          key: const Key('target-summary-fat'),
          label: '脂肪',
          color: c.fat,
          min: target.fatMinGrams,
          max: target.fatMaxGrams,
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Text(
          '确认后进入「今日」页开始记录。范围条只表达你这一档的落点，不是「已完成进度」。',
          style: LfText.label.copyWith(color: c.mutedForeground),
        ),
      ],
    );
  }
}

/// 目标三大卡：图标 + 标签，选中薄荷描边 + 浅底（docs/21 §3.1）。
///
/// Round7 阶段 6 · 缺陷 ㉓：原来是 32px **emoji**（🔥💪🌿）——本仓不随包
