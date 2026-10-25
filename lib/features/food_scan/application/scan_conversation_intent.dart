/// 拍照页对话意图（docs/21 §5.4「对话能力」1–3）。
///
/// 这是一个**纯函数分类器**：不碰数据库、不发网络、不依赖 Flutter。
/// 它的产出是「用户想干什么 + 解析出的参数」，执行由页面负责——
/// 这样意图判别可以被穷举测试，而不会被设备/网络状态污染。
///
/// 设计取舍：只在能**确定**解析出参数时才认意图。宁可回一句「没听懂，
/// 你可以…」，也不要在解析不出体重数值时猜一个数写进库——写库是不可逆的。
///
/// 2026-10-04（docs/28 §6.4）：原先还有第三种意图「创建食谱计划」
///（`CreateRecipePlanIntent` + `_mentionsRecipe` + `_parseSlot`）。食谱计划
/// 生成器随「食谱 / 计划」整族下线，说「今天帮我制定早餐食谱」这类句子现在
/// 落到 [UnknownScanIntent]（页面回引导文案），不再假装能打开一张不存在的界面。
sealed class ScanConversationIntent {
  const ScanConversationIntent();
}

/// 「记录今天体重 72.5kg」（docs/01 §5 能力 1）。
final class LogWeightIntent extends ScanConversationIntent {
  const LogWeightIntent({required this.weightKg, this.localDate});

  final double weightKg;

  /// 用户显式说的日期；null＝今天。解析不出可信日期时为 null，不猜。
  final String? localDate;
}

/// 「帮我制定今天的训练计划」（docs/01 §5 能力 2）。
final class CreateWorkoutPlanIntent extends ScanConversationIntent {
  const CreateWorkoutPlanIntent();
}

/// 认不出意图——页面回一句引导，不写任何事实。
final class UnknownScanIntent extends ScanConversationIntent {
  const UnknownScanIntent();
}

/// 把一句自然语言映射成意图。
///
/// 顺序有讲究：**先试体重**，因为「记录体重」里也可能出现「今天」，
/// 若先匹配训练的关键词，「今天」这类通用词会把它误判成建计划。
ScanConversationIntent classifyScanIntent(String rawInput) {
  final input = rawInput.trim();
  if (input.isEmpty) return const UnknownScanIntent();

  final weight = _tryParseWeight(input);
  if (weight != null) return weight;

  if (_mentionsPlan(input) && _mentionsWorkout(input)) {
    return const CreateWorkoutPlanIntent();
  }
  return const UnknownScanIntent();
}

/// 体重解析：要求「数字 + kg/公斤/千克」同时出现，且落在合法区间。
///
/// 数字必须**紧贴单位**（允许中间一个空格）。宽松地取「第一个数字」会
/// 在「记录 2026-09-01 体重 72kg」这类句子里抓到日期里的 2026，静默写错
/// 一条体重事实——这是不可逆的，所以宁可解析不出也不猜。
///
/// 35–300 kg 与 `MeasurementRepository.saveManualWeight` 的值域一致：
/// 在这里先挡一次是为了给出对话回复，而不是让仓储抛异常（页面不该用
/// 异常做控制流）。
LogWeightIntent? _tryParseWeight(String input) {
  // 单位前允许一个空格；句点兼容全角。
  final match = RegExp(r'(\d{1,3}(?:[.．]\d+)?)\s*(?:kg|KG|Kg|公斤|千克)')
      .firstMatch(input);
  if (match == null) return null;

  final raw = match.group(1)!.replaceAll('．', '.');
  final value = double.tryParse(raw);
  if (value == null || !value.isFinite) return null;
  if (value < 35 || value > 300) return null;

  return LogWeightIntent(weightKg: value, localDate: _parseDate(input));
}

bool _mentionsWorkout(String input) =>
    input.contains('训练') || input.contains('健身') || input.contains('锻炼');

bool _mentionsPlan(String input) =>
    input.contains('制定') ||
    input.contains('生成') ||
    input.contains('创建') ||
    input.contains('安排') ||
    input.contains('帮我') ||
    input.contains('计划');

/// 只认显式 `YYYY-MM-DD`。说不清就返回 null＝按今天，而不是猜一个偏移量。
String? _parseDate(String input) {
  final explicit = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(input);
  if (explicit != null) return explicit.group(1);
  return null;
}
