import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show formatLocalDate;
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';

/// 「今天是已有相同记录」的应用前提示（2026-11-07 下一版·重复可见化）。
///
/// 【为什么需要它】编译侧已经从结构上杜绝了"把已写库内容当素材"（编辑卡不进
/// 最近对话、事实只由快照提供）。但还有一种情况本地管不了：模型仍可能对同一
/// 件事再提一次（例如你连点两次生成、或回复里重复列出同一份食物）。执行器对
/// 餐食有全天去重、对体重是同日覆盖，**饮水则是实打实的追加**。
///
/// 这里不做硬拦截（用户可能真的又喝了一杯），只把「今天已有」摆在卡片上，
/// 让你在点「应用」之前就看见：这条是重复的，还是新的。
///
/// 失败一律静默（提示是旁注，绝不因为它让卡片出不来）。
final class ExistingFactProbe {
  ExistingFactProbe({
    required this.mealRepository,
    required this.waterRepository,
    required this.measurementRepository,
    required this.clock,
  });

  final MealRepository mealRepository;
  final WaterRepository waterRepository;
  final MeasurementRepository measurementRepository;
  final AppClock clock;

  /// 返回 rowIndex → 人话提示。只对记餐/饮水/体重三类给提示（其余命令没有
  /// 「重复」语义：更新/删除天然按 id 幂等，新建食材/菜品是 upsert）。
  Future<Map<int, String>> call(ChatEditTurn turn) async {
    final today = formatLocalDate(clock.nowUtc());
    final hints = <int, String>{};
    // 按日期缓存今天的既有事实，避免同一张卡里多条命令重复查库。
    final mealNamesByDate = <String, Set<String>>{};
    final waterByDate = <String, List<double>>{};
    final weightByDate = <String, double?>{};

    for (final row in turn.rows) {
      final command = row.command;
      if (command == null) continue;
      final date = (command.args['localDate'] as String?) ?? today;
      switch (command.action) {
        case 'meal.create':
          final names = mealNamesByDate[date] ??= await _mealFoodNames(date);
          final rawItems = command.args['items'];
          if (rawItems is! List) break;
          final hits = <String>[];
          for (final entry in rawItems) {
            if (entry is! Map) continue;
            final food = entry['food'];
            if (food is String && names.contains(food.trim())) {
              hits.add(food.trim());
            }
          }
          final hint = duplicateHintFor(
            action: 'meal.create',
            existingFoodNames: hits.toSet(),
          );
          if (hint != null) hints[row.index] = hint;
        case 'water.add':
          final amounts = waterByDate[date] ??= await _waterAmounts(date);
          final amount = (command.args['amountMl'] as num?)?.toDouble();
          if (amount == null) break;
          final hint = duplicateHintFor(
            action: 'water.add',
            existingWaterMl: amounts,
            draftAmountMl: amount,
          );
          if (hint != null) hints[row.index] = hint;
        case 'weight.log':
          final existing = weightByDate.containsKey(date)
              ? weightByDate[date]
              : (weightByDate[date] = (await measurementRepository.findByDate(
                  date,
                ))?.weightKg);
          final hint = duplicateHintFor(
            action: 'weight.log',
            existingWeightKg: existing,
          );
          if (hint != null) hints[row.index] = hint;
      }
    }
    return hints;
  }

  Future<Set<String>> _mealFoodNames(String localDate) async {
    final meals = await mealRepository.watchForDate(localDate).first;
    return {
      for (final meal in meals)
        for (final item in meal.items) item.foodName.trim(),
    };
  }

  Future<List<double>> _waterAmounts(String localDate) async {
    final summary = await waterRepository.watchDay(localDate).first;
    return [for (final record in summary.records) record.amountMl];
  }
}

/// 纯判断（可单测）：该命令与「今天已有」冲突时返回人话提示，否则 null。
///
/// 文案原则：说清**已有几条/哪几样**，以及**应用后会发生什么**（不重复写入 /
/// 覆盖 / 再记一次），不替用户做决定。
String? duplicateHintFor({
  required String action,
  Set<String> existingFoodNames = const {},
  List<double> existingWaterMl = const [],
  double? draftAmountMl,
  double? existingWeightKg,
}) {
  switch (action) {
    case 'meal.create':
      if (existingFoodNames.isEmpty) return null;
      final names = existingFoodNames.join('、');
      return '今天已经记过$names，应用时不会重复写入';
    case 'water.add':
      if (draftAmountMl == null) return null;
      // **相同容量**才算重复（不同容量是新的那杯，不提示）。
      final same = existingWaterMl.where((value) => value == draftAmountMl);
      if (same.isEmpty) return null;
      final ml = _ml(draftAmountMl);
      return '今天已有 ${same.length} 次 ${ml}ml 的饮水，确认要再记一次吗';
    case 'weight.log':
      if (existingWeightKg == null) return null;
      final kg = _kg(existingWeightKg);
      return '今天已记过体重 $kg kg，应用会覆盖为这次的值';
    default:
      return null;
  }
}

String _ml(double value) =>
    value == value.roundToDouble() ? value.round().toString() : '$value';

String _kg(double value) {
  final text = value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return text;
}
