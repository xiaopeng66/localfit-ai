import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';

/// BYOK Base URL 的解析与规范化（docs/24 §3）。
///
/// 本地硬约束（与协议无关，先于任何网络动作）：
/// * 只接受 `https`（明文 `http` 直接拒绝，不给「先用着」的口子）；
/// * 端口只能是 443 或省略（Custom port 一律拒绝——它让「同源」判断失去
///   意义，也给不出与供应商文档一致的保证）；
/// * 不允许 userinfo / query / fragment / 点段 / 反斜杠 / `%2e`·`%2f`·`%5c`
///   这类编码歧义（它们能把「看起来同源」变成实际不同源）。
///
/// 路径侧新增（v18）：用户把**完整端点**粘进来是常态
/// （`https://host/v1/chat/completions`）。解析时把末尾的协议尾巴剥掉，
/// 得到 API 根（`https://host/v1/`），再由 [AiProviderProtocol.requestPath]
/// 拼出当前协议真正要请求的路径——这样用户在设置页切换协议时不必改
/// Base URL，也不会拼出 `/v1/chat/completions/chat/completions`。
final class OpenAiCompatibleEndpoint {
  const OpenAiCompatibleEndpoint._({
    required this.baseUrl,
    required this.protocol,
  });

  /// 旧名保留：历史调用点按「默认协议」理解这个常量。
  static const requestPath = 'chat/completions';

  /// 默认协议的完整端点后缀，用于识别「粘贴了完整端点」的输入。
  static const _protocolTails = <String>[
    'chat/completions',
    'responses',
    'messages',
    'completions',
    'embeddings',
    'audio/transcriptions',
    'audio/speech',
  ];

  final String baseUrl;

  /// 该端点当前按哪种协议解析（决定 [requestUri]）。
  final AiProviderProtocol protocol;

  /// 解析后的 API 根（保证以 `/` 结尾）。
  Uri get baseUri => Uri.parse(baseUrl);

  /// 真正要 POST 的地址：API 根 + 协议路径。
  Uri get requestUri => baseUri.resolve(protocol.requestPath);

  static OpenAiCompatibleEndpoint? tryParse(
    String input, {
    AiProviderProtocol protocol = AiProviderProtocol.chatCompletions,
  }) {
    final source = input.trim();
    if (source.isEmpty ||
        _hasUnsafeCharacters(source) ||
        _hasDotSegment(source) ||
        _hasEncodedAmbiguity(source)) {
      return null;
    }

    final uri = Uri.tryParse(source);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443) ||
        !_isSafePath(uri.path)) {
      return null;
    }

    final path = _normalizedPath(_stripProtocolTail(uri.path));
    final baseUri = Uri(
      scheme: 'https',
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      path: path,
    );
    final baseUrl = baseUri.toString();
    return OpenAiCompatibleEndpoint._(
      baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
      protocol: protocol,
    );
  }

  /// 剥掉粘贴进来的协议端点尾巴（大小写不敏感）。
  ///
  /// 只剥**一次**且只剥最外层：`/v1/chat/completions` → `/v1/`。
  /// `audio/*` 两项保留：用户可能从文档里整段复制 URL，剥掉后 API 根
  /// 不变（P10 已删语音转写，App 自身不再发起这些请求；留在表里只是
  /// 粘贴容错，不构成出网面）。
  static String _stripProtocolTail(String path) {
    var result = path;
    for (final tail in _protocolTails) {
      final lower = result.toLowerCase();
      if (lower.endsWith('/$tail')) {
        result = result.substring(0, result.length - tail.length - 1);
        break;
      }
    }
    return result;
  }

  static bool _hasUnsafeCharacters(String value) =>
      value.contains(RegExp(r'[\x00-\x20\\\\]'));

  static bool _hasDotSegment(String value) => value
      .split('?')
      .first
      .split('#')
      .first
      .split('/')
      .any((segment) => segment == '.' || segment == '..');

  static bool _hasEncodedAmbiguity(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('%2e') ||
        normalized.contains('%2f') ||
        normalized.contains('%5c');
  }

  static bool _isSafePath(String path) {
    if (path.contains('\\')) return false;
    return path
        .split('/')
        .every((segment) => segment != '.' && segment != '..');
  }

  static String _normalizedPath(String path) {
    if (path.isEmpty || path == '/') return '/';
    return '${path.replaceFirst(RegExp(r'/+$'), '')}/';
  }
}
