import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_empty_state.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';
import 'package:localfit_ai/features/nutrition/application/build_daily_meal_recommendation.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/retrieval/application/feedback_store.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/retrieval/data/feedback_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/daily_meal_set_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/dish_card.dart';
import 'package:localfit_ai/features/ai_conversation/domain/degradation_matrix.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_search_field.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_search_results.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';

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
/// 主来源是 [DishLibraryRepository]（docs/21 §5.3 数据源裁决）。**不得**渲染
/// `MenuItems`——那张表的语义是「菜单上印着的名字」，证据等级低且可能没有
/// 营养值。
///
/// 三餐推荐由 [buildDailyMealRecommendation] 算出（本地、确定性、零 AI）：
/// 同一份数据每次进页面都给同一组推荐，用户不会觉得「它在随机挑」。
class MenuDishList extends StatefulWidget {
  const MenuDishList({
    super.key,
    required this.repository,
    this.mealRepository,
    this.now,
    this.onAddToMeal,
    this.onOpenCanteen,
    this.onAskAiForSet,
    this.semantic,
    this.searchService = const DishSearchService(),
    this.searchDebounce = const Duration(milliseconds: 200),
    this.addClock,
  });

  /// null = 未接线：只渲染 hero 与空态（不退回拿别的表冒充菜品）。
  final DishLibraryRepository? repository;

  /// 当日目标与「今天已经吃过什么」的来源（三餐预算 + 已记录餐次）。
  /// null = 没有目标也没有记录，推荐退化成「只看证据等级 + 菜名」。
  final MealRepository? mealRepository;
  final DateTime? now;
  final Future<void> Function(DishRecord dish)? onAddToMeal;

  /// 「加入餐」冷却用的时钟（测试注入；null = 系统时间）。
  final DateTime Function()? addClock;

  /// 「管理食堂目录」二级入口（docs/22 裁决 ②）。null → 不渲染该入口。
  final VoidCallback? onOpenCanteen;

  /// 「换一整套」在 **AI 已配置**时的分支（D3 裁决第一条）：跳到 AI 对话页
  /// 并预填「生成今日吃法」，由模型用 `meal.create` 逐餐重配。
  ///
  /// **返回值**：`true` = 已交给 AI（调用方不要再做本地重排）；
  /// `false` = AI 其实没配好（配置在组合根查证），调用方继续本地重排 + 实话。
  /// null = 未接线。
  ///
  /// 【为什么是跳转而不是就地调 AI】本组件没有 AI 服务依赖（构造函数里只有
  /// 仓储与几个回调）。跳转复用**已经可用**的 AI 链路（`daily-menu-plan`
  /// starter → 可应用的编辑卡），不新造第二条 AI 路径。
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

  DateTime get _now => widget.now ?? DateTime.now();

  // 2026-10-24（`RV4-P2-09`，已锁裁决 D2）：陈旧提示 + 手动同步整族退役。
  // 自动同步覆盖七条写路径，且用户手改的行现在被冻结
  // （`DishLibraryRepository.upsertBySource` 跳过 `userEdited`），
  // 「食堂营养有更新 + 同步」这套交互已无对象。

  /// 推荐反馈（「不错 / 换一个」）：写 `app_settings` KV，不新增表。
  FeedbackRepository? get _feedbackRepository {
    final repository = widget.repository;
    return repository == null
        ? null
        : FeedbackRepository(database: repository.database);
  }

  /// 记一次显式反馈。**失败不打扰用户**：反馈是锦上添花，不该挡住浏览。
  Future<void> _recordFeedback(DishRecord dish, FeedbackVote vote) async {
    final repository = _feedbackRepository;
    if (repository == null) return;
    try {
      await repository.record(dish.name, vote);
    } on Object {
      // 忽略：反馈是软排序信号，不承载记账正确性。
    }
  }

  Future<void> _like(BuildContext context, DishRecord dish) async {
    await _recordFeedback(dish, FeedbackVote.like);
    if (!context.mounted) return;
    AppSnackBar.show(
      context,
      '已记下「不错」，以后同类会多推荐',
      icon: AppSnackBar.successIcon,
    );
  }

  @override
  void initState() {
    super.initState();
    _bindStream();
  }

  @override
  void didUpdateWidget(MenuDishList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _bindStream();
      _lastDishes = const [];
    }
  }

  /// 菜品流**缓存**（`watchAll()` 每次调用都新建一条 drift 查询流）。
  /// 在 build 里现取等于「每次重建都换流 → 重订阅 → 立刻 emit 新的 List
  /// 实例 → 又触发陈旧刷新 → setState」，页面永远 settle 不下来
  /// （实测一次 pumpAndSettle 触发 3001 次刷新）。
  Stream<List<DishRecord>>? _dishStream;

  void _bindStream() {
    _dishStream = widget.repository?.watchAll();
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
    final repository = widget.repository;
    if (repository == null) {
      return CustomScrollView(
        slivers: [
          _headerSliver(
            child: const _MenuHeader(plannedMeals: 0, plannedKcal: null),
          ),
          const SliverToBoxAdapter(
            // 缺陷 ㉓：空态统一 LfEmptyState（A 的图标块语言）。
            child: LfEmptyState(
              icon: Icons.menu_book_outlined,
              title: '菜品库尚未配置。',
              message: '接线后这里会列出可加入的菜品。',
            ),
          ),
          ..._pageEnd(),
          _navReserve(),
        ],
      );
    }
    return StreamBuilder<List<DishRecord>>(
      stream: _dishStream ??= repository.watchAll(),
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
        final dishes = snapshot.data;
        if (dishes != null && !identical(dishes, _lastDishes)) {
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
        return _withMealFacts(dishes);
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
    final onOpenCanteen = widget.onOpenCanteen;
    return [
      if (onOpenCanteen != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LfDimens.pagePadding,
              LfDimens.spaceLarge,
              LfDimens.pagePadding,
              0,
            ),
            child: _CanteenLink(onTap: onOpenCanteen),
          ),
        ),
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

  /// 把「当日目标」与「今天已记录的餐食」读进来，再交给纯函数算推荐。
  ///
  /// 两路数据都来自 `MealRepository`；未接线时按「没有目标、没有记录」处理
  /// （推荐仍然给得出，只是不按预算挑、不显示已安排餐次）。
  Widget _withMealFacts(List<DishRecord> dishes) {
    final meals = widget.mealRepository;
    if (meals == null) return _body(dishes, const {}, null);
    final date = formatLocalDate(_now);
    return StreamBuilder<DailyNutritionSummary>(
      stream: meals.watchNutritionForDate(date),
      builder: (context, targetSnapshot) => StreamBuilder<List<MealRecord>>(
        stream: meals.watchForDate(date),
        builder: (context, mealSnapshot) => _body(
          dishes,
          recordedKcalBySlot(mealSnapshot.data ?? const []),
          targetSnapshot.data?.target?.calorieMaxKcal,
        ),
      ),
    );
  }

  Widget _body(
    List<DishRecord> dishes,
    Map<MealSlot, double> recorded,
    double? dailyTargetKcal,
  ) {
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
          ..._pageEnd(),
          _navReserve(),
        ],
      );
    }
    final plan = buildDailyMealRecommendation(
      dishes: dishes,
      recordedKcalBySlot: recorded,
      dailyTargetKcal: dailyTargetKcal,
      nowMinute: _now.hour * 60 + _now.minute,
    );
    // 菜品库是空的：三餐块会退化成三个「暂无推荐」，不如直接给一个能照做的
    // 空态（去哪写菜、让谁生成），段头保留以便用户看到「今天已安排了几餐」。
    if (dishes.isEmpty) {
      return CustomScrollView(
        slivers: [
          _headerSliver(
            child: _MenuHeader(
              plannedMeals: plan.plannedMeals,
              plannedKcal: plan.plannedMeals == 0 ? null : plan.plannedKcal,
            ),
          ),
          const SliverToBoxAdapter(
            child: LfEmptyState(
              icon: Icons.menu_book_outlined,
              title: '菜品库还是空的。',
              message: '在食堂目录里自建菜品，或让 AI 生成今日菜单。',
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

    return CustomScrollView(
      slivers: [
        _headerSliver(
          child: _MenuHeader(
            plannedMeals: plan.plannedMeals,
            // 一道都没排时不写 0 kcal，写「—」：0 的意思是「今天不吃」，
            // 而这里的意思是「还没有推荐」（docs/28 §4.1）。
            plannedKcal: plan.plannedMeals == 0 ? null : plan.plannedKcal,
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
                meals: plan.meals,
                views: views,
                onLike: (dish) => _like(context, dish),
                onRepickSet: () => unawaited(_repickSet()),
                onShowCandidates: (slot) => _showCandidates(slot, views[slot]!),
                onAddToMeal: widget.onAddToMeal == null
                    ? null
                    : (dish) => _addToMeal(context, dish),
                onOpenCanteen: widget.onOpenCanteen,
              ),
            ],
          ),
        ),
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

  /// 「换一整套」（`RV4-P2-08` / `docs/56` R10-a，已锁裁决 D3）。
  ///
  /// 三格各自的「换一个」退役了：单格换会破坏整套营养平衡。现在的行为：
  /// 1. **整套重排**——把三餐的候选偏移整体往后挪一格（同一份候选榜、同一套
  ///    规则，所以「同一道菜不跨餐重复」仍然成立）；
  /// 2. **给一句实话**：本页没接 AI 配置，所以这是本地重排而不是「AI 重新分析」。
  ///    （已配置 AI 的入口在 AI 对话页的「生成今日吃法」，那里走 chat-edit
  ///    逐餐提议；本页不复制那条写路径。）
  /// 3. 记一次 dislike 软反馈（用户表达了「这一套现在不太想吃」）。
  ///
  /// **不写库**：纯 UI 状态，与原来的「换一个」同性质。
  Future<void> _repickSet() async {
    // 【D3 裁决的第一条分支，2026-10-25 补齐】「已配置 AI → 走
    // `aiStarterRequest`（AI 用 `meal.create` 逐餐提议）」。
    //
    // 【缺陷原委】原实现**只做了第二条分支**（本地重排），而且不管配没配 AI
    // 都弹「**AI 未配置**」——那句是写死的，`_repickSet` 从未检查过任何配置。
    // 于是配好 AI 的用户被告知「AI 未配置」，以为配置没生效或链路断了
    // （用户实测原话：「我配置了AI，但还是显示AI未配置的提示」）。
    //
    // 现在：`onAskAiForSet` 只在 **AI 确实已配置**时被注入（判定在组合根），
    // 有它就**优先走 AI**；没有（未配置）才落到下面的本地重排 + 实话。
    final askAi = widget.onAskAiForSet;
    if (askAi != null) {
      final handled = await askAi();
      // await 期间页面可能已被销毁（用户切走/退栈）——用 context 前必须确认。
      if (!mounted) return;
      if (handled) return;
    }
    final shown = [
      for (final view in _viewsOfCurrentPlan.values) view.displayed,
    ];
    setState(() {
      // 三格一起挪一格：没建立过偏移的餐次（首次点）也要跟着动，
      // 否则「整套换」只影响之前点过的那几格。
      for (final slot in _viewsOfCurrentPlan.keys) {
        _swapOffset[slot] = (_swapOffset[slot] ?? 0) + 1;
      }
    });
    for (final dish in shown) {
      if (dish != null) unawaited(_recordFeedback(dish, FeedbackVote.dislike));
    }
    AppSnackBar.show(
      context,
      '已按本地规则重排一整套（这一步不调用 AI，即时生效；'
      '配置 AI 后会走模型逐餐重配）。',
      icon: AppSnackBar.infoIcon,
    );
  }

  Future<void> _showCandidates(MealSlot slot, DailyMealSetSlotView view) async {
    final picked = await AppSheet.show<int>(
      context,
      title: '${slot.label}候选',
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < view.candidates.length; i++)
              _CandidateRow(
                dish: view.candidates[i],
                selected: i == view.displayedIndex,
                index: i,
                onTap: () => Navigator.of(context).pop(i),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _swapOffset[slot] = picked);
  }

  DateTime _nowForAdd() => widget.addClock?.call() ?? DateTime.now();

  Future<void> _addToMeal(BuildContext context, DishRecord dish) async {
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
      await add(dish);
      succeeded = true;
      // 2026-10-16 用户：「点加入午餐什么的时候，没有提示」——成功也要
      // 上屏（原来只有失败分支有提示）：说清加进了哪一餐、以及「记为已吃」
      // 这条事实（本页页脚原本只用一行小字说明）。
      if (context.mounted) {
        AppSnackBar.show(
          context,
          '已加入${DishCard.mealSlotLabel(dish.mealSlot)}（记为已吃）',
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

  SliverPadding _navReserve() => SliverPadding(
    padding: EdgeInsets.only(bottom: LfInsets.navReserve(context)),
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

/// 页尾的 A `.list-link`（`styles.css:359–363` + `polish.css:106–107`）：
/// 圆角 chip + 两行文字 + 右箭头，整行可点、**不是卡**（`.list-link{border:0}`）。
///
/// **2026-10-14（3-1 D28）**：它承接原 hero 右上角 [LfCircleIconButton] 的
/// 「管理食堂目录」入口——`cta-manage-canteen` 的 Key 一起迁过来（同一个路由、
/// 同一个回调，只是从卡上一枚圆钮变成页尾一行）。A 的 chip 用 `book` 图标
/// （`app.js:185` 的 `chip('book')`），底色被 `polish.css:107` 覆盖成
/// brand-soft / brand-strong。
class _CanteenLink extends StatelessWidget {
  const _CanteenLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    return InkWell(
      key: const Key('cta-manage-canteen'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      child: Padding(
        // A `.list-link{padding:10px 0;min-height:64px}`。
        padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceSmallPlus),
        child: Row(
          children: [
            Container(
              // A `.icon-chip`：36×36 / 12 圆角；`.list-link .icon-chip` 改
              // brand-soft 底 + brand-strong 字。
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: LfColors.brandSoft(brightness),
                borderRadius: BorderRadius.circular(LfDimens.radiusMd),
              ),
              child: Icon(
                Icons.menu_book_outlined,
                size: LfDimens.iconMd,
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
                    '管理食堂目录',
                    // A `.list-link b{font-size:12px}`（`b` 是粗体，落 captionStrong）。
                    style: LfText.captionStrong.copyWith(
                      color: c.cardForeground,
                    ),
                  ),
                  const SizedBox(height: LfDimens.spaceMicro),
                  Text(
                    '地点、窗口与菜品',
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: LfDimens.iconSm,
              color: c.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

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
          searchMode
              ? '输入菜名、口味或窗口，搜索本地已分析的菜品。'
              : '按你的食堂窗口推荐 · 先看看今天的候选，选好份量后再加入饮食记录。',
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
