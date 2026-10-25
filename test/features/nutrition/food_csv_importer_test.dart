import 'dart:convert';
import 'dart:typed_data';

// 只取 Value：`drift/drift.dart` 也导出 `isNull`/`isNotNull`，与 matcher 撞名。
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/csv_exporters.dart';
import 'package:localfit_ai/features/nutrition/application/clear_builtin_foods.dart';
import 'package:localfit_ai/features/nutrition/data/food_csv_importer.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 食物库 CSV 导入器（docs/31 S5 需求 55/57）。
///
/// 口径：RFC 4180 解析（本库导出全引号格式要能原样读回）、(名称, 品牌)
/// 归一去重只**提示**不拦截、导入走 `FoodRepository.create` 落库一律自建。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late FoodRepository repository;
  late FoodCsvImporter importer;

  setUp(() {
    // 刻意**不导种子**：去重断言要一个可控的小库，真实种子几万行反而让
    // 「与库内重复」的边界没法钉。
    database = AppDatabase(NativeDatabase.memory());
    repository = FoodRepository(
      database: database,
      idGenerator: _SeqIdGenerator(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 9)),
    );
    importer = FoodCsvImporter(repository: repository);
  });

  tearDown(() => database.close());

  // 官方导入格式（ADR-036，2026-10-21「导入格式定死为一种」）：**9 列**中文表头，
  // 前 8 列与用户那份「国内食品营养数据」文件逐字同序（随包 8 列资产就是这前 8 列），
  // 第 9 列「自建/内置」是展示列。与导出器 `_foodsHeader` 同序同字面量
  // （逐字 pin 见「导出表头逐字 == 官方 10 列」）。
  const header =
      '食品ID,品牌,食物名称,别名,一级分类,'
      '热量(kcal/100g),蛋白质(g/100g),碳水化合物(g/100g),脂肪(g/100g),自建/内置';
  // 旧 21 列文件（Round 5 T11 / 需求 75 那套全列表头）继续能导入：认领的 7 列照常
  // 读，其余 14 列**读取后丢弃**（判据见「旧 21 列文件」那两条）。
  const legacy21Header =
      '食品ID,品牌,食物名称,一级分类,二级分类,菜系,数据类型,'
      '热量(kcal/100g),蛋白质(g/100g),碳水化合物(g/100g),脂肪(g/100g),'
      '计量口径,食品状态,来源代号,来源食品编码,原始名称,原始分类,'
      '数据说明,来源链接,配方摘要,来源性质';
  // D14 的兼容性条款：旧 8 列英文表头仍可导入。
  const legacyHeader =
      'name,brand,category,kcal_per_100g,protein_per_100g,carbs_per_100g,'
      'fat_per_100g,origin';
  String csv(String rows) => '$header\r\n$rows';
  Uint8List bytesOf(String text) => Uint8List.fromList(utf8.encode(text));

  /// 按 [header] 的列序造一行数据：命名参数只给关心的列，其余留空。
  /// 全引号 + 引号转义与导出器同一格式（往返判据用得上）。
  /// [id] 与 [origin] 是官方格式里**不落库**的两列（身份去重走（名称, 品牌）；
  /// 导入一律自建）：fixture 里留着它们，好让「列在、值给了、仍被忽略」也被钉住。
  String foodRow({
    String id = '',
    String brand = '',
    String name = '',
    String aliases = '',
    String group = '',
    String kcal = '',
    String protein = '',
    String carbs = '',
    String fat = '',
    String origin = '',
  }) => [
    id,
    brand,
    name,
    aliases,
    group,
    kcal,
    protein,
    carbs,
    fat,
    origin,
  ].map((cell) => '"${cell.replaceAll('"', '""')}"').join(',');

  /// 只带名字、营养值固定的占位行（100/1/1/1）：分页 / 批量 / 两万行那些只
  /// 关心行数与去重记账的测试用它，免得 9 列字面量淹没断言。
  String plainRow(String name) =>
      foodRow(name: name, kcal: '100', protein: '1', carbs: '1', fat: '1');

  group('parseCsvRows（RFC 4180）', () {
    test('引号内的逗号、双引号转义、CRLF 都按数据读', () {
      final rows = FoodCsvImporter.parseCsvRows(
        '"a, ""b"""\r\n"line1\nline2",x\r\n',
      );
      expect(rows, [
        ['a, "b"'],
        ['line1\nline2', 'x'],
      ]);
    });

    test('裸 LF 与结尾换行不产生空行', () {
      final rows = FoodCsvImporter.parseCsvRows('a,b\nc,d\n');
      expect(rows, [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('BOM 剥掉，不吃掉第一个表头字符', () {
      final rows = FoodCsvImporter.parseCsvRows('\uFEFFname,kcal_per_100g');
      expect(rows.single, ['name', 'kcal_per_100g']);
    });
  });

  group('normalizeKey（去重键归一）', () {
    test('trim + 忽略大小写 + 全角折半角', () {
      expect(
        FoodCsvImporter.normalizeKey('ＯＡＫ牛奶'),
        FoodCsvImporter.normalizeKey('oak牛奶'),
      );
      expect(
        FoodCsvImporter.normalizeKey('无糖酸奶　'),
        FoodCsvImporter.normalizeKey(' 无糖酸奶 '),
      );
      // 归一只影响去重判断，不改写名字本身。
      expect(FoodCsvImporter.normalizeKey('ＯＡＫ牛奶'), 'oak牛奶');
    });
  });

  test('大小判据是纯函数：上限之内放行，超出给中文原因（含提高后的实测档位）', () {
    // T11（docs/32 §4 T11 验收 2 / §3 D14 ①）：上限从 16 MiB 提高，全库
    // 重建的 CSV 预计 30+ MB。三条一起钉：上限本身放行、30 MB 放行、
    // 1 GB 仍被挡住（提高不等于拆掉「别把 1 GB 读进内存」的原意）。
    expect(
      FoodCsvImporter.sizeViolation(bytes: importer.maxImportBytes),
      isNull,
    );
    expect(
      FoodCsvImporter.sizeViolation(bytes: 30 * 1024 * 1024),
      isNull,
      reason: '全量重建的 CSV 预计 30+ MB，不能被上限拒绝',
    );
    expect(FoodCsvImporter.sizeViolation(bytes: 40 * 1024 * 1024), isNull);
    final violation = FoodCsvImporter.sizeViolation(
      bytes: importer.maxImportBytes + 1,
    );
    expect(violation, isNotNull);
    expect(
      violation,
      contains('${importer.maxImportBytes ~/ (1024 * 1024)} MiB'),
      reason: '原因里写出的上限必须是真上限',
    );
    expect(
      FoodCsvImporter.sizeViolation(bytes: 1024 * 1024 * 1024),
      isNotNull,
      reason: '上限提高后仍要挡住 1 GB 级的误选文件',
    );
  });

  group('preview', () {
    test('缺必需列表头直接报格式错（宽容多余列）', () async {
      // 顺带钉「多余列宽容」：品牌/origin 都不在必需列里。
      const noMacros = '食物名称,品牌,origin\n"鸡蛋","","内置"';
      expect(
        () => importer.preview(bytesOf(noMacros)),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            '表头缺少必需列：热量(kcal/100g)、蛋白质(g/100g)、碳水化合物(g/100g)、脂肪(g/100g)。',
          ),
        ),
      );
    });

    test('空文件与纯表头都不进导入流程', () async {
      await expectLater(
        importer.preview(bytesOf('')),
        throwsA(isA<FormatException>()),
      );
      final headerOnly = await importer.preview(bytesOf('$header\r\n'));
      expect(headerOnly.hasNothingToImport, isTrue);
    });

    test('一级分类认库大类、枚举标签与枚举 id，留空按名字归类（导入侧宽容）', () async {
      final preview = await importer.preview(
        bytesOf(
          csv(
            '${foodRow(name: '鸡蛋', group: '乳类及制品', kcal: '144', protein: '13.3', carbs: '2.8', fat: '8.8')}\r\n'
            '${foodRow(name: '纯牛奶', group: '乳制品', kcal: '62', protein: '3.2', carbs: '4.8', fat: '3.1')}\r\n'
            '${foodRow(name: '全麦面包', group: 'staple', kcal: '246', protein: '9', carbs: '45', fat: '3.4')}\r\n'
            '${foodRow(name: '神秘食材', kcal: '100', protein: '1', carbs: '2', fat: '3')}',
          ),
        ),
      );

      expect(preview.errorCount, 0);
      expect(preview.newCount, 4);
      expect(preview.newFoods[0].category, FoodCategory.dairy); // 库大类
      expect(preview.newFoods[1].category, FoodCategory.dairy); // 枚举标签
      expect(preview.newFoods[2].category, FoodCategory.staple); // 枚举 id
      // 留空：「神秘食材」关键词表里哪档都不命中 → 如实落「其他」。
      expect(preview.newFoods[3].category, FoodCategory.other);
      // 「一级分类」原文只在新列取值是**库大类写法**时落库：老文件的枚举标签/id
      // 不是库大类，把它写进新列就是编数据（导出侧会回退成枚举标签）。
    });

    test('表外种类值整行拒绝（不猜「其他」），同文件里的合法行照常导入', () async {
      final preview = await importer.preview(
        bytesOf(
          csv(
            '${foodRow(name: '鸡蛋', group: '生鲜', kcal: '144', protein: '13.3', carbs: '2.8', fat: '8.8')}\r\n'
            '${foodRow(name: '番茄', group: '蔬菜及制品', kcal: '20', protein: '1', carbs: '4', fat: '0.2')}',
          ),
        ),
      );
      expect(preview.errorCount, 1);
      expect(preview.errors.single.row, 1);
      expect(preview.errors.single.message, startsWith('第 1 行「生鲜」不是有效种类。'));
      // ADR-037：错误里列出十档，用户照着改文件；预览还要给出取值汇总。
      expect(preview.errors.single.message, contains('主食、蛋白质食物'));
      expect(preview.unknownCategories, {'生鲜': 1});
      expect(preview.newCount, 1);
      expect(preview.newFoods.single.name, '番茄');
    });

    test('数字解析错误与超范围错误都带行号（行号从数据第 1 行起）', () async {
      final preview = await importer.preview(
        bytesOf(
          csv(
            '${foodRow(name: '鸡蛋', group: '蛋白质食物', kcal: '144', protein: '13.3', carbs: '2.8', fat: '8.8')}\r\n'
            '${foodRow(name: '坏行', kcal: 'abc', protein: '1', carbs: '2', fat: '3')}\r\n'
            '${foodRow(name: '爆表行', kcal: '1200', protein: '1', carbs: '2', fat: '3')}\r\n'
            '${foodRow(name: '负数行', kcal: '-1', protein: '1', carbs: '2', fat: '3')}',
          ),
        ),
      );
      expect(preview.newCount, 1);
      expect(
        preview.errors.map((error) => error.message).toList(),
        containsAll([
          '第 2 行「abc」不是数字。',
          '第 3 行营养数值超出合理范围。',
          '第 4 行营养数值超出合理范围。',
        ]),
      );
    });

    test('缺名称的行报错', () async {
      final preview = await importer.preview(
        bytesOf(
          csv(
            foodRow(
              brand: '某品牌',
              kcal: '100',
              protein: '1',
              carbs: '2',
              fat: '3',
            ),
          ),
        ),
      );
      expect(preview.errorCount, 1);
      expect(preview.errors.single.message, '第 1 行缺少食物名称。');
    });

    test('与库内 (名称, 品牌) 归一命中 → duplicates 带库内身份', () async {
      await repository.create(
        const NewFood(
          name: '无糖酸奶',
          brand: '某乳业',
          kcalPer100g: 62,
          proteinPer100g: 3.2,
          carbsPer100g: 4.8,
          fatPer100g: 3.1,
          category: FoodCategory.dairy,
        ),
      );
      final now = DateTime.utc(2026, 10, 9);
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: 'seed-1',
              name: '鸡胸肉',
              brand: const Value('some'),
              kcalPer100g: 133,
              proteinPer100g: 24,
              carbsPer100g: 1.2,
              fatPer100g: 3.6,
              source: 'seed-v5',
              createdAt: now,
              updatedAt: now,
            ),
          );

      final preview = await importer.preview(
        bytesOf(
          csv(
            '${foodRow(name: '无糖酸奶', brand: '某乳业', group: '乳类及制品', kcal: '62', protein: '3.2', carbs: '4.8', fat: '3.1')}\r\n'
            // 全角品牌 + 大小写差异也要命中同一键。
            '${foodRow(name: '鸡胸肉', brand: 'ＳＯＭＥ', group: '蛋白质食物', kcal: '133', protein: '24', carbs: '1.2', fat: '3.6')}\r\n'
            '${foodRow(name: '无糖酸奶', brand: '另一家', group: '乳类及制品', kcal: '60', protein: '3', carbs: '5', fat: '3')}',
          ),
        ),
      );

      expect(preview.newCount, 1); // 「另一家」是新的
      expect(preview.duplicateCount, 2);
      // 样例带库内身份：自建行 → 自建，种子行 → 内置。
      expect(
        preview.duplicates
            .firstWhere((d) => d.name == '无糖酸奶')
            .existingIsUserCreated,
        isTrue,
      );
      expect(
        preview.duplicates
            .firstWhere((d) => d.name == '鸡胸肉')
            .existingIsUserCreated,
        isFalse,
      );
    });

    test('同一文件里的重复也算重复（第一条照常算新增）', () async {
      final preview = await importer.preview(
        bytesOf(
          csv(
            '${foodRow(name: '鸡蛋', kcal: '144', protein: '13.3', carbs: '2.8', fat: '8.8')}\r\n'
            '${foodRow(name: '鸡蛋', kcal: '144', protein: '13.3', carbs: '2.8', fat: '8.8')}',
          ),
        ),
      );
      expect(preview.newCount, 1);
      expect(preview.duplicateCount, 1);
      expect(preview.duplicates.single.existingIsUserCreated, isTrue);
    });
  });

  group('execute', () {
    Future<FoodCsvImportPreview> twoRows() => importer.preview(
      bytesOf(
        csv(
          '${foodRow(name: '新食材', kcal: '100', protein: '1', carbs: '2', fat: '3')}\r\n'
          '${foodRow(name: '无糖酸奶', brand: '某乳业', group: '乳类及制品', kcal: '62', protein: '3.2', carbs: '4.8', fat: '3.1')}',
        ),
      ),
    );

    setUp(() async {
      await repository.create(
        const NewFood(
          name: '无糖酸奶',
          brand: '某乳业',
          kcalPer100g: 55,
          proteinPer100g: 3,
          carbsPer100g: 5,
          fatPer100g: 2.5,
        ),
      );
    });

    test('skipDuplicates 只导未命中的候选', () async {
      final preview = await twoRows();
      final result = await importer.execute(
        preview: preview,
        policy: FoodCsvImportPolicy.skipDuplicates,
      );

      expect(result.imported, 1);
      expect(result.skippedDuplicates, 1);
      expect(result.failed, 0);
      expect(await repository.count(), 2);
    });

    test('importAll 连重复的也导（提示不是拦截；库无唯一约束）', () async {
      final preview = await twoRows();
      final result = await importer.execute(
        preview: preview,
        policy: FoodCsvImportPolicy.importAll,
      );

      expect(result.imported, 2);
      expect(result.skippedDuplicates, 0);
      expect(await repository.count(), 3);
    });

    test('导入一律走 create：落库是内置（老文件的「自建/内置」列也改不了身份）', () async {
      final preview = await twoRows();
      await importer.execute(
        preview: preview,
        policy: FoodCsvImportPolicy.importAll,
      );

      final imported = await repository.searchExact('新食材');
      expect(imported, hasLength(1));
      // 2026-10-23 用户：导入的食物都属内置，只有 App 内新建才是自建。
      expect(imported.single.isUserCreated, isFalse);
      expect(imported.single.category, FoodCategory.other);
    });
  });

  // ---------------------------------------------------------------------
  // 新结构 21 列（Round 5 T11 / 需求 75）：用户食物库「国内食品营养数据」的
  // 列定义。逐条钉住列名 → 字段的接线、库大类映射、旧 8 列兼容与导出表头逐字。
  // ---------------------------------------------------------------------
  const libraryGroupToCategory = <String, FoodCategory>{
    '谷物及主食': FoodCategory.staple,
    '薯类及淀粉': FoodCategory.staple,
    '粥类': FoodCategory.staple,
    '中式面点': FoodCategory.staple,
    '零食及甜品': FoodCategory.snack,
    '烘焙食品': FoodCategory.snack,
    '蔬菜及制品': FoodCategory.vegetable,
    '菌藻类': FoodCategory.vegetable,
    '水果及制品': FoodCategory.fruit,
    '乳类及制品': FoodCategory.dairy,
    '饮料类': FoodCategory.beverage,
    '调味品': FoodCategory.condiment,
    '油脂类': FoodCategory.condiment,
    '菜肴及地方食品': FoodCategory.prepared,
    '菜肴及快餐': FoodCategory.prepared,
    '汤羹炖品': FoodCategory.prepared,
    '酱卤熟食': FoodCategory.prepared,
    '蛋类及制品': FoodCategory.protein,
    '畜肉及制品': FoodCategory.protein,
    '禽肉及制品': FoodCategory.protein,
    '水产及制品': FoodCategory.protein,
    '豆类及制品': FoodCategory.protein,
    '坚果种子': FoodCategory.protein,
    '其他食品': FoodCategory.other,
  };

  test('官方 9 列中文表头：全列取值零错误、逐列落进候选（列名接线钉住）', () async {
    final preview = await importer.preview(
      bytesOf(
        csv(
          foodRow(
            id: 'F-2001',
            brand: '样例品牌',
            name: '样例食物',
            group: '菜肴及快餐',
            kcal: '612',
            protein: '24.5',
            carbs: '78',
            fat: '20.1',
            origin: '内置',
          ),
        ),
      ),
    );

    expect(preview.errorCount, 0);
    expect(preview.newCount, 1);
    final food = preview.newFoods.single;
    expect(food.brand, '样例品牌');
    expect(food.name, '样例食物');
    expect(food.category, FoodCategory.prepared); // 枚举由映射表派生
    expect(food.kcalPer100g, 612);
    expect(food.proteinPer100g, 24.5);
    expect(food.carbsPer100g, 78);
    expect(food.fatPer100g, 20.1);
    // 「食品ID」与「自建/内置」两列在表头里、值也给了，仍**不落库**：
    // 身份去重走（名称, 品牌），身份一律自建（execute 侧断言见「导入一律走 create」）。
    expect(food.brand, isNot('自建'));
  });

  test('别名写入库：与名称同形的丢、归一化后去重、类型 manual/来源 import', () async {
    final preview = await importer.preview(
      bytesOf(
        csv(
          foodRow(
            name: '西红柿',
            aliases: '番茄、 洋 柿子 ,番茄,西红柿',
            group: '蔬菜及制品',
            kcal: '20',
            protein: '1',
            carbs: '4',
            fat: '0.2',
          ),
        ),
      ),
    );
    await importer.execute(
      preview: preview,
      policy: FoodCsvImportPolicy.skipDuplicates,
    );

    final food = (await database.select(database.foods).get()).single;
    final aliases = await repository.aliasesFor(food.id);
    expect(aliases, ['番茄', '洋柿子']);
    final rows = await database.select(database.foodAliases).get();
    expect(rows.every((row) => row.aliasType == 'manual'), isTrue);
    expect(rows.every((row) => row.source == 'import'), isTrue);
  });

  test('名称按固定格式落库：鲫鱼-天津 → 鲫鱼（天津）', () async {
    final preview = await importer.preview(
      bytesOf(
        csv(
          foodRow(
            name: '鲫鱼-天津',
            group: '水产及制品',
            kcal: '108',
            protein: '17.1',
            carbs: '3.8',
            fat: '2.7',
          ),
        ),
      ),
    );
    expect(preview.errorCount, 0);
    await importer.execute(
      preview: preview,
      policy: FoodCsvImportPolicy.skipDuplicates,
    );
    final food = (await database.select(database.foods).get()).single;
    expect(food.name, '鲫鱼（天津）');
  });

  test('旧 21 列文件仍可导入：认领 7 列照读，其余 14 列读取后丢弃（ADR-036）', () async {
    final preview = await importer.preview(
      bytesOf(
        '$legacy21Header\r\n'
        '"F-2001","样例品牌","样例食物","菜肴及快餐","盖浇饭","川菜","预包装",'
        '"612","24.5","78","20.1","100g可食部","熟","SRC-9","SF-9",'
        '"原样名称","原样分类","数据说明文本","https://example.com/2001",'
        '"配方摘要文本","实测"',
      ),
    );

    expect(preview.errorCount, 0, reason: '旧文件的 14 个多余列不许让整行报错');
    expect(preview.newCount, 1);
    final food = preview.newFoods.single;
    // 认领的 7 列照常读。
    expect(food.name, '样例食物');
    expect(food.brand, '样例品牌');
    expect(food.category, FoodCategory.prepared);
    expect(food.kcalPer100g, 612);
    expect(food.proteinPer100g, 24.5);
    expect(food.carbsPer100g, 78);
    expect(food.fatPer100g, 20.1);

    // 落库侧：把整行写进库再回读——被丢弃的 14 列在表上**没有**对应列
    // （schema 30 已 DROP 17 列），回读只有契约里的字段。
    await importer.execute(
      preview: preview,
      policy: FoodCsvImportPolicy.skipDuplicates,
    );
    final stored = await repository.searchExact('样例食物');
    expect(stored, hasLength(1));
    expect(stored.single.brand, '样例品牌');
    expect(stored.single.category, FoodCategory.prepared);
    expect(stored.single.kcalPer100g, 612);
    expect(
      database.foods.$columns.map((column) => column.$name),
      isNot(contains('category_sub')),
    );
  });

  test('旧 8 列英文表头仍可导入（D14 兼容条款）', () async {
    final preview = await importer.preview(
      bytesOf(
        '$legacyHeader\r\n'
        // origin 写「内置」只作对照：身份不从这里来（execute 侧断言见
        // 上面「导入一律走 create」那条）。
        '"鸡蛋","","蛋白质食物","144","13.3","2.8","8.8","内置"',
      ),
    );

    expect(preview.errorCount, 0);
    expect(preview.newCount, 1);
    final food = preview.newFoods.single;
    expect(food.name, '鸡蛋');
    expect(food.brand, isNull);
    expect(food.category, FoodCategory.protein); // 旧标签照旧认
    expect(food.kcalPer100g, 144);
  });

  // 设备实测（2026-10-21 vc4044 升级轮）抓到的往返缺口：导出侧按 CWE-1236 给
  // 以 `=`/`+`/`-`/`@` 开头的单元格加了前导单引号（表格软件强制文本记号），
  // 导入侧原样收下 ⇒ 名称被改成 `'+电商山楂饼`，与库内身份**对不上**，
  // 于是「导出 → 原样导入」把这两条当成新条目（设备上实测：2 可导入 / 0 错误）。
  test('公式守卫往返：导出加的前导单引号，导入必须还原（身份对得上）', () async {
    for (final name in [
      '=HYPERLINK("x")',
      '+电商山楂饼',
      '-负数开头',
      '@手写',
      "'已有单引号",
    ]) {
      await repository.create(
        NewFood(
          name: name,
          kcalPer100g: 100,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
          category: FoodCategory.other,
        ),
      );
    }
    final foods = await database.select(database.foods).get();
    final csvText = const CsvExporters().foodsCsv(foods);

    final preview = await importer.preview(bytesOf(csvText));

    expect(preview.errorCount, 0);
    expect(preview.newCount, 0, reason: '自己的导出重新导入不该产生「新条目」');
    expect(preview.duplicateCount, foods.length);
    expect(
      preview.duplicates.map((duplicate) => duplicate.name).toSet(),
      foods.map((food) => food.name).toSet(),
      reason: '名称必须逐字还原（前导单引号是导出侧的表格保护记号，不是名字的一部分）',
    );
  });

  test('一级分类：24 个库大类逐条映射全覆盖（表外值见上一条整行拒绝）', () async {
    // 与 food_category.dart 的 `_libraryGroups` 是**同一份事实的两处字面量**：
    // 少一条、错一条都会在这里红——这张表是库里自由文本与 App 枚举之间唯一的翻译。
    expect(FoodCategory.libraryGroups, libraryGroupToCategory);
    expect(libraryGroupToCategory, hasLength(24));

    final groups = libraryGroupToCategory.keys.toList();
    final preview = await importer.preview(
      bytesOf(
        csv(
          [
            for (final group in groups)
              foodRow(
                name: group,
                group: group,
                kcal: '100',
                protein: '1',
                carbs: '1',
                fat: '1',
              ),
          ].join('\r\n'),
        ),
      ),
    );

    expect(preview.errorCount, 0, reason: '24 个大类一个都不许被拒');
    expect(preview.newCount, 24);
    for (var i = 0; i < groups.length; i++) {
      expect(
        preview.newFoods[i].category,
        libraryGroupToCategory[groups[i]],
        reason: '「${groups[i]}」映射错了',
      );
    }
  });

  test('导出表头逐字 == 官方 10 列（ADR-037，别名紧跟食物名称）', () async {
    final foods = await database.select(database.foods).get();
    expect(
      FoodCsvImporter.parseCsvRows(const CsvExporters().foodsCsv(foods)).first,
      const [
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
      ],
      reason:
          '导出表头就是官方 10 列：前 8 列与用户那份「国内食品营养数据」文件逐字同序'
          '（括号 / 斜杠 / 单位的写法与顺序都不许改写），「别名」紧跟食物名称'
          '（用户指示「名称后边加一个别名」），「自建/内置」在最后。'
          '改了它，上面两条 pin 与 csv_exporters.dart 的 `_foodsHeader` 都要同一笔跟。',
    );
  });

  test('往返：foodsCsv 导出的文件 preview 零错误、种类与身份读回一致（需求 54）', () async {
    await repository.create(
      const NewFood(
        // ADR-037：写入口统一名称格式，引号/多余空格会被收掉（见名称格式测试）。
        name: '米饭, "熟"',
        brand: '某烘焙',
        kcalPer100g: 246,
        proteinPer100g: 9,
        carbsPer100g: 45,
        fatPer100g: 3.4,
        category: FoodCategory.staple,
      ),
    );
    final now = DateTime.utc(2026, 10, 9);
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
    final foods = await database.select(database.foods).get();
    final csvText = const CsvExporters().foodsCsv(foods);

    final preview = await importer.preview(bytesOf(csvText));

    expect(preview.errorCount, 0);
    // 库内两行都在 → 全是「重复」账（导入侧提示，不静默）。
    expect(preview.newCount, 0);
    expect(preview.duplicateCount, 2);
    // 名称里的逗号/引号原样读回（RFC 4180 全引号格式的往返判据）。
    expect(
      preview.duplicates.map((duplicate) => duplicate.name),
      contains('米饭,熟'),
      reason: '名称按固定格式口径读回（引号/空格收掉，逗号保留）',
    );
    // 种类读回：中文标签 → 枚举。
    expect(
      preview.duplicates
          .firstWhere((duplicate) => duplicate.name == '鸡蛋')
          .food
          .category,
      FoodCategory.protein,
    );
  });

  // docs/32 §4 T11 验收 4 的机器外框：钉住「没有静默列」——导出表头里每一列
  // 要么被导入器消费落库，要么显式登记为「读了不落库」或「只给人看」。
  // ADR-036（2026-10-21 导入格式定死）之后官方 9 列 = 7 落库 + 1 读了不落库
  // （食品ID，身份去重走（名称, 品牌））+ 1 展示列（自建/内置，导入一律自建）。
  // 今后再加导出列，这条会先红，逼着对新列做一次显式决定（接线 / 登记），
  // 而不是被 `_mapHeader` 的「多出的列忽略」悄悄丢掉。
  test('导出表头的列集 == 导入器消费列 ∪ 显式仅展示列（防新列静默丢弃）', () async {
    final foods = await database.select(database.foods).get();
    final header = FoodCsvImporter.parseCsvRows(
      const CsvExporters().foodsCsv(foods),
    ).first.toSet();
    // 7 列在 `_columnAliases` 里有归属，`preview` 逐列读进 NewFood 并落库。
    const consumed = <String>{
      '品牌',
      '食物名称',
      '一级分类',
      '热量(kcal/100g)',
      '蛋白质(g/100g)',
      '碳水化合物(g/100g)',
      '脂肪(g/100g)',
    };
    // 读了不落库：身份去重走（名称, 品牌），ADF-036 后库里没有独立的食品ID列。
    const droppedAfterRead = <String>{'食品ID'};
    // 只给人看：导入行一律自建，这一列导入侧读都不读。
    const displayOnly = <String>{'自建/内置'};
    // 写进**另一张表**（`food_aliases`）：别名是这条食物的派生数据。
    const otherTables = <String>{'别名'};

    expect(
      header,
      consumed.union(droppedAfterRead).union(displayOnly).union(otherTables),
      reason:
          '导出表头的列集变了：多出的列要先决定归宿（接线到导入器 / 登记为读了不落库 or '
          'displayOnly）、少了的列要同步删登记，再同步导入器别名表与 docs/32 §2 列清单；'
          '不要只改这里。',
    );
  });

  // docs/32 §4 T11 验收 4 的三方对账：第三条腿——表结构。上面那条 pin 只锁住
  // 「导出表头 ↔ 导入器消费」两方；这一条把 **foods 表结构**也拉进来：表里每一列
  // 要么在 CSV 契约里有归属（导出/导入覆盖），要么显式登记为不参与。ADR-036 落地
  // （schema 29→30，DROP 17 列）时四处必须同一笔改：导出表头 / 别名表 / 行映射
  // （`_row()`）与表结构；表里偷加了字段却没进 CSV 契约，同样会红。
  test('foods 表列集 == CSV 映射覆盖列 ∪ 显式登记的不参与列（三方对账的表结构腿）', () async {
    // CSV 列（中文表头）→ 表列（SQL 名）。顺序与 `_foodsHeader` 同（逐字 pin 见
    // 「导出表头逐字 == 官方 10 列」）。注意表列名是 `kcal_per100g` 形态，
    // 与 CSV 的 `热量(kcal/100g)` **不是同一个串**：这两个命名系的差异就是靠
    // 这张映射显式记住的（docs/32 §2 列名契约）。
    const csvToTable = <String, String?>{
      '食品ID': null, // ADR-036：竞争的旧主键列已 DROP；身份去重走（名称, 品牌）
      '品牌': 'brand',
      '食物名称': 'name',
      '别名': null, // ADR-037：落在 food_aliases 表，不是 foods 的列
      '一级分类': 'category', // 导入期就把原文翻译成枚举，原文不落库
      '热量(kcal/100g)': 'kcal_per100g',
      '蛋白质(g/100g)': 'protein_per100g',
      '碳水化合物(g/100g)': 'carbs_per100g',
      '脂肪(g/100g)': 'fat_per100g',
      '自建/内置': null, // 只给人看：导入行一律自建
    };
    // 表里有、CSV 契约刻意不参与的列（主键 / 内在属性 / 审计列 / 派生列）。
    // `is_user_created`：落库身份，导入一律自建（旧文件的 origin 列只作对照，
    // 不落库）；`default_serving_grams`：份量在 UI 里编辑，不在 CSV 契约内。
    const tableNotInCsv = <String>{
      'id',
      'default_serving_grams',
      'source',
      'is_user_created',
      'created_at',
      'updated_at',
      'state',
      'locale',
      'source_version',
      'license_status',
    };
    // ADR-036：library_code / category_group / category_sub 等 17 列已由
    // schema 30 DROP；上面 csvToTable 里值为 null 的键是读取后丢弃 / 展示列。

    final tableColumns = database.foods.$columns
        .map((column) => column.$name)
        .toSet();
    final storedColumns = csvToTable.entries
        .map((e) => e.value)
        .whereType<String>()
        .toSet();
    expect(
      tableColumns,
      storedColumns.union(tableNotInCsv),
      reason:
          'foods 表列集变了：新列要先决定去向（进 CSV 契约就补进 csvToTable、不参与就补进 '
          'tableNotInCsv），再同步导出表头 / 别名表 / 行映射与 docs/32 §2 列清单；'
          '需要落库的新列还要 schema 30→31。不要只改这里。',
    );

    final foods = await database.select(database.foods).get();
    final header = FoodCsvImporter.parseCsvRows(
      const CsvExporters().foodsCsv(foods),
    ).first.toSet();
    expect(
      header,
      csvToTable.keys,
      reason:
          '导出表头与「CSV→表列」映射登记不一致：加/删 CSV 列时 csvToTable（本测试）与导出表头'
          '（csv_exporters.dart 的 `_foodsHeader`）必须同一笔改；只动一处就会留下对不上表的列，'
          '或表上无人认领的列。',
    );
  });

  // T11（docs/32 §4 T11 验收 4「导入 / 导出 / 表结构三处一致」的**值**那一半）：
  // 上面两条 pin 只管列名对得上——「按新结构重建」要的是**值也进对列**。这条不写死
  // 任何列名：拿导出器自己的表头当契约，造一行每列都有区分值的内置食物（内置 ⇒
  // `自建/内置` 列首尾都是「内置」，身份语义不掺进来）→ 导出 → 清空库 → 同一份文件导入
  // → 再导出 ⇒ 两遍的数据行**逐列相同**。fixture 现在给全部 21 列（含 15 个
  // 新列）都填了区分值 ⇒「解析了却没落库」（`_row()` / `NewFood` 漏列）、
  // 「落库了却没回读」、「回读格式飘了」三种病都会被这一条钉住（变异实测见证据 §14）。
  test('逐列值往返：导出 → 导入空库 → 再导出，数据行逐列与首导出行相同（表头自适应）', () async {
    // 源行**直插表**（绕开 `_row()`）：若也走 `repository.create`，落库侧漏一列会被
    // 「第一次导出本来就是空的」掩盖（幂等）——实测 m1（`_row()` 丢 brand）就打不红。
    final now = DateTime.utc(2026, 10, 13, 7);
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'roundtrip-src',
            name: '米,饭（熟）',
            brand: const Value('某烘焙 工坊'),
            kcalPer100g: 246.5,
            proteinPer100g: 9.25,
            carbsPer100g: 45,
            fatPer100g: 3.4,
            source: 'user',
            isUserCreated: const Value(false), // 内置行（导入也落内置，身份列首尾一致）
            createdAt: now,
            updatedAt: now,
            category: const Value('staple'),
            // ADR-036 后契约里只剩 7 个落库列：这条 fixture 给品牌与四项营养
            // 都是区分值（不是默认 / 空值），哪一列在解析 / `_row()` / 回读 /
            // 导出四处的任一处丢了或改了，下面的逐列断言都会点名列名。
          ),
        );
    final firstCsv = const CsvExporters().foodsCsv(
      await database.select(database.foods).get(),
    );
    final firstRows = FoodCsvImporter.parseCsvRows(firstCsv);
    expect(firstRows, hasLength(2), reason: '首导出 = 表头 + 唯一那行');
    final columns = firstRows.first;
    final firstRow = firstRows[1];

    await database.delete(database.foods).go(); // 同一台库上重建

    final preview = await importer.preview(bytesOf(firstCsv));
    expect(preview.errorCount, 0, reason: '自己的导出必须零错误');
    expect(preview.newCount, 1);
    final result = await importer.execute(
      preview: preview,
      policy: FoodCsvImportPolicy.skipDuplicates,
    );
    expect(result.imported, 1);
    expect(result.failed, 0);

    final secondRows = FoodCsvImporter.parseCsvRows(
      const CsvExporters().foodsCsv(
        await database.select(database.foods).get(),
      ),
    );
    expect(secondRows.first, columns, reason: '两遍导出的表头必须一致');
    expect(secondRows, hasLength(2), reason: '导入 1 行 ⇒ 再导出也是 1 行');
    final secondRow = secondRows[1];
    for (var i = 0; i < columns.length; i++) {
      expect(
        secondRow[i],
        firstRow[i],
        reason:
            '列「${columns[i]}」的值没能往返：首导出 `"${firstRow[i]}"` → 再导出 '
            '`"${secondRow[i]}"`。解析 / `_row()` 落库 / 回读 / 导出四处里有一处把它丢了或改了；'
            '新结构落地时先给这条 fixture 的对应字段一个区分值，再看它红在哪一列。',
      );
    }
  });

  // T11（docs/32 §4 T11 验收 3 的机器部分）：「清空内置 → 重新导入」的连贯流程。
  // CSV 刻意用**导出器自己的输出**（表头随当前结构自动跟随）⇒ 用户的新表头一落地，
  // 这条测试就直接覆盖新结构、fixture 不用改；断言只钉计数与去重语义：被清掉的
  // 内置行回灌时是「新增」、保住的自建行是唯一的「重复」、第二遍导入恒为全重复
  // （去重靠的是预览期的身份索引，库里没有唯一约束）。
  test('T11 清空内置 → 用导出文件回灌：计数与去重语义一致（新表头自适应）', () async {
    final now = DateTime.utc(2026, 10, 13, 9);
    for (final (id, name) in [('seed-a', '内置米饭'), ('seed-b', '内置鸡蛋')]) {
      await database
          .into(database.foods)
          .insert(
            FoodsCompanion.insert(
              id: id,
              name: name,
              kcalPer100g: 116,
              proteinPer100g: 2.6,
              carbsPer100g: 25.9,
              fatPer100g: 0.3,
              source: 'seed-v5',
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    final userFood = await repository.create(
      const NewFood(
        name: '我的鸡胸饭',
        brand: '自家',
        kcalPer100g: 260,
        proteinPer100g: 10,
        carbsPer100g: 30,
        fatPer100g: 3,
        category: FoodCategory.staple,
      ),
    );
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'meal-1',
            localDate: '2026-10-13',
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
            foodId: const Value('seed-a'),
            foodNameSnapshot: '内置米饭',
            grams: 200,
            kcalSnapshot: 232,
            proteinSnapshot: 5.2,
            carbsSnapshot: 51.8,
            fatSnapshot: 0.6,
            createdAt: now,
            updatedAt: now,
          ),
        );

    final csvText = const CsvExporters().foodsCsv(
      await database.select(database.foods).get(),
    );

    final cleared = await ClearBuiltinFoods(database).call();
    expect(cleared.deletedFoods, 2);
    expect(cleared.unlinkedMealItems, 1);
    expect(
      (await database.select(database.foods).get()).map((food) => food.id),
      [userFood.id],
      reason: '清空后只剩自建行',
    );
    final items = await database.select(database.mealItems).get();
    expect(items, hasLength(1), reason: '记录本身保留');
    expect(items.single.foodId, isNull, reason: '引用被置空');

    final preview = await importer.preview(bytesOf(csvText));
    expect(preview.errorCount, 0);
    expect(preview.newCount, 2, reason: '被清掉的内置行回灌时是新增');
    expect(preview.duplicateCount, 1, reason: '保住的自建行是唯一的重复');
    final result = await importer.execute(
      preview: preview,
      policy: FoodCsvImportPolicy.skipDuplicates,
    );
    expect(result.imported, 2);
    expect(result.skippedDuplicates, 1);
    expect(result.failed, 0);
    final rebuilt = await database.select(database.foods).get();
    expect(rebuilt, hasLength(3), reason: '1 自建 + 回灌进来的 2 行');
    expect(
      rebuilt.where((food) => food.isUserCreated),
      hasLength(1),
      reason: '回灌一律内置：只有 App 内新建的那条仍是自建',
    );

    final again = await importer.preview(bytesOf(csvText));
    expect(again.newCount, 0, reason: '第二遍幂等：没有幽灵重复');
    expect(again.duplicateCount, 3);
  });

  // T11（docs/32 §4 T11 验收 2 / §3 D14）：导入器三处升级的机器判据——
  // 上限提高、去重索引分批、落库批量且单事务。B19 的原话是「无法承接
  // 4.9 万级重建」，所以这里的两万行档位就是重建的最小可信档。
  test('大文件不再被上限拒绝：30 MB 真实字节流走通 preview', () async {
    // 不是只看纯函数：真造一个 30+ MB 的字节流走 sizeViolation → utf8 →
    // RFC 4180 解析全链路（填充放在一个格里，行数仍是 1）。
    final padding = 'x' * (31 * 1024 * 1024);
    final preview = await importer.preview(
      bytesOf(
        csv(
          '${foodRow(name: '巨型品牌食物', brand: padding, kcal: '100', protein: '1', carbs: '1', fat: '1')}\r\n',
        ),
      ),
    );

    expect(preview.newCount, 1);
    expect(preview.errorCount, 0);
    expect(preview.newFoods.single.brand, hasLength(padding.length));
  });

  test('分批索引不重不漏：分页边界与收尾页上的库内行照样命中', () async {
    for (var i = 0; i < 5; i++) {
      await repository.create(
        NewFood(
          name: '库内-$i',
          kcalPer100g: 100,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ),
      );
    }
    // 页小到 2 行：5 条库内行要跨 3 页拼出索引（[0,1] / [2,3] / [4]）。
    // 下面**每一页都有**被对照的行：跳过任何一页，对应那条就会从「重复」
    // 掉进「新增」——这正是分页在页边界上最容易犯的错。
    final paged = FoodCsvImporter(repository: repository, indexPageSize: 2);

    final preview = await paged.preview(
      bytesOf(
        csv(
          '${plainRow('库内-0')}\r\n' // 第 1 页首行
          '${plainRow('库内-1')}\r\n' // 第 1 页末行
          '${plainRow('全新的')}\r\n'
          '${plainRow('全新的')}\r\n' // 同文件重复
          '${plainRow('库内-2')}\r\n' // 第 2 页首行
          '${plainRow('库内-3')}\r\n' // 第 2 页末行
          '${plainRow('库内-4')}', // 第 3 页（奇数收尾）
        ),
      ),
    );

    expect(preview.errorCount, 0);
    expect(preview.duplicateCount, 6, reason: '5 条库内命中（每页都有）+ 1 条同文件内重复');
    expect(preview.newCount, 1);
    expect(preview.newFoods.single.name, '全新的');
  });

  test('批量落库单事务：第二批撞 id 时前一批也回滚，异常不吞', () async {
    final now = DateTime.utc(2026, 10, 9);
    // 与 importer 共用同一个 id 生成器（gen-0 / gen-1 / …）：把第 4 条会
    // 拿到的 id 提前占掉 ⇒ insertBatchSize=2 时第 2 批必然违反主键。
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'gen-3',
            name: '占位',
            kcalPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 1,
            fatPer100g: 1,
            source: 'test',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final batched = FoodCsvImporter(repository: repository, insertBatchSize: 2);
    final preview = await batched.preview(
      bytesOf(
        csv(
          '${plainRow('批量-0')}\r\n'
          '${plainRow('批量-1')}\r\n'
          '${plainRow('批量-2')}\r\n'
          '${plainRow('批量-3')}\r\n'
          '${plainRow('批量-4')}',
        ),
      ),
    );
    expect(preview.newCount, 5);

    await expectLater(
      batched.execute(
        preview: preview,
        policy: FoodCsvImportPolicy.skipDuplicates,
      ),
      throwsA(isA<Exception>()),
      reason: '落库意外必须冒出来，不能报成「failed 几条」装作部分成功',
    );
    expect((await database.select(database.foods).get()).map((row) => row.id), [
      'gen-3',
    ], reason: '第 1 批已经写进事务的行也必须跟着回滚（整批一个事务）');
  });

  test('两万行端到端：三本账与落库计数逐条对得上（实测耗时见输出）', () async {
    final buffer = StringBuffer('$header\r\n');
    for (var i = 0; i < 20000; i++) {
      buffer.write('${plainRow('批量食物-$i')}\r\n');
    }
    final stopwatch = Stopwatch()..start();
    final preview = await importer.preview(bytesOf(buffer.toString()));
    final result = await importer.execute(
      preview: preview,
      policy: FoodCsvImportPolicy.skipDuplicates,
    );
    stopwatch.stop();
    // ignore: avoid_print
    print(
      '[T11 实测] 2 万行 preview+execute = ${stopwatch.elapsedMilliseconds} ms',
    );

    expect(preview.newCount, 20000);
    expect(preview.errorCount, 0);
    expect(result.imported, 20000, reason: '跨批边界一条都不许丢或重');
    expect(result.failed, 0);
    expect(await repository.count(), 20000);
    // 上界很松：只抓「数量级退化」（例如退回逐行自动提交），实测值看上一行。
    expect(stopwatch.elapsedMilliseconds, lessThan(120000));
  });
}

final class _SeqIdGenerator implements IdGenerator {
  var _next = 0;

  @override
  String next() => 'gen-${_next++}';
}
