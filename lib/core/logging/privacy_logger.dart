enum LogLevel { debug, info, warning, error }

typedef LogWriter = void Function(String message);

final class PrivacyLogger {
  PrivacyLogger({
    LogWriter? writer,
    Set<String> allowedKeys = defaultAllowedKeys,
    Set<String> sensitiveKeys = defaultSensitiveKeys,
  }) : _writer = writer ?? _defaultWriter,
       _allowedKeys = allowedKeys.map(_normalizeKey).toSet(),
       _sensitiveKeys = sensitiveKeys.map(_normalizeKey).toSet();

  /// 普通日志**只**写这些字段（docs/07 §12 风险表的「日志白名单」）。
  ///
  /// 生产上三个 AI 出口只写这四个指标（`resultKind`/`durationMs`/
  /// `requestBytes`/`responseBytes`）；`sizeBytes` 是备份文件的大小
  /// （`backup_file_store` 写入成功时记录），属于设备侧文件尺寸指标，
  /// 不含任何用户内容——2026-09-19 白名单评审通过加入（docs/11 P3：
  /// 此前该指标被默认拒绝抹成 `[REDACTED:not-allow-listed]`，等于写不
  /// 出去）。要再增加日志字段就改这一行——改它是一次审计点：新字段是
  /// 否属于「菜单原文/学校/地点/行程/food/menu/exercise ID/健康档案/
  /// AI 正文」必须先回答清楚。
  static const defaultAllowedKeys = {
    'resultKind',
    'durationMs',
    'requestBytes',
    'responseBytes',
    'sizeBytes',
  };

  static const defaultSensitiveKeys = {
    'apiKey',
    'authorization',
    'accessToken',
    'refreshToken',
    'password',
    'image',
    'imageBase64',
    'requestBody',
    'responseBody',
    'healthData',
  };

  /// 命中敏感键名（连白名单也拦不住的第二道闸）。
  static const redacted = '[REDACTED]';

  /// 未列入白名单：值不写，键名保留——审计仍能看出「有人想写这些字段」。
  static const notAllowed = '[REDACTED:not-allow-listed]';

  final LogWriter _writer;
  final Set<String> _allowedKeys;
  final Set<String> _sensitiveKeys;

  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
  }) {
    final safeFields = <String, Object?>{};
    for (final entry in fields.entries) {
      safeFields[entry.key] = _sanitizeValue(entry.key, entry.value);
    }
    _writer('[${level.name.toUpperCase()}] $event $safeFields');
  }

  bool _isSensitive(String key) =>
      _sensitiveKeys.any((sensitive) => _normalizeKey(key).contains(sensitive));

  static String _normalizeKey(String key) =>
      key.replaceAll(RegExp('[^a-zA-Z]'), '').toLowerCase();

  /// 默认拒绝：键名不在白名单里，整棵子树都不写（容器一并拦掉，
  /// 不因为「里面可能有个指标」给未知结构开后门）。
  Object? _sanitizeValue(String key, Object? value) {
    if (_isSensitive(key)) return redacted;
    if (!_allowedKeys.contains(_normalizeKey(key))) return notAllowed;
    if (value is Map) {
      return value.map(
        (nestedKey, nestedValue) => MapEntry(
          nestedKey.toString(),
          _sanitizeValue(nestedKey.toString(), nestedValue),
        ),
      );
    }
    if (value is Iterable) {
      return value
          .map((item) => _sanitizeValue(key, item))
          .toList(growable: false);
    }
    return value;
  }

  static void _defaultWriter(String message) {
    assert(() {
      // ignore: avoid_print
      print(message);
      return true;
    }());
  }
}
