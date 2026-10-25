import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/settings/domain/ai_endpoint_probe.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/domain/ai_reasoning_mode.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

/// docs/29 §P4：AI 配置统一弹层（协议 / Base URL / 模型 / 连通性测试 /
/// 模型拉取选择 / 推理开关 / API Key 同一处）。
///
/// 这里用**脚本化 fake 探测器**（零真实网络）锁 UI 行为：结果内联不弹窗、
/// 模型点选填入模型字段并随保存落库、推理档默认「关闭推理」且可选改。
/// 探测器自身的分档文案（401/404/超时）在
/// `dio_ai_endpoint_probe_test.dart` 单测。
void main() {
  void useTallViewport(WidgetTester tester) {
    // 弹层内容很长（协议/地址/模型/探测/列表/推理/Key/说明），
    // 默认 800×600 会溢出。
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('settings-ai-model-row')));
    await tester.pumpAndSettle();
  }

  testWidgets('探测成功：结果内联显示 + 模型列表可选，点选填入模型字段', (tester) async {
    useTallViewport(tester);
    final probe = _FakeProbe(
      AiEndpointProbeResult.ok(models: const ['alpha-model', 'beta-model']),
    );
    final store = _FakeStore(
      initial: const AiProviderSettings(
        configuration: AiProviderConfiguration(
          baseUrl: 'https://api.example.com/v1',
          model: 'manual-model',
        ),
        hasApiKey: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(settingsStore: store, endpointProbe: probe),
      ),
    );
    await tester.pumpAndSettle();
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('ai-config-probe')));
    await tester.pumpAndSettle();

    // 结果内联（不弹 snackbar/系统提示）。
    expect(find.byKey(const Key('ai-config-probe-result')), findsOneWidget);
    expect(find.text('连通成功，发现 2 个模型'), findsOneWidget);
    expect(find.byKey(const Key('ai-model-option-0')), findsOneWidget);
    expect(find.byKey(const Key('ai-model-option-1')), findsOneWidget);
    // 探测参数来自表单。
    expect(probe.calls.single.baseUrl, 'https://api.example.com/v1');
    expect(probe.calls.single.protocol, AiProviderProtocol.chatCompletions);

    // 点选第二个模型 → 模型字段被填入（手输名字永远可用的兜底不变）。
    await tester.tap(find.byKey(const Key('ai-model-option-1')));
    await tester.pumpAndSettle();
    final modelField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('ai-model')),
        matching: find.byType(TextField),
      ),
    );
    expect(modelField.controller!.text, 'beta-model');
  });

  testWidgets('探测失败（401 档）：错误内联显示，不出现模型列表', (tester) async {
    useTallViewport(tester);
    final probe = _FakeProbe(
      const AiEndpointProbeResult.failure('API Key 无效或无权访问该服务。'),
    );
    final store = _FakeStore(
      initial: const AiProviderSettings(
        configuration: AiProviderConfiguration(
          baseUrl: 'https://api.example.com/v1',
          model: 'manual-model',
        ),
        hasApiKey: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(settingsStore: store, endpointProbe: probe),
      ),
    );
    await tester.pumpAndSettle();
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('ai-config-probe')));
    await tester.pumpAndSettle();

    expect(find.text('API Key 无效或无权访问该服务。'), findsOneWidget);
    expect(find.byKey(const Key('ai-model-option-0')), findsNothing);
  });

  testWidgets('模型列表可筛选：搜索把列表收窄，序号按过滤后的列表排', (tester) async {
    useTallViewport(tester);
    final probe = _FakeProbe(
      AiEndpointProbeResult.ok(
        models: const ['alpha-model', 'beta-model', 'gamma-model'],
      ),
    );
    final store = _FakeStore(
      initial: const AiProviderSettings(
        configuration: AiProviderConfiguration(
          baseUrl: 'https://api.example.com/v1',
          model: 'manual-model',
        ),
        hasApiKey: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(settingsStore: store, endpointProbe: probe),
      ),
    );
    await tester.pumpAndSettle();
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('ai-config-probe')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('ai-model-search')), 'beta');
    await tester.pumpAndSettle();

    // 过滤后只剩 beta：且它现在是列表的第 0 个。
    expect(find.byKey(const Key('ai-model-option-0')), findsOneWidget);
    expect(find.byKey(const Key('ai-model-option-1')), findsNothing);
    expect(find.text('没有匹配「beta」的模型'), findsNothing);

    await tester.enterText(find.byKey(const Key('ai-model-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配「zzz」的模型'), findsOneWidget);
  });

  testWidgets('推理开关：默认「关闭推理」，切到「默认」后随保存落库', (tester) async {
    useTallViewport(tester);
    final probe = _FakeProbe(const AiEndpointProbeResult.failure('unused'));
    final store = _FakeStore(
      initial: const AiProviderSettings(
        configuration: AiProviderConfiguration(
          baseUrl: 'https://api.example.com/v1',
          model: 'manual-model',
        ),
        hasApiKey: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(settingsStore: store, endpointProbe: probe),
      ),
    );
    await tester.pumpAndSettle();
    await openSheet(tester);

    // 下拉框当前值 = 默认档「关闭推理（更快）」。
    expect(find.text('关闭推理（更快）'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-reasoning')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('默认（由上游决定）').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ai-config-sheet-save')));
    await tester.pumpAndSettle();

    expect(store.saved, hasLength(1));
    expect(store.saved.single.reasoning, AiReasoningMode.providerDefault);
    expect(store.saved.single.protocol, AiProviderProtocol.chatCompletions);
  });

  testWidgets('探测用 Key：框里刚输入的优先，留空则读已保存的', (tester) async {
    useTallViewport(tester);
    final probe = _FakeProbe(AiEndpointProbeResult.ok(models: const ['m']));
    final store = _FakeStore(
      initial: const AiProviderSettings(
        configuration: AiProviderConfiguration(
          baseUrl: 'https://api.example.com/v1',
          model: 'manual-model',
        ),
        hasApiKey: true,
      ),
    );
    final keyStore = AiApiKeyStore(
      store: _MemorySecureStore()
        ..values[AiApiKeyStore.storageKey] = 'stored-key',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: store,
          endpointProbe: probe,
          apiKeyStore: keyStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openSheet(tester);

    // 框里留空 → 用已保存的 Key。
    await tester.tap(find.byKey(const Key('ai-config-probe')));
    await tester.pumpAndSettle();
    expect(probe.calls.single.apiKey, 'stored-key');

    // 框里输入了新 Key → 用新的。
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('ai-api-key')),
        matching: find.byType(TextField),
      ),
      'fresh-key',
    );
    await tester.tap(find.byKey(const Key('ai-config-probe')));
    await tester.pumpAndSettle();
    expect(probe.calls.last.apiKey, 'fresh-key');
  });
  testWidgets('未配置时 API Key 栏不伪装成已保存（缺陷 ㉕）', (tester) async {
    useTallViewport(tester);
    final store = _FakeStore(
      initial: const AiProviderSettings(configuration: null, hasApiKey: false),
    );
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(settingsStore: store)),
    );
    await tester.pumpAndSettle();
    await openSheet(tester);

    // 占位是渲染出来的文本 ⇒ 直接按文案断言（`TextFormField` 不暴露 decoration）。
    expect(
      find.text('••••••••'),
      findsNothing,
      reason: '未配置时用掩码点当占位，用户分不清「没存过」与「已保存」',
    );
    expect(
      find.textContaining('未配置'),
      findsWidgets,
      reason: '未配置时提示必须如实说「未配置」',
    );
  });
  testWidgets('本机 Key 读不出来时：不许当成「没 Key」去探测，要给出可行动文案', (tester) async {
    // 2026-10-16 设备实测（AVD LocalFit_API35）：应用升级后本机保存的 API Key
    // 变成**读不出来**（系统凭据被重置这一类），而 `resolveProbeKey()` 当时
    // 把读异常吞成空串 ⇒ 无 Authorization 头去探测 ⇒ 供应商断开连接 ⇒ 界面
    // 写「网络连接不可用，请检查网络后重试。」。诊断被带偏了整整半小时：
    // 真正该说的是「Key 读不出来，请重新填写并保存」。
    useTallViewport(tester);
    final probe = _FakeProbe(AiEndpointProbeResult.ok(models: const ['m']));
    final store = _FakeStore(
      initial: const AiProviderSettings(
        configuration: AiProviderConfiguration(
          baseUrl: 'https://api.example.com/v1',
          model: 'm',
        ),
        hasApiKey: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          settingsStore: store,
          endpointProbe: probe,
          apiKeyStore: AiApiKeyStore(store: _ThrowingSecureStore()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openSheet(tester);

    await tester.tap(find.byKey(const Key('ai-config-probe')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-config-probe-result')), findsOneWidget);
    // Key 挂在 Text 本体上（不是包一层），所以直接按 Key 取 Text。
    final resultText = tester
        .widget<Text>(find.byKey(const Key('ai-config-probe-result')))
        .data!;
    debugPrint('[sheet] 读 Key 失败文案：$resultText');
    expect(resultText, contains('重新'), reason: '要告诉用户怎么办（重新填写并保存）');
    expect(probe.calls, isEmpty, reason: 'Key 读不出来时不该发请求（发了也只是让供应商报错，掩盖真因）');
  });
}

final class _FakeProbe implements AiEndpointProbe {
  _FakeProbe(this.result);

  final AiEndpointProbeResult result;
  final calls =
      <({String baseUrl, AiProviderProtocol protocol, String apiKey})>[];

  @override
  Future<AiEndpointProbeResult> probe({
    required String baseUrl,
    required AiProviderProtocol protocol,
    required String apiKey,
  }) async {
    calls.add((baseUrl: baseUrl, protocol: protocol, apiKey: apiKey));
    return result;
  }
}

final class _FakeStore implements AiProviderSettingsStore {
  _FakeStore({required this.initial});

  AiProviderSettings initial;
  final saved = <AiProviderSettingsInput>[];

  @override
  Future<void> clearApiKey() async {
    initial = AiProviderSettings(
      configuration: initial.configuration,
      hasApiKey: false,
    );
  }

  @override
  Future<AiProviderSettings> load() async => initial;

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      initial.configuration;

  @override
  Future<void> save(AiProviderSettingsInput input) async {
    saved.add(input);
    initial = AiProviderSettings(
      configuration: AiProviderConfiguration(
        baseUrl: input.baseUrl.trim(),
        model: input.model.trim(),
        protocol: input.protocol,
        reasoning: input.reasoning,
      ),
      hasApiKey: true,
    );
  }
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

/// 读就抛的密钥存储：模拟「系统凭据被重置后 Key 读不出来」。
final class _ThrowingSecureStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async =>
      throw Exception('keychain unavailable');

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}
