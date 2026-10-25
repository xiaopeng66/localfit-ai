import 'package:flutter/services.dart' show rootBundle;
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_csv_importer.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 随包「用户食物库」CSV 的资产路径（pubspec 声明；转换脚本
/// `tool/food_catalog/convert_food_xlsx.py`，来源见
/// `docs/THIRD_PARTY_LICENSES.md` §1b）。
const String kBundledUserFoodCsvAsset = 'assets/seed/user_foods_8col.v1.csv';

/// 「随包食物库已导入」的 KV 键（幂等判据）。
///
/// 为什么不用 `foods.source`：导入行构造只有一处（`FoodRepository._row`），
/// 所有导入行一律 `source='user'`——这是刻意的（手动导入与随包导入是同一
/// 批「用户可编辑数据」），不为随包路径单开一个 source 值。
const String kBundledUserFoodSource = 'bundled-user-v1';

/// KV 键：`app_settings` 里标「随包食物库已导入成功过一次」。
const String kBundledUserFoodImportedKey = 'bundled_user_food_imported';

/// 随包食物库引导的一次结果（页面/调试面板只读它）。
final class BundledUserFoodImportResult {
  const BundledUserFoodImportResult({
    required this.imported,
    required this.skippedDuplicates,
    required this.failed,
    required this.alreadyImported,
  });

  final int imported;
  final int skippedDuplicates;
  final int failed;

  /// 库里已有本批数据（幂等短路）：本次什么都没写。
  final bool alreadyImported;

  bool get isEmpty => imported == 0 && alreadyImported;
}

/// 把**随包的用户食物库 CSV** 在首启后导进主库。
///
/// 与手动「食物库 → 导入」的差别只有三点：
/// 1. 数据源是随包资产（`rootBundle`），不是用户选的文件——没有大小检查
///    与「文件不是 UTF-8」的用户文案路径；
/// 2. **幂等**：`app_settings` 的 `kBundledUserFoodImportedKey` 已打标 ⇒ 直接
///    跳过；标记随「清除所有数据」一起被清，但内置行仍在库里，下一次预览会
///    按（名称, 品牌）把它们全判成重复（导入 0 条）后重新打标；
/// 3. 落库与手动导入同一条 `FoodRepository.createMany` 行构造（因此这批行
///    是**内置**——2026-10-23 用户：「导入的食物都属内置（以后导入也是），
///    只有 App 内新建才是自建」；不可编辑/删除，「清除所有数据」不清它们，
///    要清走设置页的「清空内置食物」）。
///
/// 失败语义与引导一致：**绝不阻断启动**——调用方在后台调用并吞掉异常，
/// 用户可随时用「食物库 → 导入」手动补。
final class BundledUserFoodImporter {
  BundledUserFoodImporter({
    required this.repository,
    this.assetPath = kBundledUserFoodCsvAsset,
    Future<String> Function(String path)? loadAsset,
  }) : loadAsset = loadAsset ?? rootBundle.loadString;

  final FoodRepository repository;
  final String assetPath;

  /// 资产读取（默认 `rootBundle.loadString`）。测试注入闭包，避免依赖
  /// Flutter 资产通道与它的进程级缓存（`CachingAssetBundle`）。
  final Future<String> Function(String path) loadAsset;

  Future<BundledUserFoodImportResult> importIfNeeded() async {
    final settings = AppSettingsRepository(database: repository.database);
    if (await settings.getBool(kBundledUserFoodImportedKey)) {
      return const BundledUserFoodImportResult(
        imported: 0,
        skippedDuplicates: 0,
        failed: 0,
        alreadyImported: true,
      );
    }
    final text = await loadAsset(assetPath);
    final importer = FoodCsvImporter(repository: repository);
    final preview = await importer.previewText(text);
    final result = await importer.execute(
      preview: preview,
      policy: FoodCsvImportPolicy.skipDuplicates,
    );
    // 只有**导入真的发生**才打标：全部行都因重复被跳过（升级库）也算完成——
    // 数据已在库里的前提成立；failed 很大说明资产坏了，不打标以便重试。
    if (result.imported > 0 || result.failed == 0) {
      await settings.setBool(kBundledUserFoodImportedKey, value: true);
    }
    return BundledUserFoodImportResult(
      imported: result.imported,
      skippedDuplicates: result.skippedDuplicates,
      failed: result.failed,
      alreadyImported: false,
    );
  }
}

/// 供 main.dart 后台调用（与 [BundledUserFoodImporter] 同参）。
Future<BundledUserFoodImportResult> importBundledUserFoods({
  required AppDatabase database,
  required IdGenerator idGenerator,
  required AppClock clock,
}) => BundledUserFoodImporter(
  repository: FoodRepository(
    database: database,
    idGenerator: idGenerator,
    clock: clock,
  ),
).importIfNeeded();
