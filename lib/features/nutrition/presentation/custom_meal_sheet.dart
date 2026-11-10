import 'dart:async';

import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_slot_pill.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart'
    show MacroDotLine;

/// **「自定义一顿」**（2026-10-26 用户：「营养摄入自己不能改」）。
///
/// 复核发现的缺口：记餐只有「食物库 × 克数」这一条手工路（外加 AI 识餐与
/// 按菜品）。库里没有的外卖/家常菜/聚餐，只能先建一个食物、或者拍照让 AI
/// 估——**没有「我就吃了这么多」的入口**。
///
/// 数据层不需要任何迁移：`MealItems` 本来就允许 `foodId = null` +
/// `sourceType = 'manual'` + 四个营养快照列（`MealItemDraft` 已支持），
/// 这里只补一个输入面。
///
/// **份量（g）怎么填**：热量与宏量按「这一份」算；份量只用于以后在编辑弹层里
/// 按比例调整（比如「其实只吃了一半」把 100 改成 50）。所以默认 100、
/// 不必精确——这一点写在弹层里，不让用户猜。
final class CustomMealSheet extends StatefulWidget {
  const CustomMealSheet({
    super.key,
    required this.localDate,
    required this.onSubmit,
    this.initialSlot,
  });

  final String localDate;

  /// 落库动作由调用方给（与 `MealEditorDialog` 同一条契约）：返回 `null` =
  /// 成功并关窗；返回文案 = 写失败，弹层不关、错误就地显示。
  final Future<String?> Function(MealDraft draft) onSubmit;

  final MealSlot? initialSlot;

  /// 默认份量（g）：只用于「以后按比例改」，不是营养学上的精确克数。
  static const double defaultPortionGrams = 100;

  /// 打开弹层（返回即关闭；落库在 [onSubmit] 里完成）。
  static Future<void> show(
    BuildContext context, {
    required String localDate,
    required Future<String?> Function(MealDraft draft) onSubmit,
    MealSlot? initialSlot,
  }) {
    return AppSheet.showCustom<void>(
      context,
      builder: (_) => CustomMealSheet(
        localDate: localDate,
        onSubmit: onSubmit,
        initialSlot: initialSlot,
      ),
    );
  }

  @override
  State<CustomMealSheet> createState() => _CustomMealSheetState();
}

class _CustomMealSheetState extends State<CustomMealSheet> {
  final _name = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  late final _portion = TextEditingController(
    text: _format(CustomMealSheet.defaultPortionGrams),
  );
  late MealSlot _slot = widget.initialSlot ?? MealSlot.lunch;
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _kcal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    _portion.dispose();
    super.dispose();
  }

  static String _format(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);

  void _showError(String message) => setState(() => _errorText = message);

  Future<void> _submit() async {
    if (_saving) return;
    final kcal = double.tryParse(_kcal.text.trim());
    if (kcal == null) {
      _showError('请填这一顿的热量（kcal）。');
      return;
    }
    final portion = double.tryParse(_portion.text.trim());
    if (portion == null || !portion.isFinite || portion <= 0) {
      _showError('份量要填一个大于 0 的数字（不确定就保持 100）。');
      return;
    }
    double macro(TextEditingController controller, String label) {
      final raw = controller.text.trim();
      if (raw.isEmpty) return 0;
      final value = double.tryParse(raw);
      if (value == null || !value.isFinite || value < 0) {
        throw FormatException('$label 要填一个非负数字。');
      }
      return value;
    }

    final NutritionValues nutrition;
    try {
      nutrition = NutritionValues(
        kcal: kcal,
        proteinGrams: macro(_protein, '蛋白质'),
        carbsGrams: macro(_carbs, '碳水'),
        fatGrams: macro(_fat, '脂肪'),
      );
    } on FormatException catch (error) {
      _showError(error.message);
      return;
    }
    if (nutrition.kcal < 0) {
      _showError('热量不能是负数。');
      return;
    }
    final draft = MealDraft(
      localDate: widget.localDate,
      slot: _slot,
      items: [
        MealItemDraft(
          foodName: _name.text.trim().isEmpty ? '自定义一餐' : _name.text.trim(),
          grams: portion,
          nutrition: nutrition,
          // 无食物库来源：`foodId` 留空，来源标记 manual（schema 28 已支持）。
          sourceType: 'manual',
        ),
      ],
    );
    setState(() {
      _saving = true;
      _errorText = null;
    });
    String? failure;
    try {
      failure = await widget.onSubmit(draft);
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
    // 结构照 `MealEditorDialog`：字段区**限高 + 自己滚动**，标题/按钮常驻。
    // 弹层壳（`AppSheet`）不给内容滚动，六个字段 + 餐次胶囊在 800dp 屏幕上
    // 会顶破底部（实测溢出 52px），所以这里自己兜住。
    return Column(
      key: const Key('custom-meal-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('自定义一顿', style: LfText.headline.copyWith(color: c.cardForeground)),
        const SizedBox(height: LfDimens.spaceSmall),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: SingleChildScrollView(child: _fields(context)),
          ),
        ),
        if (_errorText case final error?) ...[
          const SizedBox(height: LfDimens.spaceSmall),
          Text(
            error,
            key: const Key('custom-meal-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: LfDimens.spaceSmall),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(
              label: '取消',
              onPressed: _saving ? null : () => Navigator.pop(context),
            ),
            LfConfirmButton(
              key: const Key('custom-meal-save'),
              label: '保存这一顿',
              expand: false,
              busy: _saving,
              onPressed: _saving ? null : () => unawaited(_submit()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fields(BuildContext context) {
    final c = context.lf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '不依赖食物库：直接填这一顿的热量与三个宏量（宏量可留空，按 0 计）。'
          '份量只用于以后按比例调整，不必精确。',
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        // 餐次胶囊 = 三处记录弹层共用的 `MealSlotPillRow`（2026-10-28 用户
        // 「自定义一顿也是一样」：LfFilterChip 浅底描边款与按食材的实心款
        // 不同构）。每颗 Key 沿用 `custom-meal-slot-<storedValue>`。
        KeyedSubtree(
          key: const Key('custom-meal-slot'),
          child: MealSlotPillRow(
            selected: (slot) => slot == _slot,
            onChanged: (slot) => setState(() => _slot = slot),
            pillKeyFor: (slot) => Key('custom-meal-slot-${slot.storedValue}'),
          ),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        LfTextField(
          fieldKey: const Key('custom-meal-name'),
          label: '名称',
          hintText: '例如：楼下炒饭（不填就叫「自定义一餐」）',
          optional: true,
          controller: _name,
          onChanged: (_) {},
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        AppNumberField(
          fieldKey: const Key('custom-meal-kcal'),
          controller: _kcal,
          label: '热量',
          unit: 'kcal',
          onChanged: (_) {},
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        // 三个宏量是**同级**的三件事，并排一行（取帧实测：竖着排 6 个字段
        // 会把最后「份量」那一格挤到折叠线下面，看起来像渲染坏了）。
        //
        // 【2026-10-29（R-2，用户：三宏量标题换行、三个输入框不在同一高度）】
        // 标签口径与菜品编辑器同源：320dp 三列各 ~85dp，「蛋白质（g，可选）」
        // 必折行且把第一个框顶下去（三框不等高的根因）。标签只留三个字，
        // 单位进 hint；「可选（留空 = 按 0 计）」写进顶部说明——诚实口径不丢。
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppNumberField(
                fieldKey: const Key('custom-meal-protein'),
                controller: _protein,
                label: '蛋白质',
                suffixText: 'g',
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: LfDimens.spaceSmall),
            Expanded(
              child: AppNumberField(
                fieldKey: const Key('custom-meal-carbs'),
                controller: _carbs,
                label: '碳水',
                suffixText: 'g',
                onChanged: (_) {},
              ),
            ),
            const SizedBox(width: LfDimens.spaceSmall),
            Expanded(
              child: AppNumberField(
                fieldKey: const Key('custom-meal-fat'),
                controller: _fat,
                label: '脂肪',
                suffixText: 'g',
                onChanged: (_) {},
              ),
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        AppNumberField(
          fieldKey: const Key('custom-meal-grams'),
          label: '份量',
          unit: 'g',
          controller: _portion,
          onChanged: (_) {},
        ),
        const SizedBox(height: LfDimens.spaceLarge),
        // 合计卡：与按食材/按菜品的「合计」同构（kcal 大字 + 三宏量点行），
        // 随输入实时变化——填了多少就是多少，不替用户换算。
        MutedBlock(
          key: const Key('custom-meal-totals'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '合计',
                style: LfText.captionStrong.copyWith(color: c.mutedForeground),
              ),
              const SizedBox(height: LfDimens.spaceSmall),
              Text(
                '${_enteredTotals().kcal.round()} kcal',
                style: LfText.headline.copyWith(color: c.foreground),
              ),
              const SizedBox(height: LfDimens.spaceSmall),
              MacroDotLine(
                protein: _enteredTotals().proteinGrams,
                carbs: _enteredTotals().carbsGrams,
                fat: _enteredTotals().fatGrams,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 输入框里的当前营养（留空 = 0；非法输入当 0 画——提交时的校验与
  /// 错误提示仍由 `_submit` 负责，合计卡只是实时预览）。
  NutritionValues _enteredTotals() {
    double? parse(TextEditingController controller) {
      final raw = controller.text.trim();
      if (raw.isEmpty) return null;
      final value = double.tryParse(raw);
      return (value == null || !value.isFinite || value < 0) ? null : value;
    }

    return NutritionValues(
      kcal: parse(_kcal) ?? 0,
      proteinGrams: parse(_protein) ?? 0,
      carbsGrams: parse(_carbs) ?? 0,
      fatGrams: parse(_fat) ?? 0,
    );
  }
}
