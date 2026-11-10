import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';

/// **SFT 误差分析反哺协议（2026-11-06）。**
///
/// 本地 SFT 试点（`E:/AI/Zcode/projects/localfit-ai/sft/README.md`，1.5B/3B × v1–v3 数据）
/// 用 46+24+29 条离线用例反复量出了同一批**命令族混淆**：
///
/// - 「删掉昨天晚餐」（餐记录）/「删掉菜品库里的X」/「删掉食堂的X」/
///   「删掉一楼快餐」（窗口）/「删掉东区食堂」（地点）——小模型会跨库选命令
///   （`dish.delete`→`canteen.dish.delete`、`meal.delete`→`memory.forget`）；
/// - 「改成减脂，目标 65 公斤」（`profile.goal.update`）vs
///   「每天步数目标 10000」（`targets.update`）——goal/targets 互相顶替；
/// - 「把今天的菜单录进去」被当成逐条 `canteen.dish.create`；
/// - `dish.upsert` 在用户没说份量时凭空补 `servingGrams:250`。
///
/// 云端大模型没有这些训练信号，但**同样的混淆在提示词里没有一条显式对照**。
/// 把它们压成一条「按宾语选命令」的对照规则写进协议，让云端模型直接受益。
/// 预算约束：协议总长 ≤ 7500 字（见 `chat_edit_protocol_budget_test.dart`）。
void main() {
  final proto = ChatEditCommandRegistry().renderProtocol();

  group('协议含 SFT 误差反哺的易混命令对照', () {
    test('「删掉/忘掉」按宾语选命令的对照规则存在', () {
      expect(
        proto.contains('删掉/忘掉按宾语选命令'),
        isTrue,
        reason:
            'SFT 试点在 46+24+29 条用例上反复量出删除族跨库混淆'
            '（dish.delete→canteen.dish.delete、meal.delete→memory.forget）。'
            '协议里必须有一条显式的「按宾语选命令」对照，云端模型才能不靠猜。',
      );
    });

    test('「把菜单录进去」≠ 逐条建菜，写进协议', () {
      expect(
        proto.contains('→`menu.snapshot.publish`'),
        isTrue,
        reason:
            'SFT 评测里 menu.snapshot.publish 被当成逐条 canteen.dish.create；'
            '协议要把「录菜单」显式映射到快照发布命令。',
      );
    });

    test('servingGrams 只在用户明说份量时才填', () {
      expect(
        proto.contains('用户明说「一份X克」'),
        isTrue,
        reason:
            'SFT 评测中 dish.upsert 在用户没提份量时凭空补 servingGrams:250'
            '（v1 基线 2/2 触发）——这是把库默认值当用户事实，协议必须禁止。',
      );
    });
  });
}
