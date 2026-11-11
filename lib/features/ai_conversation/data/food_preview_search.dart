import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// AI 对话发送前的**本地食物名预检索**（docs/40 §2.4 / docs/41 §7）。
///
/// 模型看不到 2 万行食物库（快照只带自建食物），但用户说「我吃了 200g 米饭」
/// 时，把**本次相关的 3 条**（名称 / 每 100g 值 / 来源徽标）作为
/// 「食物库参考」段注入快照，模型就不必把「米饭 116 kcal」当推测编出来。
///
/// 纪律：
/// * **全程本地、同步执行**（单次 SQL，无网络、无 AI 调用）——失败返回空，
///   绝不让预检索问题挡住一次对话（与快照的段级失败语义一致）；
/// * 只做**建议**：命中行带 id，模型据此引用/提议，不许把预检索当成
///   「已确认用户吃了什么」。
final class FoodPreviewSearch {
  const FoodPreviewSearch({required this.database});

  final AppDatabase database;

  /// 消息文本 → 至多 [limit] 条候选（精确同名优先，其次包含命中）。
  ///
  /// 查询词：先试整句 trim；没命中再退到「去掉常见动词/量词后的尾巴」
  /// 由调用方决定是否重试（本类保持无状态）。
  Future<List<FoodRecord>> search(
    String message, {
    int limit = kFoodPreviewLimit,
  }) async {
    final query = message.trim();
    if (query.isEmpty || limit <= 0) return const [];
    // 2026-11-11 复核：候选词不能只有「整句」或「动词后一个词」。用户的长句
    // （「帮我记早餐：米饭 100 克和紫米饭 150 克，…」）整句 LIKE 必然零命中，
    // 模型就看不到库里的食物（实测回「快照未提供条目」）。这里按标点/连词
    // 切词、剥掉数量与单位，再逐个查；整句仍保留作兜底。
    final candidates = <String>{
      ?_stripCommonPhrases(query),
      query,
      ..._keywordTerms(query),
    }.take(_maxPreviewTerms);
    final result = <String, FoodRecord>{};
    for (final term in candidates) {
      if (term.trim().isEmpty) continue;
      // ① 精确同名（食物库的权威命中）。
      for (final row in await _exact(term)) {
        result.putIfAbsent(row.id, () => row);
      }
      if (result.length >= limit) break;
      // ② 别名精确（用户维护的叫法）。
      for (final row in await _viaAlias(term)) {
        result.putIfAbsent(row.id, () => row);
      }
      if (result.length >= limit) break;
      // ③ 名称包含（相关性排序与食物库搜索同一套：完全匹配 > 位置靠前 > 名称更短）。
      for (final row in await _contains(term, limit: limit)) {
        result.putIfAbsent(row.id, () => row);
      }
      if (result.length >= limit) break;
    }
    final rows = result.values.take(limit).toList(growable: false);
    return rows;
  }

  static const int kFoodPreviewLimit = 3;

  Future<List<FoodRecord>> _exact(String term) async {
    final rows =
        await (database.select(database.foods)
              ..where((row) => row.name.equals(term))
              ..limit(kFoodPreviewLimit))
            .get();
    return rows.map(_map).toList(growable: false);
  }

  Future<List<FoodRecord>> _viaAlias(String term) async {
    final aliasRows =
        await (database.select(database.foodAliases)
              ..where((row) => row.normalizedText.equals(term))
              ..limit(kFoodPreviewLimit))
            .get();
    if (aliasRows.isEmpty) return const [];
    final foodRows =
        await (database.select(database.foods)..where(
              (row) =>
                  row.id.isIn([for (final alias in aliasRows) alias.foodId]),
            ))
            .get();
    return foodRows.map(_map).toList(growable: false);
  }

  Future<List<FoodRecord>> _contains(String term, {required int limit}) async {
    final escaped = term
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows =
        await (database.select(database.foods)
              ..where((row) => row.name.like('%$escaped%', escapeChar: r'\'))
              ..orderBy([
                (row) => OrderingTerm.desc(row.name.equals(term)),
                (row) => OrderingTerm.asc(
                  FunctionCallExpression<int>('instr', [
                    row.name,
                    Constant(term),
                  ]),
                ),
                (row) => OrderingTerm.asc(
                  FunctionCallExpression<int>('length', [row.name]),
                ),
                (row) => OrderingTerm.asc(row.name),
              ])
              ..limit(limit))
            .get();
    return rows.map(_map).toList(growable: false);
  }

  /// 长句 → 可能的食物词（尽力而为，不做 NLP）。
  ///
  /// 按标点/连词切分，去掉开头的人称与动词、结尾的「数字 + 单位 + 余下说明」，
  /// 只保留 2–12 字的候选。命中与否仍由 SQL 决定，这里只负责别把整句塞给 LIKE。
  static Iterable<String> _keywordTerms(String message) sync* {
    final parts = message.split(RegExp(r'[，。；：、,.;:!?！？\s]|和|与|跟|还有|以及'));
    for (final raw in parts) {
      var token = raw.trim();
      if (token.isEmpty) continue;
      token = token.replaceFirst(
        RegExp(r'^(帮我|请|给我|我要|我想|然后|再|把|将|记一下|记录|添加|加进)+'),
        '',
      );
      // 餐次 + 吃了/喝了 + 中文数量 + 单位（「午饭吃了一碗米饭」→「米饭」）。
      // 单位必须命中白名单，避免误伤「三文鱼」「半熟芝士」这类名字。
      token = token.replaceFirst(
        RegExp(
          r'^(?:早饭|早餐|午饭|午餐|晚饭|晚餐|夜宵|加餐|今天|刚才|我)?'
          r'(?:吃了|喝了|吃|喝|了)*'
          r'(?:(?:[0-9０-９一二两三四五六七八九十半]+)'
          r'(?:碗|个|杯|份|根|块|片|勺|盒|袋|瓶|只|颗|串|盘))+',
        ),
        '',
      );
      // 从第一个数量/单位处截断（「米饭 100 克」→「米饭」）。
      token = token
          .replaceFirst(
            RegExp(
              // 只在**出现数字**处截断：食物名本身可能含「三/半/两」
              // （三文鱼、半熟芝士），不能用中文数字当分隔。
              r'\s*[0-9０-９]+\s*'
              r'(?:克|g|G|毫升|ml|ML|个|只|碗|杯|份|根|块|片|勺|盒|袋|瓶)?.*$',
            ),
            '',
          )
          .trim();
      if (token.length >= 2 && token.length <= 12) yield token;
    }
  }

  static const int _maxPreviewTerms = 6;

  /// 「我早上吃了 200 克米饭和两个鸡蛋」→「米饭」这类**尽力而为**的裁剪：
  /// 只剥常见动词短语，不做真正的 NLP；剥不出就原样查整句（LIKE 兜底）。
  String? _stripCommonPhrases(String message) {
    final match = RegExp(
      r'(?:吃了?|喝(?:了)?|来(?:了)?|点(?:了)?|要(?:了)?)\s*'
      r'(?:一|两|三|四|五|半|\d+)?\s*'
      r'(?:[个只碗杯份根块片勺克gG毫升mlML]+)?\s*'
      r'([\u4e00-\u9fa5A-Za-z]{2,8})',
    ).firstMatch(message);
    return match?.group(1);
  }

  FoodRecord _map(Food row) => FoodRecord(
    id: row.id,
    name: row.name,
    kcalPer100g: row.kcalPer100g,
    proteinPer100g: row.proteinPer100g,
    carbsPer100g: row.carbsPer100g,
    fatPer100g: row.fatPer100g,
    isUserCreated: row.isUserCreated,
    brand: row.brand,
    defaultServingGrams: row.defaultServingGrams,
    category: null,
  );
}
