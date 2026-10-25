import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_search_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_category_icon.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';

/// 「记录一餐 / 编辑餐食」弹层。
///
/// 用户 2026-10-03 走查原话：「食物添加界面的弹窗卡片太丑了，你根据现在的
/// 主题，重新设计」。旧实现里有四处与主题语言不符的地方，逐条改掉：
///
///  * **餐次是 `DropdownButtonFormField`**——点开是一个系统菜单，选完只显示
///    一个词；四个餐次是固定集合，改成**一横排胶囊**（选中 = `primary` 实底），
///    一眼看到「这餐算哪一餐」并能一键切换，与页面其它 sub-tab 胶囊同语言。
///  * **搜索框是 M3 `SearchBar`**（主题没有 `searchBarTheme`，落地成
///    `surfaceContainerHigh` + 海拔阴影 + 28 圆角），换成主题内的
///    [LfSearchField]；结果行从 `ListTile` 换成一枚枚 muted 圆角行，带分类
///    图标块、热量与「＋」。
///  * **已添加食物是一段裸 Row + TextField**，没有容器，和上面的搜索结果
///    视觉上分不开；改成 [MutedBlock] 卡片，卡内直接显示**按当前克数换算的**
///    热量与三大宏量（旧版只显示克数，用户改克数时看不到营养怎么变）。
///  * **合计是一行灰字**（「合计 209 kcal · 蛋白质 …」），改成合计卡：kcal
///    一行大字 + 三个彩点宏量，与食物卡/分析卡同一套读法。
///
/// 一处行为修复：搜索结果 future 缓存在 State 里（只在关键词变化时重建）。
/// 旧实现每帧新建 future，于是改克数触发的 `setState` 也会把结果区打回
/// 「加载中」——每敲一个数字结果列表闪一次。
///
/// Key 与文案契约全部保留（`meal-slot` / `meal-notes` / `meal-grams-item-N`
/// / `meal-save`、两条错误文案、条目 id 从 `item-1` 起）。
class MealEditorDialog extends StatefulWidget {
  const MealEditorDialog({
    required this.foodRepository,
    required this.localDate,
    this.initialMeal,
    this.initialSlot,
    this.onSubmit,
    super.key,
  });

  final FoodRepository foodRepository;
  final String localDate;
  final MealRecord? initialMeal;

  /// 预选槽位（Round7 阶段 2 决策 D9）：今日页「记录晚餐」与记录页槽位卡头的
  /// 「+」都要「点哪一餐就记哪一餐」。不传 = 既有默认（午餐），行为不变；
  /// 编辑既有餐食时 [initialMeal] 的槽位优先（那是那条记录的事实）。
  final MealSlot? initialSlot;

  /// 保存动作（落库由调用方给）。返回 `null` = 成功并关窗；返回文案 =
  /// **留在弹层内显示、不关窗**，用户添加的食物与克数一个都不丢（N7）。
  final Future<String?> Function(MealDraft draft)? onSubmit;

  @override
  State<MealEditorDialog> createState() => _MealEditorDialogState();
}

class _MealEditorDialogState extends State<MealEditorDialog> {
  final _search = TextEditingController();
  final _notes = TextEditingController();
  final List<_EditableItem> _items = [];
  late MealSlot _slot;
  String _query = '';
  String? _errorText;

  /// 提交态（只在给了 [MealEditorDialog.onSubmit] 时使用）。
  bool _saving = false;

  /// 当前关键词对应的一次查询。只在 `_query` 变化时重建（见类注释）。
  Future<List<FoodRecord>>? _results;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMeal;
    _slot = initial?.slot ?? widget.initialSlot ?? MealSlot.lunch;
    _notes.text = initial?.notes ?? '';
    if (initial != null) {
      _items.addAll(initial.items.map(_EditableItem.fromRecord));
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _notes.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nutrition = _draftItems().fold(
      NutritionValues.zero,
      (total, item) => total + item.nutrition,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.initialMeal == null ? '记录一餐' : '编辑餐食',
          // 原先只给字号没给色 ⇒ 落到 `TextTheme` 默认的纯黑/纯白。
          style: LfText.headline.copyWith(color: context.lf.cardForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 620),
            child: SingleChildScrollView(child: _content(nutrition)),
          ),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        if (_errorText case final error?)
          Padding(
            padding: const EdgeInsets.only(bottom: LfDimens.spaceXSmall),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        // 弹层行动行统一（§3.4）：左取消（B6）右主行动（B2）。
        // 两者都 `expand: false`——B2 默认撑满，在行内布局里会请求无限宽。
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(
              label: '取消',
              onPressed: _saving ? null : () => Navigator.pop(context),
            ),
            LfConfirmButton(
              key: const Key('meal-save'),
              expand: false,
              busy: _saving,
              onPressed: _saving ? null : _submit,
              label: widget.initialMeal == null ? '保存餐食' : '保存修改',
            ),
          ],
        ),
      ],
    );
  }

  Widget _content(NutritionValues nutrition) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppFieldLabel(label: '餐次'),
        const SizedBox(height: LfDimens.spaceTiny),
        _slotRow(),
        const SizedBox(height: LfDimens.spaceLarge),
        const AppFieldLabel(label: '添加食物'),
        const SizedBox(height: LfDimens.spaceTiny),
        LfSearchField(
          fieldKey: const Key('meal-food-search'),
          hintText: '搜索并添加食物',
          controller: _search,
          onChanged: _onQueryChanged,
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        // 结果区只在**有查询**时占固定高度：空查询时它是零信息量的提示，
        // 给它 168dp 会在弹层里留一大块空白，把合计卡挤出可视区（设备实测：
        // 360dp × 780dp 下列表高度固定时「合计」卡被切掉一半）。打字时键盘
        // 已经盖住这块，高度变化的跳动看不见。
        if (_query.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceSmall),
            child: Text(
              '输入名称搜索本地食物',
              textAlign: TextAlign.center,
              style: LfText.bodySmall.copyWith(
                color: context.lf.mutedForeground,
              ),
            ),
          )
        else
          SizedBox(height: _resultsHeight, child: _resultList()),
        const SizedBox(height: LfDimens.spaceLarge),
        Text(
          _items.isEmpty ? '已添加' : '已添加 ${_items.length} 项',
          style: LfText.captionStrong.copyWith(
            color: context.lf.mutedForeground,
          ),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        if (_items.isEmpty)
          MutedBlock(
            child: Text(
              '还没添加食物。在上面搜索食物名称，点一下加进来。',
              style: LfText.caption.copyWith(color: context.lf.mutedForeground),
            ),
          )
        else
          for (var index = 0; index < _items.length; index++) ...[
            if (index > 0) const SizedBox(height: LfDimens.spaceSmall),
            _itemCard(index),
          ],
        const SizedBox(height: LfDimens.spaceLarge),
        AppFieldLabel(label: '备注', optional: true),
        const SizedBox(height: LfDimens.spaceTiny),
        Semantics(
          label: '备注（可选）',
          child: TextField(
            key: const Key('meal-notes'),
            controller: _notes,
            decoration: const InputDecoration(hintText: '比如外食、加量'),
          ),
        ),
        const SizedBox(height: LfDimens.spaceLarge),
        _totalsCard(nutrition),
      ],
    );
  }

  /// 搜索结果区高度：三行半，够看到还有更多（滚一下就有）。
  static const double _resultsHeight = 168;

  /// 四枚餐次胶囊。
  ///
  /// 用 `Wrap` 而不是 `Row`：320dp 视口 + 2.0× 字号下四个「早餐/午餐/晚餐/
  /// 加餐」会超过一行，`Wrap` 会自动折到第二行；`Row` 只会溢出。
  Widget _slotRow() {
    return Wrap(
      // 胶囊组整体一个 Key（既有测试与语义都按 `meal-slot` 找它）。
      key: const Key('meal-slot'),
      spacing: LfDimens.spaceSmall,
      runSpacing: LfDimens.spaceSmall,
      children: [
        for (final slot in MealSlot.values)
          _SlotPill(
            label: slot.label,
            selected: slot == _slot,
            onTap: () => setState(() => _slot = slot),
          ),
      ],
    );
  }

  /// 有查询时的结果区（调用点已保证查询非空）。
  Widget _resultList() {
    return FutureBuilder<List<FoodRecord>>(
      future: _results,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: AppErrorText('食物加载失败，请重试。'));
        }
        if (!snapshot.hasData) {
          return const Center(
            child: SizedBox.square(
              dimension: LfDimens.iconLg,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final foods = snapshot.data!;
        if (foods.isEmpty) {
          return Center(
            child: Text(
              '没有找到食物，换个词再试。',
              style: LfText.bodySmall.copyWith(
                color: context.lf.mutedForeground,
              ),
            ),
          );
        }
        return ListView.separated(
          // 这一层是弹层里的**内部**小滚动区（最多 10 行），不参与页面级
          // 遮挡断言；键盘弹起时外层滚动区负责把整块带进视野。
          padding: EdgeInsets.zero,
          itemCount: foods.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: LfDimens.spaceTiny),
          itemBuilder: (context, index) {
            final food = foods[index];
            return _FoodResultRow(food: food, onTap: () => _addFood(food));
          },
        );
      },
    );
  }

  /// 已添加项卡片：名称 + 移除 + 克数输入 + 按当前克数换算的营养。
  Widget _itemCard(int index) {
    final item = _items[index];
    final grams = double.tryParse(item.grams.text.trim());
    final scaled = grams == null || grams <= 0
        ? item.referenceNutrition
        : item.toDraft(grams).nutrition;
    final inSync = grams != null && grams > 0;
    return MutedBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.foodName,
                  style: LfText.bodyStrong.copyWith(
                    color: context.lf.foreground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 卡内移除 = §3.8 B4 圆钮（muted 档）。
              LfCircleIconButton(
                tooltip: '移除 ${item.foodName}',
                onPressed: () => _removeItem(index),
                iconSize: LfDimens.iconMd,
                icon: Icons.remove_circle_outline,
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppNumberField(
                  // 按条目稳定 id 而非列表下标做 key：按下标时移除中间项会让
                  // 后续字段的元素复用错位的控制器，把焦点与 IME 输入串到别的条目。
                  fieldKey: Key('meal-grams-${item.id}'),
                  label: '克数',
                  unit: 'g',
                  controller: item.grams,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: LfDimens.spaceMedium),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${scaled.kcal.round()} kcal',
                    style: LfText.title.copyWith(color: context.lf.foreground),
                    maxLines: 1,
                  ),
                  const SizedBox(height: LfDimens.spaceMicro),
                  Text(
                    // 克数非法时如实说明这行数字是「原始份量」而不是当前值，
                    // 不能让用户以为它在跟着输入框变。
                    inSync ? '按当前克数' : '待填克数',
                    style: LfText.micro.copyWith(
                      color: context.lf.mutedForeground,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          MacroDotLine(
            protein: scaled.proteinGrams,
            carbs: scaled.carbsGrams,
            fat: scaled.fatGrams,
          ),
        ],
      ),
    );
  }

  /// 合计卡：kcal 一行大字 + 三个彩点宏量。
  Widget _totalsCard(NutritionValues nutrition) {
    return MutedBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '合计',
            style: LfText.captionStrong.copyWith(
              color: context.lf.mutedForeground,
            ),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          Text(
            '${nutrition.kcal.round()} kcal',
            style: LfText.headline.copyWith(color: context.lf.foreground),
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

  List<MealItemDraft> _draftItems() => _items
      .map((item) {
        final grams = double.tryParse(item.grams.text.trim());
        return grams == null ? null : item.toDraft(grams);
      })
      .whereType<MealItemDraft>()
      .toList(growable: false);

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _results = value.trim().isEmpty
          ? null
          : widget.foodRepository.search(value, limit: 10);
    });
  }

  void _addFood(FoodRecord food) {
    final serving = food.defaultServingGrams;
    final grams = serving != null && serving > 0 ? serving : 100.0;
    setState(() {
      _items.add(_EditableItem.fromFood(food, grams));
      _search.clear();
      _query = '';
      _results = null;
    });
  }

  void _removeItem(int index) {
    final removed = _items.removeAt(index);
    setState(() {});
    // 待本帧元素真正卸载后再释放控制器，避免残留的焦点/IME 引用悬空。
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  Future<void> _submit() async {
    // 双击/连点只落一次库（落库异步化后，`pop` 不再于第一击内同步发生）。
    if (_saving) return;
    final items = _draftItems();
    if (_items.isEmpty) {
      _showError('请至少添加一种食物。');
      return;
    }
    if (items.length != _items.length ||
        items.any((item) => !item.grams.isFinite || item.grams <= 0)) {
      _showError('食物克数必须是大于零的数值。');
      return;
    }
    final draft = MealDraft(
      localDate: widget.localDate,
      slot: _slot,
      items: items,
      notes: _notes.text,
    );
    final onSubmit = widget.onSubmit;
    if (onSubmit == null) {
      Navigator.pop(context, draft);
      return;
    }
    // 提交失败留在弹层内（N7）：食物清单与克数都不丢，改完能直接再存。
    setState(() {
      _saving = true;
      _errorText = null;
    });
    String? failure;
    try {
      failure = await onSubmit(draft);
    } catch (_) {
      failure = '餐食保存失败，请重试。';
    }
    if (!mounted) return;
    if (failure == null) {
      Navigator.pop(context, draft);
      return;
    }
    setState(() {
      _saving = false;
      _errorText = failure;
    });
  }

  void _showError(String message) {
    // 弹层盖住了 Scaffold，SnackBar 会被完全遮住；错误必须在弹层内内联展示。
    setState(() => _errorText = message);
  }
}

/// 餐次胶囊（选中 = primary 实底，未选 = muted 底）。
class _SlotPill extends StatelessWidget {
  const _SlotPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? c.primary : c.muted,
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
          child: InkWell(
            borderRadius: BorderRadius.circular(LfDimens.radiusFull),
            onTap: onTap,
            child: ConstrainedBox(
              // 命中高度对齐 44dp 触达线（视觉上是整块胶囊，不是只给文字）。
              constraints: const BoxConstraints(
                minHeight: LfDimens.minTouchTarget,
                minWidth: LfDimens.minTouchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LfDimens.spaceLarge,
                ),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label,
                    style: LfText.bodyStrong.copyWith(
                      color: selected ? c.primaryForeground : c.foreground,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 搜索结果行：muted 圆角行 + 分类图标块 + 名称 + 品牌/每 100g 热量 + 「＋」。
///
/// 品牌必须进这一行：真实库里同名不同品牌的条目很常见（「米饭」有四条，
/// 116/156/181/338 kcal），只印名称时用户分不清点的是哪条，点错就记错营养。
class _FoodResultRow extends StatelessWidget {
  const _FoodResultRow({required this.food, required this.onTap});

  final FoodRecord food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brand = food.brand?.trim() ?? '';
    final subtitle =
        '${brand.isEmpty ? '' : '$brand · '}'
        '${food.kcalPer100g.round()} kcal / 100g';
    return Semantics(
      button: true,
      label: brand.isEmpty ? '添加 ${food.name}' : '添加 ${food.name}（$brand）',
      child: ExcludeSemantics(
        child: Material(
          color: c.muted,
          borderRadius: BorderRadius.circular(LfDimens.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(LfDimens.radiusMd),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: LfDimens.minTouchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: LfDimens.spaceMedium,
                  vertical: LfDimens.spaceSmall,
                ),
                child: Row(
                  children: [
                    FoodCategoryIcon(
                      category: FoodCategory.classify(name: food.name),
                      size: 40,
                    ),
                    const SizedBox(width: LfDimens.spaceMedium),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            food.name,
                            style: LfText.body.copyWith(color: c.foreground),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            subtitle,
                            style: LfText.micro.copyWith(
                              color: c.mutedForeground,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: LfDimens.spaceSmall),
                    Icon(
                      Icons.add_circle_outline,
                      size: LfDimens.iconMd,
                      color: c.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _EditableItem {
  _EditableItem({
    required this.foodName,
    required this.referenceGrams,
    required this.referenceNutrition,
    required double initialGrams,
    this.foodId,
  }) : id = 'item-${_nextId++}',
       grams = TextEditingController(text: _formatNumber(initialGrams));

  static int _nextId = 1;

  /// 弹层会话内唯一且稳定，用于 TextField key 与测试定位。
  final String id;

  factory _EditableItem.fromFood(FoodRecord food, double grams) {
    final draft = MealItemDraft.fromFood(food, grams);
    return _EditableItem(
      foodId: food.id,
      foodName: food.name,
      referenceGrams: grams,
      referenceNutrition: draft.nutrition,
      initialGrams: grams,
    );
  }

  factory _EditableItem.fromRecord(MealItemRecord item) => _EditableItem(
    foodId: item.foodId,
    foodName: item.foodName,
    referenceGrams: item.grams,
    referenceNutrition: item.nutrition,
    initialGrams: item.grams,
  );

  final String? foodId;
  final String foodName;
  final double referenceGrams;
  final NutritionValues referenceNutrition;
  final TextEditingController grams;

  MealItemDraft toDraft(double newGrams) {
    final factor = newGrams / referenceGrams;
    return MealItemDraft(
      foodId: foodId,
      foodName: foodName,
      grams: newGrams,
      nutrition: NutritionValues(
        kcal: referenceNutrition.kcal * factor,
        proteinGrams: referenceNutrition.proteinGrams * factor,
        carbsGrams: referenceNutrition.carbsGrams * factor,
        fatGrams: referenceNutrition.fatGrams * factor,
      ),
    );
  }

  void dispose() => grams.dispose();

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();
}
