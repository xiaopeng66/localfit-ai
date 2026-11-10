import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// S11（docs/38 §6.1）：schema 26 → 27 —— **纯加法**（AI 长期记忆表）。
///
/// 加法迁移的失败模式：按版本区间猜「表在不在」、把旧库里的行误伤、
/// 或重开已升过的库时重复建表。这里钉三件事：
/// 1. v26 老库升到当前 schema，旧数据保全，生产仓库可读写当前记忆；
/// 2. 全新安装（onCreate）的同一写入路径也可用；
/// 3. 幂等：重开升级后的库不会重建表或丢掉已保存记忆。
void main() {
  late Directory tempDir;
  final now = DateTime.utc(2026, 11, 10, 12);

  AiMemoryRepository repositoryFor(AppDatabase database) => AiMemoryRepository(
    database: database,
    clock: FixedAppClock(now),
    idGenerator: const UuidV7Generator(),
    // 不接向量索引：这里只验证本地持久层，不触发嵌入或其它外呼。
  );

  Future<AiMemoryRow> expectRememberWorks(AppDatabase database) async {
    final repository = repositoryFor(database);
    final memory = await repository.remember(
      text: '周三晚饭后散步',
      kind: AiMemoryKind.habit,
      domain: AiMemoryDomain.training,
      tags: ['散步'],
      source: 'manual',
    );
    final row = (await database.select(database.aiMemories).get()).single;
    expect(row.id, memory.id);
    expect(row.textContent, '周三晚饭后散步');
    expect(row.kind, 'habit');
    expect(row.domain, 'training');
    expect(decodeAiMemoryTags(row.tagsJson), ['散步']);
    expect(row.source, 'manual');
    expect(row.status, 'active');
    expect(row.pinned, isFalse);
    expect(row.importance, 50);
    expect(row.useCount, 0);
    expect(row.lastUsedAt, isNull);
    expect(row.supersededById, isNull);
    expect(row.expiresAt, isNull);
    // SQLite 存时间戳，Drift 读回可为本地时区；比较同一 UTC 时刻而非时区标志。
    expect(row.createdAt.toUtc(), now);
    expect(row.updatedAt.toUtc(), now);
    expect(row.validFrom?.toUtc(), now);
    expect(row.validTo, isNull);

    final active = (await repository.listActive()).single;
    expect(active.id, memory.id);
    expect(active.text, '周三晚饭后散步');
    expect(active.kind, AiMemoryKind.habit);
    expect(active.domain, AiMemoryDomain.training);
    expect(active.validFrom?.toUtc(), now);
    return row;
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('localfit-v27-');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('v26 老库升级：记忆生产读写可用，旧数据一字不动', () async {
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
    await expectRememberWorks(database);
    expect(
      (await database.select(database.appSettings).get()).single.value,
      'kept',
    );
  });

  test('全新安装：记忆生产仓库读写与时间语义可用', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    expect(await database.select(database.aiMemories).get(), isEmpty);
    await expectRememberWorks(database);
  });

  test('幂等：重开已升级库保全全部记忆字段和旧设置', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}localfit-again.sqlite',
    );
    _createV26Database(file.path);

    final first = AppDatabase(NativeDatabase(file));
    late final AiMemoryRow saved;
    try {
      saved = await expectRememberWorks(first);
    } finally {
      await first.close();
    }

    final second = AppDatabase(NativeDatabase(file));
    addTearDown(second.close);
    expect(await second.select(second.aiMemories).get(), [saved]);
    final active = (await repositoryFor(second).listActive()).single;
    expect(active.id, saved.id);
    expect(active.text, '周三晚饭后散步');
    expect(active.validFrom?.toUtc(), now);
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
