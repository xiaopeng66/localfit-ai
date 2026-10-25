import 'package:drift/drift.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/text/search_text.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_csv_importer.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 存量食物库的一次性归一化（ADR-037）。
///
/// 随包资产 `assets/seed/food_library_normalization.v1.csv` 由
/// `tool/food_catalog/normalize_food_library.py` 生成，每行是：
///
/// ```
/// 旧名称, 旧品牌, 新名称, 新品牌, 分类, 别名
/// ```
///
/// 做的事：按**旧身份**（名称, 品牌）在库里找到对应行 → 改成新名称/品牌、
/// 落十档分类、补别名。找不到的行跳过（用户手删过就跳过）。
///
/// 纪律：
///  * **只搬文字、不删备注**（改名规则见 `normalize_food_name_format.dart`）；
///  * 别名只在**该食物还没有任何别名**时写入——不覆盖用户自己加的；
///  * 幂等：KV `food_library_normalized_v1` 打标后不再跑；打标前崩溃则下次重跑
///    （重跑时旧身份已不存在 ⇒ 自然跳过，仍安全）；
///  * 一个事务：要么整批到位，要么都不动。
const String kFoodLibraryNormalizationAsset =
    'assets/seed/food_library_normalization.v1.csv';
// v2（2026-10-22）：资产补了「麻花」家族（27 条）、黑豆腐 ×2、蒸米糕 ×1 的分类纠正。
// 换键让已经跑过 v1 的库再应用一次——重跑是幂等的：改名后的行按新身份命中，
// 已有别名不覆盖，字段没变的行不写。
const String kFoodLibraryNormalizedKey = 'food_library_normalized_v2';

final class FoodLibraryNormalizationResult {
  const FoodLibraryNormalizationResult({
    required this.alreadyDone,
    required this.rowsRead,
    required this.foodsUpdated,
    required this.aliasesInserted,
    required this.skipped,
  });

  final bool alreadyDone;
  final int rowsRead;
  final int foodsUpdated;
  final int aliasesInserted;
  final int skipped;

  bool get didNothing => alreadyDone || foodsUpdated == 0;
}

final class FoodLibraryNormalizer {
  FoodLibraryNormalizer({
    required this.database,
    required this.idGenerator,
    required this.clock,
    this.assetPath = kFoodLibraryNormalizationAsset,
    Future<String> Function(String path)? loadAsset,
  }) : loadAsset = loadAsset ?? rootBundle.loadString;

  final AppDatabase database;
  final IdGenerator idGenerator;
  final AppClock clock;
  final String assetPath;
  final Future<String> Function(String path) loadAsset;

  Future<FoodLibraryNormalizationResult> runIfNeeded() async {
    final settings = AppSettingsRepository(database: database);
    if (await settings.getBool(kFoodLibraryNormalizedKey)) {
      return const FoodLibraryNormalizationResult(
        alreadyDone: true,
        rowsRead: 0,
        foodsUpdated: 0,
        aliasesInserted: 0,
        skipped: 0,
      );
    }
    final text = await loadAsset(assetPath);
    final rows = FoodCsvImporter.parseCsvRows(text);
    if (rows.isEmpty) {
      throw const FormatException('归一化资产是空的。');
    }
    final header = rows.first;
    if (header.length < 6) {
      throw FormatException('归一化资产表头不对：$header');
    }

    // 库内身份索引（一次读全：23,919 行 × 4 列，几十 MB 以内）。
    final foods = await database.select(database.foods).get();
    final byIdentity = <String, List<Food>>{};
    for (final food in foods) {
      final key = _identityKey(food.name, food.brand);
      byIdentity.putIfAbsent(key, () => <Food>[]).add(food);
    }
    // 已有别名的食物：不覆盖用户自己加的。
    final withAliases = <String>{
      for (final row in await database.select(database.foodAliases).get())
        row.foodId,
    };

    final now = clock.nowUtc();
    var updated = 0;
    var aliasesInserted = 0;
    var skipped = 0;
    final aliasRows = <FoodAliase>[];

    await database.transaction(() async {
      for (final row in rows.skip(1)) {
        if (row.length < 6) continue;
        final oldName = row[0].trim();
        final oldBrand = row[1].trim();
        final newName = row[2].trim();
        final newBrand = row[3].trim();
        final categoryId = _categoryIdOf(row[4].trim());
        final aliasText = row[5].trim();
        if (oldName.isEmpty) continue;

        // 先按**旧身份**找（升级上来的库）；找不到再按**新身份**找——
        // 新装走的是「导入 → 写入口就归一化名称」，库里存的已经是新名称
        // （ADR-037），旧身份自然不存在。两条都找不到才算跳过。
        final matches =
            byIdentity[_identityKey(oldName, oldBrand)] ??
            byIdentity[_identityKey(
              newName.isEmpty ? oldName : newName,
              newBrand,
            )];
        if (matches == null || matches.isEmpty) {
          skipped += 1;
          continue;
        }
        final aliases = aliasText
            .split(RegExp(r'[、,，;；|｜]'))
            .map((raw) => raw.trim())
            .where((raw) => raw.isNotEmpty)
            .toList(growable: false);

        for (final food in matches) {
          final targetName = newName.isEmpty ? food.name : newName;
          final targetBrand = newBrand.isEmpty ? null : newBrand;
          final categoryChanged =
              categoryId != null && (food.category ?? '') != categoryId;
          // 比较前先把「无品牌」统一成空串：`String? null != String ''` 恒真，
          // 会让**每一条无品牌的行每次重跑都被重写**（2026-10-22 设备实测抓到：
          // 第二次运行仍报「更新 9474 条」）。
          final fieldsChanged =
              targetName != food.name ||
              (targetBrand ?? '') != (food.brand ?? '') ||
              categoryChanged;
          if (fieldsChanged) {
            await (database.update(
              database.foods,
            )..where((t) => t.id.equals(food.id))).write(
              FoodsCompanion(
                name: Value(targetName),
                brand: Value(targetBrand),
                category: categoryChanged
                    ? Value(categoryId)
                    : const Value.absent(),
                updatedAt: Value(now),
              ),
            );
            updated += 1;
          }
          if (aliases.isNotEmpty && !withAliases.contains(food.id)) {
            for (final alias in aliases) {
              final text = normalizeSearchText(alias);
              if (text.isEmpty) continue;
              aliasRows.add(
                FoodAliase(
                  id: idGenerator.next(),
                  foodId: food.id,
                  normalizedText: text,
                  language: 'zh-CN',
                  // 规则派生的别名：普通精确命中档（manual 留给用户自己填的）。
                  aliasType: 'nickname',
                  source: 'normalized',
                  confidence: 1,
                  createdAt: now,
                ),
              );
              aliasesInserted += 1;
            }
            withAliases.add(food.id);
          }
        }
      }
      if (aliasRows.isNotEmpty) {
        await database.batch((batch) {
          for (final alias in aliasRows) {
            batch.insert(database.foodAliases, alias);
          }
        });
      }
    });

    await settings.setBool(kFoodLibraryNormalizedKey, value: true);
    return FoodLibraryNormalizationResult(
      alreadyDone: false,
      rowsRead: rows.length - 1,
      foodsUpdated: updated,
      aliasesInserted: aliasesInserted,
      skipped: skipped,
    );
  }

  /// 与导入器/去重口径同一套键：trim + 忽略大小写 + 全角折半角。
  String _identityKey(String name, String? brand) =>
      FoodCsvImporter.normalizeKey(
        '${name.trim()}\u241F${brand?.trim() ?? ''}',
      );

  /// 资产里写的分类是十档 id（未知值不写，保持库内原样）。
  static String? _categoryIdOf(String raw) =>
      FoodCategory.tryFromId(raw)?.id ?? FoodCategory.tryFromLabel(raw)?.id;
}
