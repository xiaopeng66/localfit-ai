import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/features/ai/data/ai_protocol_wire.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';
import 'package:localfit_ai/features/settings/domain/open_ai_compatible_endpoint.dart';
import 'package:localfit_ai/features/ai_conversation/domain/ai_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';

/// BYOK AI 对话服务（三种协议，docs/24）。
///
/// 与工作台/识别/训练三类出口共用同一张协议表
/// （[AiProtocolWire]）：路径、认证头、请求体形状、SSE 增量提取全部来自
/// 那里；本文件只负责**流式装配**——按 `data:` 行切 SSE、判断结束、把增量
/// 交给 controller。
///
/// 与非流式出口的差别只有一处：这里必须处理**跨 chunk 切断**。网络分块
/// 可以落在任意字节位置（包括一个多字节 UTF-8 字符中间，或一条 SSE 事件
/// 中间），所以：
/// * 字节层用 `Utf8Decoder(allowMalformed: true)` 的**流式**解码，让被切断
///   的多字节序列在下一个 chunk 到达时正确接上；
/// * 行层持一个残留缓冲，只有见到完整行才解析——半行 JSON 直接 `jsonDecode`
///   会 FormatException，旧实现就是这么静默丢增量的。
class OpenAiCompatibleConversationService implements AiConversationService {
  OpenAiCompatibleConversationService({
    required this.dio,
    required this.configurationReader,
    required this.apiKeyStore,
    this.maxRequestBytes = 64 * 1024,
    this.maxRequestBytesWithImage = 8 * 1024 * 1024,
    this.maxOutputTokens = 3000,
    this.maxResponseBytes = 512 * 1024,
    this.maxStreamDuration = const Duration(minutes: 3),
  });

  static const maxModelLength = 256;

  final Dio dio;
  final AiProviderConfigurationReader configurationReader;
  final AiApiKeyStore apiKeyStore;
  final int maxRequestBytes;

  /// **本条请求带图**时的上限（2026-10-16 实时实测补）。
  ///
  /// 64 KiB 是给纯文字请求定的（快照+历史有界）。但手机照片动辄 1–5 MB，
  /// 经 base64 膨胀 4/3 后必然超过 64 KiB —— 实测一张 49 KB 的图就被判
  /// 「对话内容过长，请精简后重试。」，也就是说**真照片根本发不出去**。
  /// 带图这一趟放到与识餐出口同档（那边是 5 MiB 图 / 7 MiB 请求）。
  final int maxRequestBytesWithImage;
  final int maxOutputTokens;

  /// 流式回复的**累计**字节上限与总时长上限。请求侧一直有 64 KiB 上限，响应
  /// 侧以前只有 dio 的 `receiveTimeout`（45s，是「两次 chunk 之间」而不是总
  /// 时长）——供应商若持续吐字节（恶意的无限 SSE、或网关把长连接一直挂着），
  /// 累积的增量会无界增长直到 OOM，用户按返回也没有任何中止点。
  ///
  /// 512 KiB 远高于任何合法回复：`maxOutputTokens` 3000 的正文不到 12 KB，
  /// SSE 帧的 JSON 包装通常放大 5–10 倍。总时长 3 分钟同样宽松——正常回复
  /// 是秒级。
  final int maxResponseBytes;
  final Duration maxStreamDuration;

  static const _systemPrompt =
      '你是 LocalFit AI 助手，一位专业的健康饮食与训练顾问。'
      '如果消息里提供了「当前可编辑数据快照」，说明用户授权你基于这些数据'
      '回答与提议修改；修改提议只有在用户点「应用」后才会生效。'
      '请用简洁、友好的语气回答问题，必要时可以建议具体的饮食或训练调整。'
      '所有回复使用简体中文。';

  @override
  Stream<String> sendMessage({
    required List<ConversationMessage> messages,
    required void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext,
  }) {
    final controller = StreamController<String>();

    _send(controller, messages, onProgress, cancelToken, systemContext);

    return controller.stream;
  }

  /// 带图请求被供应商拒绝时，**去掉图片重发一次**并如实说明原因。
  ///
  /// 2026-10-16 用户实测缺陷：「打开 app 的 ai 对话显示发送失败，点击重试」
  /// ——图像一旦进了历史，之后**每次**发送都会重发它；只要供应商的模型不
  /// 支持图片输入（多数网关回 400），整个对话就永久发不出去。有界降级
  /// （最多一次、不带图）把对话救回来，同时把事实写进回复开头：
  /// 图没发出去、为什么、以及要看图该怎么办。
  static const imageRejectionNote =
      '（供应商拒绝了带图片的请求——当前模型可能不支持图片输入。'
      '这条已经改用**纯文字**重发；想让我看图，请在设置里换一个支持视觉的模型。）';

  Future<void> _send(
    StreamController<String> controller,
    List<ConversationMessage> messages,
    void Function(String chunk) onProgress,
    Stream<void>? cancelToken,
    String? systemContext, {
    bool includeImages = true,
    String? leadingNote,
    bool imageFallbackUsed = false,
  }) async {
    final dioCancelToken = CancelToken();
    try {
      final configuration = await _loadConfiguration();
      final protocol = configuration.protocol;
      final endpoint = _parseEndpoint(configuration);
      final apiKey = await _readApiKey();
      final built = await _buildBody(
        protocol: protocol,
        model: configuration.model,
        messages: messages,
        systemContext: systemContext,
        reasoning: configuration.reasoning,
        includeImages: includeImages,
      );
      final body = built.body;
      // 「去图重发」这一趟要先把原因播给用户与上屏（不静默）。
      if (leadingNote != null) {
        onProgress(leadingNote);
        controller.add(leadingNote);
      }

      final requestBytes = utf8.encode(body).length;
      // 带图就放到 8 MiB（真照片才发得出去），纯文字仍守 64 KiB。
      final limit = built.hasImage ? maxRequestBytesWithImage : maxRequestBytes;
      if (requestBytes > limit) {
        throw const ValidationFailure('对话内容过长，请精简后重试。');
      }

      cancelToken?.listen((_) => dioCancelToken.cancel());

      final response = await dio.requestUri<ResponseBody>(
        endpoint.requestUri,
        data: body,
        cancelToken: dioCancelToken,
        options: Options(
          method: 'POST',
          headers: {
            Headers.acceptHeader: Headers.jsonContentType,
            ...protocol.authHeaders(apiKey),
          },
          contentType: Headers.jsonContentType,
          responseType: ResponseType.stream,
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 45),
          followRedirects: false,
          maxRedirects: 0,
          receiveDataWhenStatusError: false,
          validateStatus: (status) => status == 200,
        ),
      );

      if (response.statusCode != 200 || response.data == null) {
        throw _mapStatus(response.statusCode);
      }

      await _streamResponse(
        protocol: protocol,
        stream: response.data!.stream,
        controller: controller,
        onProgress: onProgress,
        cancelToken: dioCancelToken,
      );
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        // 取消不是错误，静默结束。
        controller.close();
        return;
      }
      final status = error.response?.statusCode;
      final rejected = status == 400 || status == 422;
      if (includeImages && rejected && !imageFallbackUsed) {
        // 带图被拒 ⇒ 去图重发一次（有界：`imageFallbackUsed` 挡住二次降级）。
        await _send(
          controller,
          messages,
          onProgress,
          cancelToken,
          systemContext,
          includeImages: false,
          leadingNote: imageRejectionNote,
          imageFallbackUsed: true,
        );
        return;
      }
      controller.addError(_mapDioError(error));
    } catch (error) {
      controller.addError(error);
    } finally {
      if (!controller.isClosed) {
        controller.close();
      }
    }
  }

  /// 逐 chunk 解析 SSE。**行缓冲 + 流式 UTF-8 解码**是这里的两个正确性
  /// 要件（见类注释）：任何一条事件被网络切在两块之间都不能丢。
  ///
  /// 实现上把字节流交给 [utf8.decoder] 的流式版本，再按行积攒；只剩最后
  /// 一行没有换行时留在缓冲里等下一块——**不解析半行**。
  Future<void> _streamResponse({
    required AiProviderProtocol protocol,
    required Stream<List<int>> stream,
    required StreamController<String> controller,
    required void Function(String chunk) onProgress,
    required CancelToken cancelToken,
  }) async {
    var sawDone = false;
    // 空回复兜底（docs/29 §P4）：推理型模型的流里全是 `reasoning_content`
    // 增量，`extractDelta` 一条都拿不到 ⇒ 静默空气泡。流结束时若「有过推理
    // 增量、零内容增量」，给出可解释错误而不是空气泡。
    var sawContent = false;
    var sawReasoning = false;
    String? truncationNotice;

    void handleLine(String rawLine) {
      if (sawDone) return;
      // 兼容 CRLF（`\r\n`）与纯 LF：两个协议族都出现过。
      final line = rawLine.endsWith('\r')
          ? rawLine.substring(0, rawLine.length - 1)
          : rawLine;
      if (!line.startsWith('data:')) return;
      // `data:` 后允许一个空格；没有空格的写法也存在（谨慎兼容）。
      var payload = line.substring(5);
      if (payload.startsWith(' ')) payload = payload.substring(1);
      payload = payload.trim();
      if (payload.isEmpty) return;
      if (payload == '[DONE]') {
        sawDone = true;
        return;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        // 单条事件不是合法 JSON：跳过这一条，不影响后面的增量。
        return;
      }
      if (decoded is! Map) return;
      final event = <String, Object?>{
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      truncationNotice ??= protocol.truncationNotice(event);
      if (protocol.isStreamEndEvent(event)) {
        sawDone = true;
        return;
      }
      final delta = protocol.extractDelta(event);
      if (delta != null && delta.isNotEmpty) {
        sawContent = true;
        onProgress(delta);
        controller.add(delta);
        return;
      }
      if (protocol.extractReasoningDelta(event) != null) {
        sawReasoning = true;
      }
    }

    // 用 `utf8.decoder.bind(...)` 而不是 `Stream.transform`：后者的泛型是
    // `StreamTransformer<Uint8List, String>`，而这里拿到的是 `Stream<List<int>>`
    // （dio 的 ResponseBody.stream 声明），transform 会在运行时类型检查上炸。
    // bind 接受 `Stream<List<int>>`，且同样是**流式**解码——被切断的多字节
    // 序列会保留在解码器内部等下一个 chunk 接上。
    //
    // 计数与计时挂在**字节层**（解码之前）：字符数受编码方式影响，字节才是
    // 「这块内存有多大」的直说；同理，永不换行的流也会被这个上限挡住，
    // LineSplitter 不会攒出无界的一行。
    final deadline = Stopwatch()..start();
    var receivedBytes = 0;
    Stream<List<int>> guardBytes(Stream<List<int>> source) async* {
      await for (final chunk in source) {
        receivedBytes += chunk.length;
        // 抛 NetworkFailure（AppFailure 家族）：`_send` 的 catch 会把它原样
        // 交给 controller，UI 上显示的就是这两句中文而不是 Dio 英文异常。
        if (receivedBytes > maxResponseBytes) {
          throw NetworkFailure(
            '供应商返回内容超出上限（>${maxResponseBytes ~/ 1024} KiB），'
            '已中止本次回复。',
            kind: NetworkFailureKind.invalidResponse,
          );
        }
        if (deadline.elapsed > maxStreamDuration) {
          throw NetworkFailure(
            '本次回复累计超时（>${maxStreamDuration.inMinutes} 分钟），'
            '已中止。',
            kind: NetworkFailureKind.timeout,
          );
        }
        yield chunk;
      }
    }

    final lines = utf8.decoder
        .bind(guardBytes(stream))
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (cancelToken.isCancelled) return;
      handleLine(line);
      if (sawDone) break;
    }
    // 流走到了头（自然结束或 [DONE]）：一条内容增量都没有、但确实有过推理
    // 增量 ⇒ 报可解释错误（AppFailure 家族，UI 显示中文文案），不静默。
    // 注意 cancel 分支在上面直接 return，不会误伤「用户主动中止」。
    // 2026-10-21 RV-P2-17：截断必须如实标注（不静默当正常结束）。
    final notice = truncationNotice;
    if (notice != null) {
      if (sawContent) {
        controller.add('\n\n（$truncationNotice）');
      } else {
        controller.addError(
          NetworkFailure(notice, kind: NetworkFailureKind.invalidResponse),
        );
      }
    }
    if (!sawContent && sawReasoning) {
      controller.addError(
        const NetworkFailure(
          '模型只返回了推理内容，请在设置里关闭推理或增大输出上限。',
          kind: NetworkFailureKind.invalidResponse,
        ),
      );
    }
  }

  /// 拼请求体。**带图消息会把图真的编进去**（2026-10-16，S1）：用户随消息
  /// 发的那张图按各协议的图片块形状发给你配置的供应商；纯文本消息的形状与
  /// 历史逐字节一致。
  Future<({String body, bool hasImage})> _buildBody({
    required AiProviderProtocol protocol,
    required String model,
    required List<ConversationMessage> messages,
    required String? systemContext,
    required AiReasoningMode reasoning,
    bool includeImages = true,
  }) async {
    final wire = <ConversationWireMessage>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      // 只有**正在发的这一条**（列表末条）读不到图时才硬失败（用户能重选）；
      // 历史消息的图不在了就如实写进那条的文字里，绝不让一次旧图缺失把整个
      // 对话卡死（2026-10-16 用户实测缺陷：一旦卡死，每次发送都会重发它）。
      final isCurrent = i == messages.length - 1;
      String? missingImageNote;
      Uint8List? image;
      if (includeImages) {
        try {
          image = await _readMessageImage(message);
        } on ValidationFailure {
          if (isCurrent) rethrow;
          missingImageNote = _missingImageNote;
        }
      }
      wire.add((
        role: message.role == ConversationRole.user ? 'user' : 'assistant',
        text: missingImageNote == null
            ? message.text
            : '${message.text}${message.text.isEmpty ? '' : ' '}$missingImageNote',
        image: image,
      ));
    }
    return (
      body: jsonEncode(
        protocol.conversationRequestBody(
          model: model,
          maxTokens: maxOutputTokens,
          systemPrompt: _systemPrompt,
          systemContext: systemContext,
          reasoning: reasoning,
          messages: wire,
        ),
      ),
      hasImage: wire.any((message) => message.image != null),
    );
  }

  /// 历史消息的图不在了时，写进那条文字里的如实说明。
  static const _missingImageNote = '（这条消息里的图片已不在本机，未随本条发送。）';

  /// 这条消息随附的图片字节（没有图 → null）。
  ///
  /// 读不到就**如实失败**：抛 [ValidationFailure]（页面显示成人话），绝不
  /// 静默降级成「只发文字」——那正是 2026-10-16 这轮要修的缺陷（用户以为
  /// 图发出去了，模型其实没看到）。
  Future<Uint8List?> _readMessageImage(ConversationMessage message) async {
    if (message.kind != ConversationMessageKind.image) return null;
    final path = message.imagePath;
    if (path == null || path.isEmpty) return null;
    try {
      return await File(path).readAsBytes();
    } on FileSystemException {
      throw const ValidationFailure('这条消息的图片读不到了，请重新选择图片再发。');
    }
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

  NetworkFailure _mapStatus(int? status) {
    if (status == 401 || status == 403) {
      return const NetworkFailure(
        'API Key 无效或无权使用该服务。',
        kind: NetworkFailureKind.authentication,
      );
    }
    if (status == 429) {
      return const NetworkFailure(
        '服务请求过于频繁，请稍后手动重试。',
        kind: NetworkFailureKind.rateLimited,
      );
    }
    if (status == 408 || (status != null && status >= 500)) {
      return const NetworkFailure(
        '供应商暂时不可用，请稍后手动重试。',
        kind: NetworkFailureKind.serviceUnavailable,
      );
    }
    return const NetworkFailure(
      '供应商拒绝了该请求。',
      kind: NetworkFailureKind.requestRejected,
    );
  }

  NetworkFailure _mapDioError(DioException error) {
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const NetworkFailure(
        'AI 请求超时，请稍后重试。',
        kind: NetworkFailureKind.timeout,
      );
    }
    if (error.type == DioExceptionType.connectionError) {
      return const NetworkFailure(
        '网络连接不可用，请检查网络后重试。',
        kind: NetworkFailureKind.connection,
      );
    }
    final status = error.response?.statusCode;
    if (status != null) return _mapStatus(status);
    return const NetworkFailure(
      '网络连接不可用，请检查网络后重试。',
      kind: NetworkFailureKind.connection,
    );
  }
}
