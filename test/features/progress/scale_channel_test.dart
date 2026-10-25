import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/progress/data/scale_channel.dart';

/// `localfit/scale` 通道薄封装（docs/31 S6，需求 47 / D6）。
///
/// 与步数通道同一套测试法：`TestDefaultBinaryMessengerBinding` 装 fake
/// handler，不需要真秤就能覆盖全部状态（D6 ⑤ 的验收上限）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <String>[];
  Map<Object?, Object?>? Function(MethodCall call)? handler;

  setUp(() {
    calls.clear();
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('localfit/scale'), (
          call,
        ) async {
          calls.add(call.method);
          final scripted = handler;
          if (scripted == null) throw PlatformException(code: 'none');
          return scripted(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('localfit/scale'), null);
  });

  group('check', () {
    test('ready / denied / unsupported 各自如实翻译', () async {
      final channel = ScaleChannel();
      handler = (_) => {'status': 'ready'};
      expect(await channel.check(), ScaleAvailability.ready);
      handler = (_) => {'status': 'denied'};
      expect(await channel.check(), ScaleAvailability.denied);
      handler = (_) => {'status': 'unsupported', 'reason': 'api_too_low'};
      expect(await channel.check(), ScaleAvailability.unsupported);
      expect(calls, ['check', 'check', 'check']);
    });

    test('未知状态与通道异常都按「不支持」——不把不确定报成能扫', () async {
      final channel = ScaleChannel();
      handler = (_) => {'status': 'something_new'};
      expect(await channel.check(), ScaleAvailability.unsupported);
      handler = (_) => throw PlatformException(code: 'crash');
      expect(await channel.check(), ScaleAvailability.unsupported);
    });
  });

  group('requestPermission', () {
    test('granted 以原生回的 status 为准', () async {
      final channel = ScaleChannel();
      handler = (_) => {'status': 'granted'};
      expect(await channel.requestPermission(), isTrue);
      handler = (_) => {'status': 'denied'};
      expect(await channel.requestPermission(), isFalse);
      handler = (_) => throw PlatformException(code: 'crash');
      expect(await channel.requestPermission(), isFalse);
    });
  });

  group('scanOnce', () {
    test('ok：克数原样带出（解析在原生侧完成）', () async {
      final channel = ScaleChannel();
      handler = (_) => {'status': 'ok', 'grams': 62400, 'atMs': 1728460800000};
      final reading = await channel.scanOnce();
      expect(reading.status, ScaleReadStatus.ok);
      expect(reading.grams, 62400);
      expect(reading.atMs, 1728460800000);
      expect(calls, ['scanOnce']);
    });

    test('ok 但 grams 不是 int：按 timeout + bad_grams，不猜数值', () async {
      final channel = ScaleChannel();
      handler = (_) => {'status': 'ok', 'grams': '62.4'};
      final reading = await channel.scanOnce();
      expect(reading.status, ScaleReadStatus.timeout);
      expect(reading.reason, 'bad_grams');
    });

    test('no_scale / timeout / denied / unsupported 四态分开', () async {
      final channel = ScaleChannel();
      handler = (_) => {'status': 'no_scale', 'reason': 'scan_window'};
      expect((await channel.scanOnce()).status, ScaleReadStatus.noScale);
      handler = (_) => {'status': 'timeout', 'reason': 'gatt_window'};
      expect((await channel.scanOnce()).status, ScaleReadStatus.timeout);
      handler = (_) => {'status': 'denied'};
      expect((await channel.scanOnce()).status, ScaleReadStatus.denied);
      handler = (_) => {'status': 'unsupported'};
      expect((await channel.scanOnce()).status, ScaleReadStatus.unsupported);
    });

    test('未知状态与通道异常都翻成 timeout，不带编造的读数', () async {
      final channel = ScaleChannel();
      handler = (_) => {'status': 'mystery'};
      final unknown = await channel.scanOnce();
      expect(unknown.status, ScaleReadStatus.timeout);
      expect(unknown.reason, 'unknown_status');
      expect(unknown.grams, isNull);
      handler = (_) => throw PlatformException(code: 'crash');
      final error = await channel.scanOnce();
      expect(error.status, ScaleReadStatus.timeout);
      expect(error.reason, 'channel_error');
    });
  });

  group('openAppSettings', () {
    test('调用一次且不因通道异常抛出', () async {
      final channel = ScaleChannel();
      handler = (_) => null;
      await channel.openAppSettings();
      expect(calls, ['openAppSettings']);
      handler = (_) => throw PlatformException(code: 'crash');
      await channel.openAppSettings();
      expect(calls, ['openAppSettings', 'openAppSettings']);
    });
  });
}
