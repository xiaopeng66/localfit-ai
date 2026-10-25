import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/ai_memory/application/ai_memory_candidates.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 「会话结束自动提炼」开关（docs/43 B8，**默认关**）。
///
/// 决策点 D2 未答复 ⇒ 默认关：真实 AI 调用只在用户显式开启后发生；
/// 关闭时只保留对话页顶栏的手动「从对话提炼记忆」。
const String kAiMemoryAutoExtractKey = 'ai_memory_auto_extract';

bool parseAiMemoryAutoExtractEnabled(String? raw) =>
    raw == 'true' || raw == '1';

/// 至少多少条可用消息才允许「结束本次会话」（docs/43 B8：≥6）。
const int kMemoryExtractionMinMessages = 6;

/// 任务类型（`background_jobs.type`）。
const String kMemoryExtractionJobType = 'memoryExtraction';

/// 一条待确认候选（job payload 的投影）。
final class PendingMemoryCandidate {
  const PendingMemoryCandidate({
    required this.jobId,
    required this.index,
    required this.candidate,
  });

  final String jobId;
  final int index;
  final AiMemoryCandidate candidate;
}

/// 「结束本次会话」的结果（页面直接上屏，不抛预期内的失败）。
final class MemoryExtractionResult {
  const MemoryExtractionResult({
    required this.ok,
    required this.message,
    this.candidates = 0,
  });

  final bool ok;
  final String message;
  final int candidates;
}

/// 会话结束提炼进「待确认」队列（docs/43 B8 / docs/39 §7）。
///
/// **不新增表**：候选存 `background_jobs.payload`：
/// ```json
/// {"conversationId":"…","candidates":[{text,kind,domain,tags}],"reply":"…","createdAt":"…"}
/// ```
/// 状态语义：`pending` = 等待用户确认（**不是**等待执行）；`failed` = 提炼
/// 调用失败，可重试。确认一条就从 payload 移除一条，全部处理完删行。
///
/// **永不静默写入**：本类唯一的写库路径是 [confirm] 里的
/// `remember(source='extracted')`，且只由用户点击触发。
final class MemoryExtractionQueue {
  MemoryExtractionQueue({
    required this.jobs,
    required this.memoryRepository,
    required this.settings,
    required this.clock,
    this.service,
  });

  final BackgroundJobRepository jobs;
  final AiMemoryRepository memoryRepository;
  final AppSettingsRepository settings;
  final AppClock clock;

  /// AI 对话服务；null = 未配置（提炼失败并如实说明，不入库）。
  final AiConversationService? service;

  Future<bool> enabled() async => parseAiMemoryAutoExtractEnabled(
    await settings.getString(kAiMemoryAutoExtractKey),
  );

  Future<void> setEnabled(bool value) =>
      settings.setBool(kAiMemoryAutoExtractKey, value: value);

  /// 「结束本次会话」：消息 ≥6 且开关开启才入队并立即执行一次。
  ///
  /// [sessionId] 是聊天记录会话（当前只有 `default`）；[conversationId] 由
  /// 调用方给出（用最后一条消息 id 标记「这一次会话」），保证重复点击幂等、
  /// 下一条消息开始的新会话又是新任务。
  ///
  /// [explicit] = 用户**显式**点了「结束本次对话」（`RV4-P2-05` / D4）。
  /// 显式动作**不受「自动提炼」开关约束**——那个开关只管后台自动跑；
  /// 非显式（后台/自动路径）仍按开关拦截。
  Future<MemoryExtractionResult> endSession({
    required String conversationId,
    required List<ConversationMessage> messages,
    bool explicit = false,
  }) async {
    final usable = _usable(messages);
    if (usable.length < kMemoryExtractionMinMessages) {
      return MemoryExtractionResult(
        ok: false,
        message: '这段对话还太短（至少 $kMemoryExtractionMinMessages 条），先多聊几句。',
      );
    }
    if (!explicit && !await enabled()) {
      return const MemoryExtractionResult(
        ok: false,
        message: '自动提炼未开启（默认关）。可在设置里开启后再结束会话。',
      );
    }
    final jobId = await jobs.enqueue(
      type: kMemoryExtractionJobType,
      dedupeKey: 'memoryExtraction:$conversationId',
      payload: {
        'conversationId': conversationId,
        'candidates': const <Object>[],
        'reply': '',
        'createdAt': clock.nowUtc().toIso8601String(),
      },
    );
    final existing = await jobs.byId(jobId);
    if (existing == null) {
      return const MemoryExtractionResult(ok: false, message: '这次会话已经处理完了。');
    }
    final candidates = _payloadCandidates(existing.payload);
    if (candidates.isNotEmpty) {
      return MemoryExtractionResult(
        ok: true,
        message: '这段对话已有 ${candidates.length} 条待确认。',
        candidates: candidates.length,
      );
    }
    final claimed = await jobs.claimById(jobId);
    if (claimed == null) {
      return const MemoryExtractionResult(
        ok: false,
        message: '提炼任务正在执行，请稍后到记忆页查看。',
      );
    }
    final ai = service;
    if (ai == null) {
      await jobs.fail(jobId, error: 'AI 未配置');
      return const MemoryExtractionResult(ok: false, message: 'AI 未配置，无法提炼记忆。');
    }
    try {
      final parse = await _extract(ai, usable);
      final payload = {
        ...claimed.payload,
        'candidates': [
          for (final candidate in parse.candidates)
            {
              'text': candidate.text,
              'kind': candidate.kind.name,
              'domain': candidate.domain.name,
              'tags': candidate.tags,
            },
        ],
        'reply': parse.reply,
        'updatedAt': clock.nowUtc().toIso8601String(),
      };
      if (parse.candidates.isEmpty) {
        // 没有候选：任务完成（不留下一个永远空着的待确认）。
        await jobs.complete(jobId);
        return MemoryExtractionResult(
          ok: true,
          message: parse.reply.isEmpty ? '这段对话没有值得记住的内容。' : parse.reply,
        );
      }
      await jobs.updatePayload(jobId, payload);
      // 回到 pending：等待用户确认（不是等待执行）。
      await jobs.requeue(jobId);
      return MemoryExtractionResult(
        ok: true,
        message: '已提炼 ${parse.candidates.length} 条候选，去「AI 记忆」确认。',
        candidates: parse.candidates.length,
      );
    } on Object catch (error) {
      await jobs.fail(jobId, error: '$error');
      return const MemoryExtractionResult(ok: false, message: '提炼失败，可在记忆页重试。');
    }
  }

  Future<AiMemoryCandidateParse> _extract(
    AiConversationService ai,
    List<ConversationMessage> usable,
  ) async {
    final transcript = [
      for (final message in usable.take(40))
        '${message.role == ConversationRole.user ? 'U' : 'A'}: '
            '${message.text.trim()}',
    ].join('\n');
    final buffer = StringBuffer();
    await ai
        .sendMessage(
          messages: [
            ConversationMessage(
              id: 'memory-extract-${clock.nowUtc().microsecondsSinceEpoch}',
              role: ConversationRole.user,
              text: aiMemoryExtractPrompt(transcript),
              createdAt: clock.nowUtc(),
            ),
          ],
          onProgress: buffer.write,
          systemContext: null,
        )
        .drain<void>();
    return parseAiMemoryCandidates(buffer.toString());
  }

  /// 待确认候选（按入队顺序）。
  Future<List<PendingMemoryCandidate>> pendingCandidates() async {
    final pending = await jobs.list(state: BackgroundJobState.pending);
    final out = <PendingMemoryCandidate>[];
    for (final job in pending) {
      if (job.type != kMemoryExtractionJobType) continue;
      final candidates = _payloadCandidates(job.payload);
      for (var i = 0; i < candidates.length; i++) {
        out.add(
          PendingMemoryCandidate(
            jobId: job.id,
            index: i,
            candidate: candidates[i],
          ),
        );
      }
    }
    return out;
  }

  Future<int> pendingCount() async => (await pendingCandidates()).length;

  /// 用户确认：写 `remember(source='extracted')`，成功后从 payload 移除。
  ///
  /// 失败（重复/敏感/合并建议）原样抛出——页面把中文消息显示给用户，
  /// **候选留在待确认里**（不吞掉）。
  Future<void> confirm(PendingMemoryCandidate item) async {
    await memoryRepository.remember(
      text: item.candidate.text,
      kind: item.candidate.kind,
      domain: item.candidate.domain,
      tags: item.candidate.tags,
      source: 'extracted',
    );
    await _removeAt(item.jobId, item.index);
  }

  /// 用户忽略：只从 payload 移除，不写库。
  Future<void> ignore(PendingMemoryCandidate item) =>
      _removeAt(item.jobId, item.index);

  /// 失败任务重试（再次执行一次提炼）。
  Future<int> retryFailed() => jobs.retryFailed(type: kMemoryExtractionJobType);

  Future<void> _removeAt(String jobId, int index) async {
    final job = await jobs.byId(jobId);
    if (job == null) return;
    final candidates = _payloadCandidates(job.payload);
    if (index < 0 || index >= candidates.length) return;
    final next = [
      for (var i = 0; i < candidates.length; i++)
        if (i != index)
          {
            'text': candidates[i].text,
            'kind': candidates[i].kind.name,
            'domain': candidates[i].domain.name,
            'tags': candidates[i].tags,
          },
    ];
    if (next.isEmpty) {
      await jobs.complete(jobId);
      return;
    }
    await jobs.updatePayload(jobId, {
      ...job.payload,
      'candidates': next,
      'updatedAt': clock.nowUtc().toIso8601String(),
    });
  }

  static List<AiMemoryCandidate> _payloadCandidates(
    Map<String, Object?> payload,
  ) {
    final raw = payload['candidates'];
    if (raw is! List) return const [];
    return [for (final entry in raw) ?parseAiMemoryCandidate(entry)];
  }

  static List<ConversationMessage> _usable(
    List<ConversationMessage> messages,
  ) => [
    for (final message in messages)
      if (message.text.trim().isNotEmpty &&
          message.status != ConversationMessageStatus.error)
        message,
  ];
}
