import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/logging/privacy_logger.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/data/open_ai_compatible_workout_plan_provider.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

void main() {
  const secret = 'test-secret-key';

  AiWorkoutPlanRequest request() => const AiWorkoutPlanRequest(
    daysPerWeek: 2,
    goalText: '增肌',
    exercises: [
      ExerciseOption(id: 'ex-barbell-squat', name: '杠铃深蹲'),
      ExerciseOption(id: 'ex-plank', name: '平板支撑'),
    ],
  );

  String validPlan() =>
      '{"schema_version":1,"name":"AI 计划","days":['
      '{"weekday":1,"exercises":[{"exercise_id":"ex-barbell-squat","target_sets":4,"target_reps":8}]},'
      '{"weekday":4,"exercises":[{"exercise_id":"ex-plank","target_sets":3,"target_reps":60}]}],'
      '"warnings":[]}';

  _Harness harness({ResponseBody? response, DioExceptionType? failure}) {
    final adapter = _Adapter(response: response, failure: failure);
    final logs = <String>[];
    final provider = OpenAiCompatibleWorkoutPlanProvider(
      dio: Dio(),
      configurationReader: const _Configuration(),
      apiKeyStore: AiApiKeyStore(
        store: _Store()..values['localfit.ai.api_key.v1'] = secret,
      ),
      logger: PrivacyLogger(writer: logs.add),
    )..dio.httpClientAdapter = adapter;
    return _Harness(provider, adapter, logs);
  }

  test(
    'sends a text-only request with the library and header-only key',
    () async {
      final value = harness(response: _json(_envelope(validPlan())));
      final draft = await value.provider.generate(request());

      expect(draft.name, 'AI 计划');
      expect(draft.days, hasLength(2));
      final sent = value.adapter.requests.single;
      expect(
        sent.uri.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(sent.headers['authorization'], 'Bearer $secret');
      expect(sent.followRedirects, isFalse);
      expect(value.adapter.bodies.single, isNot(contains(secret)));
      expect(value.adapter.bodies.single, contains('ex-barbell-squat'));
      expect(value.adapter.bodies.single, contains('exactly 2 day(s)'));
      expect(value.logs.join(), isNot(contains(secret)));
    },
  );

  test('散文在前 + 围栏包裹时：抢救出那一个 JSON（真机实测的模型习惯）', () async {
    // 2026-10-16 设备实测（AVD LocalFit_API35 → 供应商 ai.furry.vg）：生成计划
    // 时模型先写一段说明再贴 JSON，界面直接报「供应商返回格式无法识别。」。
    // 同族的坑在对话信封那边已经补过抢救（`ai_json_object_salvage.dart`），
    // 这里把同一层兜底接到计划出口上。
    final chatty = '好的，我给你排了一套三天计划，下面是 JSON：\n```json\n${validPlan()}\n```';
    final value = harness(response: _json(_envelope(chatty)));
    final draft = await value.provider.generate(request());
    expect(draft.name, 'AI 计划');
    expect(draft.days, hasLength(2));
  });

  test('第一次解不出来：带强化提醒**重问一次**，成功就用第二次的结果', () async {
    // 2026-10-16 真机实测：独立创建页上模型把 exercise_id 写成自己编的名字，
    // 界面只写「供应商返回格式无法识别。」。与对话信封同族：**每轮最多重试
    // 一次**，带更硬的约束重问；第二次还不行才如实报错（不无限重问）。
    final adapter = _QueueAdapter([
      _json(_envelope('抱歉，我先说明一下：这个计划的动作我会用杠铃深蹲。')),
      _json(_envelope(validPlan())),
    ]);
    final provider = OpenAiCompatibleWorkoutPlanProvider(
      dio: Dio(),
      configurationReader: const _Configuration(),
      apiKeyStore: AiApiKeyStore(
        store: _Store()..values['localfit.ai.api_key.v1'] = secret,
      ),
      logger: PrivacyLogger(writer: (_) {}),
    )..dio.httpClientAdapter = adapter;

    final draft = await provider.generate(request());

    expect(draft.name, 'AI 计划', reason: '第二次给的是合法计划，应直接可用');
    expect(adapter.bodies, hasLength(2), reason: '只许重试一次');
    expect(
      adapter.bodies.last,
      contains('逐字复制'),
      reason: '重试请求必须带上强化提醒（否则等于原样再问一遍）',
    );
  });

  test('rejects an unknown exercise id without returning a draft', () async {
    final badPlan = validPlan().replaceFirst('ex-plank', 'ex-unknown');
    // 2026-10-16：格式失败现在会**带强化提醒重问一次** ⇒ 这一条也要能提供两次
    // 响应（dio 的 `ResponseBody` 是一次性流，同一个实例读第二次会抛）。
    final adapter = _QueueAdapter([
      _json(_envelope(badPlan)),
      _json(_envelope(badPlan)),
    ]);
    final logs = <String>[];
    final provider = openAiWorkoutPlanProviderForTest(
      adapter: adapter,
      logs: logs,
      secret: secret,
    );
    await expectLater(
      provider.generate(request()),
      throwsA(isA<NetworkFailure>()),
    );
    expect(logs.join(), contains('invalidResponse'));
    expect(adapter.bodies, hasLength(2), reason: '重试恰好一次');
  });

  test(
    'does not send invalid requests, missing credentials, or timeouts',
    () async {
      final value = harness();
      await expectLater(
        value.provider.generate(
          const AiWorkoutPlanRequest(
            daysPerWeek: 0,
            goalText: '',
            exercises: [ExerciseOption(id: 'ex-plank', name: '平板支撑')],
          ),
        ),
        throwsFormatException,
      );
      expect(value.adapter.requests, isEmpty);

      final noConfig = OpenAiCompatibleWorkoutPlanProvider(
        dio: Dio(),
        configurationReader: const _EmptyConfiguration(),
        apiKeyStore: AiApiKeyStore(store: _Store()),
      )..dio.httpClientAdapter = _Adapter();
      await expectLater(
        noConfig.generate(request()),
        throwsA(isA<ValidationFailure>()),
      );

      final timeout = harness(failure: DioExceptionType.connectionTimeout);
      await expectLater(
        timeout.provider.generate(request()),
        throwsA(
          isA<NetworkFailure>().having(
            (failure) => failure.kind,
            'kind',
            NetworkFailureKind.timeout,
          ),
        ),
      );
    },
  );
}

ResponseBody _json(String content) => ResponseBody.fromString(
  jsonEncode({
    'choices': [
      {
        'message': {'content': content},
      },
    ],
  }),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

String _envelope(String plan) => plan;

final class _Harness {
  _Harness(this.provider, this.adapter, this.logs);

  final OpenAiCompatibleWorkoutPlanProvider provider;
  final _Adapter adapter;
  final List<String> logs;
}

final class _Adapter implements HttpClientAdapter {
  _Adapter({this.response, this.failure});

  final ResponseBody? response;
  final DioExceptionType? failure;
  final requests = <RequestOptions>[];
  final bodies = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = options.data;
    if (data is String) bodies.add(data);
    final failure = this.failure;
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure);
    }
    final response = this.response;
    if (response == null) {
      throw StateError('no response configured');
    }
    return response;
  }
}

final class _Configuration implements AiProviderConfigurationReader {
  const _Configuration();

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      const AiProviderConfiguration(
        baseUrl: 'https://api.example.com/v1',
        model: 'plan-test',
      );
}

final class _EmptyConfiguration implements AiProviderConfigurationReader {
  const _EmptyConfiguration();

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => null;
}

final class _Store implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// 按顺序返回响应的适配器（重试用例要「第一次坏、第二次好」）。
final class _QueueAdapter implements HttpClientAdapter {
  _QueueAdapter(this._responses);

  final List<ResponseBody> _responses;
  final List<String> bodies = [];
  var _index = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data;
    if (data is String) bodies.add(data);
    final response =
        _responses[_index < _responses.length ? _index : _responses.length - 1];
    _index++;
    return response;
  }

  @override
  void close({bool force = false}) {}
}

/// 直接给一个适配器的 provider（重试用例需要队列适配器，不走 `harness()`）。
OpenAiCompatibleWorkoutPlanProvider openAiWorkoutPlanProviderForTest({
  required HttpClientAdapter adapter,
  required List<String> logs,
  required String secret,
}) {
  final provider = OpenAiCompatibleWorkoutPlanProvider(
    dio: Dio(),
    configurationReader: const _Configuration(),
    apiKeyStore: AiApiKeyStore(
      store: _Store()..values['localfit.ai.api_key.v1'] = secret,
    ),
    logger: PrivacyLogger(writer: logs.add),
  );
  provider.dio.httpClientAdapter = adapter;
  return provider;
}
