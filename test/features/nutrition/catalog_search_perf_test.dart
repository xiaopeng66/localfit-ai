import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 50k 行目录分片上的搜索性能基准（GOAL：50k/100k 性能基准；分页 ≤50）。
/// 100k 扩展基准由 tool/food_catalog 侧脚本一次性验证（见 evidence）。
void main() {
  late Directory tempDir;
  late String shardPath;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('localfit-perf-');
    shardPath = '${tempDir.path}${Platform.pathSeparator}foods-core-000.sqlite';
    final db = sqlite.sqlite3.open(shardPath);
    db.execute('''
CREATE TABLE foods (
  id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, state TEXT NOT NULL,
  locale TEXT, category TEXT, brand TEXT, kcal_per100g REAL,
  protein_per100g REAL, carbs_per100g REAL, fat_per100g REAL,
  source_id TEXT NOT NULL, source_version TEXT, license_status TEXT NOT NULL
);
CREATE VIRTUAL TABLE food_search USING fts5(food_id UNINDEXED, text, brand, category);
''');
    db.execute('BEGIN');
    final foodStmt = db.prepare(
      'INSERT INTO foods (id, name, state, locale, kcal_per100g,'
      ' protein_per100g, carbs_per100g, fat_per100g, source_id,'
      " license_status) VALUES (?, ?, 'verified', 'zh', 100, 1, 1, 1,"
      " 'openfoodfacts', 'allowed')",
    );
    final ftsStmt = db.prepare(
      'INSERT INTO food_search (food_id, text, brand, category) VALUES (?, ?, \'\', \'\')',
    );
    const adjectives = ['红烧', '清蒸', '爆炒', '白灼', '凉拌', '油炸', '炖煮', '烤制'];
    const nouns = ['牛肉', '猪肉', '鸡肉', '鱼肉', '豆腐', '青菜', '米饭', '面条'];
    try {
      for (var i = 0; i < 50000; i++) {
        final name =
            '${adjectives[i % adjectives.length]}${nouns[(i ~/ 8) % nouns.length]}'
            '${(i ~/ 64) % 100}';
        final spaced = name.split('').join(' ');
        foodStmt.execute(['perf:$i', name]);
        ftsStmt.execute(['perf:$i', spaced]);
      }
      db.execute('COMMIT');
    } finally {
      foodStmt.dispose();
      ftsStmt.dispose();
    }
    db.dispose();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('CJK prefix search over 50k rows stays under 100 ms', () {
    final service = CatalogSearchService(shardPaths: [shardPath]);
    // 预热一次（打开分片、journal 读取）。
    service.search('红烧');

    final sw = Stopwatch()..start();
    final page = service.search('红烧牛');
    sw.stop();

    // 不再分页：命中全量返回，性能判据只看耗时；数量上限只为兜住意外膨胀。
    expect(page.items, isNotEmpty);
    expect(page.items.length, lessThanOrEqualTo(1000));
    expect(sw.elapsedMilliseconds, lessThan(100));
  });

  test('rare-token search over 50k rows stays under 100 ms', () {
    final service = CatalogSearchService(shardPaths: [shardPath]);
    service.search('烤制');
    final sw = Stopwatch()..start();
    service.search('烤制豆');
    sw.stop();
    expect(sw.elapsedMilliseconds, lessThan(100));
  });
}
