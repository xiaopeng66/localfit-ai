import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/pressable_scale.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 记录页餐食卡（docs/21 §5.2 MealCard，3.1 唯一卡片形态）。
///
/// 结构（自上而下）：餐次 + 合计 kcal（embedded 时整行让给槽位头）／ 逐条
/// 菜品行（右侧挂该项**主要宏量**的彩点）／ 分隔线 ／ 备注。
///
/// 「主要宏量」= 该项热量贡献最大的宏量（4/4/9 kcal/g 换算），不是固定写
/// 蛋白质——否则一碗米饭会被标成「碳水 25g」之外还挂个蛋白质彩点，与设计
/// 稿每行只挂一个点不符。
///
/// **2026-10-14(docs/33 阶段 2B D16)**:新增 [embedded] 形态,供记录页的槽位
/// 分组卡内使用。它去掉 `DesignCard` 外壳与 `PressableScale`(避免**卡中
/// 卡**),但保留点击 / 长按 / 多选圈、全部内容与全部 Key。默认 false =
/// 独立白卡,既有调用点行为不变。
///
/// **2026-10-25（需求 20）的两处改动**（用户原话见 `docs/60` §6.6）：
/// 1. **只显示热量**：原来底行那串「蛋白质 X · 碳水 Y · 脂肪 Z」被
///    `Flexible` + `maxLines: 1` + ellipsis 挤成「蛋白质 1…」——用户点名
///    「可以不显示三宏量，只显示热量」。那串文字整行退役，宏量改为
///    **读屏语义**（数字不丢，只是不再占卡面）；
/// 2. **同名餐次合并成一张卡 + 去掉卡头时间**：`for (index < meals.length)`
///    原本一条记录一张卡（各自带 `HH:mm`），用户后边再记一次午餐就多出一张
///    「午餐」卡。现在**一个槽位一张卡**：卡内按原记录用极淡分隔线分组，
///    食物都在一起；编辑/删除/多选仍按**原 `meal.id`** 定位（卡内每个分组
///    都带该记录的 Key 与圈）。
class MealRecordCard extends StatelessWidget {
  const MealRecordCard({
    super.key,
    required this.meals,
    this.onTapCard,
    this.embedded = false,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.selectedItemIds = const {},
    this.onLongPress,
    this.onToggleSelected,
    this.onToggleItemSelected,
  });

  /// 同一槽位（同一天同一餐次）的**全部**记录，按 `eatenAt` 升序。
  ///
  /// 空列表不该出现在这里（调用方只在该槽位有记录时建卡）；防御性当作没有。
  final List<MealRecord> meals;

  /// 【2026-10-31 用户：右下角三个点删掉 + 每条食物不要单独点开编辑】
  /// 逐条 `onEdit`/`onDelete`/⋮ 菜单整族退役——编辑入口是**整卡点击**
  /// [onTapCard]（合并编辑该槽位全部记录），删除在编辑弹层里逐条进行
  /// （垃圾桶按钮）；记录级操作只剩长按进多选。
  final VoidCallback? onTapCard;

  /// 内嵌形态(阶段 2B D16):宿主本身已经是卡(记录页槽位分组卡)时用。
  /// 去掉 `DesignCard` 外壳与 `PressableScale`,行内容与 Key 不变。
  final bool embedded;

  /// docs/21 §3 多选模式:点击切换勾选、勾选圈常驻左侧;进入模式靠长按。
  final bool selectionMode;

  /// 已选中的整条记录 id（按 `meal.id`）。
  final Set<String> selectedIds;

  /// 已单独选中的食物 id（按 `MealItemRecord.id`）。整条记录已选时，其食物
  /// 无须再进这个集合；[MealRecordCard] 的勾选态取两者的并集。
  final Set<String> selectedItemIds;
  final ValueChanged<MealRecord>? onLongPress;

  /// 多选模式下点击记录分组 = 切换整条记录。
  final ValueChanged<MealRecord>? onToggleSelected;

  /// 多选模式下点击某个食物 = 只切换该食物，删除不会波及其他食物。
  final void Function(MealRecord meal, MealItemRecord item)?
  onToggleItemSelected;

  /// 底行备注的**最小可读宽度**（2026-10-26 看图复核缺陷 7）。
  ///
  /// 320dp × 2.0× 时两枚来源徽标会吃光底行：备注若拿不到这个宽度，就整块
  /// 换到下一行拿满整行宽（见 build 里的 `Wrap`），否则会被压成一字一列。
  /// 104 ≈ 2.0× 下四个字——低于它，「食堂二楼」就竖起来了。
  static const double minNotesWidth = 104;

  /// 该项的「主要宏量」：按 4/4/9 热量贡献取最大者。
  static MacroKind dominantMacro(NutritionValues nutrition) {
    final protein = nutrition.proteinGrams * 4;
    final carbs = nutrition.carbsGrams * 4;
    final fat = nutrition.fatGrams * 9;
    if (protein >= carbs && protein >= fat) return MacroKind.protein;
    if (carbs >= fat) return MacroKind.carbs;
    return MacroKind.fat;
  }

  /// 整卡合计（合并后是**所有记录之和**）。
  NutritionValues get _total => meals.fold(
    const NutritionValues(kcal: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0),
    (sum, meal) => sum + meal.nutrition,
  );

  /// 卡根 Key：第一条记录的 id（单一记录时与既有 `meal-<id>` 语义一致）。
  ///
  /// **`meal-<id>` 落在卡内的「记录分组」上**（不只是卡根）：合并后一条记录
  /// 仍然要有自己的定位点——点击/长按/勾选都按它走。
  String get _cardKeySeed => meals.isEmpty ? 'none' : meals.first.id;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final total = _total;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 设计稿是 `flex items-center justify-between`:左餐次、右合计 kcal。
        // 【需求 20b】左边**不再有时间**（`_clockLabel` 退役）——用户原话
        // 「去掉时间显示，午餐就都放一起，不要因为我后边记的就分开显示」。
        //
        // 【为什么用 Row + Expanded 而不是 Wrap】取帧复核发现 `Wrap` 的
        // `spaceBetween` 在这里没有把两端推开（读出来是「午餐444 kcal」黏在
        // 一起）。`Row` + `Expanded(餐次)` 让 kcal 恒贴右缘，几何确定。
        // 【2026-10-31 用户：标题晚餐下边还有一行显示晚餐和热量，不需要】
        // embedded（记录页槽位卡）时这一行整行退役——槽位头已经写着
        // 「晚餐 · 合计 kcal」，再写一遍是同一个数字出现两次。kcal 移到
        // 槽位头（见 nutrition_record_slot_grouping 的 summary）。
        if (!embedded)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  meals.isEmpty ? '' : meals.first.slot.label,
                  style: LfText.bodyStrong.copyWith(color: c.cardForeground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              // 热量写成「大数字 + 小单位」，与今日页/趋势卡的数字语言一致。
              // 【需求 20】三宏量退场后这里**只剩热量**，用户明确要的就是它。
              Semantics(
                // 三宏量从视觉让位到读屏（需求 20 第 5 条）：数字不丢，只是不再
                // 占卡面（原来那串被挤成省略号，等于既没显示也读不全）。
                container: true,
                label: _macroSemanticLabel(total),
                // 大字号窄屏：热量按比例缩小也不换行（同 `LfStatTile` 的兜底）。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${total.kcal.round()}',
                        key: Key('meal-kcal-$_cardKeySeed'),
                        style: LfText.title.copyWith(color: c.cardForeground),
                      ),
                      const SizedBox(width: LfDimens.spaceMicro),
                      Text(
                        'kcal',
                        style: LfText.micro.copyWith(color: c.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        if (meals.any((meal) => meal.items.isNotEmpty)) ...[
          const SizedBox(height: LfDimens.spaceMedium),
          for (var index = 0; index < meals.length; index++) ...[
            // 【需求 20b】记录之间的**极淡分隔线**：视觉上仍是一张卡、食物都
            // 在一起，但「这是两次记录」这件事没被抹掉（编辑/删除按记录走）。
            if (index > 0 && meals[index - 1].items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: LfDimens.spaceSmall),
                child: Divider(
                  key: Key('meal-merge-divider-${meals[index].id}'),
                  height: 1,
                  thickness: 1,
                  color: c.border.withValues(alpha: 0.5),
                ),
              ),
            _RecordGroup(
              meal: meals[index],
              selectionMode: selectionMode,
              selected: selectedIds.contains(meals[index].id),
              // 【2026-10-31 用户：每条食物不要单独点开编辑】非多选时组行
              // 不再吃掉点击（编辑走整卡 [onTapCard]）；多选模式点组行仍是
              // 勾选切换（勾选圈太小，点行更顺手）。
              onTap: selectionMode ? onToggleSelected : null,
              onLongPress: onLongPress,
              selectedItemIds: selectedItemIds,
              onToggleItem: onToggleItemSelected,
            ),
          ],
        ],
        const SizedBox(height: LfDimens.spaceSmall),
        Container(height: 1, color: c.border),
        const SizedBox(height: LfDimens.spaceSmall),
        Row(
          children: [
            // 【2026-10-26 看图复核缺陷 7（320dp × 2.0×）】底行原来是一个
            // `Row`：两枚来源徽标 + `Expanded(备注)` + 管理菜单。大字号下两枚
            // 徽标就把宽度吃光，备注被压成**一字一列**（「食/堂/二/楼」竖排）、
            // 菜单也被挤到边框上——不好看，更读不出来。
            //
            // 改成 `Wrap` + 「备注至少要有可读宽度」（[minNotesWidth]）：放不下
            // 就整块换到下一行、拿满整行宽（菜单留在右缘、不受影响）；1.0× 下
            // 通常仍在同一行，既有观感不变。
            Expanded(
              child: Wrap(
                spacing: LfDimens.spaceSmall,
                runSpacing: LfDimens.spaceXSmall,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // 【2026-10-29（N-1，用户：「AI估算这东西为什么要出现在
                  // 这里…已确认有什么用」）】来源徽标从餐卡**撤下**——它描述
                  // 的是记录来源，不是用户需要天天看的运营信息；事实保留在
                  // `sourceType` 列与编辑弹层里。备注同理：自动长备注不再写
                  // 入（见 `AddDishToMeal._noteFor`），用户自己的备注仍显示。
                  if (_notesText case final notes?)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: minNotesWidth,
                      ),
                      child: Text(
                        notes,
                        key: Key('meal-notes-$_cardKeySeed'),
                        // 【需求 20】三宏量退场后底行宽松了：**不再省略**。
                        // 用户看到的每一句备注都是完整的（原来是 `maxLines: 1`
                        // + ellipsis，与三宏量抢同一行的宽度）。
                        style: LfText.caption.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 【2026-10-31 用户：右下角三个点删掉】逐条 ⋮ 菜单退役——编辑
            // 入口改为**整卡点击**（合并编辑该槽位全部已添加食物，见
            // [onTapCard]），删除在编辑弹层里逐条进行（垃圾桶按钮）。
          ],
        ),
      ],
    );
    // 内嵌形态(D16):宿主(记录页槽位卡)已经是卡,这里不再套第二层
    // `DesignCard`(描边 + 阴影 + 16 内边距会变成「卡中卡」),也不要
    // `PressableScale`(缩放动画在卡内会像整卡在抖)。点击 / 长按与全部
    // 内容、全部 Key 一个不少——**点击落在卡内的记录分组上**（见
    // [_RecordGroup]），卡本身不再是可点区（两条记录时「点卡」是歧义的）。
    // 【2026-10-31 用户：整卡点击后显示所有已添加的食物】整卡可点（多选
    // 模式下仍由勾选圈接管），触发 [onTapCard] 合并编辑。
    final tappable = onTapCard == null || selectionMode
        ? content
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTapCard,
            child: content,
          );
    if (embedded) {
      return KeyedSubtree(
        key: Key('meal-card-$_cardKeySeed'),
        // 【需求 20a 读屏契约（2026-10-25）在 embedded 下仍要成立】卡头热量
        // 行整行退役（用户 2026-10-31：kcal 直接放槽位头标题后边），但三宏量
        // 合计的读屏语义不能跟着丢——挂到卡根上：视觉不占位，数字不丢。
        child: Semantics(
          container: true,
          // 卡面上没有 kcal 数字了（在槽位头），读屏面板必须自己把热量补全：
          // 「热量与宏量是同一个数字面板的读法」（需求 20a 契约）。
          label: '合计 ${total.kcal.round()} kcal、${_macroSemanticLabel(total)}',
          child: tappable,
        ),
      );
    }
    return PressableScale(
      child: DesignCard(key: Key('meal-card-$_cardKeySeed'), child: tappable),
    );
  }

  /// 多条记录的备注并成一句（每条都不丢；空备注跳过）。
  String? get _notesText {
    final notes = [
      for (final meal in meals)
        if ((meal.notes ?? '').trim().isNotEmpty) meal.notes!.trim(),
    ];
    return notes.isEmpty ? null : notes.join(' · ');
  }

  /// 合计三宏量的读屏文案（视觉不占位，读屏仍能拿到事实）。
  static String _macroSemanticLabel(NutritionValues total) =>
      '蛋白质 ${_grams(total.proteinGrams)} 克、'
      '碳水 ${_grams(total.carbsGrams)} 克、'
      '脂肪 ${_grams(total.fatGrams)} 克';
}

/// 卡内**一条原始记录**的分组（需求 20b）：自己的 Key、自己的勾选圈、
/// 自己的菜品行。
///
/// 【点击归属（2026-10-31 起）】普通态组行**不再**吃点击——编辑入口是整卡
/// [MealRecordCard.onTapCard]（合并编辑该槽位全部记录）。多选模式下点组行
/// 切换勾选（勾选圈太小，点行更顺手），长按进多选不变。
///
/// 【2026-10-31 用户：餐卡逐食物勾选删除】多选状态下每条食物行左侧也有
/// 勾选圈；食物选中状态独立于记录分组，不再是「只能整餐勾」。
class _RecordGroup extends StatelessWidget {
  const _RecordGroup({
    required this.meal,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.selectedItemIds,
    required this.onToggleItem,
  });

  final MealRecord meal;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<MealRecord>? onTap;
  final ValueChanged<MealRecord>? onLongPress;

  final Set<String> selectedItemIds;
  final void Function(MealRecord meal, MealItemRecord item)? onToggleItem;

  @override
  Widget build(BuildContext context) {
    // 【2026-10-31 用户：每个食物独立勾选】组头不再画第二枚「整组圈」：
    // 首行会并排出现两枚圈，既重复又分不清点哪个。每条食物各一枚圈；点
    // 组行（不在圈上）仍是整组切换，长按仍进多选。
    return GestureDetector(
      key: Key('meal-${meal.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => onTap!(meal),
      onLongPress: onLongPress == null ? null : () => onLongPress!(meal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in meal.items)
            Padding(
              padding: const EdgeInsets.only(bottom: LfDimens.spaceSmall),
              child: _ItemRow(
                item: item,
                selected: selected || selectedItemIds.contains(item.id),
                onToggle: selectionMode && onToggleItem != null
                    ? () => onToggleItem!(meal, item)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// 单条菜品行：菜名 + 克数（左）／ 主要宏量彩点（右）。
///
/// 多选状态下最左侧多一枚 **20dp 勾选圈**（与组头圈同一几何与选中色）：
/// 点它只切换当前食物的勾选，不影响同餐其他食物。
class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.selected,
    required this.onToggle,
  });

  final MealItemRecord item;
  final bool selected;

  /// null = 普通态（不画圈）；非 null = 只切换当前这个食物。
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final macro = MealRecordCard.dominantMacro(item.nutrition);
    final (color, grams, label) = switch (macro) {
      MacroKind.protein => (c.protein, item.nutrition.proteinGrams, '蛋白质'),
      MacroKind.carbs => (c.carbs, item.nutrition.carbsGrams, '碳水'),
      MacroKind.fat => (c.fat, item.nutrition.fatGrams, '脂肪'),
    };
    return GestureDetector(
      key: Key('meal-food-${item.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: Row(
        children: [
          if (onToggle != null)
            Padding(
              padding: const EdgeInsets.only(
                right: LfDimens.spaceSmall,
                top: 2,
              ),
              child: _SelectionCircle(
                key: Key('meal-food-select-circle-${item.id}'),
                selected: selected,
              ),
            ),
          Expanded(
            child: Text(
              // 每项一行「名称 克数g」——克数只出现一次，宏量只留行尾那枚彩点。
              '${item.foodName} ${_grams(item.grams)}g',
              style: LfText.body.copyWith(color: c.cardForeground),
              // 2026-10-14(docs/33 阶段 2B,2A 渲染审看登记的缺陷 3):原先
              // `maxLines: 1 + ellipsis` 会把长菜名裁成「番茄牛腩煲 32...」。
              // 数据必须原样交给界面,截断只能由渲染层做——而这里正确的做法是
              // **折行扩高**:行高随内容长,克数/宏量点/读屏语义都不动。
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          // 主导宏量：**只留 8dp 彩点**（色标），不再在项行里再报一次克数
          // ——每行两个数字（食物克数 + 宏量克数）在条目多时互相干扰，而食物
          // 克数才是这一行的主信息。
          // 读屏仍把彩点补成完整一句（小彩点不能是唯一信息来源，docs/21 §2.6.3）。
          Semantics(
            label: '主要$label ${_grams(grams)} 克',
            child: ExcludeSemantics(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 20dp 勾选圈（与组头圈**同一几何与选中色**：圈 20、对勾 14、品牌绿实心）。
///
/// 抽出来是因为它在两处出现（组头、每条食物），两处必须长得一模一样——
/// 复制一份尺寸常量迟早会漂成 20 / 22。
class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? LfColors.brandStrong(brightness) : context.lf.muted,
      ),
      child: selected
          ? Icon(
              Icons.check,
              size: 14,
              color: LfColors.onBrandStrong(brightness),
            )
          : null,
    );
  }
}

enum MacroKind { protein, carbs, fat }

/// 克数显示：整数不拖小数点（与页面既有格式一致）。
String _grams(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
