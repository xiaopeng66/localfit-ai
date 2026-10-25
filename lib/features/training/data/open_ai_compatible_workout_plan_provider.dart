import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai/data/ai_json_object_salvage.dart';
import 'package:localfit_ai/core/logging/privacy_logger.dart';
import 'package:localfit_ai/features/ai/data/ai_protocol_wire.dart';
import 'package:localfit_ai/features/ai/data/open_ai_compatible_transport.dart';
import 'package:localfit_ai/features/ai/domain/ai_transport.dart';
import 'package:localfit_ai/features/ai/domain/prompt_catalog.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/open_ai_compatible_endpoint.dart';
import 'package:localfit_ai/features/training/data/workout_plan_json_decoder.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// Task adapter for workout-plan.v1: owns the library allow-list payload and
/// draft decoding, and delegates every HTTP concern to the shared
/// [OpenAiCompatibleAiTransport].
///
/// prompt 正文不在本文件里：渲染自 [workoutPlanPromptTemplate]（domain 层
/// 单一来源，经 [PromptCatalog]）——docs/11 P3「prompt 内联在 provider、
/// 守护扫不到」的修复点。
final class OpenAiCompatibleWorkoutPlanProvider implements WorkoutPlanProvider {
  OpenAiCompatibleWorkoutPlanProvider({
    required this.dio,
    required this.configurationReader,
    required this.apiKeyStore,
    this.decoder = const WorkoutPlanJsonDecoder(),
    this.logger,
    PromptCatalog? catalog,
    this.template = workoutPlanPromptTemplate,
  }) : _catalog =
           catalog ?? (PromptCatalog()..register(workoutPlanPromptTemplate)) {
    // 调用方传入自己的目录时必须注册了同一份模板：缺失/版本不符在构造期
    // 就暴露（而不是到生成时才 PromptCatalogException）。
    _catalog.register(template);
  }

  static const maxRequestBytes = 64 * 1024;
  static const maxModelLength = 256;
  static const maxOutputTokens = 2000;

  /// 第一次拿回来的东西解不出来时的**一次**强化提醒（2026-10-16 真机实测）：
  /// 模型会（a）先写说明再贴 JSON、（b）把 `exercise_id` 写成自己编的名字。
  /// 前者已由 `normalizeJsonEnvelopeContent` 抢救；后者只能重问一次——这是
  /// 与「对话信封催一次」同一族的兜底：**每轮最多重试一次**，不无限重问。
  static const retryReminder =
      '上次的输出无法解析。请**只**输出那一个 JSON 对象（不要说明、不要'
      'Markdown 围栏），且每个 exercise_id 必须**逐字复制**给定列表里的值，'
      '不得自己发明动作名或 id。';

  final Dio dio;
  final AiProviderConfigurationReader configurationReader;
  final AiApiKeyStore apiKeyStore;
  final WorkoutPlanJsonDecoder decoder;
  final PrivacyLogger? logger;
  final PromptCatalog _catalog;
  final PromptTemplate template;

  late final AiTransport transport = OpenAiCompatibleAiTransport(
    dio: dio,
    failureMessages: const AiTransportFailureMessages(
      timeout: '计划请求超时，请稍后重试。',
      cancelled: '计划请求已取消。',
      requestTooLarge: '训练计划请求过大，请减少目标描述或动作数量。',
    ),
  );

  @override
  Future<AiWorkoutPlanDraft> generate(
    AiWorkoutPlanRequest request, {
    WorkoutPlanCancellationToken? cancellationToken,
  }) async {
    request.validate();
    final startedAt = DateTime.now();
    var requestBytes = 0;
    var responseBytes = 0;
    try {
      final configuration = await _loadConfiguration();
      _throwIfCancelled(cancellationToken);
      final protocol = configuration.protocol;
      final endpoint = _parseEndpoint(configuration);
      final apiKey = await _readApiKey();
      _throwIfCancelled(cancellationToken);
      final requestBody = jsonEncode(
        protocol.taskRequestBody(
          model: configuration.model,
          maxTokens: maxOutputTokens,
          prompt: _prompt(request),
          reasoning: configuration.reasoning,
        ),
      );
      requestBytes = utf8.encode(requestBody).length;

      final response = await transport.complete(
        AiTransportRequest(
          requestUri: endpoint.requestUri,
          body: requestBody,
          requestBytes: requestBytes,
          maxRequestBytes: maxRequestBytes,
          headers: protocol.authHeaders(apiKey),
          protocol: protocol,
        ),
        cancellationToken: _bridgeToken(cancellationToken),
      );
      responseBytes = response.responseBytes;

      // 2026-10-16 真机实测：模型会先写一段说明（还爱包 ```json 围栏）再贴
      // JSON，严格解码器一律判「供应商返回格式无法识别。」。这里用共享的
      // 「抠出恰好一个 JSON 对象」兜底把内容归一，解码器本身一条都不放松。
      final AiWorkoutPlanDraft draft;
      try {
        draft = decoder.decode(
          normalizeJsonEnvelopeContent(response.content),
          request,
        );
      } on FormatException {
        // 一次强化提醒后重问（每轮最多一次）。第二次还解不出来才如实报错。
        final retryBody = jsonEncode(
          protocol.taskRequestBody(
            model: configuration.model,
            maxTokens: maxOutputTokens,
            prompt: '${_prompt(request)}\n\n$retryReminder',
            reasoning: configuration.reasoning,
          ),
        );
        final retryResponse = await transport.complete(
          AiTransportRequest(
            requestUri: endpoint.requestUri,
            body: retryBody,
            requestBytes: utf8.encode(retryBody).length,
            maxRequestBytes: maxRequestBytes,
            headers: protocol.authHeaders(apiKey),
            protocol: protocol,
          ),
          cancellationToken: _bridgeToken(cancellationToken),
        );
        responseBytes = retryResponse.responseBytes;
        _log('format_retry', startedAt, requestBytes, responseBytes);
        try {
          return decoder.decode(
            normalizeJsonEnvelopeContent(retryResponse.content),
            request,
          );
        } on FormatException {
          // 重试也解不出来：归到**同一类**失败（invalidResponse），别落进
          // 外层兜底的 connection（那会把「模型没按格式回」说成「网络问题」）。
          throw const NetworkFailure(
            '供应商返回格式无法识别。',
            kind: NetworkFailureKind.invalidResponse,
          );
        }
      }
      _log('success', startedAt, requestBytes, responseBytes);
      return draft;
    } on AppFailure catch (failure) {
      _log(
        failure is NetworkFailure ? failure.kind.name : 'local_failure',
        startedAt,
        requestBytes,
        responseBytes,
      );
      rethrow;
    } on FormatException {
      const failure = NetworkFailure(
        '供应商返回格式无法识别。',
        kind: NetworkFailureKind.invalidResponse,
      );
      _log(failure.kind.name, startedAt, requestBytes, responseBytes);
      throw failure;
    } catch (_) {
      const failure = NetworkFailure(
        '计划请求未能完成，请稍后重试。',
        kind: NetworkFailureKind.connection,
      );
      _log(failure.kind.name, startedAt, requestBytes, responseBytes);
      throw failure;
    }
  }

  AiTransportCancellationToken? _bridgeToken(
    WorkoutPlanCancellationToken? token,
  ) {
    if (token == null) return null;
    final bridged = AiTransportCancellationToken();
    if (token.isCancelled) {
      bridged.cancel();
    } else {
      token.whenCancelled.then((_) => bridged.cancel());
    }
    return bridged;
  }

  OpenAiCompatibleEndpoint _parseEndpoint(
    AiProviderConfiguration configuration,
  ) {
    final endpoint = OpenAiCompatibleEndpoint.tryParse(
      configuration.baseUrl,
      protocol: configuration.protocol,
    );
    if (endpoint == null) {
      throw const ValidationFailure('AI Base URL 配置无效，请在设置中更新。');
    }
    return endpoint;
  }

  Future<AiProviderConfiguration> _loadConfiguration() async {
    final configuration = await configurationReader.loadConfiguration();
    if (configuration == null) {
      throw const ValidationFailure('请先在设置中保存 AI 配置。');
    }
    if (configuration.model.trim().isEmpty ||
        configuration.model.trim().length > maxModelLength) {
      throw const ValidationFailure('AI 模型配置无效，请在设置中更新。');
    }
    return configuration;
  }

  Future<String> _readApiKey() async {
    final value = await apiKeyStore.read();
    if (value == null || value.trim().isEmpty) {
      throw const ValidationFailure('请先在设置中保存 API Key。');
    }
    return value.trim();
  }

  /// 模板正文（domain 单一来源）+ 渲染值；占位符逐个替换后与既有上线内容
  /// 逐字节同构（egress 评测集钉住请求体哈希）。请求体形状在 wire 表里。
  String _prompt(AiWorkoutPlanRequest request) => _catalog.render(
    taskId: template.taskId,
    promptVersion: template.promptVersion,
    values: {
      'days_per_week': '${request.daysPerWeek}',
      'exercise_library': request.exercises
          .map((exercise) => '- ${exercise.id}: ${exercise.name}')
          .join('\n'),
      'goal_guidance': _goalGuidance(request),
    },
  );

  String _goalGuidance(AiWorkoutPlanRequest request) {
    final goal = request.goalText.trim();
    if (goal.isEmpty) return '';
    return '\nUser goal (unverified guidance only): $goal';
  }

  void _throwIfCancelled(WorkoutPlanCancellationToken? token) {
    if (token?.isCancelled ?? false) {
      throw const NetworkFailure(
        '计划请求已取消。',
        kind: NetworkFailureKind.cancelled,
      );
    }
  }

  void _log(
    String kind,
    DateTime startedAt,
    int requestBytes,
    int responseBytes,
  ) {
    logger?.log(
      LogLevel.info,
      'workout_plan_finished',
      fields: {
        'resultKind': kind,
        'durationMs': DateTime.now().difference(startedAt).inMilliseconds,
        'requestBytes': requestBytes,
        'responseBytes': responseBytes,
      },
    );
  }
}
