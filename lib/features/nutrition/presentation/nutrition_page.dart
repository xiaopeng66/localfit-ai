import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_legacy_tab_shell.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_tab_bodies.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/canteen_directory_fab.dart';
import 'package:localfit_ai/app/design/widgets/record_fab.dart';
import 'package:localfit_ai/app/placeholder_feature_page.dart';
import 'package:localfit_ai/core/time/daily_rollover.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/application/swap_daily_set_with_ai.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/canteen_directory_page.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_actions.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_intents.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_sub_tab_chips.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/record_tab.dart';
import 'package:localfit_ai/features/progress/application/load_intake_trend.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';

/// 饮食页（docs/21 §5.2 / §5.3 / §4.3）。
///
/// **无 AppBar**：sub-tab 胶囊行是页级唯一实例，画在全部 tab 内容之上
/// （用户 2026-10-03：各界面的按钮必须落在同一个位置），页壳只做编排。
/// 三项 tab：记录 / 菜单 / 食物库（docs/28 §6.1）。
class NutritionPage extends StatefulWidget {
  const NutritionPage({
    super.key,
    this.repository,
    this.mealRepository,
    this.loadDietaryConstraints,
    this.dishLibraryRepository,
    this.loadIntakeTrend,
    this.canteenRepository,
    this.onAnalyzeDishes,
    this.onAskAiForSet,
    this.onSwapSetWithAi,
    this.pickDishImage,
    this.onAddDishToMeal,
    this.foodLibraryController,
    this.menuTabRequest,
    this.mealAddRequest,
    this.now,
    this.foodReferenceService,
    this.semanticRuntime,
    this.supplyCatalog,
  });

  /// 食堂供应读取口（docs/67 §6.4）：记餐与食堂流程共用。
  final SupplyCatalogRepository? supplyCatalog;
  final FoodRepository? repository;
  final MealRepository? mealRepository;
  final Future<PlanningConstraints> Function()? loadDietaryConstraints;

  /// 语义检索（docs/43 A1）；null＝退关键词+标签。
  final SemanticRuntime? semanticRuntime;

  /// 「引用食物库」匹配服务（docs/67 §3.3）；null＝流程关闭。
  final FoodReferenceService? foodReferenceService;

  /// 菜品库仓储（旧只读视图）。未接线时菜单页只渲染 hero 与空态。
  final DishLibraryRepository? dishLibraryRepository;

  /// 近 7 日摄入趋势（记录页趋势卡 + 营养分析卡共用）。未接线时两卡不渲染。
  final LoadIntakeTrend? loadIntakeTrend;

  /// 食堂目录（二级入口）：从菜单页 hero 右上角进入，不再是首屏内容
  /// （docs/22 裁决 ②）。
  final CanteenRepository? canteenRepository;

  /// 「AI 分析这些菜品」：由路由层接线到工作台任务（预填 + 打开详情）。
  final Future<void> Function(List<CanteenDish> dishes)? onAnalyzeDishes;

  /// 「换一整套」的 AI 分支（D3）；`true` = 已交给 AI。
  final Future<bool> Function()? onAskAiForSet;

  /// 【R-4】「换一整套」的内联 AI 重配（不跳页、只换推荐表、只取食堂目录）。
  final Future<MenuSetSwapResult?> Function()? onSwapSetWithAi;

  /// 菜品照片取图（docs/29 §P7 需求 16）；null＝菜品表单不渲染照片字段。
  final Future<String?> Function(bool fromCamera)? pickDishImage;

  /// 菜单页「加入」：把一道菜记成一餐（`cta-add-meal-<n>`）；未接线不渲染。
  ///
  /// [slotOverride] 由「按菜品记录」入口给：用户刚说的餐次优先。
  final Future<void> Function(DishRecord dish, {MealSlot? slotOverride})?
  onAddDishToMeal;

  /// 食物库搜索控制器（有值时食物库 tab 走主库+分片合并）。
  final FoodLibraryController? foodLibraryController;

  /// 下一餐决策主卡控制器（2.0-6i）。记录页把它作为「今天」的置顶卡渲染。
  /// 「查看菜单」跨页请求（今日页决策卡 → 本页菜单 chip）：计数递增即
  /// 切到菜单 tab。null = 无外部请求，页面自己管理 chip。
  final ValueListenable<int>? menuTabRequest;

  /// 「打开餐食编辑」一次性意向（D9）：**消费一次即清空**（`take()`）。
  final MealAddIntent? mealAddRequest;
  final DateTime? now;

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

// 页面常驻 IndexedStack，跨零点不会自然重建；不刷新会让「今日」餐食
// 归到昨天。
class _NutritionPageState extends State<NutritionPage> with DailyRollover {
  String _query = '';
  int _revision = 0;
  int _tab = NutritionTabs.recordIndex;

  /// 记录页多选操作条在屏 ⇒ 右下加号 FAB 隐藏（2026-10-31 用户）。
  bool _recordSelectionMode = false;
  late DateTime _selectedDate;
  StreamSubscription<void>? _foodChanges;

  /// 动作层（docs/07 §9.3）：每次取用都是无状态对象，日期从页面按需读取。
  /// 「按菜品记录」复用页面已接线的 `onAddDishToMeal`，不另建一份——两份
  /// 写入路径一定会漂（docs/40 §3：所有路径最终都落到同一个 create）。
  NutritionActions get _actions => NutritionActions(
    context: context,
    selectedDate: () => _selectedDate,
    onDateSelected: (date) => setState(() => _selectedDate = date),
    dishLibraryRepository: widget.dishLibraryRepository,
    onAddDishToMeal: widget.onAddDishToMeal,
    // D-1（2026-10-25）：让「按菜品记录」也能搜到**食堂目录里未分析**的菜
    // （它们不进菜品库，但用户要搜得到）。分析与食堂目录页同一个回调。
    canteenRepository: widget.canteenRepository,
    onAnalyzeDishes: widget.onAnalyzeDishes,
    supplyCatalog: widget.supplyCatalog,
  );

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _watchFoods();
    widget.menuTabRequest?.addListener(_openMenuTab);
    widget.mealAddRequest?.addListener(_onMealAddRequest);
    // 重放一次性意图（docs/21 §5.8.2 规则 3）。本页在懒分支里创建，而调用方
    // 是「先 value++ 再 go(/nutrition)」——addListener 收不到订阅前的这次
    // 变化，不重放就会落到默认的记录 tab。
    if ((widget.menuTabRequest?.value ?? 0) > 0) {
      _tab = NutritionTabs.menuIndex;
    }
    // 同一类重放：发起方是「先 value=请求 再 go(/nutrition)」，而本页在懒分支
    // 里创建——addListener 收不到订阅前写入的这次请求。弹层要等首帧后再开
    // （initState 里没有可用的 Navigator/Overlay）。
    if (widget.mealAddRequest?.value != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onMealAddRequest());
    }
  }

  void _watchFoods() {
    _foodChanges?.cancel();
    widget.foodLibraryController?.invalidate();
    _foodChanges = widget.repository?.watchChanges().listen((_) {
      if (!mounted) return;
      widget.foodLibraryController?.invalidate();
      setState(() => _revision++);
    });
  }

  @override
  void didUpdateWidget(NutritionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.foodLibraryController != widget.foodLibraryController) {
      _watchFoods();
      _revision++;
    }
  }

  Future<IntakeTrend> _loadRecordTrend(int days, DateTime endDate) =>
      widget.loadIntakeTrend!.run(days: days, endDate: endDate);

  @override
  void dispose() {
    _foodChanges?.cancel();
    widget.menuTabRequest?.removeListener(_openMenuTab);
    widget.mealAddRequest?.removeListener(_onMealAddRequest);
    super.dispose();
  }

  /// 一次性意向：取走（内部已置空）→ 打开记录入口弹层（带可选槽位）。
  /// 未接线的仓库不存在时什么都不做——宁可没有反应，也不弹一个空的编辑框。
  void _onMealAddRequest() {
    final request = widget.mealAddRequest?.take();
    if (request == null) return;
    final foods = widget.repository;
    final meals = widget.mealRepository;
    if (foods == null || meals == null || !mounted) return;
    _actions.editMeal(foods, meals, initialSlot: request.slot);
  }

  /// 外部（今日页决策卡「查看菜单」）请求切到菜单 tab；页面常驻
  /// IndexedStack，靠值通知跨页触发一次切换。
  void _openMenuTab() => setState(() => _tab = NutritionTabs.menuIndex);

  @override
  void onNewDay(DateTime previousDay) {
    setState(() {
      // 仅当用户停留在「今天」时才推进选中日期；用户主动翻看的历史
      // 日期保持不变。
      if (_selectedDate.year == previousDay.year &&
          _selectedDate.month == previousDay.month &&
          _selectedDate.day == previousDay.day) {
        _selectedDate = DateTime(
          observedToday.year,
          observedToday.month,
          observedToday.day,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final foods = widget.repository;
    if (foods == null) {
      return const PlaceholderFeaturePage(
        title: '饮食',
        icon: Icons.restaurant_menu_outlined,
        message: '在本地记录餐食、搜索食物并查看营养历史。',
      );
    }
    final meals = widget.mealRepository;
    return Scaffold(
      // 胶囊行是页面最顶元素，由它吃掉顶部叠层并把底色铺到屏幕物理顶边
      // （docs/21 §5.8.5）；它之下的 hero/顶栏内容随之整体下移，所以各 tab
      // 自己都不再消费叠层。**别在这里补 SafeArea**：那会把胶囊行底色一起
      // 推下去，屏幕顶部留出一条空白带。
      body: Stack(
        children: [
          Column(
            children: [
              // 三个 sub-tab 共用同一份胶囊行、同一个位置（用户 2026-10-03
              // 要求）。各 tab 自己的页头留在内容里，紧接本行下缘。
              NutritionSubTabChips(
                labels: NutritionTabs.labels,
                keys: NutritionTabs.keys,
                selected: _tab,
                onSelected: (value) => setState(() => _tab = value),
              ),
              Expanded(
                child: switch (_tab) {
                  NutritionTabs.recordIndex => _recordBody(foods),
                  NutritionTabs.menuIndex => _menuBody(),
                  _ => _legacyTabBody(
                    title: '食物库',
                    // 需求 30：食物库 tab 没有可返回的上一级，标题与返回键
                    // 一起撤掉（顶栏是共享件，只按页开关）。
                    showBack: false,
                    showTitle: false,
                    child: _foodBody(foods),
                  ),
                },
              ),
            ],
          ),
          // 记录页 FAB（docs/21 §5.2）：点开先问「按食材 / 按菜品」
          // （docs/41 §7）；【2026-10-31】多选操作条在屏时隐藏（盖住删除所选）。
          if (_tab == NutritionTabs.recordIndex &&
              meals != null &&
              !_recordSelectionMode)
            PositionedRecordFab(
              onPressed: () => _actions.editMeal(foods, meals),
            ),
          // 【需求 13a（2026-10-25）】菜单 tab 的「管理食堂目录」= 右下浮动
          // 钮（原页尾 list-link）；构造在 `sections/canteen_directory_fab.dart`
          // （页只留一行挂载：本文件有 400 行维护性预算）。
          if (_tab == NutritionTabs.menuIndex &&
              widget.canteenRepository != null)
            PositionedCanteenDirectoryFab(
              onOpen: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CanteenDirectoryPage(
                    repository: widget.canteenRepository!,
                    now: _now,
                    foodReferenceService: widget.foodReferenceService,
                    onAnalyzeDishes: widget.onAnalyzeDishes,
                    pickDishImage: widget.pickDishImage,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 设计稿未画的那枚 tab（食物库）的外壳（见
  /// [NutritionLegacyTabShell]）：细顶栏 + 内容。胶囊行由页壳统一画。
  Widget _legacyTabBody({
    required String title,
    required Widget child,
    List<Widget> actions = const [],
    bool showBack = true,
    bool showTitle = true,
  }) => NutritionLegacyTabShell(
    title: title,
    actions: actions,
    showBack: showBack,
    showTitle: showTitle,
    child: child,
  );

  /// 菜单 tab（docs/21 §5.3）：hero + 菜品卡列表；食堂目录与「今日推荐」
  /// 按 docs/22 裁决 ② 收进二级入口，首屏只画菜品卡。
  Widget _menuBody() {
    final canteen = widget.canteenRepository;
    return MenuDishList(
      repository: widget.dishLibraryRepository,
      supplyCatalog: widget.supplyCatalog,
      mealRepository: widget.mealRepository,
      loadDietaryConstraints: widget.loadDietaryConstraints,
      now: _now,
      semantic: widget.semanticRuntime,
      onAddToMeal: widget.onAddDishToMeal,
      onAskAiForSet: widget.onAskAiForSet,
      onSwapSetWithAi: widget.onSwapSetWithAi,
      onOpenCanteen: canteen == null
          ? null
          : () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => CanteenDirectoryPage(
                  repository: canteen,
                  now: _now,
                  foodReferenceService: widget.foodReferenceService,
                  onAnalyzeDishes: widget.onAnalyzeDishes,
                  pickDishImage: widget.pickDishImage,
                ),
              ),
            ),
    );
  }

  /// 「记录」tab（docs/21 §5.2）：hero + 趋势卡 + 周条 + 餐卡列表 +
  /// 营养分析 + FAB（胶囊行由页壳统一画在内容之上）。
  Widget _recordBody(FoodRepository foods) {
    final meals = widget.mealRepository;
    // 未接线时也要能切走：页壳已把胶囊行画出来了，这里只负责正文。
    if (meals == null) {
      return _legacyTabBody(
        title: '记录',
        child: const Center(child: Text('餐食记录尚未配置。')),
      );
    }
    final trend = widget.loadIntakeTrend;
    return RecordTab(
      mealRepository: meals,
      selectedDate: _selectedDate,
      now: _now,
      onSelectDate: (date) => setState(() => _selectedDate = date),
      // 【2026-10-31 用户】整卡点击 = 合并编辑该槽位全部记录（逐条编辑已退役）。
      onEditSlotMeals: (records) =>
          _actions.editSlotMeals(foods, meals, records: records),
      // 2026-10-26 用户：「营养摄入自己不能改」——热量卡的「依据」格就是
      // 目标的可改入口（弹层里能手动指定区间，也能恢复按身体数据计算）。
      onEditTarget: () => _actions.editNutritionTarget(meals),
      onDeleteSelected: (deleted) => _actions.deleteMeals(deleted, meals),
      // 【2026-10-31 用户】多选操作条在屏 ⇒ 页面隐藏加号 FAB（不再盖按钮）。
      onSelectionModeChanged: (active) =>
          setState(() => _recordSelectionMode = active),
      // 槽位头加号(仅今天)——【N-2】直接开统一记录弹层（双库搜索 + 手动
      // 添加 + 已添加项同屏编辑），预选餐次不变（D9）；编辑既有餐食同弹层。
      onAddToSlot: (slot) => _actions.editMeal(foods, meals, initialSlot: slot),
      loadTrend: trend == null ? null : _loadRecordTrend,
      // 2026-10-24 用户（`docs/56` R4）：「下一餐详情」入口整族退役不留死码
      // ——`leading` 不再传 `NextMealEntryCard`（docs/58 B3 R4-4a / B6 R4-4b）。
    );
  }

  Widget _foodBody(FoodRepository repository) => NutritionFoodLibraryTabBody(
    repository: repository,
    controller: widget.foodLibraryController,
    query: _query,
    revision: _revision,
    onQueryChanged: (value) => setState(() => _query = value),
    // 需求 29：自建食物入口随搜索行一起下发（两条数据路径各自渲染按钮）。
    onCreateFood: () => _actions.createFood(repository),
    // 页尾两条链（Round7 阶段 3 · 3-2c，A `app.js:201`）：导入走既有 CSV 通路，
    // 管理走共享的食物数据弹层。两条都挂在 tab body 上，两条数据路径共用。
    onImportFoods: () => _actions.importFoods(repository),
  );
}
