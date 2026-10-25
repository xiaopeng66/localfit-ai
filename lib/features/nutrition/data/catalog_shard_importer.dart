import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_manifest.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 分片连接工厂（测试可注入）。默认只读打开分片的明文库，见
/// [openCatalogShardReadOnly]。
typedef CatalogShardOpener = sqlite.Database Function(String path);

/// 打开分片：**独立**的只读连接，绝不在主库连接上 `ATTACH`。
///
/// 主库是 SQLCipher 加密库，而分片是 ETL（Python 标准 sqlite3）产出的明文
/// 库。`ATTACH` 会让主库的密钥作用到被附着的库上，真机上直接抛
/// `SqliteException(26) file is not a database`（2026-09-16 在 API 35 上实测）。
/// 分片不带密钥自己开连接就没有这个问题——与搜索层
/// `CatalogSearchService` 取分片 FTS 的做法一致。
sqlite.Database openCatalogShardReadOnly(String path) =>
    sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);

/// 目录分片导入失败类别。
enum CatalogImportFailureKind {
  hashMismatch,
  rowCountMismatch,
  invalidRow,
  duplicateId,
  insufficientSpace,
  missingShardFile,

  /// 分片读不出来（文件损坏、不是 SQLite、或加密库读不了它）。
  unreadableShard,
}

class CatalogImportException implements Exception {
  CatalogImportException(this.kind, this.message);

  final CatalogImportFailureKind kind;
  final String message;

  @override
  String toString() => 'CatalogImportException(${kind.name}): $message';
}

/// 单个待导入分片：manifest 元数据 + 本地文件路径（随包资产或已下载文件）。
class ShardInput {
  const ShardInput({required this.meta, required this.path});

  final CatalogManifestShard meta;
  final String path;
}

class CatalogImportReport {
  const CatalogImportReport({
    required this.importedRows,
    required this.importedShards,
    required this.skippedExistingRows,
    required this.incompleteSkippedRows,
    required this.resumed,
    required this.skippedEntirely,
    this.portionRows = 0,
    this.revisionRows = 0,
    this.evidenceRows = 0,
  });

  final int importedRows;
  final int importedShards;
  final int skippedExistingRows;
  final int incompleteSkippedRows;
  final bool resumed;
  final bool skippedEntirely;

  /// docs/07 §5.5 的三个实体实际写进主库的行数（2.0-1j 起有值）。
  final int portionRows;
  final int revisionRows;
  final int evidenceRows;
}

/// 应用内目录分片导入（docs/07 §5.6）。
///
/// 流程：manifest hash 幂等检查 → 逐分片（磁盘余量检查 → hash 校验 →
/// 只读连接读分片并与 manifest 对行数 → 事务切换）→ job 记录 completed。
/// 任何校验失败都抛 [CatalogImportException] 并把 job 标记 failed；切换在
/// 单个事务里进行，失败整体回滚，主库 foods 保留旧目录不被切成半套。
///
/// 边界（与 1e 分工）：只有完整宏量的行进入主库 foods（kcal 等四列 NOT NULL）；
/// incomplete 行留在分片 SQLite，由 FTS5 搜索层接入。
final class CatalogShardImporter {
  CatalogShardImporter({
    required this.database,
    this.remainingDiskBytes,
    this.minFreeBytes = 32 * 1024 * 1024,
    this.openShard = openCatalogShardReadOnly,
  });

  static const double _kcalMin = 0, _kcalMax = 900;
  static const double _macroMin = 0, _macroMax = 100;
  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  final AppDatabase database;

  /// 分片文件连接工厂；测试可注入（断言只读、记录调用等）。
  final CatalogShardOpener openShard;

  /// 可注入的磁盘余量探测（测试用）；默认用分片所在盘的剩余空间。
  final int Function()? remainingDiskBytes;
  final int minFreeBytes;

  final Sha256 _sha256 = Sha256();

  Future<CatalogImportReport> importCatalog({
    required CatalogManifest manifest,
    required List<ShardInput> shards,
  }) async {
    final manifestHash = await _importHash(manifest, shards);

    // 幂等：同一批分片已成功导入则跳过。
    final completedJob = await (database.select(
      database.foodImportJobs,
    )..where((row) => row.status.equals('completed'))).get();
    if (completedJob.any((job) => job.manifestHash == manifestHash)) {
      return const CatalogImportReport(
        importedRows: 0,
        importedShards: 0,
        skippedExistingRows: 0,
        incompleteSkippedRows: 0,
        resumed: false,
        skippedEntirely: true,
      );
    }

    final now = DateTime.now().toUtc();
    final jobId = 'catalog-import-${now.millisecondsSinceEpoch}';
    try {
      // 中断清理：上次导入没走完（进程被杀/断电）留下的 `importing` 行
      // 不会有人再来收尾——新导入开始前把它们标成 `interrupted`，诊断时
      // 「importing = 正在进行」的语义才成立（docs/11 P3：孤儿 job 行）。
      await (database.update(
        database.foodImportJobs,
      )..where((row) => row.status.equals('importing'))).write(
        FoodImportJobsCompanion(
          status: const Value('interrupted'),
          updatedAt: Value(now),
        ),
      );
      await database
          .into(database.foodImportJobs)
          .insert(
            FoodImportJobsCompanion.insert(
              id: jobId,
              catalogVersion: _catalogVersionSeed(manifest),
              status: 'importing',
              totalShards: shards.length,
              manifestHash: manifestHash,
              startedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
    } catch (error) {
      // 建 job 行是本次导入的**第一条写**，盘真满时它就先失败（2026-09-19
      // API 35 实测：/data 只剩 44MB 时卡在这一步，抛的同样是
      // `DriftRemoteException{remoteCause: SqliteException(13)}`）。只在下面
      // 的分片写入处兜底会漏掉这条路径，用户看到的仍是类型名而不是
      // 「清理空间后重试」。这里没有已落库的 job 行要保留，直接归类即可。
      if (_isDiskFull(error)) {
        throw CatalogImportException(
          CatalogImportFailureKind.insufficientSpace,
          'database or disk is full',
        );
      }
      rethrow;
    }

    var importedRows = 0;
    var importedShards = 0;
    var skippedExisting = 0;
    var incompleteSkipped = 0;
    var portionRows = 0;
    var revisionRows = 0;
    var evidenceRows = 0;

    try {
      for (final shard in shards) {
        _checkDiskSpace(shard);
        final outcome = await _importShard(shard);
        importedRows += outcome.importedRows;
        skippedExisting += outcome.skippedExistingRows;
        incompleteSkipped += outcome.incompleteSkippedRows;
        portionRows += outcome.portionRows;
        revisionRows += outcome.revisionRows;
        evidenceRows += outcome.evidenceRows;
        importedShards += 1;
        await (database.update(
          database.foodImportJobs,
        )..where((row) => row.id.equals(jobId))).write(
          FoodImportJobsCompanion(
            importedShards: Value(importedShards),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
      }
    } on CatalogImportException catch (error) {
      if (error.kind == CatalogImportFailureKind.insufficientSpace) {
        // docs/07 §5.6：磁盘/内存不足时停止导入并提供恢复 —— job 保持
        // importing（已导入分片数已落库），用户清理空间后重试。
      } else {
        await _markJob(jobId, 'failed', errorCount: 1);
      }
      rethrow;
    } catch (error) {
      // 写库那一刻才发现的磁盘满（SQLITE_FULL）要走同一条「空间不足」路径。
      //
      // 前置探测（`_checkDiskSpace`）只在接线层注入了余量探测时才有值，
      // 而 Android 侧没有接；于是真机满盘时失败发生在写事务里，SQLite 报
      // `SQLITE_FULL(13)`，drift 把它从后台 isolate 包成
      // `DriftRemoteException` 上抛（2026-09-19 API 35 实测：
      // `DriftRemoteException{remoteCause: SqliteException(13)}`）。不在这里
      // 归类的话，界面上只能显示「意外错误（DriftRemoteException）」——用户
      // 拿不到「清理空间后重试」这条唯一可行动的指引，job 还会被误标 failed，
      // 与 docs/07 §5.6「保持可续跑」相反。
      if (_isDiskFull(error)) {
        throw CatalogImportException(
          CatalogImportFailureKind.insufficientSpace,
          'database or disk is full',
        );
      }
      // 非预期错误同样不允许留下半套目录或 importing 悬挂状态。
      await _markJob(jobId, 'failed', errorCount: 1);
      rethrow;
    }

    await _markJob(jobId, 'completed');
    return CatalogImportReport(
      importedRows: importedRows,
      importedShards: importedShards,
      skippedExistingRows: skippedExisting,
      incompleteSkippedRows: incompleteSkipped,
      resumed: false,
      skippedEntirely: false,
      portionRows: portionRows,
      revisionRows: revisionRows,
      evidenceRows: evidenceRows,
    );
  }

  Future<void> _markJob(
    String jobId,
    String status, {
    int errorCount = 0,
  }) async {
    final now = DateTime.now().toUtc();
    await (database.update(
      database.foodImportJobs,
    )..where((row) => row.id.equals(jobId))).write(
      FoodImportJobsCompanion(
        status: Value(status),
        errorCount: Value(errorCount),
        finishedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  int _catalogVersionSeed(CatalogManifest manifest) {
    // catalog_version 形如 2026.09-test；取数字部分作为整数种子。
    final digits = manifest.catalogVersion.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return manifest.catalogVersion.hashCode;
    return int.tryParse(digits.substring(0, digits.length.clamp(0, 9))) ??
        manifest.catalogVersion.hashCode;
  }

  /// 幂等键：catalog_version + **本次给出的**分片（文件名与 sha256）。
  ///
  /// 不能对「整个 manifest 的所有分片」取键：docs/07 §5.6 允许首装只导入随包的
  /// core 分片、其余分片之后再由用户主动导入，而同一 manifest 的两批分片会
  /// 算出同一个整包键——首装那次就把 job 记成 completed，后面那批被整包跳过，
  /// 用户永远补不齐目录。
  Future<String> _importHash(
    CatalogManifest manifest,
    List<ShardInput> shards,
  ) async {
    final builder = BytesBuilder();
    builder.add(manifest.catalogVersion.codeUnits);
    for (final shard in shards) {
      builder.add(shard.meta.file.codeUnits);
      builder.add(shard.meta.sha256.codeUnits);
    }
    final digest = await _sha256.hash(builder.toBytes());
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _checkDiskSpace(ShardInput shard) {
    // Dart 标准库没有空闲磁盘 API；真机探测由 UI 接线层注入
    //（platform channel / path_provider 所在盘），未注入时跳过检查。
    final probe = remainingDiskBytes;
    if (probe == null) return;
    final required = File(shard.path).lengthSync() * 3 + minFreeBytes;
    final free = probe();
    if (free < required) {
      throw CatalogImportException(
        CatalogImportFailureKind.insufficientSpace,
        'insufficient disk space for shard ${shard.meta.file}: '
        '$free free, $required required',
      );
    }
  }

  /// 这次失败是不是「磁盘/数据库写满」（SQLITE_FULL，扩展码 13）。
  ///
  /// 判断本身在文件末尾的 [isDiskFullError]（来源层写标记文件时也要用同一
  /// 判断，两边不能漂移）。
  static bool _isDiskFull(Object error) => isDiskFullError(error);

  Future<_ShardOutcome> _importShard(ShardInput shard) async {
    final file = File(shard.path);
    if (!file.existsSync()) {
      throw CatalogImportException(
        CatalogImportFailureKind.missingShardFile,
        'shard file missing: ${shard.path}',
      );
    }

    // 校验阶段（切换前）：hash 与行数。分片读不出来（损坏/不是 SQLite）
    // 在这里就要变成可分类的失败，而不是把 sqlite3 的原始异常漏给调用方。
    final actualHash = await _sha256.hash(await file.readAsBytes());
    final actualHashHex = actualHash.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    if (actualHashHex != shard.meta.sha256) {
      throw CatalogImportException(
        CatalogImportFailureKind.hashMismatch,
        'shard hash mismatch: ${shard.meta.file}',
      );
    }

    final read = await _readShard(shard);

    // docs/07 §5.5 的三个实体：manifest 申报了多少行，分片里就得有多少行
    // （导入器只对「本次真正入库的 food」写这三张表，所以这里比的是
    // **分片内容**与 manifest，而不是与本次插入数——分片可以被部分导入）。
    _checkOntologyCounts(shard, read.ontology);

    return _applyShard(read);
  }

  /// 原子切换：分片内容 → 主库全部在一个事务里；失败整体回滚。
  Future<_ShardOutcome> _applyShard(
    ({List<_ShardRecord> records, int rowCount, _ShardOntology ontology})
    staged,
  ) async {
    final outcome = await database.transaction(() async {
      final existingIds = await database
          .select(database.foods)
          .map((row) => row.id)
          .get();
      final existing = existingIds.toSet();

      var importedRows = 0;
      var skippedExisting = 0;
      var incompleteSkipped = 0;
      var portionRows = 0;
      var revisionRows = 0;
      var evidenceRows = 0;
      final seenInShard = <String>{};
      final insertedEvidence = <String>{};
      final now = DateTime.now().toUtc();

      for (final record in staged.records) {
        if (!seenInShard.add(record.id)) {
          throw CatalogImportException(
            CatalogImportFailureKind.duplicateId,
            'duplicate id in shard: ${record.id}',
          );
        }
        if (record.state != 'verified') {
          incompleteSkipped += 1;
          continue;
        }
        _validateNutrition(record);
        if (existing.contains(record.id)) {
          // 用户编辑/自建行不被目录覆盖。
          skippedExisting += 1;
          continue;
        }
        await database
            .into(database.foods)
            .insert(
              FoodsCompanion.insert(
                id: record.id,
                name: record.name,
                brand: Value.absentIfNull(record.brand),
                kcalPer100g: record.kcal!,
                proteinPer100g: record.protein!,
                carbsPer100g: record.carbs!,
                fatPer100g: record.fat!,
                source: record.sourceId,
                state: const Value('verified'),
                locale: Value.absentIfNull(record.locale),
                category: Value.absentIfNull(record.category),
                licenseStatus: Value(record.licenseStatus),
                createdAt: now,
                updatedAt: now,
              ),
            );
        importedRows += 1;

        // docs/07 §5.5：修订与来源证据跟着条目一起进来（只对真正入库的行，
        // 不然外键指向不存在的 food）。份量与修订按 food id 取，证据按
        // 修订指回的 id 取且同一分片内只插一次。
        final revision = staged.ontology.revisionByFood[record.id];
        if (revision != null) {
          for (final evidenceId
              in revision.sourceEvidenceId == null
                  ? const <String>[]
                  : [revision.sourceEvidenceId!]) {
            final evidence = staged.ontology.evidenceById[evidenceId];
            if (evidence == null) {
              throw CatalogImportException(
                CatalogImportFailureKind.invalidRow,
                'revision of ${record.id} points at missing evidence '
                '$evidenceId',
              );
            }
            if (insertedEvidence.add(evidenceId)) {
              await database
                  .into(database.foodEvidence)
                  .insert(
                    FoodEvidenceCompanion.insert(
                      id: evidence.id,
                      sourceId: evidence.sourceId,
                      license: evidence.license,
                      attribution: Value.absentIfNull(evidence.attribution),
                      retrievedAt: evidence.retrievedAt,
                      transformVersion: evidence.transformVersion,
                      qualityStatus: evidence.qualityStatus,
                      recordHash: evidence.recordHash,
                      createdAt: now,
                    ),
                  );
              evidenceRows += 1;
            }
          }
          await database
              .into(database.foodNutritionRevisions)
              .insert(
                FoodNutritionRevisionsCompanion.insert(
                  id: revision.id,
                  foodId: record.id,
                  revisionNumber: revision.revisionNumber,
                  kcalPer100g: Value.absentIfNull(revision.kcal),
                  proteinGPer100g: Value.absentIfNull(revision.protein),
                  carbsGPer100g: Value.absentIfNull(revision.carbs),
                  fatGPer100g: Value.absentIfNull(revision.fat),
                  sourceEvidenceId: Value.absentIfNull(
                    revision.sourceEvidenceId,
                  ),
                  qualityStatus: Value(revision.qualityStatus),
                  validFrom: Value.absentIfNull(revision.validFrom),
                  createdAt: now,
                ),
              );
          revisionRows += 1;
        }
        for (final portion
            in staged.ontology.portionsByFood[record.id] ??
                const <_ShardPortion>[]) {
          _validatePortion(portion, record.id);
          await database
              .into(database.foodPortions)
              .insert(
                FoodPortionsCompanion.insert(
                  id: portion.id,
                  foodId: record.id,
                  name: portion.name,
                  grams: portion.grams,
                  locale: Value.absentIfNull(portion.locale),
                  source: portion.source,
                  createdAt: now,
                ),
              );
          portionRows += 1;
        }
      }
      return (
        importedRows: importedRows,
        skippedExisting: skippedExisting,
        incompleteSkipped: incompleteSkipped,
        portionRows: portionRows,
        revisionRows: revisionRows,
        evidenceRows: evidenceRows,
      );
    });

    return _ShardOutcome(
      importedRows: outcome.importedRows,
      skippedExistingRows: outcome.skippedExisting,
      incompleteSkippedRows: outcome.incompleteSkipped,
      portionRows: outcome.portionRows,
      revisionRows: outcome.revisionRows,
      evidenceRows: outcome.evidenceRows,
      rowCount: staged.rowCount,
    );
  }

  /// 份量：克数必须是有限正数且不超过 5kg（与 ETL 的 `PORTION_MAX_GRAMS`
  /// 同一判据）。上游把整包重量写进份量是可预见的脏数据，不能让 12kg 的
  /// 「一份」进主库。
  void _validatePortion(_ShardPortion portion, String foodId) {
    final grams = portion.grams;
    if (grams.isNaN || grams.isInfinite || grams <= 0 || grams > 5000) {
      throw CatalogImportException(
        CatalogImportFailureKind.invalidRow,
        'invalid portion grams $grams for $foodId',
      );
    }
  }

  /// manifest 申报的实体行数 vs 分片里真实存在的行数。
  ///
  /// 分片是自包含的（份量/修订/证据都在同一个 SQLite 里），所以这几个数字
  /// 必须对得上；对不上说明产物坏了或者有人在中间改过分片——两者都不该
  /// 静默通过。旧分片（2.0-1j 之前）manifest 里没有这些字段，按「没有实体表」
  /// 处理，不报错也不导入。
  void _checkOntologyCounts(ShardInput shard, _ShardOntology ontology) {
    void check(String label, int? declared, int actual) {
      if (declared == null) return;
      if (declared != actual) {
        throw CatalogImportException(
          CatalogImportFailureKind.rowCountMismatch,
          'shard $label row count mismatch: ${shard.meta.file} '
          'manifest=$declared actual=$actual',
        );
      }
    }

    check('portion', shard.meta.portionRows, ontology.portionCount);
    check('revision', shard.meta.revisionRows, ontology.revisionCount);
    check('evidence', shard.meta.evidenceRows, ontology.evidenceCount);
  }

  void _validateNutrition(_ShardRecord record) {
    void range(String field, double value, double min, double max) {
      if (value.isNaN || value.isInfinite || value < min || value > max) {
        throw CatalogImportException(
          CatalogImportFailureKind.invalidRow,
          'invalid $value for $field in ${record.id}',
        );
      }
    }

    range('kcal', record.kcal!, _kcalMin, _kcalMax);
    range('protein', record.protein!, _macroMin, _macroMax);
    range('carbs', record.carbs!, _macroMin, _macroMax);
    range('fat', record.fat!, _macroMin, _macroMax);
  }

  /// 读一个分片：先对行数（与 manifest 比），再把 foods 行与三个实体读进内存。
  ///
  /// 分片用独立的只读连接打开（[openShard]），主库连接完全不参与——主库是
  /// SQLCipher 加密库，在它上面 `ATTACH` 明文分片会被套上主库密钥并直接报错。
  Future<({List<_ShardRecord> records, int rowCount, _ShardOntology ontology})>
  _readShard(ShardInput shard) async {
    final sqlite.Database shardDb;
    try {
      shardDb = openShard(shard.path);
    } on sqlite.SqliteException catch (error) {
      throw CatalogImportException(
        CatalogImportFailureKind.unreadableShard,
        'cannot open shard ${shard.meta.file}: ${error.message}',
      );
    }
    try {
      final int rowCount;
      try {
        rowCount =
            shardDb.select('SELECT COUNT(*) AS n FROM foods').first['n'] as int;
      } on sqlite.SqliteException catch (error) {
        throw CatalogImportException(
          CatalogImportFailureKind.unreadableShard,
          'cannot read shard ${shard.meta.file}: ${error.message}',
        );
      }
      if (rowCount != shard.meta.rows) {
        throw CatalogImportException(
          CatalogImportFailureKind.rowCountMismatch,
          'shard row count mismatch: ${shard.meta.file} '
          'manifest=${shard.meta.rows} actual=$rowCount',
        );
      }
      final rows = shardDb.select(
        'SELECT id, name, state, locale, category, brand, kcal_per100g,'
        ' protein_per100g, carbs_per100g, fat_per100g, source_id,'
        ' license_status FROM foods',
      );
      final records = rows
          .map(
            (row) => _ShardRecord(
              id: row['id'] as String,
              name: row['name'] as String,
              state: row['state'] as String,
              locale: row['locale'] as String?,
              category: row['category'] as String?,
              brand: row['brand'] as String?,
              kcal: (row['kcal_per100g'] as num?)?.toDouble(),
              protein: (row['protein_per100g'] as num?)?.toDouble(),
              carbs: (row['carbs_per100g'] as num?)?.toDouble(),
              fat: (row['fat_per100g'] as num?)?.toDouble(),
              sourceId: row['source_id'] as String,
              licenseStatus: row['license_status'] as String? ?? 'unknown',
            ),
          )
          .toList();
      return (
        records: records,
        rowCount: rowCount,
        ontology: _readOntology(shardDb, shard.meta.file),
      );
    } finally {
      shardDb.dispose();
    }
  }

  /// 读分片里的三个实体表（docs/07 §5.5）。
  ///
  /// 表不存在时返回空集合而不是报错：2.0-1j 之前的发布物只有 `foods`/
  /// `aliases`，用户支持目录里也可能留着旧分片，导入器要能照常吃下去。
  /// 日期列由 ETL 写成 ISO-8601 文本（`datetime.now(timezone.utc)` 的
  /// `%Y-%m-%dT%H:%M:%SZ`），这里按文本解析。
  _ShardOntology _readOntology(sqlite.Database shardDb, String shardFile) {
    final Set<String> present;
    try {
      present = shardDb
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((row) => row['name'] as String)
          .toSet();
    } on sqlite.SqliteException catch (error) {
      throw CatalogImportException(
        CatalogImportFailureKind.unreadableShard,
        'cannot read shard $shardFile: ${error.message}',
      );
    }
    final ontology = _ShardOntology();
    if (!present.contains('revisions') ||
        !present.contains('evidence') ||
        !present.contains('portions')) {
      return ontology;
    }

    final evidenceRows = shardDb.select(
      'SELECT id, source_id, license, attribution, retrieved_at,'
      ' transform_version, quality_status, record_hash FROM evidence',
    );
    for (final row in evidenceRows) {
      final id = row['id'] as String;
      final retrievedAt = _parseInstant(row['retrieved_at'], 'evidence.$id');
      final recordHash = row['record_hash'] as String? ?? '';
      if (!_hex64.hasMatch(recordHash)) {
        throw CatalogImportException(
          CatalogImportFailureKind.invalidRow,
          'evidence $id has invalid record_hash',
        );
      }
      ontology.evidenceById[id] = _ShardEvidence(
        id: id,
        sourceId: row['source_id'] as String,
        license: row['license'] as String,
        attribution: row['attribution'] as String?,
        retrievedAt: retrievedAt,
        transformVersion: row['transform_version'] as String,
        qualityStatus: row['quality_status'] as String,
        recordHash: recordHash,
      );
    }
    ontology.evidenceCount = ontology.evidenceById.length;

    final revisionRows = shardDb.select(
      'SELECT id, food_id, revision_number, kcal_per100g, protein_per100g,'
      ' carbs_per100g, fat_per100g, source_evidence_id, quality_status,'
      ' valid_from FROM revisions',
    );
    for (final row in revisionRows) {
      final foodId = row['food_id'] as String;
      ontology.revisionByFood[foodId] = _ShardRevision(
        id: row['id'] as String,
        revisionNumber: (row['revision_number'] as num).toInt(),
        kcal: (row['kcal_per100g'] as num?)?.toDouble(),
        protein: (row['protein_per100g'] as num?)?.toDouble(),
        carbs: (row['carbs_per100g'] as num?)?.toDouble(),
        fat: (row['fat_per100g'] as num?)?.toDouble(),
        sourceEvidenceId: row['source_evidence_id'] as String?,
        qualityStatus: row['quality_status'] as String,
        validFrom: row['valid_from'] == null
            ? null
            : _parseInstant(row['valid_from'], 'revision.$foodId'),
      );
    }
    ontology.revisionCount = ontology.revisionByFood.length;

    final portionRows = shardDb.select(
      'SELECT id, food_id, name, grams, locale, source FROM portions',
    );
    for (final row in portionRows) {
      final foodId = row['food_id'] as String;
      ontology.portionCount += 1;
      (ontology.portionsByFood[foodId] ??= <_ShardPortion>[]).add(
        _ShardPortion(
          id: row['id'] as String,
          name: row['name'] as String,
          grams: (row['grams'] as num).toDouble(),
          locale: row['locale'] as String?,
          source: row['source'] as String? ?? 'unknown',
        ),
      );
    }
    return ontology;
  }

  DateTime _parseInstant(Object? value, String where) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    throw CatalogImportException(
      CatalogImportFailureKind.invalidRow,
      'invalid timestamp for $where: $value',
    );
  }
}

class _ShardRecord {
  const _ShardRecord({
    required this.id,
    required this.name,
    required this.state,
    required this.locale,
    required this.category,
    required this.brand,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.sourceId,
    required this.licenseStatus,
  });

  final String id;
  final String name;
  final String state;
  final String? locale;
  final String? category;
  final String? brand;
  final double? kcal;
  final double? protein;
  final double? carbs;
  final double? fat;
  final String sourceId;
  final String licenseStatus;
}

class _ShardOutcome {
  const _ShardOutcome({
    required this.importedRows,
    required this.skippedExistingRows,
    required this.incompleteSkippedRows,
    required this.rowCount,
    required this.portionRows,
    required this.revisionRows,
    required this.evidenceRows,
  });

  final int importedRows;
  final int skippedExistingRows;
  final int incompleteSkippedRows;
  final int rowCount;
  final int portionRows;
  final int revisionRows;
  final int evidenceRows;
}

/// 一个分片里的三个实体（docs/07 §5.5）：份量与修订按 food id 索引，证据按自己的
/// id 索引——`revisions.source_evidence_id` 是两者之间唯一的链（表里没有
/// `evidence.food_id`，证据描述的是「一次采集」而不是「一个食物」）。
class _ShardOntology {
  final Map<String, _ShardEvidence> evidenceById = {};
  final Map<String, _ShardRevision> revisionByFood = {};
  final Map<String, List<_ShardPortion>> portionsByFood = {};
  int evidenceCount = 0;
  int revisionCount = 0;
  int portionCount = 0;
}

class _ShardEvidence {
  const _ShardEvidence({
    required this.id,
    required this.sourceId,
    required this.license,
    required this.attribution,
    required this.retrievedAt,
    required this.transformVersion,
    required this.qualityStatus,
    required this.recordHash,
  });

  final String id;
  final String sourceId;
  final String license;
  final String? attribution;
  final DateTime retrievedAt;
  final String transformVersion;
  final String qualityStatus;
  final String recordHash;
}

class _ShardRevision {
  const _ShardRevision({
    required this.id,
    required this.revisionNumber,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.sourceEvidenceId,
    required this.qualityStatus,
    required this.validFrom,
  });

  final String id;
  final int revisionNumber;
  final double? kcal;
  final double? protein;
  final double? carbs;
  final double? fat;
  final String? sourceEvidenceId;
  final String qualityStatus;
  final DateTime? validFrom;
}

class _ShardPortion {
  const _ShardPortion({
    required this.id,
    required this.name,
    required this.grams,
    required this.locale,
    required this.source,
  });

  final String id;
  final String name;
  final double grams;
  final String? locale;
  final String source;
}

/// 这次失败是不是「磁盘/数据库写满」（SQLITE_FULL 或文件系统 ENOSPC）。
///
/// 目录链路上有两个会写盘的地方——导入器的 SQLite 写事务、来源层复制分片
/// 与写标记文件的 dart:io 写——它们对用户是同一件事（「空间不够」），所以
/// 分类只留这一处，避免两边的判断漂移。
bool isDiskFullError(Object error) {
  if (error is sqlite.SqliteException) return error.resultCode == 13;
  final cause = diskFullRemoteCause(error);
  if (cause is sqlite.SqliteException) return cause.resultCode == 13;
  return mentionsDiskFull(cause ?? error);
}

/// 取 drift 远程异常的 `remoteCause`；不是那种异常就返回 null。
///
/// 用鸭子类型而不是 `is DriftRemoteException`：`package:drift/isolate.dart`
/// 才导出这个类型，而调用方只依赖 `package:drift/drift.dart`（不为一个
/// 分类判断把 isolate 库拉进依赖面）。
Object? diskFullRemoteCause(Object error) {
  try {
    final dynamic dynamicError = error;
    final Object? cause = dynamicError.remoteCause;
    return cause;
  } catch (_) {
    return null;
  }
}

/// 兜底：跨 isolate 的异常只剩文本，按关键字认。
bool mentionsDiskFull(Object error) {
  final text = error.toString();
  return text.contains('database or disk is full') ||
      text.contains('SQLITE_FULL') ||
      text.contains('disk is full') ||
      text.contains('No space left on device') ||
      text.contains('ENOSPC');
}
