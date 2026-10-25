import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;

/// docs/07 §5.7 的匹配层：命中越精确越靠前，同层内再按 bm25。
///
/// 前四层与最后一层是规范点名的顺序（精确 canonical 名称 > 用户常用别名 >
/// 中文前缀 > 拼音/英文别名 > 品牌和分类）。规范没有点名的第五种情况——主名
/// 或别名**包含**查询但不是前缀——单独放在 [nameToken]：它排在 [namePrefix]
/// 之后、[aliasPrefix] 之前，即「名称命中一律优先于别名命中，别名一律优先于
/// 只命中品牌/分类」。这是对规范末层的细化，规范点名的五个层相对顺序不变。
///
/// 用户自己的别名与自建条目不在这里——它们在主库里，由
/// `FoodLibraryController` 排在目录结果之前。
enum CatalogMatchTier {
  /// 主名与查询完全一致。
  exactName,

  /// 别名（翻译名/常用名）与查询完全一致，主名不是。
  exactAlias,

  /// 主名以查询开头（规范里的「中文前缀」）。
  namePrefix,

  /// 主名/别名包含查询但不是前缀。
  nameToken,

  /// 别名以查询开头（拼音/英文别名）。
  aliasPrefix,

  /// 只命中品牌或分类（规范末层）。
  brandCategory,
}

/// 目录搜索结果行。
class CatalogSearchResult {
  const CatalogSearchResult({
    required this.id,
    required this.name,
    required this.state,
    required this.brand,
    required this.category,
    required this.kcalPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    this.tier = CatalogMatchTier.brandCategory,
  });

  final String id;
  final String name;
  final String state;

  /// docs/07 §5.7：incomplete 行可搜索但不能加入确认计划。
  bool get canJoinPlan => state == 'verified' || state == 'estimated';

  final String? brand;
  final String? category;
  final double? kcalPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;

  /// 这条命中落在哪一层（docs/07 §5.7）；排序已按层生效，页面展示不需要再用它。
  final CatalogMatchTier tier;
}

class CatalogSearchPage {
  const CatalogSearchPage({required this.items});

  final List<CatalogSearchResult> items;
}

/// 分片 FTS5 搜索（docs/07 §5.7）。
///
/// 只读打开随包/已导入分片（ETL 产出的 `food_search` FTS5 表），跨分片
/// 合并去重；主库 foods（用户自建/既有行）由调用方另行合并，本服务不触
/// SQLCipher 主库。CJK 通过 ETL 阶段逐字空格化 token 命中。
///
/// 排序是「匹配层 + bm25」（docs/07 §5.7）：每个分片取两批候选再合并——
///
/// 1. **分层探测**：`{text} : "…" *`，只在主名/别名那一列里找连续命中，
///    所以品牌与分类不会挤掉精确名；批内按 bm25。
/// 2. **bm25 窗口**：原来的 token 查询（隐式 AND），覆盖品牌与分类命中。
///
/// 全量 FTS5 搜索（docs/07 §5.7 分页限制已取消）。
final class CatalogSearchService {
  CatalogSearchService({required List<String> shardPaths})
    : _shardPaths = List.of(shardPaths);

  /// 单个分片单次查询的候选上限。
  static const int _maxCandidatesPerShard = 1000;

  final List<String> _shardPaths;

  CatalogSearchPage search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return CatalogSearchPage(items: const []);
    }

    // FTS5 查询串：ETL 对 CJK 逐字空格化（每字一个 token）；英文按空白
    // 分词。查询侧镜像：连续拉丁字母合成一个词级 token（前缀匹配），
    // CJK 逐字拆 token，全部隐式 AND。
    final tokens = _queryTokens(trimmed);
    if (tokens.isEmpty) {
      return CatalogSearchPage(items: const []);
    }
    final match = tokens.map((token) => '$token*').join(' ');
    // 分层探测：短语 + 结尾前缀（`*` 必须在引号外，放引号里会被当成普通
    // 字符——0 命中）。只在 text 列里匹配，主名与别名都在这一列。
    final tierProbe = '{text} : "${tokens.join(' ')}" *';
    final limit = _maxCandidatesPerShard;
    final normalizedQuery = _normalize(trimmed);

    // id → 最好的一层（LinkedHashMap 保序）。
    final merged = <String, _Candidate>{};
    for (final path in _shardPaths) {
      // 路径是启动时扫出来的，文件之后被删/被换都可能：缺文件跳过，
      // 别让整页搜索报错（其余分片照样出结果）。
      if (!File(path).existsSync()) continue;
      // 文件还在但内容坏了（下载/拷贝被截断、磁盘位翻转、被别的进程写坏）
      // 属于同一类「这一片用不了」：单片异常只跳过这一片。分片是可再分发的
      // 目录缓存，不是用户数据，没道理为了它让整个搜索抛错。
      try {
        final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
        try {
          _collect(db, tierProbe, limit, normalizedQuery, merged);
          _collect(db, match, limit, normalizedQuery, merged);
        } finally {
          db.dispose();
        }
      } catch (_) {
        continue;
      }
    }

    final ordered = merged.values.toList()
      ..sort((a, b) {
        final byTier = a.tier.index.compareTo(b.tier.index);
        if (byTier != 0) return byTier;
        final byScore = a.score.compareTo(b.score);
        if (byScore != 0) return byScore;
        return a.result.id.compareTo(b.result.id);
      });

    return CatalogSearchPage(items: ordered.map((c) => c.result).toList());
  }

  /// 跑一批 FTS 查询并把命中并进 [merged]，同一条食物保留更好的层与 bm25。
  void _collect(
    sqlite.Database db,
    String match,
    int limit,
    String normalizedQuery,
    Map<String, _Candidate> merged,
  ) {
    // 顺序不能反：FTS 先在子查询里按 bm25 取 top-N，再按主键关联 foods。
    // JOIN 写在外层时 SQLite 会把整批 MATCH 命中行先关联再排序，实测 85 分片、
    // 170 万条下 `chicken*` 要 203 ms，FTS 先取 id 只要 55 ms（2.0-1h 的 50k/100k
    // 真分片实测）。
    final rows = db.select(
      'SELECT f.id, f.name, f.state, f.brand, f.category,'
      ' f.kcal_per100g, f.protein_per100g, f.carbs_per100g, f.fat_per100g,'
      ' s.text AS matched_text, s.score AS score'
      ' FROM (SELECT food_id, text, bm25(food_search) AS score FROM food_search'
      ' WHERE food_search MATCH ? ORDER BY bm25(food_search) LIMIT ?) s'
      ' JOIN foods f ON f.id = s.food_id',
      [match, limit],
    );
    for (final row in rows) {
      final id = row['id'] as String;
      final name = row['name'] as String;
      final score = (row['score'] as num).toDouble();
      final tier = _tierOf(
        name: name,
        matchedText: (row['matched_text'] as String?) ?? name,
        normalizedQuery: normalizedQuery,
      );
      final existing = merged[id];
      if (existing != null) {
        if (existing.tier.index < tier.index) continue;
        if (existing.tier == tier && existing.score <= score) continue;
      }
      merged[id] = _Candidate(
        tier: tier,
        score: score,
        result: CatalogSearchResult(
          id: id,
          name: name,
          state: row['state'] as String,
          brand: row['brand'] as String?,
          category: row['category'] as String?,
          kcalPer100g: (row['kcal_per100g'] as num?)?.toDouble(),
          proteinPer100g: (row['protein_per100g'] as num?)?.toDouble(),
          carbsPer100g: (row['carbs_per100g'] as num?)?.toDouble(),
          fatPer100g: (row['fat_per100g'] as num?)?.toDouble(),
          tier: tier,
        ),
      );
    }
  }

  /// 匹配层判定（docs/07 §5.7）。[matchedText] 是命中的那一行 FTS 文本：主名行
  /// 就是主名本身，别名行是别名，两者都已按 CJK 逐字空格化。
  ///
  /// 判断「命中来自名称列还是品牌/分类列」只靠 [matchedText] 是否包含查询：
  /// 名称/别名行都是整行文本匹配，品牌与分类命中不会出现在这一列里。少数
  /// 情况（令牌跨列分别命中、或 CJK 名称里查询字序被打乱）会被保守地算成
  /// [CatalogMatchTier.brandCategory]——只影响末两层的先后，不影响精确名与
  /// 前缀的优先。
  CatalogMatchTier _tierOf({
    required String name,
    required String matchedText,
    required String normalizedQuery,
  }) {
    final nameKey = _normalize(name);
    if (nameKey == normalizedQuery) return CatalogMatchTier.exactName;
    final textKey = _normalize(matchedText);
    if (textKey == normalizedQuery) return CatalogMatchTier.exactAlias;
    if (nameKey.startsWith(normalizedQuery)) {
      return CatalogMatchTier.namePrefix;
    }
    if (textKey.startsWith(normalizedQuery)) {
      return CatalogMatchTier.aliasPrefix;
    }
    if (textKey.contains(normalizedQuery)) return CatalogMatchTier.nameToken;
    return CatalogMatchTier.brandCategory;
  }

  /// 比较键：去掉空白再小写，让「牛 奶」（FTS 文本）与「牛奶」（用户输入）
  /// 以及大小写差异不会破坏精确/前缀判定。
  String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 防注入：剥离 FTS5 语法字符，只留字母数字与 CJK。
  String _ftsEscape(String token) => token
      .split('')
      .where(
        (c) => RegExp(r'[0-9A-Za-z\u00c0-\u024f\u4e00-\u9fff]').hasMatch(c),
      )
      .join();

  /// 查询分词：先按空白拆段，段内连续拉丁/数字合成词级 token、CJK 逐字。
  List<String> _queryTokens(String query) {
    final tokens = <String>[];
    for (final segment in query.split(RegExp(r'\s+'))) {
      final cleaned = _ftsEscape(segment);
      final latin = StringBuffer();
      for (final char in cleaned.split('')) {
        if (RegExp(r'[\u4e00-\u9fff]').hasMatch(char)) {
          if (latin.isNotEmpty) {
            tokens.add(latin.toString());
            latin.clear();
          }
          tokens.add(char);
        } else {
          latin.write(char.toLowerCase());
        }
      }
      if (latin.isNotEmpty) tokens.add(latin.toString());
    }
    return tokens;
  }
}

/// 合并期的中间态：分层排序要同时看层、bm25 与结果本身。
class _Candidate {
  const _Candidate({
    required this.tier,
    required this.score,
    required this.result,
  });

  final CatalogMatchTier tier;

  /// FTS5 `bm25()`：负数，越小越相关。
  final double score;

  final CatalogSearchResult result;
}
