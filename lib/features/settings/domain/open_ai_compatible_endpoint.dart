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
        !_isAllowedScheme(uri) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        // 非回环仍只认 443：外部端点用非标端口没有产品需求，保持收窄。
        (uri.hasPort && uri.port != 443 && !isLoopbackHost(uri.host)) ||
        !_isSafePath(uri.path)) {
      return null;
    }

    final path = _normalizedPath(_stripProtocolTail(uri.path));
    final baseUri = Uri(
      scheme: uri.scheme.toLowerCase(),
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

  /// 允许的 scheme：https（沿用 443 端口限制）；
  /// **明文只放行回环地址**（127.0.0.0/8、localhost、[::1]）——本机模型网关
  /// 的流量不出设备，不构成出网面。远程明文一律拒绝。
  ///
  /// 注意：Android 侧 `usesCleartextTraffic="false"` 仍然会拦回环明文，
  /// 这条放宽只对桌面/测试构建生效（见 docs/09 发布清单）。
  static bool _isAllowedScheme(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return true;
    return scheme == 'http' && isLoopbackHost(uri.host);
  }

  /// 是否本机回环主机（不含 `0.0.0.0` 这类"监听所有网卡"的写法）。
  static bool isLoopbackHost(String host) {
    final value = host.toLowerCase();
    if (value == 'localhost') return true;
    if (value == '::1' || value == '[::1]') return true;
    final parts = value.split('.');
    if (parts.length != 4) return false;
    if (parts.first != '127') return false;
    return parts.every((part) {
      final octet = int.tryParse(part);
      return octet != null && octet >= 0 && octet <= 255;
    });
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
