import 'package:flutter/foundation.dart';

import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 「打开餐食编辑」的一次性意向（Round7 阶段 2 决策 D9）。
///
/// 今日页的「记录饮食」「记录晚餐」和记录页槽位卡头的「+」都不在饮食页里，
/// 而弹层归饮食页的 [NutritionActions] 管。既有做法有两种：`menuTabRequest`
/// 那种**计数递增**（切 tab，重复消费无害），和 `aiStarterRequest` 那种
/// **pending 消费一次**。这里必须是后者——计数式的「再次打开编辑弹层」在用户
/// 下次自己点进饮食页时会突然弹出一个空编辑框。
///
/// 因此本件保存**至多一个待处理请求**，页面取走（[take]）即清空：
/// 消费、置空、再由页面打开 [MealEditorDialog]（带可选槽位）。
final class MealAddRequest {
  const MealAddRequest({this.slot});

  /// 预选槽位。null = 弹层用既有默认（午餐）。
  final MealSlot? slot;
}

/// 路由层持有的意向通道；页面侧只依赖 [ValueListenable] 接口。
final class MealAddIntent extends ValueNotifier<MealAddRequest?> {
  MealAddIntent() : super(null);

  /// 请求打开餐食编辑（可由任意页发起；发起方负责随后导航到饮食页）。
  void request({MealSlot? slot}) => value = MealAddRequest(slot: slot);

  /// 取走并清空待处理请求；没有请求时返回 null。
  MealAddRequest? take() {
    final pending = value;
    if (pending != null) value = null;
    return pending;
  }
}
