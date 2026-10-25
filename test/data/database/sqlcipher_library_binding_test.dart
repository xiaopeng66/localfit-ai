import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 2026-09-16 真机回归：`package:sqlite3` 在 Android 上默认解析
/// `libsqlite3.so`（系统里没有），`sqlite3.open` 于是抛 `ArgumentError`——
/// 不是 `SqliteException`。主库自己走后台 isolate 的 `isolateSetup`，但
/// **主 isolate 里也有裸 sqlite3 调用**（目录分片搜索 `CatalogSearchService`、
/// 分片导入 `CatalogShardImporter`）。只给后台 isolate 装覆盖时，真机上
/// 「食物目录」显示导入遇到意外错误、搜索也打不开分片。
///
/// 单元测试跑在桌面明文 sqlite3 上，永远不会自己暴露这类「库加载」问题，
/// 所以这里钉两件事：启动时确实装了覆盖，且装了之后在桌面仍然可用。
void main() {
  test('main() 在打开数据库之前装好 SQLCipher 库解析覆盖', () {
    final source = File('lib/main.dart').readAsStringSync();
    final configureAt = source.indexOf('configureSqlCipherLibrary();');
    final openAt = source.indexOf('AppDatabase.open');

    expect(
      configureAt,
      greaterThanOrEqualTo(0),
      reason: '主 isolate 的启动路径必须调用 configureSqlCipherLibrary()',
    );
    expect(
      openAt,
      greaterThan(configureAt),
      reason: '必须在任何数据库/分片打开之前调用（库覆盖只对之后创建的对象生效）',
    );
  });

  test('库覆盖函数在桌面测试环境可安全调用且 sqlite3 照常可用', () {
    // 覆盖只登记 Android 的加载函数；当前 OS 不是 Android 时走默认加载，
    // 所以这里既验证「启动调用不会破坏桌面/测试运行」，也验证它幂等。
    configureSqlCipherLibrary();
    configureSqlCipherLibrary();

    final db = sqlite.sqlite3.openInMemory();
    try {
      db.execute('CREATE TABLE probe (x INTEGER)');
      db.execute('INSERT INTO probe (x) VALUES (1)');
      expect(db.select('SELECT COUNT(*) AS n FROM probe').first['n'], 1);
    } finally {
      db.dispose();
    }
  });
}
