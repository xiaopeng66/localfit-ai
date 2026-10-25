/// 备份包与恢复文件的共同大小上限（单一事实源）。
///
/// 导出侧（[LfbBackupCodec.encode]）、恢复侧（[LfbBackupCodec.decode]）与
/// 选文件侧（`FilePickerBackupFileStore.pickRestoreFile`）以前各算各的：
/// 只有 `encode` 校验明文大小，`decode` 与选文件都不校验 ⇒ 一个几个 GB 的
/// `.lfb` 会被整份读进内存（`readAsBytes`）再解析，任何校验之前就先 OOM。
///
/// 数字必须**同源**：明文上限换算出封套上限（密文是密文的 base64），否则
/// 「导得出、恢复不回来」这种自相矛盾的状态会随任意一侧的改动悄悄出现。
abstract final class BackupLimits {
  /// 明文载荷（解压后的备份 JSON）上限。256 MiB 与 2.0 全量 ETL 的库相称
  /// （随包食物库 49k 行、导出 JSON 数十 MB 量级），保持既有契约不变。
  static const maxPayloadBytes = 256 * 1024 * 1024;

  /// `.lfb` 文件本身（封套 JSON）的上限：密文是明文的 base64（4/3），
  /// 再留 12% 余量覆盖封套字段（format/version/kdf/nonce/mac/checksum）
  /// 与 JSON 转义。恢复侧**先按文件长度判据拒绝，再读字节**。
  static const maxEnvelopeBytes = maxPayloadBytes * 3 ~/ 2;
}
