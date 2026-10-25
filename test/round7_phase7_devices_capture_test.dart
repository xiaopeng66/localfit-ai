import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/progress/application/scale_sync_controller.dart';
import 'package:localfit_ai/features/progress/data/standard_scale_reading_source.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

import 'support/round7_render.dart';

/// Round7 阶段 7：**设备与权限行**的渲染帧（阶段 6 登记的最后视觉盲区）。
///
/// 4 帧：步数行（未授权态）浅 360-1.0、步数权限弹层浅 360-1.0、
/// 电子秤行（未适配/未连接态）浅 360-1.0、两行同屏深色 360-1.0。
///
/// 行为判据在 `steps_permission_row_test` / `settings_scale_row_test`（全量门禁
/// 里跑）；本件只补**可审看的实际渲染**，覆盖 docs/33 §3.7 的
/// 「未授权 / 拒绝 / 不支持 / 读取中 / 失败 / 成功」在静态帧上的最低档
/// （未授权）+ 秤的「接口预留、未适配」如实文案。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/steps');
  late AppDatabase database;
  final nowUtc = DateTime.utc(2026, 10, 15, 2);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    // 权限未授权：`permissionStatus` 返回 denied（与既有判据同一手法）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'permissionStatus') return 'denied';
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await database.close();
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    required bool withSteps,
    required bool withScale,
    required bool dark,
    double width = 360,
    double height = 900,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: round7CaptureTheme(dark ? AppTheme.dark() : AppTheme.light()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: SettingsPage(
            stepsRepository: withSteps
                ? StepsRepository(
                    database: database,
                    channel: StepsChannel(),
                    idGenerator: _Ids(),
                    clock: FixedAppClock(nowUtc),
                  )
                : null,
            scaleSync: withScale
                ? ScaleSyncController(
                    source: StandardScaleReadingSource(),
                    repository: MeasurementRepository(
                      database: database,
                      idGenerator: _Ids(),
                      clock: FixedAppClock(nowUtc),
                    ),
                    clock: FixedAppClock(nowUtc),
                  )
                : null,
            now: nowUtc.toLocal(),
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 24 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -320));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('设备与权限行（4 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    // 步数行（未授权）+ 秤行同屏（浅）
    await pumpSettings(tester, withSteps: true, withScale: true, dark: false);
    final steps = find.byKey(const Key('settings-steps-permission'));
    await scrollTo(tester, steps);
    expect(tester.takeException(), isNull, reason: '设备行浅色：布局溢出');
    await captureRound7(tester, 'settings-devices-light-360-1.0');

    // 步数权限弹层
    await tester.tap(steps);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    if (find
        .byKey(const Key('steps-permission-sheet-body'))
        .evaluate()
        .isNotEmpty) {
      await captureRound7(tester, 'settings-steps-sheet-light-360-1.0');
      // 关掉弹层
      await tester.tapAt(const Offset(10, 10));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    // 电子秤行（未适配文案）
    await pumpSettings(tester, withSteps: false, withScale: true, dark: false);
    final scale = find.byKey(const Key('settings-scale-row'));
    await scrollTo(tester, scale);
    expect(tester.takeException(), isNull, reason: '秤行浅色：布局溢出');
    await captureRound7(tester, 'settings-scale-light-360-1.0');

    // 两行同屏（深色）
    await pumpSettings(tester, withSteps: true, withScale: true, dark: true);
    await scrollTo(tester, find.byKey(const Key('settings-steps-permission')));
    expect(tester.takeException(), isNull, reason: '设备行深色：布局溢出');
    await captureRound7(tester, 'settings-devices-dark-360-1.0');

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

final class _Ids implements IdGenerator {
  int _v = 0;
  @override
  String next() => 'p7-${_v++}';
}
