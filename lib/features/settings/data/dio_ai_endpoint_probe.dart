import 'package:dio/dio.dart';
import 'package:localfit_ai/features/ai/data/ai_protocol_wire.dart';
import 'package:localfit_ai/features/settings/domain/ai_endpoint_probe.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/open_ai_compatible_endpoint.dart';

/// [AiEndpointProbe] 的 Dio 实现：`GET {base}/models`，5 秒超时，失败分档。
///
/// 复用 [OpenAiCompatibleEndpoint] 的规范化（协议尾巴剥离、HTTPS-only），
/// 认证头走与正式请求同一张 wire 表——探测通过就等于「这个 Key + 这个
/// Base URL + 这个协议」的组合在正式请求里也成立。
final class DioAiEndpointProbe implements AiEndpointProbe {
  DioAiEndpointProbe({required this.dio});

  final Dio dio;

  /// docs/29 §P4：连通性测试 5 秒超时（正式请求是 10/30/45s——探测只是
  /// 「通不通」的快检，不该让用户等一轮正式请求的时间）。
  static const timeout = Duration(seconds: 5);

  @override
  Future<AiEndpointProbeResult> probe({
    required String baseUrl,
    required AiProviderProtocol protocol,
    required String apiKey,
  }) async {
    final endpoint = OpenAiCompatibleEndpoint.tryParse(
      baseUrl,
      protocol: protocol,
    );
    if (endpoint == null) {
      return const AiEndpointProbeResult.failure(
        'Base URL 无效：需要 HTTPS 地址（如 https://api.example.com/v1）。',
      );
    }
    if (apiKey.trim().isEmpty) {
      return const AiEndpointProbeResult.failure('请先填写 API Key。');
    }

    final modelsUri = endpoint.baseUri.resolve('models');
    final Response<dynamic> response;
    try {
      response = await dio.requestUri<dynamic>(
        modelsUri,
        options: Options(
          method: 'GET',
          headers: {
            Headers.acceptHeader: Headers.jsonContentType,
            ...protocol.authHeaders(apiKey.trim()),
          },
          connectTimeout: timeout,
          receiveTimeout: timeout,
          followRedirects: false,
          maxRedirects: 0,
          receiveDataWhenStatusError: false,
          // 4xx/5xx 不抛异常，交给下面的分档口径解释。
          validateStatus: (status) => status != null && status < 400,
        ),
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return const AiEndpointProbeResult.failure('连接超时：网络不可达或 Base URL 有误。');
      }
      if (error.type == DioExceptionType.badCertificate) {
        return const AiEndpointProbeResult.failure('安全连接无法验证。');
      }
      if (status != null) {
        return AiEndpointProbeResult.failure(_statusMessage(status));
      }
      return const AiEndpointProbeResult.failure('网络连接不可用，请检查网络后重试。');
    } catch (_) {
      return const AiEndpointProbeResult.failure('网络连接不可用，请检查网络后重试。');
    }

    final status = response.statusCode ?? 0;
    if (status >= 400) {
      return AiEndpointProbeResult.failure(_statusMessage(status));
    }
    final models = _parseModelIds(response.data);
    if (models == null) {
      return const AiEndpointProbeResult.failure(
        '连通了，但 /models 返回格式无法识别（不影响手输模型使用）。',
      );
    }
    return AiEndpointProbeResult.ok(models: models);
  }

  String _statusMessage(int status) {
    if (status == 401 || status == 403) {
      return 'API Key 无效或无权访问该服务。';
    }
    if (status == 404) {
      return '未找到 /models：Base URL 可能不对（应包含 /v1 之类的前缀）。';
    }
    if (status == 429) {
      return '请求过于频繁，请稍后重试。';
    }
    if (status >= 500) {
      return '供应商暂时不可用（HTTP $status），请稍后重试。';
    }
    return '请求被拒绝（HTTP $status）。';
  }

  /// OpenAI 形状 `{"data":[{"id":...},...]}`；兼容直接返回数组的一家网关。
  /// 形状不认识返回 null（区别于「合法但空」= 空列表）。
  List<String>? _parseModelIds(Object? data) {
    List<dynamic>? items;
    if (data is Map) {
      items = data['data'] is List ? data['data'] as List<dynamic> : null;
    } else if (data is List) {
      items = data;
    }
    if (items == null) return null;
    final ids = <String>{};
    for (final item in items) {
      final id = item is Map ? item['id'] : null;
      if (id is String && id.isNotEmpty) ids.add(id);
    }
    final sorted = ids.toList()..sort();
    return sorted;
  }
}
