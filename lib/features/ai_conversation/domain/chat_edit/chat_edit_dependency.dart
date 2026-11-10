/// 「记一餐」对「新建食材」的依赖（需求 6d / 19，2026-10-25 用户原话：
/// 「我点击鸡蛋水煮的应用的时候，应该弹窗提示是否应用创建食材鸡蛋水煮，
/// 我选择确认后又可以继续应用该早餐添加」）。
///
/// 【为什么需要它】一张编辑卡里，「记一餐」与「新建食材」原本是两个**互相
/// 独立**的组（各有一个「应用本组」）。用户只点「记一餐」那组 ⇒ `food.create`
/// 没执行 ⇒ 写库时 `meal.create` 报「找不到食材「鸡蛋水煮」」——用户看到的是
/// 「点了应用却失败」，而他并不知道要先点上面/下面另一组。
///
/// 【两件事】本文件只管**判据**（谁依赖谁），分两份消费者：
/// * **执行层**（`ChatEditCoordinator`）：应用前预检、确认后先建再记；
/// * **呈现层**（`ChatEditCard`）：把被依赖的 `food.create` 并进那一餐、
///   在该行挂「新建」徽标（需求 19）。
///
/// 两边用**同一份**判据，不各写一套匹配规则（否则会出现「卡片说是一个板块、
/// 执行时又当成另一件事」的分叉）。
library;

import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';

/// 一条依赖：`meal.create` 用到的某个食材，本卡里有对应的 `food.create`。
final class ChatEditFoodDependency {
  const ChatEditFoodDependency({
    required this.foodName,
    required this.createRowIndex,
    required this.mealRowIndexes,
  });

  /// 食材名（模型给的 `items[].food` 原文，两侧都按它匹配）。
  final String foodName;

  /// 承载创建动作的行下标（信封下标）。
  final int createRowIndex;

  /// 用到这个食材的记餐行下标（可能不止一条）。
  final List<int> mealRowIndexes;
}

/// 本卡里 `food.create` 的 **名字 → 行下标**（名字取 `args['name']` 的 trim）。
///
/// 同名取**第一条**：模型给的重复创建本身就异常（执行器也会拒绝重复），
/// 这里不做二次判断，只保证「有一个能指认的创建行」。
Map<String, int> foodCreateRowIndexByName(ChatEditTurn turn) {
  final out = <String, int>{};
  for (final row in turn.rows) {
    final command = row.command;
    if (command == null || command.action != 'food.create') continue;
    final name = (command.args['name'] as String? ?? '').trim();
    if (name.isEmpty) continue;
    out.putIfAbsent(name, () => row.index);
  }
  return out;
}

/// 一条 `meal.create` 行里引用的食材名（按 `items` 顺序，保留重复但去连续重复）。
List<String> mealItemFoodNames(ChatEditTurnItem row) {
  final command = row.command;
  if (command == null || command.action != 'meal.create') return const [];
  final raw = command.args['items'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) ((item['food'] as String?) ?? '').trim(),
  ];
}

/// 该记餐行里「本卡会新建」的食材名（去重、按出现顺序）。
///
/// 判定只用名字：模型在 `items[].food` 里给的是**名字**（快照里没有的新食材
/// 不可能有 id），`food.create` 的 `name` 也是名字——两边同名即视为同一个。
List<String> newlyCreatedFoodsOf(
  ChatEditTurnItem row,
  Map<String, int> createRows,
) {
  final out = <String>[];
  for (final name in mealItemFoodNames(row)) {
    if (name.isEmpty || !createRows.containsKey(name)) continue;
    if (out.contains(name)) continue;
    out.add(name);
  }
  return out;
}

/// 汇总整卡的依赖清单（不查库、纯函数）：只回答「结构上谁依赖谁」。
///
/// [onlyIndexes] 非空 = 只看这些**记餐行**（「应用本组」时用户只选了一组）；
/// 创建行本身不在选择范围内也算——它是被依赖方，本来就该跟着走。
List<ChatEditFoodDependency> structuralDependenciesOf(
  ChatEditTurn turn, {
  Set<int>? onlyIndexes,
}) {
  final createRows = foodCreateRowIndexByName(turn);
  if (createRows.isEmpty) return const [];
  final byName = <String, List<int>>{};
  for (final row in turn.rows) {
    if (row.command?.action != 'meal.create') continue;
    if (onlyIndexes != null && !onlyIndexes.contains(row.index)) continue;
    for (final name in newlyCreatedFoodsOf(row, createRows)) {
      byName.putIfAbsent(name, () => []).add(row.index);
    }
  }
  return [
    for (final entry in byName.entries)
      ChatEditFoodDependency(
        foodName: entry.key,
        createRowIndex: createRows[entry.key]!,
        mealRowIndexes: entry.value,
      ),
  ];
}

/// 一条记餐行里，第 [itemIndex] 个食材是不是「本卡会新建」的（呈现层挂徽标用）。
bool isNewlyCreatedMealItem(
  ChatEditTurnItem row,
  int itemIndex,
  Map<String, int> createRows,
) {
  final names = mealItemFoodNames(row);
  if (itemIndex < 0 || itemIndex >= names.length) return false;
  return createRows.containsKey(names[itemIndex]);
}

/// 「这条 `food.create` 服务着本卡的某一餐吗」——需求 19 的分组判据。
///
/// true ⇒ 并进那一餐（不再单列「新建食材」板块）；false ⇒ 用户只是单纯
/// 「加一个叫麻辣烫的食材」，仍要独立板块（用户原话里点名不许把它吞掉）。
bool isFoodCreateUsedByMeal(ChatEditTurn turn, ChatEditTurnItem foodRow) {
  final command = foodRow.command;
  if (command == null || command.action != 'food.create') return false;
  final name = (command.args['name'] as String? ?? '').trim();
  if (name.isEmpty) return false;
  for (final row in turn.rows) {
    if (row.command?.action != 'meal.create') continue;
    if (mealItemFoodNames(row).contains(name)) return true;
  }
  return false;
}
