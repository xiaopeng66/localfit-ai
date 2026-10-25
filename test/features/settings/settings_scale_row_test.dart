import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/application/scale_sync_controller.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/standard_scale_reading_source.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

/// 设置页「电子体重秤」行（docs/31 S6，需求 47 / D6）。
///
/// 断言围绕四件事：① 行徽章三态各自说实话（不合并、不猜）；
/// ② 未接线不渲染；③ 说明弹层的动作接对了（去系统设置 / 开始同步）；
/// ④ 同步结局按 D6 ③ 呈现——成功落库、同日冲突默认保留原记录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/scale');
  final nowUtc = DateTime(2026, 10, 8, 9).toUtc();
  Future<Map<Object?, Object?>?> Function(MethodCall call)? handler;
  var openSettingsCalls = 0;

  setUp(() {
    handler = null;
    openSettingsCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'openAppSettings':
              openSettingsCalls++;
              return null;
          }
          final scripted = handler;
          if (scripted == null) throw PlatformException(code: 'none');
          return scripted(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  late AppDatabase database;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

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

  ScaleSyncController controller() => ScaleSyncController(
    source: StandardScaleReadingSource(),
    repository: MeasurementRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(nowUtc),
    ),
    clock: FixedAppClock(nowUtc),
  );

  Widget host(Widget child) =>
      MaterialApp(theme: AppTheme.light(), home: child);

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      host(SettingsPage(scaleSync: controller(), now: nowUtc.toLocal())),
    );
    await tester.pumpAndSettle();
    final finder = find.byKey(const Key('settings-scale-row'));
    await scrollTo(tester, finder);
    expect(finder, findsOneWidget, reason: '数据管理组里的电子体重秤行没出现');
  }

  Future<void> closeDatabase(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  }

  group('行徽章三态（不合并、不猜）', () {
    testWidgets('ready → 已授权', (tester) async {
      handler = (_) async => {'status': 'ready'};
      await pumpSettings(tester);
      expect(find.text('已授权'), findsOneWidget);
      await closeDatabase(tester);
    });

    testWidgets('denied → 未授权', (tester) async {
      handler = (_) async => {'status': 'denied'};
      await pumpSettings(tester);
      expect(find.text('未授权'), findsOneWidget);
      await closeDatabase(tester);
    });

    testWidgets('unsupported → 设备不支持（API ≤ 30 的诚实降级）', (tester) async {
      handler = (_) async => {'status': 'unsupported', 'reason': 'api_too_low'};
      await pumpSettings(tester);
      expect(find.text('设备不支持'), findsOneWidget);
      await closeDatabase(tester);
    });

    testWidgets('未接线（scaleSync == null）：组在场、这一行不渲染', (tester) async {
      await tester.pumpWidget(
        host(
          SettingsPage(
            appSettingsRepository: AppSettingsRepository(database: database),
            now: nowUtc.toLocal(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byKey(const Key('settings-group-data')));
      expect(find.byKey(const Key('settings-group-data')), findsOneWidget);
      expect(find.byKey(const Key('settings-scale-row')), findsNothing);
      await closeDatabase(tester);
    });
  });

  group('说明弹层（docs/31 S6 稿 ②）', () {
    testWidgets('正文四条说明 + 三个动作都在；去系统设置真的去调通道', (tester) async {
      handler = (_) async => {'status': 'denied'};
      await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('settings-scale-row')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('scale-permission-sheet-body')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('scale-action-sync')), findsOneWidget);
      expect(
        find.byKey(const Key('scale-action-app-settings')),
        findsOneWidget,
      );
      expect(find.text('授权并开始同步'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scale-action-app-settings')));
      await tester.pumpAndSettle();
      expect(openSettingsCalls, 1);
      expect(find.byKey(const Key('scale-action-sync')), findsNothing);
      await closeDatabase(tester);
    });
  });

  group('同步结局（docs/31 S6 稿 ④）', () {
    testWidgets('扫描中：进度态在场、可取消；取消后不再弹任何结局', (tester) async {
      await addProfile();
      // scanOnce 永不完成：模拟秤一直没读到。
      final never = Completer<Map<Object?, Object?>?>();
      handler = (call) async {
        switch (call.method) {
          case 'check':
            return {'status': 'ready'};
          case 'requestPermission':
            return {'status': 'granted'};
          case 'scanOnce':
            return await never.future;
        }
        throw StateError('unexpected ${call.method}');
      };
      await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('settings-scale-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scale-action-sync')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('scale-sync-progress')), findsOneWidget);
      expect(find.byKey(const Key('scale-sync-cancel')), findsOneWidget);
      await tester.tap(find.byKey(const Key('scale-sync-cancel')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('scale-sync-progress')),
        findsNothing,
        reason: '取消即关弹层，结局无处呈现也不再弹',
      );
      await closeDatabase(tester);
    });

    testWidgets('当天无记录 → 落库 ble_scale + 成功提示', (tester) async {
      await addProfile();
      handler = (call) async => switch (call.method) {
        'check' => {'status': 'ready'},
        'requestPermission' => {'status': 'granted'},
        'scanOnce' => {'status': 'ok', 'grams': 62400, 'atMs': 1728460800000},
        _ => throw StateError('unexpected ${call.method}'),
      };
      await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('settings-scale-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scale-action-sync')));
      // 扫描态有转圈动画，pumpAndSettle 会等不到停：按固定步长推进，
      // 让通道 mock 的答复在 pump 间送达。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('scale-action-sync')),
        findsNothing,
        reason: '同步完成后弹层关闭',
      );
      expect(find.text('已同步秤读数 62.40 kg。'), findsOneWidget);
      final row = await (database.select(
        database.measurements,
      )..limit(1)).getSingle();
      expect(row.source, 'ble_scale');
      expect(row.localDate, expectedToday());
      await closeDatabase(tester);
    });

    testWidgets('同日冲突 → 二选一弹层；默认动作保留原记录，一个字不动', (tester) async {
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
      handler = (call) async => switch (call.method) {
        'check' => {'status': 'ready'},
        'requestPermission' => {'status': 'granted'},
        'scanOnce' => {'status': 'ok', 'grams': 62400, 'atMs': 1728460800000},
        _ => throw StateError('unexpected ${call.method}'),
      };
      await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('settings-scale-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scale-action-sync')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scale-conflict-body')), findsOneWidget);
      expect(find.textContaining('62.80 kg'), findsOneWidget);
      expect(find.textContaining('62.40 kg'), findsOneWidget);
      await tester.tap(find.byKey(const Key('scale-conflict-keep')));
      await tester.pumpAndSettle();

      expect(find.text('已保留原记录。'), findsOneWidget);
      final row = await (database.select(
        database.measurements,
      )..limit(1)).getSingle();
      expect(row.weightKg, closeTo(62.8, 1e-9));
      expect(row.source, 'manual');
      await closeDatabase(tester);
    });

    testWidgets('冲突后明确选覆盖 → 换成秤读数、来源 ble_scale', (tester) async {
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
      handler = (call) async => switch (call.method) {
        'check' => {'status': 'ready'},
        'requestPermission' => {'status': 'granted'},
        'scanOnce' => {'status': 'ok', 'grams': 62400, 'atMs': 1728460800000},
        _ => throw StateError('unexpected ${call.method}'),
      };
      await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('settings-scale-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scale-action-sync')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scale-conflict-overwrite')));
      await tester.pumpAndSettle();

      expect(find.textContaining('已用秤读数 62.40 kg 覆盖今天的记录。'), findsOneWidget);
      final row = await (database.select(
        database.measurements,
      )..limit(1)).getSingle();
      expect(row.weightKg, closeTo(62.4, 1e-9));
      expect(row.source, 'ble_scale');
      expect(row.notes, '晨重');
      await closeDatabase(tester);
    });

    testWidgets('未发现支持的电子秤 → 如实提示，不落库', (tester) async {
      await addProfile();
      handler = (call) async => switch (call.method) {
        'check' => {'status': 'ready'},
        'requestPermission' => {'status': 'granted'},
        'scanOnce' => {'status': 'no_scale', 'reason': 'scan_window'},
        _ => throw StateError('unexpected ${call.method}'),
      };
      await pumpSettings(tester);
      await tester.tap(find.byKey(const Key('settings-scale-row')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scale-action-sync')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.textContaining('未发现支持的电子秤'), findsOneWidget);
      expect(await database.select(database.measurements).get(), isEmpty);
      await closeDatabase(tester);
    });
  });
}

final class _Ids implements IdGenerator {
  var value = 0;

  @override
  String next() => 'scale-${++value}';
}
