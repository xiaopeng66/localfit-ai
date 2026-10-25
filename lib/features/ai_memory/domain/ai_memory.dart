import 'dart:convert';

/// AI 长期记忆（docs/38 §4）。
///
/// 与结构化事实（`profiles` / `goals` / `daily_targets` /
/// `planning_constraints`）的分工：**能落到结构化字段的一律不写记忆**。
/// 记忆只收软信息——口味、作息、器械条件、常去的窗口、沟通偏好、近况。
/// 这条分工同时写在协议规则 11 与记忆页的说明里；违反它只会制造
/// 「同一事实两处不一致」这种最难查的缺陷。
enum AiMemoryKind {
  preference('偏好'),
  habit('习惯'),
  fact('事实'),
  context('近况');

  const AiMemoryKind(this.label);
  final String label;

  static AiMemoryKind? tryParse(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    for (final value in values) {
      if (text == value.name || text == value.label) return value;
    }
    return null;
  }
}

enum AiMemoryDomain {
  nutrition('饮食'),
  training('训练'),
  schedule('作息'),
  canteen('食堂'),
  general('其他');

  const AiMemoryDomain(this.label);
  final String label;

  static AiMemoryDomain? tryParse(Object? raw) {
    if (raw is! String) return null;
    final text = raw.trim();
    for (final value in values) {
      if (text == value.name || text == value.label) return value;
    }
    return null;
  }
}

/// 一条记忆（一行 `ai_memories`）。
final class AiMemory {
  const AiMemory({
    required this.id,
    required this.text,
    required this.kind,
    required this.domain,
    required this.tags,
    required this.pinned,
    required this.source,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.importance = 50,
    this.useCount = 0,
    this.lastUsedAt,
    this.supersededById,
    this.expiresAt,
    this.sourceMessageId,
    this.linkedEntityType,
    this.linkedEntityId,
    this.validFrom,
    this.validTo,
  });

  final String id;
  final String text;
  final AiMemoryKind kind;
  final AiMemoryDomain domain;
  final List<String> tags;
  final bool pinned;

  /// `explicit`（AI 对话的 `memory.remember`）/ `manual`（记忆页手写）/
  /// `extracted`（对话页「提炼记忆」候选被用户点选保存）。
  final String source;

  /// `active`；`archived` 预留给后续的老化/清理（v1 页面只做硬删）。
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── 时间语义（G23 / S14，schema 29）─────────────────────────────────
  /// 这条从何时成立；null 只在极旧库（迁移未回填）出现。
  final DateTime? validFrom;

  /// 到何时不再成立（改口时闭合）；null = 仍然有效。
  final DateTime? validTo;

  /// [when] 时刻这条是否成立（左闭右开：`validFrom <= when < validTo`）。
  ///
  /// `validFrom` 为空按「一直成立」处理（旧库兜底），与「不知道就不排除」
  /// 的既有口径一致。
  bool isValidAt(DateTime when) {
    final from = validFrom;
    if (from != null && when.isBefore(from)) return false;
    final to = validTo;
    if (to != null && !when.isBefore(to)) return false;
    return true;
  }

  bool get isClosed => validTo != null;

  /// 有效期文案（页面直接用；不给旧库/无值编日期）。
  String? get validityLabel {
    final from = validFrom;
    final to = validTo;
    if (from == null && to == null) return null;
    final start = from == null ? '—' : _ymd(from);
    if (to == null) return '$start 起';
    return '$start – ${_ymd(to)}（已改口）';
  }

  static String _ymd(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  // ── schema 28（docs/41 §5 / §11）──────────────────────────────────────
  /// 重要性 0–100（注入排序用；默认 50）。
  final int importance;

  /// 最近一次被注入/命中的时间与次数（**节流写**，见仓库）。
  final int useCount;
  final DateTime? lastUsedAt;

  /// 改口留痕：旧条指向新条（检索只看 active；页面可看历史、可撤销）。
  final String? supersededById;

  /// `kind=context` 的临时近况到期时间。
  final DateTime? expiresAt;

  /// 来源对话消息（来源追溯）。
  final String? sourceMessageId;

  /// 实体链接（G19）：`dish` | `food` | `venue`。
  final String? linkedEntityType;
  final String? linkedEntityId;

  bool get isActive => status == 'active';

  /// 已被新说法取代（检索不得返回）。
  bool get isSuperseded => supersededById != null && supersededById!.isNotEmpty;

  /// 已过期（到期只**提议**归档，不自动删——见 `expiredMemories()`）。
  bool get isExpired {
    final at = expiresAt;
    return at != null && at.isBefore(DateTime.now());
  }

  String get sourceLabel => switch (source) {
    'explicit' => '你说过',
    'manual' => '手动添加',
    'extracted' => '从对话提炼',
    _ => '导入',
  };

  /// 实体链接文案（页面展示/调试用）。
  String? get linkedEntityLabel => switch (linkedEntityType) {
    'dish' => '菜品',
    'food' => '食物',
    'venue' => '食堂',
    null => null,
    _ => linkedEntityType,
  };

  AiMemory copyWith({
    String? text,
    AiMemoryKind? kind,
    AiMemoryDomain? domain,
    List<String>? tags,
    bool? pinned,
    String? status,
    int? importance,
    int? useCount,
    DateTime? lastUsedAt,
    String? supersededById,
    DateTime? expiresAt,
    String? sourceMessageId,
    String? linkedEntityType,
    String? linkedEntityId,
    DateTime? updatedAt,
  }) => AiMemory(
    id: id,
    text: text ?? this.text,
    kind: kind ?? this.kind,
    domain: domain ?? this.domain,
    tags: tags ?? this.tags,
    pinned: pinned ?? this.pinned,
    source: source,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    importance: importance ?? this.importance,
    useCount: useCount ?? this.useCount,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    supersededById: supersededById ?? this.supersededById,
    expiresAt: expiresAt ?? this.expiresAt,
    sourceMessageId: sourceMessageId ?? this.sourceMessageId,
    linkedEntityType: linkedEntityType ?? this.linkedEntityType,
    linkedEntityId: linkedEntityId ?? this.linkedEntityId,
  );
}

/// 一条记忆的长度上限（一句话；超了拆几条，模型与页面同一口径）。
const int kAiMemoryMaxTextLength = 140;

/// 记忆容量（docs/41 §5 / docs/43 B5，2026-10-19 锁定）：
/// * 软顶：超过仍可写，但页面提示「建议整理」；
/// * 硬顶：达到后拒绝新增（文案指向整理入口）；
/// * 注入候选：每轮参与相关性打分的条数上限——**与总条数解耦**，
///   保证 2000 条时打分仍 <30ms（docs/43 B5 性能判据）。
const int kAiMemorySoftCap = 2000;
const int kAiMemoryHardCap = 5000;
const int kAiMemoryInjectionCandidates = 200;
const int kAiMemoryMaxTags = 6;
const int kAiMemoryMaxTagLength = 12;

/// 每次注入的**默认档**上限（docs/41 D4：标准 3k 字符 / 24 条；
/// 紧凑 1.5k/12、更多 6k/48 见 `MemoryBudget`）：条数 + 字符数双封顶。
///
/// 2026-10-18 由 12/1500 提到 24/3000——那是 v1 的保守值，D4 已裁决
/// 默认改为标准档（1500/12 仍是紧凑档，见 `MemoryBudget.compact`）。
const int kAiMemoryMaxInjected = 24;
const int kAiMemoryMaxInjectedChars = 3000;

/// 「对话时使用记忆」开关的 KV 键（`app_settings`）。缺键 = 开启。
const String kAiMemoryInjectionKey = 'ai_memory_injection_enabled';

bool parseAiMemoryInjectionEnabled(String? raw) {
  if (raw == null) return true;
  final value = raw.trim().toLowerCase();
  return value != 'false' && value != '0';
}

/// 去重/匹配用的归一化：去空白、去常见标点、小写。
String normalizeAiMemoryText(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\u3000]+'), '')
    .replaceAll(RegExp(r'''[，。！？、；：,.!?;:（）()「」“”"'`]'''), '');

/// 记忆写入被拒时抛的异常；`message` 是给人看的中文（直接上编辑卡/页面）。
final class AiMemoryException implements Exception {
  const AiMemoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 敏感信息红线（docs/38 §4.6，照 Claude 的「永不保存」清单）：
/// 证件号、银行卡号、移民/犯罪类不进记忆。返回命中的类别名，未命中返回 null。
///
/// 刻意从宽：宁可让用户改写一句，也不要把这类信息写进一个会被注入
/// system prompt 的存储里。
String? aiMemorySensitiveReason(String text) {
  if (RegExp(r'\d{17}[\dXx]').hasMatch(text)) return '身份证号';
  if (RegExp(r'\d{16,19}').hasMatch(text)) return '银行卡号';
  const keywords = ['身份证', '银行卡', '护照号', '移民', '犯罪记录', '银行账户'];
  for (final keyword in keywords) {
    if (text.contains(keyword)) return keyword;
  }
  return null;
}

/// 把标签列表编码进 `tags_json`（排序后再存，便于对账）。
String encodeAiMemoryTags(List<String> tags) => jsonEncode(([...tags]..sort()));

List<String> decodeAiMemoryTags(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  } on FormatException {
    // 坏值当作没有标签：读侧绝不因为一条脏数据把整页打死。
    return const [];
  }
}
