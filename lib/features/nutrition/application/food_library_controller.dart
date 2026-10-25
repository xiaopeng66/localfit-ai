import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/food_detail_loader.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_detail.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_write_failure.dart';

/// 食物库搜索结果项：主库与目录分片归一视图（2.0-6f）。
class FoodLibraryItem {
  const FoodLibraryItem({
    required this.id,
    required this.name,
    required this.source,
    required this.state,
    required this.canJoinPlan,
    this.brand,
    this.category,
    this.isUserCreated = false,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
  });

  final String id;
  final String name;

  /// 主库（用户自建/既有种子）= main；目录分片 = catalog。
  final String source;

  /// foods.state：verified | estimated | user_created | incomplete…
  final String state;

  /// docs/07 §5.7：incomplete 可搜索但不能加入确认计划。
  final bool canJoinPlan;
  final String? brand;
  final String? category;

  /// docs/28 §5.1 D2：卡上的「自建 / 内置」两档标识。目录分片永远不是自建
  /// （它是导入的上游数据），所以这里只有主库行会给 `true`。
  final bool isUserCreated;

  final double? kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
}

/// 食物库浏览 / 搜索控制器（application 层；页面零 SQL）。
///
/// 两条数据路径共用一对接口 [count] + [page]（docs/28 §8.2）：
///  * **默认浏览**（空查询）：主库走 SQL `LIMIT/OFFSET` 分页，4.9 万条不整体载入；
///    [count] 是 `COUNT(*)` 真实总数——滑条长度代表真实总量，不是已加载量。
///  * **搜索**（非空查询）：主库 LIKE + 目录分片 FTS5 合并去重后按页切片；
///    合并结果按查询词缓存一次（目录搜索是同步全量调用，每页重跑没有意义）。
class FoodLibraryController {
  FoodLibraryController({
    required this.repository,
    required this.catalogSearch,
    this.detailLoader,
  });

  /// 一页的条数。滑条与分页换算都以它为准（视图层与控制器共用一个常量）。
  static const int pageSize = 50;

  /// 搜索路径下一次取多少条主库命中。与目录分片单次候选上限（1000）对齐，
  /// 让两侧都不会成为新的瓶颈（旧实现是 30 条，正是 D5 抱怨的成因）。
  static const int _searchMainLimit = 1000;

  final FoodRepository repository;
  final CatalogSearchService catalogSearch;

  /// 详情装载器（2.0-1j）。没配时列表行不可点：不给一个点了没反应的入口。
  final FoodDetailLoader? detailLoader;

  /// 搜索合并结果的缓存：key = 查询词，value = 去重后的完整列表。
  /// 默认浏览**不**走这里——主库不整体载入内存。
  String? _mergedQuery;
  List<FoodLibraryItem> _merged = const [];
  int _cacheRevision = 0;
  int _searchRequest = 0;

  /// 是否可展示详情（列表行据此决定要不要挂 onTap）。
  bool get canShowDetail => detailLoader != null;

  /// 读某个搜索结果的详情（主库 / 分片路由见 [FoodDetailLoader]）。
  Future<FoodDetail?> loadDetail(FoodLibraryItem item) async {
    final loader = detailLoader;
    if (loader == null) return null;
    return loader.load(item.id, source: item.source);
  }

  /// 取一条自建食物（编辑弹层的初值）。
  Future<FoodRecord?> foodById(String id) => repository.getById(id);

  /// 取一条食物的别名（编辑弹层回显；ADR-037）。
  Future<List<String>> aliasesFor(String id) => repository.aliasesFor(id);

  /// 改一条自建食物；返回 `null` = 成功，返回文案 = 留在弹层里显示（N7）。
  ///
  /// 固定文案（内置条目 / 条目已消失）由
  /// [FoodWriteFailure] 承载；其它异常翻成一句通用话——不把 `SqliteException`
  /// 之类的内部措辞摆到用户面前。
  Future<String?> updateFood(String id, NewFood food) async {
    try {
      await repository.update(id, food);
      return null;
    } on FoodWriteFailure catch (failure) {
      return failure.message;
    } catch (_) {
      return '保存失败，请重试。';
    }
  }

  /// 删一条自建食物；返回 `null` = 成功，返回文案 = 显示给用户（不关窗）。
  Future<String?> deleteFood(String id) async {
    try {
      await repository.delete(id);
      return null;
    } on FoodWriteFailure catch (failure) {
      return failure.message;
    } catch (_) {
      return '删除失败，请重试。';
    }
  }

  /// 命中总数（docs/28 §8.2）：滑条长度与顶部计数都读它。
  ///
  /// 默认浏览 = 主库 `COUNT(*)`（真实 4.9 万，不是已加载条数）；搜索 = 主库 +
  /// 目录合并去重后的条数。
  ///
  /// [category] 非空时只数该分类（Round7 阶段 3）：两条路径都过同一个判据
  /// ——**落库的枚举 id**（[FoodCategory.tryFromId]），浏览路径下推到 SQL，
  /// 搜索路径在合并列表上过滤。没落库分类的行不属于任何分类。
  Future<int> count(String query, {FoodCategory? category}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return repository.count(category: category);
    final items = _applyCategory(await _mergedSearch(trimmed), category);
    return items.length;
  }

  /// 取第 [offset] 条起的 [limit] 条。
  ///
  /// 默认浏览走主库 SQL 分页（不整体载入内存）；搜索在缓存好的合并列表上切片。
  Future<List<FoodLibraryItem>> page(
    String query, {
    required int offset,
    required int limit,
    FoodCategory? category,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      final rows = await repository.page(
        offset: offset,
        limit: limit,
        category: category,
      );
      return rows.map(_fromMainRow).toList(growable: false);
    }
    final items = _applyCategory(await _mergedSearch(trimmed), category);
    if (offset >= items.length) return const [];
    final end = (offset + limit).clamp(0, items.length);
    return items.sublist(offset, end);
  }

  /// 清掉搜索合并缓存。编辑 / 删除之后必须调用：缓存里那份是旧数据
  /// （被删的条目仍会出现在搜索结果里）。
  void invalidate() {
    _cacheRevision++;
    _mergedQuery = null;
    _merged = const [];
  }

  Future<List<FoodLibraryItem>> _mergedSearch(String trimmed) async {
    final request = ++_searchRequest;
    return _searchAtRevision(trimmed, request);
  }

  Future<List<FoodLibraryItem>> _searchAtRevision(
    String trimmed,
    int request,
  ) async {
    if (_mergedQuery == trimmed) return _merged;
    final revision = _cacheRevision;
    final merged = <String, FoodLibraryItem>{};
    final mainRows = await repository.page(
      query: trimmed,
      offset: 0,
      limit: _searchMainLimit,
    );
    for (final row in mainRows) {
      merged[row.id] = _fromMainRow(row);
    }
    for (final row in catalogSearch.search(trimmed).items) {
      if (merged.containsKey(row.id)) continue;
      merged[row.id] = FoodLibraryItem(
        id: row.id,
        name: row.name,
        source: 'catalog',
        state: row.state,
        canJoinPlan: row.canJoinPlan,
        brand: row.brand,
        category: row.category,
        kcalPer100g: row.kcalPer100g,
        proteinPer100g: row.proteinPer100g,
        carbsPer100g: row.carbsPer100g,
        fatPer100g: row.fatPer100g,
      );
    }
    if (revision != _cacheRevision) {
      return _searchAtRevision(trimmed, request);
    }
    final items = merged.values.toList(growable: false);
    if (request == _searchRequest) {
      _mergedQuery = trimmed;
      _merged = items;
    }
    return items;
  }

  FoodLibraryItem _fromMainRow(FoodRecord row) => FoodLibraryItem(
    id: row.id,
    name: row.name,
    source: 'main',
    state: row.isUserCreated ? 'user_created' : 'verified',
    canJoinPlan: true,
    isUserCreated: row.isUserCreated,
    brand: row.brand,
    // Round7 阶段 3（D34）：主库行必须带上**落库分类**。旧实现这里恒为 null
    // ⇒ 搜索路径的分类筛选只会留下目录分片行，把用户自己导入的整个主库筛空
    // （4.9 万条里有分类的是绝大多数）。`FoodRecord.category` 是 v11 起的域
    // 字段，本步只是把它接上，没动库结构。
    category: row.category?.id,
    kcalPer100g: row.kcalPer100g,
    proteinPer100g: row.proteinPer100g,
    carbsPer100g: row.carbsPer100g,
    fatPer100g: row.fatPer100g,
  );

  /// 分类筛选：两侧都按**落库枚举 id** 归一后比较。
  ///
  /// 主库行的 `category` 是枚举 id（上一步写进去的）；目录分片行是**上游原串**
  /// （如 `noodle`/`bakery`）——能反查到枚举的（恰好等于某个 id）留下，反查
  /// 不到的不猜、不回落，只在「全部」里出现。用 `classify(name:)` 的关键词表
  /// 给它们补分类是**猜测**：那正是 `FoodLibraryView` 拒绝把分类当筛选器的
  /// 理由（中文覆盖弱，会把大多数条目挤进同一格）。
  List<FoodLibraryItem> _applyCategory(
    List<FoodLibraryItem> items,
    FoodCategory? category,
  ) {
    if (category == null) return items;
    return items
        .where((item) => FoodCategory.tryFromId(item.category) == category)
        .toList(growable: false);
  }
}
