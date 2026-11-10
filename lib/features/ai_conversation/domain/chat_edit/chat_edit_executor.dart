import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_command.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_repair.dart';

/// 单条命令的执行结果；`message` 无论成败都要是能直接给用户看的人话。
final class ChatEditApplyResult {
  const ChatEditApplyResult.ok([
    this.message = '已完成',
    this.itemNotes = const {},
  ]) : ok = true,
       repair = null;

  const ChatEditApplyResult.failure(
    this.message, {
    this.repair,
    this.itemNotes = const {},
  }) : ok = false;

  final bool ok;
  final String message;

  /// 失败时的可点修复动作（可选）：目前只有「缺食材」一类——
  /// 2026-10-16 用户要求缺食材时给可点按钮，而不是只回一句人话。
  final ChatEditRepair? repair;

  /// [repair] 为「缺食材」时的名字（按钮文案与测试用）。
  String? get missingFoodName => repair?.name;

  /// **按食物**的结果说明（2026-11-07 用户：结果别堆在卡片末尾，要挂在
  /// 每样食物下面）。key = 食物名（与命令 `items[].food` 一致，卡片按
  /// 子条目标题对位）；value = 一句人话（「已记入今天的午餐」/
  /// 「今天已记过，没有重复算」）。只有记餐类命令会填；其它命令为空，
  /// 结果仍由卡片挂在自己那一行下面。
  final Map<String, String> itemNotes;
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
