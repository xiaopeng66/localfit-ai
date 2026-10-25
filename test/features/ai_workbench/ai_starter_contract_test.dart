import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_workbench/application/ai_starter.dart';

/// `RV4-P1-08`（`docs/57` §3 / `docs/56` R12）：**AI 创作与现有功能对齐**。
///
/// 根因：「生成今日吃法」（`daily-menu-plan`）的启动提示词仍要求模型返回
/// `daily-menu-plan v1` JSON（`schema_version` / `slots` / `candidate_ids`），
/// 而该契约的解码器已在 `RV2-P2-01` **整族退役**——这条模板在要求模型输出
/// 一个 App 已经不能解析的形状。
///
/// 本文件钉两件事：
/// 1. 六张卡的提示词里**不得出现**已退役词；
/// 2. 每张卡的 id 都能在 `chat_edit_registry` 或纯文本能力里找到落点。
void main() {
  const retiredWords = [
    'schema_version',
    'v1 JSON',
    'candidate_ids',
    'selected_candidate_id',
    'reason_codes',
    'needs_confirmation',
  ];

  test('六张卡的启动提示词都不含已退役的契约词', () {
    for (final starter in aiStarters) {
      final prompt = starter.promptBuilder('示例输入');
      for (final word in retiredWords) {
        expect(
          prompt.contains(word),
          isFalse,
          reason: '`${starter.id}` 的提示词含已退役词「$word」：$prompt',
        );
      }
    }
  });

  test('每张卡的 id 都有落点（chat-edit 命令 或 纯文本能力）', () {
    final registry = ChatEditCommandRegistry();
    // 纯文本能力的显式白名单（不产生写操作、只要模型说清就行）。
    const plainTextCapable = {
      'daily-menu-plan', // 逐餐提议走 meal.create + reply 说明
      'dish-guidance', // 纯文本建议
      'meal-pairing', // 纯文本搭配建议
    };
    for (final starter in aiStarters) {
      final actions = _actionsFor(starter.id, registry);
      expect(
        actions.isNotEmpty || plainTextCapable.contains(starter.id),
        isTrue,
        reason: '`${starter.id}` 既没有 chat-edit 命令也没有登记为纯文本能力',
      );
    }
  });

  test('「生成今日吃法」明确要求用 meal.create 逐餐提议', () {
    final starter = aiStarters.firstWhere((s) => s.id == 'daily-menu-plan');
    final prompt = starter.promptBuilder('今天还剩午餐和晚餐');
    expect(
      prompt.contains('meal.create'),
      isTrue,
      reason: '提示词必须点名可应用的命令（R12：用 meal.create 逐餐提议）',
    );
    // 「不要输出 JSON」这句里含 JSON 二字，所以判据不是「不含 JSON」，
    // 而是「不含已退役的契约键」（由上面第一条统一覆盖）。
    expect(prompt.contains('不要输出 JSON'), isTrue);
  });
}

/// 粗略能力映射：按 starter id → 该卡实际会用到的命令 action。
Set<String> _actionsFor(String starterId, ChatEditCommandRegistry registry) {
  const mapping = {
    'menu-normalize': {'canteen.dish.create', 'canteen.dish.nutrition'},
    'dish-nutrition': {'canteen.dish.nutrition'},
    'workout-plan': {'workout.plan.create'},
    'daily-menu-plan': {'meal.create'},
  };
  final wanted = mapping[starterId] ?? const <String>{};
  final available = {for (final spec in registry.specs) spec.action};
  return {
    for (final action in wanted)
      if (available.contains(action)) action,
  };
}
