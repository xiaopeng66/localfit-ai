import 'dart:async';

import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/domain/nutrition_target_override.dart';

/// **手动指定每日营养目标**（2026-10-26 用户：「营养摄入自己不能改」）。
///
/// 2026-10-31 用户：「营养目标设置界面重新设计」。旧形态是四行
/// 「标签 3 : 下限 4 : 上限 4」的等分横排——四个汉字标签被挤在半宽里，
/// 大字号下先折行再截断；八个输入框平铺又没有层次，用户不知道该填哪个。
///
/// 新形态（三段式，全部复用既有设计件，不引新依赖）：
///
///  1. **热量**独占一段：大号 `AppNumberField` 两格 + 「kcal」，它是这张
///     弹层的主字段（每日预算先定热量，宏量是它的分配）；
///  2. **三大宏量**并排三段：每段 = 彩色圆点 + 名称（一行，不折）+ 两格
///     「下限 / 上限」单位 g；段与段之间用竖分隔线，扫一列时对齐；
///  3. **说明一行**：从哪天起生效、卡上的「依据」会改成手动设定；底部
///     「恢复按身体数据计算」在左、「保存（从今天起）」在右。
///
/// 三条纪律不变：
/// 1. 从**今天**起生效（`effectiveDate` = 调用方给的当天），不改写过去几天；
/// 2. 卡上的「依据」会改成「手动设定」——不再声称按 Mifflin–St Jeor 算；
/// 3. 「恢复按身体数据计算」清掉这套手动值，公式那套原样回来。
///
/// 所有输入框 Key（`target-<项>-min|max`）与两个按钮 Key 原样保留：既有
/// 测试与取帧件按它们定位，换的是版式不是契约。
final class NutritionTargetSheet extends StatefulWidget {
  const NutritionTargetSheet({
    super.key,
    required this.effectiveDate,
    required this.onSave,
    required this.onRestore,
    this.current,
  });

  /// 生效日期（`yyyy-MM-dd`）。
  final String effectiveDate;

  /// 当前生效目标（预填用；null = 还没有目标，留空由用户填）。
  final DailyNutritionTarget? current;

  /// 保存（返回 null = 成功关窗；返回文案 = 就地显示错误）。
  final Future<String?> Function(NutritionTargetOverride value) onSave;

  /// 恢复按身体数据计算。
  final VoidCallback onRestore;

  static Future<void> show(
    BuildContext context, {
    required String effectiveDate,
    required Future<String?> Function(NutritionTargetOverride value) onSave,
    required VoidCallback onRestore,
    DailyNutritionTarget? current,
  }) {
    return AppSheet.showCustom<void>(
      context,
      builder: (_) => NutritionTargetSheet(
        effectiveDate: effectiveDate,
        current: current,
        onSave: onSave,
        onRestore: onRestore,
      ),
    );
  }

  @override
  State<NutritionTargetSheet> createState() => _NutritionTargetSheetState();
}

class _NutritionTargetSheetState extends State<NutritionTargetSheet> {
  late final Map<String, TextEditingController> _controllers = {
    'kcal-min': _controller(widget.current?.calorieMinKcal),
    'kcal-max': _controller(widget.current?.calorieMaxKcal),
    'protein-min': _controller(widget.current?.proteinMinGrams),
    'protein-max': _controller(widget.current?.proteinMaxGrams),
    'carbs-min': _controller(widget.current?.carbsMinGrams),
    'carbs-max': _controller(widget.current?.carbsMaxGrams),
    'fat-min': _controller(widget.current?.fatMinGrams),
    'fat-max': _controller(widget.current?.fatMaxGrams),
  };
  String? _errorText;
  bool _saving = false;

  static TextEditingController _controller(double? value) {
    if (value == null) return TextEditingController();
    final text = value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return TextEditingController(text: text);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double? _read(String key) => double.tryParse(_controllers[key]!.text.trim());

  Future<void> _submit() async {
    if (_saving) return;
    // 只校验**缺项**：区间大小关系交给 `NutritionTargetOverride.validate()`
    // （单一口径，弹层不另写一套规则）。
    final keys = [
      'kcal-min',
      'kcal-max',
      'protein-min',
      'protein-max',
      'carbs-min',
      'carbs-max',
      'fat-min',
      'fat-max',
    ];
    for (final key in keys) {
      if (_read(key) == null) {
        setState(() => _errorText = '四项区间都要填数字（不确定就沿用当前的）。');
        return;
      }
    }
    final value = NutritionTargetOverride(
      effectiveDate: widget.effectiveDate,
      calorieMinKcal: _read('kcal-min')!,
      calorieMaxKcal: _read('kcal-max')!,
      proteinMinGrams: _read('protein-min')!,
      proteinMaxGrams: _read('protein-max')!,
      carbsMinGrams: _read('carbs-min')!,
      carbsMaxGrams: _read('carbs-max')!,
      fatMinGrams: _read('fat-min')!,
      fatMaxGrams: _read('fat-max')!,
    );
    final problem = value.validate();
    if (problem != null) {
      setState(() => _errorText = problem);
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    String? failure;
    try {
      failure = await widget.onSave(value);
    } catch (_) {
      failure = '保存失败，请重试。';
    }
    if (!mounted) return;
    if (failure == null) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _errorText = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 2.0× 下三列布局每格只剩约 76dp：四位数被输入框滚成「18」，三位宏量
    // 变「1」。大字号改为每个输入独占整行；1.0× 保留紧凑三列。
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 19;
    final macros = [
      ('蛋白质', c.protein, 'protein'),
      ('碳水', c.carbs, 'carbs'),
      ('脂肪', c.fat, 'fat'),
    ];
    return Column(
      key: const Key('nutrition-target-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('营养目标', style: LfText.headline.copyWith(color: c.cardForeground)),
        const SizedBox(height: LfDimens.spaceXSmall),
        Text(
          '从 ${widget.effectiveDate} 起生效。',
          key: const Key('target-sheet-note'),
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Section(
                    // 热量是这张弹层的主字段：独占一段、字号高一档。
                    title: '每日热量',
                    accent: c.primary,
                    child: _RangeRow(
                      keyPrefix: 'kcal',
                      controllers: _controllers,
                      unit: 'kcal',
                      emphasized: true,
                      stacked: largeText,
                    ),
                  ),
                  const SizedBox(height: LfDimens.spaceSmall),
                  _Section(
                    title: '三大宏量',
                    accent: c.mutedForeground,
                    child: largeText
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (index, macro) in macros.indexed) ...[
                                if (index > 0)
                                  const SizedBox(height: LfDimens.spaceMedium),
                                _MacroColumn(
                                  label: macro.$1,
                                  color: macro.$2,
                                  keyPrefix: macro.$3,
                                  controllers: _controllers,
                                  stacked: true,
                                ),
                              ],
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final (index, macro) in macros.indexed) ...[
                                if (index > 0) _MacroDivider(color: c.border),
                                Expanded(
                                  child: _MacroColumn(
                                    label: macro.$1,
                                    color: macro.$2,
                                    keyPrefix: macro.$3,
                                    controllers: _controllers,
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_errorText case final error?) ...[
          const SizedBox(height: LfDimens.spaceSmall),
          Text(
            error,
            key: const Key('target-sheet-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: LfDimens.spaceSmall),
        // 底部两档：恢复是 B6 文字按钮（次级），保存是 B2 实心（主行动）。
        // 用 `Wrap` + `spaceBetween`：大字号下两颗各占一行也不叠字。
        SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: LfDimens.spaceSmall,
            runSpacing: LfDimens.spaceXSmall,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LfTextButton(
                key: const Key('target-restore'),
                label: '恢复按身体数据计算',
                onPressed: _saving
                    ? null
                    : () {
                        widget.onRestore();
                        Navigator.pop(context);
                      },
              ),
              LfConfirmButton(
                key: const Key('target-save'),
                label: '保存（从今天起）',
                expand: false,
                busy: _saving,
                onPressed: _saving ? null : () => unawaited(_submit()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 一段：小标题 + 内容（弱底卡，与「大数字卡」同族的圆角与描边）。
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.accent,
    required this.child,
  });

  final String title;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        LfDimens.spaceMedium,
        LfDimens.spaceSmallPlus,
        LfDimens.spaceMedium,
        LfDimens.spaceMedium,
      ),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                ),
              ),
              const SizedBox(width: LfDimens.spaceXSmall),
              Text(
                title,
                style: LfText.captionStrong.copyWith(color: c.cardForeground),
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          child,
        ],
      ),
    );
  }
}

/// 热量那一段的两格（下限 / 上限）：标签放在框内右缘做单位后缀，框外不写
/// 重复的「下限/上限」长标签——两格并排时靠位置与提示词区分。
class _RangeRow extends StatelessWidget {
  const _RangeRow({
    required this.keyPrefix,
    required this.controllers,
    required this.unit,
    this.emphasized = false,
    this.stacked = false,
  });

  final String keyPrefix;
  final Map<String, TextEditingController> controllers;
  final String unit;
  final bool emphasized;

  /// true = 两格各占一整行（大字号），避免四位数被输入框横向滚动裁掉。
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final min = AppNumberField(
      fieldKey: Key('target-$keyPrefix-min'),
      label: '',
      hintText: '下限',
      suffixText: unit,
      controller: controllers['$keyPrefix-min'],
      onChanged: (_) {},
    );
    final max = AppNumberField(
      fieldKey: Key('target-$keyPrefix-max'),
      label: '',
      hintText: '上限',
      suffixText: unit,
      controller: controllers['$keyPrefix-max'],
      onChanged: (_) {},
    );
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          min,
          const SizedBox(height: LfDimens.spaceXSmall),
          max,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: min),
        const SizedBox(width: LfDimens.spaceSmall),
        Expanded(child: max),
      ],
    );
  }
}

/// 宏量三段里的一段：圆点 + 名称（一行）+ 下限/上限两格（单位 g）。
class _MacroColumn extends StatelessWidget {
  const _MacroColumn({
    required this.label,
    required this.color,
    required this.keyPrefix,
    required this.controllers,
    this.stacked = false,
  });

  final String label;
  final Color color;
  final String keyPrefix;
  final Map<String, TextEditingController> controllers;

  /// true = 该宏量占满整行（大字号下三列会裁数字）。
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: LfDimens.spaceXSmall),
            // 名称**单行**：旧版四字标签在半宽里折行才是缺陷；这里每段只有
            // 两字，放不下就等比缩小，绝不折行（名字断了比字小更难读）。
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  style: (stacked ? LfText.bodyStrong : LfText.captionStrong)
                      .copyWith(color: c.cardForeground),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceXSmall),
        AppNumberField(
          fieldKey: Key('target-$keyPrefix-min'),
          label: '',
          hintText: '下限',
          suffixText: 'g',
          controller: controllers['$keyPrefix-min'],
          onChanged: (_) {},
        ),
        const SizedBox(height: LfDimens.spaceXSmall),
        AppNumberField(
          fieldKey: Key('target-$keyPrefix-max'),
          label: '',
          hintText: '上限',
          suffixText: 'g',
          controller: controllers['$keyPrefix-max'],
          onChanged: (_) {},
        ),
      ],
    );
  }
}

/// 三段之间的竖分隔线（与内容顶部对齐，不拉满整段高）。
class _MacroDivider extends StatelessWidget {
  const _MacroDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: LfDimens.spaceSmall),
    child: Container(width: 1, height: 96, color: color),
  );
}
