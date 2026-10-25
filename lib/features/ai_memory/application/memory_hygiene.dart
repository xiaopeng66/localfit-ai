import 'dart:math' as math;

import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/domain/memory_dedupe.dart';

/// 整理建议（docs/43 B7 / docs/39 §7）：**只读扫描 + 建议，用户确认才动**。
///
/// 两类建议：
/// 1. 近义簇：按 `domain` 分桶，桶内两两 cosine ≥ [kMemoryClusterThreshold]
///    聚簇（每簇 ≥2 条），按簇内最高相似度排序；
/// 2. 长期未用：`lastUsedAt` 为空或早于 [kMemoryStaleDays] 天，且
///    `importance < 40`。
///
/// 纪律：
/// * **不自动改数据**：本类没有任何写方法；归档走页面上的显式动作
///   （`status='archived'`，列已存在）；
/// * **有界**：每桶最多 [kMemoryBucketLimit] 条，避免 O(n²) 爆炸；
/// * 向量不可用 ⇒ 只给「长期未用」建议（近义簇需要向量，不猜）。
final class MemoryHygiene {
  const MemoryHygiene({
    required this.repository,
    required this.clock,
    this.vectorIndex,
  });

  final AiMemoryRepository repository;
  final AppClock clock;
  final MemoryVectorIndex? vectorIndex;

  Future<MemoryHygieneReport> scan() async {
    final active = await repository.listActive();
    final Map<String, List<double>>? vectors;
    try {
      vectors = await vectorIndex?.vectors();
    } on Object {
      return MemoryHygieneReport(clusters: const [], stale: _stale(active));
    }
    return MemoryHygieneReport(
      clusters: vectors == null ? const [] : _clusters(active, vectors),
      stale: _stale(active),
    );
  }

  List<MemoryCluster> _clusters(
    List<AiMemory> memories,
    Map<String, List<double>> vectors,
  ) {
    final buckets = <AiMemoryDomain, List<AiMemory>>{};
    for (final memory in memories) {
      final bucket = buckets[memory.domain] ??= <AiMemory>[];
      if (bucket.length >= kMemoryBucketLimit) continue;
      if (!vectors.containsKey(memory.id)) continue;
      bucket.add(memory);
    }
    final out = <MemoryCluster>[];
    for (final entry in buckets.entries) {
      final bucket = entry.value;
      if (bucket.length < 2) continue;
      final parent = List<int>.generate(bucket.length, (index) => index);
      int find(int value) {
        while (parent[value] != value) {
          parent[value] = parent[parent[value]];
          value = parent[value];
        }
        return value;
      }

      void union(int a, int b) {
        final rootA = find(a);
        final rootB = find(b);
        if (rootA != rootB) parent[rootB] = rootA;
      }

      final bestByRoot = <int, double>{};
      for (var i = 0; i < bucket.length; i++) {
        for (var j = i + 1; j < bucket.length; j++) {
          final cosine = _cosine(
            vectors[bucket[i].id]!,
            vectors[bucket[j].id]!,
          );
          if (cosine < kMemoryClusterThreshold) continue;
          union(i, j);
          final root = find(i);
          if (cosine > (bestByRoot[root] ?? 0)) bestByRoot[root] = cosine;
        }
      }
      final groups = <int, List<AiMemory>>{};
      for (var i = 0; i < bucket.length; i++) {
        final root = find(i);
        (groups[root] ??= <AiMemory>[]).add(bucket[i]);
      }
      for (final group in groups.entries) {
        if (group.value.length < 2) continue;
        out.add(
          MemoryCluster(
            domain: entry.key,
            memories: group.value,
            maxSimilarity: bestByRoot[group.key] ?? 0,
          ),
        );
      }
    }
    out.sort((a, b) => b.maxSimilarity.compareTo(a.maxSimilarity));
    return out;
  }

  List<AiMemory> _stale(List<AiMemory> memories) {
    final cutoff = clock.nowUtc().subtract(
      const Duration(days: kMemoryStaleDays),
    );
    return [
      for (final memory in memories)
        if (memory.importance < kMemoryStaleImportance &&
            (memory.lastUsedAt == null || memory.lastUsedAt!.isBefore(cutoff)))
          memory,
    ]..sort((a, b) {
      final left = a.lastUsedAt;
      final right = b.lastUsedAt;
      if (left == null && right == null) return 0;
      if (left == null) return -1;
      if (right == null) return 1;
      return left.compareTo(right);
    });
  }

  static double _cosine(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    var dot = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }
}

/// 近义簇阈值（docs/43 B7：cosine ≥0.9）。
const double kMemoryClusterThreshold = 0.9;

/// 每桶上限（避免 O(n²) 爆炸；超出部分本次不扫描）。
const int kMemoryBucketLimit = 500;

/// 长期未用：180 天。
const int kMemoryStaleDays = 180;

/// 长期未用：importance < 40。
const int kMemoryStaleImportance = 40;

/// 一个近义簇（≥2 条）。
final class MemoryCluster {
  const MemoryCluster({
    required this.domain,
    required this.memories,
    required this.maxSimilarity,
  });

  final AiMemoryDomain domain;
  final List<AiMemory> memories;

  /// 簇内最高两两相似度（排序与展示用）。
  final double maxSimilarity;
}

/// 一次整理扫描的结果。
final class MemoryHygieneReport {
  const MemoryHygieneReport({required this.clusters, required this.stale});

  final List<MemoryCluster> clusters;
  final List<AiMemory> stale;

  bool get isEmpty => clusters.isEmpty && stale.isEmpty;
}
