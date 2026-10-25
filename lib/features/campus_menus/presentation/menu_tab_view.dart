import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_dish_flows.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_venue_body_section.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_venue_selector.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_delete_confirms.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_window_card.dart';
import 'package:localfit_ai/features/campus_menus/presentation/food_reference_coordinator.dart';
import 'package:localfit_ai/features/campus_menus/presentation/food_reference_sheet.dart';
import 'package:localfit_ai/features/campus_menus/presentation/menu_form_prompts.dart';
import 'package:localfit_ai/app/design/widgets/lf_empty_state.dart';

/// 食堂 tab（3.0）：**地点 → 窗口 → 菜品** 三级自建结构。
///
/// 取代旧的「导入菜单文件 → 快照」入口：用户维护的是常驻结构
/// （我在哪几个地点吃饭、每个地点有哪些窗口、每个窗口常卖哪些菜），
/// 而不是某一天的菜单照片。菜品营养由 AI 分析后写入证据表，供每日
/// 推荐使用。
///
/// 页面只做编排（选择地点、跑写操作、分类错误文案）；渲染在
/// [CanteenWindowCard]，表单在 [MenuFormPrompts]（校验与换算在 domain 层）。
class MenuTabView extends StatefulWidget {
  const MenuTabView({
    super.key,
    required this.repository,
    this.onAnalyzeDishes,
    this.pickDishImage,
    this.leading,
    this.onDirectoryChanged,
    this.foodReferenceService,
  });

  final CanteenRepository repository;

  /// 建食堂菜/改名后的「参考食物库」匹配（docs/40 §3.1）。null＝该流程
  /// 整体关闭（测试与纯本地场景），建菜行为与旧版逐字一致。
  final FoodReferenceService? foodReferenceService;

  /// 菜品照片取图（docs/29 §P7 需求 16）：true＝拍照、false＝从相册选，
  /// 返回私有目录里的新路径。null＝菜品表单不渲染照片字段。
  final Future<String?> Function(bool fromCamera)? pickDishImage;

  /// 目录数据每次重新载入后的回调（2026-10-16）：目录页用它刷新「今日推荐」
  /// ——用户在菜品表单里**后补了照片**，推荐卡上的照片要跟着更新（用户要求）。
  final VoidCallback? onDirectoryChanged;

  /// 「AI 分析这些菜品」回调：由接线方打开 AI 工作台任务并预填菜名。
  /// null＝不渲染该入口（测试或未接 AI 时的降级）。
  final Future<void> Function(List<CanteenDish> dishes)? onAnalyzeDishes;

  /// 置顶内容（由页面拼装，目录本身不关心它从哪来），与 [RecordTab.leading]
  /// 同约定：跟目录**共用同一个滚动上下文**一起滚。
  ///
  /// 不能把它放在页面级 Column 里独立成块——推荐菜单是自然高度，窄屏 +
  /// 1.5× 字号下约 700dp，会把窗口列表挤成 0 高并让外层溢出（2.0-6i-4
  /// 在记录 tab 上踩过同类缺陷）。
  final Widget? leading;

  @override
  State<MenuTabView> createState() => _MenuTabViewState();
}

class _MenuTabViewState extends State<MenuTabView> {
  List<CanteenVenue>? _venues;
  String? _selectedVenueId;
  bool _busy = false;

  /// 窗口列表的**上一份成功数据**（按地点缓存）。需求 18 的修法核心：
  /// 切换地点/写操作刷新时**继续画旧数据**，绝不回到 `SliverFillRemaining`
  /// 加载分支——那个分支把滚动视图压成零内容高，offset 被夹回 0，
  /// 用户看到的「切换食堂就跳顶」就是这么来的。
  final Map<String, List<CanteenWindow>> _windowsByVenue = {};

  /// 正在拉取窗口列表的地点（用于顶部细进度条；有旧数据时不遮内容）。
  final Set<String> _fetchingVenues = {};

  /// 最近一次拉取失败的地点。有旧数据时只加一条错误细条（旧列表仍是
  /// 上一份事实），无旧数据才进整块错误分支。
  final Set<String> _failedVenues = {};

  /// 「参考食物库」三选一编排（docs/40 §3.1）。null＝服务未接线。
  late final FoodReferenceCoordinator? _foodReference =
      widget.foodReferenceService == null
      ? null
      : FoodReferenceCoordinator(
          repository: widget.repository,
          service: widget.foodReferenceService!,
          loadDish: _loadDish,
          onAnalyze: widget.onAnalyzeDishes,
        );

  /// createDish 只回 id；从窗口缓存里找刚建/刚改的那道菜。
  Future<CanteenDish?> _loadDish(String dishId) async {
    for (final windows in _windowsByVenue.values) {
      for (final window in windows) {
        for (final dish in window.dishes) {
          if (dish.id == dishId) return dish;
        }
      }
    }
    return null;
  }

  /// 目录四表的变更订阅：别处写入（AI 应用/备份恢复）也要让列表自动刷新
  /// （2026-10-16 设备实测缺陷 ㊵ 的修复；docs/21 §5.3「食堂目录」注）。
  /// 自己写入期间不重复刷新；已在刷新则合并一趟（不叠队）。
  StreamSubscription<void>? _directorySubscription;
  bool _selfWriting = false;
  bool _reloadInFlight = false;
  bool _reloadQueued = false;

  /// 首次加载失败的原因（RV-P1-12）：null = 没有错误。
  Object? _loadError;

  @override
  void dispose() {
    unawaited(_directorySubscription?.cancel());
    super.dispose();
  }

  /// 四张表单弹层（添加地点/窗口/菜品、编辑菜品）；失败留窗见 [MenuFormPrompts]。
  late final MenuFormPrompts _forms = MenuFormPrompts(
    repository: widget.repository,
    reload: _reload,
    pickDishImage: widget.pickDishImage,
    onDishCreated: _foodReference == null
        ? null
        : (dishId, dishName) {
            return _foodReference.run(
              dishId: dishId,
              dishName: dishName,
              showSnack: (message, {error = false}) {
                if (!mounted) return;
                AppSnackBar.show(
                  context,
                  message,
                  icon: error ? AppSnackBar.errorIcon : AppSnackBar.successIcon,
                );
              },
              showSheet: (dishName, candidates) => FoodReferenceSheet.show(
                context,
                dishName: dishName,
                candidates: candidates,
              ),
              isMounted: () => mounted,
            );
          },
  );
  @override
  void initState() {
    super.initState();
    _reload();
    // 订阅放 initState 一次（不能在 build 里建流：每次重建换一个新 stream
    // 会让监听永不收敛，同 ai_memory_page 的既有教训）。
    _directorySubscription = widget.repository.watchDirectory().listen((_) {
      if (_selfWriting) return; // 自己的写入 _run 里已经 reload 过。
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    if (_reloadInFlight) {
      _reloadQueued = true;
      return;
    }
    _reloadInFlight = true;
    try {
      await _reloadOnce();
      if (mounted) setState(() => _loadError = null);
    } on Object catch (error) {
      // 报错也不能把页面变成永久 spinner：置一个可重试的错误态。
      if (mounted) setState(() => _loadError = error);
    } finally {
      _reloadInFlight = false;
      if (_reloadQueued && mounted) {
        _reloadQueued = false;
        unawaited(_reload());
      }
    }
  }

  Future<void> _reloadOnce() async {
    widget.onDirectoryChanged?.call();
    final venues = await widget.repository.listVenues();
    if (!mounted) return;
    setState(() {
      _venues = venues;
      if (venues.isEmpty) {
        _selectedVenueId = null;
      } else if (!venues.any((venue) => venue.id == _selectedVenueId)) {
        _selectedVenueId = venues.first.id;
      }
      // 已删地点的缓存一并清掉，避免幽灵数据在下次选中时复活。
      _windowsByVenue.removeWhere(
        (id, _) => venues.every((venue) => venue.id != id),
      );
      _failedVenues.removeWhere(
        (id) => venues.every((venue) => venue.id != id),
      );
    });
    // 每个地点都刷新（stale-while-revalidate）：地点通常只有两三个，
    // 全量预取让「切换地点」永远有数据可画，从根上消除加载分支。
    for (final venue in venues) {
      unawaited(_refreshWindows(venue.id));
    }
  }

  /// 拉取一个地点的窗口列表并更新缓存；失败时保留旧数据、只记失败态。
  Future<void> _refreshWindows(String venueId) async {
    if (_fetchingVenues.contains(venueId)) return;
    _fetchingVenues.add(venueId);
    if (mounted) setState(() {});
    try {
      final windows = await widget.repository.listWindows(venueId);
      if (!mounted) return;
      setState(() {
        _windowsByVenue[venueId] = windows;
        _failedVenues.remove(venueId);
      });
    } on Object {
      if (!mounted) return;
      setState(() => _failedVenues.add(venueId));
    } finally {
      _fetchingVenues.remove(venueId);
      if (mounted) setState(() {});
    }
  }

  /// 写操作外壳：忙态 + 分类错误文案（原始异常绝不上屏）。
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    _selfWriting = true;
    try {
      await action();
      await _reload();
    } on CanteenWriteException catch (error) {
      if (!mounted) return;
      AppSnackBar.show(context, error.userMessage, icon: AppSnackBar.errorIcon);
    } on Object {
      if (!mounted) return;
      AppSnackBar.show(context, '操作失败：请稍后重试。', icon: AppSnackBar.errorIcon);
    } finally {
      _selfWriting = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final venues = _venues;
    if (venues == null) {
      if (_loadError != null) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppErrorText('食堂目录加载失败，请重试。'),
              LfTextButton(
                key: const Key('canteen-directory-retry'),
                label: '重试',
                onPressed: () => unawaited(_reload()),
              ),
            ],
          ),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // 置顶内容（推荐菜单）与地点/窗口列表共用一个滚动上下文（见 [leading]）：
    // 各自独立成块时，推荐菜单的自然高度会把窗口列表挤成 0 高并让外层
    // Column 溢出（320dp + 1.5× 实测溢出 227dp）。
    return CustomScrollView(
      slivers: [
        if (widget.leading case final header?)
          SliverToBoxAdapter(child: header),
        // 目录为空也要渲染置顶内容：推荐菜单是独立区块，不因目录空态消失。
        if (venues.isEmpty)
          SliverFillRemaining(hasScrollBody: false, child: _emptyState())
        else ...[
          SliverToBoxAdapter(
            child: CanteenVenueSelector(
              venues: venues,
              selected: _selected(venues),
              busy: _busy,
              onAddVenue: () => _forms.promptAddVenue(context),
              onSelectVenue: (id) => setState(() => _selectedVenueId = id),
            ),
          ),
          CanteenVenueBodySection(
            venue: _selected(venues),
            windows: _windowsByVenue[_selected(venues).id],
            fetching: _fetchingVenues.contains(_selected(venues).id),
            failed: _failedVenues.contains(_selected(venues).id),
            busy: _busy,
            onAddDish: (window) => _forms.promptAddDish(context, window.id),
            onDeleteWindow: (window) => _confirmDeleteWindow(window),
            onDishTap: (dish) => showCanteenDishActions(
              context,
              dish,
              repository: widget.repository,
              onAnalyze: widget.onAnalyzeDishes,
              onManualNutrition: _runManualNutrition,
              runWrite: _run,
              onEdit: (dish) => _forms.promptEditDish(context, dish),
              onDelete: _confirmDeleteDish,
              isMounted: () => mounted,
            ),
            onAddWindow: () =>
                _forms.promptAddWindow(context, _selected(venues).id),
            onRetry: () => unawaited(_refreshWindows(_selected(venues).id)),
            onAnalyze: widget.onAnalyzeDishes,
          ),
        ],
        // 本页由饮食·菜单页 `Navigator.push` 推入，仍挂在 shell 分支的
        // Navigator 上 ⇒ 底部那条 `extendBody` 浮起的贴底栏压在这条滚动视图
        // 之上（0-7 走查实测栏体顶边 y=2000）。空态行动原本落在 y=2124~2268，
        // 既被栏体盖住又因为 `SliverFillRemaining` 没有可滚余量而永远滚不上
        // 来（两次点按都落到栏体/FAB 上）⇒ 末尾留出栏高 + 上凸 + 手势带。
        SliverToBoxAdapter(
          child: SizedBox(height: LfInsets.navReserve(context)),
        ),
      ],
    );
  }

  CanteenVenue _selected(List<CanteenVenue> venues) {
    for (final venue in venues) {
      if (venue.id == _selectedVenueId) return venue;
    }
    return venues.first;
  }

  // ── 地点正文：窗口列表（sliver，与置顶内容共用一个滚动上下文）──────
  //
  // 数据来自 [_windowsByVenue] 的**上一份成功结果**（需求 18）：刷新中
  // 继续画旧列表 + 顶部 2dp 细进度条，绝不进 `SliverFillRemaining` 加载
  // 分支（那个分支会把滚动视图压成零内容高、offset 夹回 0 ⇒ 跳顶）。
  // 只有「从未拿到过数据」的地点才允许加载/错误占位——那是真正没有旧
  // 数据可画的情形，而不是把已见的列表藏起来。

  // ── 空态：一个地点都没有 ────────────────────────────────────────────

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LfEmptyState(
              icon: Icons.school_outlined,
              title: '还没有食堂地点。',
              message: '先添加你常去的食堂，再按窗口录入常卖的菜品。',
            ),
            const SizedBox(height: 12),
            // 空态行动 = §3.8 B6 主色文字按钮（用户 2026-10-03 裁决：空态入口
            // 不用实心/淡底，避免与页面主行动抢视觉）。
            LfTextButton(
              key: const Key('canteen-add-venue'),
              icon: Icons.add_location_alt_outlined,
              label: '添加地点',
              onPressed: _busy ? null : () => _forms.promptAddVenue(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── 表单弹层 ────────────────────────────────────────────────────────
  //
  // 四张表单（添加地点/窗口/菜品、编辑菜品）与 N7 的「写失败不关窗」都在
  // `menu_form_prompts.dart`；本页只负责把结果刷新到列表。

  /// D10 手动营养的宿主（写操作外壳在本页，弹层在共享 flows）。
  Future<void> _runManualNutrition(CanteenDish dish) =>
      showManualNutritionSheet(
        context,
        dish,
        repository: widget.repository,
        runWrite: _run,
      );

  Future<void> _confirmDeleteWindow(CanteenWindow window) async {
    final confirmed = await confirmCanteenDelete(
      context,
      title: '删除窗口',
      message: '删除「${window.name}」会同时删掉它的 ${window.dishes.length} 道菜与营养数据。',
    );
    if (!confirmed) return;
    await _run(() => widget.repository.deleteWindow(window.id));
  }

  Future<void> _confirmDeleteDish(CanteenDish dish) async {
    final confirmed = await confirmCanteenDelete(
      context,

      title: '删除菜品',

      message: '删除「${dish.name}」会同时删掉它的营养数据。',
    );

    if (!confirmed) return;

    await _run(() => widget.repository.deleteDish(dish.id));
  }
}
