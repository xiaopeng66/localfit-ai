import 'package:flutter/material.dart';

/// 画廊分组（docs/32 §3 D5 六卡映射）。
enum AiStarterGroup {
  diet('饮食'),
  training('训练与搭配');

  const AiStarterGroup(this.label);

  final String label;
}

/// 一张「AI 创作」启动卡（docs/32 §4 T6a / §3 D5）。
///
/// 六张卡的 `title` / `description` / `inputHint` **逐字沿用**各既有
/// `*WorkbenchTask` 的 `title` / `inputSummary` / `inputHint`（不新造文案；
/// 其中 menu/pairing 两条已被既有测试断言）；[promptBuilder] 是 D5 表格里
/// 的启动提示词方向——用户输入会拼进这句话，随消息一起发给对话。
@immutable
class AiStarter {
  const AiStarter({
    required this.id,
    required this.group,
    required this.title,
    required this.description,
    required this.icon,
    required this.inputHint,
    required this.promptBuilder,
  });

  /// 与既有 `AiWorkbenchTask.id` 同名（Key `ai-workbench-task-<id>` 沿用）。
  final String id;
  final AiStarterGroup group;
  final String title;
  final String description;
  final IconData icon;

  /// 描述框的占位文案（沿用各任务既有 `inputHint`）。
  final String inputHint;

  /// 把用户输入拼成发给对话的启动提示词（docs/32 §3 D5 的「启动提示词方向」）。
  final String Function(String userInput) promptBuilder;
}

/// 六张启动卡的唯一定义处（docs/32 §3 D5）。
///
/// 顺序 = 画廊显示顺序（饮食 4 张在前、训练与搭配 2 张在后），
/// 与 D5 表格逐行对应。
const List<AiStarter> aiStarters = [
  AiStarter(
    id: 'menu-normalize',
    group: AiStarterGroup.diet,
    title: '解析学校菜单',
    description: '把粘贴的菜单文本整理成待确认草案；确认后才发布为菜单快照。',
    icon: Icons.receipt_long_outlined,
    inputHint: '粘贴菜单文本（食堂/窗口、菜名）',
    promptBuilder: _menuNormalizePrompt,
  ),
  AiStarter(
    id: 'dish-nutrition',
    group: AiStarterGroup.diet,
    title: '分析菜品营养',
    description: '输入菜品名与配料提示，估算每 100g 营养与证据等级',
    icon: Icons.auto_awesome_outlined,
    inputHint: '每行一道菜，例：\n番茄炒蛋\n宫保鸡丁 花生米少许',
    promptBuilder: _dishNutritionPrompt,
  ),
  AiStarter(
    id: 'daily-menu-plan',
    group: AiStarterGroup.diet,
    title: '生成今日吃法',
    // 【2026-10-25 文案修复】原文写「确认只加入计划」——「加入计划」随
    // `daily_plan` 整族退役（docs/58 D1）已经不存在，这句是在给用户承诺一个
    // 没有的功能。现在改成如实描述：产出的是一份**可应用的编辑卡**，
    // 点了才记进当天餐记录，不点就什么都不写。
    description:
        '用本地菜单候选和目标先算一遍，再让 AI 只在这些候选里选；'
        '结果是一张可应用的卡片——点「应用」才记进当天餐记录。',
    icon: Icons.today_outlined,
    inputHint: '想吃什么或忌口（可留空；留空则只看本地目标）',
    promptBuilder: _dailyMenuPlanPrompt,
  ),
  AiStarter(
    id: 'dish-guidance',
    group: AiStarterGroup.diet,
    title: '这道菜怎么吃',
    description: '只解释怎么吃：份量、搭配与可替换方向；营养由本地目录计算，AI 不提供营养数字，也不写入任何记录。',
    icon: Icons.restaurant_outlined,
    inputHint: '菜名（可加说明，如「食堂的番茄炒蛋，少油」）',
    promptBuilder: _dishGuidancePrompt,
  ),
  AiStarter(
    id: 'workout-plan',
    group: AiStarterGroup.training,
    title: '训练计划',
    description: '只从本地动作库组织训练计划；确认后创建为训练计划，不会自动开始会话。',
    icon: Icons.fitness_center,
    inputHint: '例如：一周 4 练，增肌，家里只有哑铃',
    promptBuilder: _workoutPlanPrompt,
  ),
  AiStarter(
    id: 'meal-pairing',
    group: AiStarterGroup.training,
    title: '常吃搭配',
    description: '你点名的本地食材 → AI 只在这些食材里组织搭配 → 本地重算营养（只读建议）。不上传餐食历史。',
    icon: Icons.sync_alt,
    inputHint: '想搭配的本地食材，用顿号分隔，如：鸡胸肉、米饭、西兰花',
    promptBuilder: _mealPairingPrompt,
  ),
];

// 提示词模板（docs/32 §3 D5 表格的「启动提示词方向」逐条落地）。
// 顶层函数而非闭包：`const` 列表要求这些构造器是常量引用。

String _menuNormalizePrompt(String input) =>
    '把下面这份菜单整理进本地菜单库（先建地点和窗口，再逐条加菜品）：\n\n$input';

String _dishNutritionPrompt(String input) => '估算这道菜每份的营养并收录：\n\n$input';

/// 「生成今日吃法」的启动提示词（`RV4-P1-08` / `docs/56` R12）。
///
/// **旧实现要求模型返回 `daily-menu-plan v1` JSON**（`schema_version` /
/// `slots` / `candidate_ids`）——那份契约的解码器已在 `RV2-P2-01` 整族退役，
/// 模型就算照做 App 也解析不了。
///
/// 现在改成 **chat-edit 口径**：说明要用 `meal.create` 逐餐提议、在 reply 里
/// 说清每餐选了什么为什么；写库仍走「编辑卡逐条确认」（不新增写路径）。
String _dailyMenuPlanPrompt(String input) =>
    '按我的目标和今天已吃的，帮我搭配今天剩下几餐。'
    '用可应用的修改（meal.create）逐餐提议，reply 里说清每餐选了什么、为什么；'
    '不要输出 JSON。\n\n$input';

String _dishGuidancePrompt(String input) => '这道菜怎么吃、怎么搭配：\n\n$input';

String _workoutPlanPrompt(String input) => '按我描述的目标生成训练计划并保存：\n\n$input';

String _mealPairingPrompt(String input) => '在这些本地食材里给我搭配：\n\n$input';
