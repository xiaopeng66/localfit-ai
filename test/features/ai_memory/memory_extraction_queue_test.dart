import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_extraction_queue.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 会话结束提炼进「待确认」（docs/43 B8）。
void main() {
  late AppDatabase db;
  late BackgroundJobRepository jobs;
  late AiMemoryRepository memories;
  late AppSettingsRepository settings;
  final now = DateTime.utc(2026, 10, 19, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    jobs = BackgroundJobRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: _SeqIds(),
    );
    memories = AiMemoryRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: _SeqIds(),
    );
    settings = AppSettingsRepository(database: db);
  });

  tearDown(() async => db.close());

  MemoryExtractionQueue queue({AiConversationService? service}) =>
      MemoryExtractionQueue(
        jobs: jobs,
        memoryRepository: memories,
        settings: settings,
        clock: FixedAppClock(now),
        service: service,
      );

  List<ConversationMessage> messages(int count) => [
    for (var i = 0; i < count; i++)
      ConversationMessage(
        id: 'm-$i',
        role: i.isEven ? ConversationRole.user : ConversationRole.assistant,
        text: '第 $i 条',
        createdAt: now,
      ),
  ];

  test('消息不足 6 条不入队', () async {
    final result = await queue(service: _FakeService('{}'))
        .endSession(conversationId: 'c1', messages: messages(5));
    expect(result.ok, isFalse);
    expect(await jobs.count(), 0);
  });

  test('开关关闭（默认）不入队', () async {
    expect(await queue().enabled(), isFalse);
    final result = await queue(service: _FakeService('{}'))
        .endSession(conversationId: 'c1', messages: messages(8));
    expect(result.ok, isFalse);
    expect(result.message, contains('未开启'));
    expect(await jobs.count(), 0);
  });

  test('开启后候选只进 payload，不写 ai_memories', () async {
    await queue().setEnabled(true);
    final service = _FakeService(
      '{"reply":"找到 1 条","candidates":[{"text":"喜欢清淡","kind":"preference","domain":"nutrition"}]}',
    );
    final result = await queue(service: service)
        .endSession(conversationId: 'c1', messages: messages(8));
    expect(result.ok, isTrue);
    expect(result.candidates, 1);
    expect(await memories.listActive(), isEmpty, reason: '永不静默写入');
    final rows = await jobs.list();
    expect(rows.single.type, kMemoryExtractionJobType);
    expect(rows.single.dedupeKey, 'memoryExtraction:c1');
    expect(rows.single.state, BackgroundJobState.pending);
    expect((rows.single.payload['candidates'] as List), hasLength(1));
    expect(await queue().pendingCount(), 1);
  });

  test('重复点同一个会话幂等（不重复调用 AI）', () async {
    await queue().setEnabled(true);
    final service = _FakeService('{"candidates":[{"text":"喜欢清淡"}]}');
    final q = queue(service: service);
    await q.endSession(conversationId: 'c1', messages: messages(8));
    await q.endSession(conversationId: 'c1', messages: messages(8));
    expect(service.calls, 1);
    expect(await jobs.count(), 1);
  });

  test('保存后 source=extracted；忽略后不再出现', () async {
    await queue().setEnabled(true);
    await queue(
      service: _FakeService(
        '{"candidates":[{"text":"喜欢清淡"},{"text":"周三晚上练腿"}]}',
      ),
    ).endSession(conversationId: 'c1', messages: messages(8));
    final q = queue();
    final pending = await q.pendingCandidates();
    expect(pending, hasLength(2));

    await q.confirm(pending.first);
    final active = await memories.listActive();
    expect(active.single.source, 'extracted');
    expect(active.single.text, pending.first.candidate.text);
    expect(await q.pendingCount(), 1);

    await q.ignore((await q.pendingCandidates()).single);
    expect(await q.pendingCount(), 0);
    expect(await jobs.count(), 0, reason: '全部处理完任务即完成');
    expect(await memories.listActive(), hasLength(1));
  });

  test('AI 失败进 failed 且可重试', () async {
    await queue().setEnabled(true);
    final result = await queue(service: const _FailingService())
        .endSession(conversationId: 'c1', messages: messages(8));
    expect(result.ok, isFalse);
    expect(await jobs.count(state: BackgroundJobState.failed), 1);
    expect(await queue().retryFailed(), 1);
    expect(await jobs.count(state: BackgroundJobState.pending), 1);
  });
}

class _FakeService implements AiConversationService {
  _FakeService(this.reply);

  final String reply;
  int calls = 0;

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    calls++;
    onProgress(reply);
    yield reply;
  }
}

class _FailingService implements AiConversationService {
  const _FailingService();

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    throw StateError('网络不可用');
  }
}

class _SeqIds implements IdGenerator {
  int _n = 0;
  @override
  String next() => 'id-${_n++}';
}
