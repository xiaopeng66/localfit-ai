/// 上一张**还没点「应用」**的编辑卡（2026-10-24 多轮实测）。
///
/// 【为什么需要它】用户说「我中午吃了米饭和鸡胸肉」→ 模型给出一张待应用
/// 卡片 → 用户接着说「米饭改成 100 克」。此时数据库里**还没有**那条午餐
/// （用户没点应用），模型在快照里只看得到「今天没有记录」，于是回：
///
/// > 还没生成这条午餐记录，所以暂时改不了克数。**等你应用上一步的午餐
/// > 记录后**，我再把米饭改成 100 克。
///
/// 这句话本身没错，但用户被要求「先点一次应用、再说一遍」——两轮做一件事，
/// 而用户明明只是想把克数改掉。根因是模型不知道「屏幕上还挂着一张卡」。
///
/// 把待应用提议原样告诉模型，它就能直接给出**一份合并后的新提议**（把
/// 150g 改成 100g 再整体提一次），而不是把用户打发回去点按钮。
final class PendingProposal {
  const PendingProposal({required this.summary, required this.commands});

  /// 那张卡片的 reply（给用户看的那句话），给模型当上下文。
  final String summary;

  /// 信封里的命令原样（action + 已校验的参数）。空列表 = 没有可执行提议。
  final List<({String action, Map<String, Object?> args})> commands;

  bool get isEmpty => commands.isEmpty;
}

/// 可编辑快照构建器（docs/23 §3）。
///
/// 产物是一段纯文本，作为 system 上下文随对话发出（披露见 docs/08）。
/// 失败语义：实现方应尽力出完整快照；个别段失败要如实标注而不是让整次
/// 发送失败——快照是辅助信息，不值得为它挡住一次对话。
abstract interface class ChatEditContextBuilder {
  /// [userMessage] 是**本次要发送的用户消息**（可空 = 既有调用点行为不变）。
  /// 非空时实现方可以做消息相关的预检索（docs/40 §2.4 的食物库 top3 注入、
  /// docs/41 §5 的 query-aware 记忆），并把结果作为独立段拼进快照。
  ///
  /// [pendingProposal] 非空时把「还没点应用的上一张卡」渲染成独立段。
  Future<String> build({String? userMessage, PendingProposal? pendingProposal});
}
