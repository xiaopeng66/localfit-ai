import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:localfit_ai/core/logging/privacy_logger.dart';
import 'package:localfit_ai/features/backup/domain/backup_limits.dart';

/// User-facing storage for `.lfb` backup files. The UI never touches the
/// picker plugin directly so tests can substitute an in-memory store.
abstract interface class BackupFileStore {
  /// Asks the user where to save an export. Returns the chosen path, or null
  /// when the user cancelled.
  Future<String?> saveExport({
    required String defaultFileName,
    required Uint8List bytes,
  });

  /// Asks the user to pick an existing backup file. Returns its bytes, or
  /// null when the user cancelled.
  Future<Uint8List?> pickRestoreFile();
}

final class FilePickerBackupFileStore implements BackupFileStore {
  const FilePickerBackupFileStore({
    this.logger,
    this.maxFileBytes = BackupLimits.maxEnvelopeBytes,
  });

  static const backupExtension = 'lfb';

  final PrivacyLogger? logger;

  /// 允许读入的备份文件上限。用户可以在选择器里挑中任意文件（含被改名成
  /// `.lfb` 的大文件），`readAsBytes` 会把整份读进内存——所以在读之前先
  /// 用文件长度判据拒绝。可注入是为了测试（真上限 384 MiB 造不出来）。
  final int maxFileBytes;

  /// 纯判据（无 I/O）：超限时返回给用户看的中文原因，否则返回 null。
  /// 单测直接测它，免去 mock 选择器插件。
  static String? sizeViolation({
    required int bytes,
    required int maxFileBytes,
  }) {
    if (bytes <= maxFileBytes) return null;
    final limitMib = maxFileBytes ~/ (1024 * 1024);
    final actualMib = bytes / (1024 * 1024);
    return '备份文件过大（约 ${actualMib.toStringAsFixed(1)} MiB，'
        '上限 $limitMib MiB），请确认选择的是应用导出的 .lfb 文件。';
  }

  @override
  Future<String?> saveExport({
    required String defaultFileName,
    required Uint8List bytes,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: defaultFileName,
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: [backupExtension],
    );
    return uri?.toString();
  }

  @override
  Future<Uint8List?> pickRestoreFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: [backupExtension],
    );
    if (file == null) return null;
    // 只问大小、不读内容：`length()` 优先用选择器报回的 size，避免为判据
    // 读整份文件。
    final length = await file.length();
    final violation = sizeViolation(bytes: length, maxFileBytes: maxFileBytes);
    if (violation != null) {
      logger?.log(
        LogLevel.warning,
        'backup_restore_file_too_large',
        fields: {'sizeBytes': length, 'maxBytes': maxFileBytes},
      );
      throw FormatException(violation);
    }
    final bytes = await file.readAsBytes();
    logger?.log(
      LogLevel.info,
      'backup_file_picked',
      fields: {'sizeBytes': bytes.length},
    );
    return bytes;
  }
}
