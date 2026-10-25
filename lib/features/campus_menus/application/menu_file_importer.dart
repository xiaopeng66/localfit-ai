import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/application/menu_import_publisher.dart';
import 'package:localfit_ai/features/campus_menus/domain/menu_raw_content_store.dart';
import 'package:localfit_ai/features/menu_normalize/data/menu_normalize_json_decoder.dart';

/// 导入失败的类别：决定上屏文案。原始 message 是开发者文本（英文、可能带
/// 本机绝对路径），只进 job 记录与断言，绝不直接给用户看（docs/11 §3-B）。
enum MenuImportFailureKind {
  fileUnreadable,
  unsupportedFormat,
  invalidContent,
  sourceMissing,
  fileTooLarge,
}

/// 导入文件的大小上限。菜单原文是纯文本，真实场景（一个食堂几个月的 CSV）
/// 也就几百 KB；上限存在的意义是别让用户选中一个几百 MB 的文件之后被
/// `readAsBytesSync` 整份读进内存。
const int menuImportMaxBytesMiB = 8;
const int menuImportMaxBytes = menuImportMaxBytesMiB * 1024 * 1024;

/// 文件导入失败（解析错误聚合在上层 job 记录中）。
class MenuFileImportException implements Exception {
  const MenuFileImportException(
    this.message, {
    this.kind = MenuImportFailureKind.invalidContent,
  });

  final String message;
  final MenuImportFailureKind kind;

  /// 用户可见文案：按类别给固定文案，不回显 [message]。
  String get userMessage => switch (kind) {
    MenuImportFailureKind.fileUnreadable => '导入失败：找不到或无法读取该文件。',
    MenuImportFailureKind.unsupportedFormat => '导入失败：只支持 TXT/CSV/JSON 文件。',
    MenuImportFailureKind.invalidContent => '导入失败：文件内容不符合导入格式，请检查后重试。',
    MenuImportFailureKind.sourceMissing => '导入失败：本地食堂记录缺失，请重新选择食堂。',
    MenuImportFailureKind.fileTooLarge =>
      '导入失败：文件过大（上限 $menuImportMaxBytesMiB MiB），请拆分后重试。',
  };

  @override
  String toString() => 'MenuFileImportException: $message';
}

/// 2.0-3c：本地 TXT/CSV/JSON 文件导入（P0 输入方式，docs/07 §6.2）。
///
/// 本机解析（无网络、无 AI）；原文写入 [rawContentStore]，数据库只存
/// 相对路径与 hash（docs/07 §6.1）。解析产物交 [MenuImportPublisher] 走统一
/// 发布链路。
final class MenuFileImporter {
  MenuFileImporter({
    required AppDatabase database,
    required this.rawContentStore,
    MenuImportPublisher? publisher,
  }) : _database = database,
       _publisher = publisher ?? MenuImportPublisher(database: database);

  final AppDatabase _database;
  final MenuImportPublisher _publisher;

  /// 原文存储（应用私有目录；数据库只存相对路径与 hash，docs/07 §6.1）。
  final MenuRawContentStore rawContentStore;

  final Sha256 _sha256 = Sha256();

  static const Set<String> _supportedExtensions = {'.txt', '.csv', '.json'};

  Future<MenuPublishResult> importFile({
    required String venueId,
    required String sourceId,
    required String filePath,
    bool skipIfHashMatches = false,
    DateTime? now,
  }) async {
    // 可注入的时钟：调用方（控制器/测试）给了就用它，否则用真实时间。
    // 业务日期、失败 job 与原文保存时间都取自这里，避免「用 now 查、用
    // 真实时钟写」两套时间对不上（2.0-1j 修：菜单 tab 的 8 个用例在跨日
    // 之后全红，就是因为导入写的是当天、查询用的是注入的固定日期）。
    final clock = (now ?? DateTime.now()).toUtc();
    final file = File(filePath);
    if (!file.existsSync()) {
      throw MenuFileImportException(
        'file not found: $filePath',
        kind: MenuImportFailureKind.fileUnreadable,
      );
    }
    final extension = file.path.split('.').last.toLowerCase();
    if (!_supportedExtensions.contains('.$extension')) {
      throw MenuFileImportException(
        'unsupported file extension: .$extension '
        '(supported: txt/csv/json; pdf/image 属 P1 输入方式)',
        kind: MenuImportFailureKind.unsupportedFormat,
      );
    }

    // 先读字节再显式按 UTF-8 解码，把「读不了」和「不是 UTF-8 文本」分开：
    // Excel 导出的中文 CSV 常见是 GBK，`readAsStringSync` 默认按 UTF-8 解码，
    // 解码失败裸抛 FileSystemException 会绕过按类别固定的上屏文案与 failed
    // job 留痕（与「解析失败也要留痕」的约定不一致）。
    final List<int> rawBytes;
    try {
      // 先问长度再读：`readAsBytesSync` 会把整份文件读进内存，超大文件在
      // 任何解析之前就能把内存吃光。
      final length = file.lengthSync();
      if (length > menuImportMaxBytes) {
        throw MenuFileImportException(
          'file too large: $filePath ($length bytes > $menuImportMaxBytes bytes)',
          kind: MenuImportFailureKind.fileTooLarge,
        );
      }
      rawBytes = file.readAsBytesSync();
    } on FileSystemException catch (error) {
      throw MenuFileImportException(
        'file not readable: $filePath ($error)',
        kind: MenuImportFailureKind.fileUnreadable,
      );
    }
    final String rawText;
    try {
      rawText = utf8.decode(rawBytes);
    } on FormatException {
      const error = MenuFileImportException(
        'file is not valid UTF-8 text',
        kind: MenuImportFailureKind.invalidContent,
      );
      await _recordFailedJob(sourceId, error.message, clock);
      throw error;
    }
    final rawHash = await _hashText(rawText);

    // 草案 venue 名：JSON 模板自带时以文件为准，否则回落到数据库
    // venue 行名（CSV/TXT 格式无 venue 字段，必须由导入器填入，
    // 否则发布链路的 venue_name 非空校验会拒绝）。
    final venueRow = await (_database.select(
      _database.venues,
    )..where((row) => row.id.equals(venueId))).getSingleOrNull();
    if (venueRow == null) {
      throw MenuFileImportException(
        'venue not found: $venueId',
        kind: MenuImportFailureKind.sourceMissing,
      );
    }
    final venueName = venueRow.name;

    final MenuNormalizeDraft draft;
    final parseErrors = <String>[];
    try {
      draft = switch (extension) {
        'json' => _parseJson(rawText, venueName),
        'csv' => _parseCsv(rawText, venueName, clock),
        _ => _parseTxt(rawText, venueName, clock),
      };
    } on MenuFileImportException catch (error) {
      // 解析失败也要留痕：source 上记一条 failed job（docs/07 §6.2
      // 导入可观测），旧快照不动，异常上抛给调用方。
      await _recordFailedJob(sourceId, error.message, clock);
      rethrow;
    } catch (error) {
      parseErrors.add('parse failed: $error');
      await _recordFailedJob(sourceId, parseErrors.first, clock);
      throw MenuFileImportException(parseErrors.first);
    }

    // businessDate = 草案自己的 source_date：JSON 模板里写的就是这份菜单
    // 的日期（decoder 会校验成 ISO 日期），TXT/CSV 没有该字段、按当天填。
    // 这与另一条发布入口 publish_menu_normalize_draft 取的是同一个值。
    final businessDate = draft.sourceDate;

    final result = await _publisher.publishDraft(
      venueId: venueId,
      sourceId: sourceId,
      businessDate: businessDate,
      draft: draft,
      skipIfHashMatches: skipIfHashMatches,
      // 同一条导入链路上的时间戳共用一个时钟：业务日期、入库时间、
      // job 起止时间不该各自取一次真实时间。
      now: clock,
    );

    // 发布成功后保存原文（私有目录；数据库只存相对路径与 hash）——
    // 前提是来源声明允许保存原文（docs/07 §6.1 末句）。
    if (result.snapshotId != null && await _allowsRawContent(sourceId)) {
      await _saveRawContent(result.snapshotId!, rawText, rawHash, clock);
    }
    return result;
  }

  /// 来源是否允许保存原文（`menu_sources.allow_raw_content`，docs/07 §6.1：
  /// 用户可以选择「不保存原文，只保存已确认的结构化菜单」）。来源行缺失
  /// 按不允许处理：宁可少存一份用户原文。
  Future<bool> _allowsRawContent(String sourceId) async {
    final row = await (_database.select(
      _database.menuSources,
    )..where((source) => source.id.equals(sourceId))).getSingleOrNull();
    return row?.allowRawContent ?? false;
  }

  MenuNormalizeDraft _parseJson(String rawText, String venueName) {
    final document = jsonDecode(rawText);
    if (document is! Map<String, dynamic>) {
      throw const MenuFileImportException('json root must be an object');
    }
    // 模板即 menu-normalize.v1 的去 schema_version 形状；补默认版本交给
    // 统一 decoder 校验全部约束。venue_name 缺省时回落到数据库 venue 名。
    final payload = {
      'schema_version': 1,
      ...document,
      if ((document['venue_name'] as String? ?? '').trim().isEmpty)
        'venue_name': venueName,
    };
    return const MenuNormalizeJsonDecoder().decode(jsonEncode(payload));
  }

  MenuNormalizeDraft _parseCsv(
    String rawText,
    String venueName,
    DateTime clock,
  ) {
    // 简单 CSV：表头 窗口,开始,结束,菜名；同名窗口聚合为一个服务。
    // （2026-10-16 用户删掉价格：`价格分` 列整条撤掉。）
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      throw const MenuFileImportException('csv is empty');
    }
    final header = lines.first.split(',').map((c) => c.trim()).toList();
    const expected = ['窗口', '开始', '结束', '菜名'];
    if (header.length != expected.length ||
        !List.generate(
          expected.length,
          (i) => header[i] == expected[i],
        ).every((ok) => ok)) {
      throw MenuFileImportException(
        'csv header must be ${expected.join(",")}: got ${header.join(",")}',
      );
    }

    final services = <String, MenuNormalizeServiceBuilder>{};
    for (var i = 1; i < lines.length; i++) {
      final cells = lines[i].split(',').map((c) => c.trim()).toList();
      if (cells.length != 4) {
        throw MenuFileImportException(
          'csv row ${i + 1} must have 4 cells: ${lines[i]}',
        );
      }
      final name = cells[0];
      final open = cells[1];
      final close = cells[2];
      final item = cells[3];
      if (!_hhmm.hasMatch(open) || !_hhmm.hasMatch(close)) {
        throw MenuFileImportException(
          'csv row ${i + 1} has invalid time (HH:MM required)',
        );
      }
      if (item.isEmpty) {
        throw MenuFileImportException('csv row ${i + 1} item name is empty');
      }
      final builder = services.putIfAbsent(
        name,
        () => MenuNormalizeServiceBuilder(),
      );
      builder.open ??= open;
      builder.close ??= close;
      builder.items.add({'display_name': item});
    }
    if (services.isEmpty) {
      throw const MenuFileImportException('csv has no data rows');
    }
    return _buildDraft(services, venueName, clock);
  }

  MenuNormalizeDraft _parseTxt(
    String rawText,
    String venueName,
    DateTime clock,
  ) {
    // 约定：`# 窗口名 HH:MM-HH:MM` 开始一个窗口；其后每行 `菜名`。
    // （2026-10-16 删掉价格：行尾的裸数字不再解析——写了几列就是几列。）
    final services = <String, MenuNormalizeServiceBuilder>{};
    String? current;
    for (final line in rawText.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
      if (trimmed.startsWith('#')) {
        // trimmed 仍带 '#' 前缀，正则直接对其整体匹配。
        final match = RegExp(
          r'^#\s*(.+?)\s+(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})$',
        ).firstMatch(trimmed);
        if (match == null) {
          throw MenuFileImportException(
            'txt service line must be "# 窗口名 HH:MM-HH:MM": $trimmed',
          );
        }
        final name = match.group(1)!;
        final open = match.group(2)!;
        final close = match.group(3)!;
        if (!_hhmm.hasMatch(open) || !_hhmm.hasMatch(close)) {
          throw MenuFileImportException('txt service time invalid: $trimmed');
        }
        final builder = services.putIfAbsent(
          name,
          () => MenuNormalizeServiceBuilder(),
        );
        builder.open ??= open;
        builder.close ??= close;
        current = name;
        continue;
      }
      if (current == null) {
        throw MenuFileImportException(
          'txt item line before any service line: $trimmed',
        );
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      final item = parts.first;
      // （价格已不再解析。）
      if (item.isEmpty) {
        throw const MenuFileImportException('txt item name is empty');
      }
      services[current]!.items.add({'display_name': item});
    }
    if (services.isEmpty) {
      throw const MenuFileImportException('txt has no service lines');
    }
    return _buildDraft(services, venueName, clock);
  }

  MenuNormalizeDraft _buildDraft(
    Map<String, MenuNormalizeServiceBuilder> services,
    String venueName,
    DateTime clock,
  ) {
    return MenuNormalizeDraft(
      schemaVersion: 1,
      sourceDate: _todayIso(clock),
      venueName: venueName,
      services: [
        for (final entry in services.entries)
          MenuNormalizeService(
            serviceName: entry.key,
            openTime: entry.value.open!,
            closeTime: entry.value.close!,
            items: [
              for (final item in entry.value.items)
                MenuNormalizeItem(
                  displayName: item['display_name']! as String,
                  stationName: null,
                  reportedNutrition: null,
                  ingredientHints: const [],
                  allergenHints: const [],
                  needsConfirmation: true,
                  questions: const [],
                ),
            ],
          ),
      ],
      warnings: const [],
    );
  }

  /// 解析失败留痕（docs/07 §6.2 导入可观测）。job 行由 publisher 落库：job id 的
  /// 唯一性由它保证（同一毫秒连续两次导入不该撞主键）。
  Future<void> _recordFailedJob(
    String sourceId,
    String message,
    DateTime clock,
  ) async {
    assert(message.isNotEmpty);
    await _publisher.recordFailedJob(
      sourceId: sourceId,
      message: message,
      now: clock,
    );
  }

  /// 业务日期是「本地日」口径，必须与 `MenuTabController._todayIso` 同源。
  ///
  /// 调用方传进来的时钟在上面被 `.toUtc()` 归一过（时间戳落库用 UTC），所以
  /// 这里要转回本地再取年月日：否则在 UTC 日与本地日不同的那段时间里
  /// （如本地 09-15 04:00 = UTC 09-14 20:00），导入写下 businessDate=09-14
  /// 而查询按本地日查 09-15，刚导入的菜单立刻查不到（docs/11 §3-D）。
  String _todayIso(DateTime clock) {
    final now = clock.toLocal();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<String> _hashText(String text) async {
    final digest = await _sha256.hash(utf8.encode(text));
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _saveRawContent(
    String snapshotId,
    String rawText,
    String hash,
    DateTime clock,
  ) async {
    // 相对路径入库（docs/07 §6.1：数据库只保存相对路径、哈希和摘要）；
    // 绝对路径会绑定当前设备与沙箱目录，备份到别的设备后即失效。
    final rawContentPath = await rawContentStore.save(
      snapshotId: snapshotId,
      rawText: rawText,
    );
    await _publisher.database.customUpdate(
      'UPDATE menu_snapshots SET raw_content_path = ?, raw_content_hash = ?,'
      ' updated_at = ? WHERE id = ?',
      variables: [
        Variable.withString(rawContentPath),
        Variable.withString(hash),
        Variable.withDateTime(clock),
        Variable.withString(snapshotId),
      ],
    );
  }
}

class MenuNormalizeServiceBuilder {
  String? open;
  String? close;
  final List<Map<String, Object?>> items = [];
}

final RegExp _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
