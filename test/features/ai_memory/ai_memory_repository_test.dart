import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';

import '../ai_conversation/application/chat_edit_executor_test.dart'
    show IdsForTest;

/// S11（docs/38 §4）：长期记忆的落库纪律——有界、去重、敏感红线、如实遗忘。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 10, 17, 12);
  late AppDatabase database;
  late AiMemoryRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = AiMemoryRepository(
      database: database,
      clock: FixedAppClock(now),
      idGenerator: IdsForTest(),
    );
  });

  tearDown(() => database.close());

  test('remember：真的落库，默认值与标签按排序存', () async {
    final memory = await repository.remember(
      text: '周三晚上练腿',
      kind: AiMemoryKind.habit,
      domain: AiMemoryDomain.training,
      tags: ['腿', '周三'],
    );

    expect(memory.text, '周三晚上练腿');
    final row = (await database.select(database.aiMemories).get()).single;
    expect(row.textContent, '周三晚上练腿');
    expect(row.kind, 'habit');
    expect(row.domain, 'training');
    expect(decodeAiMemoryTags(row.tagsJson), ['周三', '腿']);
    expect(row.source, 'explicit');
    expect(row.status, 'active');
    expect(row.pinned, isFalse);
  });

  test('remember：空/超长/敏感信息都拒绝，且消息是人话', () async {
    await expectLater(
      () => repository.remember(text: '   '),
      throwsA(
        isA<AiMemoryException>().having(
          (error) => error.message,
          'message',
          contains('不能为空'),
        ),
      ),
    );
    await expectLater(
      () => repository.remember(text: '长' * (kAiMemoryMaxTextLength + 1)),
      throwsA(
        isA<AiMemoryException>().having(
          (error) => error.message,
          'message',
          contains('太长'),
        ),
      ),
    );
    await expectLater(
      () => repository.remember(text: '我的身份证 110101199001011234'),
      throwsA(
        isA<AiMemoryException>().having(
          (error) => error.message,
          'message',
          contains('敏感'),
        ),
      ),
    );
    expect(await database.select(database.aiMemories).get(), isEmpty);
  });

  test('去重：完全相同与包含关系都拒绝（不静默并存）', () async {
    await repository.remember(text: '不吃香菜');
    await expectLater(
      () => repository.remember(text: ' 不吃香菜 '),
      throwsA(
        isA<AiMemoryException>().having(
          (error) => error.message,
          'message',
          contains('已经有这条记忆'),
        ),
      ),
    );
    await expectLater(
      () => repository.remember(text: '不吃香菜和葱'),
      throwsA(
        isA<AiMemoryException>().having(
          (error) => error.message,
          'message',
          contains('相近'),
        ),
      ),
    );
    expect(await database.select(database.aiMemories).get(), hasLength(1));
  });

  test('条数上限：硬顶之后拒绝新增', () async {
    for (var index = 0; index < kAiMemoryHardCap; index++) {
      await _insertRaw(database, 'id-$index', '记忆 $index', now);
    }
    await expectLater(
      () => repository.remember(text: '再来一条'),
      throwsA(
        isA<AiMemoryException>().having(
          (error) => error.message,
          'message',
          contains('硬顶'),
        ),
      ),
    );
  });

  test('findMatches：正文、标签、反向包含（≥2 字）都命中', () async {
    await repository.remember(text: '周三晚上练腿', tags: ['周三', '腿']);
    await repository.remember(text: '早上没时间做饭', domain: AiMemoryDomain.schedule);

    expect(await repository.findMatches('练腿'), hasLength(1));
    expect(await repository.findMatches('腿'), hasLength(1));
    expect(
      await repository.findMatches('周三晚上练腿和跑步'),
      hasLength(1),
      reason: '用户说得比记忆长时也应命中',
    );
    expect(await repository.findMatches('做饭'), hasLength(1));
    expect(await repository.findMatches('完全无关'), isEmpty);
    expect(await repository.findMatches('   '), isEmpty);
  });

  test('delete/deleteAll：真的删掉', () async {
    final first = await repository.remember(text: '喜欢鸡胸肉');
    await repository.remember(text: '常去二食堂');
    expect(await repository.delete(first.id), isTrue);
    expect(await database.select(database.aiMemories).get(), hasLength(1));
    expect(await repository.delete('missing'), isFalse);
    expect(await repository.deleteAll(), 1);
    expect(await database.select(database.aiMemories).get(), isEmpty);
  });

  test('置顶优先排序（watchActive 与 listActive 同一口径）', () async {
    await _insertRaw(
      database,
      'old-pinned',
      '置顶的旧记忆',
      now.subtract(const Duration(days: 10)),
      pinned: true,
    );
    await _insertRaw(database, 'new-normal', '最新的普通记忆', now);

    final list = await repository.listActive();
    expect(list.first.id, 'old-pinned');
    expect((await repository.watchActive().first).first.id, 'old-pinned');
  });

  test('update：只改给了的字段，其余原样保留', () async {
    final memory = await repository.remember(
      text: '周三晚上练腿',
      kind: AiMemoryKind.habit,
      domain: AiMemoryDomain.training,
      tags: ['腿'],
    );
    final updated = await repository.update(
      memory.id,
      text: '周四晚上练腿',
      pinned: true,
    );
    expect(updated!.text, '周四晚上练腿');
    expect(updated.kind, AiMemoryKind.habit);
    expect(updated.domain, AiMemoryDomain.training);
    expect(updated.tags, ['腿']);
    expect(updated.pinned, isTrue);
    // drift 读回的 DateTime 是本地表示；比较「同一时刻」而不是表示形式。
    expect(updated.createdAt.toUtc(), memory.createdAt.toUtc());
  });

  test('update 去重守卫：改成与另一条相同/相近 ⇒ 拒绝；改回自己 ⇒ 放行', () async {
    final first = await repository.remember(text: '不吃香菜');
    final second = await repository.remember(text: '常去二食堂');

    await expectLater(
      () => repository.update(second.id, text: '不吃香菜'),
      throwsA(
        isA<AiMemoryException>().having(
          (error) => error.message,
          'message',
          contains('不吃香菜'),
        ),
      ),
    );
    await expectLater(
      () => repository.update(second.id, text: '不吃香菜和葱'),
      throwsA(
        isA<AiMemoryException>().having(
          (error) => error.message,
          'message',
          contains('相近'),
        ),
      ),
    );
    // 改回自己的原文不算重复（守卫只拦「变成别人」）。
    final unchanged = await repository.update(second.id, text: '常去二食堂 ');
    expect(unchanged!.text, '常去二食堂');
    expect(first.text, '不吃香菜');
  });

  test('source=extracted 的记忆显示「从对话提炼」', () async {
    final memory = await repository.remember(text: '喜欢晨跑', source: 'extracted');
    expect(memory.sourceLabel, '从对话提炼');
  });

  test('开关：缺键默认开启，关掉后读回 false', () async {
    expect(await repository.injectionEnabled(), isTrue);
    await repository.setInjectionEnabled(false);
    expect(await repository.injectionEnabled(), isFalse);
    await repository.setInjectionEnabled(true);
    expect(await repository.injectionEnabled(), isTrue);
  });
}

Future<void> _insertRaw(
  AppDatabase database,
  String id,
  String text,
  DateTime updatedAt, {
  bool pinned = false,
}) => database
    .into(database.aiMemories)
    .insert(
      AiMemoriesCompanion.insert(
        id: id,
        textContent: text,
        kind: AiMemoryKind.fact.name,
        domain: AiMemoryDomain.general.name,
        tagsJson: const Value('[]'),
        pinned: Value(pinned),
        source: 'manual',
        status: const Value('active'),
        createdAt: updatedAt,
        updatedAt: updatedAt,
      ),
    );
