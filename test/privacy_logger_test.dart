import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/logging/privacy_logger.dart';

/// `PrivacyLogger` 的规范（docs/07 §12 风险表「日志白名单」、docs/05 §4）：
/// 普通日志只允许写**白名单内的指标**，其余字段一律默认拒绝。
///
/// 2026-09-15（2.0-7d）行为变更：原实现是默认放行——只有键名命中敏感词才
/// 脱敏，所以任何新调用方把菜单原文/学校/地点塞进 fields 都会原样落进日志
/// （2.0-7c 只证明了当前三个调用方恰好只写四个指标）。现在改成默认拒绝：
/// 未列入白名单的键值不写，只在原键名下留标记，这样「有人想加字段」这件事
/// 在日志里仍然看得见，值却出不去。
void main() {
  /// 与 docs/07 §11.1 同一组本地事实：出现任何一个都算泄漏。
  const canaries = <String>[
    '红烧肉7CANARY 12元',
    '示范大学7CANARY',
    '东区食堂7CANARY',
    'food7canary',
    '午餐7CANARY 米饭200g',
    '39.9042,116.4074',
  ];

  List<String> capture(void Function(PrivacyLogger logger) body) {
    final messages = <String>[];
    body(PrivacyLogger(writer: messages.add));
    return messages;
  }

  test('白名单内的指标照常写出（诊断能力不能被一起关掉）', () {
    final messages = capture(
      (logger) => logger.log(
        LogLevel.info,
        'meal_recognition_finished',
        fields: {
          'resultKind': 'ok',
          'durationMs': 42,
          'requestBytes': 1024,
          'responseBytes': 2048,
        },
      ),
    );

    expect(messages, hasLength(1));
    expect(messages.single, contains('meal_recognition_finished'));
    expect(messages.single, contains('resultKind: ok'));
    expect(messages.single, contains('durationMs: 42'));
    expect(messages.single, contains('requestBytes: 1024'));
    expect(messages.single, contains('responseBytes: 2048'));
    expect(messages.single, isNot(contains('REDACTED')));
  });

  test('未列入白名单的字段：值不写，键名留标记', () {
    final messages = capture(
      (logger) => logger.log(
        LogLevel.info,
        'menu_import_finished',
        fields: {
          'menuText': canaries[0],
          'campus': canaries[1],
          'venueName': canaries[2],
          'foodId': canaries[3],
          'mealSummary': canaries[4],
          'coordinates': canaries[5],
        },
      ),
    );

    expect(messages, hasLength(1));
    for (final canary in canaries) {
      expect(
        messages.single,
        isNot(contains(canary)),
        reason: '默认拒绝：$canary 不许进普通日志',
      );
    }
    // 键名保留：审计能看出「有人想写这些字段」，值仍在门外。
    expect(messages.single, contains('menuText: [REDACTED:not-allow-listed]'));
    expect(messages.single, contains('campus: [REDACTED:not-allow-listed]'));
  });

  test('白名单键名本身命中敏感词时，敏感规则仍然优先', () {
    final messages = <String>[];
    PrivacyLogger(
      writer: messages.add,
      allowedKeys: const {'apiKey', 'durationMs'},
    ).log(
      LogLevel.info,
      'manual',
      fields: {'apiKey': 'sk-canary-7d', 'durationMs': 7},
    );

    expect(messages.single, isNot(contains('sk-canary-7d')));
    expect(messages.single, contains('apiKey: [REDACTED]'));
    expect(messages.single, contains('durationMs: 7'));
  });

  test('嵌套容器不在白名单里时整棵子树不写（不给未知结构开后门）', () {
    final messages = capture(
      (logger) => logger.log(
        LogLevel.info,
        'ai_request_finished',
        fields: {
          'durationMs': 12,
          'headers': {'Authorization': 'Bearer canary-token', 'status': 200},
          'items': [
            {'imageBase64': 'raw-image', 'mealName': canaries[0]},
          ],
        },
      ),
    );

    expect(messages, hasLength(1));
    expect(messages.single, contains('durationMs: 12'));
    expect(messages.single, isNot(contains('Bearer canary-token')));
    expect(messages.single, isNot(contains('raw-image')));
    expect(messages.single, isNot(contains(canaries[0])));
    expect(messages.single, isNot(contains('status: 200')));
    expect(messages.single, contains('headers: [REDACTED:not-allow-listed]'));
  });

  test('深层嵌套里的白名单指标也不会被容器带出去', () {
    // 目前没有任何调用方这么写；这里钉住的是「容器一律不放行」这条规则，
    // 免得将来有人为了看嵌套指标而把容器整体加到白名单。
    final messages = capture(
      (logger) => logger.log(
        LogLevel.info,
        'nested',
        fields: {
          'attempts': [
            {'durationMs': 5, 'menuText': canaries[0]},
          ],
        },
      ),
    );

    expect(messages.single, isNot(contains(canaries[0])));
    expect(messages.single, isNot(contains('durationMs: 5')));
  });

  test('默认白名单就是生产上在用的指标（四个 AI 指标 + 备份文件尺寸）', () {
    // sizeBytes（backup_file_store 的备份文件字节数）是 2026-09-19 白名单
    // 评审通过加入的：设备侧文件尺寸指标，不含任何用户内容。此前它被
    // 默认拒绝抹成 [REDACTED:not-allow-listed]，等于写不出去。
    expect(PrivacyLogger.defaultAllowedKeys, {
      'resultKind',
      'durationMs',
      'requestBytes',
      'responseBytes',
      'sizeBytes',
    });
  });

  test('sizeBytes 走白名单原样落盘（P3：该指标此前实际写不出去）', () {
    final messages = <String>[];
    final logger = PrivacyLogger(writer: messages.add);
    logger.log(
      LogLevel.info,
      'backup_written',
      fields: {'resultKind': 'success', 'sizeBytes': 14184448},
    );
    expect(messages.single, contains('sizeBytes: 14184448'));
    expect(messages.single, isNot(contains('not-allow-listed')));
  });
}
