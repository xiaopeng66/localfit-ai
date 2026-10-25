import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/application/scale_sync_controller.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/scale_reading_source.dart';
import 'package:localfit_ai/features/progress/data/standard_scale_reading_source.dart';

/// T14（docs/32 §4 T14 / §3 D16）：电子秤「读数来源」抽象与厂商 parser 挂点。
///
/// 本文件管三件事，恰对应 T14 的三条新验收：
/// ① 标准协议行为无回归——`StandardScaleReadingSource` 是通道的逐字透传；
/// ② 编排只依赖抽象——fake source 就能把 `ScaleSyncController` 的七种结局全驱动；
/// ③ 新增私有协议只需注册 parser——假 parser 进 registry，被按设备正确分派。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = MethodChannel('localfit/scale');
  Map<Object?, Object?>? Function(MethodCall call)? handler;

  setUp(() {
    handler = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channelName, (call) async {
          final scripted = handler;
          if (scripted == null) throw PlatformException(code: 'none');
          return scripted(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channelName, null);
  });

  /// 拟「小米秤」这类私有协议设备：不广播 0x181D，认领要靠广播名。
  const vendorDevice = ScaleDevice(
    id: 'C8:47:8C:00:00:01',
    name: 'MI SCALE2',
    serviceUuids: ['0000fee7-0000-1000-8000-00805f9b34fb'],
  );

  group('ScaleDevice：按广播服务/设备名认领', () {
    test('advertises 大小写不敏感；没带的服务不认', () {
      const device = ScaleDevice(
        id: 'AA:BB:CC:00:00:01',
        name: 'Mi Body Composition Scale',
        serviceUuids: ['0000181D-0000-1000-8000-00805F9B34FB'],
      );
      expect(device.advertises(standardWeightScaleServiceUuid), isTrue);
      expect(
        device.advertises('0000181d-0000-1000-8000-00805f9b34fb'),
        isTrue,
        reason: '大小写归一后同一条服务',
      );
      expect(
        device.advertises('0000181d-0000-1000-8000-00805f9b34fc'),
        isFalse,
        reason: '差一位就不是这条服务',
      );
      expect(
        device.advertises('0000fee7-0000-1000-8000-00805f9b34fb'),
        isFalse,
      );
    });
  });

  group('ScaleParserRegistry：厂商挂点（D16 验收 ③）', () {
    test('标准设备归标准 parser；注册的厂商 parser 只认领自己的设备；不认识如实为 null', () {
      final registry = ScaleParserRegistry([
        StandardWeightMeasurementParser(),
        _VendorParser(),
      ]);

      expect(
        registry.forDevice(standardWeightScaleDevice)?.id,
        'standard_weight_measurement',
      );
      expect(registry.forDevice(vendorDevice)?.id, 'fake_mi_scale');
      expect(
        registry.forDevice(
          const ScaleDevice(id: 'x', name: '未知名', serviceUuids: []),
        ),
        isNull,
        reason: '没人认领就是没人认领，不硬塞一个 parser',
      );
      expect(registry.parsers, hasLength(2));
    });

    test('分派读一次：认领者被真实调用，设备与窗口原样带过去', () async {
      final vendor = _VendorParser(
        reading: const ScaleReading(status: ScaleReadStatus.ok, grams: 72500),
      );
      final registry = ScaleParserRegistry([vendor]);

      final reading = await registry.readOnce(
        vendorDevice,
        window: const Duration(seconds: 3),
      );

      expect(reading.status, ScaleReadStatus.ok);
      expect(reading.grams, 72500);
      expect(vendor.calls, [('C8:47:8C:00:00:01', const Duration(seconds: 3))]);
    });

    test('没人认领：如实 timeout/no_parser，不猜一个数值', () async {
      final registry = ScaleParserRegistry();
      final reading = await registry.readOnce(
        vendorDevice,
        window: const Duration(seconds: 3),
      );
      expect(reading.status, ScaleReadStatus.timeout);
      expect(reading.reason, 'no_parser');
      expect(reading.grams, isNull);
    });

    test('重复 id 注册 = 接线错误：直接抛，不静默覆盖', () {
      final registry = ScaleParserRegistry([_VendorParser()]);
      expect(() => registry.register(_VendorParser()), throwsArgumentError);
      expect(registry.parsers, hasLength(1));
    });
  });

  group('StandardScaleReadingSource：标准协议逐字透传（T14 验收 ①）', () {
    test('默认注册表 = 只有标准 parser，认领标准设备描述', () {
      final source = StandardScaleReadingSource();
      expect(source.parsers.parsers.map((it) => it.id), [
        'standard_weight_measurement',
      ]);
      expect(
        source.parsers.forDevice(standardWeightScaleDevice)?.id,
        'standard_weight_measurement',
      );
    });

    test('ok 读数原样带出（克 / atMs）', () async {
      handler = (_) => {'status': 'ok', 'grams': 62400, 'atMs': 1728460800000};
      final source = StandardScaleReadingSource();

      final reading = await source.readOnce();

      expect(reading.status, ScaleReadStatus.ok);
      expect(reading.grams, 62400);
      expect(reading.atMs, 1728460800000);
    });

    test('失败态逐一保持：no_scale / timeout / denied / unsupported 不合并', () async {
      final source = StandardScaleReadingSource();
      final cases = <Map<Object?, Object?>, (ScaleReadStatus, String?)>{
        {'status': 'no_scale', 'reason': 'scan_window'}: (
          ScaleReadStatus.noScale,
          'scan_window',
        ),
        {'status': 'timeout', 'reason': 'gatt_window'}: (
          ScaleReadStatus.timeout,
          'gatt_window',
        ),
        {'status': 'denied'}: (ScaleReadStatus.denied, null),
        {'status': 'unsupported'}: (ScaleReadStatus.unsupported, null),
      };
      for (final entry in cases.entries) {
        handler = (_) => entry.key;
        final reading = await source.readOnce();
        expect(reading.status, entry.value.$1, reason: '${entry.key} 的状态不许合并');
        expect(reading.reason, entry.value.$2);
      }
    });

    test('readOnce 真的过 registry：换掉认领者，来源的输出就换人', () async {
      handler = (_) => {'status': 'ok', 'grams': 62400, 'atMs': 1};
      // 一个「认领一切」的 recorder：它给出的读数必须压过通道脚本，
      // 证明来源不是绕过 registry 直接调通道。
      final recorder = _VendorParser(
        id: 'recorder',
        matchesEverything: true,
        reading: const ScaleReading(status: ScaleReadStatus.ok, grams: 88800),
      );
      final source = StandardScaleReadingSource(
        parsers: ScaleParserRegistry([recorder]),
      );

      final reading = await source.readOnce();

      expect(reading.grams, 88800);
      expect(recorder.calls, hasLength(1));
      expect(source.parsers.parsers.single.id, 'recorder');
    });

    test('能力/授权/去系统设置都直通通道（行徽章与弹层用）', () async {
      final calls = <String>[];
      handler = (call) {
        calls.add(call.method);
        return switch (call.method) {
          'check' => {'status': 'ready'},
          'requestPermission' => {'status': 'granted'},
          'openAppSettings' => null,
          _ => throw StateError('unexpected ${call.method}'),
        };
      };
      final source = StandardScaleReadingSource();

      expect(await source.check(), ScaleAvailability.ready);
      expect(await source.requestPermission(), isTrue);
      await source.openAppSettings();

      expect(calls, ['check', 'requestPermission', 'openAppSettings']);
    });
  });

  group('编排只依赖抽象：fake source 驱动七种结局（T14 验收 ②）', () {
    final nowUtc = DateTime.utc(2026, 10, 13, 12);
    late AppDatabase database;
    late MeasurementRepository repository;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      repository = MeasurementRepository(
        database: database,
        idGenerator: _Ids(),
        clock: FixedAppClock(nowUtc),
      );
    });

    tearDown(() => database.close());

    String expectedToday() {
      final local = nowUtc.toLocal();
      return '${local.year.toString().padLeft(4, '0')}-'
          '${local.month.toString().padLeft(2, '0')}-'
          '${local.day.toString().padLeft(2, '0')}';
    }

    Future<void> addProfile() async {
      await database
          .into(database.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: 'profile',
              activityLevel: 'lightlyActive',
              createdAt: nowUtc,
              updatedAt: nowUtc,
            ),
          );
    }

    ScaleSyncController overSource(_FakeSource source) => ScaleSyncController(
      source: source,
      repository: repository,
      clock: FixedAppClock(nowUtc),
    );

    test('ok → 落库，来源 ble_scale（落地规则经由抽象同样成立）', () async {
      await addProfile();
      final source = _FakeSource(
        reading: const ScaleReading(status: ScaleReadStatus.ok, grams: 62400),
      );

      final outcome = await overSource(source).sync();

      expect(outcome, isA<ScaleSyncSaved>());
      expect((outcome as ScaleSyncSaved).measurement.source, 'ble_scale');
      final row = await (database.select(
        database.measurements,
      )..limit(1)).getSingle();
      expect(row.source, 'ble_scale');
      expect(row.localDate, expectedToday());
    });

    test('同日已有手输 → 冲突且一个字不写（默认保留）', () async {
      await addProfile();
      await database
          .into(database.measurements)
          .insert(
            MeasurementsCompanion.insert(
              id: 'manual-1',
              profileId: 'profile',
              localDate: expectedToday(),
              weightKg: 62.8,
              source: const Value('manual'),
              createdAt: nowUtc,
              updatedAt: nowUtc,
            ),
          );
      final source = _FakeSource(
        reading: const ScaleReading(status: ScaleReadStatus.ok, grams: 62400),
      );

      final outcome = await overSource(source).sync();

      expect(outcome, isA<ScaleSyncConflict>());
      final rows = await database.select(database.measurements).get();
      expect(rows, hasLength(1));
      expect(rows.single.weightKg, closeTo(62.8, 1e-9));
      expect(rows.single.source, 'manual');
    });

    test(
      '其余结局逐一对上：outOfRange / noScale / timeout / denied / unsupported',
      () async {
        await addProfile();
        final scripted = <(_FakeSource, Type)>[
          (
            _FakeSource(
              reading: const ScaleReading(
                status: ScaleReadStatus.ok,
                grams: 34500,
              ),
            ),
            ScaleSyncOutOfRange,
          ),
          (
            _FakeSource(
              reading: const ScaleReading(status: ScaleReadStatus.noScale),
            ),
            ScaleSyncNoScale,
          ),
          (
            _FakeSource(
              reading: const ScaleReading(status: ScaleReadStatus.timeout),
            ),
            ScaleSyncTimeout,
          ),
          (
            _FakeSource(
              reading: const ScaleReading(status: ScaleReadStatus.denied),
            ),
            ScaleSyncPermissionDenied,
          ),
          (
            _FakeSource(availability: ScaleAvailability.unsupported),
            ScaleSyncUnsupported,
          ),
        ];
        for (final (source, expected) in scripted) {
          final outcome = await overSource(source).sync();
          expect(
            outcome.runtimeType,
            expected,
            reason: '脚本 ${source.describe()} 应映射 $expected',
          );
          expect(await database.select(database.measurements).get(), isEmpty);
        }
      },
    );

    test('未授权 / 更前面的门都不过时：不发起读取（calls 顺序如实）', () async {
      final deniedPermission = _FakeSource(permissionGranted: false);
      expect(
        await overSource(deniedPermission).sync(),
        isA<ScaleSyncPermissionDenied>(),
      );
      expect(deniedPermission.calls, ['check', 'requestPermission']);

      final unsupported = _FakeSource(
        availability: ScaleAvailability.unsupported,
      );
      expect(await overSource(unsupported).sync(), isA<ScaleSyncUnsupported>());
      expect(unsupported.calls, ['check']);
    });

    test('availability 直通来源 check（行徽章用）', () async {
      final source = _FakeSource(availability: ScaleAvailability.denied);
      expect(await overSource(source).availability(), ScaleAvailability.denied);
      expect(source.calls, ['check']);
    });
  });
}

/// 假「厂商 parser」：按广播名认领（拟小米这类私有协议的注册样式）。
final class _VendorParser implements ScaleProtocolParser {
  _VendorParser({
    this.id = 'fake_mi_scale',
    this.matchesEverything = false,
    this.reading = const ScaleReading(status: ScaleReadStatus.noScale),
  });

  @override
  final String id;

  final bool matchesEverything;
  final ScaleReading reading;

  /// (设备 id, 窗口) 调用记录。
  final calls = <(String, Duration)>[];

  @override
  bool matches(ScaleDevice device) =>
      matchesEverything || device.name.toUpperCase().startsWith('MI SCALE');

  @override
  Future<ScaleReading> readOnce(
    ScaleDevice device, {
    required Duration window,
  }) async {
    calls.add((device.id, window));
    return reading;
  }
}

/// 只实现抽象、不碰平台通道的假来源：证明编排层对实现的唯一要求就是这个接口。
final class _FakeSource implements ScaleReadingSource {
  _FakeSource({
    this.availability = ScaleAvailability.ready,
    this.permissionGranted = true,
    this.reading = const ScaleReading(status: ScaleReadStatus.noScale),
  });

  ScaleAvailability availability;
  bool permissionGranted;
  ScaleReading reading;
  final calls = <String>[];

  @override
  final ScaleParserRegistry parsers = ScaleParserRegistry();

  @override
  Future<ScaleAvailability> check() async {
    calls.add('check');
    return availability;
  }

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    return permissionGranted;
  }

  @override
  Future<void> openAppSettings() async => calls.add('openAppSettings');

  @override
  Future<ScaleReading> readOnce({
    Duration window = ScaleReadingSource.defaultWindow,
  }) async {
    calls.add('readOnce');
    return reading;
  }

  String describe() =>
      '${availability.name}/granted=$permissionGranted/${reading.status.name}';
}

final class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'id-${++_n}';
}
