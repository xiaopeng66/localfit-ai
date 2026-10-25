import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';

/// 单条命令的执行结果；`message` 无论成败都要是能直接给用户看的人话。
final class ChatEditApplyResult {
  const ChatEditApplyResult.ok([this.message = '已完成'])
    : ok = true,
      repair = null;

  const ChatEditApplyResult.failure(this.message, {this.repair}) : ok = false;

  final bool ok;
  final String message;

  /// 失败时的可点修复动作（可选）：目前只有「缺食材」一类——
  /// 2026-10-16 用户要求缺食材时给可点按钮，而不是只回一句人话。
  final ChatEditRepair? repair;

  /// [repair] 为「缺食材」时的名字（按钮文案与测试用）。
  String? get missingFoodName => repair?.name;
}

/// chat-edit 命令的落库出口（docs/23 §4）。
///
/// 实现方负责：目标解析（id/精确唯一名）、把仓储抛出的异常翻译成人话、
/// 以及「AI 提议的数值必须再过一遍仓储自己的校验」这条双层防线。
abstract interface class ChatEditExecutor {
  /// 按命令语义写库。**不负责**确认流——调用方必须保证只有用户点过
  /// 「应用」才进来（docs/23 硬规则 1）。
  Future<ChatEditApplyResult> apply(ChatEditCommand command);
}
