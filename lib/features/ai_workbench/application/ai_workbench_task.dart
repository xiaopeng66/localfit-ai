import 'package:flutter/widgets.dart';

/// AI 创作画廊的**任务展示模型**（docs/32 §4 T6c / §3 D6）。
///
/// 【本件在第五轮被收敛为纯展示】原先它还带执行字段
/// （`runTask` / `controller` / `onConfirm` / `onCancel` / `draftDetails` /
/// `draftEditor` / `onManualEntry`）——那套「卡内生成 → 卡内草案 → 卡内确认
/// 写入」的管线随 T6c 退役：生成改在 AI 对话里发生（D5），写库统一走
/// chat-edit 命令层（编辑卡的「全部应用」），安全断言已重钉到
/// `chat_edit_executor`。
///
/// 现在只保留画廊与「描述框」需要的事实：id / 标题 / 摘要 / 提示 / 披露。
@immutable
class AiWorkbenchTask {
  const AiWorkbenchTask({
    required this.id,
    required this.title,
    required this.inputSummary,
    this.disclosure,
    this.inputHint,
  });

  /// 稳定 id：视图用它作任务卡 Key 后缀（`ai-workbench-task-<id>`）。
  final String id;
  final String title;

  /// 卡面摘要（沿用各任务既有 `inputSummary` 文案）。
  final String inputSummary;

  /// 发送披露（docs/07 §4.2.x：将发送什么、绝不发送什么）。
  ///
  /// T6c 后画廊不再展示它（生成改在对话里、披露由对话侧承担）；
  /// 字段保留供启动提示词拼装参考与既有断言读取。
  final String? disclosure;

  /// 描述框占位文案（各任务既有 `inputHint`）。
  final String? inputHint;
}
