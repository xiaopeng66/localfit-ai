import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/back_navigation.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_scrollbar.dart';
import 'package:localfit_ai/app/design/widgets/record_fab.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_analysis_sliver.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/record_energy_section.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_selection_bar.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_slot_grouping.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/record_trend_card_skeleton.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_source_summary.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_week_section.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_trend_card.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// 记录页：周条、热量、趋势、餐卡与分析共用一个 `CustomScrollView`，窄屏
/// 不因置顶内容挤爆视口。长按多选，批量删除只确认一次，撤销由动作层提供。
class RecordTab extends StatefulWidget {
  const RecordTab({
    super.key,
    required this.mealRepository,
    required this.selectedDate,
    required this.now,
    required this.onSelectDate,
    this.onEditSlotMeals,
    this.onEditTarget,
    this.onDeleteSelected,
    this.onSelectionModeChanged,
    this.onAddToSlot,
    this.loadTrend,
    this.leading,
  });

  final MealRepository mealRepository;
  final DateTime selectedDate;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDate;

  /// 【2026-10-31 用户】整卡点击：合并编辑该槽位全部记录（null = 不接）。
  final void Function(List<MealRecord> records)? onEditSlotMeals;

  /// 点热量卡的「依据」格 → 手动指定营养目标（null = 不接）。
  final VoidCallback? onEditTarget;
  // 【2026-10-31】逐条 onEditMeal/onDeleteMeal 整族退役：编辑=整卡点击
  // [onEditSlotMeals]（合并视图），删除在编辑弹层里逐条进行（垃圾桶）。

  /// 槽位头加号(**仅今天**渲染,A `data-slot`):走既有
  /// `NutritionActions.editMeal(initialSlot:)`(D9/D19 通道)。
  /// null = 不画加号(切片测试与旧装配不传时不改行为)。
  final ValueChanged<MealSlot>? onAddToSlot;

  /// docs/21 §3 批量删除回调（页面接动作层 `NutritionActions.deleteMeals`）。
  /// 不传则隐藏「长按多选」入口，保持现网行为不回退。
  final Future<void> Function(List<MealRecord> selected)? onDeleteSelected;

  /// 【2026-10-31 用户：删除按钮出现时加号就该隐藏】选择态变化上报给页面
  /// （FAB 挂在页级 Stack 上，多选时要隐藏）。null = 调用方不关心（切片测试）。
  final ValueChanged<bool>? onSelectionModeChanged;

  /// 趋势与分析固定取选中日结束的 7 天；自然周的后续日期单独补取，
  /// 截止今天，不把它们计入选中日的平均值与目标统计。
  /// null 时不渲染趋势与分析，但保留日期切换入口。
  final Future<IntakeTrend> Function(int days, DateTime endDate)? loadTrend;

  /// 可选置顶内容；与热量卡保持 `pagePadding` 外部间距。
  final Widget? leading;

  @override
  State<RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends State<RecordTab> {
  /// 长按多选已勾选的 meal.id 集合（多选模式下可暂空，只有取消/删除才退出）。
  final Set<String> _selected = {};

  /// 单独勾选的食物 item.id（与整条记录选择分开；两者 UI 取并集）。
  final Set<String> _selectedItems = {};

  /// 最近一次拿到的趋势。null = 还没到数据（骨架态）。
  IntakeTrend? _trend;
  List<DailyIntakeRecord> _weekRemainder = const [];
  StreamSubscription<void>? _intakeChanges;

  /// 仅最新窗口、最新数据库快照可以发布。
  int _trendRequest = 0;

  /// 最近一帧拿到的当日目标区间。hero、趋势卡、分析卡共用同一份，避免各处
  /// 各取一次流（同一页面上多份快照可能差一帧，读数就会互相矛盾）。
  double? _targetMinKcal;
  double? _targetKcal;

  /// 最近一帧当日餐食：批量删除按 id 还原完整记录，不依赖调用方回传。
  List<MealRecord> _meals = const [];

  /// 多选可停在「已选 0 项」，所以模式不能从集合是否为空反推。
  bool _selectionMode = false;

  /// 返回拦截器的注销函数（initState 注册，见下）。
  VoidCallback? _unregisterBackInterceptor;

  @override
  void initState() {
    super.initState();
    // 【2026-10-31 用户：手势返回要先取消选择，而不是退出应用】系统返回
    // （手势/返回键）经 shell 出口先问这里：多选激活时返回 = 退出多选。
    // 必须在 initState 显式注册——`late final` 初始化器等首次访问才跑，
    // 从不访问就从不注册（dispose 前一刻才注册、等于全程没注册的坑）。
    _unregisterBackInterceptor = AppBackInterceptors.register(() {
      if (!_selectionMode) return false;
      _exitSelection();
      return true;
    });
    _watchIntake();
    _loadTrend();
  }

  void _watchIntake() {
    _intakeChanges?.cancel();
    _intakeChanges = widget.mealRepository.watchIntakeChanges().listen((_) {
      if (mounted) _loadTrend();
    });
  }

  @override
  void didUpdateWidget(RecordTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repositoryChanged = oldWidget.mealRepository != widget.mealRepository;
    if (repositoryChanged) _watchIntake();
    if (repositoryChanged ||
        oldWidget.loadTrend != widget.loadTrend ||
        oldWidget.selectedDate != widget.selectedDate ||
        !DateUtils.isSameDay(oldWidget.now, widget.now)) {
      _trend = null;
      _weekRemainder = const [];
      _loadTrend();
    }
  }

  @override
  void dispose() {
    _unregisterBackInterceptor?.call();
    _intakeChanges?.cancel();
    super.dispose();
  }

  DateTime get _trendWindowEnd => DateUtils.dateOnly(widget.selectedDate);

  /// 选中日所在自然周的周一。
  DateTime get _weekStart {
    final selected = DateUtils.dateOnly(widget.selectedDate);
    return selected.subtract(
      Duration(days: selected.weekday - DateTime.monday),
    );
  }

  DateTime get _weekDataEnd {
    final sunday = _weekStart.add(const Duration(days: 6));
    final today = DateUtils.dateOnly(widget.now);
    return sunday.isBefore(today) ? sunday : today;
  }

  Future<void> _loadTrend() async {
    final request = ++_trendRequest;
    final loader = widget.loadTrend;
    if (loader == null) return;
    final end = _trendWindowEnd;
    final weekEnd = _weekDataEnd;
    try {
      final windows = await Future.wait([
        loader(7, end),
        if (weekEnd.isAfter(end))
          loader(weekEnd.difference(end).inDays, weekEnd),
      ]);
      if (!mounted || request != _trendRequest) return;
      setState(() {
        _trend = windows.first;
        _weekRemainder = windows.length > 1 ? windows.last.records : const [];
      });
    } catch (_) {
      if (!mounted || request != _trendRequest) return;
      setState(() {
        _trend = null;
        _weekRemainder = const [];
      });
    }
  }

  /// 周条数据。
  ///
  /// 未接线趋势加载器时**按空数据构造**（7 列全「无记录」，但列本身、星期
  /// 字与选中态都在）——周条是切换日期的主入口，不能因为趋势没接线就整条
  /// 消失，否则用户翻不到别的日子。
  CalorieTrendBars _weekBars(IntakeTrend? trend) => buildCalorieTrendBars(
    records: [...?trend?.records, ..._weekRemainder],
    endDate: DateUtils.dateOnly(_weekStart).add(const Duration(days: 6)),
    targetMaxKcal: _targetKcal,
  );

  void _onTargetChanged(double? minKcal, double? maxKcal) {
    final changed = maxKcal != _targetKcal || minKcal != _targetMinKcal;
    _targetKcal = maxKcal;
    _targetMinKcal = minKcal;
    if (!changed) return;
    // 兄弟卡在目标流返回前已经按旧值构建；目标变化时补一帧，让趋势徽标
    // 与分析卡同步，而不是等用户翻页后才更新。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _enterOrToggle(MealRecord meal) {
    setState(() {
      _selectionMode = true;
      if (_selected.remove(meal.id)) {
        _selectedItems.removeWhere(
          (id) => meal.items.any((item) => item.id == id),
        );
      } else {
        // 未选或只选了部分食物 → 点分组一律整选。
        _selected.add(meal.id);
        _selectedItems.removeWhere(
          (id) => meal.items.any((item) => item.id == id),
        );
      }
    });
    widget.onSelectionModeChanged?.call(true);
  }

  void _toggleItem(MealRecord meal, MealItemRecord item) {
    setState(() {
      if (_selected.remove(meal.id)) {
        // 从整选中排除当前食物：其余转成逐项选择，而不是整餐全取消。
        for (final other in meal.items) {
          if (other.id != item.id) _selectedItems.add(other.id);
        }
      } else if (!_selectedItems.remove(item.id)) {
        _selectedItems.add(item.id);
      }
    });
  }

  /// 操作条按食物计数；整选记录 = 其全部食物，不重复计个别 item。
  int get _selectedFoodCount {
    var count = _selectedItems.length;
    for (final meal in _meals) {
      if (!_selected.contains(meal.id)) continue;
      count += meal.items.length;
      count -= meal.items
          .where((item) => _selectedItems.contains(item.id))
          .length;
    }
    return count;
  }

  void _exitSelection() {
    if (_selectionMode) {
      setState(() {
        _selected.clear();
        _selectedItems.clear();
        _selectionMode = false;
      });
      widget.onSelectionModeChanged?.call(false);
    }
  }

  Future<void> _confirmBulkDelete() async {
    final selected = _meals
        .where(
          (meal) =>
              _selected.contains(meal.id) ||
              meal.items.any((item) => _selectedItems.contains(item.id)),
        )
        .toList(growable: false);
    final selectedCount = _selectedFoodCount;
    if (selected.isEmpty || selectedCount == 0) return;
    final confirmed = await AppSheet.show<bool>(
      context,
      title: '删除所选食物？',
      content: Text('将删除所选 $selectedCount 项食物，可撤销；未选中的食物会保留。'),
      // 弹层行动档（§3.8）：**破坏性确认 = B7**，次级取消 = B6。
      // `我的.html:524-532` 的「清除所有数据」就是 error 字色的一行——设计稿
      // 里没有实心 error 按钮，所以这里不能用 B2 的实心主色。
      actions: Builder(
        builder: (sheetContext) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(
              label: '取消',
              onPressed: () => Navigator.pop(sheetContext, false),
            ),
            LfDangerButton(
              key: const Key('meals-bulk-delete-confirm'),
              label: '删除',
              onPressed: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    // 先冻结选择快照，再退出多选；退出会清空集合，不能拿清空后的状态决定
    // 是删整餐还是删部分食物。
    final selectedMealIds = Set<String>.of(_selected);
    final selectedFoodIds = Set<String>.of(_selectedItems);
    _exitSelection();
    // 落库由 RecordTab 持有（本就注入 repository）——删除成功后调用
    // onDeleteSelected 作为撤销/提示通道给页面动作层，两条路径分离。
    final deleted = <MealRecord>[];
    for (final meal in selected) {
      try {
        final record = selectedMealIds.contains(meal.id)
            ? await widget.mealRepository.delete(meal.id)
            : await widget.mealRepository.deleteItems(meal.id, {
                for (final item in meal.items)
                  if (selectedFoodIds.contains(item.id)) item.id,
              });
        if (record != null) deleted.add(record);
      } catch (_) {
        // 单项失败继续下一条——批量删除不追求原子性。
      }
    }
    final callback = widget.onDeleteSelected;
    if (callback != null && deleted.isNotEmpty && mounted) {
      await callback(deleted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = formatLocalDate(widget.selectedDate);
    final trend = _trend;
    // 趋势卡：滚动近 7 日（末位 = 选中日）。
    final bars = trend == null
        ? null
        : buildCalorieTrendBars(
            records: trend.records,
            endDate: _trendWindowEnd,
            targetMinKcal: _targetMinKcal,
            targetMaxKcal: _targetKcal,
          );
    // 周条：自然周（周一..周日）。与趋势卡是**两个不同的窗口**，所以不复用
    // `bars`——设计稿的周条列是「一 22 … 日 28」，不是「今天往前数 7 天」。
    final weekBars = _weekBars(trend);

    return Column(
      children: [
        Expanded(
          // 记录列表也挂常显滑条（docs/28 §8.3）：历史的餐次可以很长。
          child: LfScrollbar(
            child: CustomScrollView(
              slivers: [
                // 周条恒渲染（见 [_weekBars]：它是切换日期的主入口），并且是
                // **页首元素**——A 的 `nutritionRecords()` 先画 `.date-strip`
                // 再画 `.selected-date`，热量卡排在它们之下。顶距 12 = A 的
                // `.page{padding-top:12px}`；底距 16 = 页间隙，交给下面的热量卡。
                // 组成见 [NutritionRecordWeekSection]。
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    LfDimens.pagePadding,
                    LfDimens.spaceMedium,
                    LfDimens.pagePadding,
                    LfDimens.pagePadding,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: NutritionRecordWeekSection(
                      bars: weekBars,
                      selectedDate: widget.selectedDate,
                      now: widget.now,
                      onSelect: widget.onSelectDate,
                      // 【N-4】回到今天 = 复用 onSelectDate（同一写入路径，
                      // 把选中日推回今天）。
                      onBackToToday: () => widget.onSelectDate(DateTime.now()),
                    ),
                  ),
                ),
                // 热量卡：A `nutritionRecords()` 里排在周条与日期行之下。
                // 组成与目标流在 RecordEnergySection；目标由本页统一持有，
                // 趋势与分析共享同一快照。
                SliverToBoxAdapter(
                  child: RecordEnergySection(
                    repository: widget.mealRepository,
                    localDate: date,
                    selectedDate: widget.selectedDate,
                    now: widget.now,
                    onTargetChanged: _onTargetChanged,
                    onEditTarget: widget.onEditTarget,
                  ),
                ),
                // 置信摘要（A `.source-summary`）：热量卡之下的**页级一行**
                // （阶段 2B 步骤 4 从分析卡卡尾挪过来）。段间距与 4px 内衬都
                // 在摘要件里，空列表时连同间距整段退场。
                SliverToBoxAdapter(
                  child: NutritionRecordSourceSummary(
                    mealRepository: widget.mealRepository,
                    localDate: date,
                  ),
                ),
                if (widget.leading != null)
                  SliverToBoxAdapter(
                    // docs/29 §P6 需求 12：页首卡与这张卡之间此前外部间距 = 0
                    // （旧 hero 的 20dp 内边距在渐变内部，不算间隔）。
                    child: Padding(
                      padding: const EdgeInsets.only(top: LfDimens.pagePadding),
                      child: widget.leading,
                    ),
                  ),
                // 趋势卡（有趋势数据才渲染）。骨架在首次加载时占位，避免
                // 「卡突然冒出来把列表顶下去」。
                if (bars != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      // 底距 16 = A 的页间隙：趋势卡之下现在是时间线（周条
                      // 已搬到页首，旧装配此处是「趋势 → 周条」12dp）。
                      padding: const EdgeInsets.fromLTRB(
                        LfDimens.pagePadding,
                        LfDimens.pagePadding,
                        LfDimens.pagePadding,
                        LfDimens.pagePadding,
                      ),
                      child: NutritionTrendCard(
                        bars: bars,
                        targetKcal: _targetKcal,
                      ),
                    ),
                  )
                else if (widget.loadTrend != null)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        LfDimens.pagePadding,
                        LfDimens.pagePadding,
                        LfDimens.pagePadding,
                        LfDimens.pagePadding,
                      ),
                      child: RecordTrendCardSkeleton(),
                    ),
                  ),
                // 时间线（A `.meal-timeline`）：竖直排四张槽位卡、卡间 12dp。
                SliverToBoxAdapter(
                  child: NutritionRecordSlotGrouping(
                    repository: widget.mealRepository,
                    localDate: date,
                    now: widget.now,
                    onEditSlot: widget.onEditSlotMeals,
                    onAddToSlot: widget.onAddToSlot,
                    // 供批量删除按 id 还原记录:在 build 里赋值而不是 setState,
                    // 同一帧内读到的就是与屏幕一致的那份列表。
                    onMealsChanged: (meals) => _meals = meals,
                    selectionMode: _selectionMode,
                    selectedIds: _selected,
                    selectedItemIds: _selectedItems,
                    onLongPress: widget.onDeleteSelected == null
                        ? null
                        : _enterOrToggle,
                    onToggleSelected: _enterOrToggle,
                    onToggleItemSelected: _toggleItem,
                  ),
                ),
                // 营养分析卡（有趋势数据才渲染）。
                if (bars != null)
                  NutritionAnalysisSliver(
                    trend: trend!,
                    bars: bars,
                    targetMinKcal: _targetMinKcal,
                    targetMaxKcal: _targetKcal,
                  ),
                // 用无子节点的 SliverPadding 留底：SizedBox 会成为最深叶子，
                // 滑到底会被「内容不得画到遮挡线之下」判红。
                SliverPadding(
                  padding: EdgeInsets.only(
                    // 右下常驻 RecordFab：让最后一行能滚出圆钮覆盖带。
                    bottom: RecordFab.contentClearance(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_selectionMode)
          NutritionRecordSelectionBar(
            count: _selectedFoodCount,
            onDelete: _selectedFoodCount == 0
                ? null
                : () => _confirmBulkDelete(),
            onCancel: _exitSelection,
          ),
      ],
    );
  }
}
