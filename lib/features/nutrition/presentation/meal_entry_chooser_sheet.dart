import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_search_field.dart';
import 'package:localfit_ai/core/text/search_text.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/domain/source_badge.dart';

/// 记录餐的两个入口（docs/41 §7「写入路径矩阵」的前两条，用户诉求 R7/R9）。
///
/// 为什么必须分成两个入口：食物库是**每 100g 的事实库**，菜品库/食堂菜是
/// **按份的模板**。混在同一个弹层里时，用户只看到「搜索食物」一个框，
/// 于是永远发现不了食物库（自做饭、包装食品、按食材记账全靠它）。
///
/// 两条路径最终都落到**同一个** `MealRepository.create`——这里只决定默认
/// 份量与默认来源，不产生第二套记账逻辑（docs/40 §3 的硬要求）。
enum MealRecordEntry {
  /// 按食材记录：食物库（每 100g × 克数）。
  byFood('按食材记录', '食物库 · 每 100g × 克数', Icons.scale_outlined),

  /// 按菜品记录：我的菜 / 食堂菜（按份）。
  byDish('按菜品记录', '我的菜 · 按份记入', Icons.restaurant_outlined);

  const MealRecordEntry(this.title, this.subtitle, this.icon);

  final String title;
  final String subtitle;
  final IconData icon;
}

/// 入口选择弹层。点 FAB 先问「记什么」，再进对应的弹层。
///
/// 键：`meal-entry-chooser`（层内根）/ `meal-entry-by-food` / `meal-entry-by-dish`。
class MealRecordEntryChooser extends StatelessWidget {
  const MealRecordEntryChooser({super.key});

  static Future<MealRecordEntry?> show(BuildContext context) =>
      AppSheet.showCustom<MealRecordEntry>(
        context,
        builder: (context) => const MealRecordEntryChooser(),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      key: const Key('meal-entry-chooser'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('记录一餐', style: LfText.headline.copyWith(color: c.cardForeground)),
        const SizedBox(height: LfDimens.spaceSmall),
        Text(
          // 一句话说清两条路的区别——这是本批要解决的核心困惑。
          '按食材记账用食物库（每 100g）；吃现成的菜用我的菜（按份）。',
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        for (final entry in MealRecordEntry.values) ...[
          DesignCard(
            key: Key(
              entry == MealRecordEntry.byFood
                  ? 'meal-entry-by-food'
                  : 'meal-entry-by-dish',
            ),
            onTap: () => Navigator.of(context).pop(entry),
            child: Row(
              children: [
                Icon(entry.icon, size: 22, color: c.primary),
                const SizedBox(width: LfDimens.spaceSmall),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: LfText.bodyStrong.copyWith(
                          color: c.cardForeground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.subtitle,
                        style: LfText.caption.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: c.mutedForeground),
              ],
            ),
          ),
          if (entry != MealRecordEntry.values.last)
            const SizedBox(height: LfDimens.spaceSmall),
        ],
      ],
    );
  }
}

/// 「按菜品记录」的菜品选择弹层：菜品库（我的菜）列表 + 一份确认。
///
/// **份量口径（本轮如实口径）**：`dish_library` 这一轮还是「每份」四列、
/// 没有 `servingGrams` 列，所以记一笔就是**整份**（克数记为
/// [AddDishToMeal.assumedServingGrams] 仅供展示），营养按整份快照写入——
/// 与既有的「加入午餐」一字不差。按克数换算的份量口径在 schema 28 落地后
/// 才成立（docs/40 §2.2），届时改这里一处即可。
class DishMealPickerDialog extends StatefulWidget {
  const DishMealPickerDialog({
    super.key,
    required this.dishes,
    required this.mealSlotLabel,
    this.title = '按菜品记录',
  });

  /// 菜品库全部条目（调用方已读好；弹层自己不查库）。
  final List<DishRecord> dishes;

  /// 餐次文案（复用菜品卡的既有口径，不在本件里再写一份 switch）。
  final String Function(String mealSlot) mealSlotLabel;
  final String title;

  @override
  State<DishMealPickerDialog> createState() => _DishMealPickerDialogState();
}

class _DishMealPickerDialogState extends State<DishMealPickerDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// 本地过滤（弹层已拿到全量 list，不查库——既有约束不变）。
  ///
  /// 口径与食材侧同源：`normalizeSearchText` 后做包含匹配（大小写/全半角/
  /// 空白归一），所以「番茄 牛腩」也能命中「番茄牛腩」。
  List<DishRecord> get _visible {
    final normalized = normalizeSearchText(_query);
    if (normalized.isEmpty) return widget.dishes;
    return [
      for (final dish in widget.dishes)
        if (normalizeSearchText(dish.name).contains(normalized)) dish,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final visible = _visible;
    return Column(
      key: const Key('dish-meal-picker'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: LfText.headline.copyWith(color: c.cardForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        if (widget.dishes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceMedium),
            child: Text(
              // 空态给可行动的信息，不是一句「暂无数据」。
              '菜品库还是空的。先在菜单页把吃过的菜「存为菜品」，或在食堂目录里分析菜品。',
              key: const Key('dish-meal-picker-empty'),
              style: LfText.body.copyWith(color: c.mutedForeground),
            ),
          )
        else ...[
          // `RV4-P1-06`：菜品多了只能滚 ⇒ 加搜索框（原来是整表列表）。
          LfSearchField(
            fieldKey: const Key('dish-meal-picker-search'),
            controller: _search,
            hintText: '搜菜品名（如「番茄」）',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: LfDimens.spaceMedium,
              ),
              child: Text(
                '没有匹配的菜品，换个词试试。',
                key: const Key('dish-meal-picker-no-match'),
                style: LfText.body.copyWith(color: c.mutedForeground),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                key: const Key('dish-meal-picker-list'),
                shrinkWrap: true,
                itemCount: visible.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, thickness: 1, color: c.border),
                itemBuilder: (context, index) {
                  final dish = visible[index];
                  return InkWell(
                    key: Key('dish-meal-picker-item-${dish.id}'),
                    onTap: () => Navigator.of(context).pop(dish),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  dish.name,
                                  style: LfText.bodyStrong.copyWith(
                                    color: c.cardForeground,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${widget.mealSlotLabel(dish.mealSlot)} · '
                                  '${dish.kcal.round()} kcal/份',
                                  style: LfText.caption.copyWith(
                                    color: c.mutedForeground,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 来源徽标与菜品卡同源（docs/41 §7 第四条铁律）。
                          LfSourceBadgePair.forMealSource(
                            dish.source,
                            keyPrefix: 'dish-meal-picker-badge-${dish.id}',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ],
    );
  }
}

/// 「记一份」确认弹层：把 [DishRecord] 说清楚再写库（写库由调用方做）。
///
/// `RV4-P1-06`（D9 同一口径）：餐次从**只读文案**改成**四枚可点胶囊**——
/// 用户点了「记一份」就意味着此刻在吃，此刻是哪一餐由他说了算，不该被菜品
/// 库的存档值锁死。返回值也从 `bool` 改成 [MealSlot?]（null = 取消）。
class DishMealConfirmSheet extends StatefulWidget {
  const DishMealConfirmSheet({
    super.key,
    required this.dish,
    required this.mealSlotLabel,
    this.initialSlot,
  });

  final DishRecord dish;
  final String Function(String mealSlot) mealSlotLabel;

  /// 预选餐次（页面已指定时优先）；null = 用菜品存档的餐次。
  final MealSlot? initialSlot;

  /// 弹层入口：返回用户选定的餐次，取消返回 null。
  static Future<MealSlot?> show(
    BuildContext context, {
    required DishRecord dish,
    required String Function(String mealSlot) mealSlotLabel,
    MealSlot? initialSlot,
  }) => AppSheet.show<MealSlot>(
    context,
    title: '记这一份？',
    content: Builder(
      builder: (context) => DishMealConfirmSheet(
        dish: dish,
        mealSlotLabel: mealSlotLabel,
        initialSlot: initialSlot,
      ),
    ),
    actions: Builder(
      builder: (sheetContext) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          LfTextButton(
            key: const Key('dish-meal-cancel'),
            onPressed: () => Navigator.pop(sheetContext),
            label: '取消',
          ),
          LfPrimaryButton(
            key: const Key('dish-meal-confirm'),
            onPressed: () => Navigator.pop(sheetContext, _slotOf(sheetContext)),
            label: '记一份',
          ),
        ],
      ),
    ),
  );

  /// 从弹层子树里读当前选中餐次（`_SlotPill` 持有状态，动作行在子树外）。
  ///
  /// `AppSheet.show` 的 actions 是独立 `Builder`，拿不到 content 的 State；
  /// 用 `InheritedNotifier` 会把简单事做复杂。这里改成**由 content 自己
  /// 记住选择**并把值放在 `ValueNotifier` 上，actions 直接读它。
  static MealSlot _slotOf(BuildContext sheetContext) =>
      _selectedSlot.value ?? MealSlot.lunch;

  @override
  State<DishMealConfirmSheet> createState() => _DishMealConfirmSheetState();
}

/// 当前弹层的选中餐次（单个弹层同一时刻只开一个，静态单例足够）。
///
/// 【为什么用静态而不是 InheritedWidget】`AppSheet.show` 的 `actions` 在
/// content 之外构建，两者没有共同的 Inherited 祖先（都是 sheet 的兄弟）。
/// 一个 ValueNotifier + 打开时重置，比为了传一个枚举值而改 AppSheet 的接口小。
final _selectedSlot = ValueNotifier<MealSlot?>(null);

class _DishMealConfirmSheetState extends State<DishMealConfirmSheet> {
  late MealSlot _slot;

  @override
  void initState() {
    super.initState();
    _slot = widget.initialSlot ?? mealSlotFromDishSlot(widget.dish.mealSlot);
    _selectedSlot.value = _slot;
  }

  @override
  void dispose() {
    _selectedSlot.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      // 与确认按钮的 Key 区分：内容根用 `-body`，动作钮保留契约名
      // `dish-meal-confirm`（`docs/21` 附录 D1 + `key_contract_test` 都按它找）。
      key: const Key('dish-meal-confirm-body'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.mealSlotLabel(widget.dish.mealSlot)} · '
          '${widget.dish.kcal.round()} kcal',
          style: LfText.bodyStrong.copyWith(color: c.cardForeground),
        ),
        const SizedBox(height: 2),
        Text(
          // 诚实边界：库里没有份量列，就不假装知道这一份有多少克。
          '营养按整份记入（本仓暂未记录这份菜的克数）。',
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        if ((widget.dish.servingWindow ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '供应时段 ${widget.dish.servingWindow}',
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
        ],
        const SizedBox(height: LfDimens.spaceSmall),
        // 记到哪一餐：四枚胶囊（`RV4-P1-06`，D9 同一口径）。
        Wrap(
          key: const Key('dish-meal-slot-row'),
          spacing: LfDimens.spaceSmall,
          runSpacing: LfDimens.spaceSmall,
          children: [
            for (final slot in MealSlot.values)
              LfPillButton(
                key: Key('dish-meal-slot-${slot.name}'),
                label: slot.label,
                selected: _slot == slot,
                onPressed: () {
                  setState(() => _slot = slot);
                  _selectedSlot.value = slot;
                },
              ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        LfSourceBadgePair.forMealSource(
          widget.dish.source,
          keyPrefix: 'dish-meal-confirm-badge',
        ),
      ],
    );
  }
}

/// 菜品库条目的餐次文案（`DishCard.mealSlotLabel` 的同一份口径）。
///
/// 放在这里而不是让两个弹层各自 switch：`dish_library.meal_slot` 存的是
/// 中文槽位名，写入值域由 `DishCard` 侧维护，读侧照抄一份就会漂。
String defaultMealSlotLabel(String mealSlot) => switch (mealSlot) {
  '早餐' => '早餐',
  '午餐' => '午餐',
  '晚餐' => '晚餐',
  '加餐' => '加餐',
  final other => other.isEmpty ? '午餐' : other,
};

/// 把菜品库的**中文槽位**映射回 [MealSlot]（写入路径用）。
MealSlot mealSlotFromDishSlot(String mealSlot) =>
    MealSlot.fromStoredValue(switch (mealSlot) {
      '早餐' => MealSlot.breakfast.storedValue,
      '晚餐' => MealSlot.dinner.storedValue,
      '加餐' => MealSlot.snack.storedValue,
      _ => MealSlot.lunch.storedValue,
    });
