import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_context_builder.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_executor.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_proposal_audit.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';

/// 把「快照构建、协议注入、信封解码、落库执行」粘在一起的对象；
/// ConversationController 只认它，不直接碰任何仓储（docs/23 §0）。
///
/// null 安全：未接线（`chatEdit == null`）时对话退回纯聊天，所有编辑路径
/// 都不激活——与对话服务未配置时的降级同一套哲学。
final class ChatEditCoordinator {
  ChatEditCoordinator({
    required this.contextBuilder,
    required this.executor,
    ChatEditCommandRegistry? registry,
    AppClock? clock,
    this.auditor,
  }) : registry = registry ?? ChatEditCommandRegistry();

  final ChatEditContextBuilder contextBuilder;
  final ChatEditExecutor executor;
  final ChatEditCommandRegistry registry;

  /// 提案审查器（2026-10-24）。null = 未接线，卡片不显示审查警告
  /// （行为与改动前完全一致）。
  final ChatEditAuditor? auditor;

  /// 每次发送前调用：协议段 + 快照段。[userMessage] 是本次要发送的用户
  /// 消息（可空 = 既有调用点行为不变），快照构建器用它做消息相关的预检索
  /// （docs/40 §2.4 食物库 top3）。构建失败返回 null（本次不带快照，
  /// 对话照常），绝不让快照问题挡住一次对话（docs/23 §3）。
  ///
  /// [pendingProposal] 非空时把「上一张还没点应用的卡」告诉模型——否则
  /// 用户对着那张卡说「米饭改成 100 克」时，模型只看得见数据库（还没有那条
  /// 记录），会回答「等你先应用后我再改」，把两轮才能做完的事拖成四轮。
  Future<String?> buildSystemContext({
    String? userMessage,
    PendingProposal? pendingProposal,
  }) async {
    try {
      final snapshot = await contextBuilder.build(
        userMessage: userMessage,
        pendingProposal: pendingProposal,
      );
      return '${registry.renderProtocol()}\n\n$snapshot';
    } on Object {
      return null;
    }
  }

  /// 解析助手输出；非信封返回 null（调用方按纯文本渲染）。
  ChatEditTurn? decode(String rawOutput) =>
      parseChatEditTurn(rawOutput, registry);

  /// 应用**一条**推荐按钮的命令（2026-10-16 的 `suggestions` 通道）：
  /// 与编辑卡走同一个执行器、同一套失败翻译——点按钮本身就是用户的确认。
  Future<ChatEditApplyResult> applyOne(ChatEditCommand command) =>
      executor.apply(command);

  /// 逐条执行提议（按序；单条失败不连坐）。处理「可执行」的行：
  /// `command != null` 且状态为 proposed / applying（控制器先把要执行的
  /// 行标成 applying 以挡双击，这里两种都认）；解码失败的行已是 failed，
  /// 直接跳过。
  ///
  /// [onlyIndexes] 非空 = 只执行这些行（编辑卡按类分组的「应用本组」）；
  /// 未选中的行原样保留（proposed 仍是 proposed，之后还能单独应用）。
  Future<ChatEditTurn> applyProposed(
    ChatEditTurn turn, {
    Set<int>? onlyIndexes,
  }) async {
    final rows = <ChatEditTurnItem>[];
    for (final row in turn.rows) {
      final command = row.command;
      final selected = onlyIndexes == null || onlyIndexes.contains(row.index);
      final runnable =
          row.status == ChatEditRowStatus.proposed ||
          row.status == ChatEditRowStatus.applying;
      if (!runnable || command == null || !selected) {
        rows.add(row);
        continue;
      }
      final result = await executor.apply(command);
      rows.add(
        row.copyWith(
          status: result.ok
              ? ChatEditRowStatus.applied
              : ChatEditRowStatus.failed,
          resultMessage: result.message,
          // 失败带可点修复动作（缺食材 → 「创建食材 X」）时如实挂到那一行。
          repair: result.repair,
        ),
      );
    }
    return ChatEditTurn(
      reply: turn.reply,
      rows: rows,
      // 推荐按钮不是「行」，与执行过程无关——重建轮次时必须原样带走
      // （丢在这里＝用户点完「全部应用」按钮就消失）。
      suggestions: turn.suggestions,
    );
  }
}
