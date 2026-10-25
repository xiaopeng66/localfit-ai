import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_hygiene.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/domain/memory_dedupe.dart';

/// 记忆治理 M2（docs/43 B5 / B6 / B7 / B11）。
void main() {
  late AppDatabase db;
  late AiMemoryRepository repo;
  final now = DateTime.utc(2026, 10, 19, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = AiMemoryRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: _SeqIds(),
    );
  });

  tearDown(() async => db.close());

  group('B5 容量', () {
    test('常量拆分：软顶 2000 / 硬顶 5000 / 注入候选 200', () {
      expect(kAiMemorySoftCap, 2000);
      expect(kAiMemoryHardCap, 5000);
      expect(kAiMemoryInjectionCandidates, 200);
    });

    test('超软顶仍可写，但 isOverSoftCap 为真', () async {
      for (var i = 0; i <= kAiMemorySoftCap; i++) {
        await _insertRaw(db, 'bulk-$i', '批量记忆$i', now);
      }
      expect(await repo.activeCount(), kAiMemorySoftCap + 1);
      expect(await repo.isOverSoftCap(), isTrue);
      // 仍可写（软顶不是硬顶）。
      await repo.remember(text: '再来一条', policy: DuplicatePolicy.allow);
      expect(await repo.activeCount(), kAiMemorySoftCap + 2);
    });

    test('达硬顶拒绝，文案指向整理', () async {
      for (var i = 0; i < kAiMemoryHardCap; i++) {
        await _insertRaw(db, 'hard-$i', '硬顶记忆$i', now);
      }
      await expectLater(
        () => repo.remember(text: '再来一条'),
        throwsA(
          isA<AiMemoryException>().having(
            (error) => error.message,
            'message',
            contains('硬顶'),
          ),
        ),
      );
    });

    test('注入候选固定 200：listActive 默认不再随总条数增长', () async {
      for (var i = 0; i < kAiMemoryInjectionCandidates + 50; i++) {
        await _insertRaw(db, 'cap-$i', '候选记忆$i', now);
      }
      expect(
        (await repo.listActive(limit: kAiMemoryInjectionCandidates)).length,
        kAiMemoryInjectionCandidates,
      );
    });

    test('导入上限 = 硬顶（整单拒绝）', () async {
      final doc = {
        'version': 1,
        'memories': [
          for (var i = 0; i < kAiMemoryHardCap + 1; i++) {'text': '导入$i'},
        ],
      };
      await expectLater(
        () => repo.importDocument(doc),
        throwsA(isA<FormatException>()),
      );
    });

    test('2000 条分页搜索 <100ms', () async {
      for (var i = 0; i < kAiMemorySoftCap; i++) {
        await _insertRaw(db, 'perf-$i', '性能记忆$i', now);
      }
      final watch = Stopwatch()..start();
      final page = await repo.searchPage(query: '性能', limit: 50);
      watch.stop();
      expect(page.total, kAiMemorySoftCap);
      expect(watch.elapsedMilliseconds, lessThan(100));
    });
  });

  group('B6 向量判重', () {
    test('完全相同文本 → 拒，且不调用嵌入', () async {
      final engine = _CountingIndex(_UnitVectors());
      final repository = _repoWith(db, now, vectorIndex: engine);
      await repository.remember(text: '我不吃香菜');
      final before = engine.calls;
      await expectLater(
        () => repository.remember(text: '我不吃香菜'),
        throwsA(isA<AiMemoryException>()),
      );
      expect(engine.calls, before, reason: '快速路径不得花一次嵌入');
    });

    test('cosine 0.97 → 拒绝', () async {
      final engine = _ScriptedIndex(target: 0.97);
      final repository = _repoWith(db, now, vectorIndex: engine);
      final first = await repository.remember(text: '喜欢清淡口味');
      expect(first.id, isNotEmpty);
      await expectLater(
        () => repository.remember(text: '偏爱清淡的菜'),
        throwsA(
          isA<AiMemoryException>().having(
            (error) => error.message,
            'message',
            contains('非常接近'),
          ),
        ),
      );
    });

    test('cosine 0.90 → AiMemoryMergeSuggested，候选含旧条 id', () async {
      final engine = _ScriptedIndex(target: 0.90);
      final repository = _repoWith(db, now, vectorIndex: engine);
      final first = await repository.remember(text: '喜欢清淡口味');
      await expectLater(
        () => repository.remember(text: '口味偏清淡'),
        throwsA(
          isA<AiMemoryMergeSuggested>().having(
            (error) => error.candidates.map((c) => c.id),
            'candidates',
            contains(first.id),
          ),
        ),
      );
    });

    test('cosine 0.5 → 写入成功，索引新增一行', () async {
      final engine = _ScriptedIndex(target: 0.5);
      final repository = _repoWith(db, now, vectorIndex: engine);
      await repository.remember(text: '喜欢清淡口味');
      await repository.remember(text: '周三晚上练腿');
      expect(await repository.listActive(), hasLength(2));
      expect(engine.entries.length, 2);
    });

    test('allow 策略可强制写入（0.90 也写）', () async {
      final engine = _ScriptedIndex(target: 0.90);
      final repository = _repoWith(db, now, vectorIndex: engine);
      await repository.remember(text: '喜欢清淡口味');
      final forced = await repository.remember(
        text: '口味偏清淡',
        policy: DuplicatePolicy.allow,
      );
      expect(forced.id, isNotEmpty);
    });

    test('删除记忆 → 索引行同步删除', () async {
      final engine = _ScriptedIndex(target: 0.5);
      final repository = _repoWith(db, now, vectorIndex: engine);
      final memory = await repository.remember(text: '喜欢清淡口味');
      expect(engine.entries, contains(memory.id));
      await repository.delete(memory.id);
      expect(engine.entries, isNot(contains(memory.id)));
    });

    test('重建覆盖 memory（恢复备份后）', () async {
      final engine = _ScriptedIndex(target: 0.5);
      final repository = _repoWith(db, now, vectorIndex: engine);
      await repository.remember(text: '喜欢清淡口味');
      engine.entries.clear();
      final rebuilt = await engine.rebuild(await repository.listActive());
      expect(rebuilt, 1);
      expect(engine.entries, hasLength(1));
    });
  });

  group('B7 整理建议', () {
    test('按 domain 分桶找 cosine ≥0.9 的近义簇', () async {
      final engine = _ScriptedIndex(target: 0.95, clusterKey: '清淡');
      final repository = _repoWith(db, now, vectorIndex: engine);
      await repository.remember(
        text: '喜欢清淡口味',
        domain: AiMemoryDomain.nutrition,
      );
      await repository.remember(
        text: '口味偏清淡',
        domain: AiMemoryDomain.nutrition,
        policy: DuplicatePolicy.allow,
      );
      await repository.remember(
        text: '周三晚上练腿',
        domain: AiMemoryDomain.training,
      );
      final report = await MemoryHygiene(
        repository: repository,
        clock: FixedAppClock(now),
        vectorIndex: engine,
      ).scan();
      expect(report.clusters, hasLength(1));
      expect(report.clusters.single.memories, hasLength(2));
      expect(report.clusters.single.domain, AiMemoryDomain.nutrition);
      expect(report.clusters.single.maxSimilarity, greaterThanOrEqualTo(0.9));
    });

    test('180 天未用且 importance<40 → 长期未用', () async {
      final fresh = await repo.remember(text: '最近的偏好', importance: 30);
      final stale = await repo.remember(text: '很久以前的偏好', importance: 30);
      final important = await repo.remember(text: '重要的偏好', importance: 90);
      await repo.markUsed([fresh.id, important.id]);
      // 把 stale 的 lastUsedAt 推到 200 天前（直接改行）。
      await (db.update(
        db.aiMemories,
      )..where((r) => r.id.equals(stale.id))).write(
        AiMemoriesCompanion(
          lastUsedAt: Value(now.subtract(const Duration(days: 200))),
        ),
      );
      // important 的 lastUsedAt 也是「刚用」但 importance 高 ⇒ 不入选。
      await (db.update(
        db.aiMemories,
      )..where((r) => r.id.equals(important.id))).write(
        AiMemoriesCompanion(
          lastUsedAt: Value(now.subtract(const Duration(days: 200))),
        ),
      );
      final report = await MemoryHygiene(
        repository: repo,
        clock: FixedAppClock(now),
      ).scan();
      expect(report.stale.map((m) => m.id), [stale.id]);
    });

    test('只建议不改数据：scan 后 active 条数不变', () async {
      final engine = _ScriptedIndex(target: 0.95, clusterKey: '清淡');
      final repository = _repoWith(db, now, vectorIndex: engine);
      await repository.remember(text: '喜欢清淡口味');
      await repository.remember(text: '口味偏清淡', policy: DuplicatePolicy.allow);
      final before = await repository.listActive();
      await MemoryHygiene(
        repository: repository,
        clock: FixedAppClock(now),
        vectorIndex: engine,
      ).scan();
      expect((await repository.listActive()).length, before.length);
    });

    test('归档后不在 listActive，但 listAsOf 仍可回看', () async {
      final memory = await repo.remember(text: '很久以前的偏好');
      await repo.archive(memory.id);
      expect(await repo.listActive(), isEmpty);
      expect(
        (await repo.listAsOf(now.add(const Duration(minutes: 1))))
            .map((m) => m.id),
        contains(memory.id),
      );
    });
  });

  group('B11 分页', () {
    test('第 1 页 50 条、加载更多不重复、总数正确', () async {
      for (var i = 0; i < 120; i++) {
        await _insertRaw(db, 'page-$i', '分页记忆$i', now);
      }
      final first = await repo.searchPage(limit: 50);
      expect(first.items, hasLength(50));
      expect(first.total, 120);
      final second = await repo.searchPage(
        offset: first.items.length,
        limit: 50,
      );
      expect(second.items, hasLength(50));
      final ids = {...first.items.map((m) => m.id)};
      expect(
        second.items.where((m) => ids.contains(m.id)),
        isEmpty,
        reason: '加载更多不得重复',
      );
    });

    test('搜索跨页一致', () async {
      for (var i = 0; i < 80; i++) {
        await _insertRaw(db, 'q-$i', '清淡记忆$i', now);
      }
      for (var i = 0; i < 30; i++) {
        await _insertRaw(db, 'o-$i', '训练记忆$i', now);
      }
      final page1 = await repo.searchPage(query: '清淡', limit: 50);
      final page2 = await repo.searchPage(query: '清淡', offset: 50, limit: 50);
      expect(page1.total, 80);
      expect(page1.items.length + page2.items.length, 80);
    });
  });
}

AiMemoryRepository _repoWith(
  AppDatabase db,
  DateTime now, {
  MemoryVectorIndex? vectorIndex,
}) => AiMemoryRepository(
  database: db,
  clock: FixedAppClock(now),
  idGenerator: _SeqIds(),
  vectorIndex: vectorIndex,
);

Future<void> _insertRaw(AppDatabase db, String id, String text, DateTime now) =>
    db
        .into(db.aiMemories)
        .insert(
          AiMemoriesCompanion.insert(
            id: id,
            textContent: text,
            kind: 'fact',
            domain: 'general',
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );

/// 可控向量索引：按「新文本是否含 clusterKey」与目标余弦构造向量。
///
/// 第一条（基线）固定 `[1,0,0,0]`；后写入的按 [target] 旋转，
/// 使 cosine(基线, 新条) = target。
class _ScriptedIndex implements MemoryVectorIndex {
  _ScriptedIndex({required this.target, this.clusterKey});

  final double target;
  final String? clusterKey;
  final Map<String, List<double>> entries = {};
  final Map<String, String> _texts = {};

  @override
  Future<Map<String, double>?> similarities(String text) async => {
    for (final entry in entries.entries)
      entry.key: _cosine(_queryVectorFor(text), entry.value),
  };

  /// 查询文本的向量：与基线成 [target] 余弦（B7 里非簇内文本正交）。
  List<double> _queryVectorFor(String text) {
    if (clusterKey != null && !text.contains(clusterKey!)) {
      return const [0, 0, 1, 0];
    }
    final s = math.sqrt(1 - target * target);
    return [target, s, 0, 0];
  }

  List<double> _vectorFor(String text) {
    if (entries.isEmpty) return const [1, 0, 0, 0];
    return _queryVectorFor(text);
  }

  @override
  Future<void> upsertMemory(AiMemory memory) async {
    entries[memory.id] = _vectorFor(memory.text);
    _texts[memory.id] = memory.text;
  }

  @override
  Future<void> deleteMemory(String id) async {
    entries.remove(id);
    _texts.remove(id);
  }

  @override
  Future<int> rebuild(List<AiMemory> memories) async {
    var written = 0;
    for (final memory in memories) {
      entries[memory.id] = _vectorFor(memory.text);
      written++;
    }
    return written;
  }

  @override
  Future<Map<String, List<double>>?> vectors() async => {...entries};

  static double _cosine(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    var dot = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }
}

/// 只计数 embed 调用的索引（「完全相同不花嵌入」判据）。
class _CountingIndex implements MemoryVectorIndex {
  _CountingIndex(this._inner);

  final MemoryVectorIndex _inner;
  int calls = 0;

  @override
  Future<Map<String, double>?> similarities(String text) async {
    calls++;
    return _inner.similarities(text);
  }

  @override
  Future<void> upsertMemory(AiMemory memory) async {
    calls++;
    await _inner.upsertMemory(memory);
  }

  @override
  Future<void> deleteMemory(String id) => _inner.deleteMemory(id);

  @override
  Future<int> rebuild(List<AiMemory> memories) => _inner.rebuild(memories);

  @override
  Future<Map<String, List<double>>?> vectors() => _inner.vectors();
}

class _UnitVectors implements MemoryVectorIndex {
  final Map<String, List<double>> _entries = {};

  @override
  Future<Map<String, double>?> similarities(String text) async => {
    for (final entry in _entries.entries) entry.key: 0.1,
  };

  @override
  Future<void> upsertMemory(AiMemory memory) async {
    _entries[memory.id] = const [1, 0, 0, 0];
  }

  @override
  Future<void> deleteMemory(String id) async => _entries.remove(id);

  @override
  Future<int> rebuild(List<AiMemory> memories) async => 0;

  @override
  Future<Map<String, List<double>>?> vectors() async => {..._entries};
}

class _SeqIds implements IdGenerator {
  int _n = 0;
  @override
  String next() => 'mem-${_n++}';
}
