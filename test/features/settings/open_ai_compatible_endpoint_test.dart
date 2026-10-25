import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/open_ai_compatible_endpoint.dart';

void main() {
  group('OpenAiCompatibleEndpoint', () {
    test('canonicalizes an API root and fixed chat completions route', () {
      final endpoint = OpenAiCompatibleEndpoint.tryParse(
        'https://API.example.com/v1/',
      );

      expect(endpoint?.baseUrl, 'https://api.example.com/v1/');
      expect(
        endpoint?.requestUri.toString(),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('canonicalizes a root path', () {
      final endpoint = OpenAiCompatibleEndpoint.tryParse(
        'https://api.example.com',
      );

      expect(endpoint?.baseUrl, 'https://api.example.com/');
      expect(
        endpoint?.requestUri.toString(),
        'https://api.example.com/chat/completions',
      );
    });

    test('rejects unsafe or ambiguous input', () {
      const inputs = [
        'http://api.example.com/v1',
        'https://user:secret@api.example.com/v1',
        'https://api.example.com/v1?token=secret',
        'https://api.example.com/v1#fragment',
        'https://api.example.com:8443/v1',
        'https://api.example.com/v1/../admin',
        'https://api.example.com/v1%2fadmin',
        'https://api.example.com/v1%2e%2e/admin',
        'https://api.example.com/v1\\admin',
        'https://api.example.com/v1 with-space',
      ];

      for (final input in inputs) {
        expect(OpenAiCompatibleEndpoint.tryParse(input), isNull, reason: input);
        // 三种协议下的校验口径一致（协议只改路径，不改安全检查）。
        for (final protocol in AiProviderProtocol.values) {
          expect(
            OpenAiCompatibleEndpoint.tryParse(input, protocol: protocol),
            isNull,
            reason: '$input / $protocol',
          );
        }
      }
    });

    test('请求路径按协议出（同一个 Base URL，不改配置就能换协议）', () {
      const base = 'https://api.example.com/v1';

      expect(
        OpenAiCompatibleEndpoint.tryParse(
          base,
          protocol: AiProviderProtocol.chatCompletions,
        )?.requestUri.toString(),
        'https://api.example.com/v1/chat/completions',
      );
      expect(
        OpenAiCompatibleEndpoint.tryParse(
          base,
          protocol: AiProviderProtocol.responses,
        )?.requestUri.toString(),
        'https://api.example.com/v1/responses',
      );
      expect(
        OpenAiCompatibleEndpoint.tryParse(
          base,
          protocol: AiProviderProtocol.anthropicMessages,
        )?.requestUri.toString(),
        'https://api.example.com/v1/messages',
      );
    });

    test('粘贴完整端点时剥掉协议尾巴', () {
      // 用户从供应商文档整段复制是常态；不剥就会拼出
      // /v1/chat/completions/chat/completions。
      final fromFull = OpenAiCompatibleEndpoint.tryParse(
        'https://api.example.com/v1/chat/completions',
      );

      // baseUrl 始终是 API 根；requestUri 由当前协议拼出。
      expect(fromFull?.baseUrl, 'https://api.example.com/v1/');
      expect(
        fromFull?.requestUri.toString(),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('剥尾巴是幂等的：API 根本身不会被二次剥离', () {
      final fromRoot = OpenAiCompatibleEndpoint.tryParse(
        'https://api.example.com/v1/',
      );
      final fromFull = OpenAiCompatibleEndpoint.tryParse(
        'https://api.example.com/v1/chat/completions',
      );

      expect(fromFull?.baseUrl, fromRoot?.baseUrl);
      expect(fromFull?.requestUri, fromRoot?.requestUri);
    });

    test('换成别的协议时同一个完整端点仍指向正确路径', () {
      // 关键场景：用户粘了 /v1/chat/completions，之后在设置里改成 Anthropic。
      final endpoint = OpenAiCompatibleEndpoint.tryParse(
        'https://api.example.com/v1/chat/completions',
        protocol: AiProviderProtocol.anthropicMessages,
      );

      expect(endpoint?.baseUrl, 'https://api.example.com/v1/');
      expect(
        endpoint?.requestUri.toString(),
        'https://api.example.com/v1/messages',
      );
    });

    test('没有协议尾巴的路径原样保留', () {
      // 自建网关常把版本段写成别的（/openai/、/compat/v2/…），不许乱剥。
      final endpoint = OpenAiCompatibleEndpoint.tryParse(
        'https://gw.example.com/openai/',
      );

      expect(endpoint?.baseUrl, 'https://gw.example.com/openai/');
      expect(
        endpoint?.requestUri.toString(),
        'https://gw.example.com/openai/chat/completions',
      );
    });

    test('大小写不敏感地识别协议尾巴', () {
      final endpoint = OpenAiCompatibleEndpoint.tryParse(
        'https://api.example.com/v1/Chat/Completions',
      );

      expect(endpoint?.baseUrl, 'https://api.example.com/v1/');
    });

    test('只剥最外层一次，中间出现同名字段不误剥', () {
      // `messages` 既是 Anthropic 的路径，也可能是个正常的版本段名。
      final endpoint = OpenAiCompatibleEndpoint.tryParse(
        'https://api.example.com/messages/v1/',
      );

      expect(endpoint?.baseUrl, 'https://api.example.com/messages/v1/');
    });
  });
}
