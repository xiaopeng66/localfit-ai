import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';

/// 写入时的重复策略（docs/43 B6 / docs/39 §7）。
///
/// * [reject]（默认）：完全相同 / cosine ≥0.96 拒绝，0.88–0.96 抛
///   [AiMemoryMergeSuggested]；
/// * [allow]：用户明确「我确定要另存一条」时跳过向量判重（字符串完全相同
///   仍然拒绝——那不是「另存」，是重复提交）。
enum DuplicatePolicy { reject, allow }

/// 一条近重复候选（`findNearDuplicates` / 合并提议共用）。
final class NearDuplicate {
  const NearDuplicate({
    required this.id,
    required this.text,
    required this.cosine,
  });

  final String id;
  final String text;
  final double cosine;
}

/// 0.88–0.96：不静默并存，也不直接拒绝——**提议合并**（docs/39 §7）。
///
/// 命令层/页面把它转成「建议合并/更新」；用户确认后走 `update` 或
/// `supersede`，不新造机制。
final class AiMemoryMergeSuggested implements Exception {
  const AiMemoryMergeSuggested(this.candidates);

  final List<NearDuplicate> candidates;

  /// 给人看的中文（取最接近的一条做文案）。
  String get message {
    if (candidates.isEmpty) return '已有相近记忆，建议合并。';
    final best = candidates.first;
    return '已有相近记忆「${best.text}」，建议合并或更新，而不是另存一条。';
  }

  @override
  String toString() => message;
}

/// 记忆向量索引（docs/43 B6）：**仓储只认这个接口**，实现由
/// `SemanticRuntime` 提供（端上 bge-small-zh，写 `embedding_index`）。
///
/// 所有方法都允许抛错/返回 null：向量不可用是**降级**，不是写入失败
/// （docs/41 §10 降级矩阵）。调用方（仓储）负责吞掉并继续走字符串判重。
abstract interface class MemoryVectorIndex {
  /// 文本与已索引记忆的 cosine（id → 相似度）。不可用返回 null。
  Future<Map<String, double>?> similarities(String text);

  /// 写入/刷新一条记忆的向量（`textHash` 未变时跳过）。
  Future<void> upsertMemory(AiMemory memory);

  /// 删除一条记忆的向量。
  Future<void> deleteMemory(String id);

  /// 全量重建（恢复备份 / 换模型后）；返回写入条数。
  Future<int> rebuild(List<AiMemory> memories);

  /// 全部记忆向量（整理建议的近义簇用）。不可用返回 null。
  Future<Map<String, List<double>>?> vectors();
}
