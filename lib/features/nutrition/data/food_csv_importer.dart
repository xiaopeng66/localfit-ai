import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:localfit_ai/core/csv/csv_formula_guard.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_name_format.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';

/// 一条解析/校验失败（行号从**数据**第 1 行起，不含表头）。
final class FoodCsvRowError {
  const FoodCsvRowError({required this.row, required this.message});

  final int row;
  final String message;
}

/// 库内已命中 (名称, 品牌) 的候选：带库内行的「内置/自建」身份，
/// 预览列表原样展示（docs/31 S5 ④ 的样例行）。
final class FoodCsvDuplicate {
  const FoodCsvDuplicate({
    required this.food,
    required this.existingIsUserCreated,
  });

  final NewFood food;
  final bool existingIsUserCreated;

  String get name => food.name;

  /// 展示用品牌文案：无品牌给「无品牌」（不带括号——弹层里外层统一包
  /// 「名字（品牌）」，这里再带括号会渲染成双括号）。
  String get brandLabel => food.brand ?? '无品牌';
}

/// 导入预览（docs/31 S5 需求 57：**先给账再决定**，不静默跳过）。
final class FoodCsvImportPreview {
  const FoodCsvImportPreview({
    required this.newFoods,
    required this.duplicates,
    required this.errors,
    this.unknownCategories = const {},
  });

  /// 没有命中库内 (名称, 品牌) 的候选，直接可导。
  final List<NewFood> newFoods;

  /// 命中的候选，由用户决定跳过还是照导。
  final List<FoodCsvDuplicate> duplicates;

  /// 解析/校验失败的行（**不参与**导入，只如实报数）。
  final List<FoodCsvRowError> errors;

  /// 「分类」列里无法识别的取值 → 出现次数（ADR-037 的硬门禁）。
  /// 预览弹层据此给用户一句话：「N 个分类无法识别，请先手工改成 10 档」，
  /// 而不是让他在几百行错误里自己找规律。
  final Map<String, int> unknownCategories;

  int get newCount => newFoods.length;
  int get duplicateCount => duplicates.length;
  int get errorCount => errors.length;
  bool get hasNothingToImport => newCount == 0 && duplicateCount == 0;
}

/// 执行结果。`failed` 正常为 0（预览已做过同一套校验），留着是诚实兜底：
/// 落库那一步如果真出意外，数字要说出来，不能装作全成功。
final class FoodCsvImportResult {
  const FoodCsvImportResult({
    required this.imported,
    required this.skippedDuplicates,
    required this.failed,
  });

  final int imported;
  final int skippedDuplicates;
  final int failed;
}

/// 用户在预览弹层里的决定（docs/31 S5 ④ 的两个按钮）。
enum FoodCsvImportPolicy {
  /// 「跳过重复，导入 N 条」：只导未命中的候选。
  skipDuplicates,

  /// 「全部导入」：重复的也照导（foods 无唯一约束，D7 ④）。
  importAll,
}

/// 食物库 CSV 导入器（docs/31 S5 需求 55/57）。
///
/// 与 `menu_file_importer` 的裸 split 不同，这里按 **RFC 4180** 解析：
/// 本应用导出的每格都带引号（`CsvExporters._render`），名称里含逗号、
/// 引号、换行的食物（如 `"100%果汁,浓缩"`）必须能原样读回。
///
/// 去重口径：`normalize(名称) + normalize(品牌)`——trim、忽略大小写、
/// 全角折半角。命中是**提示**不是拦截：用户选「全部导入」就照导
/// （库本就允许同名食物，无唯一约束）。导入一律走
/// [FoodRepository.createMany]（与 [FoodRepository.create] 共用行构造）：
/// 同一套校验、同一套自建标记，没有旁路。
///
/// 2026-10-13（docs/32 §4 T11 / §3 D14）三处升级——都是为了承接「清空内置
/// 食物 + 按新结构重建」那种 4.9 万行的量级（B19）：上限 16 MiB → 256 MiB、
/// 去重索引由整表物化改**分页**、落库由逐行 `create` 改**分批 + 单事务**。
///
/// 2026-10-21（ADR-036「导入格式定死为一种」）：**官方 9 列**——
/// `食品ID, 品牌, 食物名称, 一级分类, 热量(kcal/100g), 蛋白质(g/100g),
/// 碳水化合物(g/100g), 脂肪(g/100g), 自建/内置`（前 8 列与用户那份
/// 「国内食品营养数据」文件逐字同序）。认领 7 列（见 `_columnAliases`）；
/// 「食品ID」读取后丢弃（身份去重走（名称, 品牌））、「自建/内置」读都不读
/// （导入行一律自建）；「一级分类」在**导入期**翻成 `FoodCategory` 枚举 id
/// 存储，原文不落库。旧 21 列与旧 8 列英文表头继续宽容接受，未认领的列
/// 一律读取后丢弃（不报错、不编数据）。
final class FoodCsvImporter {
  const FoodCsvImporter({
    required this.repository,
    this.maxImportBytes = defaultMaxImportBytes,
    this.indexPageSize = defaultIndexPageSize,
    this.insertBatchSize = defaultInsertBatchSize,
  });

  final FoodRepository repository;

  /// 单文件导入上限：**256 MiB**（docs/32 §4 T11 验收 2 / §3 D14 ①）。
  ///
  /// 原值是 16 MiB，当时的口径是「种子全量约 6 MiB，这个上限约等于两个
  /// 全库」；全库重建要收的文件预计 30+ MB，那个上限会**直接拒绝用户自己的
  /// 全量导出**。提高不等于拆掉：上限的原意是「别把误选的 1 GB 文件读进
  /// 内存」，所以它仍然是硬的（1 GiB 照样拒绝），只是阈值挪到全量重建的
  /// 八倍开外。
  static const int defaultMaxImportBytes = 256 * 1024 * 1024;

  /// 去重索引的分页大小（D14 ②）：库内 (名称, 品牌) 索引按 id 序**一页一页**
  /// 取，不再一次性把全表物化进内存。可注入——测试用小页当放大镜，直接压出
  /// 「跨页边界」这类只在页边界上才犯的错。
  static const int defaultIndexPageSize = 5000;

  /// 落库批大小（D14 ③）：每批一个 drift `Batch`（一次往返），批与批在
  /// **同一个事务**里。可注入：测试用小批把「批边界」压到台面上。
  static const int defaultInsertBatchSize = 500;

  final int maxImportBytes;
  final int indexPageSize;
  final int insertBatchSize;

  /// 纯判据（无 I/O）：超限返回给用户看的中文原因，否则 null。
  /// 单测直接测它，免造真文件。
  static String? sizeViolation({
    required int bytes,
    int limit = defaultMaxImportBytes,
  }) {
    if (bytes <= limit) return null;
    final limitMib = limit ~/ (1024 * 1024);
    final actualMib = bytes / (1024 * 1024);
    return '文件过大（约 ${actualMib.toStringAsFixed(1)} MiB，'
        '上限 $limitMib MiB）。';
  }

  /// 解析 + 对照库内 (名称, 品牌)。只读不写。
  Future<FoodCsvImportPreview> preview(Uint8List bytes) async {
    final violation = sizeViolation(bytes: bytes.length, limit: maxImportBytes);
    if (violation != null) throw FormatException(violation);

    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('文件不是 UTF-8 编码，无法读取。');
    }
    return previewText(text);
  }

  /// 已解码文本的预览（随包食物库引导复用：资产已经是 UTF-8 字符串，
  /// 不再走一次大小检查/解码——那条纪律属于「用户选的文件」）。
  Future<FoodCsvImportPreview> previewText(String text) async {
    final rows = parseCsvRows(text);
    if (rows.isEmpty) {
      throw const FormatException('文件里没有 CSV 表头。');
    }
    final columns = _mapHeader(rows.first);
    final keysByIdentity = await _identityIndex();

    final newFoods = <NewFood>[];
    final duplicates = <FoodCsvDuplicate>[];
    final errors = <FoodCsvRowError>[];
    final unknownCategories = <String, int>{};
    for (var i = 1; i < rows.length; i++) {
      final cells = rows[i];
      final rowNumber = i; // 数据第 1 行 = rows[1]
      if (cells.length == 1 && cells.first.trim().isEmpty) {
        continue; // 空行不算数据（RFC 4180 允许最后换行，也容忍中间空行）
      }
      String cell(String column) {
        final index = columns[column];
        return index != null && index < cells.length ? cells[index].trim() : '';
      }

      /// 文本列：先拆掉导出侧的表格公式守卫（前导单引号），再当值用。
      /// 数值列不走这里——`restoreFormulaGuard` 只认「`'` + 守卫字符」这一种
      /// 形状，数字本来也不会被加记号。
      String textCell(String column) => restoreFormulaGuard(cell(column));

      final name = normalizeFoodNameFormat(textCell('name'));
      final brand = textCell('brand');
      if (name.isEmpty) {
        errors.add(
          FoodCsvRowError(row: rowNumber, message: '第 $rowNumber 行缺少食物名称。'),
        );
        continue;
      }
      // 别名（ADR-037）：一格多个，`、`/`,`/`;` 分隔；空 = 无别名。
      final aliases = const ['aliases', 'alias']
          .map((column) => cell(column))
          .firstWhere((raw) => raw.isNotEmpty, orElse: () => '')
          .split(RegExp(r'[、,，;；|｜]'))
          .map((raw) => raw.trim())
          .where((raw) => raw.isNotEmpty)
          .toList(growable: false);
      final numbers = <String, double>{};
      var badNumber = false;
      for (final column in const [
        'kcal_per_100g',
        'protein_per_100g',
        'carbs_per_100g',
        'fat_per_100g',
      ]) {
        final raw = cell(column);
        final value = double.tryParse(raw);
        if (value == null) {
          errors.add(
            FoodCsvRowError(
              row: rowNumber,
              message: '第 $rowNumber 行「$raw」不是数字。',
            ),
          );
          badNumber = true;
          break;
        }
        numbers[column] = value;
      }
      if (badNumber) continue;
      if (numbers['kcal_per_100g']! > 1000 ||
          numbers['protein_per_100g']! > 100 ||
          numbers['carbs_per_100g']! > 100 ||
          numbers['fat_per_100g']! > 100 ||
          numbers.values.any((value) => value < 0)) {
        errors.add(
          FoodCsvRowError(row: rowNumber, message: '第 $rowNumber 行营养数值超出合理范围。'),
        );
        continue;
      }
      final rawCategory = textCell('category');
      final FoodCategory category;
      if (rawCategory.isEmpty) {
        // 留空 = 不知道：按名字确定性归类（docs/31 S5 ⑥「导入侧宽容」）。
        category = FoodCategory.classify(name: name);
      } else {
        // ADR-036：分类是唯一指标——导入期就把「一级分类」翻译成枚举存
        // `category`，原文不落库。三种写法都认（库大类 / 枚举标签 / 枚举 id）。
        final parsed =
            FoodCategory.tryFromLibraryGroup(rawCategory) ??
            FoodCategory.tryFromLabel(rawCategory) ??
            FoodCategory.tryFromId(rawCategory.toLowerCase());
        if (parsed == null) {
          unknownCategories.update(
            rawCategory,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
          errors.add(
            FoodCsvRowError(
              row: rowNumber,
              message:
                  '第 $rowNumber 行「$rawCategory」不是有效种类。分类只能是这 10 个：'
                  '${FoodCategory.values.map((value) => value.label).join('、')}'
                  '（或用旧文件的 24 个库大类，导入时自动对应）。',
            ),
          );
          continue;
        }
        category = parsed;
      }
      final food = NewFood(
        name: name,
        brand: brand.isEmpty ? null : brand,
        kcalPer100g: numbers['kcal_per_100g']!,
        proteinPer100g: numbers['protein_per_100g']!,
        carbsPer100g: numbers['carbs_per_100g']!,
        fatPer100g: numbers['fat_per_100g']!,
        category: category,
        aliases: aliases,
      );
      final key = normalizeKey('$name\u241F$brand');
      final existingIsUserCreated = keysByIdentity[key];
      if (existingIsUserCreated == null) {
        keysByIdentity[key] = true; // 自建：同文件里再遇到同名同牌也算重复
        newFoods.add(food);
      } else {
        duplicates.add(
          FoodCsvDuplicate(
            food: food,
            existingIsUserCreated: existingIsUserCreated,
          ),
        );
      }
    }
    return FoodCsvImportPreview(
      newFoods: newFoods,
      duplicates: duplicates,
      errors: errors,
      unknownCategories: unknownCategories,
    );
  }

  /// 落库。走的和手动新建同一条 [FoodRepository.createMany]（内部与
  /// [FoodRepository.create] 共用行构造），但**身份不同**：导入行是
  /// **内置**（`isUserCreated=false`），只有 App 内新建才是自建
  /// （2026-10-23 用户）。CSV 里的「自建/内置」列只作展示对照，不改变身份。
  ///
  /// 写入形态（docs/32 §4 T11 验收 2 / §3 D14 ③）：`insertBatchSize` 行一个
  /// drift `Batch`，**所有批共用一个事务**——几万行逐条自动提交会拖到分钟级，
  /// 一次提交快两个数量级。逐行 `create` 的做法已经拆掉：那不是「慢一点」，
  /// 而是 B19 里点名承接不了 4.9 万级重建。
  ///
  /// 失败语义（与逐条版本**不同**，故意改的）：校验不过的行由
  /// [FoodRepository.createMany] 只数不抛，计进
  /// [FoodCsvImportResult.failed]（预览期已做过同一套判据，真出现是意外）；
  /// DB 级错误**不吞**——异常穿出去、事务回滚，调用方给中文原因。吞掉它会把
  /// 「整批一行都没进去」报成「全进去了」，比慢更糟。
  Future<FoodCsvImportResult> execute({
    required FoodCsvImportPreview preview,
    required FoodCsvImportPolicy policy,
  }) async {
    final foods = switch (policy) {
      FoodCsvImportPolicy.skipDuplicates => preview.newFoods,
      FoodCsvImportPolicy.importAll => [
        ...preview.newFoods,
        for (final duplicate in preview.duplicates) duplicate.food,
      ],
    };
    var imported = 0;
    var failed = 0;
    await repository.database.transaction(() async {
      for (var start = 0; start < foods.length; start += insertBatchSize) {
        final end = start + insertBatchSize < foods.length
            ? start + insertBatchSize
            : foods.length;
        final result = await repository.createMany(foods.sublist(start, end));
        imported += result.created;
        failed += result.rejected;
      }
    });
    return FoodCsvImportResult(
      imported: imported,
      skippedDuplicates: policy == FoodCsvImportPolicy.skipDuplicates
          ? preview.duplicateCount
          : 0,
      failed: failed,
    );
  }

  /// 库内 (名称, 品牌) 归一索引，**分页**拼出来（docs/32 §3 D14 ②）。
  ///
  /// 只取三列——对键用不上整个实体。`orderBy(id)` 是分页正确性的前提：
  /// 没有稳定序时 offset 会在页边界上漏行或重复行，而漏掉的那一行正好是
  /// 导入文件里的候选时会直接从「重复」变成「新增」——错得悄无声息。
  ///
  /// 重建后的库通常只剩自建的那几十条（一页返回）；旧安装升级上来的
  /// 四万多行则被切成若干页，峰值不再是一次性物化全表。
  Future<Map<String, bool>> _identityIndex() async {
    final database = repository.database;
    final keys = <String, bool>{};
    var offset = 0;
    while (true) {
      final rows =
          await (database.selectOnly(database.foods)
                ..addColumns([
                  database.foods.name,
                  database.foods.brand,
                  database.foods.isUserCreated,
                ])
                ..orderBy([OrderingTerm.asc(database.foods.id)])
                ..limit(indexPageSize, offset: offset))
              .get();
      for (final row in rows) {
        keys[normalizeKey(
          '${row.read(database.foods.name)!}'
          '\u241F${row.read(database.foods.brand) ?? ''}',
        )] = row.read(
          database.foods.isUserCreated,
        )!;
      }
      if (rows.length < indexPageSize) break;
      offset += indexPageSize;
    }
    return keys;
  }

  /// 规范键 → 可接受的表头写法（**每项第一个 = 报错文案与文档里的首选名**）。
  ///
  /// ADR-036（2026-10-21「导入格式定死为一种」）：认领的列只有官方这 9 列里的
  /// 7 列 + 旧 8 列英文表头的同义写法。
  ///
  /// 「食品ID」「自建/内置」见 §键名之外：两列都**不进**这张表——导入侧不看
  /// 它们（身份去重走（名称, 品牌），**导入行一律内置**）。旧 21 列文件里那 15 列
  /// （二级分类 / 菜系 / 数据类型 / 计量口径 / 食品状态 / 来源代号 / 来源食品
  /// 编码 / 原始名称 / 原始分类 / 数据说明 / 来源链接 / 配方摘要 / 来源性质、
  /// 及旧文件的 `origin`）同样不在表里：不认识的列由 `_mapHeader` 直接忽略，
  /// **读取后丢弃**——既不报错，也不拿它们编数据。
  static const Map<String, List<String>> _columnAliases = {
    'brand': ['品牌', 'brand'],
    'name': ['食物名称', 'name'],
    'aliases': ['别名', 'alias', 'aliases'],
    'category': ['一级分类', 'category'],
    'kcal_per_100g': ['热量(kcal/100g)', 'kcal_per_100g'],
    'protein_per_100g': ['蛋白质(g/100g)', 'protein_per_100g'],
    'carbs_per_100g': ['碳水化合物(g/100g)', 'carbs_per_100g'],
    'fat_per_100g': ['脂肪(g/100g)', 'fat_per_100g'],
  };

  /// 表头 → 规范键下标。必需列缺失直接报格式错（多出的列忽略，宽容导入）。
  /// 必需列的中文/英文两种写法都在 `_columnAliases` 里，报错文案用首选名。
  static Map<String, int> _mapHeader(List<String> header) {
    final byName = <String, int>{
      for (var i = 0; i < header.length; i++) header[i].trim(): i,
    };
    final columns = <String, int>{};
    for (final entry in _columnAliases.entries) {
      for (final alias in entry.value) {
        final index = byName[alias];
        if (index != null) {
          columns[entry.key] = index;
          break;
        }
      }
    }
    final missing = const [
      'name',
      'kcal_per_100g',
      'protein_per_100g',
      'carbs_per_100g',
      'fat_per_100g',
    ].where((key) => !columns.containsKey(key)).toList();
    if (missing.isNotEmpty) {
      throw FormatException(
        '表头缺少必需列：'
        '${missing.map((key) => _columnAliases[key]!.first).join('、')}。',
      );
    }
    return columns;
  }

  /// 去重键归一：trim + 忽略大小写 + 全角折半角（含全角空格）。
  /// 「ＯＡＫ牛奶」和「oak牛奶」、「无糖酸奶」和「无糖酸奶　」是同一候选。
  static String normalizeKey(String raw) {
    final buffer = StringBuffer();
    for (final code in raw.trim().toLowerCase().runes) {
      if (code == 0x3000) {
        buffer.write(' ');
      } else if (code >= 0xFF01 && code <= 0xFF5E) {
        buffer.writeCharCode(code - 0xFEE0);
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// RFC 4180 解析：双引号包裹、引号内逗号/换行/转义引号（`""`）都是数据。
  /// CRLF 与 LF 都认。为测试公开（菜单导入的裸 split 解析不了本库的
  /// 全引号格式，这里是食物库自己的解析器）。
  static List<List<String>> parseCsvRows(String text) {
    var source = text;
    if (source.startsWith('\uFEFF')) source = source.substring(1);
    final rows = <List<String>>[];
    final row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    var hasCell = false;
    void endCell() {
      row.add(cell.toString());
      cell.clear();
      hasCell = false;
    }

    void endRow() {
      if (cell.isNotEmpty || row.isNotEmpty || hasCell) endCell();
      if (row.isNotEmpty) rows.add(List<String>.of(row));
      row.clear();
    }

    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < source.length && source[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(char);
        }
        continue;
      }
      switch (char) {
        case '"':
          inQuotes = true;
          hasCell = true;
        case ',':
          endCell();
        case '\r':
          if (i + 1 < source.length && source[i + 1] == '\n') i++;
          endRow();
        case '\n':
          endRow();
        default:
          cell.write(char);
          hasCell = true;
      }
    }
    endRow();
    return rows;
  }
}
