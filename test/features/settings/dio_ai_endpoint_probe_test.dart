import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/settings/data/dio_ai_endpoint_probe.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';

/// docs/29 §P4 需求 7：连通性测试（GET {base}/models，5s 超时，失败分档）。
///
/// 用记录型 adapter 覆盖四档失败 + 两种成功形状 + 两个本地短路（无效
/// Base URL / 空 Key），断言「实际发出的请求」与「上屏的中文原因」。
void main() {
  test('成功：OpenAI 形状，id 去重排序，GET /models 带 Bearer', () async {
    final adapter = _ScriptedAdapter(
      ResponseBody.fromString(
        jsonEncode({
          'object': 'list',
          'data': [
            {'id': 'b-model'},
            {'id': 'a-model'},
            {'id': 'a-model'},
          ],
        }),
        200,
        headers: const {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    final probe = _probe(adapter);

    final result = await probe.probe(
      baseUrl: 'https://api.example.com/v1',
      protocol: AiProviderProtocol.chatCompletions,
      apiKey: 'sk-test',
    );

    expect(result.isSuccess, isTrue);
    expect(result.models, ['a-model', 'b-model'], reason: '去重 + 排序');
    final request = adapter.requests.single;
    expect(request.uri.toString(), 'https://api.example.com/v1/models');
    expect(request.method, 'GET');
    expect(request.headers['authorization'], 'Bearer sk-test');
  });

  test('成功：裸数组形状（一家网关的写法）也认', () async {
    final adapter = _ScriptedAdapter(
      ResponseBody.fromString(
        jsonEncode([
          {'id': 'only-model'},
        ]),
        200,
        headers: const {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    final result = await _probe(adapter).probe(
      baseUrl: 'https://api.example.com/v1',
      protocol: AiProviderProtocol.chatCompletions,
      apiKey: 'sk-test',
    );
    expect(result.isSuccess, isTrue);
    expect(result.models, ['only-model']);
  });

  test('200 但形状不认识：如实说明（不影响手输模型）', () async {
    final adapter = _ScriptedAdapter(
      ResponseBody.fromString(jsonEncode({'foo': 1}), 200),
    );
    final result = await _probe(adapter).probe(
      baseUrl: 'https://api.example.com/v1',
      protocol: AiProviderProtocol.chatCompletions,
      apiKey: 'sk-test',
    );
    expect(result.isSuccess, isFalse);
    expect(result.message, contains('格式无法识别'));
  });

  test('401：Key 错的分档文案', () async {
    final adapter = _ScriptedAdapter(ResponseBody.fromString('denied', 401));
    final result = await _probe(adapter).probe(
      baseUrl: 'https://api.example.com/v1',
      protocol: AiProviderProtocol.chatCompletions,
      apiKey: 'sk-wrong',
    );
    expect(result.isSuccess, isFalse);
    expect(result.message, 'API Key 无效或无权访问该服务。');
  });

  test('404：Base URL 不对的分档文案', () async {
    final adapter = _ScriptedAdapter(ResponseBody.fromString('nope', 404));
    final result = await _probe(adapter).probe(
      baseUrl: 'https://api.example.com/v2',
      protocol: AiProviderProtocol.chatCompletions,
      apiKey: 'sk-test',
    );
    expect(result.isSuccess, isFalse);
    expect(result.message, contains('Base URL 可能不对'));
  });

  test('超时：网络不可达的分档文案', () async {
    final adapter = _ThrowingAdapter(
      DioException(
        requestOptions: RequestOptions(path: '/models'),
        type: DioExceptionType.connectionTimeout,
      ),
    );
    final result = await _probe(adapter).probe(
      baseUrl: 'https://api.example.com/v1',
      protocol: AiProviderProtocol.chatCompletions,
      apiKey: 'sk-test',
    );
    expect(result.isSuccess, isFalse);
    expect(result.message, '连接超时：网络不可达或 Base URL 有误。');
  });

  test('本地短路：Base URL 无效 / Key 为空不发请求', () async {
    final adapter = _ScriptedAdapter(ResponseBody.fromString('', 200));
    final probe = _probe(adapter);

    final badUrl = await probe.probe(
      baseUrl: 'http://api.example.com/v1',
      protocol: AiProviderProtocol.chatCompletions,
      apiKey: 'sk-test',
    );
    expect(badUrl.isSuccess, isFalse);
    expect(badUrl.message, contains('Base URL 无效'));

    final noKey = await probe.probe(
      baseUrl: 'https://api.example.com/v1',
      protocol: AiProviderProtocol.chatCompletions,
      apiKey: '  ',
    );
    expect(noKey.isSuccess, isFalse);
    expect(noKey.message, '请先填写 API Key。');

    expect(adapter.requests, isEmpty, reason: '两种短路都不许触网');
  });

  test('认证头按协议出：anthropic 用 x-api-key', () async {
    final adapter = _ScriptedAdapter(
      ResponseBody.fromString(jsonEncode([]), 200),
    );
    await _probe(adapter).probe(
      baseUrl: 'https://api.example.com/v1',
      protocol: AiProviderProtocol.anthropicMessages,
      apiKey: 'sk-ant',
    );
    final request = adapter.requests.single;
    expect(request.headers['x-api-key'], 'sk-ant');
    expect(request.headers.containsKey('authorization'), isFalse);
  });
}

DioAiEndpointProbe _probe(HttpClientAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return DioAiEndpointProbe(dio: dio);
}

final class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this.response);

  final ResponseBody response;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return response;
  }

  @override
  void close({bool force = false}) {}
}

final class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.error);

  final DioException error;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    throw error;
  }

  @override
  void close({bool force = false}) {}
}
