import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/core/csv/csv_formula_guard.dart';
import 'package:localfit_ai/features/backup/application/csv_exporters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late CsvExportTables tables;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 9, 12, 12);
    await database
        .into(database.exercises)
        .insert(
          Exercise(
            id: 'ex-squat',
            name: '杠铃深蹲',
            muscleGroup: 'legs',
            equipment: 'barbell',
            source: 'seed-v1',
            isUserCreated: false,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-1',
            localDate: '2026-09-12',
            slot: 'lunch',
            eatenAt: now,
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.mealItems)
        .insert(
          MealItemsCompanion.insert(
            id: 'item-1',
            mealId: 'meal-1',
            foodNameSnapshot: '米饭, "熟"',
            grams: 150,
            kcalSnapshot: 174,
            proteinSnapshot: 3.9,
            carbsSnapshot: 38.9,
            fatSnapshot: 0.45,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(
            id: 'session-1',
            localDate: '2026-09-12',
            startedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.workoutSets)
        .insert(
          WorkoutSetsCompanion.insert(
            id: 'set-1',
            sessionId: 'session-1',
            exerciseId: 'ex-squat',
            sortOrder: 0,
            weightKg: 60,
            reps: 8,
            rpe: const Value(7.5),
            completedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    tables = CsvExportTables(
      meals: await database.select(database.meals).get(),
      mealItems: await database.select(database.mealItems).get(),
      workoutSessions: await database.select(database.workoutSessions).get(),
      workoutSets: await database.select(database.workoutSets).get(),
      exercises: await database.select(database.exercises).get(),
    );
  });

  tearDown(() => database.close());

  test('exports meals as CSV with escaped quoting', () {
    final csv = const CsvExporters().mealsCsv(tables);
    final lines = csv.split('\r\n');

    expect(lines, hasLength(2));
    expect(lines.first, startsWith('"meal_id","local_date","slot"'));
    expect(lines.last, contains('"米饭, ""熟"""'));
    expect(lines.last, contains('"150.0"'));
    expect(lines.last, contains('"174.0"'));
    // The CSV parses back into the same number of cells despite the comma.
    final cells = const CsvFieldParser().parseLine(lines.last);
    expect(cells, hasLength(12));
    expect(cells[6], '米饭, "熟"');
  });

  test('公式注入的菜名被中和为文本（CWE-1236）', () async {
    // 用户在菜名/AI 回复里写下 `=HYPERLINK(...)`，导出后别人用 Excel 打开
    // 就会跟着执行。加前导单引号是表格软件共同的「强制文本」记号。
    final now = DateTime.utc(2026, 9, 12, 12);
    await database
        .into(database.mealItems)
        .insert(
          MealItemsCompanion.insert(
            id: 'item-formula',
            mealId: 'meal-1',
            foodNameSnapshot: '=HYPERLINK("http://evil.example","点我")',
            grams: 100,
            kcalSnapshot: 100,
            proteinSnapshot: 1,
            carbsSnapshot: 1,
            fatSnapshot: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
    final withFormula = CsvExportTables(
      meals: await database.select(database.meals).get(),
      mealItems: await database.select(database.mealItems).get(),
      workoutSessions: await database.select(database.workoutSessions).get(),
      workoutSets: await database.select(database.workoutSets).get(),
      exercises: await database.select(database.exercises).get(),
    );

    final csv = const CsvExporters().mealsCsv(withFormula);
    final formulaLine = csv
        .split('\r\n')
        .firstWhere((line) => line.contains('HYPERLINK'));

    // 值本身完整保留，只是被单引号强制成文本。
    expect(
      formulaLine,
      contains("'=HYPERLINK(\"\"http://evil.example\"\",\"\"点我\"\")"),
    );
    final cells = const CsvFieldParser().parseLine(formulaLine);
    expect(cells[6], "'=HYPERLINK(\"http://evil.example\",\"点我\")");
    // 数值单元格不受影响（否则导入侧会把数值列当文本）。
    expect(csv, contains('"100.0"'));
  });

  test('中和判据：危险前导字符加引号，纯数字豁免', () {
    for (final dangerous in [
      '=1+1',
      '+1+1',
      '-1+1',
      '@SUM(A1)',
      '\t=1',
      '\r=1',
    ]) {
      expect(
        CsvExporters.neutralizeFormula(dangerous),
        "'$dangerous",
        reason: '$dangerous 必须以文本形式导出（CWE-1236）',
      );
    }
    // 负数/正数：加引号会让表格把它们当文本，破坏数值列。
    for (final numeric in ['-5', '-5.0', '+5', '150.0']) {
      expect(CsvExporters.neutralizeFormula(numeric), numeric);
    }
    // 普通文本一字不改。
    expect(CsvExporters.neutralizeFormula('米饭, "熟"'), '米饭, "熟"');
    expect(CsvExporters.neutralizeFormula(''), '');
  });

  test('守卫是**可逆**的：加记号 / 拆记号一对，任何名字都能原样回来', () {
    // 2026-10-21 设备实测（食物库导出 → 原样导入）就栽在「只加不拆」上：
    // 名字被写成 `'+电商山楂饼`，与库内 (名称, 品牌) 身份对不上。这条把两半
    // 钉成一对——导出加了什么，导入就必须拆掉什么。
    const names = [
      '=HYPERLINK("http://evil.example","点我")',
      '+电商山楂饼',
      '-负数开头',
      '@手写',
      "'已有单引号",
      "''双引号开头",
      '米饭, "熟"',
      '普通名字',
      // 数字形状的**名字**：导出侧按「纯数字豁免」不加记号，导入侧也就不该拆。
      '-5',
      '+5',
    ];
    for (final name in names) {
      final exported = CsvExporters.neutralizeFormula(name);
      expect(
        restoreFormulaGuard(exported),
        name,
        reason: '「$name」导出成「$exported」后拆不回来了',
      );
    }
    // 手写文件里的单引号不被误拆（后一个字符是普通字）。
    expect(restoreFormulaGuard("'引号开头"), "'引号开头");
    expect(restoreFormulaGuard(''), '');
    expect(restoreFormulaGuard("'"), "'");
  });

  test('exports training sets with exercise names and optional RPE', () {
    final csv = const CsvExporters().trainingCsv(tables);
    final lines = csv.split('\r\n');

    expect(lines, hasLength(2));
    expect(lines.last, contains('"杠铃深蹲"'));
    expect(lines.last, contains('"7.5"'));
    expect(lines.last, contains('"8"'));
  });

  test('食物库导出：官方 10 列中文表头（ADR-037），一级分类出枚举标签、身份列如实', () async {
    final now = DateTime.utc(2026, 9, 12, 12);
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'seed-egg',
            name: '鸡蛋',
            kcalPer100g: 144,
            proteinPer100g: 13.3,
            carbsPer100g: 2.8,
            fatPer100g: 8.8,
            category: const Value('protein'),
            source: 'seed-v5',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'user-bowl',
            name: '我的酸奶碗',
            brand: const Value('自家'),
            kcalPer100g: 90,
            proteinPer100g: 3.2,
            carbsPer100g: 12,
            fatPer100g: 2.5,
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final foods = await database.select(database.foods).get();

    final csv = const CsvExporters().foodsCsv(foods);
    final lines = csv.split('\r\n');

    expect(
      lines.first,
      '"食品ID","品牌","食物名称","别名","一级分类","热量(kcal/100g)","蛋白质(g/100g)",'
      '"碳水化合物(g/100g)","脂肪(g/100g)","自建/内置"',
    );
    // 一级分类 = 唯一分类（ADR-036）：库内只留枚举 id，导出它的中文标签
    //（表格软件里人能读；导入侧库大类 / 标签 / id 都认）。食品ID 库里已无独立
    // 列 ⇒ 留空；「自建/内置」按落库身份出「自建」/「内置」——导入侧读都不读。
    expect(
      lines,
      contains('"","","鸡蛋","","蛋白质食物","144.0","13.3","2.8","8.8","内置"'),
    );
    expect(
      lines,
      contains('"","自家","我的酸奶碗","","","90.0","3.2","12.0","2.5","自建"'),
    );
  });

  test('别名列：多个别名用顿号连接，没有别名的写空串（导入侧按、/;/，切）', () async {
    final now = DateTime.utc(2026, 9, 12, 12);
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'user-tomato',
            name: '西红柿',
            kcalPer100g: 20,
            proteinPer100g: 1,
            carbsPer100g: 4,
            fatPer100g: 0.2,
            category: const Value('vegetable'),
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final foods = await database.select(database.foods).get();
    final csv = const CsvExporters().foodsCsv(
      foods,
      aliases: {
        'user-tomato': ['番茄', '洋柿子'],
      },
    );
    expect(
      csv.split('\r\n').last,
      '"","","西红柿","番茄、洋柿子","蔬菜","20.0","1.0","4.0","0.2","自建"',
    );
  });
}

/// Minimal RFC-4180 field parser used only by tests to prove round-tripping.
final class CsvFieldParser {
  const CsvFieldParser();

  List<String> parseLine(String line) {
    final fields = <String>[];
    var current = StringBuffer();
    var inQuotes = false;
    var index = 0;
    while (index < line.length) {
      final char = line[index];
      if (inQuotes) {
        if (char == '"') {
          if (index + 1 < line.length && line[index + 1] == '"') {
            current.write('"');
            index++;
          } else {
            inQuotes = false;
          }
        } else {
          current.write(char);
        }
      } else if (char == '"') {
        inQuotes = true;
      } else if (char == ',') {
        fields.add(current.toString());
        current = StringBuffer();
      } else {
        current.write(char);
      }
      index++;
    }
    fields.add(current.toString());
    return fields;
  }
}
