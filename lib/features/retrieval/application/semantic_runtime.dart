import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/domain/memory_dedupe.dart';
import 'package:localfit_ai/features/retrieval/application/memory_selector.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/retrieval/data/embedding_engine.dart';
import 'package:localfit_ai/features/retrieval/data/embedding_worker.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 语义检索是否启用（`app_settings` KV）。**缺键 = 开**：稳态复测后
/// 32 档两条门槛都过（`docs/evidence/2026-10-18-p0-eval.md` §7），
/// 所以默认走语义路；关掉后立刻退回关键词 + 标签（docs/39 §4.3 的降级）。
const String kSemanticSearchEnabledKey = 'semantic_search_enabled';

bool parseSemanticSearchEnabled(String? raw) {
  if (raw == null) return true;
  final value = raw.trim().toLowerCase();
  return value != 'false' && value != '0';
}

/// 一次索引填充的结果。
final class SemanticIndexReport {
  const SemanticIndexReport({
    required this.indexed,
    required this.skipped,
    required this.removed,
  });

  /// 新写入/重算的条数（文本变了或从未索引）。
  final int indexed;

  /// 文本未变、直接用旧向量的条数（`textHash` 命中）。
  final int skipped;

  /// 清掉的孤儿（条目已删除）。
  final int removed;

  int get total => indexed + skipped;
}

/// 语义检索运行时（docs/39 §4–§5/§8）：**唯一**持有嵌入引擎与
/// `embedding_index` 读写的地方。
///
/// 三条纪律：
/// 1. **失败即降级**：模型缺失/加载失败/推理异常都抛/返回 null，检索退回
///    关键词 + 标签，绝不阻断记餐或搜索（docs/39 §4.3）；
/// 2. **文本没变不重算**：`textHash` 命中直接跳过（加密库写放大很贵）；
/// 3. **换模型全量重建**：`modelId` 不同的一律当作未索引（向量空间不可混用）。
final class SemanticRuntime implements MemoryVectorIndex {
  SemanticRuntime({
    required this.database,
    required this.engineFactory,
    this.settings,
  });

  final AppDatabase database;

  /// 引擎的懒加载工厂（测试注入 [FakeEmbeddingEngine]）。
  final Future<EmbeddingEngine> Function() engineFactory;

  /// 开关的读侧；null = 未接线（按「开」处理，与缺键一致）。
  final AppSettingsRepository? settings;

  EmbeddingEngine? _engine;
  Object? _loadError;
  bool _loading = false;

  /// 引擎是否已就绪（未加载/加载失败都是 false）。
  bool get isReady => _engine != null;

  /// 加载失败的原因（给调试面板如实显示）。
  Object? get loadError => _loadError;

  /// 语义路是否可用 = 开关打开 且 引擎加载成功。
  Future<bool> isAvailable() async {
    if (!await enabled()) return false;
    try {
      await _ensureEngine();
      return true;
    } on Object {
      return false;
    }
  }

  Future<bool> enabled() async {
    final value = await settings?.getString(kSemanticSearchEnabledKey);
    return parseSemanticSearchEnabled(value);
  }

  Future<void> setEnabled(bool value) async {
    await settings?.setBool(kSemanticSearchEnabledKey, value: value);
  }

  /// 预热（**当前没有调用点**，保留给 isolate 化之后的空闲预热）。
  ///
  /// 【为什么现在不调】2026-10-19 设备实测：在主 isolate 上加载 24MB 权重 +
  /// 建 ORT session 会把低内存设备（2.5GB AVD）的界面拖住——点击全丢、
  /// 导航切不动。docs/39 §4.3 要求的是「长驻单 worker isolate + 空闲预热」，
  /// 两者要一起做；在 isolate 化之前调用本方法只有害处。
  Future<void> warmUp() async {
    try {
      await _ensureEngine();
    } on Object {
      // 预热失败不打扰用户：真正用到时还有一次降级机会。
    }
  }

  Future<EmbeddingEngine> _ensureEngine() async {
    final ready = _engine;
    if (ready != null) return ready;
    if (_loadError case final error?) {
      throw EmbeddingUnavailable('语义引擎不可用：$error');
    }
    if (_loading) {
      // 并发调用共享同一次加载（索引填充与查询可能同时进来）。
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final loaded = _engine;
      if (loaded != null) return loaded;
      throw EmbeddingUnavailable('语义引擎不可用：$_loadError');
    }
    _loading = true;
    try {
      final engine = await engineFactory();
      _engine = engine;
      return engine;
    } on Object catch (exception) {
      _loadError = exception;
      throw EmbeddingUnavailable('语义引擎不可用：$exception');
    } finally {
      _loading = false;
    }
  }

  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    // 两种引擎都要能收尾：直连 ONNX（测试/无 isolate 环境）与 worker 持有者。
    if (engine is OnnxEmbeddingEngine) {
      await engine.dispose();
    }
    if (engine is WorkerEmbeddingEngine) {
      await engine.dispose();
    }
  }

  // ── 索引 ────────────────────────────────────────────────────────────

  /// 索引文本（docs/39 §5.3）：`名称｜份量｜来源｜标签｜营养摘要`。
  static String dishIndexText(DishRecord dish) {
    final parts = <String>[
      dish.name,
      ?dish.servingWindow,
      '${dish.kcal.round()} kcal/份',
      '蛋白 ${dish.proteinG.round()} 碳水 ${dish.carbsG.round()} 脂肪 '
          '${dish.fatG.round()}',
    ];
    return parts.join('｜');
  }

  /// 填充/刷新菜品索引。返回本次的统计（进度经 [onProgress] 上报）。
  Future<SemanticIndexReport> indexDishes(
    List<DishRecord> dishes, {
    void Function(int done, int total)? onProgress,
  }) async {
    final engine = await _ensureEngine();
    final existing = {
      for (final row
          in await (database.select(database.embeddingIndex)..where(
                (row) =>
                    row.ownerType.equals('dish') &
                    row.modelId.equals(kEmbeddingModelId),
              ))
              .get())
        row.ownerId: row,
    };

    final pending = <DishRecord>[];
    final pendingHash = <String, String>{};
    var skipped = 0;
    var removed = 0;
    final alive = <String>{};
    for (final dish in dishes) {
      alive.add(dish.id);
      final text = dishIndexText(dish);
      final hash = await _sha256(text);
      final row = existing[dish.id];
      if (row != null && row.textHash == hash) {
        skipped++;
        continue;
      }
      pending.add(dish);
      pendingHash[dish.id] = hash;
    }
    // 孤儿：库里索引着但条目已不在（与启动 sweep 同义，这里顺手清）。
    for (final id in existing.keys) {
      if (alive.contains(id)) continue;
      await (database.delete(database.embeddingIndex)..where(
            (row) => row.ownerId.equals(id) & row.ownerType.equals('dish'),
          ))
          .go();
      removed++;
    }

    for (var start = 0; start < pending.length; start += 32) {
      final batch = pending.skip(start).take(32).toList();
      final vectors = await engine.embed([
        for (final dish in batch) dishIndexText(dish),
      ], maxLen: kDishEmbedMaxLen);
      await database.transaction(() async {
        for (var i = 0; i < batch.length; i++) {
          final dish = batch[i];
          await database
              .into(database.embeddingIndex)
              .insertOnConflictUpdate(
                EmbeddingIndexCompanion.insert(
                  ownerType: 'dish',
                  ownerId: dish.id,
                  modelId: kEmbeddingModelId,
                  dim: engine.dim,
                  encoding: 'f32',
                  textHash: pendingHash[dish.id]!,
                  vector: _encode(vectors[i]),
                  updatedAt: DateTime.now().toUtc(),
                ),
              );
        }
      });
      onProgress?.call(
        math.min(start + batch.length, pending.length),
        pending.length,
      );
    }
    return SemanticIndexReport(
      indexed: pending.length,
      skipped: skipped,
      removed: removed,
    );
  }

  /// 语义名次（id 列表，按余弦降序）。**任何失败都返回 null**（调用方降级）。
  Future<List<String>?> rankDishes(
    String query,
    List<DishRecord> dishes,
  ) async {
    if (query.trim().isEmpty || dishes.isEmpty) return null;
    try {
      if (!await enabled()) {
        lastRankError = '语义检索开关关闭';
        return null;
      }
      final engine = await _ensureEngine();
      final rows =
          await (database.select(database.embeddingIndex)..where(
                (row) =>
                    row.ownerType.equals('dish') &
                    row.modelId.equals(kEmbeddingModelId),
              ))
              .get();
      if (rows.isEmpty) {
        lastRankError = '索引为空（尚未建索引）';
        return null;
      }
      final byId = {for (final row in rows) row.ownerId: row};
      final queryVector = (await engine.embed(
        [query],
        maxLen: kDishEmbedMaxLen,
        prefix: kQueryPrefix,
      )).single;
      final scored = <(String, double)>[];
      for (final dish in dishes) {
        final row = byId[dish.id];
        if (row == null) continue;
        scored.add((dish.id, _cosine(queryVector, _decode(row.vector))));
      }
      if (scored.isEmpty) {
        lastRankError =
            '索引与当前菜品不匹配（${rows.length} 条索引 / '
            '${dishes.length} 道菜）';
        return null;
      }
      scored.sort((a, b) => b.$2.compareTo(a.$2));
      // 2026-10-20 审查 RV-P1-06：**必须**有最低相关度，否则任意查询都会把
      // 全部菜品当命中（设备实测：查「不存在的菜」→「找到 1 道 · 命中：语义」）。
      final relevant = scored
          .where((entry) => entry.$2 >= kDishSemanticMinCosine)
          .toList();
      if (relevant.isEmpty) {
        lastRankError =
            '没有足够相关的菜（最高 cos '
            '${scored.first.$2.toStringAsFixed(2)} < '
            '${kDishSemanticMinCosine.toStringAsFixed(2)}）';
        return null;
      }
      lastRankError = null;
      return [for (final entry in relevant) entry.$1];
    } on Object catch (error) {
      // 降级不是错误，但**原因必须可见**（docs/43 A1）：调试面板读它。
      lastRankError = '$error';
      return null;
    }
  }

  /// 最近一次 [rankDishes] 降级的原因（null = 上一次成功或从未调用）。
  String? lastRankError;

  /// 记忆注入的语义相关度打分器（docs/39 §6.4）。
  ///
  /// 返回 null ⇒ 调用方退回 [KeywordMemoryScorer]：开关关着、引擎不可用、
  /// 消息为空、或任一环节抛错——**降级不是报错**。
  Future<MemoryRelevanceScorer?> memoryScorer({
    required String userMessage,
    required List<AiMemory> memories,
  }) async {
    if (userMessage.trim().isEmpty || memories.isEmpty) return null;
    try {
      if (!await enabled()) return null;
      final engine = await _ensureEngine();
      // 记忆正文最长 140 字：用 64 档（32 会截断尾部；每轮只有一次查询嵌入，
      // p95 ≈ 17.8ms 落在「每轮额外 <30ms」的预算内）。
      final queryVector = (await engine.embed(
        [userMessage],
        maxLen: kMemoryEmbedMaxLen,
        prefix: kQueryPrefix,
      )).single;
      final vectors = await engine.embed([
        for (final memory in memories) memoryEmbedText(memory),
      ], maxLen: kMemoryEmbedMaxLen);
      final byId = <String, List<double>>{
        for (var i = 0; i < memories.length; i++) memories[i].id: vectors[i],
      };
      return VectorMemoryScorer(queryVector: queryVector, vectors: byId);
    } on Object {
      return null;
    }
  }

  /// 记忆的嵌入文本：正文 + 标签（类型/域不参与——它们是元数据，
  /// 拼进去会让「偏好」这类词把不相关条目拉近）。
  static String memoryEmbedText(AiMemory memory) => memory.tags.isEmpty
      ? memory.text
      : '${memory.text}｜${memory.tags.join(' ')}';

  // ── 记忆向量（docs/43 B6：ownerType='memory'）───────────────────────

  /// 文本与**已索引记忆**的 cosine（id → 相似度）。
  ///
  /// 返回 null = 语义不可用（开关关/引擎失败/无索引）——调用方据此跳过
  /// 向量判重，只保留字符串判重（降级，不是错误）。
  @override
  Future<Map<String, double>?> similarities(String text) async {
    if (text.trim().isEmpty) return null;
    try {
      if (!await enabled()) return null;
      final engine = await _ensureEngine();
      final rows =
          await (database.select(database.embeddingIndex)..where(
                (row) =>
                    row.ownerType.equals('memory') &
                    row.modelId.equals(kEmbeddingModelId),
              ))
              .get();
      if (rows.isEmpty) return const {};
      final queryVector = (await engine.embed(
        [text],
        maxLen: kMemoryEmbedMaxLen,
        prefix: kQueryPrefix,
      )).single;
      return {
        for (final row in rows)
          row.ownerId: _cosine(queryVector, _decode(row.vector)),
      };
    } on Object {
      return null;
    }
  }

  /// 写入/刷新一条记忆的向量。`textHash` 未变且模型一致时**跳过**。
  @override
  Future<void> upsertMemory(AiMemory memory) async {
    final engine = await _ensureEngine();
    final text = memoryEmbedText(memory);
    final hash = await _sha256(text);
    final existing =
        await (database.select(database.embeddingIndex)..where(
              (row) =>
                  row.ownerType.equals('memory') &
                  row.ownerId.equals(memory.id),
            ))
            .getSingleOrNull();
    if (existing != null &&
        existing.textHash == hash &&
        existing.modelId == kEmbeddingModelId) {
      return;
    }
    final vector = (await engine.embed([
      text,
    ], maxLen: kMemoryEmbedMaxLen)).single;
    await database
        .into(database.embeddingIndex)
        .insertOnConflictUpdate(
          EmbeddingIndexCompanion.insert(
            ownerType: 'memory',
            ownerId: memory.id,
            modelId: kEmbeddingModelId,
            dim: engine.dim,
            encoding: 'f32',
            textHash: hash,
            vector: _encode(vector),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  @override
  Future<void> deleteMemory(String id) async {
    await (database.delete(database.embeddingIndex)..where(
          (row) => row.ownerType.equals('memory') & row.ownerId.equals(id),
        ))
        .go();
  }

  /// 全量重建记忆向量（恢复备份后 / 换模型后）。返回写入条数。
  @override
  Future<int> rebuild(List<AiMemory> memories) async {
    final engine = await _ensureEngine();
    var written = 0;
    for (var start = 0; start < memories.length; start += 32) {
      final batch = memories.skip(start).take(32).toList(growable: false);
      final texts = [for (final memory in batch) memoryEmbedText(memory)];
      final hashes = <String>[for (final text in texts) await _sha256(text)];
      final vectors = await engine.embed(texts, maxLen: kMemoryEmbedMaxLen);
      await database.transaction(() async {
        for (var i = 0; i < batch.length; i++) {
          await database
              .into(database.embeddingIndex)
              .insertOnConflictUpdate(
                EmbeddingIndexCompanion.insert(
                  ownerType: 'memory',
                  ownerId: batch[i].id,
                  modelId: kEmbeddingModelId,
                  dim: engine.dim,
                  encoding: 'f32',
                  textHash: hashes[i],
                  vector: _encode(vectors[i]),
                  updatedAt: DateTime.now().toUtc(),
                ),
              );
          written++;
        }
      });
    }
    return written;
  }

  /// 全部记忆向量（整理建议的近义簇用）。不可用返回 null。
  @override
  Future<Map<String, List<double>>?> vectors() async {
    try {
      final rows =
          await (database.select(database.embeddingIndex)..where(
                (row) =>
                    row.ownerType.equals('memory') &
                    row.modelId.equals(kEmbeddingModelId),
              ))
              .get();
      return {for (final row in rows) row.ownerId: _decode(row.vector)};
    } on Object {
      return null;
    }
  }

  /// 供调试面板显示：已索引条数。
  Future<int> indexedCount({String ownerType = 'dish'}) async {
    final rows =
        await (database.select(database.embeddingIndex)..where(
              (row) =>
                  row.ownerType.equals(ownerType) &
                  row.modelId.equals(kEmbeddingModelId),
            ))
            .get();
    return rows.length;
  }

  static Future<String> _sha256(String text) async {
    final hash = await Sha256().hash(utf8.encode(text));
    return base64Encode(hash.bytes);
  }

  static Uint8List _encode(List<double> vector) {
    final data = Float32List.fromList(vector);
    return data.buffer.asUint8List();
  }

  static List<double> _decode(Uint8List bytes) {
    final data = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ 4,
    );
    return [for (final value in data) value];
  }

  static double _cosine(List<double> a, List<double> b) {
    // 两侧都已 L2 归一 ⇒ 点积即余弦；长度不一致时按较短的对齐（脏数据兜底）。
    final n = math.min(a.length, b.length);
    var dot = 0.0;
    for (var i = 0; i < n; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }
}
