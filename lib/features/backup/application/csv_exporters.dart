import 'package:localfit_ai/core/csv/csv_formula_guard.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';

final class CsvExportTables {
  const CsvExportTables({
    required this.meals,
    required this.mealItems,
    required this.workoutSessions,
    required this.workoutSets,
    required this.exercises,
  });

  final List<Meal> meals;
  final List<MealItem> mealItems;
  final List<WorkoutSession> workoutSessions;
  final List<WorkoutSet> workoutSets;
  final List<Exercise> exercises;
}

/// Rule-based CSV exports for portability. Values are plain facts from the
/// local database; no interpretation or aggregation is added here.
final class CsvExporters {
  const CsvExporters();

  static const _mealsHeader = [
    'meal_id',
    'local_date',
    'slot',
    'eaten_at',
    'source',
    'item_id',
    'food_name',
    'grams',
    'kcal',
    'protein_grams',
    'carbs_grams',
    'fat_grams',
  ];

  static const _trainingHeader = [
    'session_id',
    'session_date',
    'session_status',
    'set_sort_order',
    'exercise_name',
    'weight_kg',
    'reps',
    'rpe',
    'completed_at',
  ];

  /// 食物库 CSV（ADR-037，2026-10-21）：官方 **10 列**，别名紧跟食物名称
  /// （用户指示「名称后边加一个别名」），与导入器（`food_csv_importer.dart`）
  /// 共认这套表头，往返同格式。
  ///
  /// 前 8 列与用户那份「国内食品营养数据」文件**逐字同序**——
  /// `assets/seed/user_foods_8col.v1.csv` 的表头就是这 8 列；第 9 列
  /// 「自建/内置」是给人看的展示列，导入侧读都不读（导入行一律自建）。
  ///
  /// 旧 21 列文件仍可导入：导入器按列名认领，不认识的列**读取后丢弃**，
  /// 不多报一行错，也不拿它们编数据。
  static const _foodsHeader = [
    '食品ID',
    '品牌',
    '食物名称',
    '别名',
    '一级分类',
    '热量(kcal/100g)',
    '蛋白质(g/100g)',
    '碳水化合物(g/100g)',
    '脂肪(g/100g)',
    '自建/内置',
  ];

  String mealsCsv(CsvExportTables tables) {
    final itemsByMeal = <String, List<MealItem>>{};
    for (final item in tables.mealItems) {
      itemsByMeal.putIfAbsent(item.mealId, () => []).add(item);
    }
    final lines = <List<String>>[_mealsHeader];
    for (final meal in tables.meals) {
      final items = itemsByMeal[meal.id] ?? const <MealItem>[];
      if (items.isEmpty) {
        lines.add([
          meal.id,
          meal.localDate,
          meal.slot,
          meal.eatenAt.toIso8601String(),
          meal.source,
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ]);
        continue;
      }
      for (final item in items) {
        lines.add([
          meal.id,
          meal.localDate,
          meal.slot,
          meal.eatenAt.toIso8601String(),
          meal.source,
          item.id,
          item.foodNameSnapshot,
          _number(item.grams),
          _number(item.kcalSnapshot),
          _number(item.proteinSnapshot),
          _number(item.carbsSnapshot),
          _number(item.fatSnapshot),
        ]);
      }
    }
    return _render(lines);
  }

  String trainingCsv(CsvExportTables tables) {
    final namesById = {
      for (final exercise in tables.exercises) exercise.id: exercise.name,
    };
    final setsBySession = <String, List<WorkoutSet>>{};
    for (final set in tables.workoutSets) {
      setsBySession.putIfAbsent(set.sessionId, () => []).add(set);
    }
    final lines = <List<String>>[_trainingHeader];
    for (final session in tables.workoutSessions) {
      final sets = setsBySession[session.id] ?? const <WorkoutSet>[];
      if (sets.isEmpty) {
        lines.add([
          session.id,
          session.localDate,
          session.status,
          '',
          '',
          '',
          '',
          '',
          '',
        ]);
        continue;
      }
      for (final set in sets) {
        lines.add([
          session.id,
          session.localDate,
          session.status,
          '${set.sortOrder}',
          namesById[set.exerciseId] ?? set.exerciseId,
          _number(set.weightKg),
          '${set.reps}',
          set.rpe == null ? '' : _number(set.rpe!),
          set.completedAt.toIso8601String(),
        ]);
      }
    }
    return _render(lines);
  }

  /// 食物库全量导出（ADR-036）：官方 9 列，一列不多一列不少（顺序与
  /// `_foodsHeader` 同）。空值一律空串（导入侧空串 = 未填）。
  ///
  /// **一级分类**：库内只留枚举 id（原文列已 DROP），导出它的中文标签——
  /// 导入侧三种写法（库大类 / 枚举标签 / 枚举 id）都认，标签是唯一能同时
  /// 被人和导入器读懂的写法。缺失（未知 id）留空，导入时按名字归类，不编
  /// 一个假种类。
  String foodsCsv(
    List<Food> foods, {

    /// `{foodId: [归一化别名...]}`（ADR-037）：一次查出来的别名表，
    /// 由调用方传入——导出器不碰数据库。
    Map<String, List<String>> aliases = const {},
  }) {
    final lines = <List<String>>[_foodsHeader];
    for (final food in foods) {
      lines.add([
        // 食品ID：ADR-036 后库内无独立列（并入名称/品牌身份去重），导出留空。
        '',
        food.brand ?? '',
        food.name,
        // 别名：一格多个，`、` 分隔（导入侧按 `、`/`,`/`;` 切）。
        (aliases[food.id] ?? const <String>[]).join('、'),
        // 一级分类 = 唯一分类（ADR-036）。
        FoodCategory.tryFromId(food.category)?.label ?? '',
        _number(food.kcalPer100g),
        _number(food.proteinPer100g),
        _number(food.carbsPer100g),
        _number(food.fatPer100g),
        food.isUserCreated ? '自建' : '内置',
      ]);
    }
    return _render(lines);
  }

  String _number(double value) =>
      value == value.roundToDouble() && value.abs() < 1e15
      ? value.toStringAsFixed(1)
      : value.toString();

  /// 表格公式注入（CWE-1236）：Excel / Numbers / Sheets 会把以 `=`、`+`、
  /// `-`、`@` 或前导 Tab/CR 开头的单元格当**公式**执行——用户在食物名或
  /// 动作名里写 `=HYPERLINK("http://…")` 或是命令式 payload，导出文件被
  /// 别人用表格软件打开时就会跟着跑。加前导单引号是表格软件共同的「强制
  /// 文本」记号，值本身一字不改。
  ///
  /// 纯数字不处理：`-5` 这类负数（以及 `+5`）本来就是数字，加了引号反而
  /// 让导入侧把它们当文本，破坏数值列。
  ///
  /// 实现搬到了 [neutralizeFormulaCell]（`lib/core/csv/csv_formula_guard.dart`）：
  /// 导出加记号、导入拆记号是**一对**，两半必须放在一起看才不会只改一半
  /// ——2026-10-21 设备实测就是这么漏的（见该文件文档）。这里保留同名静态
  /// 入口只为既有判据与调用点。
  static String neutralizeFormula(String cell) => neutralizeFormulaCell(cell);

  /// 每个单元格都加引号并转义内部引号（RFC 4180），转义之前先按
  /// [neutralizeFormula] 拆掉公式语义。
  String _render(List<List<String>> lines) => lines
      .map(
        (line) => line
            .map((cell) => '"${neutralizeFormula(cell).replaceAll('"', '""')}"')
            .join(','),
      )
      .join('\r\n');
}
