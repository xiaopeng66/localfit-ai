import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';

/// docs/24：三种协议走**真实服务 + 记录型 adapter** 的端到端形状验证。
///
/// 断言的是「实际发出去的字节」与「实际流回来的增量」：
/// * 路径、认证头、请求体键名按协议出；
/// * SSE 增量正确解析（含跨 chunk 切断的多字节字符与半条事件）。
void main() {
  const apiKey = 'sk-canary-secret';

  _Harness createHarness({
    required AiProviderProtocol protocol,
    required ResponseBody response,
    String baseUrl = 'https://api.example.com/v1',
    int maxResponseBytes = 512 * 1024,
    Duration maxStreamDuration = const Duration(minutes: 3),
  }) {
    final adapter = _RecordingAdapter(response);
    final service = OpenAiCompatibleConversationService(
      dio: Dio(),
      configurationReader: _FixedConfiguration(
        AiProviderConfiguration(
          baseUrl: baseUrl,
          model: 'test-model',
          protocol: protocol,
        ),
      ),
      apiKeyStore: AiApiKeyStore(
        store: _MemorySecureStore()..values[AiApiKeyStore.storageKey] = apiKey,
      ),
      maxResponseBytes: maxResponseBytes,
      maxStreamDuration: maxStreamDuration,
    );
    service.dio.httpClientAdapter = adapter;
    return _Harness(service, adapter);
  }

  Future<(String text, List<RequestOptions> requests, List<String> bodies)>
  runHarness(_Harness harness) async {
    final chunks = <String>[];
    final done = Completer<void>();
    Object? error;
    harness.service
        .sendMessage(
          messages: [
            ConversationMessage(
              id: 'm-1',
              role: ConversationRole.user,
              text: '记录今天体重 70kg',
              createdAt: DateTime.utc(2026, 10, 2),
              status: ConversationMessageStatus.sent,
            ),
          ],
          onProgress: chunks.add,
        )
        .listen(
          (_) {},
          onDone: done.complete,
          onError: (Object e) {
            error = e;
            done.complete();
          },
        );
    await done.future;
    if (error != null) throw StateError('stream error: $error');
    return (chunks.join(), harness.adapter.requests, harness.adapter.bodies);
  }

  /// 一条 SSE 响应（把事件拼成字节流）。
  ResponseBody sseResponse(List<String> events) => ResponseBody.fromString(
    events.map((e) => 'data: $e\n\n').join(),
    200,
    headers: const {
      Headers.contentTypeHeader: ['text/event-stream'],
    },
  );

  // 2026-10-16（S1，用户：「你的哪里设置不对吧，我的模型可以识图的」）：
  // 对话里的图片**真的随这条消息发出去**——按各协议的图片块形状拼请求体。
  group('对话图片上行（S1）', () {
    late Directory tempDir;
    late String imagePath;
    final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lf-chat-image');
      imagePath = '${tempDir.path}/lunch.jpg';
      await File(imagePath).writeAsBytes(jpegBytes);
    });

    tearDown(() async => tempDir.delete(recursive: true));

    Future<List<String>> sendPicture(AiProviderProtocol protocol) async {
      final harness = createHarness(
        protocol: protocol,
        response: sseResponse([
          jsonEncode({
            'choices': [
              {
                'delta': {'content': '看到图了'},
              },
            ],
          }),
          '[DONE]',
        ]),
      );
      final chunks = <String>[];
      final done = Completer<void>();
      harness.service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'm-img',
                role: ConversationRole.user,
                text: '这是我的午饭',
                createdAt: DateTime.utc(2026, 10, 16),
                status: ConversationMessageStatus.sent,
                kind: ConversationMessageKind.image,
                imagePath: imagePath,
              ),
              ConversationMessage(
                id: 'm-text',
                role: ConversationRole.user,
                text: '再记 250ml 水',
                createdAt: DateTime.utc(2026, 10, 16),
                status: ConversationMessageStatus.sent,
              ),
            ],
            onProgress: chunks.add,
          )
          .listen(
            (_) {},
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            onError: (Object e) {
              if (!done.isCompleted) done.complete();
            },
          );
      await done.future;
      return harness.adapter.bodies;
    }

    test('chat 协议：图片按 data URL 出 image_url 块，文本消息形状不变', () async {
      final body = jsonDecode(
        (await sendPicture(AiProviderProtocol.chatCompletions)).single,
      ) as Map<String, Object?>;
      final messages = body['messages']! as List<Object?>;
      expect(messages[1], {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '这是我的午饭'},
          {
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/jpeg;base64,${base64Encode(jpegBytes)}',
            },
          },
        ],
      });
      expect(messages[2], {'role': 'user', 'content': '再记 250ml 水'});
    });

    test('anthropic 协议：图片按裸 base64 出 image 块', () async {
      final body = jsonDecode(
        (await sendPicture(AiProviderProtocol.anthropicMessages)).single,
      ) as Map<String, Object?>;
      final messages = body['messages']! as List<Object?>;
      // 相邻同角色合并成一条：文本段 + 图片段 + 文本段。
      expect(messages, [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '这是我的午饭'},
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': base64Encode(jpegBytes),
              },
            },
            {'type': 'text', 'text': '再记 250ml 水'},
          ],
        },
      ]);
    });

    test('图片读不到：报诚实错误，不静默丢图', () async {
      final harness = createHarness(
        protocol: AiProviderProtocol.chatCompletions,
        response: sseResponse(['[DONE]']),
      );
      Object? error;
      final done = Completer<void>();
      harness.service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'm-gone',
                role: ConversationRole.user,
                text: '图没了',
                createdAt: DateTime.utc(2026, 10, 16),
                status: ConversationMessageStatus.sent,
                kind: ConversationMessageKind.image,
                imagePath: '${tempDir.path}/not-here.jpg',
              ),
            ],
            onProgress: (_) {},
          )
          .listen(
            (_) {},
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            onError: (Object e) {
              error = e;
              if (!done.isCompleted) done.complete();
            },
          );
      await done.future;
      expect(error, isA<ValidationFailure>());
      expect('$error', contains('图片'));
      // 没有静默发一条「只有文字」的请求，也没有静默成功。
      expect(harness.adapter.bodies, isEmpty);
    });
  });

  // 2026-10-16（用户实测：「打开 app 的 ai 对话显示发送失败，点击重试」）：
  // 带图的请求被供应商拒绝时，**不能让整个对话永久发不出去**——图像留在
  // 历史里，之后每次发送都会重发它。这里钉两条兜底。
  group('带图请求的兜底（2026-10-16 用户实测缺陷）', () {
    late Directory tempDir;
    late String imagePath;
    final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9]);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lf-img-fallback');
      imagePath = '${tempDir.path}/lunch.jpg';
      await File(imagePath).writeAsBytes(jpegBytes);
    });

    tearDown(() async => tempDir.delete(recursive: true));

    /// 记录型 adapter：带 `image_url` 的请求回 400，其余回正常 SSE。
    _Harness rejectingImagesHarness() {
      final adapter = _ScriptedAdapter();
      final service = OpenAiCompatibleConversationService(
        dio: Dio(),
        configurationReader: _FixedConfiguration(
          AiProviderConfiguration(
            baseUrl: 'https://api.example.com/v1',
            model: 'test-model',
            protocol: AiProviderProtocol.chatCompletions,
          ),
        ),
        apiKeyStore: AiApiKeyStore(
          store: _MemorySecureStore()
            ..values[AiApiKeyStore.storageKey] = apiKey,
        ),
      );
      service.dio.httpClientAdapter = adapter;
      return _Harness(service, adapter);
    }

    ConversationMessage imageMessage(String id) => ConversationMessage(
      id: id,
      role: ConversationRole.user,
      text: '看看这张',
      createdAt: DateTime.utc(2026, 10, 16),
      status: ConversationMessageStatus.sent,
      kind: ConversationMessageKind.image,
      imagePath: imagePath,
    );

    ConversationMessage textMessage(String id, String text) =>
        ConversationMessage(
          id: id,
          role: ConversationRole.user,
          text: text,
          createdAt: DateTime.utc(2026, 10, 16),
          status: ConversationMessageStatus.sent,
        );

    Future<(String text, List<String> bodies)> run(
      _Harness harness,
      List<ConversationMessage> messages,
    ) async {
      final chunks = <String>[];
      final done = Completer<void>();
      Object? error;
      harness.service
          .sendMessage(messages: messages, onProgress: chunks.add)
          .listen(
            (_) {},
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            onError: (Object e) {
              error = e;
              if (!done.isCompleted) done.complete();
            },
          );
      await done.future;
      if (error != null) throw StateError('stream error: $error');
      return (chunks.join(), harness.adapter.bodies);
    }

    test('带图被 400 拒绝 ⇒ 自动去掉图片重发一次，并把原因写进回复', () async {
      final harness = rejectingImagesHarness();
      final (text, bodies) = await run(harness, [
        textMessage('m-1', '早上吃了鸡蛋'),
        imageMessage('m-2'),
      ]);

      expect(bodies, hasLength(2), reason: '第一次带图被拒 ⇒ 去图重发一次（有界）');
      expect(bodies[0], contains('image_url'), reason: '第一次是带图的');
      expect(
        bodies[1],
        isNot(contains('image_url')),
        reason: '第二次必须不带图（这是兜底的全部意义）',
      );
      expect(text, contains('不支持图片'), reason: '原因要如实写进回复，不能静默');
      expect(text, contains('这条已经改用**纯文字**重发'), reason: '要告诉用户「这条已经用文字发出去了」');
      expect(text, contains('可以帮你算营养'), reason: '模型对纯文字的回答照常显示（降级只去掉图，不影响回答）');
    });

    test('历史消息的图片文件不在了 ⇒ 不阻断发送，改写成诚实说明', () async {
      final harness = createHarness(
        protocol: AiProviderProtocol.chatCompletions,
        response: sseResponse([
          jsonEncode({
            'choices': [
              {
                'delta': {'content': '好的'},
              },
            ],
          }),
          '[DONE]',
        ]),
      );
      final missing = ConversationMessage(
        id: 'm-gone',
        role: ConversationRole.user,
        text: '当时那张图',
        createdAt: DateTime.utc(2026, 10, 16),
        status: ConversationMessageStatus.sent,
        kind: ConversationMessageKind.image,
        imagePath: '${tempDir.path}/not-here.jpg',
      );
      final (text, bodies) = await run(harness, [
        missing,
        textMessage('m-2', '继续聊'),
      ]);

      expect(text, '好的');
      expect(bodies, hasLength(1));
      expect(bodies.single, isNot(contains('image_url')), reason: '读不到的图不发送');
      expect(
        bodies.single,
        contains('图片已不在本机'),
        reason: '历史图的缺失要如实写进那一条的文字里（不静默、也不阻断对话）',
      );
    });

    test('正在发的这条图读不到 ⇒ 仍然如实报错（可行动：重新选图）', () async {
      final harness = createHarness(
        protocol: AiProviderProtocol.chatCompletions,
        response: sseResponse(['[DONE]']),
      );
      final missing = ConversationMessage(
        id: 'm-now',
        role: ConversationRole.user,
        text: '这张',
        createdAt: DateTime.utc(2026, 10, 16),
        status: ConversationMessageStatus.sent,
        kind: ConversationMessageKind.image,
        imagePath: '${tempDir.path}/not-here.jpg',
      );
      Object? error;
      final done = Completer<void>();
      harness.service
          .sendMessage(messages: [missing], onProgress: (_) {})
          .listen(
            (_) {},
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            onError: (Object e) {
              error = e;
              if (!done.isCompleted) done.complete();
            },
          );
      await done.future;
      expect(error, isA<ValidationFailure>());
      expect('$error', contains('重新选择图片'));
      expect(harness.adapter.bodies, isEmpty, reason: '不发半条请求');
    });
  });

  group('Chat Completions', () {
    test('请求路径/认证头/请求体形状', () async {
      final harness = createHarness(
        protocol: AiProviderProtocol.chatCompletions,
        response: sseResponse([
          jsonEncode({
            'choices': [
              {
                'delta': {'content': '好的'},
              },
            ],
          }),
          '[DONE]',
        ]),
      );

      final (text, requests, bodies) = await runHarness(harness);

      expect(text, '好的');
      final request = requests.single;
      expect(
        request.uri.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(request.headers['authorization'], 'Bearer $apiKey');
      expect(request.headers.containsKey('x-api-key'), isFalse);

      final body = jsonDecode(bodies.single) as Map<String, Object?>;
      // thinking：推理档默认「关闭推理」，chat 协议随请求发送（docs/29 §P4）。
      expect(body.keys.toSet(), {
        'model',
        'stream',
        'max_tokens',
        'thinking',
        'messages',
      });
      expect(body['thinking'], {'type': 'disabled'});
      expect(body['max_tokens'], 3000);
      expect((body['messages']! as List).first, {
        'role': 'system',
        'content': contains('LocalFit AI 助手'),
      });
    });
  });

  group('推理开关与空回复兜底（docs/29 §P4）', () {
    test('请求体不带 thinking：推理档选「默认」时', () async {
      final adapter = _RecordingAdapter(
        sseResponse([
          jsonEncode({
            'choices': [
              {
                'delta': {'content': 'ok'},
              },
            ],
          }),
          '[DONE]',
        ]),
      );
      final service = OpenAiCompatibleConversationService(
        dio: Dio(),
        configurationReader: _FixedConfiguration(
          AiProviderConfiguration(
            baseUrl: 'https://api.example.com/v1',
            model: 'test-model',
            protocol: AiProviderProtocol.chatCompletions,
            reasoning: AiReasoningMode.providerDefault,
          ),
        ),
        apiKeyStore: AiApiKeyStore(
          store: _MemorySecureStore()
            ..values[AiApiKeyStore.storageKey] = apiKey,
        ),
      );
      service.dio.httpClientAdapter = adapter;

      final (text, _, bodies) = await runHarness(_Harness(service, adapter));
      expect(text, 'ok');
      final body = jsonDecode(bodies.single) as Map<String, Object?>;
      expect(body.containsKey('thinking'), isFalse);
    });

    test('整条流只有 reasoning_content：报可解释错误，不出空气泡', () async {
      final harness = createHarness(
        protocol: AiProviderProtocol.chatCompletions,
        response: sseResponse([
          jsonEncode({
            'choices': [
              {
                'delta': {'reasoning_content': '思考第一段'},
              },
            ],
          }),
          jsonEncode({
            'choices': [
              {
                'delta': {'reasoning_content': '思考第二段'},
              },
            ],
          }),
          '[DONE]',
        ]),
      );

      final chunks = <String>[];
      final done = Completer<void>();
      Object? error;
      harness.service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'm-1',
                role: ConversationRole.user,
                text: '记录今天体重 70kg',
                createdAt: DateTime.utc(2026, 10, 2),
                status: ConversationMessageStatus.sent,
              ),
            ],
            onProgress: chunks.add,
          )
          .listen(
            (_) {},
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            onError: (Object e) {
              error = e;
              if (!done.isCompleted) done.complete();
            },
          );
      await done.future;

      expect(chunks, isEmpty, reason: '推理增量不许上屏');
      expect(error, isA<NetworkFailure>());
      expect(
        (error! as NetworkFailure).message,
        '模型只返回了推理内容，请在设置里关闭推理或增大输出上限。',
      );
    });

    test('有内容增量的正常流不受兜底影响（不误报）', () async {
      final harness = createHarness(
        protocol: AiProviderProtocol.chatCompletions,
        response: sseResponse([
          jsonEncode({
            'choices': [
              {
                'delta': {'reasoning_content': '先想想'},
              },
            ],
          }),
          jsonEncode({
            'choices': [
              {
                'delta': {'content': '正文'},
              },
            ],
          }),
          '[DONE]',
        ]),
      );

      final (text, _, _) = await runHarness(harness);
      expect(text, '正文');
    });
  });

  group('Responses', () {
    test('请求路径/认证头/请求体形状', () async {
      final harness = createHarness(
        protocol: AiProviderProtocol.responses,
        response: sseResponse([
          jsonEncode({'type': 'response.output_text.delta', 'delta': '好的'}),
          jsonEncode({'type': 'response.completed'}),
        ]),
      );

      final (text, requests, bodies) = await runHarness(harness);

      expect(text, '好的');
      final request = requests.single;
      expect(request.uri.toString(), 'https://api.example.com/v1/responses');
      expect(request.headers['authorization'], 'Bearer $apiKey');

      final body = jsonDecode(bodies.single) as Map<String, Object?>;
      // Responses：input / max_output_tokens / instructions，无 messages。
      expect(body.keys.toSet(), {
        'model',
        'stream',
        'max_output_tokens',
        'instructions',
        'input',
      });
      expect(body.containsKey('messages'), isFalse);
      expect(body['max_output_tokens'], 3000);
      expect(body['instructions'], contains('LocalFit AI 助手'));
    });
  });

  group('Anthropic Messages', () {
    test('请求路径/认证头/请求体形状', () async {
      final harness = createHarness(
        protocol: AiProviderProtocol.anthropicMessages,
        response: sseResponse([
          jsonEncode({
            'type': 'content_block_delta',
            'delta': {'type': 'text_delta', 'text': '好的'},
          }),
          jsonEncode({'type': 'message_stop'}),
        ]),
      );

      final (text, requests, bodies) = await runHarness(harness);

      expect(text, '好的');
      final request = requests.single;
      expect(request.uri.toString(), 'https://api.example.com/v1/messages');
      // 认证：x-api-key + 版本头，**不发 Bearer**。
      expect(request.headers['x-api-key'], apiKey);
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(request.headers.containsKey('authorization'), isFalse);

      final body = jsonDecode(bodies.single) as Map<String, Object?>;
      expect(body.keys.toSet(), {
        'model',
        'stream',
        'max_tokens',
        'system',
        'messages',
      });
      expect(body['max_tokens'], 3000);
      // system 是顶层字符串（不是 messages[0]）。
      expect(body['system'], contains('LocalFit AI 助手'));
      expect((body['messages']! as List).single, {
        'role': 'user',
        'content': '记录今天体重 70kg',
      });
      // Key 不许进正文（三种协议共同的不变量）。
      expect(bodies.single, isNot(contains(apiKey)));
    });
  });

  group('跨 chunk 切断（SSE 正确性）', () {
    /// 任意切分点把字节流切成多块，模拟真实网络分块。
    ResponseBody chunkedResponse(List<int> bytes, List<int> cutPoints) {
      final chunks = <Uint8List>[];
      var start = 0;
      for (final cut in [...cutPoints, bytes.length]) {
        chunks.add(Uint8List.fromList(bytes.sublist(start, cut)));
        start = cut;
      }
      return ResponseBody(
        Stream<Uint8List>.fromIterable(chunks),
        200,
        headers: const {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );
    }

    test('事件被切成两半也能完整解析（旧实现会丢增量）', () async {
      // 整条 SSE：`data: {...}\n\ndata: [DONE]\n\n`
      final payload = [
        jsonEncode({
          'choices': [
            {
              'delta': {'content': '第一段'},
            },
          ],
        }),
        jsonEncode({
          'choices': [
            {
              'delta': {'content': '第二段'},
            },
          ],
        }),
        '[DONE]',
      ].map((e) => 'data: $e\n\n').join();
      final bytes = utf8.encode(payload);
      // 在一个 JSON 事件中间切开（正是旧实现 jsonDecode 半行失败的位置）。
      final firstEventEnd = payload.indexOf('\n\n');
      final cut = firstEventEnd - 12;
      expect(cut, greaterThan(0));

      final harness = createHarness(
        protocol: AiProviderProtocol.chatCompletions,
        response: chunkedResponse(bytes, [cut]),
      );

      final (text, _, _) = await runHarness(harness);

      expect(text, '第一段第二段');
    });

    test('多字节 UTF-8 字符被切成两半不产生乱码', () async {
      final payload = [
        jsonEncode({
          'choices': [
            {
              'delta': {'content': '中文测试'},
            },
          ],
        }),
        '[DONE]',
      ].map((e) => 'data: $e\n\n').join();
      final bytes = utf8.encode(payload);
      // 在「中」的三个字节中间切开。
      final charIndex = payload.indexOf('中');
      expect(charIndex, greaterThan(0));
      final cut = utf8.encode(payload.substring(0, charIndex)).length + 1;

      final harness = createHarness(
        protocol: AiProviderProtocol.chatCompletions,
        response: chunkedResponse(bytes, [cut]),
      );

      final (text, _, _) = await runHarness(harness);

      expect(text, '中文测试');
      expect(text, isNot(contains('\uFFFD')));
    });

    test('CRLF 行尾也认（部分网关回 \\r\\n）', () async {
      final payload = [
        jsonEncode({
          'choices': [
            {
              'delta': {'content': 'CRLF'},
            },
          ],
        }),
        '[DONE]',
      ].map((e) => 'data: $e\r\n\r\n').join();
      final harness = createHarness(
        protocol: AiProviderProtocol.chatCompletions,
        response: chunkedResponse(utf8.encode(payload), []),
      );

      final (text, _, _) = await runHarness(harness);

      expect(text, 'CRLF');
    });
  });

  group('错误口径（跨协议统一）', () {
    test('401 报 Key 无效，不泄露响应体或协议', () async {
      final harness = createHarness(
        protocol: AiProviderProtocol.anthropicMessages,
        response: ResponseBody.fromString(
          '{"error":{"message":"hostile detail"}}',
          401,
          headers: const {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        ),
      );

      final errors = <Object>[];
      final done = Completer<void>();
      harness.service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'm-1',
                role: ConversationRole.user,
                text: 'hi',
                createdAt: DateTime.utc(2026, 10, 2),
                status: ConversationMessageStatus.sent,
              ),
            ],
            onProgress: (_) {},
          )
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await done.future;

      expect(errors, hasLength(1));
      final text = errors.single.toString();
      expect(text, contains('API Key 无效或无权使用该服务。'));
      expect(text, isNot(contains('hostile detail')));
      expect(text, isNot(contains(apiKey)));
    });
  });

  /// 累积上限（docs/25 §5 M1）：响应侧以前只有 dio 的 receiveTimeout
  /// （「两次 chunk 之间」45s），没有总量上限，也没有总时长上限。
  group('流式回复的累计上限', () {
    String event(String text) =>
        'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': text})}\n\n';

    /// 跑一次并**把错误也交出来**（runHarness 会把错误当测试失败抛出）。
    Future<(String text, Object? error)> runCapturingError(
      _Harness harness,
    ) async {
      final chunks = <String>[];
      final done = Completer<void>();
      Object? error;
      harness.service
          .sendMessage(
            messages: [
              ConversationMessage(
                id: 'm-1',
                role: ConversationRole.user,
                text: '记录今天体重 70kg',
                createdAt: DateTime.utc(2026, 10, 2),
                status: ConversationMessageStatus.sent,
              ),
            ],
            onProgress: chunks.add,
          )
          .listen(
            (_) {},
            onError: (Object e) {
              error = e;
              if (!done.isCompleted) done.complete();
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
          );
      await done.future;
      return (chunks.join(), error);
    }

    test('累计字节超上限即中止（任一块单独都没超）', () async {
      final first = event('a' * 10);
      final second = event('b' * 10);
      final firstBytes = utf8.encode(first).length;
      final secondBytes = utf8.encode(second).length;
      // 上限卡在「单块放行、累计必超」之间：任何只检查单块大小的实现
      // （比如把 receivedBytes 每块重置）都会放行，只有**累计**计数才抓得住。
      final cap = firstBytes + secondBytes - 1;
      final body = StreamController<Uint8List>();
      final harness = createHarness(
        protocol: AiProviderProtocol.responses,
        response: ResponseBody(
          body.stream,
          200,
          headers: const {
            Headers.contentTypeHeader: ['text/event-stream'],
          },
        ),
        maxResponseBytes: cap,
      );
      scheduleMicrotask(() {
        body.add(Uint8List.fromList(utf8.encode(first)));
        body.add(Uint8List.fromList(utf8.encode(second)));
      });

      final (text, error) = await runCapturingError(harness);

      expect(error, isA<NetworkFailure>());
      expect(
        (error! as NetworkFailure).kind,
        NetworkFailureKind.invalidResponse,
      );
      expect((error as NetworkFailure).message, contains('超出上限'));
      // 中止发生在超限的那一块：第一块（合法）已经交付，第二块没有。
      expect(text, 'a' * 10);
      expect(text, isNot(contains('b' * 10)));
      await body.close();
    });

    group('带图请求的体量上限', () {
      // 2026-10-16 实时实测（供应商 ai.furry.vg）：一张 49 KB 的探针图经 base64
      // 膨胀后超过对话路径的 64 KiB 请求上限 ⇒ 直接报「对话内容过长，请精简后
      // 重试。」；而手机拍的照片动辄 1–5 MB ⇒ **真照片根本发不出去**。
      // 口径：文字请求仍守 64 KiB（快照有界），**本条带图**就放到 8 MiB
      // （与识餐出口同档，识餐那份是 5 MiB 图 / 7 MiB 请求）。
      late Directory tempDir;
      late String bigImagePath;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('lf-chat-big-image');
        bigImagePath = '${tempDir.path}/big.jpg';
        await File(bigImagePath).writeAsBytes(
          Uint8List.fromList([
            0xFF,
            0xD8,
            0xFF,
            0xE0,
            ...List.filled(200 * 1024, 0x41),
          ]),
        );
      });

      tearDown(() async => tempDir.delete(recursive: true));

      test('200 KB 的图（base64 后 ~270 KB）能发出去：不许被 64 KiB 挡下', () async {
        final harness = createHarness(
          protocol: AiProviderProtocol.chatCompletions,
          response: sseResponse([
            jsonEncode({
              'choices': [
                {
                  'delta': {'content': '看到图了'},
                },
              ],
            }),
            '[DONE]',
          ]),
        );
        final chunks = <String>[];
        await harness.service
            .sendMessage(
              messages: [
                ConversationMessage(
                  id: 'm-big',
                  role: ConversationRole.user,
                  text: '这是什么？',
                  createdAt: DateTime.utc(2026, 10, 16),
                  status: ConversationMessageStatus.sent,
                  kind: ConversationMessageKind.image,
                  imagePath: bigImagePath,
                ),
              ],
              onProgress: chunks.add,
            )
            .drain<void>();
        expect(chunks.join(), contains('看到图了'));
        expect(harness.adapter.bodies.single, contains('image_url'));
      });

      test('纯文字请求仍守 64 KiB（快照有界这条不许松）', () async {
        final harness = createHarness(
          protocol: AiProviderProtocol.chatCompletions,
          response: sseResponse(const ['好']),
        );
        final chunks = <String>[];
        await expectLater(
          harness.service
              .sendMessage(
                messages: [
                  ConversationMessage(
                    id: 'm-huge',
                    role: ConversationRole.user,
                    text: 'x' * (200 * 1024),
                    createdAt: DateTime.utc(2026, 10, 16),
                    status: ConversationMessageStatus.sent,
                  ),
                ],
                onProgress: chunks.add,
              )
              .drain<void>(),
          throwsA(
            isA<ValidationFailure>().having(
              (failure) => failure.message,
              'message',
              contains('对话内容过长'),
            ),
          ),
        );
      });
    });

    test('累计时长超上限即中止（每次间隔都短于 receiveTimeout）', () async {
      final body = StreamController<Uint8List>();
      final harness = createHarness(
        protocol: AiProviderProtocol.responses,
        response: ResponseBody(
          body.stream,
          200,
          headers: const {
            Headers.contentTypeHeader: ['text/event-stream'],
          },
        ),
        // 真等 300ms：不注入假时钟，测的就是 `Stopwatch` 的真实读数。
        maxStreamDuration: const Duration(milliseconds: 120),
      );
      scheduleMicrotask(() {
        body.add(Uint8List.fromList(utf8.encode(event('第一块'))));
      });
      Timer(const Duration(milliseconds: 300), () {
        body.add(Uint8List.fromList(utf8.encode(event('第二块'))));
      });

      final (text, error) = await runCapturingError(harness);

      expect(error, isA<NetworkFailure>());
      expect((error! as NetworkFailure).kind, NetworkFailureKind.timeout);
      expect((error as NetworkFailure).message, contains('累计超时'));
      expect(text, '第一块');
      await body.close();
    });
  });
}

final class _Harness {
  const _Harness(this.service, this.adapter);

  final OpenAiCompatibleConversationService service;
  final _BodyRecordingAdapter adapter;
}

final class _FixedConfiguration implements AiProviderConfigurationReader {
  const _FixedConfiguration(this.configuration);

  final AiProviderConfiguration configuration;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => configuration;
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// 测试用 adapter 的共同契约：能拿到「实际发出去的请求与字节」。
abstract interface class _BodyRecordingAdapter implements HttpClientAdapter {
  List<RequestOptions> get requests;
  List<String> get bodies;
}

final class _RecordingAdapter implements _BodyRecordingAdapter {
  _RecordingAdapter(this.response);

  final ResponseBody response;
  @override
  final requests = <RequestOptions>[];
  @override
  final bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requestStream != null) {
      final chunks = <int>[];
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
      bodies.add(utf8.decode(chunks, allowMalformed: true));
    }
    return response;
  }

  @override
  void close({bool force = false}) {}
}

/// 脚本化 adapter：带 `image_url` 的请求回 400，其余回一句正常 SSE。
///
/// 用来复现「模型不支持图片输入 ⇒ 400」这一族（2026-10-16 用户实测缺陷）。
final class _ScriptedAdapter implements _BodyRecordingAdapter {
  @override
  final requests = <RequestOptions>[];
  @override
  final bodies = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final chunks = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        chunks.addAll(chunk);
      }
    }
    final body = utf8.decode(chunks, allowMalformed: true);
    bodies.add(body);
    if (body.contains('image_url')) {
      return ResponseBody.fromString('{"error":"images not supported"}', 400);
    }
    return ResponseBody.fromString(
      'data: {"choices":[{"delta":{"content":"我看不了图，但可以帮你算营养"}}]}\n\n'
      'data: [DONE]\n\n',
      200,
      headers: const {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
