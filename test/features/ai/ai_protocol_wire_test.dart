import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/ai/data/ai_protocol_wire.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';

/// docs/24 §4 的协议 wire 表：**逐条钉住三种协议的分歧点**。
///
/// 这份文件是「加协议时不能只改一半」的机械保证：认证头、请求体键名、
/// 非流式提取、流式增量、流结束事件——每一项对三种协议各断言一次。少了
/// 任何一项，对应协议的分支就没有证据。
void main() {
  const apiKey = 'sk-canary-key';

  group('认证头（Key 只进头）', () {
    test('Chat Completions 与 Responses 用 Bearer', () {
      for (final protocol in [
        AiProviderProtocol.chatCompletions,
        AiProviderProtocol.responses,
      ]) {
        final headers = protocol.authHeaders(apiKey);
        expect(headers, {
          'authorization': 'Bearer $apiKey',
        }, reason: '$protocol');
        // Anthropic 的版本头不许出现在 OpenAI 协议上。
        expect(headers.containsKey('anthropic-version'), isFalse);
      }
    });

    test('Anthropic Messages 用 x-api-key + anthropic-version，不发 Bearer', () {
      final headers = AiProviderProtocol.anthropicMessages.authHeaders(apiKey);

      expect(headers['x-api-key'], apiKey);
      expect(headers['anthropic-version'], '2023-06-01');
      // 关键：不能用 authorization——Anthropic 不认这个头，会 401。
      expect(headers.containsKey('authorization'), isFalse);
    });

    test('三种协议的 Key 都不出现在 URL 里', () {
      for (final protocol in AiProviderProtocol.values) {
        final headers = protocol.authHeaders(apiKey);
        for (final value in headers.values) {
          expect(value, isNot(contains('https://')));
        }
      }
    });
  });

  group('请求体形状', () {
    test('任务请求体：system/user 结构按协议出', () {
      final chat = AiProviderProtocol.chatCompletions.taskRequestBody(
        model: 'm-1',
        maxTokens: 100,
        prompt: '你好',
        reasoning: AiReasoningMode.disabled,
      );
      expect(chat.keys.toSet(), {
        'model',
        'temperature',
        'max_tokens',
        'thinking',
        'messages',
      });
      // 推理档「关闭推理」（默认）：chat 请求体带 thinking 字段（docs/29 §P4）。
      expect(chat['thinking'], {'type': 'disabled'});
      expect(chat['temperature'], 0);
      expect(chat['messages'], [
        {'role': 'user', 'content': '你好'},
      ]);

      final responses = AiProviderProtocol.responses.taskRequestBody(
        model: 'm-1',
        maxTokens: 100,
        prompt: '你好',
        reasoning: AiReasoningMode.disabled,
      );
      // Responses 改键名：input / max_output_tokens，且不发 temperature
      // （推理模型会直接拒绝该参数）。
      expect(responses.keys.toSet(), {'model', 'max_output_tokens', 'input'});
      // 键名逐个钉住：集合断言断不出「值写到了哪个键上」。
      expect(responses['max_output_tokens'], 100);
      expect(responses.containsKey('max_tokens'), isFalse);
      expect(responses.containsKey('temperature'), isFalse);
      expect(responses['input'], [
        {'role': 'user', 'content': '你好'},
      ]);

      final anthropic = AiProviderProtocol.anthropicMessages.taskRequestBody(
        model: 'm-1',
        maxTokens: 100,
        prompt: '你好',
        reasoning: AiReasoningMode.disabled,
      );
      expect(anthropic.keys.toSet(), {'model', 'max_tokens', 'messages'});
      // Anthropic 的 max_tokens 是必填：漏了会 400。
      expect(anthropic['max_tokens'], 100);
    });

    test('对话请求体：system 承载方式按协议出', () {
      const messages = [(role: 'user', text: '记录体重 70kg', image: null)];

      final chat = AiProviderProtocol.chatCompletions.conversationRequestBody(
        model: 'm',
        maxTokens: 50,
        systemPrompt: 'SYS',
        systemContext: 'CTX',
        messages: messages,
        reasoning: AiReasoningMode.disabled,
      );
      // Chat Completions：主 system + 快照 system 两条消息。
      expect(chat['messages'], [
        {'role': 'system', 'content': 'SYS'},
        {'role': 'system', 'content': 'CTX'},
        {'role': 'user', 'content': '记录体重 70kg'},
      ]);
      expect(chat['stream'], isTrue);

      final responses = AiProviderProtocol.responses.conversationRequestBody(
        model: 'm',
        maxTokens: 50,
        systemPrompt: 'SYS',
        systemContext: 'CTX',
        messages: messages,
        reasoning: AiReasoningMode.disabled,
      );
      // Responses：system 与快照合并进顶层 instructions（没有「多条 system」
      // 的概念，拆开写会静默丢掉后一条）。
      expect(responses['instructions'], 'SYS\n\nCTX');
      expect(responses.containsKey('system'), isFalse);
      expect(responses['input'], [
        {'role': 'user', 'content': '记录体重 70kg'},
      ]);

      final anthropic = AiProviderProtocol.anthropicMessages
          .conversationRequestBody(
            model: 'm',
            maxTokens: 50,
            systemPrompt: 'SYS',
            systemContext: 'CTX',
            messages: messages,
            reasoning: AiReasoningMode.disabled,
          );
      // Anthropic：顶层 system 字符串。
      expect(anthropic['system'], 'SYS\n\nCTX');
      expect(anthropic['messages'], [
        {'role': 'user', 'content': '记录体重 70kg'},
      ]);
    });

    // 2026-10-16（S1，用户：「我的模型可以识图的」）：对话消息可以带一张图
    // ——按各协议的图片块形状出；纯文本消息的形状与历史**逐字节一致**。
    test('对话请求体：带图消息出多模态块（三协议），纯文本消息形状不变', () {
      final bytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x01]);
      final dataUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      final messages = [
        (role: 'user', text: '记录体重 70kg', image: null),
        (role: 'user', text: '这是我的午饭', image: bytes),
        (role: 'assistant', text: '收到', image: null),
      ];

      final chat = AiProviderProtocol.chatCompletions.conversationRequestBody(
        model: 'm',
        maxTokens: 50,
        systemPrompt: 'SYS',
        messages: messages,
        reasoning: AiReasoningMode.disabled,
      );
      final chatMessages = chat['messages']! as List<Object>;
      // 纯文本消息照旧是字符串 content（下标 0 是主 system；本例没有快照段）。
      expect(chatMessages[1], {'role': 'user', 'content': '记录体重 70kg'});
      expect(chatMessages[2], {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '这是我的午饭'},
          {
            'type': 'image_url',
            'image_url': {'url': dataUrl},
          },
        ],
      });

      final responses = AiProviderProtocol.responses.conversationRequestBody(
        model: 'm',
        maxTokens: 50,
        systemPrompt: 'SYS',
        messages: messages,
        reasoning: AiReasoningMode.disabled,
      );
      final input = responses['input']! as List<Object>;
      expect(input[0], {'role': 'user', 'content': '记录体重 70kg'});
      expect(input[1], {
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': '这是我的午饭'},
          {'type': 'input_image', 'image_url': dataUrl},
        ],
      });

      final anthropic = AiProviderProtocol.anthropicMessages
          .conversationRequestBody(
            model: 'm',
            maxTokens: 50,
            systemPrompt: 'SYS',
            messages: messages,
            reasoning: AiReasoningMode.disabled,
          );
      final anthropicMessages = anthropic['messages']! as List<Object>;
      // Anthropic 相邻同角色合并成一条：合并后 content 里既有纯文本段、
      // 也有图片段（裸 base64，不是 data URL）。
      expect(anthropicMessages, [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': '记录体重 70kg\n\n这是我的午饭'},
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': base64Encode(bytes),
              },
            },
          ],
        },
        {'role': 'assistant', 'content': '收到'},
      ]);
    });

    test('Anthropic 合并相邻同角色消息（协议要求交替）', () {
      // 本地历史里失败的助手回复会被排除，可能出现连续两条 user。
      final body = AiProviderProtocol.anthropicMessages.conversationRequestBody(
        model: 'm',
        maxTokens: 50,
        systemPrompt: 'SYS',
        reasoning: AiReasoningMode.disabled,
        messages: const [
          (role: 'user', text: '第一条', image: null),
          (role: 'user', text: '第二条', image: null),
          (role: 'assistant', text: '回复', image: null),
          (role: 'assistant', text: '补充', image: null),
        ],
      );

      expect(body['messages'], [
        {'role': 'user', 'content': '第一条\n\n第二条'},
        {'role': 'assistant', 'content': '回复\n\n补充'},
      ]);
    });

    test('systemContext 为 null 时不发占位空串', () {
      for (final protocol in AiProviderProtocol.values) {
        final body = protocol.conversationRequestBody(
          model: 'm',
          maxTokens: 50,
          systemPrompt: 'SYS',
          messages: const [(role: 'user', text: 'hi', image: null)],
          reasoning: AiReasoningMode.disabled,
        );
        final encoded = jsonEncode(body);
        expect(encoded, isNot(contains('null\n')), reason: '$protocol');
        switch (protocol) {
          case AiProviderProtocol.chatCompletions:
            expect(body['messages'], hasLength(2)); // 只有主 system
          case AiProviderProtocol.responses:
            expect(body['instructions'], 'SYS');
          case AiProviderProtocol.anthropicMessages:
            expect(body['system'], 'SYS');
        }
      }
    });

    test('视觉请求体：三种协议的图片形状互不相同', () {
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0x01, 0x02, 0xff, 0xd9]);
      final base64 = base64Encode(jpeg);

      final chat = AiProviderProtocol.chatCompletions.visionRequestBody(
        model: 'm',
        maxTokens: 10,
        instruction: '看图',
        jpegBytes: jpeg,
        reasoning: AiReasoningMode.disabled,
      );
      final chatContent =
          ((chat['messages']! as List).single as Map)['content']! as List;
      expect(chatContent[1], {
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$base64'},
      });

      final responses = AiProviderProtocol.responses.visionRequestBody(
        model: 'm',
        maxTokens: 10,
        instruction: '看图',
        jpegBytes: jpeg,
        reasoning: AiReasoningMode.disabled,
      );
      final responsesContent =
          ((responses['input']! as List).single as Map)['content']! as List;
      expect(responsesContent[0]['type'], 'input_text');
      expect(responsesContent[1], {
        'type': 'input_image',
        'image_url': 'data:image/jpeg;base64,$base64',
      });

      final anthropic = AiProviderProtocol.anthropicMessages.visionRequestBody(
        model: 'm',
        maxTokens: 10,
        instruction: '看图',
        jpegBytes: jpeg,
        reasoning: AiReasoningMode.disabled,
      );
      final anthropicContent =
          ((anthropic['messages']! as List).single as Map)['content']! as List;
      // 关键差异：Anthropic 要**裸 base64**，不是 data URL。
      expect(anthropicContent[1], {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/jpeg',
          'data': base64,
        },
      });
      expect(jsonEncode(anthropic), isNot(contains('data:image/jpeg')));
    });
  });

  group('非流式响应提取', () {
    test('Chat Completions：choices[0].message.content', () {
      final content = AiProviderProtocol.chatCompletions
          .extractNonStreamContent({
            'choices': [
              {
                'message': {'content': '答案'},
              },
            ],
          });
      expect(content, '答案');
    });

    test('Responses：优先 output 数组，回落到 output_text', () {
      final fromOutput = AiProviderProtocol.responses.extractNonStreamContent({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '第一段'},
              {'type': 'output_text', 'text': '第二段'},
            ],
          },
        ],
      });
      expect(fromOutput, '第一段第二段');

      // 中转/自建网关常只回 output_text。
      final fromConvenience = AiProviderProtocol.responses
          .extractNonStreamContent({'output_text': '便捷字段'});
      expect(fromConvenience, '便捷字段');
    });

    test('Anthropic：content[].text 拼接，忽略非 text 块', () {
      final content = AiProviderProtocol.anthropicMessages
          .extractNonStreamContent({
            'content': [
              {'type': 'text', 'text': '正文'},
              {'type': 'tool_use', 'id': 'x'},
              {'type': 'text', 'text': '续'},
            ],
          });
      expect(content, '正文续');
    });

    test('形状不符一律返回 null（不猜内容）', () {
      for (final protocol in AiProviderProtocol.values) {
        expect(
          protocol.extractNonStreamContent({'unexpected': true}),
          isNull,
          reason: '$protocol',
        );
        expect(
          protocol.extractNonStreamContent({}),
          isNull,
          reason: '$protocol empty',
        );
      }
    });

    test('跨协议：别家的响应形状不会被误认', () {
      // chat 形状喂给 Responses / Anthropic → null（不能把别家协议的字段
      // 当自己的，否则一个网关换协议时会静默读到错内容）。
      final chatShaped = {
        'choices': [
          {
            'message': {'content': '给 chat 的'},
          },
        ],
      };
      expect(
        AiProviderProtocol.responses.extractNonStreamContent(chatShaped),
        isNull,
      );
      expect(
        AiProviderProtocol.anthropicMessages.extractNonStreamContent(
          chatShaped,
        ),
        isNull,
      );
      // 反向：把 Responses 的 input 形状喂给 chat / anthropic → null。
      expect(
        AiProviderProtocol.chatCompletions.extractNonStreamContent({
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'x'},
              ],
            },
          ],
        }),
        isNull,
      );
      expect(
        AiProviderProtocol.anthropicMessages.extractNonStreamContent({
          'output_text': 'x',
        }),
        isNull,
      );
    });
  });

  group('流式增量提取', () {
    test('Chat Completions：choices[].delta.content', () {
      expect(
        AiProviderProtocol.chatCompletions.extractDelta({
          'choices': [
            {
              'delta': {'content': '增量'},
            },
          ],
        }),
        '增量',
      );
      // 首帧只带 role、无 content：不是错误，返回 null。
      expect(
        AiProviderProtocol.chatCompletions.extractDelta({
          'choices': [
            {
              'delta': {'role': 'assistant'},
            },
          ],
        }),
        isNull,
      );
    });

    test('Responses：response.output_text.delta 事件', () {
      expect(
        AiProviderProtocol.responses.extractDelta({
          'type': 'response.output_text.delta',
          'delta': '增量',
        }),
        '增量',
      );
      // 别的事件类型不带文本。
      expect(
        AiProviderProtocol.responses.extractDelta({'type': 'response.created'}),
        isNull,
      );
    });

    test('Anthropic：content_block_delta + text_delta', () {
      expect(
        AiProviderProtocol.anthropicMessages.extractDelta({
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': '增量'},
        }),
        '增量',
      );
      // input_json_delta（工具调用）不是文本，不许当正文。
      expect(
        AiProviderProtocol.anthropicMessages.extractDelta({
          'type': 'content_block_delta',
          'delta': {'type': 'input_json_delta', 'partial_json': '{}'},
        }),
        isNull,
      );
    });

    test('流结束事件按协议判别', () {
      expect(
        AiProviderProtocol.responses.isStreamEndEvent({
          'type': 'response.completed',
        }),
        isTrue,
      );
      expect(
        AiProviderProtocol.anthropicMessages.isStreamEndEvent({
          'type': 'message_stop',
        }),
        isTrue,
      );
      // Chat Completions 靠 [DONE] 字面量，不走事件判别。
      expect(
        AiProviderProtocol.chatCompletions.isStreamEndEvent({
          'type': 'anything',
        }),
        isFalse,
      );
      // 别家协议的结束事件不许被误判（双向）。
      expect(
        AiProviderProtocol.responses.isStreamEndEvent({'type': 'message_stop'}),
        isFalse,
      );
      expect(
        AiProviderProtocol.anthropicMessages.isStreamEndEvent({
          'type': 'response.completed',
        }),
        isFalse,
      );
      // 任意/空 type 都不能结束 Anthropic 流。
      expect(
        AiProviderProtocol.anthropicMessages.isStreamEndEvent({}),
        isFalse,
      );
      expect(
        AiProviderProtocol.anthropicMessages.isStreamEndEvent({'type': 'x'}),
        isFalse,
      );
    });
  });
  group('推理开关（docs/29 §P4）', () {
    test('disabled：仅 chat 请求体带 thinking，另两协议永不发', () {
      final jpeg = Uint8List.fromList([0xff, 0xd9]);
      for (final protocol in AiProviderProtocol.values) {
        final task = protocol.taskRequestBody(
          model: 'm',
          maxTokens: 10,
          prompt: 'p',
          reasoning: AiReasoningMode.disabled,
        );
        final conversation = protocol.conversationRequestBody(
          model: 'm',
          maxTokens: 10,
          systemPrompt: 'SYS',
          messages: const [(role: 'user', text: 'hi', image: null)],
          reasoning: AiReasoningMode.disabled,
        );
        final vision = protocol.visionRequestBody(
          model: 'm',
          maxTokens: 10,
          instruction: 'i',
          jpegBytes: jpeg,
          reasoning: AiReasoningMode.disabled,
        );
        if (protocol == AiProviderProtocol.chatCompletions) {
          expect(task['thinking'], {'type': 'disabled'}, reason: 'task');
          expect(conversation['thinking'], {
            'type': 'disabled',
          }, reason: 'conversation');
          expect(vision['thinking'], {'type': 'disabled'}, reason: 'vision');
        } else {
          expect(
            task.containsKey('thinking'),
            isFalse,
            reason: '$protocol task',
          );
          expect(
            conversation.containsKey('thinking'),
            isFalse,
            reason: '$protocol conversation',
          );
          expect(
            vision.containsKey('thinking'),
            isFalse,
            reason: '$protocol vision',
          );
        }
      }
    });

    test('providerDefault：三协议都不发 thinking', () {
      for (final protocol in AiProviderProtocol.values) {
        final task = protocol.taskRequestBody(
          model: 'm',
          maxTokens: 10,
          prompt: 'p',
          reasoning: AiReasoningMode.providerDefault,
        );
        expect(task.containsKey('thinking'), isFalse, reason: '$protocol');
      }
    });

    test('extractReasoningDelta：chat 读 delta.reasoning_content，另两协议恒 null', () {
      expect(
        AiProviderProtocol.chatCompletions.extractReasoningDelta({
          'choices': [
            {
              'delta': {'reasoning_content': '思考中'},
            },
          ],
        }),
        '思考中',
      );
      // 内容增量不算推理。
      expect(
        AiProviderProtocol.chatCompletions.extractReasoningDelta({
          'choices': [
            {
              'delta': {'content': '正文'},
            },
          ],
        }),
        isNull,
      );
      // 未实测的另两协议：推理事件恒返回 null（诚实边界）。
      expect(
        AiProviderProtocol.responses.extractReasoningDelta({
          'type': 'response.reasoning.delta',
          'delta': 'x',
        }),
        isNull,
      );
      expect(
        AiProviderProtocol.anthropicMessages.extractReasoningDelta({
          'type': 'content_block_delta',
          'delta': {'type': 'thinking_delta', 'thinking': 'x'},
        }),
        isNull,
      );
    });

    test('reasoningOnlyHint：只有 reasoning_content 时给出可解释错误', () {
      final hint = AiProviderProtocol.chatCompletions.reasoningOnlyHint({
        'choices': [
          {
            'message': {'content': null, 'reasoning_content': '推理了 160 字'},
          },
        ],
      });
      expect(hint, '模型只返回了推理内容，请在设置里关闭推理或增大输出上限。');

      // content 为空串同样算「只有推理」。
      final emptyString = AiProviderProtocol.chatCompletions.reasoningOnlyHint({
        'choices': [
          {
            'message': {'content': '', 'reasoning_content': '推理'},
          },
        ],
      });
      expect(emptyString, isNotNull);
    });

    test('reasoningOnlyHint：有正文 / 没有推理字段 / 形状不符 → null', () {
      final protocol = AiProviderProtocol.chatCompletions;
      // 有正文：不是推理-only。
      expect(
        protocol.reasoningOnlyHint({
          'choices': [
            {
              'message': {'content': '答案', 'reasoning_content': '推理'},
            },
          ],
        }),
        isNull,
      );
      // 没有 reasoning_content：走既有「格式无法识别」口径。
      expect(
        protocol.reasoningOnlyHint({
          'choices': [
            {
              'message': {'content': null},
            },
          ],
        }),
        isNull,
      );
      // 形状不符。
      expect(protocol.reasoningOnlyHint({}), isNull);
      expect(protocol.reasoningOnlyHint({'choices': []}), isNull);
      // 另两协议：恒 null（未实测不发 hint）。
      expect(
        AiProviderProtocol.responses.reasoningOnlyHint({'output_text': ''}),
        isNull,
      );
      expect(
        AiProviderProtocol.anthropicMessages.reasoningOnlyHint({'content': []}),
        isNull,
      );
    });
  });
}
