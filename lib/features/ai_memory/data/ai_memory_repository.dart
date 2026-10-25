import 'package:drift/drift.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/domain/memory_dedupe.dart';

/// 长期记忆的落库与读取（docs/38 §4）。
///
/// 写入纪律：
/// * **有界**：软顶 [kAiMemorySoftCap]（超过仍可写，提示整理）/ 硬顶
///   [kAiMemoryHardCap]（达到即拒绝）；单条 ≤ [kAiMemoryMaxTextLength] 字。
/// * **去重**：归一化后完全相同 ⇒ 拒绝（快速路径，不花嵌入）；一条包含另一条
///   ⇒ 拒绝；向量 cosine ≥0.96 ⇒ 拒绝；0.88–0.96 ⇒ 抛
///   [AiMemoryMergeSuggested]（提议合并）；<0.88 正常写入。
/// * **敏感红线**：证件/银行/移民类直接拒绝（[aiMemorySensitiveReason]）。
/// * **不静默**：所有拒绝都抛 [AiMemoryException]，消息是给人看的中文。
final class AiMemoryRepository {
  AiMemoryRepository({
    required this.database,
    required this.clock,
    required this.idGenerator,
    this.vectorIndex,
  });

  final AppDatabase database;
  final AppClock clock;
  final IdGenerator idGenerator;

  /// 记忆向量索引（docs/43 B6）。null = 未接线：只走字符串判重
  /// （向量不可用是降级，不是写入失败）。
  final MemoryVectorIndex? vectorIndex;

  /// 管理页用：按「置顶优先、最近更新在前」订阅全部记忆。
  Stream<List<AiMemory>> watchActive() {
    final query = database.select(database.aiMemories)
      ..where(
        (row) => row.status.equals('active') & row.supersededById.isNull(),
      )
      ..orderBy([
        (row) => OrderingTerm.desc(row.pinned),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.watch().map((rows) => [for (final row in rows) _fromRow(row)]);
  }

  Future<List<AiMemory>> listActive({int limit = kAiMemoryHardCap}) async {
    final rows =
        await (database.select(database.aiMemories)
              // 改口后的旧条不再参与注入/匹配（历史页另读）。
              ..where(
                (row) =>
                    row.status.equals('active') & row.supersededById.isNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.pinned),
                (row) => OrderingTerm.desc(row.updatedAt),
              ])
              ..limit(limit))
            .get();
    return [for (final row in rows) _fromRow(row)];
  }

  Future<AiMemory> remember({
    required String text,
    AiMemoryKind kind = AiMemoryKind.preference,
    AiMemoryDomain domain = AiMemoryDomain.general,
    List<String> tags = const [],
    bool pinned = false,
    String source = 'explicit',
    int importance = 50,
    DateTime? expiresAt,
    String? sourceMessageId,
    String? linkedEntityType,
    String? linkedEntityId,
    DuplicatePolicy policy = DuplicatePolicy.reject,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const AiMemoryException('记忆内容不能为空。');
    }
    if (trimmed.length > kAiMemoryMaxTextLength) {
      throw const AiMemoryException(
        '这条记忆太长（最多 $kAiMemoryMaxTextLength 字），请拆成几条。',
      );
    }
    final sensitive = aiMemorySensitiveReason(trimmed);
    if (sensitive != null) {
      throw AiMemoryException('这条看起来是敏感信息（$sensitive），不保存。');
    }

    final cleanedTags = _cleanTags(tags);
    final active = await listActive();
    if (active.length >= kAiMemoryHardCap) {
      throw const AiMemoryException(
        '记忆已达硬顶（$kAiMemoryHardCap 条），请先在「我的 → AI 记忆」里整理。',
      );
    }
    final normalized = normalizeAiMemoryText(trimmed);
    for (final memory in active) {
      final existing = normalizeAiMemoryText(memory.text);
      if (existing == normalized) {
        // 快速路径：完全相同直接拒，**不花一次嵌入**（docs/43 B6）。
        throw AiMemoryException('已经有这条记忆了：${memory.text}');
      }
      if (existing.contains(normalized) || normalized.contains(existing)) {
        throw AiMemoryException('已有相近记忆「${memory.text}」，请改写这一条或先删掉旧的那条。');
      }
    }
    // 向量判重（docs/39 §7 / docs/43 B6）：只对 active 条目；向量不可用
    // （null）⇒ 跳过，字符串判重已经生效。
    if (policy == DuplicatePolicy.reject) {
      final duplicates = await findNearDuplicates(
        trimmed,
        threshold: 0.88,
        active: active,
      );
      if (duplicates.isNotEmpty) {
        final best = duplicates.first;
        if (best.cosine >= 0.96) {
          throw AiMemoryException('已有非常接近的一条：${best.text}');
        }
        throw AiMemoryMergeSuggested(duplicates);
      }
    }

    final now = clock.nowUtc();
    final id = idGenerator.next();
    await database
        .into(database.aiMemories)
        .insert(
          AiMemoriesCompanion.insert(
            id: id,
            textContent: trimmed,
            kind: kind.name,
            domain: domain.name,
            tagsJson: Value(encodeAiMemoryTags(cleanedTags)),
            pinned: Value(pinned),
            source: source,
            status: const Value('active'),
            importance: Value(importance.clamp(0, 100)),
            expiresAt: Value(expiresAt),
            sourceMessageId: Value(sourceMessageId),
            linkedEntityType: Value(linkedEntityType),
            linkedEntityId: Value(linkedEntityId),
            // 时间语义（S14）：新建即生效。
            validFrom: Value(now),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final memory = AiMemory(
      id: id,
      text: trimmed,
      kind: kind,
      domain: domain,
      tags: cleanedTags,
      pinned: pinned,
      source: source,
      status: 'active',
      createdAt: now,
      updatedAt: now,
      importance: importance.clamp(0, 100),
      expiresAt: expiresAt,
      sourceMessageId: sourceMessageId,
      linkedEntityType: linkedEntityType,
      linkedEntityId: linkedEntityId,
      validFrom: now,
    );
    await _indexVector(memory);
    return memory;
  }

  /// 向量写入是**尽力而为**：引擎不可用不阻断记忆落库（降级矩阵）。
  Future<void> _indexVector(AiMemory memory) async {
    final index = vectorIndex;
    if (index == null) return;
    try {
      await index.upsertMemory(memory);
    } on Object {
      // 索引失败只影响下一次判重/整理建议，不影响这条记忆本身。
    }
  }

  /// 近重复候选（docs/43 B6）：cosine ≥ [threshold]，按相似度降序。
  ///
  /// 只返回 **active** 条目（已归档/改口的不参与写入判重）。
  Future<List<NearDuplicate>> findNearDuplicates(
    String text, {
    double threshold = 0.88,
    List<AiMemory>? active,
  }) async {
    final index = vectorIndex;
    if (index == null) return const [];
    final Map<String, double>? similarities;
    try {
      similarities = await index.similarities(text);
    } on Object {
      return const [];
    }
    if (similarities == null || similarities.isEmpty) return const [];
    final memories = active ?? await listActive();
    final byId = {for (final memory in memories) memory.id: memory};
    final out = <NearDuplicate>[];
    for (final entry in similarities.entries) {
      final memory = byId[entry.key];
      if (memory == null) continue;
      if (entry.value < threshold) continue;
      out.add(
        NearDuplicate(id: memory.id, text: memory.text, cosine: entry.value),
      );
    }
    out.sort((a, b) => b.cosine.compareTo(a.cosine));
    return out;
  }

  Future<AiMemory?> update(
    String id, {
    String? text,
    AiMemoryKind? kind,
    AiMemoryDomain? domain,
    List<String>? tags,
    bool? pinned,
  }) async {
    final existing = await _byId(id);
    if (existing == null) return null;
    final nextText = text == null ? existing.text : text.trim();
    if (nextText.isEmpty) {
      throw const AiMemoryException('记忆内容不能为空。');
    }
    if (nextText.length > kAiMemoryMaxTextLength) {
      throw const AiMemoryException(
        '这条记忆太长（最多 $kAiMemoryMaxTextLength 字），请拆成几条。',
      );
    }
    final sensitive = aiMemorySensitiveReason(nextText);
    if (sensitive != null) {
      throw AiMemoryException('这条看起来是敏感信息（$sensitive），不保存。');
    }
    // 编辑也要过去重关：改成与另一条相同/相近 ⇒ 拒绝（否则用户能把两条
    // 编辑成一样的，注入时自相矛盾）。
    final normalized = normalizeAiMemoryText(nextText);
    if (normalized != normalizeAiMemoryText(existing.text)) {
      for (final memory in await listActive()) {
        if (memory.id == id) continue;
        final other = normalizeAiMemoryText(memory.text);
        if (other == normalized ||
            other.contains(normalized) ||
            normalized.contains(other)) {
          throw AiMemoryException('已有相近记忆「${memory.text}」，请改写这一条或先删掉旧的那条。');
        }
      }
    }
    final nextTags = tags == null ? existing.tags : _cleanTags(tags);
    final now = clock.nowUtc();
    await (database.update(
      database.aiMemories,
    )..where((row) => row.id.equals(id))).write(
      AiMemoriesCompanion(
        textContent: Value(nextText),
        kind: Value((kind ?? existing.kind).name),
        domain: Value((domain ?? existing.domain).name),
        tagsJson: Value(encodeAiMemoryTags(nextTags)),
        pinned: Value(pinned ?? existing.pinned),
        updatedAt: Value(now),
      ),
    );
    final updated = AiMemory(
      id: existing.id,
      text: nextText,
      kind: kind ?? existing.kind,
      domain: domain ?? existing.domain,
      tags: nextTags,
      pinned: pinned ?? existing.pinned,
      source: existing.source,
      status: existing.status,
      createdAt: existing.createdAt,
      updatedAt: now,
      importance: existing.importance,
      useCount: existing.useCount,
      lastUsedAt: existing.lastUsedAt,
      supersededById: existing.supersededById,
      expiresAt: existing.expiresAt,
      sourceMessageId: existing.sourceMessageId,
      linkedEntityType: existing.linkedEntityType,
      linkedEntityId: existing.linkedEntityId,
      validFrom: existing.validFrom,
      validTo: existing.validTo,
    );
    // 正文/标签变了 ⇒ 向量必须刷新（textHash 不同会重算）。
    if (normalized != normalizeAiMemoryText(existing.text)) {
      await _indexVector(updated);
    }
    return updated;
  }

  Future<bool> setPinned(String id, bool pinned) async {
    final changed =
        await (database.update(
          database.aiMemories,
        )..where((row) => row.id.equals(id))).write(
          AiMemoriesCompanion(
            pinned: Value(pinned),
            updatedAt: Value(clock.nowUtc()),
          ),
        );
    return changed > 0;
  }

  Future<bool> delete(String id) async {
    final removed = await (database.delete(
      database.aiMemories,
    )..where((row) => row.id.equals(id))).go();
    if (removed > 0) {
      // 索引行同步删（docs/43 B6）：留着就是一条永远匹配不到的悬空向量。
      try {
        await vectorIndex?.deleteMemory(id);
      } on Object {
        // 删除索引失败由启动 orphan sweep 兜底。
      }
    }
    return removed > 0;
  }

  Future<int> deleteAll() async {
    // 先清索引再删正表：中途失败时 sweep 会把悬空行扫掉。
    try {
      final vectors = await vectorIndex?.vectors();
      if (vectors != null) {
        for (final id in vectors.keys) {
          await vectorIndex?.deleteMemory(id);
        }
      }
    } on Object {
      // 同上：启动 sweep 兜底。
    }
    return database.delete(database.aiMemories).go();
  }

  /// 归档（docs/43 B7）：`status='archived'`，不删除、`listAsOf` 仍可回看。
  Future<bool> archive(String id) async {
    final changed =
        await (database.update(
          database.aiMemories,
        )..where((row) => row.id.equals(id))).write(
          AiMemoriesCompanion(
            status: const Value('archived'),
            updatedAt: Value(clock.nowUtc()),
          ),
        );
    return changed > 0;
  }

  /// 当前 active 条数（页面「已用 N / 2000」与软顶提示用）。
  Future<int> activeCount() async {
    final query = database.selectOnly(database.aiMemories)
      ..addColumns([database.aiMemories.id.count()])
      ..where(
        database.aiMemories.status.equals('active') &
            database.aiMemories.supersededById.isNull(),
      );
    final row = await query.getSingle();
    return row.read(database.aiMemories.id.count()) ?? 0;
  }

  /// 是否已超过软顶（docs/43 B5：超过仍可写，但提示「建议整理」）。
  Future<bool> isOverSoftCap() async => await activeCount() > kAiMemorySoftCap;

  /// 关键词匹配（`memory.forget` 与页面搜索共用）：
  /// 归一化后「记忆包含关键词 / 关键词包含记忆 / 标签命中」。
  ///
  /// 反向包含只在记忆本身 ≥2 字时成立——否则一个「腿」字会把一半记忆
  /// 都算成命中，逼用户做无意义的选择。
  Future<List<AiMemory>> findMatches(String query) async {
    final normalized = normalizeAiMemoryText(query);
    if (normalized.isEmpty) return const [];
    final active = await listActive();
    return [
      for (final memory in active)
        if (_matches(memory, normalized)) memory,
    ];
  }

  /// 「对话时使用记忆」开关。缺键 = 开启（默认值由 [parseAiMemoryInjectionEnabled]
  /// 与读侧共用，避免两处各写一套）。
  Future<bool> injectionEnabled() async {
    final row = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(kAiMemoryInjectionKey))).getSingleOrNull();
    return parseAiMemoryInjectionEnabled(row?.value);
  }

  Future<void> setInjectionEnabled(bool enabled) async {
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: kAiMemoryInjectionKey,
            value: enabled ? 'true' : 'false',
          ),
        );
  }

  bool _matches(AiMemory memory, String normalized) {
    final text = normalizeAiMemoryText(memory.text);
    if (text.contains(normalized)) return true;
    if (text.length >= 2 && normalized.contains(text)) return true;
    for (final tag in memory.tags) {
      final value = normalizeAiMemoryText(tag);
      if (value.isEmpty) continue;
      if (value.contains(normalized) || normalized.contains(value)) {
        return true;
      }
    }
    return false;
  }

  List<String> _cleanTags(List<String> tags) {
    final out = <String>[];
    for (final tag in tags) {
      final value = tag.trim();
      if (value.isEmpty) continue;
      if (value.length > kAiMemoryMaxTagLength) {
        throw const AiMemoryException('标签太长（每个最多 $kAiMemoryMaxTagLength 字）。');
      }
      if (!out.contains(value)) out.add(value);
    }
    if (out.length > kAiMemoryMaxTags) {
      throw const AiMemoryException('标签最多 $kAiMemoryMaxTags 个。');
    }
    return out;
  }

  Future<AiMemory?> _byId(String id) async {
    final row = await (database.select(
      database.aiMemories,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  AiMemory _fromRow(AiMemoryRow row) => AiMemory(
    id: row.id,
    text: row.textContent,
    kind: AiMemoryKind.tryParse(row.kind) ?? AiMemoryKind.fact,
    domain: AiMemoryDomain.tryParse(row.domain) ?? AiMemoryDomain.general,
    tags: decodeAiMemoryTags(row.tagsJson),
    pinned: row.pinned,
    source: row.source,
    status: row.status,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    importance: row.importance,
    useCount: row.useCount,
    lastUsedAt: row.lastUsedAt,
    supersededById: row.supersededById,
    expiresAt: row.expiresAt,
    sourceMessageId: row.sourceMessageId,
    linkedEntityType: row.linkedEntityType,
    linkedEntityId: row.linkedEntityId,
    validFrom: row.validFrom,
    validTo: row.validTo,
  );

  // ── schema 28（docs/41 §5）：治理、历史/撤销、分页搜索、导入导出 ──────

  /// 改口：旧条指向新条（**不删**，历史可看、可撤销）。
  Future<void> supersede({required String oldId, required String newId}) async {
    final current =
        await (database.select(database.aiMemories)
              ..where((row) => row.id.equals(oldId))
              ..limit(1))
            .getSingleOrNull();
    if (current == null) return;
    final now = clock.nowUtc();
    await (database.update(
      database.aiMemories,
    )..where((row) => row.id.equals(oldId))).write(
      AiMemoriesCompanion(
        supersededById: Value(newId),
        // 时间语义（S14）：改口那一刻起旧条不再成立。只在尚未闭合时写，
        // 重复改口不覆盖第一次的失效时刻。
        validTo: Value(current.validTo ?? now),
        updatedAt: Value(now),
      ),
    );
  }

  /// 撤销改口：清掉 supersededById，旧条重新 active。
  Future<void> undoSupersede(String oldId) async {
    await (database.update(
      database.aiMemories,
    )..where((row) => row.id.equals(oldId))).write(
      AiMemoriesCompanion(
        supersededById: const Value(null),
        // 撤销改口 = 窗口重新打开（S14）。
        validTo: const Value(null),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
  }

  /// 「当时是什么」（G23 / S14）：[when] 时刻成立的条目，含已被改口但当时
  /// 仍有效的旧条。
  ///
  /// 比较在 Dart 侧做而不是 SQL：`validFrom/validTo` 是可空时间列，
  /// 不同 drift 版本/平台写出的文本形态未必一致；条数上限 2000，读全量
  /// 再筛既确定又够快（也避免「字符串比较时区」这种隐蔽错误）。
  ///
  /// **不看 `supersededById`、只看窗口**：改口过的旧条在它有效的时段里
  /// 就是当时的答案；这正是本功能的全部意义。
  ///
  /// 也**不看 `status`**（docs/43 B7）：归档只是「从当前列表移出」，
  /// 历史回看仍应看得到它当时成立。
  Future<List<AiMemory>> listAsOf(DateTime when) async {
    final rows =
        await (database.select(database.aiMemories)..orderBy([
              (row) => OrderingTerm.desc(row.pinned),
              (row) => OrderingTerm.desc(row.updatedAt),
            ]))
            .get();
    return [
      for (final row in rows)
        if (_fromRow(row).isValidAt(when)) _fromRow(row),
    ];
  }

  /// 全部记忆（含已改口/已闭合的历史），按更新时间倒序——历史与「当时」
  /// 查询的读取面；页面默认列表仍用 [watchActive]/[listActive]。
  Future<List<AiMemory>> history({int limit = kAiMemoryHardCap}) async {
    final rows =
        await (database.select(database.aiMemories)
              ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)])
              ..limit(limit))
            .get();
    return [for (final row in rows) _fromRow(row)];
  }

  /// 某条记忆取代过谁（历史）。
  Future<List<AiMemory>> supersededBy(String id) async {
    final rows =
        await (database.select(database.aiMemories)
              ..where((row) => row.supersededById.equals(id))
              ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
            .get();
    return [for (final row in rows) _fromRow(row)];
  }

  Future<bool> setImportance(String id, int importance) async {
    final value = importance.clamp(0, 100);
    final changed =
        await (database.update(
          database.aiMemories,
        )..where((row) => row.id.equals(id))).write(
          AiMemoriesCompanion(
            importance: Value(value),
            updatedAt: Value(clock.nowUtc()),
          ),
        );
    return changed > 0;
  }

  /// 记录一次「被注入/命中」。**节流**：同一条 10 分钟内只写一次
  /// （docs/41 §9：写放大只允许 ≥10 分钟或会话结束批量提交）。
  Future<void> markUsed(Iterable<String> ids) async {
    final now = clock.nowUtc();
    for (final id in ids.toSet()) {
      final row = await (database.select(
        database.aiMemories,
      )..where((r) => r.id.equals(id))).getSingleOrNull();
      if (row == null) continue;
      final last = row.lastUsedAt;
      if (last != null && now.difference(last) < const Duration(minutes: 10)) {
        continue;
      }
      await (database.update(
        database.aiMemories,
      )..where((r) => r.id.equals(id))).write(
        AiMemoriesCompanion(
          lastUsedAt: Value(now),
          useCount: Value(row.useCount + 1),
        ),
      );
    }
  }

  /// 实体链接（G19）。
  Future<void> linkEntity({
    required String id,
    required String entityType,
    required String entityId,
  }) async {
    await (database.update(
      database.aiMemories,
    )..where((row) => row.id.equals(id))).write(
      AiMemoriesCompanion(
        linkedEntityType: Value(entityType),
        linkedEntityId: Value(entityId),
        updatedAt: Value(clock.nowUtc()),
      ),
    );
  }

  /// 已到期但尚未归档的记忆——**只提议，不自动删**。
  Future<List<AiMemory>> expiredMemories() async {
    final now = clock.nowUtc();
    final rows =
        await (database.select(database.aiMemories)
              ..where(
                (row) =>
                    row.status.equals('active') &
                    row.expiresAt.isNotNull() &
                    row.expiresAt.isSmallerThanValue(now),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.expiresAt)]))
            .get();
    return [for (final row in rows) _fromRow(row)];
  }

  /// 分页搜索（G5）：归一化判据与 [findMatches] 同一套。
  Future<AiMemorySearchPage> searchPage({
    String query = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final normalized = normalizeAiMemoryText(query);
    final rows =
        await (database.select(database.aiMemories)
              ..where(
                (row) =>
                    row.status.equals('active') & row.supersededById.isNull(),
              )
              ..orderBy([
                (row) => OrderingTerm.desc(row.pinned),
                (row) => OrderingTerm.desc(row.updatedAt),
              ]))
            .get();
    final all = [
      for (final row in rows)
        if (normalized.isEmpty || _matches(_fromRow(row), normalized))
          _fromRow(row),
    ];
    final start = offset.clamp(0, all.length);
    final end = (start + limit).clamp(start, all.length);
    return AiMemorySearchPage(
      items: all.sublist(start, end),
      total: all.length,
    );
  }

  /// 导入时解析可选时间（ISO 8601）；坏值给行号，不静默吞。
  static DateTime? _parseIso(Object? raw, int index, String field) {
    if (raw == null) return null;
    if (raw is! String) {
      throw FormatException('第 ${index + 1} 条的 $field 不是字符串。');
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException('第 ${index + 1} 条的 $field 不是 ISO 时间。');
    }
    return parsed.toUtc();
  }

  /// 导出（G4/G22）：带版本与上限。
  Future<Map<String, Object?>> exportDocument() async {
    final all = await listActive(limit: kAiMemoryHardCap);
    return {
      'version': 1,
      'exportedAt': clock.nowUtc().toIso8601String(),
      'count': all.length,
      'memories': [
        for (final memory in all)
          {
            'text': memory.text,
            'kind': memory.kind.name,
            'domain': memory.domain.name,
            'tags': memory.tags,
            'pinned': memory.pinned,
            'importance': memory.importance,
            'source': memory.source,
            // 时间语义（S14）：导出的都是当前有效条目，`validFrom` 仍要带
            // （否则导入方会把「10 月才改的口」当成「一直如此」）。
            // 统一成 UTC：drift 读回的是本地时间，导出文件必须与设备时区无关。
            'validFrom': memory.validFrom?.toUtc().toIso8601String(),
          },
      ],
    };
  }

  /// 导入（G4/G22）：逐条校验（长度/标签/敏感红线/上限），任何一条不合规
  /// **整单拒绝**并给出行号——不做「跳过坏行」的静默吞。
  Future<int> importDocument(Map<String, Object?> document) async {
    final version = document['version'];
    if (version != 1) {
      throw const FormatException('记忆导入文件版本不支持（只支持 version=1）。');
    }
    final raw = document['memories'];
    if (raw is! List) {
      throw const FormatException('记忆导入文件缺少 memories 数组。');
    }
    if (raw.length > kAiMemoryHardCap) {
      throw const FormatException('一次最多导入 $kAiMemoryHardCap 条记忆。');
    }
    final existing = await listActive();
    if (existing.length + raw.length > kAiMemoryHardCap) {
      throw const FormatException('导入后会超过 $kAiMemoryHardCap 条上限，请先整理。');
    }
    // 2026-10-20 审查 RV-P1-17：**整单原子**。原来逐条 remember 立即落库，
    // 第 N 条不合规时前 N-1 条（含 embedding_index 向量行）已经提交，
    // 与「任何一条不合规整单拒绝」的承诺相反。
    return database.transaction(() async {
      var written = 0;
      for (var index = 0; index < raw.length; index++) {
        final entry = raw[index];
        if (entry is! Map) {
          throw FormatException('第 ${index + 1} 条不是对象。');
        }
        final text = entry['text'];
        if (text is! String || text.trim().isEmpty) {
          throw FormatException('第 ${index + 1} 条缺少 text。');
        }
        final tagsRaw = entry['tags'];
        final tags = <String>[
          if (tagsRaw is List)
            for (final tag in tagsRaw)
              if (tag is String) tag,
        ];
        final validFrom = _parseIso(entry['validFrom'], index, 'validFrom');
        final validTo = _parseIso(entry['validTo'], index, 'validTo');
        if (validFrom != null &&
            validTo != null &&
            !validFrom.isBefore(validTo)) {
          throw FormatException('第 ${index + 1} 条的 validFrom 必须早于 validTo。');
        }
        try {
          final imported = await remember(
            text: text,
            kind: AiMemoryKind.tryParse(entry['kind']) ?? AiMemoryKind.fact,
            domain:
                AiMemoryDomain.tryParse(entry['domain']) ??
                AiMemoryDomain.general,
            tags: tags,
            pinned: entry['pinned'] == true,
            source: 'import',
          );
          if (validFrom != null || validTo != null) {
            // 只回填时间窗：不去重写正文（remember 已经校验过）。
            await (database.update(
              database.aiMemories,
            )..where((row) => row.id.equals(imported.id))).write(
              AiMemoriesCompanion(
                validFrom: Value(validFrom ?? imported.validFrom),
                validTo: Value(validTo),
              ),
            );
          }
        } on AiMemoryException catch (error) {
          throw FormatException('第 ${index + 1} 条被拒：${error.message}');
        }
        written++;
      }
      return written;
    });
  }
}

/// 一页记忆（分页搜索用）。
final class AiMemorySearchPage {
  const AiMemorySearchPage({required this.items, required this.total});
  final List<AiMemory> items;
  final int total;
}
