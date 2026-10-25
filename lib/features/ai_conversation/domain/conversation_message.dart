import 'package:flutter/foundation.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';

/// 对话消息角色。
enum ConversationRole { user, assistant }

/// 对话消息状态。
enum ConversationMessageStatus { sending, sent, error }

/// 消息形态（docs/21 §5.7 六种消息形态 + docs/23 §5 编辑卡）。
///
/// 形态是**显式**的而不是从路径猜的：语音消息在转写后音频即被删除
/// （docs/08），只靠路径无法区分「语音」与「纯文本」。
enum ConversationMessageKind { text, image, voice, editProposal }

/// AI 对话消息（docs/21 §5.4 对话式识别扩展 / §5.7 六种消息形态）。
///
/// 轻量级不可变模型：id 保证列表去重，role 区分用户/助手，
/// text 是已渲染完成的文本，status 驱动 UI（发送中 / 错误）。
@immutable
final class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.status = ConversationMessageStatus.sent,
    this.kind = ConversationMessageKind.text,
    this.imagePath,
    this.durationMs,
    this.editTurn,
    this.wireText,
  });

  final String id;
  final ConversationRole role;
  final String text;
  final DateTime createdAt;
  final ConversationMessageStatus status;

  /// 消息形态（docs/21 §5.7）：文本 / 图片 / 语音 / 编辑卡（docs/23 §5）。
  final ConversationMessageKind kind;

  /// 图片消息的本机文件路径（聊天专用副本，随「清除全部本地数据」删除）。
  final String? imagePath;

  /// 语音消息的录音时长（毫秒）。音频转写后即删除，时长是唯一保留的元数据。
  final int? durationMs;

  /// **发给模型的正文**（`RV4-P2-03` / `docs/56` R14 / D5）。
  ///
  /// null = 与 [text] 相同（绝大多数消息）；非空时 [text] 是**只给用户看**的
  /// 版本（例如食堂「AI 分析」只显示菜名），而请求里带定位 id。
  ///
  /// 【为什么不落库】它是发送期的瞬态事实：重启后重试一条旧消息应当用当时
  /// 的 [text]（消息里没有 id 也不会凭空造）。**不进 schema**（本批不动 schema）。
  final String? wireText;

  /// 给模型看的正文：[wireText] 优先，否则 [text]。
  String get textForRequest => wireText ?? text;

  /// 编辑卡内容（docs/23 §5）：非 null 时 [text] 存的是给用户看的 reply，
  /// 逐条提议与结果在 [editTurn] 里；落库时由仓储整体编码进 textContent，
  /// 不需要新增 schema 列。仅助手消息会出现。
  final ChatEditTurn? editTurn;

  bool get isEditProposal =>
      kind == ConversationMessageKind.editProposal && editTurn != null;

  ConversationMessage copyWith({
    String? id,
    ConversationRole? role,
    String? text,
    DateTime? createdAt,
    ConversationMessageStatus? status,
    ConversationMessageKind? kind,
    String? imagePath,
    int? durationMs,
    ChatEditTurn? editTurn,
    String? wireText,
  }) {
    return ConversationMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      kind: kind ?? this.kind,
      imagePath: imagePath ?? this.imagePath,
      durationMs: durationMs ?? this.durationMs,
      editTurn: editTurn ?? this.editTurn,
      wireText: wireText ?? this.wireText,
    );
  }
}
