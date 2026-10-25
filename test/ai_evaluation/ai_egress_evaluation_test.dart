import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/logging/privacy_logger.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai/domain/prompt_catalog.dart';
import 'package:localfit_ai/features/food_scan/data/open_ai_compatible_meal_recognition_provider.dart';
import 'package:localfit_ai/features/food_scan/data/prepared_meal_image_bytes_reader.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/data/open_ai_compatible_workout_plan_provider.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// 2.0-7c AI 出口固定评测集（docs/07 §11.1 最后两条）。
///
/// 用记录型 Dio adapter 捕获五条 AI 出口**实际发出**的请求，逐项断言：
///
/// 1. 每个任务只发它披露里承诺的字段：请求体顶层键固定、消息结构固定、
///    内容块类型固定；
/// 2. 本地金丝雀一个都不上线：API Key（只在请求头）、健康档案数值、
///    学校/食堂/地点名、导入的菜单原文、食物 id、历史餐食、精确坐标。
///    金丝雀真的被种进了本地数据与输入里，所以断言不是空跑；
/// 3. 三条带 logger 的出口，日志里同样没有金丝雀；
/// 4. 合同版本 / prompt 版本 / prompt 模板哈希 / 实际请求体哈希被钉住——
///    prompt、披露或线上字段一改，本文件立刻红，迫使重跑这套固定评测集
///    （docs/07 §11.1「Prompt 版本变化触发固定评测集」）。
///
/// 全程 fake Dio + 内存库：零真实 AI 请求、零真实 Key、零真实健康数据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  // 固定时刻取「本地正午」再转 UTC，而不是 `DateTime.utc(2026,9,15,4)` 这种
  // 本地巧合。理由：两条嵌进请求体的日期（menu-normalize 的 `today=` /
  // daily-menu-plan 的 `date=`）都由生产的 `_localDate()` 用 `.toLocal()` 算出，
  // 于是钉住的 requestSha256 只有在「这个时刻的本地日期恒为 2026-09-15」时才
  // 成立。本地墙钟正午经 toLocal() 往返恒等——任何时区都是同一天同一时刻；
  // `DateTime.utc(2026,9,15,4)` 只在 UTC 偏移 ≥ −4 的机器上算作 09-15，
  // 美东/美西机器会算成 09-14，钉值无端变红（2026-10-08 缺陷排查）。
  final now = DateTime(2026, 9, 15, 12).toUtc();

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await _seedCanaryFacts(database, now);
    await _seedMenuCandidates(database, now);
  });
  tearDown(() => database.close());

  test('五条 AI 出口的固定评测集：只发披露允许的字段，金丝雀不上线', () async {
    final outcomes = await _evaluateAll(database, now);

    // docs/32 §4 T6c（D6）：原 5 条出口中 3 条（menu-normalize /
    // daily-menu-plan / meal-pairing）随旧任务执行管线退役——它们的
    // 发送面改由对话命令层承担（`chat_edit_context_loader` 的快照分段
    // 与 `chat_edit_registry` 的协议段，另有对话侧断言守护）。
    expect(outcomes.map((row) => row.taskId).toList()..sort(), [
      'meal-estimate',
      'workout-plan',
    ]);

    for (final outcome in outcomes) {
      final expectation = _expectations[outcome.taskId]!;
      final reason = '[${outcome.taskId}]';

      // 端点、Key 位置、顶层键、单次请求。
      expect(
        outcome.sent.uri.toString(),
        'https://api.example.com/v1/chat/completions',
        reason: '$reason 只允许固定端点',
      );
      expect(outcome.sent.followRedirects, isFalse, reason: reason);
      expect(
        outcome.sent.headers['authorization'],
        'Bearer ${_Canary.apiKey}',
        reason: '$reason Key 必须在请求头',
      );
      expect(
        outcome.sent.body,
        isNot(contains(_Canary.apiKey)),
        reason: '$reason Key 不许进正文',
      );
      expect((jsonDecode(outcome.sent.body) as Map).keys.toSet(), {
        'model',
        'temperature',
        'max_tokens',
        // docs/29 §P4：推理档「关闭推理」（产品默认）附带的字段，chat 协议
        // 专用；披露文案（docs/07 §11.1）已同步承认。
        'thinking',
        'messages',
      }, reason: '$reason 请求体顶层键多一个都是没披露的字段');
      expect(
        _contentBlockTypes(outcome.sent),
        expectation.contentBlockTypes,
        reason: '$reason 内容块类型固定',
      );

      // 允许发送的部分确实发出去了（证明抓到的不是空请求）。
      final text = _messageText(outcome.sent);
      for (final snippet in expectation.sentSnippets) {
        expect(text, contains(snippet), reason: '$reason 应发送 $snippet');
      }

      // 金丝雀：四类本地事实一个都不许上线。
      for (final needle in _Canary.distinctive) {
        if (expectation.allowsPastedMenuText && needle == _Canary.pastedMenu) {
          continue;
        }
        expect(
          outcome.sent.body,
          isNot(contains(needle)),
          reason: '$reason 不许发送本地事实 $needle',
        );
      }
      for (final needle in _Canary.healthFacts) {
        expect(
          text,
          isNot(contains(needle)),
          reason: '$reason 不许发送健康档案 $needle',
        );
      }
      if (!expectation.allowsPastedMenuText) {
        expect(
          text,
          isNot(contains(_Canary.pastedMenu)),
          reason: '$reason 只有 menu-normalize 允许发送用户粘贴的文本',
        );
      }
      if (!expectation.sendsImage) {
        expect(
          outcome.sent.body,
          isNot(contains('image_url')),
          reason: '$reason 不发送图片',
        );
      } else {
        // 图片出口必须逐字节发送「处理后的那一份」，不多带任何本地字节。
        expect(outcome.sent.body, contains('data:image/jpeg;base64,'));
        expect(
          outcome.sent.body,
          contains(base64Encode(_canaryImageBytes)),
          reason: '$reason 发出的图片必须与处理后的输入逐字节一致',
        );
      }

      // 日志：Key/正文/图片/地点/学校/菜单/健康资料都不许进。
      for (final needle in [..._Canary.distinctive, ..._Canary.healthFacts]) {
        expect(
          outcome.logs.join('\n'),
          isNot(contains(needle)),
          reason: '$reason 日志不许出现 $needle',
        );
      }
    }
  });

  test('合同 / prompt 版本报告被钉住：prompt 一改就必须重跑评测集', () async {
    final outcomes = await _evaluateAll(database, now);
    final report = <String, _ReportRow>{
      for (final outcome in outcomes)
        outcome.taskId: _ReportRow(
          contractVersion: outcome.contractVersion,
          promptVersion: outcome.promptVersion,
          templateSha256: outcome.templateSha256,
          requestSha256: outcome.requestSha256,
        ),
    };

    // 报告随测试输出，便于把结果抄进证据文件。
    // ignore: avoid_print
    print(_versionTableMarkdown(outcomes));

    expect(report.keys.toSet(), _pinned.keys.toSet());
    for (final entry in _pinned.entries) {
      final live = report[entry.key]!;
      final pinned = entry.value;
      expect(live.contractVersion, pinned.contractVersion, reason: entry.key);
      expect(live.promptVersion, pinned.promptVersion, reason: entry.key);
      if (pinned.templateSha256 != null) {
        expect(
          live.templateSha256,
          pinned.templateSha256,
          reason:
              '${entry.key} 的 prompt 模板变了：请重跑固定评测集，'
              '确认脱敏结论仍成立后再更新这里的哈希',
        );
      }
      expect(
        live.requestSha256,
        pinned.requestSha256,
        reason:
            '${entry.key} 实际发出的请求体变了：请确认新字段仍符合披露，'
            '再更新这里的哈希',
      );
    }
  });

  // docs/32 §4 T6c：原「测试替身与生产 prompt 同源」随 fake capability
  // 退役——那条断言防的是「测试替身另抄一份 prompt」，替身本体已不存在。

  test('prompt 正文全仓只有一处：抄第二份就红', () {
    // 「Prompt 版本变化触发固定评测集」的前提是版本与正文只有一份来源；
    // 一旦别处又抄了一份正文（2.0-7c 之前 fake 就抄过；workout 的
    // 正文更是长期内联在 provider 里——docs/11 P3），同一版本的
    // promptVersion 会对应两段不同的正文，变更就不再触发任何重跑。
    // docs/32 §4 T6c：五个模板已集中到 `ai_workbench_prompt_templates.dart`
    // 一处（原先散在 6 个任务类里）；这里继续钉住 workout-plan 正文单源。
    for (final entry in {
      'workout-plan': workoutPlanPromptTemplate.template,
    }.entries) {
      final hits = _filesContainingPromptHeadline(entry.value);
      expect(
        hits,
        hasLength(1),
        reason:
            '[${entry.key}] prompt 正文只能有一份来源，'
            '实际出现在：${hits.isEmpty ? '（没有找到，扫描本身可能失效了）' : hits.join('、')}',
      );
    }
  });
}

/// 扫描 lib/ 与 test/ 下所有 `.dart`，返回包含该 prompt 正文首行的文件。
///
/// 比对方式是把源码与正文都去掉空白与引号后再找子串：源码里正文常常是
/// 多段相邻字符串拼接的，去掉引号才能对得上（`\n` 这类转义留在源码一侧，
/// 而首行本身不含换行，所以不影响）。
List<String> _filesContainingPromptHeadline(String template) {
  final needle = template.split('\n').first.replaceAll(RegExp(r'\s+'), '');
  final root = Directory.current.path;
  final files = [
    for (final directory in ['$root/lib', '$root/test'])
      ...Directory(directory).listSync(recursive: true, followLinks: false),
  ].whereType<File>().where((file) => file.path.endsWith('.dart'));
  return [
    for (final file in files)
      if (file
          .readAsStringSync()
          .replaceAll(RegExp(r"[\s']"), '')
          .contains(needle))
        file.path.replaceFirst('$root/', ''),
  ];
}

// ---------------------------------------------------------------- 评测执行

Future<List<_Outcome>> _evaluateAll(AppDatabase database, DateTime now) async {
  return [await _runMealEstimate(), await _runWorkoutPlan()];
}

Future<_Outcome> _runMealEstimate() async {
  final recorder = _Recorder(respond: (_) => _envelope(_mealDraft));
  final logs = <String>[];
  final provider = OpenAiCompatibleMealRecognitionProvider(
    dio: _recordedDio(recorder),
    configurationReader: _configuration,
    apiKeyStore: _apiKeyStore,
    imageBytesReader: const _CanaryImageReader(),
    logger: PrivacyLogger(writer: logs.add),
  );

  await provider.recognize(_preparedImage);

  return _outcome(
    taskId: 'meal-estimate',
    contractVersion: 'meal-estimate.v1',
    promptVersion: 'meal-estimate-prompt-1',
    // 1.x 出口的指令内联在 provider 里，没有独立模板常量：实际文本由
    // 请求体哈希兜住（见 _pinned 的说明）。
    template: null,
    recorder: recorder,
    logs: logs,
  );
}

Future<_Outcome> _runWorkoutPlan() async {
  final recorder = _Recorder(respond: (_) => _envelope(_workoutDraft));
  final logs = <String>[];
  final template = workoutPlanPromptTemplate;
  final provider = OpenAiCompatibleWorkoutPlanProvider(
    dio: _recordedDio(recorder),
    configurationReader: _configuration,
    apiKeyStore: _apiKeyStore,
    logger: PrivacyLogger(writer: logs.add),
    catalog: PromptCatalog()..register(template),
    template: template,
  );

  await provider.generate(
    const AiWorkoutPlanRequest(
      daysPerWeek: 2,
      goalText: '提高深蹲',
      exercises: [
        ExerciseOption(id: 'ex-barbell-squat', name: '杠铃深蹲'),
        ExerciseOption(id: 'ex-plank', name: '平板支撑'),
      ],
    ),
  );

  return _outcome(
    taskId: 'workout-plan',
    contractVersion: 'workout-plan.v1',
    promptVersion: 'workout-plan-prompt-1',
    // prompt 正文已收敛到 domain 单一来源（workoutPlanPromptTemplate），
    // 模板哈希从这条起被钉住（docs/11 P3）。
    template: template.template,
    recorder: recorder,
    logs: logs,
  );
}

Future<String> _sha256Hex(String text) async {
  final digest = await Sha256().hash(utf8.encode(text));
  return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 把请求体里**运行时就不同**的本地行 id 归一，用于钉版本报告。
///
/// `DailyPlanEngine` 用墙上时钟拼候选行 id（`daily-cand-<slotId>-<n>-<epochMs>`），
/// 两次运行必然不同。不归一的话这个 pin 每次都会红，警报就失效了；归一之后
/// prompt 文本、字段名与本地事实仍然逐字节被钉住。
String _pinnableBody(String body) =>
    body.replaceAll(RegExp(r'daily-cand-[^\s"]+'), '<candidate-row-id>');

Future<_Outcome> _outcome({
  required String taskId,
  required String contractVersion,
  required String promptVersion,
  required String? template,
  required _Recorder recorder,
  required List<String> logs,
}) async {
  expect(recorder.requests, hasLength(1), reason: '$taskId 只发一次请求');
  final options = recorder.requests.single;
  final sent = _SentRequest(
    uri: options.uri,
    headers: {
      for (final entry in options.headers.entries)
        entry.key.toLowerCase(): '${entry.value}',
    },
    body: recorder.bodies.single,
    followRedirects: options.followRedirects,
  );
  return _Outcome(
    taskId: taskId,
    contractVersion: contractVersion,
    promptVersion: promptVersion,
    templateSha256: template == null ? null : await _sha256Hex(template),
    requestSha256: await _sha256Hex(_pinnableBody(sent.body)),
    sent: sent,
    logs: logs,
  );
}

// ---------------------------------------------------------------- 断言工具

List<String> _contentBlockTypes(_SentRequest sent) {
  final decoded = jsonDecode(sent.body) as Map<String, Object?>;
  final content = ((decoded['messages']! as List).single as Map)['content'];
  if (content is String) return const ['text'];
  return [
    for (final block in content as List) (block as Map)['type']! as String,
  ];
}

/// 消息里的纯文本部分（content 字符串或 text 块拼接）。
String _messageText(_SentRequest sent) {
  final decoded = jsonDecode(sent.body) as Map<String, Object?>;
  final messages = decoded['messages']! as List;
  expect(messages, hasLength(1));
  final message = messages.single as Map;
  expect(message['role'], 'user');
  final content = message['content'];
  if (content is String) return content;
  return [
    for (final block in content as List)
      if ((block as Map)['type'] == 'text') block['text'] as String,
  ].join('\n');
}

/// 版本报告（Markdown）：抄进证据文件，也是 `_pinned` 的来源。
///
/// 哈希整条打印，不截断——截断后的哈希抄不回 `_pinned`。
String _versionTableMarkdown(List<_Outcome> outcomes) {
  final buffer = StringBuffer()
    ..writeln(
      '| 任务 | contract_version | prompt_version | prompt 模板 sha256 | '
      '请求体 sha256 |',
    )
    ..writeln('|---|---|---|---|---|');
  for (final outcome in outcomes) {
    buffer.writeln(
      '| ${outcome.taskId} | ${outcome.contractVersion} | '
      '${outcome.promptVersion} | '
      '${outcome.templateSha256 ?? '（指令内联，无模板常量）'} | '
      '${outcome.requestSha256} |',
    );
  }
  return buffer.toString();
}

// ---------------------------------------------------------------- 出口期望

class _Expectation {
  const _Expectation({
    required this.contentBlockTypes,
    required this.sentSnippets,
    this.sendsImage = false,
    this.allowsPastedMenuText = false,
  });

  final List<String> contentBlockTypes;
  final List<String> sentSnippets;
  final bool sendsImage;
  final bool allowsPastedMenuText;
}

final _expectations = <String, _Expectation>{
  'meal-estimate': const _Expectation(
    contentBlockTypes: ['text', 'image_url'],
    sentSnippets: ['Estimate only foods visible in the image'],
    sendsImage: true,
  ),
  'workout-plan': const _Expectation(
    contentBlockTypes: ['text'],
    sentSnippets: ['Generate a plan with exactly 2', 'ex-barbell-squat'],
  ),
  'menu-normalize': const _Expectation(
    contentBlockTypes: ['text'],
    sentSnippets: [_Canary.pastedMenu],
    allowsPastedMenuText: true,
  ),
  'daily-menu-plan': const _Expectation(
    contentBlockTypes: ['text'],
    sentSnippets: ['candidates:', 'name=鸡胸肉饭', 'id='],
  ),
  'meal-pairing': const _Expectation(
    contentBlockTypes: ['text'],
    // 任务卡披露「用户点名的食材 allow-list（id、名称与每 100g 宏量）」：
    // 模型要照抄 food_id，而 decoder 只接受 allow-list 内的 id，所以 id
    // 与宏量必须在 prompt 里，否则这条链路在生产上不可能通过校验。
    sentSnippets: ['food_id', 'canary-pairing-rice', 'kcal_per_100g'],
  ),
};

class _Outcome {
  const _Outcome({
    required this.taskId,
    required this.contractVersion,
    required this.promptVersion,
    required this.templateSha256,
    required this.requestSha256,
    required this.sent,
    required this.logs,
  });

  final String taskId;
  final String contractVersion;
  final String promptVersion;
  final String? templateSha256;
  final String requestSha256;
  final _SentRequest sent;
  final List<String> logs;

  @override
  String toString() =>
      'contract=$contractVersion prompt=$promptVersion '
      'request=${requestSha256.substring(0, 16)}…';
}

// ---------------------------------------------------------------- 固定金丝雀

/// 本地金丝雀：真实本地事实的形状，值是一眼能认出的假数据。
abstract final class _Canary {
  static const String apiKey = 'sk-canary-7c-not-a-real-key';
  static const String school = '示范大学7CANARY';
  static const String venue = '东区食堂7CANARY';
  static const String importedMenuRow = '红烧肉7CANARY 12元';
  static const String pastedMenu = '土豆丝7CANARY 6元';
  static const String foodId = 'food7canary';
  static const String mealHistory = '午餐7CANARY 米饭200g';
  static const String place = '东门7CANARY';
  static const String coordinates = '39.9042,116.4074';
  static const String imageMarker = 'JPEG-CANARY-7C';
  static const String weightKg = '65.43';
  static const String heightCm = '172.31';
  static const String targetKcal = '1793';

  /// 整体字符串匹配用（含 `7CANARY`/`sk-canary-` 或标点，base64 里不可能
  /// 偶然出现）。
  static const List<String> distinctive = [
    apiKey,
    school,
    venue,
    importedMenuRow,
    pastedMenu,
    foodId,
    mealHistory,
    place,
    coordinates,
    imageMarker,
  ];

  /// 健康档案数值：只在消息文本里查（整串查会被 base64 的巧合数字搞假绿）。
  static const List<String> healthFacts = [weightKg, heightCm, targetKcal];
}

/// 处理后的图片字节（JPEG 头尾 + 金丝雀标记）。
final Uint8List _canaryImageBytes = Uint8List.fromList([
  0xff,
  0xd8,
  0xff,
  0xe0,
  ...utf8.encode(_Canary.imageMarker),
  0xff,
  0xd9,
]);

final _preparedImage = PreparedMealImage(
  path: 'prepared-canary.jpg',
  width: 640,
  height: 480,
  byteLength: _canaryImageBytes.length,
);

final class _CanaryImageReader implements PreparedMealImageBytesReader {
  const _CanaryImageReader();

  @override
  Future<Uint8List> read(PreparedMealImage image) async => _canaryImageBytes;
}

// ---------------------------------------------------------------- 假依赖

final _configuration = _FixedConfiguration();
final _apiKeyStore = AiApiKeyStore(
  store: _MemorySecureStore()
    ..values[AiApiKeyStore.storageKey] = _Canary.apiKey,
);

Dio _recordedDio(HttpClientAdapter adapter) =>
    Dio()..httpClientAdapter = adapter;

final class _FixedConfiguration implements AiProviderConfigurationReader {
  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      const AiProviderConfiguration(
        baseUrl: 'https://api.example.com/v1',
        model: 'canary-model',
      );
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

class _SentRequest {
  const _SentRequest({
    required this.uri,
    required this.headers,
    required this.body,
    required this.followRedirects,
  });

  final Uri uri;
  final Map<String, String> headers;
  final String body;
  final bool followRedirects;
}

final class _Recorder implements HttpClientAdapter {
  _Recorder({required this.respond});

  /// 用捕获到的请求体算响应：daily-menu-plan 的候选 id 是本地生成的，
  /// 只有读到请求才知道该回哪个 id（模拟一个守规矩的供应商）。
  final String Function(String requestBody) respond;
  final List<RequestOptions> requests = [];
  final List<String> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    final bytes = <int>[];
    if (stream != null) {
      await for (final chunk in stream) {
        bytes.addAll(chunk);
      }
    }
    final body = utf8.decode(bytes);
    bodies.add(body);
    return ResponseBody.fromString(
      respond(body),
      200,
      headers: const {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _envelope(String content) => jsonEncode({
  'choices': [
    {
      'message': {'content': content},
    },
  ],
});

// ---------------------------------------------------------------- 固定输入

const _mealDraft =
    '{"schema_version":1,"items":[{"name":"米饭","estimated_grams":180,'
    '"grams_range":{"min":140,"max":220},"cooking_method":"蒸煮",'
    '"ingredients":["大米"],"confidence":0.78,"needs_confirmation":false,'
    '"questions":[]}],"meal_notes":"午餐","warnings":[]}';

const _workoutDraft =
    '{"schema_version":1,"name":"AI 计划","days":['
    '{"weekday":1,"exercises":[{"exercise_id":"ex-barbell-squat",'
    '"target_sets":4,"target_reps":8}]},'
    '{"weekday":4,"exercises":[{"exercise_id":"ex-plank",'
    '"target_sets":3,"target_reps":60}]}],"warnings":[]}';

/// 本地事实：金丝雀档案 + 学校/食堂 + 导入的菜单原文引用 + 历史餐食。
Future<void> _seedCanaryFacts(AppDatabase database, DateTime now) async {
  await database
      .into(database.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: 'profile-canary',
          birthYear: const Value(1998),
          heightCm: const Value(172.31),
          activityLevel: 'moderate',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.goals)
      .insert(
        GoalsCompanion.insert(
          id: 'goal-canary',
          profileId: 'profile-canary',
          type: 'fat_loss',
          calorieMinKcal: 1793,
          calorieMaxKcal: 1793,
          effectiveFrom: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.dailyTargets)
      .insert(
        DailyTargetsCompanion.insert(
          id: 'target-canary',
          goalId: 'goal-canary',
          effectiveDate: '2026-09-15',
          calorieMinKcal: 1793,
          calorieMaxKcal: 1793,
          proteinMinGrams: 120,
          proteinMaxGrams: 130,
          carbsMinGrams: 180,
          carbsMaxGrams: 200,
          fatMinGrams: 55,
          fatMaxGrams: 65,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.measurements)
      .insert(
        MeasurementsCompanion.insert(
          id: 'measure-canary',
          profileId: 'profile-canary',
          localDate: '2026-09-15',
          weightKg: 65.43,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.foods)
      .insert(
        FoodsCompanion.insert(
          id: _Canary.foodId,
          name: _Canary.mealHistory,
          kcalPer100g: 116,
          proteinPer100g: 2.6,
          carbsPer100g: 25.9,
          fatPer100g: 0.3,
          source: 'seed',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.campusProfiles)
      .insert(
        CampusProfilesCompanion.insert(
          id: 'campus-canary',
          name: _Canary.school,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.venues)
      .insert(
        VenuesCompanion.insert(
          id: 'venue-canary',
          campusId: 'campus-canary',
          name: _Canary.venue,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.menuSources)
      .insert(
        MenuSourcesCompanion.insert(
          id: 'source-canary',
          venueId: 'venue-canary',
          sourceType: 'file_txt_csv_json',
          reference: const Value(_Canary.importedMenuRow),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

/// 今日 active 菜单快照 + 一个已确认匹配的候选（daily-menu-plan 的输入）。
Future<void> _seedMenuCandidates(AppDatabase database, DateTime now) async {
  await database
      .into(database.menuSnapshots)
      .insert(
        MenuSnapshotsCompanion.insert(
          id: 'snap-canary',
          sourceId: 'source-canary',
          venueId: 'venue-canary',
          businessDate: '2026-09-15',
          contentHash: 'b' * 64,
          importedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.menuServices)
      .insert(
        MenuServicesCompanion.insert(
          id: 'svc-canary',
          snapshotId: 'snap-canary',
          name: '一楼窗口',
          openTime: '10:30',
          closeTime: '13:30',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.menuItems)
      .insert(
        MenuItemsCompanion.insert(
          id: 'item-canary',
          serviceId: 'svc-canary',
          displayName: '鸡胸肉饭',
          itemStatus: const Value('matched'),
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.menuItemFoodMatches)
      .insert(
        MenuItemFoodMatchesCompanion.insert(
          id: 'match-canary',
          menuItemId: 'item-canary',
          foodId: _Canary.foodId,
          matchStatus: const Value('confirmed'),
          confidence: const Value(0.95),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

// ---------------------------------------------------------------- 钉住的版本

class _ReportRow {
  const _ReportRow({
    required this.contractVersion,
    required this.promptVersion,
    required this.templateSha256,
    required this.requestSha256,
  });

  final String contractVersion;
  final String promptVersion;
  final String? templateSha256;
  final String requestSha256;

  @override
  String toString() =>
      'contract=$contractVersion prompt=$promptVersion '
      'template=${templateSha256 == null ? '指令内联' : '${templateSha256!.substring(0, 16)}…'} '
      'request=${requestSha256.substring(0, 16)}…';
}

/// docs/07 §11.1「Prompt 版本变化触发固定评测集」：这里的哈希都必须是跑过
/// 固定评测集、确认脱敏结论仍成立之后才更新的。
///
/// 两条 1.x 出口（meal-estimate / workout-plan）的指令文本内联在 provider 里、
/// 没有独立的模板常量，所以它们的模板哈希用「实际请求体哈希」代替——
/// 字段或指令一改，请求体就变。
/// 2026-10-05 docs/29 §P4：推理档「关闭推理」默认发 `thinking:{type:"disabled"}`
/// ⇒ 五条 chat 出口的请求体全部变化，本表按重跑评测集的新哈希重钉。
const _pinned = <String, _ReportRow>{
  'meal-estimate': _ReportRow(
    contractVersion: 'meal-estimate.v1',
    promptVersion: 'meal-estimate-prompt-1',
    templateSha256: null,
    requestSha256:
        '749b3740e54ebb1d6c961bfac2374ffdf286881414888db4edd88931585f3138',
  ),
  'workout-plan': _ReportRow(
    contractVersion: 'workout-plan.v1',
    promptVersion: 'workout-plan-prompt-1',
    // 2026-09-19 P3：正文移入 workoutPlanPromptTemplate，开始钉模板哈希；
    // 请求体哈希不变（渲染结果与内联时期逐字节同构）。
    templateSha256:
        'a51f17eebcbee3f0f2f9dca2139c51cb9a4f65017cb7d21e94b1ec6073f73cee',
    requestSha256:
        'f380e27ce791b8956d1fbf8776e522ff568f959c75e10bf9df4540d57e89446a',
  ),
  // docs/32 §4 T6c（D6）：原 menu-normalize / daily-menu-plan /
  // meal-pairing 三条出口随旧任务执行管线退役——它们的发送面改由
  // 对话命令层承担（协议段 + 快照分段，另有对话侧断言守护）。
};
