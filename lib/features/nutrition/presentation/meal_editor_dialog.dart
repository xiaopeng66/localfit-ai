import 'dart:io';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/features/nutrition/application/catalog_search.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_search_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/core/nutrition/nutrition_units.dart';
import 'package:localfit_ai/features/nutrition/application/nutrition_math.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_category_icon.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_slot_pill.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/dish_visuals.dart'
    show DishVisuals;
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart'
    show MacroDotLine;

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
    this.dishRepository,
    this.supplyCatalog,
    this.initialMeal,
    this.initialSlot,
    this.onSubmit,
    super.key,
  });

  final FoodRepository foodRepository;

  /// 【2026-10-29（N-2，用户：三个添加入口合并成一个界面）】菜品库一并
  /// 搜索：结果行打来源标（食物库 / 菜品库），卡片样式统一。null = 未接线
  /// （只搜食物库，行为与旧版一致）。
  final DishLibraryRepository? dishRepository;

  /// 食堂供应（docs/67 §6.4）：与主食物同一主库的另一投影。选中后可给
  /// "份数"，克数由该供应自己的每份克数解析；null = 不显示供应结果。
  final SupplyCatalogRepository? supplyCatalog;
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

  // 【N-2】手动添加食材的内联表单（搜不到也能记）。
  bool _manualAdding = false;
  final _manualName = TextEditingController();
  final _manualGrams = TextEditingController(text: '100');
  final _manualKcal = TextEditingController();
  final _manualProtein = TextEditingController();
  final _manualCarbs = TextEditingController();
  final _manualFat = TextEditingController();
  bool _manualStoreToLibrary = true;
  late MealSlot _slot;
  String _query = '';
  String? _errorText;

  /// 提交态（只在给了 [MealEditorDialog.onSubmit] 时使用）。
  bool _saving = false;

  /// 当前关键词对应的一次查询。只在 `_query` 变化时重建（见类注释）。
  /// 【N-2】命中 = 食物库 + 菜品库合并、带来源标。
  Future<List<_SearchHit>>? _results;

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
    _manualName.dispose();
    _manualGrams.dispose();
    _manualKcal.dispose();
    _manualProtein.dispose();
    _manualCarbs.dispose();
    _manualFat.dispose();
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
            child: Column(
              children: [
                Text(
                  '输入名称搜索食物库与菜品库',
                  textAlign: TextAlign.center,
                  style: LfText.bodySmall.copyWith(
                    color: context.lf.mutedForeground,
                  ),
                ),
                const SizedBox(height: LfDimens.spaceSmall),
                // 【N-2】手动添加入口不依赖搜索：常驻一行。
                _ManualAddRow(
                  expanded: _manualAdding,
                  onToggle: () =>
                      setState(() => _manualAdding = !_manualAdding),
                ),
                if (_manualAdding) _manualForm(),
              ],
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

  /// 搜索结果区高度：三张完整候选卡，不再让第三张只露一多半。
  /// 每行 56dp；两条分隔与首末内衬都使用 `spaceTiny = 6`，总高
  /// `3×56 + 4×6 = 192`。高度和间距由同一组算术约束，不再写 188 后让
  /// 首末留白把第三张挤出去。
  static const double _resultsHeight = 192;

  /// 四枚餐次胶囊（共享件 `MealSlotPillRow`，三个记录弹层同一颗）。
  Widget _slotRow() {
    // 胶囊组整体一个 Key（既有测试与语义都按 `meal-slot` 找它）。
    return KeyedSubtree(
      key: const Key('meal-slot'),
      child: MealSlotPillRow(
        selected: (slot) => slot == _slot,
        onChanged: (slot) => setState(() => _slot = slot),
      ),
    );
  }

  /// 【N-2】手动添加食材：克数 + 四个营养值（这一顿实际吃的量）。
  /// 勾选「同时存入食物库」时按 per-100g 折算落库，条目挂 `foodId`；
  /// 不勾则只作本餐条目（`sourceType = manual`），不留库。
  Future<void> _submitManual() async {
    final name = _manualName.text.trim();
    final grams = double.tryParse(_manualGrams.text.trim());
    final kcal = double.tryParse(_manualKcal.text.trim());
    if (name.isEmpty) {
      _showError('给手动添加的食材起个名字。');
      return;
    }
    if (grams == null || grams <= 0) {
      _showError('克数必须是大于 0 的数字。');
      return;
    }
    double? macro(TextEditingController controller) {
      final raw = controller.text.trim();
      if (raw.isEmpty) return null;
      final value = double.tryParse(raw);
      if (value == null || !value.isFinite || value < 0) {
        throw const FormatException('宏量要填非负数字。');
      }
      return value;
    }

    final NutritionValues nutrition;
    try {
      nutrition = NutritionValues(
        kcal: kcal ?? 0,
        proteinGrams: macro(_manualProtein) ?? 0,
        carbsGrams: macro(_manualCarbs) ?? 0,
        fatGrams: macro(_manualFat) ?? 0,
      );
    } on FormatException catch (error) {
      _showError(error.message);
      return;
    }

    if (_manualStoreToLibrary) {
      final factor = 100 / grams;
      final newFood = NewFood(
        name: name,
        kcalPer100g: nutrition.kcal * factor,
        proteinPer100g: nutrition.proteinGrams * factor,
        carbsPer100g: nutrition.carbsGrams * factor,
        fatPer100g: nutrition.fatGrams * factor,
        defaultServingGrams: grams,
      );
      // 尽力落库：成功后条目挂 foodId（下次能直接搜到）；失败不阻断记账
      // ——条目本身已能记（sourceType 退回 manual）。
      FoodRecord? stored;
      try {
        stored = await widget.foodRepository.create(newFood);
      } on Object {
        stored = null;
      }
      if (!mounted) return;
      if (stored != null) {
        _items.add(_EditableItem.fromFood(stored, grams));
      } else {
        _items.add(
          _EditableItem(
            foodName: name,
            referenceGrams: grams,
            referenceNutrition: nutrition,
            initialGrams: grams,
            sourceType: 'manual',
          ),
        );
      }
    } else {
      _items.add(
        _EditableItem(
          foodName: name,
          referenceGrams: grams,
          referenceNutrition: nutrition,
          initialGrams: grams,
          sourceType: 'manual',
        ),
      );
    }
    setState(() {
      _manualAdding = false;
      _manualName.clear();
      _manualKcal.clear();
      _manualProtein.clear();
      _manualCarbs.clear();
      _manualFat.clear();
      _errorText = null;
    });
  }

  /// 手动添加的内联表单（N-2）。
  /// 手动录入表单（2026-10-30 用户：「展开内容太丑了」）。
  ///
  /// 旧件把 6 个字段直接铺在一块灰底 `MutedBlock` 里：字段之间没有分组、
  /// 名称与营养数挤成一片、开关说明折成两行。现在按「是什么 / 吃多少 /
  /// 营养多少 / 存不存库」四段收进一张白卡（与弹层其它区域同层），每段
  /// 有独立的字段标签，动作按钮单独靠右。key 与校验逻辑一字不动。
  Widget _manualForm() {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.only(top: LfDimens.spaceSmall),
      child: DesignCard(
        key: const Key('meal-manual-form'),
        padding: const EdgeInsets.all(LfDimens.spaceLarge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '手动填写',
              style: LfText.bodyStrong.copyWith(color: c.cardForeground),
            ),
            const SizedBox(height: LfDimens.spaceMedium),
            AppFieldLabel(label: '名称'),
            const SizedBox(height: LfDimens.spaceTiny),
            TextField(
              key: const Key('meal-manual-name'),
              controller: _manualName,
              decoration: const InputDecoration(hintText: '例如：家里做的炒青菜'),
            ),
            const SizedBox(height: LfDimens.spaceMedium),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppNumberField(
                    fieldKey: const Key('meal-manual-grams'),
                    controller: _manualGrams,
                    label: '这一份的克数',
                    unit: 'g',
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Expanded(
                  child: AppNumberField(
                    fieldKey: const Key('meal-manual-kcal'),
                    controller: _manualKcal,
                    label: '总热量',
                    unit: 'kcal',
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: LfDimens.spaceMedium),
            Text(
              // 【2026-10-31 用户（设计稿 round11/editor）】单位写进组标题，
              // 不聚焦也能看到该填 g。
              '三大营养素（可选，g，按这一份的总量填）',
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
            const SizedBox(height: LfDimens.spaceTiny),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppNumberField(
                    fieldKey: const Key('meal-manual-protein'),
                    controller: _manualProtein,
                    // 【2026-10-31 用户：单位只有聚焦才显示】标签带单位常显，
                    // suffix 保留（聚焦时双保险）。
                    label: '蛋白质（g）',
                    suffixText: 'g',
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Expanded(
                  child: AppNumberField(
                    fieldKey: const Key('meal-manual-carbs'),
                    controller: _manualCarbs,
                    label: '碳水（g）',
                    suffixText: 'g',
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Expanded(
                  child: AppNumberField(
                    fieldKey: const Key('meal-manual-fat'),
                    controller: _manualFat,
                    label: '脂肪（g）',
                    suffixText: 'g',
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
            const SizedBox(height: LfDimens.spaceMedium),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '同时存入食物库，下次能直接搜到',
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
                ),
                Switch(
                  key: const Key('meal-manual-store'),
                  value: _manualStoreToLibrary,
                  onChanged: (value) =>
                      setState(() => _manualStoreToLibrary = value),
                ),
              ],
            ),
            const SizedBox(height: LfDimens.spaceSmall),
            Align(
              alignment: Alignment.centerRight,
              child: LfConfirmButton(
                key: const Key('meal-manual-add'),
                label: '添加到本餐',
                expand: false,
                onPressed: _submitManual,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 有查询时的结果区（调用点已保证查询非空）。
  /// 【N-2】双库合并命中、统一行样式 + 来源标（食物库 / 菜品库）。
  Widget _resultList() {
    return FutureBuilder<List<_SearchHit>>(
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
        final hits = snapshot.data!;
        if (hits.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  '没有找到食物或菜品，换个词再试。',
                  style: LfText.bodySmall.copyWith(
                    color: context.lf.mutedForeground,
                  ),
                ),
              ),
              const SizedBox(height: LfDimens.spaceSmall),
              // 【N-2】搜不到也能手动录入（用户：还能自己手动添加食材和营养）。
              _ManualAddRow(
                expanded: _manualAdding,
                onToggle: () => setState(() => _manualAdding = !_manualAdding),
              ),
              if (_manualAdding) _manualForm(),
            ],
          );
        }
        return ListView.separated(
          // 这一层是弹层里的**内部**小滚动区（最多 10 行），不参与页面级
          // 遮挡断言；键盘弹起时外层滚动区负责把整块带进视野。
          // 首末候选都不能贴滚动区边缘；与两条分隔共用 spaceTiny。三项内容
          // 加四处 6dp 后正好 192dp，与 `_resultsHeight` 一致。
          padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceTiny),
          // 【2026-10-31 用户：开始搜索就说明不需要手动录入】结果末尾不再
          // 常驻「手动添加」行——手动入口只在搜索为空（弹层顶部常驻行）
          // 与「没有找到」两种时机出现。
          itemCount: hits.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: LfDimens.spaceTiny),
          itemBuilder: (context, index) {
            final hit = hits[index];
            return hit.when(
              onFood: (food) =>
                  _FoodResultRow(food: food, onTap: () => _addFood(food)),
              onSupply: (supply) => _SupplyResultRow(
                supply: supply,
                onTap: () => _addSupply(supply),
              ),
              onDish: (dish) =>
                  _DishResultRow(dish: dish, onTap: () => _addDish(dish)),
            );
          },
        );
      },
    );
  }

  /// 【N-2】把菜品库的菜加入本餐：整份口径（`servingGrams` / 100g 兜底），
  /// 条目带 `sourceType = 'dish'` + `sourceId`，克数与其它条目一样可编辑。
  ///
  /// docs/67 §4.2：**份量未知/假设的旧菜不能按克换算**（每份值不知道对应
  /// 多少克），所以这里拒绝添加并提示补全——不把 100g 当默认份量。
  void _addDish(DishRecord dish) {
    final serving = dish.servingGrams;
    if (dish.basisAssumed || serving == null || serving <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '「${dish.name}」没有可信的每份克数，不能按克记；'
            '请重新分析成食物，或先补一份多少克。',
          ),
        ),
      );
      return;
    }
    setState(() {
      _items.add(_EditableItem.fromDish(dish, serving));
      _search.clear();
      _query = '';
      _results = null;
      _manualAdding = false;
    });
  }

  /// 已添加项卡片：名称 + 克数输入 + 换算营养 + 删除。
  ///
  /// 【2026-11-02 用户：这些控件的水平位置要固定，删除按钮每张卡都不一样】
  /// 旧行用 `Flexible(名称) + Expanded(克数)`：名称长度不同、kcal 文本宽度
  /// 不同，Row 的剩余空间被摊到末尾 ⇒ 每张卡的删除钮落在不同 x。现在改成
  /// **固定列**：删除列恒 44、kcal 列恒 84、克数列恒 92，名称吃剩余宽度并
  /// 省略；窄屏（320×2.0）自动降成两行，删除钮仍在右上角同一位置。
  Widget _itemCard(int index) {
    final c = context.lf;
    final item = _items[index];
    final grams = double.tryParse(item.grams.text.trim());
    final scaled = grams == null || grams <= 0
        ? item.referenceNutrition
        : item.toDraft(grams).nutrition;
    final inSync = grams != null && grams > 0;
    final name = Text(
      item.foodName,
      style: LfText.bodyStrong.copyWith(color: context.lf.foreground),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final gramsField = AppNumberField(
      // 按条目稳定 id 而非列表下标做 key：按下标时移除中间项会让
      // 后续字段的元素复用错位的控制器，把焦点与 IME 输入串到别的条目。
      fieldKey: Key('meal-grams-${item.id}'),
      // 【N-3（用户：克数描述导致卡片变高）】单位 g 改为输入框
      // 内右缘后缀，标签整行退役。
      label: '',
      suffixText: 'g',
      controller: item.grams,
      onChanged: (_) => setState(() {}),
    );
    final kcalText = Tooltip(
      message: inSync ? '按当前克数' : '待填克数（当前显示原始份量）',
      child: Text(
        '${scaled.kcal.round()} kcal',
        style: LfText.bodyStrong.copyWith(color: context.lf.foreground),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    // 【2026-10-31 用户：删除按钮做明显一点，做成删除垃圾桶按钮】
    // error 桶形钮——醒目但不占一整行。
    final deleteButton = LfCircleIconButton(
      key: Key('meal-item-delete-${item.id}'),
      tooltip: '删除 ${item.foodName}',
      onPressed: () => _removeItem(index),
      iconSize: 16,
      icon: Icons.delete_outline,
      background: c.error.withValues(alpha: 0.12),
      iconColor: c.error,
    );
    const deleteWidth = 44.0;
    const kcalWidth = 76.0;
    const gramsWidth = 96.0;
    // 【2026-11-03 用户：克数输入框应在名称后边、删除按钮前边，热量和三宏量
    // 在下边一行】最终版两行：
    //   第一行 = 名称（Expanded）+ 克数输入框（96）+ 删除钮（44）；
    //   第二行 = 热量（76，右对齐）+ 宏量点行（Expanded）。
    // 克数紧跟在名称后面，删除钮恒在最右；热量与宏量同排对照。
    //
    // 降级（320dp × 2.0× 实测固定宽度会截断「348 kcal」）：
    //   · 大字号（>1.3×）：名称+删除 / 克数 / 热量 / 宏量，各占一行；
    //   · 窄屏（<300dp，正常字号）：名称+删除 / 克数+热量 / 宏量。
    return Semantics(
      value: inSync ? '${scaled.kcal.round()} kcal' : null,
      child: MutedBlock(
        padding: const EdgeInsets.symmetric(
          horizontal: LfDimens.spaceMedium,
          vertical: LfDimens.spaceSmallPlus,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final largeText = scale > 1.3;
            final narrow = constraints.maxWidth < 300;
            final nameWithDelete = Row(
              children: [
                Expanded(child: name),
                const SizedBox(width: LfDimens.spaceXSmall),
                SizedBox(
                  width: deleteWidth,
                  child: Center(child: deleteButton),
                ),
              ],
            );
            final nameWithGrams = Row(
              children: [
                Expanded(child: name),
                const SizedBox(width: LfDimens.spaceSmall),
                SizedBox(width: gramsWidth, child: gramsField),
                const SizedBox(width: LfDimens.spaceXSmall),
                SizedBox(
                  width: deleteWidth,
                  child: Center(child: deleteButton),
                ),
              ],
            );
            final kcal = SizedBox(
              width: kcalWidth,
              child: Align(alignment: Alignment.centerRight, child: kcalText),
            );
            final macros = MacroDotLine(
              protein: scaled.proteinGrams,
              carbs: scaled.carbsGrams,
              fat: scaled.fatGrams,
              shortLabels: true,
            );
            if (largeText) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  nameWithDelete,
                  const SizedBox(height: LfDimens.spaceXSmall),
                  SizedBox(width: gramsWidth * 1.4, child: gramsField),
                  const SizedBox(height: LfDimens.spaceXSmall),
                  Align(alignment: Alignment.centerRight, child: kcalText),
                  const SizedBox(height: LfDimens.spaceXSmall),
                  macros,
                ],
              );
            }
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  nameWithDelete,
                  const SizedBox(height: LfDimens.spaceXSmall),
                  Row(
                    children: [
                      SizedBox(width: gramsWidth, child: gramsField),
                      const SizedBox(width: LfDimens.spaceSmall),
                      kcal,
                    ],
                  ),
                  const SizedBox(height: LfDimens.spaceXSmall),
                  macros,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                nameWithGrams,
                const SizedBox(height: LfDimens.spaceXSmall),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    kcal,
                    const SizedBox(width: LfDimens.spaceSmall),
                    Expanded(child: macros),
                  ],
                ),
              ],
            );
          },
        ),
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
      final query = value.trim();
      _results = query.isEmpty ? null : _searchBoth(query);
    });
  }

  /// 【N-2】统一检索（Phase 3 起走 [CatalogSearch]）：食物库 + 菜品库 +
  /// 食堂供应一次查完，归一化口径只有一份。食物库在前（高频），供应次之
  /// （带窗口、按份可记），旧菜品库最后（只读兼容）。
  Future<List<_SearchHit>> _searchBoth(String query) async {
    final result = await CatalogSearch(
      foods: widget.foodRepository,
      dishes: widget.dishRepository,
      supplies: widget.supplyCatalog,
    ).search(query);
    return [
      for (final food in result.foods) _SearchHit.food(food),
      for (final supply in result.supplies) _SearchHit.supply(supply),
      for (final dish in result.dishes) _SearchHit.dish(dish),
    ];
  }

  void _addFood(FoodRecord food) {
    final serving = food.defaultServingGrams;
    // 通用默认份量只是"这次输入框的预填建议"，不是"这个窗口的一份"。
    final grams = serving != null && serving > 0 ? serving : 100.0;
    setState(() {
      _items.add(_EditableItem.fromFood(food, grams));
      _search.clear();
      _query = '';
      _results = null;
    });
  }

  /// 食堂供应：默认记 1 份，克数由**该供应自己的**每份克数解析。
  ///
  /// 份量未知时不允许按"份"记——跳去让用户填实际克数（按克记）而不是
  /// 悄悄补 100g（docs/67 §4.2）。
  void _addSupply(SupplyCatalogItem supply) {
    if (!supply.canRecordByServing) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '「${supply.displayName}」还没有可信的每份克数；'
            '先在食堂目录补一份多少克，或按克记这一餐。',
          ),
        ),
      );
      return;
    }
    setState(() {
      _items.add(_EditableItem.fromSupply(supply));
      _search.clear();
      _query = '';
      _results = null;
      _manualAdding = false;
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

/// 搜索结果行（食物库 / 菜品库**共用同一件**）。
///
/// 【2026-10-30 用户：「来自菜品库和食物库的检索卡片样式，我不是让你统一吗，
/// 还让你加上来源的标记，你怎么不加，不统一」】旧实现是两套各写一遍：
/// 食物行有 40dp 分类图标、右侧是裸加号、**没有来源标**；菜品行没有图标、
/// 右侧只有「菜品库」徽标。于是同一个搜索列表里两种形态，食物也看不出是
/// 内置 / 自建 / 菜品。现在两库共用这一行，固定三件：
///  - 左：40dp 图标（食物按分类取图标；菜品用餐厅图标，浅品牌底圆）；
///  - 中：名称 + 一行副标题（品牌/口径/热量）；
///  - 右：**来源徽标**（食物库 / 菜品库）+ 加号（同位置、同尺寸）。
class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.name,
    required this.subtitle,
    required this.sourceLabel,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.nameKey,
    this.subtitleMaxLines = 1,
  });

  final String name;
  final String subtitle;

  /// 「食物库」/「菜品库」——来源标是固定件，两库必填，不留给调用点省略。
  final String sourceLabel;

  final Widget icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final Key? nameKey;

  /// 副标题最多几行。食物/旧菜品一行够用；**食堂供应要两行**——窗口 +
  /// 「每 100g / 每份多少克 / 一份多少千卡」挤成一行会被省略号截成
  /// 「一份 …」，正好把最关键的份量藏掉（360dp 帧捕获实测）。
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Semantics(
      button: true,
      label: semanticLabel,
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
                    icon,
                    const SizedBox(width: LfDimens.spaceMedium),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            name,
                            key: nameKey,
                            style: LfText.body.copyWith(color: c.foreground),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            subtitle,
                            style: LfText.micro.copyWith(
                              color: c.mutedForeground,
                            ),
                            maxLines: subtitleMaxLines,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: LfDimens.spaceSmall),
                    // 【2026-10-31 用户：菜品库和食物库的标签颜色要有区别】
                    // 食物库 = mint（品牌浅绿），菜品库 = honey（琥珀）——
                    // 同一形态、不同色相，扫一眼就知道结果来自哪个库。
                    if (sourceLabel == '菜品库')
                      LfBadge.honey(
                        sourceLabel,
                        key: Key('search-source-$sourceLabel'),
                      )
                    else
                      LfBadge.mint(
                        sourceLabel,
                        key: Key('search-source-$sourceLabel'),
                      ),
                    const SizedBox(width: LfDimens.spaceXSmall),
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

/// 食物库结果行：统一行 + 分类图标 + 「食物库」来源标。
///
/// 品牌必须进副标题：真实库里同名不同品牌的条目很常见（「米饭」有四条，
/// 116/156/181/338 kcal），只印名称时用户分不清点的是哪条，点错就记错营养。
class _FoodResultRow extends StatelessWidget {
  const _FoodResultRow({required this.food, required this.onTap});

  final FoodRecord food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = food.brand?.trim() ?? '';
    final subtitle =
        '${brand.isEmpty ? '' : '$brand · '}'
        '${food.kcalPer100g.round()} kcal / 100g';
    return _SearchResultRow(
      name: food.name,
      nameKey: Key('search-food-name-${food.id}'),
      subtitle: subtitle,
      sourceLabel: '食物库',
      icon: FoodCategoryIcon(
        category: FoodCategory.classify(name: food.name),
        size: 40,
      ),
      semanticLabel: brand.isEmpty
          ? '添加 ${food.name}'
          : '添加 ${food.name}（$brand）',
      onTap: onTap,
    );
  }
}

/// 食堂供应结果行：统一行 + 窗口副标题 + 「食堂」来源标。
///
/// 副标题必须把「每 100g」和「每份」分开写：用户看到的"一份多少千卡"
/// 只有在份量可信时才有，否则明说未知。
class _SupplyResultRow extends StatelessWidget {
  const _SupplyResultRow({required this.supply, required this.onTap});

  final SupplyCatalogItem supply;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final serving = switch (supply.servingGramsStatus) {
      ServingGramsStatus.known =>
        '一份 ${_num(supply.servingGrams!)}g · '
            '${supply.kcalPerServing!.round()} kcal',
      ServingGramsStatus.estimated => '一份约 ${_num(supply.servingGrams!)}g（估计）',
      ServingGramsStatus.unknown => '每份克数未知（只能按克记）',
    };
    // 两行：窗口一行、口径一行。挤成一行时省略号会把份量吃掉
    // （360dp 帧实测被截成「一份 …」）。
    final subtitle =
        '${supply.windowLabel}\n'
        '${supply.kcalPer100g!.round()} kcal/100g · $serving';
    return _SearchResultRow(
      name: supply.displayName,
      nameKey: Key('search-supply-name-${supply.id}'),
      subtitle: subtitle,
      subtitleMaxLines: 2,
      sourceLabel: '食堂',
      icon: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: LfColors.brandSoft(Theme.of(context).brightness),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.storefront,
          size: 20,
          color: LfColors.mintText(Theme.of(context).brightness),
        ),
      ),
      semanticLabel: '添加食堂供应 ${supply.displayName}（${supply.windowLabel}）',
      onTap: onTap,
    );
  }

  static String _num(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

/// 菜品库结果行：统一行 + 餐厅图标 + 「菜品库」来源标。
class _DishResultRow extends StatelessWidget {
  const _DishResultRow({required this.dish, required this.onTap});

  final DishRecord dish;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle =
        '${DishVisuals.mealSlotLabel(dish.mealSlot)} · ${dish.energyLabel}';
    return _SearchResultRow(
      name: dish.name,
      nameKey: Key('search-dish-name-${dish.id}'),
      subtitle: subtitle,
      sourceLabel: '菜品库',
      // 【2026-10-31 用户：菜品库有照片的需要显示照片缩略图】有图用图，
      // 无图回落餐厅图标——同一 40dp 槽位，两态不改变行几何。
      icon: dish.imagePath == null
          ? Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LfColors.brandSoft(Theme.of(context).brightness),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.restaurant,
                size: 20,
                color: LfColors.mintText(Theme.of(context).brightness),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(LfDimens.radiusMd),
              child: Image.file(
                File(dish.imagePath!),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: LfColors.brandSoft(Theme.of(context).brightness),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.restaurant,
                    size: 20,
                    color: LfColors.mintText(Theme.of(context).brightness),
                  ),
                ),
              ),
            ),
      semanticLabel: '添加菜品 ${dish.name}',
      onTap: onTap,
    );
  }
}

/// 「手动添加食材」入口（2026-10-30 用户：「手动添加食材的按钮和展开内容
/// 太丑了」）。
///
/// 旧件是一枚 28dp 的**虚线小胶囊**（10px 字），压在搜索框下面像个标签，
/// 既不像按钮也不成行。改成与检索结果**同一行形态**的整行入口：
/// 40dp 图标 + 标题 + 一行副标题 + 右侧展开箭头；展开后箭头转成向上。
class _ManualAddRow extends StatelessWidget {
  const _ManualAddRow({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    return Semantics(
      button: true,
      expanded: expanded,
      label: expanded ? '收起手动添加食材' : '展开手动添加食材',
      child: ExcludeSemantics(
        child: Material(
          key: const Key('meal-manual-toggle'),
          color: c.muted,
          borderRadius: BorderRadius.circular(LfDimens.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(LfDimens.radiusMd),
            onTap: onToggle,
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
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: LfColors.brandSoft(brightness),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.edit_note,
                        size: 20,
                        color: LfColors.mintText(brightness),
                      ),
                    ),
                    const SizedBox(width: LfDimens.spaceMedium),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '手动添加食材',
                            style: LfText.body.copyWith(color: c.foreground),
                          ),
                          Text(
                            '库里没有的，自己填名称和营养',
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
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: LfDimens.iconMd,
                      color: c.mutedForeground,
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

/// 记录弹层内的一条可编辑条目（弹层会话内短生命）。
///
/// `sourceType` / `sourceId` 只用于**展示来源与回指**（手动 / 食物库 / 菜品库），
/// 落库仍由 `toDraft` 产出 `MealItemDraft`（既有契约，不含来源字段）。
final class _EditableItem {
  _EditableItem({
    required this.foodName,
    required this.referenceGrams,
    required this.referenceNutrition,
    required double initialGrams,
    this.foodId,
    this.sourceType = 'manual',
    this.sourceId,
    this.supplyId,
    this.servings,
    this.servingGrams,
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
      sourceType: 'food',
      sourceId: food.id,
    );
  }

  /// 食堂供应：默认 1 份，克数 = 该供应的每份克数（不借用别的窗口）。
  factory _EditableItem.fromSupply(SupplyCatalogItem supply) {
    final servingGrams = supply.servingGrams!;
    final draft = NutritionMath.fromSupply(
      supplyId: supply.id,
      displayName: supply.displayName,
      kcalPer100g: supply.kcalPer100g!,
      proteinPer100g: supply.proteinPer100g!,
      carbsPer100g: supply.carbsPer100g!,
      fatPer100g: supply.fatPer100g!,
      servings: 1,
      servingGrams: servingGrams,
      foodId: supply.foodId,
      revisionId: supply.revisionId,
      servingGramsStatus: supply.servingGramsStatus,
    );
    return _EditableItem(
      foodId: supply.foodId,
      foodName: supply.displayName,
      referenceGrams: draft.grams,
      referenceNutrition: draft.nutrition,
      initialGrams: draft.grams,
      sourceType: 'menu_item',
      sourceId: supply.id,
      supplyId: supply.id,
      servings: 1,
      servingGrams: servingGrams,
    );
  }

  factory _EditableItem.fromRecord(MealItemRecord item) => _EditableItem(
    foodId: item.foodId,
    foodName: item.foodName,
    referenceGrams: item.grams,
    referenceNutrition: item.nutrition,
    initialGrams: item.grams,
    sourceType: item.sourceType,
    sourceId: item.sourceId,
    supplyId: item.supplyId,
    servings: item.servings,
    servingGrams: item.servingGrams,
  );

  /// 菜品库的菜：整份口径（[servingGrams] 已在调用点兜到 100g）。
  ///
  /// `dish.kcal` 是**每份**值；这里要的是「[servingGrams] 克这份」的营养，
  /// 所以只能按 `servingGrams / 这份克数` 缩放一次。旧实现再乘
  /// `servingGrams/100`，把 268 kcal/份算成 804 kcal（2026-11-04 修）。
  factory _EditableItem.fromDish(DishRecord dish, double servingGrams) {
    return _EditableItem(
      foodName: dish.name,
      referenceGrams: servingGrams,
      referenceNutrition: dish.nutritionForGrams(servingGrams),
      initialGrams: servingGrams,
      sourceType: 'dish',
      sourceId: dish.id,
    );
  }

  final String? foodId;
  final String foodName;
  final double referenceGrams;
  final NutritionValues referenceNutrition;
  final TextEditingController grams;

  /// `manual` / `food` / `dish` / `menu_item`（写入 `MealItemDraft`）。
  final String sourceType;
  final String? sourceId;

  /// 按供应记餐时的供应 id、份数与每份克数依据（schema 31 快照列）。
  final String? supplyId;
  final double? servings;
  final double? servingGrams;

  MealItemDraft toDraft(double newGrams) {
    final factor = newGrams / referenceGrams;
    // 只有"没改克数"时才保留份数：手改量后份数与克数会自相矛盾。
    final unchanged = (newGrams - referenceGrams).abs() < 1e-9;
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
      sourceType: sourceType,
      sourceId: sourceId,
      supplyId: supplyId,
      servings: unchanged ? servings : null,
      servingGrams: servingGrams,
    );
  }

  void dispose() => grams.dispose();

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();
}

/// 统一检索的一条命中（主食物 / 食堂供应 / 旧菜品库）。
sealed class _SearchHit {
  const _SearchHit();

  factory _SearchHit.food(FoodRecord food) = _FoodHit;
  factory _SearchHit.supply(SupplyCatalogItem supply) = _SupplyHit;
  factory _SearchHit.dish(DishRecord dish) = _DishHit;

  T when<T>({
    required T Function(FoodRecord food) onFood,
    required T Function(SupplyCatalogItem supply) onSupply,
    required T Function(DishRecord dish) onDish,
  }) => switch (this) {
    _FoodHit(:final food) => onFood(food),
    _SupplyHit(:final supply) => onSupply(supply),
    _DishHit(:final dish) => onDish(dish),
  };
}

final class _FoodHit extends _SearchHit {
  const _FoodHit(this.food);
  final FoodRecord food;
}

final class _SupplyHit extends _SearchHit {
  const _SupplyHit(this.supply);
  final SupplyCatalogItem supply;
}

final class _DishHit extends _SearchHit {
  const _DishHit(this.dish);
  final DishRecord dish;
}
