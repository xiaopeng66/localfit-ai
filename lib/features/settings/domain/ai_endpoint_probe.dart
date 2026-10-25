import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';

/// 连通性测试 + 模型拉取（docs/29 §P4 需求 7）。
///
/// `GET {base}/models`：唯一与供应商「闲聊」的请求——只读、无副作用、
/// 失败分档可解释（401 Key 错 / 404 base 错 / 超时网络不可达），结果
/// 内联显示在设置弹层里，不弹系统提示。
abstract interface class AiEndpointProbe {
  Future<AiEndpointProbeResult> probe({
    required String baseUrl,
    required AiProviderProtocol protocol,
    required String apiKey,
  });
}

/// 探测结果。成功时 [models] 为去重排序后的模型 id 列表（可能为空）；
/// 失败时 [message] 是可直接上屏的中文原因、[models] 为空。
final class AiEndpointProbeResult {
  const AiEndpointProbeResult.ok({required this.models})
    : message = null,
      isSuccess = true;

  const AiEndpointProbeResult.failure(this.message)
    : models = const [],
      isSuccess = false;

  final List<String> models;
  final String? message;
  final bool isSuccess;
}
