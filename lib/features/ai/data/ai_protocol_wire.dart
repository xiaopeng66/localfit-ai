import 'dart:convert';
import 'dart:typed_data';

import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';

/// 协议 wire 事实（docs/24 §4）：**每种协议的头、请求体、响应提取各只有一处
/// 定义**。六个 AI 出口（对话、工作台 6 任务、训练计划直连、拍照识别直连、
/// 语音转写）全部从这里取，禁止在各自的 service 里再写一遍。
/// （2026-10-04：食谱任务与食谱/周计划直连随 docs/28 W4 整族下线，7 → 6、
/// 3 条直连 → 2 条。）
///
/// 以 **extension on [AiProviderProtocol]** 的形式承载，而不是另立平行枚举：
/// 协议身份只有一个（用户在设置里选的那个），wire 行为挂在它身上；新增协议
/// 时每个 exhaustive switch 都会编译报错，逼你补齐每一项能力。
///
/// | 分歧点 | Chat Completions | Responses | Anthropic Messages |
/// |---|---|---|---|
/// | 路径 | `chat/completions` | `responses` | `messages` |
/// | system | `messages[0].role=system` | 顶层 `instructions` | 顶层 `system` |
/// | 输入键 | `messages` | `input` | `messages` |
/// | 输出上限 | `max_tokens` | `max_output_tokens` | `max_tokens`（**必填**）|
/// | 认证 | `Authorization: Bearer` | `Authorization: Bearer` | `x-api-key` + `anthropic-version` |
/// | 非流式回复 | `choices[0].message.content` | `output[].content[].text`（`output_text` 兜底）| `content[].text` |
/// | 流式增量 | `choices[].delta.content` | `response.output_text.delta` | `content_block_delta.delta.text` |
/// | 流结束 | `[DONE]` 字面量 | `response.completed` | `message_stop` |
///
/// **`temperature` 只在 Chat Completions 上发送**：既是保持既有请求体逐字节
/// 不变（egress 评测集的 sha256 钉住它），也是刻意的兼容性选择——Responses 在
/// 推理模型上直接拒绝该参数，Anthropic 的等价确定性由 prompt 模板里的严格
/// JSON 约束承担。少发一个可能被拒的可选参数，比多发一个更安全。
///
/// **`thinking` 同样只在 Chat Completions 上发送**（docs/29 §P4）：推理档为
/// [AiReasoningMode.disabled]（产品默认）时发 `{"type": "disabled"}`——推理型
/// 模型会把 token 花在 `reasoning_content` 上导致客户端渲染出空回复，实测该
/// 字段可关；[AiReasoningMode.providerDefault] 与另两协议一律不发（是否兼容
/// 未实测，诚实边界）。若某家上游拒绝该字段，用户切回「默认」档即可。
/// 对话里的一条消息（wire 视角，docs/24 §4）：角色 + 文本 + **可选一张图**。
///
/// [image] 是用户随这条消息发出的 JPEG 原始字节（App 每条消息最多一张，
/// docs/21 §5.7）；null = 纯文本消息——纯文本消息在三种协议下的请求形状与
/// 历史**逐字节一致**（egress 评测集按 sha256 钉住）。
typedef ConversationWireMessage = ({
  String role,
  String text,
  Uint8List? image,
});

extension AiProtocolWire on AiProviderProtocol {
  /// 认证头。**Key 只在这里出现**：不进 body、不进日志、不进任何文案。
  Map<String, String> authHeaders(String apiKey) => switch (this) {
    AiProviderProtocol.chatCompletions ||
    AiProviderProtocol.responses => {'authorization': 'Bearer $apiKey'},
    AiProviderProtocol.anthropicMessages => {
      'x-api-key': apiKey,
      // Anthropic 要求显式版本头；固定 2023-06-01（Messages API 的稳定版本，
      // 各家兼容网关都实现这一版）。
      'anthropic-version': '2023-06-01',
    },
  };

  /// 单条用户文本消息（工作台任务与训练/识别两条直连 provider 共用）。
  ///
  /// Chat Completions 分支的既有键序与取值逐字节保持不变（egress 评测集按
  /// sha256 钉住）；`thinking` 插在 `max_tokens` 与 `messages` 之间——仅当
  /// 推理档为「关闭推理」且协议为 chat 时存在（见类注释）。
  Map<String, Object> taskRequestBody({
    required String model,
    required int maxTokens,
    required String prompt,
    required AiReasoningMode reasoning,
  }) => switch (this) {
    AiProviderProtocol.chatCompletions => {
      'model': model.trim(),
      'temperature': 0,
      'max_tokens': maxTokens,
      if (reasoning == AiReasoningMode.disabled)
        'thinking': const {'type': 'disabled'},
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    },
    AiProviderProtocol.responses => {
      'model': model.trim(),
      'max_output_tokens': maxTokens,
      'input': [
        {'role': 'user', 'content': prompt},
      ],
    },
    AiProviderProtocol.anthropicMessages => {
      'model': model.trim(),
      'max_tokens': maxTokens,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    },
  };

  /// 单张 JPEG + 一段指令（拍照识别）。
  ///
  /// 三种协议的图片形状互不相同，这里一次说清：
  /// * Chat Completions：`image_url` 块，值为 data URL；
  /// * Responses：`input_image` 块，`image_url` 字段直接放 data URL；
  /// * Anthropic：`image` 块，`source` 里放**裸 base64**（不是 data URL）
  ///   与 media_type。
  Map<String, Object> visionRequestBody({
    required String model,
    required int maxTokens,
    required String instruction,
    required Uint8List jpegBytes,
    required AiReasoningMode reasoning,
  }) {
    final base64Image = base64Encode(jpegBytes);
    final dataUrl = 'data:image/jpeg;base64,$base64Image';
    return switch (this) {
      AiProviderProtocol.chatCompletions => {
        'model': model.trim(),
        'temperature': 0,
        'max_tokens': maxTokens,
        if (reasoning == AiReasoningMode.disabled)
          'thinking': const {'type': 'disabled'},
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': instruction},
              {
                'type': 'image_url',
                'image_url': {'url': dataUrl},
              },
            ],
          },
        ],
      },
      AiProviderProtocol.responses => {
        'model': model.trim(),
        'max_output_tokens': maxTokens,
        'input': [
          {
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': instruction},
              {'type': 'input_image', 'image_url': dataUrl},
            ],
          },
        ],
      },
      AiProviderProtocol.anthropicMessages => {
        'model': model.trim(),
        'max_tokens': maxTokens,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': instruction},
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/jpeg',
                  'data': base64Image,
                },
              },
            ],
          },
        ],
      },
    };
  }

  /// 对话请求体（流式）。
  ///
  /// [messages] 是已按时间排序的 `(role, text, image)` 三元组，role 只会有
  /// `user` /
  /// `assistant` 两种（system 走 [systemPrompt] / [systemContext]）。
  /// [ConversationWireMessage.image] 是**用户随这条消息发的图**的 JPEG 字节
  /// （null = 纯文本消息）。纯文本消息在三种协议下的形状与历史**逐字节一致**
  /// ——egress 评测集按 sha256 钉住它们；只有带图消息才出多模态块。
  ///
  /// Anthropic 分支会**合并相邻同角色消息**：协议要求 user/assistant 交替，
  /// 而本地历史里失败的助手回复会被排除，可能出现连续两条 user——合并后
  /// 语义不变（同一轮里的连续发言），且避免 400。
  Map<String, Object> conversationRequestBody({
    required String model,
    required int maxTokens,
    required String systemPrompt,
    String? systemContext,
    required List<ConversationWireMessage> messages,
    required AiReasoningMode reasoning,
  }) => switch (this) {
    AiProviderProtocol.chatCompletions => {
      'model': model.trim(),
      'stream': true,
      'max_tokens': maxTokens,
      if (reasoning == AiReasoningMode.disabled)
        'thinking': const {'type': 'disabled'},
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        // chat-edit 协议 + 快照（docs/23 §3）：第二条 system 消息，紧跟主
        // system prompt；null（构建失败/未接线）就不发，绝不发空串占位。
        if (systemContext != null && systemContext.isNotEmpty)
          {'role': 'system', 'content': systemContext},
        for (final message in messages)
          if (message.image == null)
            {'role': message.role, 'content': message.text}
          else
            {
              'role': message.role,
              'content': [
                {'type': 'text', 'text': message.text},
                {
                  'type': 'image_url',
                  'image_url': {'url': _jpegDataUrl(message.image!)},
                },
              ],
            },
      ],
    },
    AiProviderProtocol.responses => {
      'model': model.trim(),
      'stream': true,
      'max_output_tokens': maxTokens,
      // 快照与主 system 合并成一段 instructions：Responses 没有「多条
      // system」的概念，拆开会静默丢掉后一条。
      'instructions': [
        systemPrompt,
        if (systemContext != null && systemContext.isNotEmpty) systemContext,
      ].join('\n\n'),
      'input': [
        for (final message in messages)
          if (message.image == null)
            {'role': message.role, 'content': message.text}
          else
            {
              'role': message.role,
              'content': [
                {'type': 'input_text', 'text': message.text},
                {
                  'type': 'input_image',
                  'image_url': _jpegDataUrl(message.image!),
                },
              ],
            },
      ],
    },
    AiProviderProtocol.anthropicMessages => {
      'model': model.trim(),
      'stream': true,
      'max_tokens': maxTokens,
      'system': [
        systemPrompt,
        if (systemContext != null && systemContext.isNotEmpty) systemContext,
      ].join('\n\n'),
      'messages': _mergeAdjacentRoles(messages),
    },
  };

  /// 非流式响应里的助手文本。
  ///
  /// 形状不匹配一律返回 null（调用方转成「供应商返回格式无法识别」），
  /// **不猜**：宁可报格式错，也不把人肉拼出来的内容当成模型的回答。
  String? extractNonStreamContent(Map<String, Object?> json) => switch (this) {
    AiProviderProtocol.chatCompletions => _chatCompletionsContent(json),
    AiProviderProtocol.responses => _responsesContent(json),
    AiProviderProtocol.anthropicMessages => _anthropicContent(json),
  };

  /// 流式 SSE 事件里的增量文本；`null`＝该事件不带文本（心跳/元数据）。
  ///
  /// 事件类型用 `type` 字段判别：Responses 与 Anthropic 都是带类型的事件；
  /// Chat Completions 是裸 `choices` 增量，没有 type。
  String? extractDelta(Map<String, Object?> event) => switch (this) {
    AiProviderProtocol.chatCompletions => _chatCompletionsDelta(event),
    AiProviderProtocol.responses => _responsesDelta(event),
    AiProviderProtocol.anthropicMessages => _anthropicDelta(event),
  };

  /// 流式 SSE 事件里的**推理**增量（`reasoning_content` / thinking）；调用方
  /// 只用它判定「这条流只产出了推理」——文本本身不上屏。
  /// Chat Completions 是 `choices[].delta.reasoning_content`（实测推理型
  /// 模型的 14 条 delta 里 13 条是它）；另两协议的推理事件形状未实测，恒
  /// 返回 null（诚实边界，docs/29 §6）。
  String? extractReasoningDelta(Map<String, Object?> event) => switch (this) {
    AiProviderProtocol.chatCompletions => _chatCompletionsReasoningDelta(event),
    AiProviderProtocol.responses => null,
    AiProviderProtocol.anthropicMessages => null,
  };

  /// 非流式回复「只返回了推理、`content` 为空」时的**可解释错误**；
  /// null＝不是这种形状（调用方走既有的「格式无法识别」口径）。
  /// docs/29 §P4：不允许把推理型模型的空 `content` 静默渲染成空气泡。
  String? reasoningOnlyHint(Map<String, Object?> json) => switch (this) {
    AiProviderProtocol.chatCompletions => _chatCompletionsReasoningOnlyHint(
      json,
    ),
    AiProviderProtocol.responses => null,
    AiProviderProtocol.anthropicMessages => null,
  };

  /// 该事件是否表示「输出被截断」（2026-10-21 RV-P2-17）。
  ///
  /// 三协议的字段不同但语义一致：模型没说完就到了上限。返回给用户看的
  /// 一句话；null = 这一条不是截断信号。
  String? truncationNotice(Map<String, Object?> event) {
    switch (this) {
      case AiProviderProtocol.chatCompletions:
        final choices = event['choices'];
        if (choices is! List) return null;
        for (final choice in choices) {
          final map = _mapOrNull(choice);
          if (map?['finish_reason'] == 'length') {
            return '这段回复被输出上限截断，可能不完整。';
          }
        }
        return null;
      case AiProviderProtocol.responses:
        final type = event['type'];
        if (type == 'response.incomplete') {
          return '这段回复被输出上限截断，可能不完整。';
        }
        final response = _mapOrNull(event['response']);
        if (response?['status'] == 'incomplete') {
          return '这段回复被输出上限截断，可能不完整。';
        }
        return null;
      case AiProviderProtocol.anthropicMessages:
        if (event['type'] != 'message_delta') return null;
        final delta = _mapOrNull(event['delta']);
        if (delta?['stop_reason'] == 'max_tokens') {
          return '这段回复被输出上限截断，可能不完整。';
        }
        return null;
    }
  }

  /// 该事件是否表示流结束：Responses 发 `response.completed`，Anthropic 发
  /// `message_stop`，Chat Completions 靠 `[DONE]` 字面量（不走这里）。
  bool isStreamEndEvent(Map<String, Object?> event) {
    final type = event['type'];
    return switch (this) {
      AiProviderProtocol.chatCompletions => false,
      AiProviderProtocol.responses => type == 'response.completed',
      AiProviderProtocol.anthropicMessages => type == 'message_stop',
    };
  }
}

// ---------------------------------------------------------------- 各协议实现

List<Map<String, Object>> _mergeAdjacentRoles(
  List<ConversationWireMessage> messages,
) {
  final merged = <Map<String, Object>>[];
  for (final message in messages) {
    if (merged.isNotEmpty && merged.last['role'] == message.role) {
      merged.last['content'] = _mergeContent(merged.last['content']!, message);
      continue;
    }
    merged.add({
      'role': message.role,
      'content': _anthropicMessageContent(message),
    });
  }
  return merged;
}

/// Anthropic 的一条 message 的 `content`：纯文本消息是**字符串**（历史形状
/// 逐字节不变），带图消息是块列表（`text` 块 + `image` 块，图片用**裸
/// base64**——不是 data URL，这是 Anthropic 与另两协议的分歧点）。
Object _anthropicMessageContent(ConversationWireMessage message) {
  final image = message.image;
  if (image == null) return message.text;
  return <Object>[
    {'type': 'text', 'text': message.text},
    {
      'type': 'image',
      'source': {
        'type': 'base64',
        'media_type': 'image/jpeg',
        'data': base64Encode(image),
      },
    },
  ];
}

/// 合并相邻同角色消息的 content：
/// * 两侧都是纯文本 → 保持历史的 `'前\n\n后'` 字符串拼接（逐字节不变）；
/// * 任一侧带图 → 统一成块列表；两条的文本段并进同一个 `text` 块
///   （不产生两个相邻 text 块），图片段依次追加。
Object _mergeContent(Object previous, ConversationWireMessage message) {
  final incoming = _anthropicMessageContent(message);
  if (previous is String && incoming is String) {
    return '$previous\n\n$incoming';
  }
  final blocks = <Object>[
    if (previous is String)
      {'type': 'text', 'text': previous}
    else
      ...previous as List<Object>,
  ];
  final incomingBlocks = <Object>[
    if (incoming is String)
      {'type': 'text', 'text': incoming}
    else
      ...incoming as List<Object>,
  ];
  if (blocks.isNotEmpty &&
      incomingBlocks.isNotEmpty &&
      blocks.last is Map &&
      (blocks.last as Map)['type'] == 'text' &&
      incomingBlocks.first is Map &&
      (incomingBlocks.first as Map)['type'] == 'text') {
    final head = blocks.removeLast() as Map;
    final tail = incomingBlocks.removeAt(0) as Map;
    blocks.add({'type': 'text', 'text': '${head['text']}\n\n${tail['text']}'});
  }
  return <Object>[...blocks, ...incomingBlocks];
}

/// 把 JPEG 字节编成 Chat Completions / Responses 共用的 data URL。
String _jpegDataUrl(Uint8List jpegBytes) =>
    'data:image/jpeg;base64,${base64Encode(jpegBytes)}';

String? _chatCompletionsContent(Map<String, Object?> json) {
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = _mapOrNull(choices.first);
  if (first == null) return null;
  final message = _mapOrNull(first['message']);
  if (message == null) return null;
  final content = message['content'];
  if (content is String) return content.isEmpty ? null : content;
  if (content is List) {
    final joined = _joinTextBlocks(content, textType: 'text');
    return joined.isEmpty ? null : joined;
  }
  // 供应商原生 JSON 对象内容（既有行为：编码回紧凑 JSON）。
  if (content is Map) {
    final normalized = _mapOrNull(content);
    if (normalized == null) return null;
    return jsonEncode(normalized);
  }
  return null;
}

String? _chatCompletionsDelta(Map<String, Object?> event) {
  final choices = event['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = _mapOrNull(choices.first);
  if (first == null) return null;
  final delta = _mapOrNull(first['delta']);
  final content = delta?['content'];
  if (content is String && content.isNotEmpty) return content;
  return null;
}

String? _chatCompletionsReasoningDelta(Map<String, Object?> event) {
  final choices = event['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = _mapOrNull(choices.first);
  if (first == null) return null;
  final delta = _mapOrNull(first['delta']);
  final reasoning = delta?['reasoning_content'];
  if (reasoning is String && reasoning.isNotEmpty) return reasoning;
  return null;
}

/// `content` 为空/缺失而 `reasoning_content` 有货 ⇒ 推理吃掉了全部输出
/// （实测两种成因：模型默认推理，或 `max_tokens` 太小被推理耗尽、
/// `finish_reason=length`）。文案同时覆盖两种解法。
String? _chatCompletionsReasoningOnlyHint(Map<String, Object?> json) {
  final choices = json['choices'];
  if (choices is! List || choices.isEmpty) return null;
  final first = _mapOrNull(choices.first);
  if (first == null) return null;
  final message = _mapOrNull(first['message']);
  if (message == null) return null;
  final content = message['content'];
  final hasContent =
      (content is String && content.isNotEmpty) ||
      (content is List &&
          _joinTextBlocks(content, textType: 'text').isNotEmpty) ||
      content is Map;
  if (hasContent) return null;
  final reasoning = message['reasoning_content'];
  if (reasoning is String && reasoning.isNotEmpty) {
    return '模型只返回了推理内容，请在设置里关闭推理或增大输出上限。';
  }
  return null;
}

String? _responsesContent(Map<String, Object?> json) {
  // 便捷字段：Responses 提供 output_text（SDK 侧聚合），但**不能只认它**——
  // 自建网关/中转常只回 output 数组。两者都认，优先 output 数组（原始事实）。
  final output = json['output'];
  if (output is List) {
    final buffer = StringBuffer();
    for (final item in output) {
      final map = _mapOrNull(item);
      if (map == null || map['type'] != 'message') continue;
      final content = map['content'];
      if (content is! List) continue;
      buffer.write(_joinTextBlocks(content, textType: 'output_text'));
    }
    final joined = buffer.toString();
    if (joined.isNotEmpty) return joined;
  }
  final outputText = json['output_text'];
  if (outputText is String && outputText.isNotEmpty) return outputText;
  return null;
}

String? _responsesDelta(Map<String, Object?> event) {
  if (event['type'] != 'response.output_text.delta') return null;
  final delta = event['delta'];
  if (delta is String && delta.isNotEmpty) return delta;
  return null;
}

String? _anthropicContent(Map<String, Object?> json) {
  final content = json['content'];
  if (content is! List) return null;
  final joined = _joinTextBlocks(content, textType: 'text');
  return joined.isEmpty ? null : joined;
}

String? _anthropicDelta(Map<String, Object?> event) {
  if (event['type'] != 'content_block_delta') return null;
  final delta = _mapOrNull(event['delta']);
  if (delta == null || delta['type'] != 'text_delta') return null;
  final text = delta['text'];
  if (text is String && text.isNotEmpty) return text;
  return null;
}

/// 拼接 `[{'type': <textType>, 'text': ...}]` 形状的文本块；非文本块跳过。
String _joinTextBlocks(List<Object?> blocks, {required String textType}) {
  final buffer = StringBuffer();
  for (final block in blocks) {
    final map = _mapOrNull(block);
    if (map == null || map['type'] != textType) continue;
    final text = map['text'];
    if (text is String) buffer.write(text);
  }
  return buffer.toString();
}

Map<String, Object?>? _mapOrNull(Object? value) {
  if (value is! Map) return null;
  final out = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) return null;
    out[key] = entry.value;
  }
  return out;
}
