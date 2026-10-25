import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_scrollbar.dart';
import 'package:localfit_ai/app/design/widgets/record_fab.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_analysis_sliver.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_energy_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_selection_bar.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_slot_grouping.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_source_summary.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_week_section.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_trend_card.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// 记录页的热量卡、趋势、周条、餐卡与分析共用一个 `CustomScrollView`，
/// 避免窄屏与大字号下置顶内容把列表挤出视口。胶囊行由 `NutritionPage` 持有。
/// 长按进入多选；批量删除只确认一次，撤销由页面动作层提供。
class RecordTab extends StatefulWidget {
  const RecordTab({
    super.key,
    required this.mealRepository,
    required this.selectedDate,
    required this.now,
    required this.onSelectDate,
    required this.onEditMeal,
    required this.onDeleteMeal,
    this.onDeleteSelected,
    this.onReuseHistory,
    this.onAddToSlot,
    this.loadTrend,
    this.leading,
  });

  final MealRepository mealRepository;
  final DateTime selectedDate;
  final DateTime now;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<MealRecord> onEditMeal;
  final ValueChanged<MealRecord> onDeleteMeal;

  /// 槽位头加号(**仅今天**渲染,A `data-slot`):走既有
  /// `NutritionActions.editMeal(initialSlot:)`(D9/D19 通道)。
  /// null = 不画加号(切片测试与旧装配不传时不改行为)。
  final ValueChanged<MealSlot>? onAddToSlot;

  /// docs/21 §3 批量删除回调（页面接动作层 `NutritionActions.deleteMeals`）。
  /// 不传则隐藏「长按多选」入口，保持现网行为不回退。
  final Future<void> Function(List<MealRecord> selected)? onDeleteSelected;

  /// 「复用历史餐食」二级流程（页面接 `NutritionActions.reuseMeal`）。
  final VoidCallback? onReuseHistory;

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

  /// 最近一帧拿到的当日餐食。批量删除要按 id 还原成完整记录，操作条却只
  /// 持有计数——用列表自身的快照做映射，不再依赖调用方回传（早期版本传了
  /// 空列表进去，确认框永远弹不出来）。
  List<MealRecord> _meals = const [];

  /// 多选模式可以停在「已选 0 项」（全部取消勾选后仍在模式内），所以模式
  /// 由独立的 [_selectionMode] 记，不能从 `_selected.isNotEmpty` 推。
  bool _selectionMode = false;

  @override
  void initState() {
    super.initState();
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

  void _enterOrToggle(MealRecord meal) {
    setState(() {
      _selectionMode = true;
      if (!_selected.remove(meal.id)) _selected.add(meal.id);
    });
  }

  void _exitSelection() {
    if (_selectionMode) {
      setState(() {
        _selected.clear();
        _selectionMode = false;
      });
    }
  }

  Future<void> _confirmBulkDelete() async {
    final selected = _meals
        .where((meal) => _selected.contains(meal.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final confirmed = await AppSheet.show<bool>(
      context,
      title: '删除所选餐食？',
      content: Text('将删除所选 ${selected.length} 项餐食记录，可撤销。'),
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
    _exitSelection();
    // 落库由 RecordTab 持有（本就注入 repository）——删除成功后调用
    // onDeleteSelected 作为撤销/提示通道给页面动作层，两条路径分离。
    final deleted = <MealRecord>[];
    for (final meal in selected) {
      try {
        final record = await widget.mealRepository.delete(meal.id);
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
                      onReuseHistory: widget.onReuseHistory,
                    ),
                  ),
                ),
                // 热量卡：A `nutritionRecords()` 里排在周条与日期行之下。
                // 页级左右各 16dp（A `.page{padding:16px}`）：旧装配的页首是
                // 全宽 hero（渐变铺满整宽、内边距在渐变内部），sliver 上从来
                // 没有横向内衬——换成共享白卡后卡就贴到屏幕两边（阶段 2B
                // 步骤 6 审看发现的缺陷 ⑤）。
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LfDimens.pagePadding,
                    ),
                    child: StreamBuilder<DailyNutritionSummary>(
                      stream: widget.mealRepository.watchNutritionForDate(date),
                      builder: (context, snapshot) {
                        final summary = snapshot.data;
                        // 目标在 build 里赋值而非 setState：同一帧内热量卡、趋势卡、
                        // 分析卡读到的就是同一份目标。
                        final target = summary?.target;
                        if (snapshot.hasData) {
                          final nextMax = target?.calorieMaxKcal;
                          final nextMin = target?.calorieMinKcal;
                          // 兄弟卡（趋势/分析）的 widget 是在本 builder 运行**之前**
                          // 就按旧值构造好的，所以目标从无到有（或变了）时必须补排
                          // 一帧：否则「达标 N/7」徽标与「摄入 vs 目标 N kcal」会停在
                          // 「尚未设定目标」，直到用户翻页/切 tab 才自己刷新。
                          final changed =
                              nextMax != _targetKcal ||
                              nextMin != _targetMinKcal;
                          _targetKcal = nextMax;
                          _targetMinKcal = nextMin;
                          if (changed) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() {});
                            });
                          }
                        }
                        if (snapshot.hasError) {
                          return const Padding(
                            padding: EdgeInsets.all(LfDimens.pagePadding),
                            child: AppErrorText('当日营养加载失败。'),
                          );
                        }
                        return NutritionRecordEnergyCard(
                          consumed:
                              summary?.consumed ??
                              const NutritionValues(
                                kcal: 0,
                                proteinGrams: 0,
                                carbsGrams: 0,
                                fatGrams: 0,
                              ),
                          target: target,
                          selectedDate: widget.selectedDate,
                          now: widget.now,
                        );
                      },
                    ),
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
                      child: _TrendCardSkeleton(),
                    ),
                  ),
                // 时间线（A `.meal-timeline`）：竖直排四张槽位卡、卡间 12dp。
                SliverToBoxAdapter(
                  child: NutritionRecordSlotGrouping(
                    repository: widget.mealRepository,
                    localDate: date,
                    now: widget.now,
                    onEdit: widget.onEditMeal,
                    onDelete: widget.onDeleteMeal,
                    onAddToSlot: widget.onAddToSlot,
                    // 供批量删除按 id 还原记录:在 build 里赋值而不是 setState,
                    // 同一帧内读到的就是与屏幕一致的那份列表。
                    onMealsChanged: (meals) => _meals = meals,
                    selectionMode: _selectionMode,
                    selectedIds: _selected,
                    onLongPress: widget.onDeleteSelected == null
                        ? null
                        : _enterOrToggle,
                    onToggleSelected: _enterOrToggle,
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
                // 底部预留：extendBody 后内容会延伸到贴底栏下方。
                //
                // 用**无子节点**的 [SliverPadding] 而不是 `SliverToBoxAdapter
                // (child: SizedBox(...))`：后者会成为全页最深的**渲染叶子**，
                // 滑到底时它本身就落在栏体下方，被 `route_shell_navigation_test`
                // 的「内容不得画到遮挡线之下」判红。SliverPadding 直接产出
                // SliverGeometry、不建子节点，预留量一致且不污染叶子判据。
                SliverPadding(
                  padding: EdgeInsets.only(
                    // RV2-P2-06：记录页右下有常驻圆钮（`RecordFab`，顶边在
                    // 手势带 + 146），只留 navReserve 时最后一行会被它压住
                    // （2.0× 下实测压住「还可摄入 X kcal」）。这里让内容能
                    // 滚出圆钮的覆盖带。
                    bottom: RecordFab.contentClearance(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_selectionMode)
          NutritionRecordSelectionBar(
            count: _selected.length,
            onDelete: _selected.isEmpty ? null : () => _confirmBulkDelete(),
            onCancel: _exitSelection,
          ),
      ],
    );
  }
}

/// 趋势卡首次加载的骨架（与真实卡同构，避免加载完跳一下）。
class _TrendCardSkeleton extends StatelessWidget {
  const _TrendCardSkeleton();

  @override
  Widget build(BuildContext context) => const DesignCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(height: 18, width: 120),
        SizedBox(height: LfDimens.spaceMedium),
        SkeletonBox(height: 120),
      ],
    ),
  );
}
