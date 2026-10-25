/// 行级「修复建议」（App 侧兜底，2026-10-16）。
///
/// 执行失败时给出的**可点动作**：不写库，只把用户带到能补齐前提的界面。
/// 目前覆盖四类「库里没有这个实体」：
///
/// | 种类 | 触发 | 按钮 | 点开 |
/// |---|---|---|---|
/// | [ChatEditRepairKind.createFood] | `meal.create` 等引用库里没有的食材 | 创建食材「X」 | 预填名称的**新建食物**弹层 |
/// | [ChatEditRepairKind.createExercise] | 训练域按名字引用库里没有的动作 | 新建动作「X」 | 预填名称的**新建动作**弹层 |
/// | [ChatEditRepairKind.createVenue] | 食堂域按名字引用库里没有的地点 | 新建地点「X」 | 预填名称的**添加地点**弹层 |
/// | [ChatEditRepairKind.createWindow] | 食堂域按名字引用某地点下没有的窗口 | 新建窗口「X」 | 预填名称的**添加窗口**弹层（venueId 必带） |
///
/// 营养值/时间/分类这些仍由用户在表单里填，App 绝不替用户编数据。
///
/// （`dish` 没有这一档：菜品的写入命令 `dish.upsert` 本来就是「按名字新建或
/// 更新」，不存在「库里没有这道菜」的失败路径。）
enum ChatEditRepairKind {
  createFood,
  createExercise,
  createVenue,
  createWindow,
}

final class ChatEditRepair {
  const ChatEditRepair.createFood({required this.name})
    : kind = ChatEditRepairKind.createFood,
      venueId = null;

  const ChatEditRepair.createExercise({required this.name})
    : kind = ChatEditRepairKind.createExercise,
      venueId = null;

  const ChatEditRepair.createVenue({required this.name})
    : kind = ChatEditRepairKind.createVenue,
      venueId = null;

  /// 窗口归属的地点（修复必须落在同一个地点下，缺它就没法开对表单）。
  const ChatEditRepair.createWindow({required this.name, required this.venueId})
    : kind = ChatEditRepairKind.createWindow;

  final ChatEditRepairKind kind;

  /// 要新建的实体名（执行器从失败路径里带出来的原始引用）。
  final String name;

  /// 仅 [ChatEditRepairKind.createWindow] 用。
  final String? venueId;

  /// 按钮文案（卡片、读屏、测试共用同一处，避免两处漂）。
  String get label => switch (kind) {
    ChatEditRepairKind.createFood => '创建食材「$name」',
    ChatEditRepairKind.createExercise => '新建动作「$name」',
    ChatEditRepairKind.createVenue => '新建地点「$name」',
    ChatEditRepairKind.createWindow => '新建窗口「$name」',
  };
}
