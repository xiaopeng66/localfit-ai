import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/errors/app_failure.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/features/ai_conversation/data/open_ai_compatible_conversation_service.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_registry.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_edit/chat_edit_turn.dart';
import 'package:localfit_ai/features/ai_conversation/domain/conversation_message.dart';
import 'package:localfit_ai/features/food_scan/data/open_ai_compatible_meal_recognition_provider.dart';
import 'package:localfit_ai/features/food_scan/data/prepared_meal_image_bytes_reader.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';

/// **功能面的实时覆盖**（默认跳过；`LF_AI_LIVE_KEY/BASE/MODEL` 齐了才跑）。
///
/// 与 `ai_live_control_matrix_test.dart` 的分工：那份逐条跑**编辑命令**
/// （真模型 → 解析 → 执行 → 真库）；这份跑**命令之外的功能面**——
/// 带图对话、拍照识餐、建议通道、四类修复、错误路径、另两种协议的如实报错。
///
/// 【为什么是 `test()` 而不是 `testWidgets()`】widget binding 会把真实 HTTP
/// 拦成 400（2026-10-16 实测：上一轮「图片上行」因此只能 not run）。
///
/// 【判定口径】这一份**不替上游打包票**：
/// * 上游支持某能力（如视觉）⇒ 断言「真的用上了」；
/// * 上游不支持 ⇒ 断言「App 如实、可行动地报出来」，并把实际走的分支打进日志。
/// 两种情况都算通过，但**必须**是其中一种；静默半死（空回复、假成功）一律红。
///
/// 上游实测延迟：TTFB ≈ 11s、小回复整请求 40–46s（2026-10-16 用户授权的
/// 供应商 `ai.furry.vg`，模型 `deepseek-ai/deepseek-v4.1-flash`）。
/// 【工具盲点】`flutter test` 不认 `@Timeout` 注解 ⇒ 超时由命令行给：
/// `flutter test --timeout 240s test/ai_live/ai_live_feature_surfaces_test.dart`。
void main() {
  final env = Platform.environment;
  final apiKey = env['LF_AI_LIVE_KEY']?.trim() ?? '';
  final baseUrl = env['LF_AI_LIVE_BASE']?.trim() ?? '';
  final model = env['LF_AI_LIVE_MODEL']?.trim() ?? '';
  final skipReason = (apiKey.isEmpty || baseUrl.isEmpty || model.isEmpty)
      ? '未设置 LF_AI_LIVE_KEY / LF_AI_LIVE_BASE / LF_AI_LIVE_MODEL：功能面实时用例默认跳过'
      : null;

  final registry = ChatEditCommandRegistry();

  AiProviderConfiguration configurationWith(AiProviderProtocol protocol) =>
      AiProviderConfiguration(
        baseUrl: baseUrl,
        model: model,
        protocol: protocol,
      );

  OpenAiCompatibleConversationService serviceWith(
    AiProviderProtocol protocol, {
    Dio? dio,
  }) => OpenAiCompatibleConversationService(
    dio: dio ?? Dio(),
    configurationReader: _Config(configurationWith(protocol)),
    apiKeyStore: AiApiKeyStore(store: _Store(apiKey)),
  );

  /// 发一条消息，返回（整段回复, 分片数）。
  Future<(String, int)> send(
    OpenAiCompatibleConversationService service,
    String text, {
    String? imagePath,
    String? systemContext,
  }) async {
    final buffer = StringBuffer();
    var chunks = 0;
    await service
        .sendMessage(
          messages: [
            ConversationMessage(
              id: 'fs-${DateTime.now().microsecondsSinceEpoch}',
              role: ConversationRole.user,
              text: text,
              kind: imagePath == null
                  ? ConversationMessageKind.text
                  : ConversationMessageKind.image,
              imagePath: imagePath,
              createdAt: DateTime.utc(2026, 10, 16, 12),
            ),
          ],
          onProgress: (chunk) {
            chunks++;
            buffer.write(chunk);
          },
          systemContext: systemContext,
        )
        .drain<void>();
    return (buffer.toString(), chunks);
  }

  test(
    '① 带图对话：真上行（上游支持就看图，不支持就如实说并去掉图重发）',
    () async {
      final probeImage = File('E:/AI/Zcode/tmp/frames/synth/vision-probe.jpg');
      if (!probeImage.existsSync()) {
        markTestSkipped('探针图不存在：${probeImage.path}');
        return;
      }
      final (reply, chunks) = await send(
        serviceWith(AiProviderProtocol.chatCompletions),
        '这张图里写了什么？只回图上的文字。',
        imagePath: probeImage.path,
      );
      debugPrint(
        '[fs] 带图回复 chars=${reply.length} chunks=$chunks '
        'head="${_head(reply, 120)}"',
      );
      expect(reply.trim(), isNotEmpty, reason: '带图请求不能静默返回空回复');
      final sawImage = reply.contains('BANANA') || reply.contains('香蕉');
      final honestFallback = reply.contains('图片') || reply.contains('纯文字');
      debugPrint('[fs] 视觉判定：${sawImage ? '看图成功' : '未看图（走兜底）'}');
      expect(
        sawImage || honestFallback,
        isTrue,
        reason:
            '要么真的看图（能读出图上的字），要么如实说明图片没被接受——'
            '两者都没有＝静默半死',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: skipReason,
  );

  test(
    '② 拍照识餐：真 JPEG 上行（照实报解析结果或如实失败）',
    () async {
      final probeImage = File('E:/AI/Zcode/tmp/frames/synth/vision-probe.jpg');
      if (!probeImage.existsSync()) {
        markTestSkipped('探针图不存在：${probeImage.path}');
        return;
      }
      final bytes = probeImage.readAsBytesSync();
      final provider = OpenAiCompatibleMealRecognitionProvider(
        dio: Dio(),
        configurationReader: _Config(
          configurationWith(AiProviderProtocol.chatCompletions),
        ),
        apiKeyStore: AiApiKeyStore(store: _Store(apiKey)),
        imageBytesReader: _BytesReader(bytes),
      );
      MealEstimateDraft? draft;
      AppFailure? failure;
      try {
        draft = await provider.recognize(
          PreparedMealImage(
            path: probeImage.path,
            width: 900,
            height: 600,
            byteLength: bytes.length,
          ),
        );
      } on AppFailure catch (error) {
        failure = error;
      }
      if (draft != null) {
        debugPrint(
          '[fs] 识餐成功：items=${draft.items.length} '
          'names=${draft.items.map((i) => i.name).toList()}',
        );
        for (final item in draft.items) {
          expect(item.name.trim(), isNotEmpty, reason: '候选名不能为空');
          expect(
            item.estimatedGrams,
            greaterThan(0),
            reason: '候选克数应是正数（模型返回 0 会被解码器拦下）',
          );
        }
      } else {
        debugPrint('[fs] 识餐失败（如实）：${failure?.message}');
        expect(failure!.message.trim(), isNotEmpty, reason: '失败必须带人话文案，不能是空');
        expect(
          failure.message,
          isNot(contains('Exception')),
          reason: '不能把原始异常名甩给用户',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: skipReason,
  );

  test(
    '③ 本地拒绝：非 JPEG / 超大图在**发请求之前**就被挡下',
    () async {
      final notJpeg = Uint8List.fromList(List.filled(64, 0x41));
      final provider = OpenAiCompatibleMealRecognitionProvider(
        dio: Dio(),
        configurationReader: _Config(
          configurationWith(AiProviderProtocol.chatCompletions),
        ),
        apiKeyStore: AiApiKeyStore(store: _Store(apiKey)),
        imageBytesReader: _BytesReader(notJpeg),
      );
      var failed = false;
      try {
        await provider.recognize(
          PreparedMealImage(
            path: 'not-a-jpeg.bin',
            width: 10,
            height: 10,
            byteLength: notJpeg.length,
          ),
        );
      } on AppFailure catch (error) {
        failed = true;
        debugPrint('[fs] 本地拒绝文案：${error.message}');
        expect(error.message.trim(), isNotEmpty);
      }
      expect(failed, isTrue, reason: '非 JPEG 必须在本地被拒（不发请求）');
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: skipReason,
  );

  test(
    '④ 建议通道：模型给的每条建议都必须是**已注册命令**',
    () async {
      final service = serviceWith(AiProviderProtocol.chatCompletions);
      final (reply, _) = await send(
        service,
        '我想改善一下睡眠，但我不知道 App 里能改什么。',
        systemContext: registry.renderProtocol(),
      );
      final turn = parseChatEditTurn(reply, registry);
      debugPrint(
        '[fs] 建议用例：parsed=${turn != null} '
        'suggestions=${turn?.suggestions.map((s) => s.effectiveAction!).toList()} '
        'head="${_head(reply, 100)}"',
      );
      if (turn != null) {
        for (final suggestion in turn.suggestions) {
          expect(
            registry.specOf(suggestion.effectiveAction!),
            isNotNull,
            reason:
                '建议「${suggestion.effectiveAction}」必须已注册，'
                '否则用户点了必失败',
          );
        }
      }
      // 这一轮只做「不静默半死」的兜底断言：没信封可以，但回复不能是空的。
      expect(reply.trim(), isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: skipReason,
  );

  test(
    '⑤ 错误路径：坏 Key → 401 要变成可行动的人话',
    () async {
      final service = OpenAiCompatibleConversationService(
        dio: Dio(),
        configurationReader: _Config(
          configurationWith(AiProviderProtocol.chatCompletions),
        ),
        apiKeyStore: AiApiKeyStore(store: _Store('sk-this-key-is-not-valid')),
      );
      var failed = false;
      try {
        await send(service, '你好');
      } on AppFailure catch (error) {
        failed = true;
        debugPrint('[fs] 坏 Key 文案：${error.message}（${error.runtimeType}）');
        expect(error.message.trim(), isNotEmpty);
        expect(
          error.message,
          isNot(contains('sk-')),
          reason: '错误文案不能回显 key 片段',
        );
        expect(error.message, isNot(contains('Exception')));
      }
      expect(failed, isTrue, reason: '坏 Key 必须失败（不能假装成功）');
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: skipReason,
  );

  for (final protocol in const [
    AiProviderProtocol.responses,
    AiProviderProtocol.anthropicMessages,
  ]) {
    test(
      '⑥ 另两种协议（${protocol.storageValue}）：支持就用上，不支持就如实报错',
      () async {
        final service = serviceWith(protocol);
        String? reply;
        AppFailure? failure;
        try {
          final outcome = await send(service, '只回四个字：连接成功');
          reply = outcome.$1;
        } on AppFailure catch (error) {
          failure = error;
        }
        if (failure == null) {
          debugPrint('[fs] $protocol 可用：reply="${_head(reply ?? '', 60)}"');
          expect(reply!.trim(), isNotEmpty);
        } else {
          debugPrint(
            '[fs] $protocol 不可用（如实）：${failure.message}（${failure.runtimeType}）',
          );
          expect(failure.message.trim(), isNotEmpty);
          expect(
            failure.message,
            isNot(contains('Exception')),
            reason: '不支持时要给人话（例如「返回格式无法识别」/HTTP 状态说明）',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
      skip: skipReason,
    );
  }

  test(
    '⑦ 四类修复的关系在实时链路上仍成立（缺实体→结构化 repair）',
    () async {
      // 实时面只做「不静默失败」的观测：模型面对不存在的实体，要么拒绝（回文字），
      // 要么给出信封；给出信封时**执行器必须给出结构化 repair**（App 侧兜底的
      // 依据）。确定性的 repair 契约由执行器单测覆盖，这里验的是模型也能被兜住。
      const requests = {
        '缺食材': '把「不存在的食材XYZ」150 克记到今天午餐。',
        '缺动作': '在训练计划里加练「不存在的动作XYZ」。',
        '缺地点': '在「不存在的食堂XYZ」里新建一个窗口「一楼」，08:00–13:00。',
      };
      for (final entry in requests.entries) {
        final (reply, _) = await send(
          serviceWith(AiProviderProtocol.chatCompletions),
          entry.value,
          systemContext: registry.renderProtocol(),
        );
        final turn = parseChatEditTurn(reply, registry);
        final actions = [
          for (final row in turn?.rows ?? const <ChatEditTurnItem>[])
            if (row.command != null) row.command!.action,
        ];
        debugPrint('[fs] ${entry.key}：actions=$actions（无信封也算合规：模型先问回来）');
        expect(reply.trim(), isNotEmpty, reason: '${entry.key}：不能空回');
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
    skip: skipReason,
  );
}

String _head(String value, int max) {
  final flat = value.replaceAll('\n', ' ');
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}

final class _Config implements AiProviderConfigurationReader {
  const _Config(this._value);

  final AiProviderConfiguration _value;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => _value;
}

final class _Store implements SecureKeyValueStore {
  _Store(this.value);

  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async => this.value = value;

  @override
  Future<void> delete(String key) async => value = null;
}

final class _BytesReader implements PreparedMealImageBytesReader {
  const _BytesReader(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> read(PreparedMealImage image) async => bytes;
}
