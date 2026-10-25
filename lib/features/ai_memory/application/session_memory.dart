/// 会话级临时记忆（docs/41 P4 G20 / 学 Eta pins 的分层思路）。
///
/// 只在**本次对话**生效、**不落库**（「我在出差，只有便利店」）。它比长期
/// 记忆更"当前"，所以在注入排序里排最前；会话结束就消失，不需要清理。
library;

import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';

/// 一条临时记忆（不落库，id 只在本进程内唯一）。
final class SessionMemory {
  const SessionMemory({
    required this.text,
    this.kind = AiMemoryKind.context,
    this.domain = AiMemoryDomain.general,
  });

  final String text;
  final AiMemoryKind kind;
  final AiMemoryDomain domain;
}

/// 会话级临时记忆的持有者（一个对话页一个实例）。
///
/// 纪律：
/// * **不持久化**：没有仓储、没有表、不进备份；
/// * **有界**：最多 [maxItems] 条、单条 ≤ [kAiMemoryMaxTextLength]；
/// * **显式**：只由用户在本会话里说过的「临时情况」写入（页面/命令层调用）。
final class SessionMemoryStore {
  SessionMemoryStore({this.maxItems = 8});

  final int maxItems;
  final List<SessionMemory> _items = [];

  List<SessionMemory> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;

  /// 添加一条；返回 false = 被拒（空白/超长/已满/重复）。
  bool add(SessionMemory memory) {
    final text = memory.text.trim();
    if (text.isEmpty || text.length > kAiMemoryMaxTextLength) return false;
    if (_items.length >= maxItems) return false;
    if (_items.any(
      (item) => normalizeAiMemoryText(item.text) == normalizeAiMemoryText(text),
    )) {
      return false;
    }
    _items.add(
      SessionMemory(text: text, kind: memory.kind, domain: memory.domain),
    );
    return true;
  }

  /// 会话结束/切走时清空。
  void clear() => _items.clear();

  /// 转成注入用的 [AiMemory] 视图（id 带 `session:` 前缀，**不可**回写库）。
  List<AiMemory> asMemories(DateTime now) => [
    for (var index = 0; index < _items.length; index++)
      AiMemory(
        id: 'session:$index',
        text: _items[index].text,
        kind: _items[index].kind,
        domain: _items[index].domain,
        tags: const [],
        pinned: true,
        source: 'session',
        status: 'active',
        createdAt: now,
        updatedAt: now,
      ),
  ];
}
