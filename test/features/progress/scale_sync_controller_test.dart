import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/application/scale_sync_controller.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/standard_scale_reading_source.dart';

/// 秤同步编排（docs/31 S6，需求 47 / D6）：权限 → 前台扫描 → 落地规则。
///
/// 通道用 mock handler（与 scale_channel_test 同法），仓储用内存库——
/// 编排、通道契约、落地规则三层在同一用例里真实协作，不互相伪造。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final nowUtc = DateTime.utc(2026, 9, 9, 12);
  late AppDatabase database;
  late MeasurementRepository repository;
  late ScaleSyncController controller;
  Map<Object?, Object?>? Function(MethodCall call)? handler;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = MeasurementRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(nowUtc),
    );
    controller = ScaleSyncController(
      // 读数来源 = 标准协议实现（内部走同一个 `localfit/scale` 通道 mock）：
      // 本文件因此仍是「编排 + 通道契约 + 落地规则」三层真实协作的回归。
      source: StandardScaleReadingSource(),
      repository: repository,
      clock: FixedAppClock(nowUtc),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('localfit/scale'), (
          call,
        ) async {
          final scripted = handler;
          if (scripted == null) throw PlatformException(code: 'none');
          return scripted(call);
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('localfit/scale'), null);
    await database.close();
  });

  void script(Map<Object?, Object?>? Function(MethodCall call) answers) {
    handler = answers;
  }

  void scriptHappyPath({required int grams}) {
    script(
      (call) => switch (call.method) {
        'check' => {'status': 'ready'},
        'requestPermission' => {'status': 'granted'},
        'scanOnce' => {'status': 'ok', 'grams': grams, 'atMs': 1728460800000},
        _ => throw StateError('unexpected ${call.method}'),
      },
    );
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

  String expectedToday() {
    final local = nowUtc.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  test('当天没有记录：读到即落库，来源 ble_scale（需求 47）', () async {
    await addProfile();
    scriptHappyPath(grams: 62400);

    final outcome = await controller.sync();

    expect(outcome, isA<ScaleSyncSaved>());
    final saved = outcome as ScaleSyncSaved;
    expect(saved.weightKg, closeTo(62.4, 1e-9));
    expect(saved.measurement.source, 'ble_scale');
    expect(saved.measurement.localDate, expectedToday());
    // 落库事实以行为准：source 是 ble_scale，不是 manual。
    final row = await (database.select(
      database.measurements,
    )..limit(1)).getSingle();
    expect(row.source, 'ble_scale');
    expect(row.weightKg, closeTo(62.4, 1e-9));
  });

  test('同日已有手输记录：默认不覆盖，原记录一个字都不动（D6 ③）', () async {
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
    scriptHappyPath(grams: 62400);

    final outcome = await controller.sync();

    expect(outcome, isA<ScaleSyncConflict>());
    final conflict = outcome as ScaleSyncConflict;
    expect(conflict.scaleWeightKg, closeTo(62.4, 1e-9));
    expect(conflict.existing.weightKg, closeTo(62.8, 1e-9));
    expect(conflict.existing.source, 'manual');

    final rows = await database.select(database.measurements).get();
    expect(rows, hasLength(1));
    expect(rows.single.weightKg, closeTo(62.8, 1e-9));
    expect(rows.single.source, 'manual');
  });

  test('冲突后用户明确选覆盖：换成秤读数，来源改 ble_scale，备注保留', () async {
    await addProfile();
    await database
        .into(database.measurements)
        .insert(
          MeasurementsCompanion.insert(
            id: 'manual-1',
            profileId: 'profile',
            localDate: expectedToday(),
            weightKg: 62.8,
            notes: const Value('晨重'),
            source: const Value('manual'),
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
    scriptHappyPath(grams: 62400);

    await controller.sync();
    final saved = await controller.overwriteSameDay(scaleWeightKg: 62.4);

    expect(saved.weightKg, closeTo(62.4, 1e-9));
    expect(saved.source, 'ble_scale');
    expect(saved.notes, '晨重');
    final row = await (database.select(
      database.measurements,
    )..limit(1)).getSingle();
    expect(row.weightKg, closeTo(62.4, 1e-9));
    expect(row.source, 'ble_scale');
  });

  test('超范围读数不落库（35–300 kg 口径与手输一致）', () async {
    await addProfile();
    scriptHappyPath(grams: 34500); // 34.5 kg

    final outcome = await controller.sync();

    expect(outcome, isA<ScaleSyncOutOfRange>());
    expect((outcome as ScaleSyncOutOfRange).weightKg, closeTo(34.5, 1e-9));
    expect(await database.select(database.measurements).get(), isEmpty);

    scriptHappyPath(grams: 301000); // 301 kg
    expect(await controller.sync(), isA<ScaleSyncOutOfRange>());
    expect(await database.select(database.measurements).get(), isEmpty);
  });

  test('通道各失败态逐一映射成对应结局，一个字都不写', () async {
    await addProfile();
    final cases = <Map<Object?, Object?>, Type>{
      {'status': 'no_scale', 'reason': 'scan_window'}: ScaleSyncNoScale,
      {'status': 'timeout', 'reason': 'gatt_window'}: ScaleSyncTimeout,
      {'status': 'denied'}: ScaleSyncPermissionDenied,
      {'status': 'unsupported'}: ScaleSyncUnsupported,
    };
    for (final entry in cases.entries) {
      script(
        (call) => switch (call.method) {
          'check' => {'status': 'ready'},
          'requestPermission' => {'status': 'granted'},
          'scanOnce' => entry.key,
          _ => throw StateError('unexpected ${call.method}'),
        },
      );
      final outcome = await controller.sync();
      expect(outcome.runtimeType, entry.value, reason: 'scan 回该状态应映射对应结局');
      expect(await database.select(database.measurements).get(), isEmpty);
    }
  });

  test('未授权（用户拒了系统对话框）：不发起扫描，结局 denied', () async {
    await addProfile();
    final scannedCalls = <String>[];
    script((call) {
      scannedCalls.add(call.method);
      return switch (call.method) {
        'check' => {'status': 'ready'},
        'requestPermission' => {'status': 'denied'},
        _ => throw StateError('unexpected ${call.method}'),
      };
    });

    expect(await controller.sync(), isA<ScaleSyncPermissionDenied>());
    expect(scannedCalls, isNot(contains('scanOnce')));
  });

  test('本机不支持（check 直接 unsupported）：不请求权限也不扫描', () async {
    final calls = <String>[];
    script((call) {
      calls.add(call.method);
      return {'status': 'unsupported', 'reason': 'api_too_low'};
    });

    expect(await controller.sync(), isA<ScaleSyncUnsupported>());
    expect(calls, ['check']);
  });

  test('availability 直通通道 check（行徽章用）', () async {
    script((call) => {'status': 'ready'});
    expect(await controller.availability(), ScaleAvailability.ready);
  });
}

final class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'id-${++_n}';
}
