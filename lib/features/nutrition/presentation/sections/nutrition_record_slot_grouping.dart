import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/entrance_item.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_slot_icons.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/meal_card.dart'
    show MealCardSkeleton;
import 'package:localfit_ai/features/nutrition/presentation/sections/meal_record_card.dart';

/// 记录页的**槽位分组**(Round7 A `nutritionRecords()` 的 `.meal-timeline`,
/// docs/33 阶段 2B 步骤 5)。
///
/// A 的结构:四张 `.meal-slot-card`(域序 `['早餐','午餐','晚餐','加餐']`),
/// 每张 = `.slot-heading`(槽位图标 + 槽位名 + 槽位合计 / `尚未记录` + 仅今天
/// 的加号)+ 行区(有记录画行;无记录画一行 `.empty-meal`)。
///
/// **与 A 的两处有意差异**(都在本文件内可溯源):
///
///  * D3:`.meal-slot-card` 的三条 `display:none`(行内图标 / 槽位名 / 千卡)
///    会把克数明细、宏量、来源徽标、备注从界面拿掉 ⇒ 不移植。槽位里的每一
///    餐仍用既有 [MealRecordCard] 渲染**全部**事实。
///  * D16:为免「卡中卡」,[MealRecordCard] 走 `embedded: true` ——去掉
///    `DesignCard` 外壳(描边/阴影/16 内边距)与 `PressableScale`,但点击 /
///    长按 / 多选圈与全部内容、全部 Key 一个不少。
///
/// 多选状态由调用方(`RecordTab`)持有:多选操作条在分组**之外**,两处必须
/// 读同一份状态。
class NutritionRecordSlotGrouping extends StatelessWidget {
  const NutritionRecordSlotGrouping({
    super.key,
    required this.repository,
    required this.localDate,
    required this.now,
    required this.onEdit,
    required this.onDelete,
    this.onAddToSlot,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onLongPress,
    this.onToggleSelected,
    this.onMealsChanged,
  });

  final MealRepository repository;

  /// 查询用的日期(`yyyy-MM-dd`)。
  final String localDate;

  /// 「今天」的判据来源(A 用 `ui.date === state.today` 决定加号与空态文案)。
  final DateTime now;

  final ValueChanged<MealRecord> onEdit;
  final ValueChanged<MealRecord> onDelete;

  /// 槽位头的加号(**仅今天**渲染,A `data-action="meal-add" data-slot`):
  /// 直接走既有 `NutritionActions.editMeal(initialSlot:)` 通道(D19)。
  /// null 时不画加号——宁可少一个入口,也不弹一个只有默认槽位的编辑框。
  final ValueChanged<MealSlot>? onAddToSlot;

  final bool selectionMode;
  final Set<String> selectedIds;

  /// null = 未接多选(`onDeleteSelected` 未接线)→ 不给长按入口。
  final ValueChanged<MealRecord>? onLongPress;
  final ValueChanged<MealRecord>? onToggleSelected;

  /// 每次拿到列表时回传最近一帧(批量删除要按 id 还原成完整记录)。
  final ValueChanged<List<MealRecord>>? onMealsChanged;

  bool get _isToday => formatLocalDate(now) == localDate;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MealRecord>>(
      stream: repository.watchForDate(localDate),
      builder: (context, snapshot) {
        if (snapshot.hasData) onMealsChanged?.call(snapshot.data!);
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: LfDimens.pagePadding,
              vertical: LfDimens.spaceSmall,
            ),
            child: AppErrorText('餐食加载失败,请重试。'),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: LfDimens.pagePadding),
            child: Column(
              children: [
                MealCardSkeleton(),
                SizedBox(height: LfDimens.spaceSmall),
                MealCardSkeleton(),
              ],
            ),
          );
        }
        final meals = snapshot.data!;
        // A 的行序:同槽位内按 `eatenAt` 升序(`watchForDate` 已给域序 +
        // 同槽位内 time 升序,这里只分桶、不重排)。
        final bySlot = <MealSlot, List<MealRecord>>{
          for (final slot in MealSlot.values)
            slot: [
              for (final meal in meals)
                if (meal.slot == slot) meal,
            ],
        };
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: LfDimens.pagePadding),
          // A `.meal-timeline{flex-column;gap:12px}`:四张卡竖直排、间距 12。
          child: Column(
            children: [
              for (var index = 0; index < MealSlot.values.length; index++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: index == MealSlot.values.length - 1
                        ? 0
                        : LfDimens.spaceMedium,
                  ),
                  child: _SlotCard(
                    slot: MealSlot.values[index],
                    meals: bySlot[MealSlot.values[index]]!,
                    isToday: _isToday,
                    onEdit: onEdit,
                    onDelete: onDelete,
                    // A：`ui.date === state.today ? <button ...> : ''` —— 加号
                    // **仅今天**渲染。历史日期是只读回看面，写入口一律不出现。
                    onAdd: !_isToday || onAddToSlot == null
                        ? null
                        : () => onAddToSlot!(MealSlot.values[index]),
                    selectionMode: selectionMode,
                    selectedIds: selectedIds,
                    onLongPress: onLongPress,
                    onToggleSelected: onToggleSelected,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 一张 `.meal-slot-card`。
class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.slot,
    required this.meals,
    required this.isToday,
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
    required this.selectionMode,
    required this.selectedIds,
    required this.onLongPress,
    required this.onToggleSelected,
  });

  final MealSlot slot;
  final List<MealRecord> meals;
  final bool isToday;
  final ValueChanged<MealRecord> onEdit;
  final ValueChanged<MealRecord> onDelete;
  final VoidCallback? onAdd;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<MealRecord>? onLongPress;
  final ValueChanged<MealRecord>? onToggleSelected;

  /// A `.meal-slot-card{padding:8px 12px 12px}`。
  /// 见下方 build 注释:本仓的自有内边距由**内嵌行**承担,见 D16 说明。
  static const double _padTop = 8;
  static const double _padSide = 12;
  static const double _padBottom = 12;

  /// 槽位头图标:28dp 紧贴的图标盒(`.slot-heading>.icon-chip{width:28;height:28}`)
  /// + 18px 图标(`.slot-heading>.icon-chip>svg{width:18;height:18}`)。
  static const double iconChipSize = 28;
  static const double iconGlyphSize = 18;

  /// A `.slot-heading{gap:7px}`。
  static const double headingGap = 7;

  /// A `.empty-meal{min-height:44px;font-size:12px;padding-left:4px}`。
  static const double emptyMinHeight = 44;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final total = meals.fold<double>(
      0,
      (sum, meal) => sum + meal.nutrition.kcal,
    );
    return DesignCard(
      key: Key('nutrition-record-slot-${slot.storedValue}'),
      padding: const EdgeInsets.fromLTRB(
        _padSide,
        _padTop,
        _padSide,
        _padBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SlotHeading(
            slot: slot,
            // A:`rows.length ? format(sum)+' kcal' : '尚未记录'`。
            summary: meals.isEmpty
                ? '尚未记录'
                : '${withThousandsSeparator(total.round())} kcal',
            onAdd: onAdd,
          ),
          if (meals.isEmpty)
            // A `.empty-meal`:今天「还没记录这一餐」/ 历史「当天没有这餐记录」。
            // `min-height 44` 让这一行本身也是可点高度;此处不挂动作(空态行
            // 在 A 里是 `<p>`,记录入口是槽位头的加号)。
            Container(
              key: Key('nutrition-record-slot-${slot.storedValue}-empty'),
              constraints: const BoxConstraints(minHeight: emptyMinHeight),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: LfDimens.spaceXSmall),
              child: Text(
                isToday ? '还没记录这一餐' : '当天没有这餐记录',
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            )
          else
            for (var index = 0; index < meals.length; index++)
              EntranceItem(
                index: index,
                child: Padding(
                  // A `.meal-slot-card .meal-row{padding:2px 0 7px}`。
                  padding: EdgeInsets.only(
                    top: index == 0 ? LfDimens.spaceXSmall : 0,
                    bottom: LfDimens.spaceTiny,
                  ),
                  child: MealRecordCard(
                    // D12:`nutrition-record-meal-card-<i>`(跨槽位全局序号)
                    // 在分组后无意义,已退役;`meal-<id>` 等既有稳定 Key 不动。
                    meal: meals[index],
                    embedded: true,
                    onEdit: () => onEdit(meals[index]),
                    onDelete: () => onDelete(meals[index]),
                    selectionMode: selectionMode,
                    selected: selectedIds.contains(meals[index].id),
                    onLongPress: onLongPress == null
                        ? null
                        : () => onLongPress!(meals[index]),
                    onToggleSelected: selectionMode
                        ? () => onToggleSelected?.call(meals[index])
                        : null,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// A `.slot-heading`:图标(28 无底 + 18px)+ 槽位名(14 w700)+ 合计
/// (12 muted,`flex:1`)+(仅今天)44dp 加号。
class _SlotHeading extends StatelessWidget {
  const _SlotHeading({
    required this.slot,
    required this.summary,
    required this.onAdd,
  });

  final MealSlot slot;
  final String summary;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Row(
      children: [
        // `.slot-heading>.icon-chip{background:none}`:**无底色**的图标盒。
        SizedBox(
          width: _SlotCard.iconChipSize,
          height: _SlotCard.iconChipSize,
          child: Icon(
            slot.icon,
            size: _SlotCard.iconGlyphSize,
            color: c.mutedForeground,
          ),
        ),
        const SizedBox(width: _SlotCard.headingGap),
        Text(
          slot.label,
          // A 的 `.slot-heading h2{font-size:14px}`,而 `styles.css` 只给
          // `h1,h2,h3,p{margin:0}`——没有字重覆盖 ⇒ 浏览器默认 **bold**(700)。
          // 本仓字阶只有 w400/500/600 三档(docs/21 §2.6.2),14px 的「粗」
          // 档即 `bodyStrong`(w600);按 token 收敛,不新造 w700。
          style: LfText.bodyStrong.copyWith(color: c.cardForeground),
        ),
        const SizedBox(width: _SlotCard.headingGap),
        // A `>span{flex:1}`:合计占据图标与加号之间的**全部**余量(不只是
        // 文字宽),所以加号恒贴卡右缘。
        Expanded(
          child: Text(
            summary,
            key: Key('nutrition-record-slot-${slot.storedValue}-total'),
            style: LfText.caption.copyWith(color: c.mutedForeground),
            maxLines: 1,
            // 2.0× 窄屏:合计最长「尚未记录」(≈96dp),与槽位名并排仍有余量;
            // 极端字号下按 A 的 `flex:1` 语义让位而不是溢出。
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onAdd != null) ...[
          const SizedBox(width: LfDimens.spaceXSmall),
          // A `.icon-button{width:44px;height:44px}` + `icon('plus',18)`。
          // 用 `Semantics`+`GestureDetector` 而不是 `IconButton`:后者会带来
          // M3 的 48dp 最小盒与水波纹,44 是本稿的实测值(与今日页顶栏同一
          // 处置,见 `LfCircleIconButton`)。
          Tooltip(
            message: '记录${slot.label}',
            excludeFromSemantics: true,
            child: Semantics(
              label: '记录${slot.label}',
              button: true,
              onTap: onAdd,
              container: true,
              child: GestureDetector(
                key: Key('nutrition-record-slot-${slot.storedValue}-add'),
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTap: onAdd,
                child: SizedBox(
                  width: LfDimens.minTouchTarget,
                  height: LfDimens.minTouchTarget,
                  child: Icon(
                    Icons.add,
                    size: _SlotCard.iconGlyphSize,
                    color: c.mutedForeground,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
