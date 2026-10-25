import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_scrollbar.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_detail_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_category_chips.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_library_header.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_library_item_actions.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_library_results.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_list_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_list_states.dart';

/// 食物库浏览 / 搜索视图（2.0-6f，docs/07 §9.3；docs/28 §8 改成分页）。
///
/// 旧实现一次只取 30 条（`FoodRepository.search` 的默认 limit），下滑永远只有
/// 30 张卡——用户 2026-10-04 点名的就是这件事（D5「食物库只能显示一部分」）。
/// 现在：总数走 `COUNT(*)`、列表按 50 条一页取（`LIMIT/OFFSET`），
/// `SliverPrototypeExtentList` 的 `itemCount` 是**总数**而不是已加载数——没载到的
/// 区间画骨架并登记加载，滑条因此能拖到任意位置、一路滑到底。
///
/// 用 `SliverPrototypeExtentList`（行高实测为已知）而**不是** `SliverList`：真机
/// 拿行高未知的 sliver 拖滑条远跳时会逐行实体化到落点，主线程卡死（实测 ANR，
/// 完整归因见 `_prototypeCard`）。这一条是设备走查抓出来的，widget 测试到不了。
///
/// **分类筛选（Round7 阶段 3 · D33/D34）**：早期版本刻意不做——当时唯一的分类
/// 来源是 `FoodCategory.classify` 的关键词表，对中文食物覆盖很弱（「牛肉面」落
/// 到「其他」），拿它当筛选器只会把大多数条目挤进同一格。现在不同了：CSV 导入
/// （ADR-036 官方 9 列）的每一行都**必须**带一个合法的 `FoodCategory.id`（无法映射的行整行拒收，
/// docs/31 §S5），落库的分类是事实而不是猜的 ⇒ 按落库 id 筛选是诚实的。
///
/// 判据一律用 `FoodCategory.tryFromId`（控制器 `_applyCategory`）：id 不认识就
/// **不进任何分类**，只留在「全部」里——不回落「其他」，不关键词猜。
/// 旧 `_fromMainRow` 把主库行的分类丢成 null，这一条曾让「按分类筛」把用户自己
/// 导入的整个主库筛空，是 D34 修掉的真实缺陷。
class FoodLibraryView extends StatefulWidget {
  const FoodLibraryView({
    super.key,
    required this.controller,
    required this.revision,
    this.onCreateFood,
    this.onImportFoods,
  });

  final FoodLibraryController controller;

  /// 数据变更版本；变化时当前查询的总数与分页缓存必须一起刷新。
  final int revision;

  /// 自建食物（docs/29 §P8a 需求 29：入口在搜索框右侧）。null = 不渲染该钮
  /// ——依赖缺失时宁可没有入口，也不给点了没反应的按钮。
  final VoidCallback? onCreateFood;

  /// 「导入食物数据」（Round7 阶段 3 · 3-2c）：真·空库时给空态那枚行动钮
  /// （A `app.js:198` 的空库槽位；A 画的是「导入示例食物」，本仓不塞演示数据
  /// ——D41，落点是同一条真实 CSV 导入通路）。null = 不渲染该钮。
  final VoidCallback? onImportFoods;

  @override
  State<FoodLibraryView> createState() => _FoodLibraryViewState();
}

class _FoodLibraryViewState extends State<FoodLibraryView> {
  /// 页缓存的 LRU 上限（docs/28 §8.2）。60 页 = 3,000 条；再往回滑时重新拉。
  static const int _pageCacheLimit = 60;

  final ScrollController _scroll = ScrollController();

  /// 搜索框控制器：只为「清除筛选」能连框里的字一起清（D41）。
  final TextEditingController _search = TextEditingController();

  Timer? _debounce;

  /// 当前查询词：改完/删完要按同一个词重来（输入框本身不受控）。
  String _query = '';

  /// 当前分类筛选；null = 「全部」（不过滤，SQL 与改造前一字不差）。
  FoodCategory? _category;

  /// 陈旧结果守卫：查询词一变就自增，晚到的旧请求据此丢弃自己的结果。
  int _generation = 0;

  bool _loading = true;
  Object? _error;
  int _total = 0;

  /// pageIndex → 该页条目。`LinkedHashMap` 的插入序即 LRU 顺序。
  final LinkedHashMap<int, List<FoodLibraryItem>> _pages =
      LinkedHashMap<int, List<FoodLibraryItem>>();

  /// 正在飞的页（防同一页重复请求）。
  final Set<int> _pending = <int>{};

  /// 加载失败的页：该页渲染一行错误 + 重试，不画假卡。
  final Set<int> _failed = <int>{};

  int get _pageSize => FoodLibraryController.pageSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load('', resetScroll: false);
    });
  }

  @override
  void didUpdateWidget(FoodLibraryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 走 post-frame：_load 第一句就 setState，直接在 build 阶段调会被框架拒。
    if (oldWidget.revision != widget.revision ||
        oldWidget.controller != widget.controller) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _load(value));
  }

  /// 换分类：与换查询词同一条重来路径（清页缓存、取新总数、回列表头）。
  void _onCategoryChanged(FoodCategory? category) {
    if (category == _category) return;
    _category = category;
    _debounce?.cancel();
    _load(_query);
  }

  /// 「清除筛选」（D41/A `app.js:198` 的 `clear-filter`）：查询词与分类一起复位。
  ///
  /// **两样都要清**：只清分类而留着查询词的话，空态会原地不动——按钮点了像
  /// 没反应；只清查询词而留着分类同理。输入框里的字也必须一起清（框里写着
  /// 「米饭」、列表却是全部，是比「点了没反应」更骗人的状态）。
  void _clearFilters() {
    _debounce?.cancel();
    _search.clear();
    _category = null;
    _load('');
  }

  /// 换查询词 / 重来一次：清空缓存、取新总数、加载第一页。
  Future<void> _load(String query, {bool resetScroll = true}) async {
    _query = query;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _total = 0;
      _pages.clear();
      _pending.clear();
      _failed.clear();
    });
    if (resetScroll && _scroll.hasClients) _scroll.jumpTo(0);
    try {
      final total = await widget.controller.count(query, category: _category);
      if (!mounted || generation != _generation) return;
      setState(() {
        _total = total;
        _loading = false;
      });
      if (total > 0) await _loadPage(0, generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// 按当前查询词重来一次（编辑/删除之后必须重来：列表里那份是旧数据）。
  /// 搜索合并结果被缓存，先作废它，否则被删的条目还在。
  Future<void> _reload() {
    widget.controller.invalidate();
    return _load(_query, resetScroll: false);
  }

  Future<void> _loadPage(int pageIndex, [int? generation]) async {
    final gen = generation ?? _generation;
    if (_pages.containsKey(pageIndex) || _pending.contains(pageIndex)) return;
    _pending.add(pageIndex);
    try {
      final items = await widget.controller.page(
        _query,
        offset: pageIndex * _pageSize,
        limit: _pageSize,
        category: _category,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _pages.remove(pageIndex);
        _pages[pageIndex] = items;
        _failed.remove(pageIndex);
        _evictOverflow();
      });
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() => _failed.add(pageIndex));
    } finally {
      if (gen == _generation) _pending.remove(pageIndex);
    }
  }

  /// 超过上限就丢最久没被插入的一页（回滑时重新拉）。
  void _evictOverflow() {
    while (_pages.length > _pageCacheLimit) {
      _pages.remove(_pages.keys.first);
    }
  }

  /// 条目动作层（编辑 / 删除）：页面只把当前控制器与重来回调交给它。
  FoodLibraryItemActions get _actions => FoodLibraryItemActions(
    context: context,
    controller: widget.controller,
    reload: _reload,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 需求 29/30：页头（搜索行 + 自建食物入口）由两条数据路径共用。
        FoodLibraryHeader(
          hintText: '搜索食物名称或品牌',
          onQueryChanged: _onQueryChanged,
          onCreateFood: widget.onCreateFood,
          searchController: _search,
        ),
        // A 页序：搜索 → 分类胶囊 → 结果头 → 列表（`app.js:201`，
        // `.food-category-row` 紧跟在搜索行之后）。横滑、恒定一枚高。
        FoodCategoryChipRow(selected: _category, onChanged: _onCategoryChanged),
        if (!_loading && _error == null) FoodLibraryResultsHead(total: _total),
        // 需求 23：环的满刻度写在明面上（列表头一句，不逐卡重复）。
        const FoodLibraryScaleNoteRow(),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_error != null) {
      return const Center(child: AppErrorText('食物加载失败，请重试。'));
    }
    if (_loading && _total == 0) return const FoodListSkeleton();
    if (_total == 0) {
      return FoodLibraryEmptyState(
        filtered: _query.trim().isNotEmpty || _category != null,
        onClear: _clearFilters,
        onImport: widget.onImportFoods,
      );
    }
    return LfScrollbar(
      controller: _scroll,
      child: CustomScrollView(
        key: const Key('food-library-list'),
        controller: _scroll,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              LfDimens.pagePadding,
              0,
              LfDimens.pagePadding,
              // `RV4-P2-10`：页尾条退役后**底栏预留搬到这里**。
              // 漏这步 = 最后一行被贴底栏压住（`nutrition_subtab_occlusion_test`
              // 与 `food_library_no_footer_test` 的几何判据会红）——这是
              // 「改了就看不出来、但最后一行点不到」的隐蔽坑。
              LfInsets.navReserve(context) + LfDimens.spaceSmall,
            ),
            // A `app.js:195` 的单卡列表：一张 `.card.food-list` 包住整列
            // `.food-row`（Round7 阶段 3 · D36）；行的左右 12 内衬与那层卡面
            // 都在 `FoodListCard` 里。
            sliver: FoodListCard(
              // 行高**已知**才敢跳远端（docs/28 §8.4）；理由与红证见 `_prototypeCard`。
              sliver: SliverPrototypeExtentList.builder(
                prototypeItem: _row(0, _prototypeCard()),
                // **总数**，不是已加载数：滑条位置与总长度因此真实对应，
                // 「手滑到底」能一路加载到最后一页（docs/28 §8.2）。
                itemCount: _total,
                itemBuilder: (context, index) => _row(index, _rowAt(index)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 一行 = 行壳（可选分隔线）+ 行内容。
  ///
  /// **原型与真实行必须走同一层包装**：`SliverPrototypeExtentList` 量的是原型
  /// 外框的高度，包装差一层，真实行就会被挤掉/多出一个东西。
  ///
  /// [FoodListRow] 只叠一条不参与布局的 1px 分隔线（A `.food-row{border-bottom}`，
  /// 末行 `:last-child{border-bottom:0}`）⇒ 行距 = 行高，行高仍等于原型实测值。
  Widget _row(int index, Widget content) => FoodListRow(
    dividerKey: index >= _total - 1
        ? null
        : Key('food-library-row-divider-${_dividerIdFor(index)}'),
    child: content,
  );

  /// 分隔线的 Key 后缀：能取到行的 id 就用 id（测试按行 id 定位），还没数据
  /// （骨架 / 未加载 / 失败行）时用行下标。
  String _dividerIdFor(int index) {
    final pageIndex = index ~/ _pageSize;
    final page = _pages[pageIndex];
    if (page != null) {
      final within = index - pageIndex * _pageSize;
      if (within < page.length) return page[within].id;
    }
    return 'index-$index';
  }

  /// 行高原型：与真行**同一形态**（单行三件：40dp 图标 + 名称 + 36dp 环）。
  ///
  /// 原型只是被量一次，不上屏、不响应点击（`SliverPrototypeExtentList` 的
  /// `prototypeItem` 语义），所以它不进任何用户可见的位置。
  ///
  /// 2026-10-08（docs/30 §2 D1）：行由五段压成单行后**所有变体等高**——「营养
  /// 不完整」不再占独立行，只在名称后加一枚图标（Round7 阶段 3 起是 16dp
  /// `info_outline`）；行高由图标 40 决定。所以这里不再需要「取最高变体」，
  /// 原型就是真行的形态。品牌/宏量/自建这几个参数行上已不渲染，继续传是为了
  /// 少改调用面，行高不受它们影响。
  ///
  /// **为什么非得让行高已知**（真机走查抓出来的卡死）：滑条可以拖到任意位置，
  /// 那会 `jumpTo` 一个几百万像素的 offset。行高已知时跳转是算术，只实体化视口
  /// 那几行；行高未知时（`SliverList`）sliver 只能从当前位置**逐行实体化**到目标
  /// 位置——一帧里要建上万行，主线程卡死（`emulator-5556` 上实测「输入分发超时」
  /// ANR，走查即复现）。这不是性能优化，是能拖到底的前提。
  ///
  /// 原型仍传 `canJoinPlan: false`：将来若有人给卡再加一件**只在某个变体上出现**
  /// 的东西，这里会先把它算进行高（原型只高不矮，真实卡在自己的固定行高里就不会
  /// RenderFlex 溢出）。
  Widget _prototypeCard() => FoodCard(
    id: 'food-library-row-prototype',
    name: '原型食物名称（只用于量行高）',
    // 分类只决定图标字形，各分类都是 40dp 方框，不影响行高；固定取一档保持确定。
    category: FoodCategory.other,
    brand: '原型品牌名称',
    kcalPer100g: 900,
    proteinPer100g: 1,
    carbsPer100g: 1,
    fatPer100g: 1,
    canJoinPlan: false,
    isUserCreated: true,
    onTap: null,
  );

  /// 第 [index] 行：已加载 → 真卡；失败 → 错误 + 重试；否则 → 骨架并登记加载。
  Widget _rowAt(int index) {
    final pageIndex = index ~/ _pageSize;
    final page = _pages[pageIndex];
    if (page != null) {
      final within = index - pageIndex * _pageSize;
      if (within < page.length) return _card(page[within]);
      // 页比预期短（总数刚变小）：留一个与卡片同高的空位，别让布局跳。
      return const FoodCardSkeleton();
    }
    if (_failed.contains(pageIndex)) {
      // 一行错误 + 重试挂在这一页的**第一格**上；同一页其余格收起（零高），
      // 否则 50 格会画出 50 个带同名 Key 的重试行。
      if (index == pageIndex * _pageSize) return _pageFailure(pageIndex);
      return const SizedBox.shrink();
    }
    // 未加载区间：登记该页待加载，本轮画骨架（诚实：不画假卡）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPage(pageIndex);
    });
    return const FoodCardSkeleton();
  }

  /// 一页加载失败：**一行**内联「说明 + 重试」。
  ///
  /// 2026-10-08（docs/30 §2 D1）：卡由五段压成单行后，行高从 ≈136dp 掉到
  /// ≈56dp（原型卡高 = 图标 40 + 上下各 8）。原先那版是**竖排**的「文字 + 按钮」
  /// 装在一个写死 96dp 的盒子里 —— 在 56dp 的行里实测 RenderFlex overflow 13px
  /// （真机上是黄黑条纹 + 裁掉的重试按钮）。所以这里改成一行横排，并用
  /// `FittedBox.scaleDown` 兜底：任何字号下行高都由原型卡决定，塞不下时等比
  /// 缩小而不是溢出（与食物环中心数字同一套退化策略）。
  ///
  /// 不套卡：行的上下内边距（8）+ 按钮的 48dp 触达盒已经等于行高，再套一层必然
  /// 溢出；Round7 阶段 3 起行也不再有各自的卡面（卡面在 `FoodListCard` 那一层）。
  Widget _pageFailure(int pageIndex) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '这一段没加载出来。',
            key: Key('food-library-page-error-$pageIndex'),
            style: LfText.caption.copyWith(color: context.lf.mutedForeground),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          LfTextButton(
            key: Key('food-library-page-retry-$pageIndex'),
            onPressed: () {
              setState(() => _failed.remove(pageIndex));
              _loadPage(pageIndex);
            },
            label: '重试',
          ),
        ],
      ),
    ),
  );

  Widget _card(FoodLibraryItem item) => FoodCard(
    key: Key('food-library-item-${item.id}'),
    id: item.id,
    // 名称清洗在卡内做（`splitFoodName`）：这里传原始 name，
    // 搜索仍按原始 name 匹配，卡上只显示产品名 + 底行品牌。
    name: item.name,
    category: FoodCategory.classify(
      name: item.name,
      rawCategory: item.category,
    ),
    isUserCreated: item.isUserCreated,
    brand: item.brand,
    kcalPer100g: item.kcalPer100g,
    proteinPer100g: item.proteinPer100g,
    carbsPer100g: item.carbsPer100g,
    fatPer100g: item.fatPer100g,
    canJoinPlan: item.canJoinPlan,
    // 详情弹层：控制器没配装载器时不给 onTap——点了没反应的入口比没有入口更糟。
    // 编辑/删除只在自建条目上挂（D1/N8）：内置条目界面上不给任何写入口，
    // 数据层还会再拒一次。
    onTap: widget.controller.canShowDetail
        ? () => FoodDetailSheet.show(
            context,
            item: item,
            load: () => widget.controller.loadDetail(item),
            onEdit: item.isUserCreated ? () => _actions.edit(item) : null,
            onDelete: item.isUserCreated ? () => _actions.delete(item) : null,
          )
        : null,
  );
}
