import 'package:flutter/foundation.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_manifest.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_importer.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_source.dart';

/// 目录引导的结果（docs/07 §5.6）。UI 只读它，不自己推断目录状态。
class CatalogBootstrapResult {
  const CatalogBootstrapResult({
    required this.catalogVersion,
    required this.importedRows,
    required this.importedShards,
    required this.totalShards,
    required this.missingShards,
    required this.skippedEntirely,
    required this.failure,
  });

  /// 随包没有目录时（开发构建）的空结果；准备阶段失败时带上原因。
  const CatalogBootstrapResult.noCatalog({this.failure})
    : catalogVersion = null,
      importedRows = 0,
      importedShards = 0,
      totalShards = 0,
      missingShards = const [],
      skippedEntirely = false;

  final String? catalogVersion;
  final int importedRows;
  final int importedShards;

  /// manifest 里的分片总数（用来告诉用户「已导入 1/5，其余需自行放入」）。
  final int totalShards;

  /// 本地没有、因而这次没导入的分片文件名。
  final List<String> missingShards;
  final bool skippedEntirely;

  /// 导入失败的可行动原因（不足空间、hash 不符、分片缺失…）；成功为 null。
  final String? failure;

  bool get hasCatalog => catalogVersion != null;

  /// 目录是否已全部就位（所有分片都导过一遍）。
  bool get isComplete => hasCatalog && missingShards.isEmpty && failure == null;
}

/// 首次启动与按需导入的目录引导。
///
/// 拆成两步是刻意的：`prepare()` 只做「把随包 core 分片落到本地」这件事
/// （一次 12 MiB 级的复制，必须赶在搜索链路取分片路径之前完成），
/// `importAvailable()` 才是真正写主库的导入（几万行，要放到后台，不能挡住
/// 首帧——`docs/05` §3「50k 分片导入不阻塞 UI isolate」）。
class CatalogBootstrap {
  CatalogBootstrap({required this.source, required this.importer});

  final CatalogShardSource source;
  final CatalogShardImporter importer;

  /// 最近一次导入的状态，供设置页显示；只读。
  final ValueNotifier<CatalogBootstrapResult?> lastResult = ValueNotifier(null);

  CatalogManifest? manifest;

  /// `prepare()` 阶段的失败原因（随包 manifest 解析不了、支持目录不可写、
  /// 资产读不出来…）。只记录不上抛：这个调用在首帧之前，抛出去就是起不来。
  /// 但不能因此把它和「本次构建没有随包目录」混为一谈——设置页的「导入结果」
  /// 卡片要如实反映（docs/11 §2.2 S-3）。
  String? prepareFailure;

  /// 载入随包 manifest 并把随包分片复制到支持目录。
  ///
  /// 随包没有目录时返回 null（调用方照常启动，搜索降级到主库）。随包 manifest
  /// 解析不了、支持目录不可写时同样返回 null：这个调用在首帧之前，抛出去就是
  /// 起不来，而目录只是一条可降级的能力。
  Future<CatalogManifest?> prepare() async {
    prepareFailure = null;
    try {
      final loaded = await source.loadBundledManifest();
      manifest = loaded;
      if (loaded == null) return null;
      await source.materializeBundledShards(loaded);
      return loaded;
    } catch (error) {
      manifest = null;
      // 满盘要说成「空间不足」而不是类型名：2026-09-19 API 35 实测，写
      // `.bundled-shards.json` 失败时上屏的是
      // 「随包目录准备失败（FileSystemException）」，用户不知道要清空间。
      if (isDiskFullError(error)) {
        prepareFailure =
            '设备剩余空间不足，随包目录未能展开。清理空间后可在'
            // docs/28 §5.6：入口从「我的 → 食物目录」搬进了「我的 → 食材库」。
            '「我的 → 食材库 → 导入扩展食物目录」重新扫描。';
      } else {
        // 用户可见文案不插异常类型名：类型名（如 FileSystemException）对
        // 用户不可行动，还会把「类型名=预期文案」钉进契约测试——BUG-17 的
        // 温床（docs/11 O-1，2026-09-19 裁定移除）。这里也不带原始
        // message——它可能含本机路径。
        prepareFailure = '随包目录准备失败，本次跳过；可在「我的 → 食材库 → 导入扩展食物目录」重新扫描。';
      }
      return null;
    }
  }

  /// 导入本地已有的分片（首装＝随包 core 分片；之后＝用户放进支持目录的分片）。
  ///
  /// 任何失败都不上抛：启动路径不允许因为目录问题起不来。失败原因写进
  /// [lastResult]，设置页据此给出可行动提示与重试入口。
  ///
  /// 准备阶段失败过（[prepareFailure] 非空）时会先**重试准备**：设置页的
  /// 「重新扫描本地分片」是卡片给出的恢复入口，而准备失败时 `manifest` 是
  /// null，只回读缓存的话用户清完空间点下去还是同一句失败——恢复路径等于死的。
  Future<CatalogBootstrapResult> importAvailable() async {
    var current = manifest;
    if (current == null && prepareFailure != null) {
      current = await prepare();
    }
    if (current == null) {
      // 准备阶段失败过就如实说失败原因，不说成「没有随包目录」。
      final empty = CatalogBootstrapResult.noCatalog(failure: prepareFailure);
      lastResult.value = empty;
      return empty;
    }

    var missingShards = const <String>[];
    try {
      final resolved = await source.resolveShards(current);
      missingShards = [for (final shard in resolved.missing) shard.file];
      if (resolved.available.isEmpty) {
        final empty = CatalogBootstrapResult(
          catalogVersion: current.catalogVersion,
          importedRows: 0,
          importedShards: 0,
          totalShards: current.totalShards,
          missingShards: missingShards,
          skippedEntirely: false,
          failure: null,
        );
        lastResult.value = empty;
        return empty;
      }

      final report = await importer.importCatalog(
        manifest: current,
        shards: resolved.available,
      );
      final result = CatalogBootstrapResult(
        catalogVersion: current.catalogVersion,
        importedRows: report.importedRows,
        importedShards: report.importedShards,
        totalShards: current.totalShards,
        missingShards: missingShards,
        skippedEntirely: report.skippedEntirely,
        failure: null,
      );
      lastResult.value = result;
      return result;
    } on CatalogImportException catch (error) {
      final result = CatalogBootstrapResult(
        catalogVersion: current.catalogVersion,
        importedRows: 0,
        importedShards: 0,
        totalShards: current.totalShards,
        missingShards: missingShards,
        skippedEntirely: false,
        failure: _describe(error),
      );
      lastResult.value = result;
      return result;
    } catch (error) {
      // 分类之外的错误（sqlite 驱动、文件系统）同样不许从启动路径上抛：
      // 2026-09-16 真机首装时这里漏出过一个 SqliteException，界面什么都不显示，
      // 目录静默为空。用户可见文案不插异常类型名（docs/11 O-1）。
      final result = CatalogBootstrapResult(
        catalogVersion: current.catalogVersion,
        importedRows: 0,
        importedShards: 0,
        totalShards: current.totalShards,
        missingShards: missingShards,
        skippedEntirely: false,
        failure: '目录导入遇到意外错误，已跳过本次导入；可在「我的 → 食材库 → 导入扩展食物目录」重试。',
      );
      lastResult.value = result;
      return result;
    }
  }

  /// `prepare()` + `importAvailable()`；只在测试与一次性场景里用。
  Future<CatalogBootstrapResult> run() async {
    await prepare();
    return importAvailable();
  }

  String _describe(CatalogImportException error) {
    switch (error.kind) {
      case CatalogImportFailureKind.insufficientSpace:
        return '设备剩余空间不足，目录导入已暂停。清理空间后可在「我的 → 食材库 → 导入扩展食物目录」重试。';
      case CatalogImportFailureKind.hashMismatch:
        return '本地分片与目录清单记录的校验和不一致，已拒绝导入（可能是副本损坏或版本不符）。';
      case CatalogImportFailureKind.rowCountMismatch:
        return '本地分片的行数与目录清单不符，已拒绝导入。';
      case CatalogImportFailureKind.invalidRow:
        return '本地分片里有超出取值范围的营养数据，已拒绝导入。';
      case CatalogImportFailureKind.duplicateId:
        return '本地分片里有重复的食物 ID，已拒绝导入。';
      case CatalogImportFailureKind.missingShardFile:
        return '本地分片文件在导入过程中消失，已拒绝导入。';
      case CatalogImportFailureKind.unreadableShard:
        return '本地分片无法读取（文件损坏或格式不符），已拒绝导入。';
    }
  }
}
