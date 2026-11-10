import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart'
    show AppFieldLabel;
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_picker_row.dart';
import 'package:localfit_ai/app/design/widgets/lf_search_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart'
    show LfCircleIconButton;
import 'package:localfit_ai/core/text/search_text.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/domain/source_badge.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_entry_chooser_sheet.dart'
    show defaultMealSlotLabel;
import 'package:localfit_ai/features/nutrition/presentation/meal_slot_pill.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart'
    show MacroDotLine;

/// 「按菜品记录」表单弹层的返回结果（取消 = null）。
///
/// [saved] = 实际落库成功的份数；[slot] = 用户最终选定的餐次（可能不是页面
/// 预选的那枚）。调用方据此如实提示「已记 N 份菜到〈餐次〉」，不拿预选值
/// 冒充用户的选择（与 `DishMealConfirmSheet` 旧口径同源：用户点的优先）。
class DishMealEditorResult {
  const DishMealEditorResult({required this.saved, required this.slot});

  final int saved;
  final MealSlot slot;
}

/// 「按菜品记录」**表单弹层**（2026-10-28 用户原话：「按菜品记录为什么弹窗
/// 还是这样，我要的是按食材记录这样，自定义一顿也是一样」）。
///
/// 旧路是「选菜 → 二次确认」两步（`DishMealPickerDialog` +
/// `DishMealConfirmSheet`），与「按食材记录」的表单形态（餐次胶囊 + 搜索 +
/// 已添加 + 合计 + 保存）不同构——同一件事两套长相。本件把「按菜品」并成
/// **同一张表单**：
///
/// * 餐次胶囊（点哪一餐记哪一餐，页面预选优先）；
/// * 搜索菜品（菜品库全量在弹层手里本地过滤，口径与食材侧同源：
///   `normalizeSearchText` 包含匹配）；
/// * 点结果行 = 加入本餐（同一道菜不重复加）；
/// * 已添加卡：名称 + 移除 + 整份口径 + 该份营养；
/// * 合计卡（与按食材同构：kcal 大字 + `MacroDotLine`）；
/// * 保存 = 对每个已添加菜走一次 [DishMealEditorSheet.onAddDish]（页面已
///   接线的 `AddDishToMeal.run` → `MealRepository.create`，
///   `source = dish_library`）——**不新增写路径**。
///
/// 份量口径不变：菜品库是「每份」模板，营养按整份记（`servingGrams` / 100g
/// 兜底由 `AddDishToMeal` 负责），弹层里只展示、不填克数。
///
/// 【未分析的食堂菜不在本表单】它们没有营养，加进来就是 0 kcal（污染当天
/// 热量）。那条「搜得到但不能记、点了给『去分析』」的路留在
/// `DishMealPickerDialog`（类型 `DishPick` / `PickedUnanalyzedCanteenDish`
/// 仍在使用），由调用方按场景继续用。
///
/// Key 契约（docs/21 附录 D1，2026-10-28 修订）：
/// `dish-meal-editor`（根）/ `dish-meal-slot` + `dish-meal-slot-<name>`
/// （胶囊）/ `dish-meal-picker-search`（搜索）/ `dish-meal-picker-item-<id>`
/// （结果行，沿用旧行键）/ `dish-meal-picker-empty` / `dish-meal-totals`
/// （合计）/ `meal-save`（动作键与按食材一字不差）。
class DishMealEditorSheet extends StatefulWidget {
  const DishMealEditorSheet({
    super.key,
    required this.dishes,
    required this.localDate,
    required this.onAddDish,
    this.initialSlot,
  });

  /// 菜品库全部条目（调用方已读好；弹层自己不查库）。
  final List<DishRecord> dishes;

  /// 记到哪一天（页面当前选中日期）。**只有 [onAddDish] 为 null 的只读预览
  /// 场景用得上**（测试与取帧）；真实落库时日期由调用方的 `AddDishToMeal`
  /// 决定（它按 `localDate` 写入），本件只负责把「哪一餐」传下去。
  final String localDate;

  /// 落库动作（页面已接线的 `onAddDishToMeal`，返回 `Future<void>`）。
  ///
  /// 失败口径：**抛异常 = 该条失败**。弹层捕获后内联显示「保存失败」、
  /// 弹层不关；已成功的条目不回滚（与旧「记一份」逐份落库语义一致），
  /// 失败的留在待存列表里，重按保存只补没存上的。
  final Future<void> Function(DishRecord dish, {MealSlot? slotOverride})
  onAddDish;

  /// 预选餐次（页面的「点哪一餐就记哪一餐」）；null = 午餐。
  final MealSlot? initialSlot;

  static Future<DishMealEditorResult?> show(
    BuildContext context, {
    required List<DishRecord> dishes,
    required String localDate,
    required Future<void> Function(DishRecord dish, {MealSlot? slotOverride})
    onAddDish,
    MealSlot? initialSlot,
  }) => AppSheet.showCustom<DishMealEditorResult>(
    context,
    builder: (_) => DishMealEditorSheet(
      dishes: dishes,
      localDate: localDate,
      onAddDish: onAddDish,
      initialSlot: initialSlot,
    ),
  );

  @override
  State<DishMealEditorSheet> createState() => _DishMealEditorSheetState();
}

class _DishMealEditorSheetState extends State<DishMealEditorSheet> {
  final _search = TextEditingController();
  late MealSlot _slot = widget.initialSlot ?? MealSlot.lunch;
  String _query = '';
  String? _errorText;
  bool _saving = false;

  /// 已加入本餐的菜（保持加入顺序；同一道菜不重复加）。
  final List<DishRecord> _added = [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 本地过滤（与食材侧同源口径：归一后包含匹配）。
  List<DishRecord> get _visible {
    final normalized = normalizeSearchText(_query);
    if (normalized.isEmpty) return widget.dishes;
    return [
      for (final dish in widget.dishes)
        if (normalizeSearchText(dish.name).contains(normalized)) dish,
    ];
  }

  bool _isAdded(DishRecord dish) => _added.any((a) => a.id == dish.id);

  /// 合计：整份口径直接相加（每份值就是这一份的营养）。
  NutritionValues get _totals {
    var kcal = 0.0;
    var protein = 0.0;
    var carbs = 0.0;
    var fat = 0.0;
    for (final dish in _added) {
      kcal += dish.kcal;
      protein += dish.proteinG;
      carbs += dish.carbsG;
      fat += dish.fatG;
    }
    return NutritionValues(
      kcal: kcal,
      proteinGrams: protein,
      carbsGrams: carbs,
      fatGrams: fat,
    );
  }

  void _addDish(DishRecord dish) {
    if (_isAdded(dish)) return;
    setState(() {
      _added.add(dish);
      _search.clear();
      _query = '';
      _errorText = null;
    });
  }

  void _removeDish(DishRecord dish) =>
      setState(() => _added.removeWhere((a) => a.id == dish.id));

  Future<void> _save() async {
    if (_saving) return;
    if (_added.isEmpty) {
      _showError('请先在搜索里点一道菜加进来。');
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    // 逐条落库（每道菜一次 AddDishToMeal.run）。异常 = 该条失败：内联显示、
    // 弹层不关；**已成功的不回滚**——与旧「记一份」逐份落库的语义一致，失败
    // 的留在待存列表里，重按保存只补没存上的那几条。
    final pending = List<DishRecord>.of(_added);
    var saved = 0;
    for (final dish in pending) {
      try {
        await widget.onAddDish(dish, slotOverride: _slot);
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _errorText = '「${dish.name}」保存失败，请重试（已存好的不受影响）。';
        });
        return;
      }
      if (!mounted) return;
      _added.removeWhere((a) => a.id == dish.id);
      saved++;
    }
    if (!mounted) return;
    // 带回存好的份数与**实际选中的餐次**，调用方据此如实提示（取消 = null）。
    Navigator.pop(context, DishMealEditorResult(saved: saved, slot: _slot));
  }

  void _showError(String message) => setState(() => _errorText = message);

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      key: const Key('dish-meal-editor'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('按菜品记录', style: LfText.headline.copyWith(color: c.cardForeground)),
        const SizedBox(height: LfDimens.spaceSmall),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: SingleChildScrollView(child: _fields(context)),
          ),
        ),
        if (_errorText case final error?) ...[
          const SizedBox(height: LfDimens.spaceSmall),
          Text(
            error,
            key: const Key('dish-meal-editor-error'),
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
              key: const Key('meal-save'),
              label: '保存餐食',
              expand: false,
              busy: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ],
    );
  }

  Widget _fields(BuildContext context) {
    final c = context.lf;
    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppFieldLabel(label: '餐次'),
        const SizedBox(height: LfDimens.spaceTiny),
        Wrap(
          key: const Key('dish-meal-slot'),
          spacing: LfDimens.spaceSmall,
          runSpacing: LfDimens.spaceSmall,
          children: [
            MealSlotPillRow(
              selected: (slot) => slot == _slot,
              onChanged: (slot) => setState(() => _slot = slot),
              pillKeyFor: (slot) => Key('dish-meal-slot-${slot.name}'),
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceLarge),
        const AppFieldLabel(label: '添加菜品'),
        const SizedBox(height: LfDimens.spaceTiny),
        LfSearchField(
          fieldKey: const Key('dish-meal-picker-search'),
          hintText: '搜菜品名（如「番茄」）',
          controller: _search,
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        if (widget.dishes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceMedium),
            child: Text(
              // 空态给可行动的信息，不是一句「暂无数据」（docs/21 D1）。
              '菜品库还是空的。先在菜单页把吃过的菜「存为菜品」，或在食堂目录里分析菜品。',
              key: const Key('dish-meal-picker-empty'),
              style: LfText.body.copyWith(color: c.mutedForeground),
            ),
          )
        else if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceMedium),
            child: Text(
              '没有匹配的菜品，换个词试试。',
              key: const Key('dish-meal-picker-no-match'),
              style: LfText.body.copyWith(color: c.mutedForeground),
            ),
          )
        else
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.border),
            _dishResultRow(visible[i]),
          ],
        const SizedBox(height: LfDimens.spaceLarge),
        Text(
          _added.isEmpty ? '已添加' : '已添加 ${_added.length} 份',
          style: LfText.captionStrong.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        if (_added.isEmpty)
          MutedBlock(
            child: Text(
              '还没有加菜。在上面搜索菜品名称，点一下加进来。',
              key: const Key('dish-meal-added-empty'),
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
          )
        else
          for (final dish in _added) ...[
            _addedCard(dish),
            const SizedBox(height: LfDimens.spaceSmall),
          ],
        const SizedBox(height: LfDimens.spaceLarge),
        _totalsCard(context),
      ],
    );
  }

  /// 搜索结果行：与旧选择弹层、与「按食材」的食物卡都走**同一个**共享行件
  /// `LfPickerRow`（需求 11a 的行形态）。点击 = 加进来（不是关弹层）。
  Widget _dishResultRow(DishRecord dish) {
    final c = context.lf;
    final added = _isAdded(dish);
    return InkWell(
      key: Key('dish-meal-picker-item-${dish.id}'),
      onTap: added ? null : () => _addDish(dish),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: LfPickerRow(
          leading: CircleAvatar(
            radius: LfPickerRow.leadingSize / 2,
            backgroundColor: c.muted,
            child: Text(
              dish.name.isEmpty ? '菜' : dish.name.characters.first,
              style: LfText.bodyStrong.copyWith(color: c.mutedForeground),
            ),
          ),
          title: dish.name,
          titleKey: Key('dish-meal-picker-title-${dish.id}'),
          subtitle:
              '${defaultMealSlotLabel(dish.mealSlot)} · ${dish.energyLabel}',
          subtitleKey: Key('dish-meal-picker-subtitle-${dish.id}'),
          // 已加入的行右侧换成对勾（一眼看出「这道已经在餐里」），
          // 未加入仍是来源徽标（与菜品卡同源，docs/41 §7 第四条铁律）。
          trailing: added
              ? Icon(Icons.check, size: LfDimens.iconMd, color: c.success)
              : LfSourceBadgePair.forMealSource(
                  dish.source,
                  keyPrefix: 'dish-meal-picker-badge-${dish.id}',
                ),
          trailingKey: Key('dish-meal-picker-row-trailing-${dish.id}'),
        ),
      ),
    );
  }

  /// 已添加卡：名称 + 移除 + 整份口径 + 该份宏量。
  Widget _addedCard(DishRecord dish) {
    final c = context.lf;
    return MutedBlock(
      key: Key('dish-meal-added-${dish.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dish.name,
                  style: LfText.bodyStrong.copyWith(color: c.foreground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              LfCircleIconButton(
                key: Key('dish-meal-added-remove-${dish.id}'),
                tooltip: '移除 ${dish.name}',
                onPressed: () => _removeDish(dish),
                iconSize: LfDimens.iconMd,
                icon: Icons.remove_circle_outline,
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMicro),
          Text(
            '整份 · ${dish.kcal.round()} kcal',
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          MacroDotLine(
            protein: dish.proteinG,
            carbs: dish.carbsG,
            fat: dish.fatG,
          ),
        ],
      ),
    );
  }

  /// 合计卡（与按食材弹层的「合计」同构）。
  Widget _totalsCard(BuildContext context) {
    final nutrition = _totals;
    final c = context.lf;
    return MutedBlock(
      key: const Key('dish-meal-totals'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '合计',
            style: LfText.captionStrong.copyWith(color: c.mutedForeground),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          Text(
            '${nutrition.kcal.round()} kcal',
            style: LfText.headline.copyWith(color: c.foreground),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          MacroDotLine(
            protein: nutrition.proteinGrams,
            carbs: nutrition.carbsGrams,
            fat: nutrition.fatGrams,
          ),
        ],
      ),
    );
  }
}
