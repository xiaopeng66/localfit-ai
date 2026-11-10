import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// C-1（docs/64 阶段 2）：**AI↔UI 能力矩阵**——注册表（`chat_edit_registry.dart`）
/// 里的每一条命令，必须在这张表里声明为 `ui` / `aiOnly(理由)` / `both`。
///
/// 三个判据：
/// 1. 注册表里的每条 action 都被声明过（**新增命令不声明就红**）；
/// 2. 声明为 `ui` / `both` 的 action，其仓储写法**至少被一处 UI 侧源码调用**
///    （静态扫描 `lib/features/**`，排除 `ai_conversation` 本身——执行器是 AI 侧）；
/// 3. `aiOnly` 必须写明理由（理由为空 = 红）。
///
/// 扫描方式是**文本扫描**（不引依赖、不跑运行时）：注册表的动作字面量
/// `action: '<name>'` 是目前唯一写法（docs/64 附录 B 风险登记）——重构改了写法
/// 请同步改这里的正则并说明。
void main() {
  final registryFile = File(
    'lib/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart',
  );
  final registrySource = registryFile.readAsStringSync();
  final registered = RegExp(r"action: '([a-zA-Z.]+)'")
      .allMatches(registrySource)
      .map((match) => match.group(1)!)
      .toSet();

  // UI 侧源码 = features 下除 AI 对话（执行器/注册表）之外的全部 Dart。
  final uiSources = <File>[];
  for (final entity in Directory('lib/features').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll('\\', '/');
    if (path.contains('/ai_conversation/')) continue;
    uiSources.add(entity);
  }

  /// 每条 ui/both 能力的「UI 侧调用点」标记（`文件名:代码片段`）。
  /// 审计过程（2026-10-27，逐条 grep 核实）：
  /// - `plan.rename` / `canteen.venue.rename` / `canteen.venue.delete` 在
  ///   `lib/features`（除 ai_conversation）下 **0 调用点** ⇒ aiOnly；
  /// - `dish.updateManualNutrition` 的旧菜品库编辑 UI 已随推荐卡菜单退役，
  ///   生产入口为零 ⇒ 该写路径与能力声明一并删除。
  final declared = <String, Capability>{
    'meal.create': Capability.ui(['nutrition_actions.dart:meals.create']),
    'meal.update': Capability.ui(['nutrition_actions.dart:meals.update']),
    'meal.delete': Capability.ui(['nutrition_actions.dart:repository.delete']),
    // UI 的「编辑餐食」弹层是整餐重写（`meals.update`），条目的改克数 /
    // 移除都在同一弹层里完成（`_removeItem` / 克数输入）。
    'meal.item.update': Capability.ui([
      'meal_editor_dialog.dart:_removeItem',
      'nutrition_actions.dart:meals.update',
    ]),
    'meal.item.delete': Capability.ui(['meal_editor_dialog.dart:_removeItem']),
    'food.create': Capability.ui(['nutrition_actions.dart:createFood']),
    'food.update': Capability.ui([
      'food_library_item_actions.dart:controller.updateFood',
    ]),
    'food.delete': Capability.ui([
      'food_library_item_actions.dart:controller.deleteFood',
    ]),
    'water.add': Capability.ui(['dashboard_page.dart:repository.add']),
    // A-1（docs/64 阶段 1）：长按饮水卡 → 记录列表 → 删除 + 撤销（restore）。
    'water.delete': Capability.ui([
      'water_records_sheet.dart:repository.delete',
      'water_records_sheet.dart:repository.restore',
    ]),
    'weight.log': Capability.ui([
      'dashboard_page.dart:repository.saveManualWeight',
    ]),
    'session.start': Capability.ui([
      'training_page.dart:sessionRepository.start',
    ]),
    'set.log': Capability.ui(['training_page.dart:sessionRepository.logSet']),
    'session.finish': Capability.ui([
      'training_page.dart:sessionRepository.finish',
    ]),
    'workout.plan.create': Capability.ui([
      'workout_plan_manual_page.dart:workoutPlanRepository.create',
    ]),
    'workout.plan.delete': Capability.ui(['training_page.dart:removePlan']),
    'plan.rename': Capability.aiOnly(
      'UI 无重命名入口（计划详情只有删除与改条目）；改名是低频维护操作，'
      '先保持 AI-only，需要时在计划详情里补一行「重命名」即可。',
    ),
    'plan.entry.add': Capability.ui(['training_page.dart:addEntry']),
    'plan.entry.remove': Capability.ui(['training_page.dart:removeEntry']),
    'memory.remember': Capability.ui([
      'ai_memory_page.dart:repository.remember',
    ]),
    'memory.forget': Capability.ui(['ai_memory_page.dart:repository.delete']),
    // docs/67 §6.2/P2-U23：`dish.upsert` 退成**旧信封兼容**命令（按旧"每份"
    // 语义解码 → 经统一主库安全换算），新流程不再产生独立每份菜品写入；
    // UI 上的等价能力是「食物库新建/编辑」（food.create / food.update）。
    'dish.upsert': Capability.aiOnly(
      '旧「每份菜品」命令只用于兼容已持久化的旧卡片：新编译不再生成它，'
      '份量不可信时要求补全。UI 的等价入口是食物库新建/编辑（按每 100g）。',
    ),
    'dish.delete': Capability.aiOnly(
      '2026-10-31 用户要求推荐卡右下三点菜单及其功能退役，菜品库的 '
      'delete+restore 因此不再有直接 UI 入口；食堂目录仍可删除源菜，但那条 '
      '级联路径不提供撤销，不能冒充 DishLibrary 的删除+撤销能力。',
    ),
    // C-2（2026-10-27 落地）：设置页「饮食约束」弹层读写同一张表。
    'constraints.set': Capability.ui([
      'dietary_constraints_sheet.dart:repository.save',
      'dietary_constraints_sheet.dart:repository.load',
    ]),
    'canteen.venue.create': Capability.ui([
      'menu_form_prompts.dart:createVenue',
    ]),
    'canteen.venue.rename': Capability.aiOnly(
      '食堂目录管理 UI 只有建地点/建窗口/建菜/改菜/删菜/删窗口；'
      '地点改名与删除没有 UI 入口（地点通常不删，删除会连带窗口与菜）。',
    ),
    'canteen.venue.delete': Capability.aiOnly(
      '同上：地点删除是破坏性级联操作（窗口、菜一起没了），'
      'UI 刻意不提供，避免误触；AI 在用户明确要求时才执行。',
    ),
    'canteen.window.create': Capability.ui([
      'menu_form_prompts.dart:createWindow',
    ]),
    'canteen.window.delete': Capability.ui(['menu_tab_view.dart:deleteWindow']),
    'canteen.dish.create': Capability.ui(['menu_form_prompts.dart:createDish']),
    'canteen.dish.update': Capability.ui(['menu_form_prompts.dart:updateDish']),
    'canteen.dish.delete': Capability.ui(['menu_tab_view.dart:deleteDish']),
    // 食堂菜单本体（menu_items）的营养只由 AI 分析链路写；菜品库的旧手动
    // 编辑 UI 已无生产入口并删除，不再声称「UI 可改」。
    'canteen.dish.nutrition': Capability.aiOnly(
      '食堂菜单本体营养是 AI 分析与来源同步的产物，UI 不直接改它；'
      '旧菜品库手动营养编辑弹层已随推荐卡菜单退役删除。',
    ),
    'targets.update': Capability.ui([
      'profile_edit_page.dart:updateWaterTargetMl',
      'profile_edit_page.dart:updateDailyGoal',
    ]),
    'profile.body.update': Capability.ui([
      'profile_edit_page.dart:updateBodyProfile',
    ]),
    'profile.goal.update': Capability.ui(['profile_edit_page.dart:updateGoal']),
    // C-3（docs/64 §0.5 已定）：内部动作，不做成按钮。
    'menu.snapshot.publish': Capability.aiOnly(
      '内部动作：AI 起草菜单时把当天菜单快照发给模型（上下文发布），'
      '没有用户可以表达的意图，做成按钮没有用户价值。',
    ),
  };

  test('注册表里的每条 action 都在矩阵里声明过（新增命令不声明就红）', () {
    final undeclared = registered.where(
      (action) => !declared.containsKey(action),
    );
    expect(
      undeclared,
      isEmpty,
      reason:
          '注册表新增了命令但没在能力矩阵里声明：${undeclared.join('、')}——'
          '先在 `ai_ui_capability_matrix_test.dart` 的 `declared` 表里补一行'
          '（ui / both + 调用点标记，或 aiOnly + 理由），再实现它。',
    );
  });

  test('矩阵里没有注册表之外的幽灵声明（拼写错误即红）', () {
    final ghosts = declared.keys.where(
      (action) => !registered.contains(action),
    );
    expect(
      ghosts,
      isEmpty,
      reason: '能力矩阵声明了注册表里不存在的命令：${ghosts.join('、')}（多半是拼写）',
    );
  });

  test('声明为 ui/both 的 action：UI 侧源码里找得到调用点（静态扫描）', () {
    final broken = <String>[];
    for (final entry in declared.entries) {
      final capability = entry.value;
      if (capability.isAiOnly) continue;
      for (final marker in capability.markers) {
        final colon = marker.indexOf('.dart:');
        final fileName = marker.substring(0, colon + 5);
        final symbol = marker.substring(colon + 6);
        final hit = uiSources.any(
          (file) =>
              file.path.replaceAll('\\', '/').endsWith('/$fileName') &&
              file.readAsStringSync().contains(symbol),
        );
        if (!hit) broken.add('${entry.key} ← $marker');
      }
    }
    expect(
      broken,
      isEmpty,
      reason:
          '以下能力声称 UI 可达，但扫描不到调用点（「声称有、实际没有」）：'
          '${broken.join('；')}——把入口补上，或如实改成 aiOnly 并写理由。',
    );
  });

  test('声明为 ai-only 的 action 必须写明理由', () {
    final noReason = <String>[];
    for (final entry in declared.entries) {
      final capability = entry.value;
      if (!capability.isAiOnly) continue;
      if (capability.reason.trim().length < 8) noReason.add(entry.key);
    }
    expect(
      noReason,
      isEmpty,
      reason: '这些 aiOnly 声明没有说清为什么不做 UI：${noReason.join('、')}',
    );
  });
}

final class Capability {
  const Capability.ui(this.markers) : isAiOnly = false, reason = '';

  const Capability.aiOnly(this.reason) : isAiOnly = true, markers = const [];

  final bool isAiOnly;
  final String reason;
  final List<String> markers;
}
