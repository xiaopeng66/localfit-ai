import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';

/// 记忆 → 约束的晋升（docs/41 §5 G1 / 互链矩阵「G1 晋升」）。
///
/// 需求：一条记忆（如「不吃香菜」）值得成为**硬约束**时，用户应该能在
/// 记忆页一键把它晋升为忌口（`constraints.set` 的写路径），而不是自己
/// 再去对话里说一遍。纪律：
///
/// * **晋升是结构化写入，不是复制文本**：走 [PlanningConstraints] 的
///   忌口自由字符串（与 `constraints.set` 2026-10-16 放宽后的口径一致，
///   任意非空食材名都可落库）。
/// * **重复晋升幂等**：归一化后已在忌口清单里的词不重复添加；
/// * **上限如实**：忌口清单满（[PlanningConstraints.maxAllergenAvoidances]）
///   时拒绝并说明，不静默挤掉旧项；
/// * **删记忆不删约束**：晋升是单向复制，原记忆是否保留由用户决定
///   （晋升成功后弹层会问「顺便删掉这条记忆？」——不自动删）。
enum MemoryPromotionResult {
  added('已转为忌口/偏好'),
  alreadyPresent('这条已经在忌口清单里了'),
  full('忌口清单已满（9 项），请先在「我的 → 饮食约束」里整理。');

  const MemoryPromotionResult(this.message);
  final String message;
}

/// 从一条记忆文本提取晋升用的关键词。
///
/// 记忆是自由文本（「不吃香菜」「对芒果过敏」「偏好清淡」）；硬约束需要
/// 的是**食材/特质词**。策略刻意保守：
/// * 剥掉常见前缀（不吃/不吃X/对X过敏/讨厌/别给我X/忌口X…）；
/// * 剩余部分整体作为忌口词（用户自己看得懂的那截）；
/// * 剥完为空 ⇒ 不给晋升（拿整句话当忌口词会污染匹配）。
String? memoryPromotionKeyword(String text) {
  var value = text.trim();
  var stripped = false;
  final patterns = [
    RegExp(r'^不(?:要|吃|想|碰)(.{1,20})$'),
    RegExp(r'^别?(?:给我|再来|吃)(.{1,20})$'),
    RegExp(r'^对(.{1,20})过敏$'),
    RegExp(r'^(.{1,20})过敏$'),
    RegExp(r'^(?:忌口|讨厌|厌恶|避开|戒)(.{1,20})$'),
    RegExp(r'^(.{1,20})(?:过敏|不耐受|吃了不舒服)$'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(value);
    if (match != null) {
      final head = match.group(1)!.trim();
      if (head.isNotEmpty) {
        value = head;
        stripped = true;
        break;
      }
    }
  }
  value = value.replaceAll(RegExp(r'[，。！？、；：,.!?;:（）()「」" ]+$'), '').trim();
  // 没有任何前缀被剥掉 ⇒ 这句话没有可提取的忌口词（整句塞进忌口清单
  // 会污染匹配），如实拒绝。
  if (!stripped) return null;
  if (value.isEmpty || value.length > 12) return null;
  return value;
}

/// 把一条记忆晋升为忌口词；返回结果与（可能的）错误文案。
///
/// [current] 是晋升前的忌口清单；[persist] 负责真正落库（页面给
/// `PlanningConstraintsRepository.save` 的闭包，本类不碰仓储——
/// 单一职责，测试也免去建库）。
Future<MemoryPromotionResult> promoteMemoryToConstraint({
  required AiMemory memory,
  required List<String> current,
  required Future<void> Function(List<String> next) persist,
}) async {
  final keyword = memoryPromotionKeyword(memory.text);
  if (keyword == null) {
    throw const FormatException(
      '这条记忆没有可提取的忌口词（如「不吃香菜」的「香菜」），'
      '请改写记忆或到「我的 → 饮食约束」手动添加。',
    );
  }
  final normalized = normalizeAiMemoryText(keyword);
  final exists = current.any(
    (item) => normalizeAiMemoryText(item) == normalized,
  );
  if (exists) return MemoryPromotionResult.alreadyPresent;
  if (current.length >= PlanningConstraints.maxAllergenAvoidances) {
    return MemoryPromotionResult.full;
  }
  await persist([...current, keyword]);
  return MemoryPromotionResult.added;
}
