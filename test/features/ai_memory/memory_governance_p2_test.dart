import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';

/// P2 记忆治理（docs/41 §5 / §11）：历史/撤销、重要性、分页、导入导出、
/// 实体链接、过期提议。
void main() {
  late AppDatabase db;
  late AiMemoryRepository repo;
  final now = DateTime.utc(2026, 10, 18, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = AiMemoryRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: const _SeqIds(),
    );
  });
  tearDown(() => db.close());

  test('改口留痕：旧条 superseded 后不再出现在 listActive，但历史可查、可撤销', () async {
    final oldMemory = await repo.remember(text: '我不吃香菜');
    final newMemory = await repo.remember(text: '我现在可以吃香菜了');
    await repo.supersede(oldId: oldMemory.id, newId: newMemory.id);

    final active = await repo.listActive();
    expect(active.map((m) => m.id), [newMemory.id], reason: '旧条不再参与注入');

    final history = await repo.supersededBy(newMemory.id);
    expect(history.single.id, oldMemory.id);
    expect(history.single.isSuperseded, isTrue);

    await repo.undoSupersede(oldMemory.id);
    expect(
      (await repo.listActive()).map((m) => m.id),
      containsAll([oldMemory.id, newMemory.id]),
    );
  });

  test('重要性可写且夹在 0–100', () async {
    final memory = await repo.remember(text: '周三晚上练腿');
    await repo.setImportance(memory.id, 120);
    expect((await repo.listActive()).single.importance, 100);
    await repo.setImportance(memory.id, -5);
    expect((await repo.listActive()).single.importance, 0);
  });

  test('markUsed 节流：10 分钟内重复调用只记一次', () async {
    final memory = await repo.remember(text: '喜欢清淡');
    await repo.markUsed([memory.id]);
    await repo.markUsed([memory.id]);
    final after = (await repo.listActive()).single;
    expect(after.useCount, 1);
    expect(after.lastUsedAt, isNotNull);
  });

  test('分页搜索：offset/limit 与总数', () async {
    for (var i = 0; i < 7; i++) {
      await repo.remember(text: '记忆条目$i', tags: ['tag$i']);
    }
    final page1 = await repo.searchPage(query: '记忆', offset: 0, limit: 3);
    expect(page1.total, 7);
    expect(page1.items, hasLength(3));
    final page3 = await repo.searchPage(query: '记忆', offset: 6, limit: 3);
    expect(page3.items, hasLength(1));
  });

  test('实体链接（G19）落库并回读', () async {
    final memory = await repo.remember(text: '不吃香菜');
    await repo.linkEntity(
      id: memory.id,
      entityType: 'food',
      entityId: 'food-cilantro',
    );
    final stored = (await repo.listActive()).single;
    expect(stored.linkedEntityType, 'food');
    expect(stored.linkedEntityId, 'food-cilantro');
    expect(stored.linkedEntityLabel, '食物');
  });

  test('过期只提议：expiredMemories 列出到期条目但不删', () async {
    final expired = await repo.remember(
      text: '我在出差',
      kind: AiMemoryKind.context,
      expiresAt: now.subtract(const Duration(days: 1)),
    );
    await repo.remember(text: '长期偏好');
    final expiredList = await repo.expiredMemories();
    expect(expiredList.single.id, expired.id);
    expect(await repo.listActive(), hasLength(2), reason: '不自动删');
  });

  test('导出 → 导入往返（带版本）', () async {
    await repo.remember(text: '不吃香菜', tags: ['饮食']);
    await repo.remember(text: '周三晚上练腿', kind: AiMemoryKind.habit);

    final document = await repo.exportDocument();
    expect(document['version'], 1);
    expect(document['memories'], hasLength(2));

    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(restored.close);
    final restoredRepo = AiMemoryRepository(
      database: restored,
      clock: FixedAppClock(now),
      idGenerator: const _SeqIds(),
    );
    final written = await restoredRepo.importDocument(document);
    expect(written, 2);
    expect((await restoredRepo.listActive()), hasLength(2));
  });

  test('导入坏数据整单拒绝（版本/形状/超长/敏感）', () async {
    await expectLater(
      repo.importDocument({'version': 99, 'memories': []}),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      repo.importDocument({'version': 1}),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      repo.importDocument({
        'version': 1,
        'memories': [
          {'text': '正常的一条'},
          {'text': '身份证号 110101199001011234'},
        ],
      }),
      throwsA(isA<FormatException>()),
    );
    // RV-P1-17（2026-10-20）：整单原子——第一条也不能留下。
    expect((await repo.listActive()), isEmpty);
  });

  test('容量上限：硬顶前拒绝新写入', () async {
    // 用较少的条数模拟上限路径（直接注满）。
    for (var i = 0; i < kAiMemoryHardCap; i++) {
      await db
          .into(db.aiMemories)
          .insert(
            AiMemoriesCompanion.insert(
              id: 'bulk-$i',
              textContent: '批量记忆$i',
              kind: 'fact',
              domain: 'general',
              source: 'manual',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    await expectLater(
      repo.remember(text: '再来一条'),
      throwsA(isA<AiMemoryException>()),
    );
  });
}

class _SeqIds implements IdGenerator {
  const _SeqIds();
  @override
  String next() => 'id-${_counter++}';
}

int _counter = 0;
