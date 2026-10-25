import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';

/// docs/29 §P9 需求 34 的 Dart 侧全量覆盖：重启基线、四态读数、
/// 「不可用时一个字都不写」。真机端到端是诚实边界（AVD 无计步器），
/// 这里用 fake channel 把四态都逼出来。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/steps');

  /// 通道上一次应答（`read` / `requestPermission` / `openAppSettings`）。
  Object? readReply;
  Object? permissionReply;

  setUp(() {
    readReply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'read':
              return readReply;
            case 'requestPermission':
              return permissionReply;
            case 'openAppSettings':
              return null;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('resolveTodaySteps：三种情形都不许冒充', () {
    test('没有基线（今天第一次读）：以当前累计值为基线，今日 0 步', () {
      final today = resolveTodaySteps(
        reading: const StepsReading(
          availability: StepsAvailability.available,
          counter: 5000,
        ),
        localDate: '2026-10-07',
        baseline: null,
      );
      expect(today.steps, 0);
      expect(today.baseline.counter, 5000);
      expect(today.baseline.localDate, '2026-10-07');
      expect(today.resetBaseline, isFalse);
    });

    test('同日正常累加：差值即今日步数', () {
      final today = resolveTodaySteps(
        reading: const StepsReading(
          availability: StepsAvailability.available,
          counter: 8432,
        ),
        localDate: '2026-10-07',
        baseline: const StepsBaseline(localDate: '2026-10-07', counter: 3000),
      );
      expect(today.steps, 5432);
      // 差值路径下基线不动（写回同一个值是白写）。
      expect(today.baseline.counter, 3000);
      expect(today.resetBaseline, isFalse);
    });

    test('计数值回退（设备重启）：不显示负数，重设基线', () {
      final today = resolveTodaySteps(
        reading: const StepsReading(
          availability: StepsAvailability.available,
          counter: 120, // 重启后从 0 重新累计
        ),
        localDate: '2026-10-07',
        baseline: const StepsBaseline(localDate: '2026-10-07', counter: 9000),
      );
      expect(today.steps, 0, reason: '重启差值是负数，不许显示');
      expect(today.baseline.counter, 120, reason: '基线必须重设到重启后的累计值');
      expect(today.resetBaseline, isTrue);
    });

    test('跨天：旧基线不参与今天的计算', () {
      final today = resolveTodaySteps(
        reading: const StepsReading(
          availability: StepsAvailability.available,
          counter: 12000,
        ),
        localDate: '2026-10-08',
        baseline: const StepsBaseline(localDate: '2026-10-07', counter: 9000),
      );
      expect(today.steps, 0, reason: '昨天 9000 与今天 12000 之差是跨天的脏值');
      expect(today.baseline.localDate, '2026-10-08');
    });
  });

  group('StepsChannel.parse：原生回包翻译', () {
    test('ok / counter / atMs', () async {
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 4242,
        'atMs': 1699000000000,
      };
      final reading = await StepsChannel().read();
      expect(reading.availability, StepsAvailability.available);
      expect(reading.counter, 4242);
      expect(reading.atMs, 1699000000000);
    });

    test('denied → 权限被拒（不是「没有传感器」）', () async {
      readReply = <Object?, Object?>{'status': 'denied'};
      final reading = await StepsChannel().read();
      expect(reading.availability, StepsAvailability.denied);
    });

    test('unavailable + no_counter_sensor / detector_only 分开记', () async {
      readReply = <Object?, Object?>{
        'status': 'unavailable',
        'reason': 'detector_only',
      };
      final reading = await StepsChannel().read();
      expect(reading.availability, StepsAvailability.noSensor);
      expect(reading.reason, 'detector_only');
    });

    test('counter 不是 int → 拒绝冒充，按没读到处理', () async {
      readReply = <Object?, Object?>{'status': 'ok', 'counter': '4242'};
      final reading = await StepsChannel().read();
      expect(reading.availability, StepsAvailability.noReading);
      expect(reading.reason, 'bad_counter');
    });

    test('原生抛异常 → noReading（步数卡不许被通道打死）', () async {
      readReply = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'channel_error');
          });
      final reading = await StepsChannel().read();
      expect(reading.availability, StepsAvailability.noReading);
    });
  });

  group('StepsRepository.syncToday：不可用时一个字都不写', () {
    late AppDatabase database;
    late StepsRepository repository;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      repository = StepsRepository(
        database: database,
        channel: StepsChannel(),
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime(2026, 10, 7, 9).toUtc()),
      );
    });

    tearDown(() => database.close());

    test('available：落库 + 基线写入', () async {
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 5000,
        'atMs': 1,
      };
      final result = await repository.syncToday('2026-10-07');
      expect(result.saved, isTrue);
      expect(result.steps, 0, reason: '首次读：基线即当前值，今日 0');
      expect(await repository.stepsForDate('2026-10-07'), 0);
      // 第二次读（同一基线上累加了 3432 步）
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 8432,
        'atMs': 2,
      };
      final second = await repository.syncToday('2026-10-07');
      expect(second.saved, isTrue);
      expect(second.steps, 3432);
      expect(await repository.stepsForDate('2026-10-07'), 3432);
    });

    test('重启回退：落库 0 并重设基线（不是负数）', () async {
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 9000,
        'atMs': 1,
      };
      await repository.syncToday('2026-10-07');
      readReply = <Object?, Object?>{'status': 'ok', 'counter': 120, 'atMs': 2};
      final result = await repository.syncToday('2026-10-07');
      expect(result.steps, 0);
      expect(result.resetBaseline, isTrue);
      expect(await repository.stepsForDate('2026-10-07'), 0);
    });

    test('noSensor / denied / noReading：步数表与基线都不留行', () async {
      for (final reply in [
        <Object?, Object?>{
          'status': 'unavailable',
          'reason': 'no_counter_sensor',
        },
        <Object?, Object?>{'status': 'denied'},
        <Object?, Object?>{'status': 'unavailable', 'reason': 'no_event'},
      ]) {
        readReply = reply;
        final result = await repository.syncToday('2026-10-07');
        expect(result.saved, isFalse, reason: '$reply 不可用时不得落库');
        expect(result.steps, isNull);
      }
      final rows = await database.select(database.stepsDaily).get();
      expect(rows, isEmpty, reason: '「没读成」不许被记成「没走过」');
      expect(await repository.readBaseline(), isNull);
    });

    // 2026-10-16 用户实测：「步数查询授权后仍识别不了」。
    // 根因：原生 read 的窗口只有 2s，`TYPE_STEP_COUNTER` 首帧偶发落在窗口外
    // 时回 `unavailable + no_event`，而这里把**所有** unavailable 都翻成
    // noSensor ⇒ 界面写「这台设备没有计步传感器」（那是句假话：设备有，只是
    // 这次没读到）。no_event 必须翻成 noReading。
    test(
      'no_event 翻成 noReading（不是「没有传感器」），其余 unavailable 才是 noSensor',
      () async {
        readReply = <Object?, Object?>{
          'status': 'unavailable',
          'reason': 'no_event',
        };
        var reading = await StepsChannel().read();
        expect(reading.availability, StepsAvailability.noReading);
        expect(reading.reason, 'no_event', reason: '细分原因原样保留给诊断');

        for (final reason in ['no_counter_sensor', 'detector_only']) {
          readReply = <Object?, Object?>{
            'status': 'unavailable',
            'reason': reason,
          };
          reading = await StepsChannel().read();
          expect(
            reading.availability,
            StepsAvailability.noSensor,
            reason: '$reason 才是真的没有累计计数器',
          );
        }
      },
    );

    test('openAppSettings 转发到通道；requestPermission 以原生回包为准', () async {
      var settingsOpened = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'openAppSettings') {
              settingsOpened = true;
              return null;
            }
            if (call.method == 'requestPermission') {
              return <Object?, Object?>{'status': 'granted'};
            }
            return null;
          });
      await repository.openAppSettings();
      expect(settingsOpened, isTrue, reason: '去设置必须真的走到通道');
      expect(await repository.requestPermission(), isTrue);

      // 原生回 denied：如实说 false，不许乐观。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'requestPermission') {
              return <Object?, Object?>{'status': 'denied'};
            }
            return null;
          });
      expect(await repository.requestPermission(), isFalse);
    });

    test('watchDate 在写入后推送新值', () async {
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 5000,
        'atMs': 1,
      };
      await repository.syncToday('2026-10-07');
      final seen = <int?>[];
      final sub = repository.watchDate('2026-10-07').listen(seen.add);
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 6500,
        'atMs': 2,
      };
      await repository.syncToday('2026-10-07');
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen.last, 1500);
    });

    test('坏基线 JSON 当作没有基线（首次读取）', () async {
      await database
          .into(database.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: StepsRepository.baselineKey,
              value: 'not-json',
            ),
          );
      readReply = <Object?, Object?>{
        'status': 'ok',
        'counter': 5000,
        'atMs': 1,
      };
      final result = await repository.syncToday('2026-10-07');
      expect(result.steps, 0, reason: '坏基线按首次读取处理，而不是抛异常');
    });
  });
}

final class _Ids implements IdGenerator {
  int _v = 0;
  @override
  String next() => 'steps-${_v++}';
}
