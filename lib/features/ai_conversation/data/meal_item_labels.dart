import 'package:localfit_ai/data/database/app_database.dart';

/// 把 `items[].food` 里的**机器引用**解析成人话标签（docs/67 §6.4）。
///
/// 为什么需要这一层：协议规则要求模型把快照里的 `[food:id]` /
/// `[canteen-dish:id]` / `[dish:id]` **连同方括号逐字抄**（否则同名歧义会被
/// 拒），但卡片的每一行不能直接显示这串 id——用户会看到
/// 「[food:01a16de4-bcde-…] 100 g」这种既读不懂、也没法核对的标题
/// （2026-11-10 真机反馈）。
///
/// 所以：**引用照抄、显示另算**。解析结果挂在 `ChatEditTurnItem.itemLabels`
/// 上（只在内存/展示层用，不写进 raw 信封），卡片、接地报错与摘要都读它。
final class MealItemLabels {
  const MealItemLabels._();

  static final RegExp _prefixed = RegExp(
    r'^\[(food|dish|canteen-dish):([^\]]+)\]$',
  );

  /// `items[].food` → 展示名。解析不到的引用不出现在返回值里（调用方回退
  /// 到原字符串，至少不会显示成空）。
  static Future<Map<String, String>> resolve(
    AppDatabase database,
    List<Object?> items,
  ) async {
    final foodIds = <String>{};
    final supplyIds = <String>{};
    final dishIds = <String>{};
    final refsByKind = <String, Map<String, String>>{};
    for (final item in items) {
      if (item is! Map) continue;
      final raw = item['food'];
      if (raw is! String) continue;
      final match = _prefixed.firstMatch(raw.trim());
      if (match == null) continue;
      final kind = match.group(1)!;
      final id = match.group(2)!.trim();
      if (id.isEmpty) continue;
      refsByKind.putIfAbsent(kind, () => {})[id] = raw.trim();
      switch (kind) {
        case 'food':
          foodIds.add(id);
        case 'canteen-dish':
          supplyIds.add(id);
        case 'dish':
          dishIds.add(id);
      }
    }
    if (refsByKind.isEmpty) return const {};

    final labels = <String, String>{};

    if (foodIds.isNotEmpty) {
      final rows = await (database.select(
        database.foods,
      )..where((row) => row.id.isIn(foodIds))).get();
      for (final row in rows) {
        final brand = row.brand?.trim() ?? '';
        labels['[food:${row.id}]'] = brand.isEmpty
            ? row.name
            : '${row.name}（$brand）';
      }
    }
    if (supplyIds.isNotEmpty) {
      final rows = await (database.select(
        database.menuItems,
      )..where((row) => row.id.isIn(supplyIds))).get();
      for (final row in rows) {
        labels['[canteen-dish:${row.id}]'] = row.displayName;
      }
    }
    if (dishIds.isNotEmpty) {
      final rows = await (database.select(
        database.dishLibrary,
      )..where((row) => row.id.isIn(dishIds))).get();
      for (final row in rows) {
        labels['[dish:${row.id}]'] = row.name;
      }
    }

    // 只保留**本次信封实际用到的原文写法**（大小写/空白可能不同）。
    final out = <String, String>{};
    for (final entry in refsByKind.entries) {
      for (final MapEntry(key: id, value: raw) in entry.value.entries) {
        final label = labels['[${entry.key}:$id]'];
        if (label != null && label.trim().isNotEmpty) out[raw] = label.trim();
      }
    }
    return out;
  }
}
