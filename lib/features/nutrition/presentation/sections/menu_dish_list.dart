import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_empty_state.dart';
import 'package:localfit_ai/app/design/widgets/lf_float_actions.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';
import 'package:localfit_ai/features/nutrition/application/build_daily_meal_recommendation.dart';
import 'package:localfit_ai/features/nutrition/application/supply_dish_candidates.dart';
import 'package:localfit_ai/features/nutrition/data/supply_catalog_repository.dart';
import 'package:localfit_ai/features/nutrition/application/swap_daily_set_with_ai.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/retrieval/application/feedback_store.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/retrieval/data/feedback_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/daily_meal_set_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/dish_visuals.dart';
import 'package:localfit_ai/features/ai_conversation/domain/degradation_matrix.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_search_field.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_search_results.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';

typedef _MenuCatalogData = ({
  List<DishRecord> dishes,
  List<SupplyCatalogItem>? supplies,
});

/// 「菜单」sub-tab（docs/28 §4.1）：**段头 + 今日三餐整套推荐**。
///
/// **2026-10-22 用户**：「根据食堂菜品，直接给出从早餐到晚餐的一整套推荐，
/// 而不是分开」——早/午/晚从三张独立卡收进同一张 [DailyMealSetCard]（卡头
/// 写「一整套」，卡内三段用分隔线连接）；「其他已分析菜品」整块退场（用户
/// 2026-10-22：「菜单界面不要显示其他已分析菜品」）。
///
/// **2026-10-14（Round7 阶段 3 步骤 1，D25–D30）**：页首 hero 卡退场，改 A
/// `nutritionMenus()`（`app.js:181–185`）的**段头块**——段标题「每日菜品推荐」
/// （`LfText.title` = A `.section-title` 15 w600）+ `.pill`「本地已分析菜品」
/// （[LfBadge.neutral]）+ 指引行（A `.intro-copy` 的字面句 + 原 hero 副标题里的
/// 「按你的食堂窗口」事实）+ 汇总行「已安排 N 餐 · 预计 X kcal」（原 hero 两枚
/// 统计的 `quiet-label` 降级）。「管理食堂目录」入口随 hero 圆钮迁到页尾
/// A `.list-link`。**键不退役**：`nutrition-menu-hero` / `-hero-planned` /
/// `-hero-kcal` / `cta-manage-canteen` 各由新件承接。
///
/// sub-tab 胶囊行**不在这里**：它是页级唯一实例，由 `NutritionPage` 画在本
/// 组件之上（用户 2026-10-03 要求五个界面位置一致），所以本页的滚动内容从
/// 段头块开始（顶距 12 = A `.page{padding-top:12px}`）。
///
/// 主来源是 [SupplyCatalogRepository] 的全量供应；无主链接或份量未知也可
/// 如实展示，但不当作可计算推荐。未接供应源时兼容旧菜品库只读视图。
///
/// 三餐推荐由 [buildDailyMealRecommendation] 算出（本地、确定性、零 AI）：
/// 同一份数据每次进页面都给同一组推荐，用户不会觉得「它在随机挑」。
class MenuDishList extends StatefulWidget {
  const MenuDishList({
    super.key,
    required this.repository,
    this.mealRepository,
    this.loadDietaryConstraints,
    this.now,
    this.onAddToMeal,
    this.onOpenCanteen,
    this.onSwapSetWithAi,
    this.onAskAiForSet,
    this.semantic,
    this.searchService = const DishSearchService(),
    this.searchDebounce = const Duration(milliseconds: 200),
    this.addClock,
    this.supplyCatalog,
  });

  /// 全量供应用于展示；本地推荐只取完整营养与有效份量（估计值明确标约），
  /// AI 自动推荐仍只接受 known + trusted。预算统一按一份比较。
  /// null = 未接线，退回菜品库旧只读视图。
  final SupplyCatalogRepository? supplyCatalog;

  /// null = 未接线：只渲染 hero 与空态（不退回拿别的表冒充菜品）。
  final DishLibraryRepository? repository;

  /// 当日目标与「今天已经吃过什么」的来源（三餐预算 + 已记录餐次）。
  /// null = 没有目标也没有记录，推荐退化成「只看证据等级 + 菜名」。
  final MealRepository? mealRepository;

  /// 设置里的饮食约束（标签 / 忌口）。null = 未接线，按空约束推荐。
  final Future<PlanningConstraints> Function()? loadDietaryConstraints;
  final DateTime? now;

  /// 加入一餐；`slotOverride` 是**用户点的那一餐**（推荐段），优先于菜品
  /// 自己在库里的默认餐次。
  final Future<void> Function(DishRecord dish, {MealSlot? slotOverride})?
  onAddToMeal;

  /// 「加入餐」冷却用的时钟（测试注入；null = 系统时间）。
  final DateTime Function()? addClock;

  /// 「管理食堂目录」二级入口（docs/22 裁决 ②）。null → 不渲染该入口。
  final VoidCallback? onOpenCanteen;

  /// 「换一整套」的 **AI 内联重配**（R-4，2026-10-29 用户：点击换一套后
  /// **不要跳转 AI 对话界面**，显示加载中、在原界面直接问 AI；内容必须
  /// 来源于食堂目录，AI 限定检索、不许随机生成或用食物库食材）。
  ///
  /// 返回值：`MenuSetSwapResult`（已本地硬校验的每餐菜 + 被过滤条数）；
  /// null = AI 未配置/食堂目录没有可用菜/输出不可解析 —— 调用方回退本地
  /// 重排并如实说明。**本组件不写任何餐记录**（换的是推荐表，不是账）。
  final Future<MenuSetSwapResult?> Function()? onSwapSetWithAi;

  /// 【2026-11-10 退役】空态「让 AI 生成今日菜单」已改为**内联**调
  /// [onSwapSetWithAi]（在本界面生成推荐清单，不跳对话页、不写库）。
  /// 该回调保留参数位但组件不再使用；组合根清理后可移除。
  final Future<bool> Function()? onAskAiForSet;

  /// 语义检索运行时（docs/43 A1）：null = 未接线——搜索自动退关键词 + 标签，
  /// **不弹错**（降级矩阵 docs/41 §10）。
  final SemanticRuntime? semantic;

  /// 检索服务（测试注入计数/脚本化实现；默认就是纯本地的那一个）。
  final DishSearchService searchService;

  /// 搜索防抖（docs/39 §8：200ms）。测试可缩短。
  final Duration searchDebounce;

  @override
  State<MenuDishList> createState() => _MenuDishListState();
}

class _MenuDishListState extends State<MenuDishList> {
  /// 「换一个」的偏移，每餐一个。
  ///
  /// **纯 UI 状态**：不写库、不进任何控制器。它只决定「这一格里现在摆的是
  /// 候选榜的第几个」，离开页面就没了——同一天再次进来仍然给同一个首推
  /// （否则推荐会显得随机）。
  final Map<MealSlot, int> _swapOffset = {};

  /// 当前这一版推荐里每格展示了什么（「换一整套」要按它记反馈 + 挪偏移）。
  /// build 时写入，纯 UI 状态。
  Map<MealSlot, DailyMealSetSlotView> _viewsOfCurrentPlan = const {};

  /// 【R-4】AI 内联换一套：进行中标志（按钮就地显示「挑菜中…」）。
  bool _swapping = false;

  /// 【R-4】AI 选中的每餐菜（已本地硬校验）。空 = 用本地候选榜。
  /// 纯 UI 状态：不写库、离开页面即失效。
  Map<MealSlot, List<DishRecord>> _aiPicks = const {};

  /// 全量本地计划，判断是否真的存在可重排候选，不拿供应条数冒充候选。
  DailyMealRecommendation? _localPlan;

  /// 设置里的饮食约束。首帧为空（不误过滤），加载完再刷新推荐；从别的
  /// 分支（设置页改完约束）切回来时，`didChangeDependencies` 会重读。
  PlanningConstraints _constraints = const PlanningConstraints();
  bool _constraintsVisible = true;

  DateTime get _now => widget.now ?? DateTime.now();

  // 2026-10-24（`RV4-P2-09`，已锁裁决 D2）：陈旧提示 + 手动同步整族退役。
  // 自动同步覆盖七条写路径，且用户手改的行现在被冻结
  // （`DishLibraryRepository.upsertBySource` 跳过 `userEdited`），
  // 「食堂营养有更新 + 同步」这套交互已无对象。

  /// 推荐反馈（「不错 / 换一整套」）：写 `app_settings` KV，不新增表。
  FeedbackRepository? get _feedbackRepository {
    final repository = widget.repository;
    return repository == null
        ? null
        : FeedbackRepository(database: repository.database);
  }

  /// 已加载的反馈存储。它有两个用途：
  /// 1. 重进页面时把点过「不错」的菜显示成「已记下」（不再只活在 SnackBar）；
  /// 2. 传给推荐引擎做同级内软排序——此前反馈只写不读，按钮等于没有作用。
  FeedbackStore? _feedback;

  /// 点过「不错」的菜名（归一化）。`DailyMealSetCard` 用它决定按钮外观。
  Set<String> get _likedDishNames => _feedback?.likedNames ?? const {};

  Future<void> _loadFeedback() async {
    final repository = _feedbackRepository;
    if (repository == null) return;
    try {
      final store = await repository.load();
      if (!mounted) return;
      setState(() => _feedback = store);
    } on Object {
      // 反馈读失败不影响浏览；推荐退化为中性排序。
    }
  }

  /// 记一次显式反馈并同步内存里的 store。
  ///
  /// 返回 false = 没有落库（未接线/写失败）。调用方据此决定是否显示
  /// 「已记下」——没写进去却把按钮改成已记下，是在骗用户。
  Future<bool> _recordFeedback(DishRecord dish, FeedbackVote vote) async {
    final repository = _feedbackRepository;
    if (repository == null) return false;
    try {
      final store = await repository.record(dish.name, vote);
      if (mounted) setState(() => _feedback = store);
      return true;
    } on Object {
      // 反馈是软排序信号，不承载记账正确性：失败只影响按钮反馈。
      return false;
    }
  }

  Future<void> _like(BuildContext context, DishRecord dish) async {
    final saved = await _recordFeedback(dish, FeedbackVote.like);
    if (!context.mounted) return;
    if (!saved) {
      AppSnackBar.show(context, '没有记下，请重试。', icon: AppSnackBar.errorIcon);
    }
    // 成功时不再弹 SnackBar：按钮就地变成「已记下」，比底部一闪而过的提示
    // 更可靠（用户原话：「我要是没看到不就完了吗」）。
  }

  @override
  void initState() {
    super.initState();
    _bindStream();
    unawaited(_loadFeedback());
    unawaited(_loadConstraints());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 设置页在另一个分支里：改完饮食约束切回饮食页时，本组件仍常驻。
    // TickerMode 由 shell 的分支可见性翻转，借它重读一次，不靠手动刷新。
    final visible = TickerMode.valuesOf(context).enabled;
    if (!_constraintsVisible && visible) {
      unawaited(_loadConstraints());
    }
    _constraintsVisible = visible;
  }

  Future<void> _loadConstraints() async {
    final loader = widget.loadDietaryConstraints;
    if (loader == null) return;
    try {
      final loaded = await loader();
      if (!mounted) return;
      if (loaded.dietaryLabelsJson == _constraints.dietaryLabelsJson &&
          loaded.allergenAvoidancesJson ==
              _constraints.allergenAvoidancesJson) {
        return;
      }
      setState(() => _constraints = loaded);
    } on Object {
      // 读失败按空约束继续推荐；不因设置读取失败把菜单卡住。
    }
  }

  @override
  void didUpdateWidget(MenuDishList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.supplyCatalog != widget.supplyCatalog) {
      _bindStream();
      _lastDishes = const [];
      _aiPicks = const {};
      _swapOffset.clear();
      _localPlan = null;
      _feedback = null;
      unawaited(_loadFeedback());
    }
    if (oldWidget.loadDietaryConstraints != widget.loadDietaryConstraints) {
      _constraints = const PlanningConstraints();
      unawaited(_loadConstraints());
    }
  }

  /// 菜品流**缓存**（`watchAll()` 每次调用都新建一条 drift 查询流）。
  /// 在 build 里现取等于「每次重建都换流 → 重订阅 → 立刻 emit 新的 List
  /// 实例 → 又触发陈旧刷新 → setState」，页面永远 settle 不下来
  /// （实测一次 pumpAndSettle 触发 3001 次刷新）。
  Stream<_MenuCatalogData>? _dishStream;

  // 流收到新事实就使在途 AI 快照失效，不等下一帧 build 才计版本。
  int _catalogGeneration = 0;

  /// 显示层保留全量供应；可计算池单独映射，不用 0 千卡哨兵填补列表。
  void _bindStream() {
    _catalogGeneration++;
    final catalog = widget.supplyCatalog;
    if (catalog == null) {
      _dishStream = widget.repository?.watchAll().map((dishes) {
        _catalogGeneration++;
        return (dishes: dishes, supplies: null);
      });
      return;
    }
    _dishStream = catalog.watchAll().map((supplies) {
      _catalogGeneration++;
      return (
        dishes: supplyDishCandidates(supplies, now: _now, strict: false),
        supplies: supplies,
      );
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<DishRecord> _lastDishes = const [];

  // ── 搜索（docs/43 A1；状态机在 menu_search_field.dart）─────────────────
  final TextEditingController _searchController = TextEditingController();
  late final MenuSearchController _search = MenuSearchController(
    searchService: widget.searchService,
    semantic: widget.semantic,
    debounce: widget.searchDebounce,
  )..addListener(_onSearchStateChanged);
  bool _searchFieldHasText = false;

  /// 在途/冷却中的「加入餐」菜品 id（RV-P1-05）。
  ///
  /// 只挡「在途」不够：设备实测两次点击相隔 ~80ms，第一次写入完成后锁就
  /// 释放了，第二次照样落库（800 kcal）。所以成功后保留 900ms 冷却。
  final Set<String> _addingDishIds = <String>{};

  /// 每道菜最近一次成功加入的时间（RV-P1-05 冷却）。
  final Map<String, DateTime> _lastAddedAt = <String, DateTime>{};

  static const Duration _addCooldown = Duration(milliseconds: 900);

  void _onSearchStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// 已触发过索引的菜品集合签名（幂等：同一集合只触发一次）。
  String? _indexedSignature;

  /// 进页空闲建索引（docs/43 A1）：`textHash` 命中直接复用，幂等。
  ///
  /// **失败不打扰用户**：模型缺失/加载失败时搜索照常走关键词 + 标签。
  void _maybeWarmIndex(List<DishRecord> dishes) {
    final semantic = widget.semantic;
    if (semantic == null || dishes.isEmpty) return;
    final signature = dishes.map((dish) => dish.id).join(',');
    if (signature == _indexedSignature) return;
    _indexedSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(() async {
        try {
          await semantic.indexDishes(dishes);
        } on Object {
          // 降级：检索退关键词 + 标签，原因在调试面板可见。
        }
      }());
    });
  }

  void _onSearchChanged(String value) {
    setState(() => _searchFieldHasText = value.trim().isNotEmpty);
    _search.onQueryChanged(value, _lastDishes);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchFieldHasText = false);
    _search.onQueryChanged('', _lastDishes);
  }

  Widget _searchSliver() => menuSearchFieldSliver(
    child: MenuSearchField(
      controller: _searchController,
      onChanged: _onSearchChanged,
      onClear: _clearSearch,
      hasText: _searchFieldHasText,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_dishStream == null) {
      return CustomScrollView(
        slivers: [
          _headerSliver(
            child: const _MenuHeader(plannedMeals: 0, plannedKcal: null),
          ),
          SliverToBoxAdapter(
            // 缺陷 ㉓：空态统一 LfEmptyState（A 的图标块语言）。
            // E-1（docs/64）：给一个能做的事——去食堂目录先建菜品。
            child: LfEmptyState(
              icon: Icons.menu_book_outlined,
              title: '菜品库尚未配置。',
              message: '接线后这里会列出可加入的菜品。',
              action: widget.onOpenCanteen == null
                  ? null
                  : LfTextButton(
                      key: const Key('menu-empty-action'),
                      icon: Icons.storefront_outlined,
                      label: '去食堂目录',
                      onPressed: widget.onOpenCanteen,
                    ),
            ),
          ),
          ..._pageEnd(),
          _navReserve(),
        ],
      );
    }
    return StreamBuilder<_MenuCatalogData>(
      stream: _dishStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return CustomScrollView(
            slivers: [
              _headerSliver(
                child: const _MenuHeader(plannedMeals: 0, plannedKcal: null),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(LfDimens.pagePadding),
                  child: AppErrorText('菜品加载失败，请重试。'),
                ),
              ),
              ..._pageEnd(),
              _navReserve(),
            ],
          );
        }
        final data = snapshot.data;
        final dishes = data?.dishes;
        if (dishes != null && !identical(dishes, _lastDishes)) {
          // 主链接、份量或营养变化后不能继续显示旧 AI 快照。
          _aiPicks = const {};
          _lastDishes = dishes;
          // 只在**数据真的换了实例**时重跑搜索：写在每次 build 里会形成
          // 「检索 → notifyListeners → setState → 再检索」的死循环（实测
          // pumpAndSettle 永不收敛）。
          _search.refresh(dishes);
        }
        if (dishes != null) _maybeWarmIndex(dishes);
        if (dishes == null) {
          return CustomScrollView(
            slivers: [
              _headerSliver(
                child: const _MenuHeader(plannedMeals: 0, plannedKcal: null),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: LfDimens.pagePadding,
                  ),
                  child: Column(
                    children: [
                      _DishCardSkeleton(),
                      SizedBox(height: LfDimens.cardGap),
                      _DishCardSkeleton(),
                    ],
                  ),
                ),
              ),
              ..._pageEnd(),
              _navReserve(),
            ],
          );
        }
        return _withMealFacts(data!);
      },
    );
  }

  /// 段头块的 sliver：顶距 12（A `.page{padding-top:12px}`，`refinement.css:3`，
  /// 与记录页周条同款取值）、左右 16；**底距 0**——段头到首个槽卡的 16 由推荐区
  /// 的 `SliverPadding` 出（A `.page{gap:16px}` 的页间隙，2026-10-14 的 3-1 几何
  /// 断言按它量）。
  static SliverPadding _headerSliver({required Widget child}) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(
      LfDimens.pagePadding,
      LfDimens.spaceMedium,
      LfDimens.pagePadding,
      0,
    ),
    sliver: SliverToBoxAdapter(child: child),
  );

  /// A `.page{gap:16px}` 与 `.list-link` 自带 padding 之外的页尾段（`app.js:185`）。
  ///
  /// 未接线（`repository == null`）也画：list-link 是**页级 chrome**，与菜品库
  /// 是否可用无关——原来它挂在 hero 卡上时同样是无条件渲染的。
  List<Widget> _pageEnd() {
    final c = context.lf;
    return [
      // 【需求 13a（2026-10-25）】「管理食堂目录」的页尾 `.list-link` 行
      // **整枚迁出**：用户要它挪到**右下浮动按钮**。浮动按钮由页面壳
      // （`NutritionPage` 的 Stack）画，与记录页 FAB 同一层——它不该跟着
      // 列表滚走（原来滚到页面底部才看得见）。`cta-manage-canteen` 的 Key
      // 与回调一起迁到那枚浮钮上。
      // A 的 `.subtle-note`（`styles.css:162`，11 muted）中**在本仓成立**的半句：
      // A 的前半句「候选与营养值为演示样例」是原型免责声明，本仓的数据是真实
      // 分析结果，搬过来是假话（D28）。没有加入动作时不写这句（说了也没用）。
      if (widget.onAddToMeal != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LfDimens.pagePadding,
              LfDimens.spaceSmall,
              LfDimens.pagePadding,
              0,
            ),
            child: Text(
              '加入餐次会记为已吃，保存前请确认。',
              key: const Key('nutrition-menu-note'),
              style: LfText.label.copyWith(color: c.mutedForeground),
            ),
          ),
        ),
    ];
  }

  /// 不可自动推荐的供应仍须可见；展示事实，不塞进非空营养的 DishRecord。
  List<Widget> _supplyStatusSlivers(
    List<SupplyCatalogItem>? supplies, {
    String query = '',
  }) {
    if (supplies == null) return const [];
    final normalized = query.trim().toLowerCase();
    final incomplete = supplies
        .where(
          (supply) =>
              !supply.isAutoRecommendable &&
              (normalized.isEmpty ||
                  '${supply.displayName} ${supply.windowLabel}'
                      .toLowerCase()
                      .contains(normalized)),
        )
        .toList();
    if (incomplete.isEmpty) return const [];
    final colors = context.lf;
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          LfDimens.pagePadding,
          LfDimens.cardGap,
          LfDimens.pagePadding,
          0,
        ),
        sliver: SliverList.list(
          children: [
            Text('供应资料待补充', style: LfText.title),
            Text(
              '以下供应真实存在，但营养或每份克数尚待确认；不会进入 AI 自动推荐。',
              style: LfText.label.copyWith(color: colors.mutedForeground),
            ),
            for (final supply in incomplete)
              Padding(
                key: Key('nutrition-menu-supply-${supply.id}'),
                padding: const EdgeInsets.symmetric(
                  vertical: LfDimens.spaceSmall,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supply.displayName, style: LfText.title),
                    Text(
                      '${supply.windowLabel} · ${supply.servingWindow}',
                      style: LfText.label.copyWith(
                        color: colors.mutedForeground,
                      ),
                    ),
                    Text(_supplyStatus(supply), style: LfText.label),
                    if (supply.isAnalyzable && !supply.foodArchived)
                      Text(
                        '${_supplyNumber(supply.kcalPer100g!)} kcal/100g',
                        style: LfText.label,
                      ),
                  ],
                ),
              ),
            if (widget.onOpenCanteen != null)
              LfTextButton(
                key: const Key('nutrition-menu-complete-supplies'),
                icon: Icons.storefront_outlined,
                label: '去食堂目录补营养与每份克数',
                onPressed: widget.onOpenCanteen,
              ),
          ],
        ),
      ),
    ];
  }

  static String _supplyNumber(double value) =>
      value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);

  static String _supplyStatus(SupplyCatalogItem supply) {
    if (supply.foodArchived) return '主食物已归档，请核对营养与份量。';
    if (!supply.isAnalyzable) return '待补营养：尚未链接主食物或营养不完整。';
    if (!supply.canRecordByServing || supply.kcalPerServing?.isFinite != true) {
      return '份量未知，请补每份克数；暂不计算每份营养。';
    }
    final grams = _supplyNumber(supply.servingGrams!);
    if (supply.state == SupplyNutritionState.servingEstimated) {
      return '估计份量 · 约 $grams g/份，加入餐前请确认。';
    }
    return '$grams g/份 · 份量来源未确认，请先核对。';
  }

  /// 把「当日目标」与「今天已记录的餐食」读进来，再交给纯函数算推荐。
  ///
  /// 两路数据都来自 `MealRepository`；未接线时按「没有目标、没有记录」处理
  /// （推荐仍然给得出，只是不按预算挑、不显示已安排餐次）。
  Widget _withMealFacts(_MenuCatalogData data) {
    final meals = widget.mealRepository;
    if (meals == null) return _body(data, const {}, null, null);
    final date = formatLocalDate(_now);
    return StreamBuilder<DailyNutritionSummary>(
      stream: meals.watchNutritionForDate(date),
      builder: (context, targetSnapshot) => StreamBuilder<List<MealRecord>>(
        stream: meals.watchForDate(date),
        builder: (context, mealSnapshot) => _body(
          data,
          recordedKcalBySlot(mealSnapshot.data ?? const []),
          // 【需求 1（2026-10-25）】三餐推荐的口径统一为**区间**：
          // 上限（旧参数名保留）+ 下限一起传，预算按 `target.min/max − 已摄入`
          // 分配（不许硬编码，也不许只按上限估）。
          targetSnapshot.data?.target?.calorieMaxKcal,
          targetSnapshot.data?.target?.calorieMinKcal,
        ),
      ),
    );
  }

  Widget _body(
    _MenuCatalogData data,
    Map<MealSlot, double> recorded,
    double? dailyTargetMaxKcal,
    double? dailyTargetMinKcal,
  ) {
    final dishes = data.dishes;
    // 搜索态（docs/43 A1）：结果替换推荐区；清空后回到推荐区、不保留状态。
    final searchResult = _search.result;
    if (_search.isSearching && searchResult != null) {
      return CustomScrollView(
        slivers: [
          _headerSliver(
            child: _MenuHeader(
              plannedMeals: 0,
              plannedKcal: null,
              searchMode: true,
            ),
          ),
          _searchSliver(),
          MenuSearchResultsSliver(
            query: _search.query,
            hits: searchResult.hits,
            dishes: dishes,
            degradedNotice: !_search.semanticUnavailable
                ? ''
                : _search.semanticBelowThreshold
                ? kSemanticBelowThresholdNotice
                : degradationNotice(
                    DegradationRow.onDeviceModelUnavailable,
                    DegradationColumn.search,
                  ),
            isAdding: (id) => _addingDishIds.contains(id),
            onAddToMeal: widget.onAddToMeal == null
                ? null
                : (dish) => _addToMeal(context, dish),
          ),
          ..._supplyStatusSlivers(data.supplies, query: _search.query),
          ..._pageEnd(),
          _navReserve(),
        ],
      );
    }
    DailyMealRecommendation localPlanFor(List<DishRecord> candidates) =>
        buildDailyMealRecommendation(
          dishes: candidates,
          recordedKcalBySlot: recorded,
          dailyTargetKcal: dailyTargetMaxKcal,
          dailyTargetMinKcal: dailyTargetMinKcal,
          nowMinute: _now.hour * 60 + _now.minute,
          feedback: _feedback,
          constraints: _constraints,
        );
    _localPlan = localPlanFor(dishes);
    // AI 已选中的供应不再给未返回的餐次补位，否则会跨餐重复。
    final aiIds = {
      for (final entry in _aiPicks.entries)
        if (!recorded.containsKey(entry.key) &&
            isMealRecommendationSlotOpen(
              entry.key,
              _now.hour * 60 + _now.minute,
            ))
          ...entry.value.map((dish) => dish.id),
    };
    final plan = _aiPicks.isEmpty
        ? _localPlan!
        : localPlanFor(dishes.where((d) => !aiIds.contains(d.id)).toList());
    final hasSupplies = data.supplies?.isNotEmpty ?? dishes.isNotEmpty;
    // 只有真实无供应时才说库空；不可计算不等于不存在。
    if (!hasSupplies && _aiPicks.isEmpty) {
      _viewsOfCurrentPlan = const {};
      return CustomScrollView(
        slivers: [
          _headerSliver(
            child: _MenuHeader(
              plannedMeals: plan.plannedMeals,
              plannedKcal: plan.plannedMeals == 0 ? null : plan.plannedKcal,
            ),
          ),
          SliverToBoxAdapter(
            child: LfEmptyState(
              icon: Icons.menu_book_outlined,
              title: '菜品库还是空的。',
              message: '请先到食堂目录添加供应并补充营养与每份克数；AI 只能从已有可信供应选菜。',
              // E-1（docs/64）：两个入口并列（AI 优先，食堂目录次之）。
              action: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onSwapSetWithAi != null)
                    LfTextButton(
                      key: const Key('menu-empty-action'),
                      icon: Icons.auto_awesome_outlined,
                      // 2026-11-10 用户：生成要在**本界面**完成，产出一份
                      // 推荐清单（不跳对话页、不直接记餐）。复用「换一套」
                      // 的内联 AI 重配——它本来就不写今日摄入。
                      label: _swapping ? 'AI 正在从食堂目录挑菜…' : '让 AI 生成今日菜单',
                      onPressed: _swapping
                          ? null
                          : () => unawaited(_repickSet()),
                    ),
                  if (widget.onOpenCanteen != null)
                    LfTextButton(
                      key: const Key('menu-empty-action-canteen'),
                      icon: Icons.storefront_outlined,
                      label: '去食堂目录',
                      onPressed: widget.onOpenCanteen,
                    ),
                ],
              ),
            ),
          ),
          ..._pageEnd(),
          _navReserve(),
        ],
      );
    }
    // 每一格现在摆的是哪个候选（「换一整套」之后会变），以及它的候选榜。
    final views = <MealSlot, DailyMealSetSlotView>{
      for (final meal in plan.meals) meal.slot: _viewFor(meal),
    };
    _viewsOfCurrentPlan = views;
    // AI 可以把唯一供应安排到本地原本没有主推的餐位；状态、理由和汇总必须
    // 跟实际显示一致，不能一边显示成功菜品、一边仍说本餐没有候选。
    final displayedMeals = [
      for (final meal in plan.meals)
        if (views[meal.slot]?.displayed case final DishRecord dish)
          MealRecommendation(
            slot: meal.slot,
            state: MealRecommendationState.recommended,
            reason: _aiPicks[meal.slot]?.isNotEmpty == true
                ? 'AI 已从可信供应中选出，营养、份量与供应餐次已由本地校验。'
                : meal.reason,
            primary: dish,
            alternatives: views[meal.slot]!.candidates
                .where((candidate) => candidate.id != dish.id)
                .toList(),
            budgetKcal: meal.budgetKcal,
            budgetMinKcal: meal.budgetMinKcal,
            kcal: dish.kcal,
          )
        else
          meal,
    ];
    final plannedMeals = displayedMeals
        .where((meal) => meal.state != MealRecommendationState.empty)
        .length;
    final plannedKcal = displayedMeals.fold<double>(
      0,
      (total, meal) => total + (meal.kcal ?? 0),
    );

    return CustomScrollView(
      slivers: [
        _headerSliver(
          child: _MenuHeader(
            plannedMeals: plannedMeals,
            // 一道都没排时不写 0 kcal，写「—」：0 的意思是「今天不吃」，
            // 而这里的意思是「还没有推荐」（docs/28 §4.1）。
            plannedKcal: plannedMeals == 0 ? null : plannedKcal,
          ),
        ),
        _searchSliver(),
        SliverPadding(
          // 顶距 16 = A 的页间隙（段头块底距是 0，两件合起来 = A `.page{gap:16}`）。
          padding: const EdgeInsets.fromLTRB(
            LfDimens.pagePadding,
            LfDimens.cardGap,
            LfDimens.pagePadding,
            0,
          ),
          sliver: SliverList.list(
            children: [
              // 2026-10-22 用户：「根据食堂菜品，直接给出从早餐到晚餐的一整套
              // 推荐，而不是分开」——早/午/晚从三张独立卡收进同一张整套卡。
              DailyMealSetCard(
                meals: displayedMeals,
                views: views,
                likedDishNames: _likedDishNames,
                onLike: (dish) => _like(context, dish),
                onRepickSet: () => unawaited(_repickSet()),
                swapping: _swapping,
                onShowCandidates: (slot) => _showCandidates(slot, views[slot]!),
                onAddToMeal: widget.onAddToMeal == null
                    ? null
                    : (dish, {slotOverride}) =>
                          _addToMeal(context, dish, slotOverride: slotOverride),
                onOpenCanteen: widget.onOpenCanteen,
              ),
            ],
          ),
        ),
        ..._supplyStatusSlivers(data.supplies),
        ..._pageEnd(),
        // 底部预留见 record_tab 同处注释：用无子节点的 [SliverPadding] 而不是
        // 末尾的 SizedBox sliver，后者会成为最深的渲染叶子、被
        // 「内容不得画到遮挡线之下」判红。
        _navReserve(),
      ],
    );
  }

  /// 某一格当前展示哪个候选（`_swapOffset` 是唯一决定因素）。
  DailyMealSetSlotView _viewFor(MealRecommendation meal) {
    // 已记录或已过的餐次没有推荐位；即使用户此前换过 AI 候选，也不能
    // 在记下这一餐后继续把旧推荐当成待吃菜品展示。
    if (meal.state == MealRecommendationState.planned ||
        !isMealRecommendationSlotOpen(
          meal.slot,
          _now.hour * 60 + _now.minute,
        )) {
      return const DailyMealSetSlotView(candidates: []);
    }
    // 【R-4】AI 换一套之后：该餐直接用 AI 的（已校验）菜当候选榜，
    // displayed = 第一道；本地偏移不再叠加（AI 的顺序就是它给的顺序）。
    final ai = _aiPicks[meal.slot];
    if (ai != null && ai.isNotEmpty) {
      return DailyMealSetSlotView(
        candidates: ai,
        displayed: ai.first,
        displayedIndex: 0,
      );
    }
    final candidates = [?meal.primary, ...meal.alternatives];
    if (candidates.isEmpty) {
      return const DailyMealSetSlotView(candidates: []);
    }
    final offset = (_swapOffset[meal.slot] ?? 0) % candidates.length;
    return DailyMealSetSlotView(
      candidates: candidates,
      displayed: candidates[offset],
      displayedIndex: offset,
    );
  }

  /// 只换推荐、不写摄入。详细失败沿用同一个回调传入；旧 null 结果仍兼容。
  /// 仅有真实本地候选才重排，资料不足时不把失败包装成「已重排」。
  Future<void> _repickSet() async {
    if (_swapping) return;
    String? failure;
    final swapWithAi = widget.onSwapSetWithAi;
    if (swapWithAi != null) {
      final requestedGeneration = _catalogGeneration;
      setState(() => _swapping = true);
      MenuSetSwapResult? result;
      try {
        result = await swapWithAi();
      } on Object {
        failure = MenuSetSwapUnavailableReason.requestFailed.message;
      }
      if (!mounted) return;
      if (requestedGeneration != _catalogGeneration) {
        setState(() {
          _swapping = false;
          _aiPicks = const {};
        });
        AppSnackBar.show(
          context,
          '食堂目录已更新，本次 AI 结果已丢弃，请重试。',
          icon: AppSnackBar.infoIcon,
        );
        return;
      }
      setState(() => _swapping = false);
      if (result != null &&
          result.unavailableReason == null &&
          result.bySlot.values.any((picks) => picks.isNotEmpty)) {
        final success = result;
        setState(() {
          _aiPicks = {
            for (final entry in success.bySlot.entries)
              entry.key: List<DishRecord>.of(entry.value),
          };
          _swapOffset.clear();
        });
        if (success.filtered > 0) {
          AppSnackBar.show(
            context,
            '已按食堂目录换一套；${success.filtered} 条未通过目录、餐次或预算校验的建议已忽略。',
          );
        }
        return;
      }
      failure ??=
          result?.unavailableReason?.message ??
          'AI 暂不可用，请检查配置、供应营养与每份克数，或稍后重试。';
    }
    final localMeals =
        _localPlan?.meals.where((meal) => meal.primary != null).toList() ??
        const <MealRecommendation>[];
    final shown = [
      for (final view in _viewsOfCurrentPlan.values)
        if (view.displayed case final DishRecord dish) dish,
    ];
    setState(() {
      // 回退后绝不保留上次 AI 快照，否则会把旧结果冒充本地重排。
      _aiPicks = {};
      for (final meal in localMeals) {
        _swapOffset[meal.slot] = (_swapOffset[meal.slot] ?? 0) + 1;
      }
    });
    final prefix = failure == null ? '' : 'AI 换一套没成功。$failure ';
    if (localMeals.isEmpty) {
      AppSnackBar.show(
        context,
        '$prefix当前没有可计算的本地候选；请到食堂目录补充营养与每份克数，并核对供应时段。',
        icon: AppSnackBar.infoIcon,
      );
      return;
    }
    for (final dish in shown) {
      unawaited(_recordFeedback(dish, FeedbackVote.dislike));
    }
    final hasAlternatives = localMeals.any(
      (meal) => meal.alternatives.isNotEmpty,
    );
    AppSnackBar.show(
      context,
      hasAlternatives
          ? '$prefix已按本地规则重排一整套（仅调整推荐，不写今日摄入）。'
          : '$prefix已按本地规则重新核对推荐，当前没有更多候选。',
      icon: AppSnackBar.infoIcon,
    );
  }

  Future<void> _showCandidates(MealSlot slot, DailyMealSetSlotView view) async {
    final picked = await AppSheet.show<int>(
      context,
      title: '${slot.label}候选',
      // 【2026-11-02 用户实机：候选点击后黑屏】弹层由 `AppSheet` 挂在**根
      // Navigator** 上（`useRootNavigator: true`），页面本身在分支 Navigator
      // 里。候选行若用页面 `context` 调 `Navigator.of(...).pop`，弹的是页面
      // 那一层——用户看到整页被 pop 成黑屏。必须用弹层内 Builder 的
      // `sheetContext` 关弹层自己（与项目弹层纪律同一条）。
      content: Builder(
        builder: (sheetContext) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < view.candidates.length; i++)
                _CandidateRow(
                  dish: view.candidates[i],
                  selected: i == view.displayedIndex,
                  index: i,
                  onTap: () => Navigator.of(sheetContext).pop(i),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    // 【R-4 实机回归】AI 换一套之后：候选来自 AI 推荐集，选中 = 把它排到
    // 首位（`_swapOffset` 只管本地候选榜，两套状态不混用）。
    final ai = _aiPicks[slot];
    if (ai != null && ai.isNotEmpty) {
      if (picked <= 0 || picked >= ai.length) return;
      setState(() {
        _aiPicks[slot] = [
          ai[picked],
          ...ai.where((d) => d.id != ai[picked].id),
        ];
      });
      return;
    }
    setState(() => _swapOffset[slot] = picked);
  }

  DateTime _nowForAdd() => widget.addClock?.call() ?? DateTime.now();

  Future<void> _addToMeal(
    BuildContext context,
    DishRecord dish, {
    MealSlot? slotOverride,
  }) async {
    final add = widget.onAddToMeal;
    if (add == null) return;
    if (!_addingDishIds.add(dish.id)) return;
    final now = _nowForAdd();
    final last = _lastAddedAt[dish.id];
    if (last != null && now.difference(last) < _addCooldown) {
      _addingDishIds.remove(dish.id);
      AppSnackBar.show(context, '刚加入过这道菜，请稍候再试。', icon: AppSnackBar.infoIcon);
      return;
    }
    setState(() {});
    var succeeded = false;
    try {
      await add(dish, slotOverride: slotOverride);
      succeeded = true;
      // 2026-10-16 用户：「点加入午餐什么的时候，没有提示」——成功也要
      // 上屏（原来只有失败分支有提示）：说清加进了哪一餐、以及「记为已吃」
      // 这条事实（本页页脚原本只用一行小字说明）。
      if (context.mounted) {
        AppSnackBar.show(
          context,
          '已加入${DishVisuals.mealSlotLabel(dish.mealSlot)}（记为已吃）',
          icon: AppSnackBar.successIcon,
        );
      }
    } on FormatException catch (error) {
      if (context.mounted) {
        AppSnackBar.show(context, error.message, icon: AppSnackBar.errorIcon);
      }
    } catch (_) {
      if (context.mounted) {
        AppSnackBar.show(context, '加入失败，请重试。', icon: AppSnackBar.errorIcon);
      }
    } finally {
      // 成功记时间戳（冷却期内连点被挡）；失败路径立即可重试。
      if (succeeded) _lastAddedAt[dish.id] = _nowForAdd();
      _addingDishIds.remove(dish.id);
      if (mounted) setState(() {});
    }
  }

  /// 页尾让位：【2026-10-31 用户】右下「管理食堂目录」浮钮（与训练页浮钮
  /// 列同一套统一阴影/尺寸后）也会盖住滚到底的内容——与训练页
  /// `columnContentClearance` 同一命题：让最后一行能滚出浮钮覆盖带。
  /// 带字档高同 48（emphasized:1）。
  SliverPadding _navReserve() => SliverPadding(
    padding: EdgeInsets.only(
      bottom: PositionedLfFloatingActions.columnContentClearance(
        context,
        emphasized: 1,
      ),
    ),
  );
}

/// 候选榜里的一行：菜名 + 热量；当前展示的那一道打勾。
class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.dish,
    required this.selected,
    required this.index,
    required this.onTap,
  });

  final DishRecord dish;
  final bool selected;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return InkWell(
      key: Key('nutrition-menu-candidate-$index'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceSmall),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: LfDimens.iconMd,
              color: selected ? c.primary : c.mutedForeground,
            ),
            const SizedBox(width: LfDimens.spaceSmall),
            Expanded(
              child: Text(
                dish.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: LfText.body.copyWith(color: c.cardForeground),
              ),
            ),
            const SizedBox(width: LfDimens.spaceSmall),
            Text(
              '${dish.kcal.round()} kcal',
              style: LfText.captionStrong.copyWith(color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

// 【退役（需求 13a，2026-10-25）】`_CanteenLink`（A 的页尾
// `.list-link` 两行行）整件删除：入口迁到菜单 tab 右下角的浮动按钮
// （`NutritionPage` 的 `PositionedLfFloatingActions`，Key 不变）。
// 保留这条说明是为了让后来者知道「页尾那行不是丢失，是搬家」。

/// 菜单页首**段头块**（A `nutritionMenus()` 页首三件，`app.js:181`）。
///
/// **2026-10-14（3-1 D25）**：原 hero 卡退场——A 的菜单页首没有卡，是段标题
/// + `.pill` + `.intro-copy`。卡退场时**卡上的事实不能跟着消失**：
///
///  * 标题「今日菜单」→ A 的「每日菜品推荐」（同一职责，A 有落点就换成 A 的）；
///  * 副标题「按你的食堂窗口推荐今天吃什么」→ 并进 A 的 `.intro-copy` 指引行
///    的**前半句**（「按你的食堂窗口」是这套推荐真正依赖的本地事实，不随换稿消失）；
///  * 两枚统计（已安排 N 餐 / 预计 X kcal）→ 汇总行，降为 A `.quiet-label` 档
///    （12 muted，与 A 的 `.intro-copy` 同档）；口径不变：0 餐写「—」不写 0 kcal；
///  * 管理圆钮 → 页尾 `.list-link`（见 [_CanteenLink]，D28）。
///
/// 键不退役：`nutrition-menu-hero` 由本块承接（语义 = 页面顶部块），两枚统计的
/// Key 落在汇总行两段文字上——8 个既有测试文件靠它们定位，删键是白拆别处的锚。
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({
    required this.plannedMeals,
    required this.plannedKcal,
    this.searchMode = false,
  });

  final int plannedMeals;

  /// 预计热量；null = 还没有任何推荐 → 写「—」（不写死设计稿的 1470）。
  final double? plannedKcal;

  /// 搜索态（docs/43 A1）：推荐汇总行在这里没有意义（结果替换推荐区），
  /// 指引行改成搜索口径；段标题与 pill 保持不变。
  final bool searchMode;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final quiet = LfText.caption.copyWith(color: c.mutedForeground);
    return Column(
      key: const Key('nutrition-menu-hero'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // A `.section-title.with-link`（`styles.css:132`）是一行两端。用 `Wrap`
        // 而不是 `Row`：2.0×/320dp 时标题 + pill 共需 ≈384dp > 卡内 288，
        // `Row` 会挤/裁，`Wrap` 让 pill 整枚掉到第二行。
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: LfDimens.spaceSmall,
          runSpacing: LfDimens.spaceXSmall,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '每日菜品推荐',
              style: LfText.title.copyWith(color: c.cardForeground),
            ),
            // A 的 `.pill`（11 号）＝共享徽章件的 neutral 档（§3.9）。
            const LfBadge.neutral('本地已分析菜品'),
          ],
        ),
        const SizedBox(height: LfDimens.spaceXSmall),
        Text(
          searchMode ? '输入菜名、口味或窗口，搜索本地已分析的菜品。' : '按食堂窗口推荐，选好后加入记录。',
          key: const Key('nutrition-menu-intro'),
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        if (!searchMode) ...[
          const SizedBox(height: LfDimens.spaceSmall),
          // 汇总行：两段独立 `Text`（各带自己的 Key）而不是拼一个长串——2.0× 时
          // 长串只能整行折，拆开后每段都能落在自己的行上、两枚 Key 都可达。
          Wrap(
            spacing: LfDimens.spaceXSmall,
            runSpacing: LfDimens.spaceMicro,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '已安排 $plannedMeals 餐',
                key: const Key('nutrition-menu-hero-planned'),
                style: quiet,
              ),
              Text('·', style: quiet),
              Text(
                plannedKcal == null
                    ? '预计 —'
                    : '预计 ${plannedKcal!.round()} kcal',
                key: const Key('nutrition-menu-hero-kcal'),
                style: quiet,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 与 [DishCard] 同构的骨架。
class _DishCardSkeleton extends StatelessWidget {
  const _DishCardSkeleton();

  @override
  Widget build(BuildContext context) => const DesignCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: SkeletonBox(height: double.infinity),
        ),
        Padding(
          padding: EdgeInsets.all(LfDimens.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(height: 20, width: 120),
              SizedBox(height: LfDimens.spaceMedium),
              SkeletonBox(height: 14),
            ],
          ),
        ),
      ],
    ),
  );
}
