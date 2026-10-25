import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// S11（docs/38 §6.1）：schema 26 → 27 —— **纯加法**（AI 长期记忆表）。
///
/// 加法迁移的失败模式：按版本区间猜「表在不在」、把旧库里的行误伤、
/// 或重开已升过的库时重复建表。这里钉三件事：
/// 1. v26 老库升级后 `ai_memories` 在、旧数据一字不动、新表可读；
/// 2. 全新安装（onCreate）直接带这张表；
/// 3. 幂等：已升到 27 的库再打开不抛。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v27-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('v26 老库升级：ai_memories 建出来，旧数据一字不动', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit.sqlite',
    );
    _createV26Database(file.path);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    final version = await database
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data['user_version'], database.schemaVersion);
    // 2026-10-19（S14 / docs/41 §11）：当时当前 schema 是 29；本用例的意图是
    // 「升到当前版」，不是钉住某个历史版本号。
    // 2026-10-21（ADR-036）：现在是 30（foods DROP 17 列）——本条跟着当前值走，
    // 断言的仍是「v26 老库能一路升到现在」。
    expect(database.schemaVersion, 30);

    final tables =
        (await database
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table'",
                )
                .get())
            .map((row) => row.data['name'])
            .toList();
    expect(tables, contains('ai_memories'));

    // 旧数据原样保留。
    expect(
      (await database.select(database.appSettings).get()).single.value,
      'kept',
    );
    // 新表可用且为空。
    expect(await database.select(database.aiMemories).get(), isEmpty);
    // schema 28 的派生表也一并建出（docs/41 §11）。
    expect(tables, containsAll(['embedding_index', 'background_jobs']));
    expect(await database.select(database.embeddingIndex).get(), isEmpty);
    expect(await database.select(database.backgroundJobs).get(), isEmpty);
  });

  test('全新安装：建表即带 ai_memories', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    expect(await database.select(database.aiMemories).get(), isEmpty);
  });

  test('幂等：已升到当前版的库再打开不抛', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit-again.sqlite',
    );
    _createV26Database(file.path);

    final first = AppDatabase(NativeDatabase(file));
    await first.customSelect('SELECT 1').get();
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    expect(await second.select(second.aiMemories).get(), isEmpty);
    expect(
      (await second.select(second.appSettings).get()).single.value,
      'kept',
    );
  });
}

/// 最小 v26 库：只建一张与迁移无关的表来证明「旧数据不被动」，
/// 并把 user_version 钉在 26。`from < 27` 分支只查 sqlite_master，
/// 不依赖其它表存在。
void _createV26Database(String path) {
  final db = sqlite.sqlite3.open(path);
  db.execute(
    'CREATE TABLE app_settings ('
    'key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)',
  );
  db.execute("INSERT INTO app_settings (key, value) VALUES ('probe', 'kept')");
  db.execute('PRAGMA user_version = 26');
  db.dispose();
}
