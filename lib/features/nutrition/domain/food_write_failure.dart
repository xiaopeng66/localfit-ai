/// 「这条食物不能这么改」的固定说法（docs/28 §5.3 D1）。
///
/// 编辑/删除只对**自建**条目开放（内置库没有入口，见 D1）。
/// 这些拒绝都要有一句用户能看懂、且**可以直接照着改**的话——用同一件异常承载，
/// 界面（弹层）把它原样显示在行动行上方，不再另写一份文案（N7 的机制）。
final class FoodWriteFailure implements Exception {
  const FoodWriteFailure(this.message);

  /// 面向用户的完整句子（自足：用户只看到这一句也知道下一步做什么）。
  final String message;

  @override
  String toString() => 'FoodWriteFailure: $message';
}
