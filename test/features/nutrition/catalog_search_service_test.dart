import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 分片布局与 ETL SHARD_SCHEMA 同形（含 food_search FTS5 表）。
void main() {
  late Directory tempDir;
  late sqlite.Database shardDb;
  late String shardPath;

  /// 与 ETL `_cjk_spaced` 同形：CJK 逐字空格化，拉丁段整词。
  String cjkSpaced(String text) {
    final out = <String>[];
    final buffer = StringBuffer();
    for (final char in text.split('')) {
      if (RegExp(r'[\u4e00-\u9fff]').hasMatch(char)) {
        if (buffer.isNotEmpty) {
          out.add(buffer.toString());
          buffer.clear();
        }
        out.add(char);
      } else {
        buffer.write(char);
      }
    }
    if (buffer.isNotEmpty) out.add(buffer.toString());
    return out.join(' ');
  }

  void food(
    String id,
    String name, {
    String state = 'verified',
    String? brand,
    String? category,
    double kcal = 100,
  }) {
    shardDb.execute(
      'INSERT INTO foods (id, name, state, locale, category, brand,'
      ' kcal_per100g, protein_per100g, carbs_per100g, fat_per100g,'
      " source_id, license_status) VALUES ('$id', '$name', '$state', 'zh',"
      " ${category == null ? 'NULL' : "'$category'"},"
      " ${brand == null ? 'NULL' : "'$brand'"}, $kcal, 1, 1, 1,"
      " 'openfoodfacts', 'allowed')",
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-search-');
    shardPath = '${tempDir.path}${Platform.pathSeparator}foods-core-000.sqlite';
    shardDb = sqlite.sqlite3.open(shardPath);
    shardDb.execute('''
CREATE TABLE foods (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  state TEXT NOT NULL,
  locale TEXT,
  category TEXT,
  brand TEXT,
  kcal_per100g REAL,
  protein_per100g REAL,
  carbs_per100g REAL,
  fat_per100g REAL,
  source_id TEXT NOT NULL,
  source_version TEXT,
  license_status TEXT NOT NULL
);
CREATE TABLE aliases (
  food_id TEXT NOT NULL REFERENCES foods(id),
  normalized_text TEXT NOT NULL,
  language TEXT,
  alias_type TEXT,
  confidence REAL NOT NULL DEFAULT 1.0
);
CREATE VIRTUAL TABLE food_search USING fts5(food_id UNINDEXED, text, brand, category);
''');
    // 中文、英文、品牌、别名与 incomplete 混合。
    food('f1', '宫保鸡丁', category: 'chuan');
    food('f2', '蒸米饭');
    food('f3', 'Steamed Rice', brand: 'Generic');
    food('f4', '面包', brand: '烘焙坊', state: 'incomplete');
    shardDb.execute(
      "INSERT INTO aliases (food_id, normalized_text, language, alias_type,"
      " confidence) VALUES ('f1', 'kung pao chicken', 'en', 'translation',"
      ' 0.9), (\'f2\', \'白米饭\', \'zh\', \'common\', 1.0)',
    );
    for (final f in const [
      ('f1', '宫 保 鸡 丁', '', 'chuan'),
      ('f2', '蒸 米 饭', '', ''),
      ('f3', 'Steamed Rice', 'Generic', ''),
      ('f4', '面 包', '烘 焙 坊', ''),
      // 别名行也进 FTS（与 ETL 一致：别名 ≠ 主名才另立 FTS 行）。
      ('f1', 'kung pao chicken', '', ''),
      ('f2', '白 米 饭', '', ''),
    ]) {
      shardDb.execute(
        "INSERT INTO food_search (food_id, text, brand, category)"
        " VALUES ('${f.$1}', '${f.$2}', '${f.$3}', '${f.$4}')",
      );
    }
  });

  tearDown(() {
    shardDb.dispose();
    tempDir.deleteSync(recursive: true);
  });

  group('catalog search service', () {
    test('finds CJK names via per-character tokens', () {
      final service = CatalogSearchService(shardPaths: [shardPath]);
      final page = service.search('宫保');
      expect(page.items.map((r) => r.id), contains('f1'));
      expect(page.items.singleWhere((r) => r.id == 'f1').name, '宫保鸡丁');
    });

    test('matches english aliases and brand names', () {
      final service = CatalogSearchService(shardPaths: [shardPath]);
      expect(service.search('kung pao').items.map((r) => r.id), contains('f1'));
      expect(service.search('Generic').items.map((r) => r.id), contains('f3'));
    });

    test('marks incomplete rows so they cannot join a confirmed plan', () {
      final service = CatalogSearchService(shardPaths: [shardPath]);
      final hit = service.search('面包').items.singleWhere((r) => r.id == 'f4');
      expect(hit.state, 'incomplete');
      expect(hit.canJoinPlan, isFalse);
    });

    test('returns all matches without pagination', () {
      // 再塞 60 条匹配「批量」的食物。
      for (var i = 0; i < 60; i++) {
        shardDb.execute(
          "INSERT INTO foods (id, name, state, locale, kcal_per100g,"
          " protein_per100g, carbs_per100g, fat_per100g, source_id,"
          " license_status) VALUES ('bulk$i', '批量食物$i', 'verified', 'zh',"
          " 100, 1, 1, 1, 'openfoodfacts', 'allowed')",
        );
        shardDb.execute(
          "INSERT INTO food_search (food_id, text, brand, category)"
          " VALUES ('bulk$i', '批 量 食 物 $i', '', '')",
        );
      }
      final service = CatalogSearchService(shardPaths: [shardPath]);
      // 不再分页：一次返回全部 60 条匹配。
      final page = service.search('批量');
      expect(page.items, hasLength(60));
      expect(page.items.map((r) => r.id).toSet(), hasLength(60));
    });

    test('returns empty for blank queries', () {
      final service = CatalogSearchService(shardPaths: [shardPath]);
      expect(service.search('   ').items, isEmpty);
    });

    test('caps candidates per shard without truncating to a page', () {
      final service = CatalogSearchService(shardPaths: [shardPath]);
      for (var i = 0; i < 60; i++) {
        shardDb.execute(
          "INSERT INTO foods (id, name, state, locale, kcal_per100g,"
          " protein_per100g, carbs_per100g, fat_per100g, source_id,"
          " license_status) VALUES ('cap$i', '容量食物$i', 'verified', 'zh',"
          " 100, 1, 1, 1, 'openfoodfacts', 'allowed')",
        );
        shardDb.execute(
          "INSERT INTO food_search (food_id, text, brand, category)"
          " VALUES ('cap$i', '容 量 食 物 $i', '', '')",
        );
      }
      expect(service.search('容量').items, hasLength(60));
    });

    test('searches across multiple shards and dedupes by food id', () {
      final secondPath =
          '${tempDir.path}${Platform.pathSeparator}foods-core-001.sqlite';
      final db2 = sqlite.sqlite3.open(secondPath);
      db2.execute('''
CREATE TABLE foods (
  id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, state TEXT NOT NULL,
  locale TEXT, category TEXT, brand TEXT, kcal_per100g REAL,
  protein_per100g REAL, carbs_per100g REAL, fat_per100g REAL,
  source_id TEXT NOT NULL, source_version TEXT, license_status TEXT NOT NULL
);
CREATE VIRTUAL TABLE food_search USING fts5(food_id UNINDEXED, text, brand, category);
''');
      db2.execute(
        "INSERT INTO foods (id, name, state, locale, kcal_per100g,"
        " protein_per100g, carbs_per100g, fat_per100g, source_id,"
        " license_status) VALUES ('f1', '宫保鸡丁（分片2）', 'verified', 'zh',"
        " 100, 1, 1, 1, 'openfoodfacts', 'allowed')",
      );
      db2.execute(
        "INSERT INTO food_search (food_id, text, brand, category)"
        " VALUES ('f1', '宫 保 鸡 丁', '', '')",
      );
      db2.dispose();

      final service = CatalogSearchService(shardPaths: [shardPath, secondPath]);
      final ids = service.search('宫保').items.map((r) => r.id).toList();
      expect(ids.where((id) => id == 'f1'), hasLength(1));
    });
  });

  group('docs/07 §5.7 搜索优先级分层', () {
    setUp(() {
      // 分层夹具：每条食物的 bm25 与「匹配层」故意不一致，用来证明排序 действительно
      // 按层而不是按 bm25 走。
      //   e1  牛奶            精确 canonical 名
      //   a1  奶粉 + 别名牛奶  精确别名（用户常用别名/翻译名）
      //   p1  牛奶巧克力        中文前缀
      //   q1  香肠  品牌=牛奶   仅品牌命中（bm25 比 p1 更好）
      //   q3  可可粉蛋糕 品牌=牛奶 仅品牌命中，文档更长
      //   n1  香草牛奶          名称包含但非前缀
      final rows = <(String, String, String?, String?)>[
        ('e1', '牛奶', null, null),
        ('a1', '奶粉', null, null),
        ('p1', '牛奶巧克力', null, null),
        ('q1', '香肠', '牛奶', null),
        ('q3', '可可粉蛋糕', '牛奶', null),
        ('n1', '香草牛奶', null, null),
        ('le', 'milk', null, null),
        ('la', 'soy drink', null, null),
        ('dm', 'milk chocolate', null, null),
        ('lp', 'milk chocolate', null, null),
        ('lq', 'boba', 'milk', null),
      ];
      for (final (id, name, brand, category) in rows) {
        food(id, name, brand: brand, category: category);
        shardDb.execute(
          'INSERT INTO food_search (food_id, text, brand, category)'
          " VALUES ('$id', '${cjkSpaced(name)}',"
          " '${brand == null ? '' : cjkSpaced(brand)}',"
          " '${category == null ? '' : cjkSpaced(category)}')",
        );
      }
      // 别名行（与 ETL 一致：别名 ≠ 主名才另立 FTS 行）。
      for (final (id, alias) in const [
        ('a1', '牛奶'),
        ('la', 'milk'),
        ('dm', 'milk'),
      ]) {
        shardDb.execute(
          "INSERT INTO aliases (food_id, normalized_text, language, alias_type,"
          " confidence) VALUES ('$id', '$alias', 'zh', 'common', 1.0)",
        );
        shardDb.execute(
          "INSERT INTO food_search (food_id, text, brand, category)"
          " VALUES ('$id', '${cjkSpaced(alias)}', '', '')",
        );
      }
    });

    test('精确名 > 精确别名 > 中文前缀 > 名称包含 > 品牌，即使 bm25 更偏后者', () {
      final service = CatalogSearchService(shardPaths: [shardPath]);
      final page = service.search('牛奶');

      expect(page.items.map((r) => r.id).toList(), [
        'e1',
        'a1',
        'p1',
        'n1',
        'q1',
        'q3',
      ], reason: 'bm25 会把品牌命中的 q1 排在中文前缀 p1 前面，分层必须纠正');
      expect(page.items.map((r) => r.tier).toList(), [
        CatalogMatchTier.exactName,
        CatalogMatchTier.exactAlias,
        CatalogMatchTier.namePrefix,
        CatalogMatchTier.nameToken,
        CatalogMatchTier.brandCategory,
        CatalogMatchTier.brandCategory,
      ]);
    });

    test('同层内再按 bm25：文档更短的品牌命中在前', () {
      final service = CatalogSearchService(shardPaths: [shardPath]);
      final ids = service.search('牛奶').items.map((r) => r.id).toList();
      expect(ids.indexOf('q1'), lessThan(ids.indexOf('q3')));
    });

    test('拉丁查询同样分层，且一条食物只出现一次并取最好的一层', () {
      final service = CatalogSearchService(shardPaths: [shardPath]);
      final page = service.search('milk');
      final items = page.items;

      expect(items.map((r) => r.id).toList(), ['le', 'dm', 'la', 'lp', 'lq']);
      expect(items.map((r) => r.tier).toList(), [
        CatalogMatchTier.exactName,
        CatalogMatchTier.exactAlias,
        CatalogMatchTier.exactAlias,
        CatalogMatchTier.namePrefix,
        CatalogMatchTier.brandCategory,
      ]);
      // dm 的 name 行（milk chocolate，中文前缀层）与别名行（milk，精确别名层）
      // 都命中，合并后只保留一条，且按更精确的层计算。
      expect(items.where((r) => r.id == 'dm'), hasLength(1));
    });

    test('别名前缀比仅品牌命中靠前', () {
      // docs/07 §5.7：拼音/英文别名 > 品牌和分类。
      final service = CatalogSearchService(shardPaths: [shardPath]);
      final ids = service.search('kung pao').items.map((r) => r.id).toList();
      expect(ids, contains('f1'));
      expect(
        service.search('kung pao').items.first.tier,
        CatalogMatchTier.aliasPrefix,
      );
      expect(
        service.search('Generic').items.first.tier,
        CatalogMatchTier.brandCategory,
      );
    });

    test('分层不破坏全量返回：无重复、层一致', () {
      for (var i = 0; i < 60; i++) {
        food('tier$i', '分层食物$i');
        shardDb.execute(
          "INSERT INTO food_search (food_id, text, brand, category)"
          " VALUES ('tier$i', '${cjkSpaced('分层食物$i')}', '', '')",
        );
      }
      final service = CatalogSearchService(shardPaths: [shardPath]);
      final page = service.search('分层');
      final ids = page.items.map((r) => r.id).toList();

      expect(page.items, hasLength(60));
      expect(ids.toSet(), hasLength(60));
      expect(
        page.items.every((r) => r.tier == CatalogMatchTier.namePrefix),
        isTrue,
      );
    });
  });

  test('a corrupt shard file is skipped, not fatal (docs/25 §5 L3)', () {
    // 文件还在但内容坏了（下载/拷贝截断、磁盘位翻转、被别的进程写坏）：
    // 分片是可再分发的目录缓存，不是用户数据，单片异常只跳过这一片。
    final corrupt =
        '${tempDir.path}${Platform.pathSeparator}foods-core-008.sqlite';
    File(corrupt).writeAsBytesSync(List<int>.filled(4096, 0x7f));

    final healthy = CatalogSearchService(shardPaths: [shardPath]).search('宫保');
    expect(healthy.items, isNotEmpty);

    final mixed = CatalogSearchService(shardPaths: [corrupt, shardPath])
        .search('宫保');
    expect(
      mixed.items.map((item) => item.id).toSet(),
      healthy.items.map((item) => item.id).toSet(),
      reason: '坏分片只跳过自己，好分片的命中一个字都不能少',
    );
    // 全部都是坏分片：返回空，而不是抛错。
    expect(
      CatalogSearchService(shardPaths: [corrupt]).search('宫保').items,
      isEmpty,
    );
  });

  test('a shard file that disappeared is skipped, not fatal', () {
    // 路径列表是启动时扫出来的；文件之后被删掉不该让整页搜索报错。
    final gone =
        '${tempDir.path}${Platform.pathSeparator}foods-core-009.sqlite';
    final service = CatalogSearchService(shardPaths: [gone, shardPath]);

    expect(service.search('宫保').items, isNotEmpty);
    expect(
      CatalogSearchService(shardPaths: [gone]).search('宫保').items,
      isEmpty,
    );
  });
}
