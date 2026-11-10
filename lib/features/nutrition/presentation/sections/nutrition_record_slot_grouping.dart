import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/entrance_item.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
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
    this.onEditSlot,
    this.onAddToSlot,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.selectedItemIds = const {},
    this.onLongPress,
    this.onToggleSelected,
    this.onToggleItemSelected,
    this.onMealsChanged,
  });

  final MealRepository repository;

  /// 查询用的日期(`yyyy-MM-dd`)。
  final String localDate;

  /// 「今天」的判据来源(A 用 `ui.date === state.today` 决定加号与空态文案)。
  final DateTime now;

  /// 【2026-10-31 用户】整卡点击：合并编辑该槽位全部已添加食物。
  /// 回调携带当前槽位记录，避免编辑午餐时误合并全天餐食。
  final void Function(List<MealRecord> records)? onEditSlot;

  /// 槽位头的加号(**仅今天**渲染,A `data-action="meal-add" data-slot`):
  /// 直接走既有 `NutritionActions.editMeal(initialSlot:)` 通道(D19)。
  /// null 时不画加号——宁可少一个入口,也不弹一个只有默认槽位的编辑框。
  final ValueChanged<MealSlot>? onAddToSlot;

  final bool selectionMode;
  final Set<String> selectedIds;
  final Set<String> selectedItemIds;

  /// null = 未接多选(`onDeleteSelected` 未接线)→ 不给长按入口。
  final ValueChanged<MealRecord>? onLongPress;
  final ValueChanged<MealRecord>? onToggleSelected;
  final void Function(MealRecord meal, MealItemRecord item)?
  onToggleItemSelected;

  /// 每次拿到列表时回传最近一帧(批量删除要按 id 还原成完整记录)。
  final ValueChanged<List<MealRecord>>? onMealsChanged;

  bool get _isToday => formatLocalDate(now) == localDate;

  /// 补记窗口（B-3，docs/64 阶段 4）：用户 2026-10-27 裁决「30 天」。
  static const int backfillWindowDays = 30;

  /// 选中日能不能补记：今天，或近 [backfillWindowDays] 天内的过去日期。
  /// **未来日期永远不能**（仓储层 B-2 的守卫也会拒，UI 不给入口）。
  bool get _canAdd {
    // `DateTime.parse` 直接吃 `yyyy-MM-dd`（无时区 = 本地零点），不引新依赖、
    // 也不跨 feature 取 progress 的 parseLocalDate。
    final selected = DateTime.parse(localDate);
    final today = DateTime.parse(formatLocalDate(now));
    if (selected.isAfter(today)) return false;
    return today.difference(selected).inDays <= backfillWindowDays;
  }

  /// 窗口外的过去日期：不画「+」，但**如实说**窗口——默默少一个按钮
  /// 会让用户以为是坏了（诚实口径，docs/64 B-3 判据 3）。
  bool get _showBackfillWindowNote {
    final selected = DateTime.parse(localDate);
    final today = DateTime.parse(formatLocalDate(now));
    return selected.isBefore(today) && !_canAdd;
  }

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
              if (_showBackfillWindowNote)
                Padding(
                  padding: const EdgeInsets.only(bottom: LfDimens.spaceMedium),
                  child: Text(
                    '只支持补记近 $backfillWindowDays 天。更早的日期是历史回看，'
                    '不再改动。',
                    key: const Key('nutrition-record-backfill-window-note'),
                    style: LfText.caption.copyWith(
                      color: context.lf.mutedForeground,
                    ),
                  ),
                ),
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
                    // B-3（docs/64 阶段 4，用户 2026-10-27 裁决「30 天」）：
                    // 加号从「仅今天」放开为「今天或近 30 天内」——写路径本来
                    // 就按选中日，这里只放开 UI 门禁；非今天另给「补记」徽标。
                    backfill: !_isToday && _canAdd && onAddToSlot != null,
                    onEditSlot:
                        bySlot[MealSlot.values[index]]!.isEmpty ||
                            onEditSlot == null
                        ? null
                        : () => onEditSlot!(bySlot[MealSlot.values[index]]!),
                    onAdd: !_canAdd || onAddToSlot == null
                        ? null
                        : () => onAddToSlot!(MealSlot.values[index]),
                    selectionMode: selectionMode,
                    selectedIds: selectedIds,
                    selectedItemIds: selectedItemIds,
                    onLongPress: onLongPress,
                    onToggleSelected: onToggleSelected,
                    onToggleItemSelected: onToggleItemSelected,
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
    required this.backfill,
    this.onEditSlot,
    required this.onAdd,
    required this.selectionMode,
    required this.selectedIds,
    required this.selectedItemIds,
    required this.onLongPress,
    required this.onToggleSelected,
    required this.onToggleItemSelected,
  });

  final MealSlot slot;
  final List<MealRecord> meals;
  final bool isToday;

  /// 非今天但在补记窗口内（槽位头画「补记」徽标）。
  final bool backfill;

  /// 【2026-10-31 用户】整卡点击：合并编辑该槽位全部已添加食物。
  final VoidCallback? onEditSlot;
  final VoidCallback? onAdd;
  final bool selectionMode;
  final Set<String> selectedIds;
  final Set<String> selectedItemIds;
  final ValueChanged<MealRecord>? onLongPress;
  final ValueChanged<MealRecord>? onToggleSelected;
  final void Function(MealRecord meal, MealItemRecord item)?
  onToggleItemSelected;

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
            backfill: backfill,
            // 【2026-10-25（需求 20b 的连带变更）】非空槽位的汇总**不再是
            // 那一串 `N kcal`**：同槽位的多条记录现在合并成一张卡，卡头大号位
            // 写的就是这个合计 ⇒ 写两遍是同一个数字挨着出现两次（取帧复核：
            // 「午餐 444 kcal」正下方又是「午餐 444 kcal」）。
            //
            // 改成只在**多条记录**时说清「几条」（那是卡头没有的新信息）；
            // 单条记录时这里留空（槽位名 + 卡头合计已经说完了）。
            // 空槽位仍是 `尚未记录`（A 的字面值，语义是「无记录 ≠ 零值记录」）。
            // 唯一例外：补记徽章在场时省略——徽章 + 槽位名已把「这不是今天」
            // 说完，再挤「尚未记录」在 2.0× 窄屏会截成「尚…」，且与下方空态
            // 行（「还没记录这一餐」）语义重复。
            summary: meals.isEmpty
                ? (backfill ? '' : '尚未记录')
                // 【2026-10-31 用户：热量直接放在标题晚餐后边】卡内自带头部
                // 行退役（MealRecordCard embedded 不再画「晚餐 + kcal」），
                // 合计 kcal 挪到槽位头标题后面；多条记录时同时说清条数。
                : () {
                    final total = meals.fold(
                      const NutritionValues(
                        kcal: 0,
                        proteinGrams: 0,
                        carbsGrams: 0,
                        fatGrams: 0,
                      ),
                      (sum, meal) => sum + meal.nutrition,
                    );
                    final kcal = '${total.kcal.round()} kcal';
                    return meals.length > 1
                        ? '$kcal · ${meals.length} 条记录'
                        : kcal;
                  }(),
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
            // 【需求 20b（2026-10-25 用户：「午餐就都放一起，不要因为我后边
            // 记的就分开显示」）】**一个槽位一张卡**：把该槽位当日的全部记录
            // 交给同一张卡，卡内按原记录用极淡分隔线分组。
            //
            // 原来是 `for (index < meals.length) MealRecordCard(meal: meals[index])`
            // ——记两次午餐就有两张都写着「午餐」的卡（各自带时间）。现在
            // 只建一张，编辑/删除/多选仍按 `meal.id` 走（见 MealRecordCard）。
            EntranceItem(
              index: 0,
              child: Padding(
                // A `.meal-slot-card .meal-row{padding:2px 0 7px}`。
                padding: const EdgeInsets.only(
                  top: LfDimens.spaceXSmall,
                  bottom: LfDimens.spaceTiny,
                ),
                child: MealRecordCard(
                  // D12:`nutrition-record-meal-card-<i>`(跨槽位全局序号)
                  // 在分组后无意义,已退役;`meal-<id>` 等既有稳定 Key 不动。
                  meals: meals,
                  embedded: true,
                  // 【2026-10-31 用户：整卡点击看全部已添加食物】合并编辑；
                  // 逐条 onEdit/onDelete 已随 ⋮ 菜单整族退役。
                  onTapCard: onEditSlot,
                  selectionMode: selectionMode,
                  selectedIds: selectedIds,
                  selectedItemIds: selectedItemIds,
                  onLongPress: onLongPress,
                  onToggleSelected: selectionMode ? onToggleSelected : null,
                  onToggleItemSelected: selectionMode
                      ? onToggleItemSelected
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
    this.backfill = false,
  });

  final MealSlot slot;
  final String summary;
  final VoidCallback? onAdd;

  /// 非今天但在补记窗口内：槽位名后加「补记」徽标（免得用户以为是今天）。
  final bool backfill;

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
        if (backfill) ...[
          const SizedBox(width: _SlotCard.headingGap),
          // 【N-7（2026-10-29 用户：补记标签太丑，优化设计）】虚框徽标
          // 换成「带图标的 mint 软徽标」：历史图标 + 「补记」二字，语义
          // （这不是今天，是在补往日的账）一眼可读，颜色也不与虚框计划态
          // 徽标（晚餐 · 计划）混同。Key 沿用。
          const LfBadge.mint(
            '补记',
            icon: Icons.history,
            key: Key('nutrition-record-backfill-badge'),
          ),
        ],
        const SizedBox(width: _SlotCard.headingGap),
        // A `>span{flex:1}`:合计占据图标与加号之间的**全部**余量(不只是
        // 文字宽),所以加号恒贴卡右缘。
        // 【2026-10-31】合计从「N 条记录」变成「N kcal(· M 条记录)」后变长了，
        // `maxLines:1 + ellipsis` 会在 320dp×2.0× 把 kcal 截没（用户点名要看
        // 的数字不能截）——改 `FittedBox(scaleDown)`：单行完整、按比例缩小，
        // 与今日页热量行的同一套兜底。
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              summary,
              key: Key('nutrition-record-slot-${slot.storedValue}-total'),
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
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
