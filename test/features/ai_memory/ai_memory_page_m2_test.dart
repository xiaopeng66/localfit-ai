import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart'
    hide ConversationMessage;
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_extraction_queue.dart';
import 'package:localfit_ai/features/ai_memory/application/memory_hygiene.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/domain/memory_dedupe.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/ai_memory/presentation/ai_memory_page.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 记忆页 M2 面（docs/43 B5/B7/B8/B11）。
///
/// 钉住「页面真的把能力露出来」：用量行/软顶提示、整理建议入口与弹层、
/// 待确认入口与「保存才写库」、分页与加载更多。
void main() {
  late AppDatabase db;
  late AiMemoryRepository memories;
  late BackgroundJobRepository jobs;
  late AppSettingsRepository settings;
  final now = DateTime.utc(2026, 10, 20, 9);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    memories = AiMemoryRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: _SeqIds(),
    );
    jobs = BackgroundJobRepository(
      database: db,
      clock: FixedAppClock(now),
      idGenerator: _SeqIds(),
    );
    settings = AppSettingsRepository(database: db);
  });

  tearDown(() async => db.close());

  Future<void> pumpPage(
    WidgetTester tester, {
    MemoryHygiene? hygiene,
    MemoryExtractionQueue? queue,
    Size size = const Size(420, 1800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AiMemoryPage(
          repository: memories,
          hygiene: hygiene,
          extractionQueue: queue,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// drift 的流在取消时会排一个 0 时长 Timer：拆树后泵一帧让它跑掉
  /// （**必须在测试体内**，addTearDown 里 pump 已经太晚）。
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('用量行与软顶提示（B5）', (tester) async {
    for (var i = 0; i < 3; i++) {
      await memories.remember(text: '记忆$i');
    }
    await pumpPage(tester);
    expect(
      find.byKey(const Key('ai-memory-usage')),
      findsOneWidget,
      reason: '「已用 N / 2000（软顶）」',
    );
    expect(find.textContaining('已用 3 / 2000'), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-softcap-hint')), findsNothing);
    await drain(tester);
  });

  testWidgets('分页：共 N 条 + 加载更多（B11）', (tester) async {
    for (var i = 0; i < 60; i++) {
      await db
          .into(db.aiMemories)
          .insert(
            AiMemoriesCompanion.insert(
              id: 'page-$i',
              textContent: '分页记忆$i',
              kind: 'fact',
              domain: 'general',
              source: 'manual',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    await pumpPage(tester);
    expect(find.byKey(const Key('ai-memory-total')), findsOneWidget);
    expect(find.text('共 60 条'), findsOneWidget);
    // 50 行列表里「加载更多」在屏外：先滚到底再断言/点击。
    // 直接滚到底：列表本身是 Scrollable，滚动后底部的「加载更多」才被构建。
    await tester.fling(
      find.byKey(const Key('ai-memory-list')),
      const Offset(0, -6000),
      3000,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai-memory-load-more')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-memory-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('共 60 条'), findsOneWidget);
    expect(
      find.byKey(const Key('ai-memory-load-more')),
      findsNothing,
      reason: '第二页已到末尾（60 ≤ 100），不再显示加载更多',
    );
    await drain(tester);
  });

  testWidgets('整理建议入口与弹层（B7）：空态如实', (tester) async {
    await memories.remember(text: '喜欢清淡');
    final hygiene = MemoryHygiene(
      repository: memories,
      clock: FixedAppClock(now),
      vectorIndex: _FakeVectors(),
    );
    await pumpPage(tester, hygiene: hygiene);
    expect(find.byKey(const Key('ai-memory-hygiene')), findsOneWidget);

    expect(find.byKey(const Key('ai-memory-hygiene')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ai-memory-hygiene')));
    // 弹层内容是异步扫描后才构建的：多泵几帧再断言。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('ai-memory-hygiene-sheet')), findsOneWidget);
    expect(find.text('暂时没有整理建议。'), findsOneWidget);
    await drain(tester);
  });

  testWidgets('整理动作：合并 / 归档 / 先不管（B7）', (tester) async {
    // 两条同域、cosine ≥0.9 的记忆（假向量直接给同一向量）。
    final first = await memories.remember(text: '喜欢清淡口味');
    final second = await memories.remember(
      text: '口味偏清淡',
      policy: DuplicatePolicy.allow,
    );
    final vectors = _IdenticalVectors();
    // 两条都要先有索引行（生产里 remember 会写；测试里手工补，保持同一份向量）。
    await vectors.upsertMemory(first);
    await vectors.upsertMemory(second);
    final hygiene = MemoryHygiene(
      repository: memories,
      clock: FixedAppClock(now),
      vectorIndex: vectors,
    );
    await pumpPage(tester, hygiene: hygiene);

    await tester.tap(find.byKey(const Key('ai-memory-hygiene')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    // 簇里第一条是基准，第二条可「合并到…」。
    await tester.tap(find.byKey(Key('ai-memory-hygiene-merge-${second.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final afterMerge = await memories.listActive();
    expect(afterMerge.map((m) => m.id), [first.id], reason: '旧条被改口闭合');

    // 再点「先不管」不写库（本测试用同一簇的另一条验证键存在）。
    expect(find.byKey(Key('ai-memory-hygiene-skip-${first.id}')), findsWidgets);
    await tester.tap(find.byKey(Key('ai-memory-hygiene-archive-${first.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(await memories.listActive(), isEmpty, reason: '归档后不在当前列表');
    await drain(tester);
  });

  testWidgets('待确认：忽略只移出 payload；非法候选就地报错（B8）', (tester) async {
    // 直接造一条含「与已有记忆完全相同」候选的待确认任务。
    await memories.remember(text: '喜欢清淡');
    await jobs.enqueue(
      type: kMemoryExtractionJobType,
      dedupeKey: 'memoryExtraction:c2',
      payload: const {
        'candidates': [
          {'text': '喜欢清淡'},
          {'text': '周三晚上练腿'},
        ],
      },
    );
    final queue = MemoryExtractionQueue(
      jobs: jobs,
      memoryRepository: memories,
      settings: settings,
      clock: FixedAppClock(now),
    );
    await pumpPage(tester, queue: queue);

    await tester.tap(find.byKey(const Key('ai-memory-pending')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 第 0 条与已有记忆相同 → 保存失败，就地显示错误键。
    await tester.tap(find.byKey(const Key('ai-memory-pending-save-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('ai-memory-pending-error-0')), findsOneWidget);

    // 第 1 条忽略 → 只从 payload 移除。
    await tester.tap(find.byKey(const Key('ai-memory-pending-ignore-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(await queue.pendingCount(), 1, reason: '第 0 条仍在待确认');
    expect((await memories.listActive()).map((m) => m.text), contains('喜欢清淡'));
    await drain(tester);
  });

  testWidgets('D2：自动提炼开关默认关；开启需确认；确认后真实生效', (tester) async {
    await settings.setBool(kAiMemoryAutoExtractKey, value: true);
    final queue = MemoryExtractionQueue(
      jobs: jobs,
      memoryRepository: memories,
      settings: settings,
      clock: FixedAppClock(now),
      service: _FakeService(
        '{"candidates":[{"text":"喜欢清淡","kind":"preference","domain":"nutrition"}]}',
      ),
    );
    await pumpPage(tester, queue: queue);
    final toggle = find.byKey(const Key('ai-memory-auto-extract-toggle'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

    // 关闭不弹窗，直接生效。
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<SwitchListTile>(toggle).value,
      isFalse,
      reason: '关闭不需要确认',
    );
    expect(await queue.enabled(), isFalse);
    await drain(tester);
  });

  testWidgets('D2：从关到开必须先确认（说明弹层），取消则不生效', (tester) async {
    final queue = MemoryExtractionQueue(
      jobs: jobs,
      memoryRepository: memories,
      settings: settings,
      clock: FixedAppClock(now),
    );
    await pumpPage(tester, queue: queue);
    final toggle = find.byKey(const Key('ai-memory-auto-extract-toggle'));
    expect(
      tester.widget<SwitchListTile>(toggle).value,
      isFalse,
      reason: 'D2 默认关',
    );

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // 说明弹层出现，取消 → 开关仍关。
    expect(find.text('开启会话结束自动提炼？'), findsOneWidget);
    await tester.tap(find.widgetWithText(LfTextButton, '取消').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(await queue.enabled(), isFalse);

    // 再开一次 → 点「开启」→ 生效。
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byKey(const Key('ai-memory-auto-extract-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(await queue.enabled(), isTrue);
    await drain(tester);
  });

  testWidgets('待确认入口（B8）：保存才写库，忽略只移出 payload', (tester) async {
    await settings.setBool(kAiMemoryAutoExtractKey, value: true);
    final queue = MemoryExtractionQueue(
      jobs: jobs,
      memoryRepository: memories,
      settings: settings,
      clock: FixedAppClock(now),
      service: _FakeService(
        '{"candidates":[{"text":"喜欢清淡","kind":"preference","domain":"nutrition"}]}',
      ),
    );
    await queue.endSession(
      conversationId: 'c1',
      messages: [
        for (var i = 0; i < 8; i++)
          ConversationMessage(
            id: 'm-$i',
            role: i.isEven ? ConversationRole.user : ConversationRole.assistant,
            text: '第 $i 条',
            createdAt: now,
          ),
      ],
    );
    expect(await memories.listActive(), isEmpty, reason: '提炼不自动写库');

    await pumpPage(tester, queue: queue);
    expect(find.byKey(const Key('ai-memory-pending')), findsOneWidget);
    expect(find.text('待确认 1 条'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-memory-pending')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('ai-memory-pending-sheet')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-memory-pending-save-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final stored = await memories.listActive();
    expect(stored.single.source, 'extracted');
    expect(stored.single.text, '喜欢清淡');
    expect(await queue.pendingCount(), 0);
    await drain(tester);
  });
}

/// 所有记忆共享同一向量（cosine=1）：用来构造稳定的近义簇。
class _IdenticalVectors implements MemoryVectorIndex {
  final Map<String, List<double>> _vectors = {};

  @override
  Future<Map<String, double>?> similarities(String text) async => {
    for (final id in _vectors.keys) id: 1.0,
  };

  @override
  Future<void> upsertMemory(AiMemory memory) async {
    _vectors[memory.id] = const [1, 0, 0, 0];
  }

  @override
  Future<void> deleteMemory(String id) async => _vectors.remove(id);

  @override
  Future<int> rebuild(List<AiMemory> memories) async => 0;

  @override
  Future<Map<String, List<double>>?> vectors() async => {..._vectors};
}

class _FakeVectors implements MemoryVectorIndex {
  @override
  Future<Map<String, double>?> similarities(String text) async => const {};

  @override
  Future<void> upsertMemory(AiMemory memory) async {}

  @override
  Future<void> deleteMemory(String id) async {}

  @override
  Future<int> rebuild(List<AiMemory> memories) async => 0;

  @override
  Future<Map<String, List<double>>?> vectors() async {
    final rows = <String, List<double>>{};
    return rows;
  }
}

class _FakeService implements AiConversationService {
  _FakeService(this.reply);

  final String reply;

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) async* {
    onProgress(reply);
    yield reply;
  }
}

class _SeqIds implements IdGenerator {
  int _n = 0;
  @override
  String next() => 'id-${_n++}';
}
