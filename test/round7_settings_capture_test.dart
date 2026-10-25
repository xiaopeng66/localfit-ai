import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/backup/application/create_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/application/export_csv_files.dart';
import 'package:localfit_ai/features/backup/application/restore_encrypted_backup.dart';
import 'package:localfit_ai/features/backup/data/backup_file_store.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';

import 'support/round7_render.dart';

/// Round7 阶段 6 的渲染矩阵（「我的」= 设置页的四个分组 + AI 配置弹层）。
///
/// 6 帧：浅/深 360-1.0 顶段、浅 320-2.0×、浅 360-1.0 中段（数据组 +
/// 数据来源组）、浅 360-1.0 末段（关于 + 清空数据）、暗色 430-1.5。
///
/// A 的「我的」事实见 `app.js` 的 settings 族 + docs/21 §5.6（身份卡/健康指标/
/// 成就/设置分组/清空数据）。本页含无限动画（骨架/滚动）⇒ 用 `pump` 数拍。
void main() {
  late AppDatabase database;
  late MeasurementRepository measurements;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 10, 12, 8);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile',
            activityLevel: 'lightlyActive',
            createdAt: now,
            updatedAt: now,
          ),
        );
    // 昵称：身份卡要显示一个真名字（否则帧里是占位「Fit」）。
    await ProfileIdentityRepository(database: database).updateDisplayName('阿彭');
    measurements = MeasurementRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    await measurements.saveManualWeight(
      localDate: '2026-10-09',
      weightKg: 65.6,
    );
    await measurements.saveManualWeight(
      localDate: '2026-10-12',
      weightKg: 65.0,
    );
  });
  tearDown(() => database.close());

  Future<void> pumpSettings(
    WidgetTester tester, {
    required bool dark,
    required double width,
    required double height,
    required double scale,
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
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          // 不传 `apiKeyStore`（final 类不可替身，本帧也不需要 Key 读取）。
          // 备份/导出/清空接上内存库 ⇒ 数据组与「关于」组按页序渲染
          // （docs/21 §5.6；不接时这两组整块自门控不画）。
          home: SettingsPage(
            settingsStore: _Store(),
            // P1（2026-10-16）：「头像和昵称不要能点击跳转，就在后边的编辑资料
            // 按钮点击就好了」——头像/昵称已不可点，**编辑资料按钮是这段唯一的
            // 入口**。夹具不接 `onOpenProfileEdit` 时那个按钮根本不渲染，帧里
            // 看不到 P1 的落点（第一版就是这样：帧上只有头像+昵称）。
            onOpenProfileEdit: () {},
            profileIdentityRepository: ProfileIdentityRepository(
              database: database,
            ),
            // Round7 裁决 R5：体型记录只读弹层的帧要用真仓储。
            measurementRepository: measurements,
            createEncryptedBackup: CreateEncryptedBackup(
              database: database,
              fileStore: _MemoryFileStore(),
            ),
            restoreEncryptedBackup: RestoreEncryptedBackup(
              database: database,
              fileStore: _MemoryFileStore(),
            ),
            clearAllLocalData: ClearAllLocalData(database),
            exportCsvFiles: ExportCsvFiles(
              database: database,
              fileStore: _MemoryFileStore(),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  testWidgets('我的（设置页）：四个分组（6 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    for (final (dark, width, height, scale, name) in [
      (false, 360.0, 900.0, 1.0, 'settings-top-light-360-1.0'),
      (true, 360.0, 900.0, 1.0, 'settings-top-dark-360-1.0'),
      (false, 320.0, 900.0, 2.0, 'settings-top-light-320-2.0'),
    ]) {
      await pumpSettings(
        tester,
        dark: dark,
        width: width,
        height: height,
        scale: scale,
      );
      // 顶段哨兵用**身份卡**（页序：身份卡 → 健康指标 → 成就 → AI 配置 → 数据…）
      // ——AI 组在 320-2.0× 下已滚出视口、懒构建里不存在。
      await shot(tester, name, const Key('settings-identity-card'));
    }

    // 数据组（备份/恢复/导出/自动备份）
    await pumpSettings(tester, dark: false, width: 360, height: 900, scale: 1);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-group-data')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 60));
    await shot(
      tester,
      'settings-data-light-360-1.0',
      const Key('cta-export-csv'),
    );

    // 关于 + 清空数据（末段）
    await tester.scrollUntilVisible(
      find.byKey(const Key('cta-clear-data')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 60));
    await shot(
      tester,
      'settings-about-light-360-1.0',
      const Key('cta-clear-data'),
    );

    // 「体重记录」只读弹层（Round7 裁决 R5）：身份卡「当前体重」→ 弹层。
    await pumpSettings(tester, dark: false, width: 360, height: 900, scale: 1);
    await tester.tap(find.byKey(const Key('settings-stat-weight-open')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await shot(
      tester,
      'settings-weight-history-light-360-1.0',
      const Key('weight-history-sheet'),
    );
    await tester.tapAt(const Offset(180, 40)); // 点弹层外关闭
    await tester.pump(const Duration(milliseconds: 200));

    // 430 + 1.5× 暗色
    await pumpSettings(
      tester,
      dark: true,
      width: 430,
      height: 1000,
      scale: 1.5,
    );
    await shot(
      tester,
      'settings-top-dark-430-1.5',
      const Key('settings-identity-card'),
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();

    // drift 的 `QueryStream` 取消会留一个 `Duration.zero` 定时器
    // （`StreamQueryStore.markAsClosed`）：本轮身份卡接了真仓储
    // （`watchIdentity`），不显式卸载会在框架期末报 pending timer
    // （`profile_edit_route_test.dart:96` 同一口径）。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _Store implements AiProviderSettingsStore {
  @override
  Future<AiProviderSettings> load() async =>
      const AiProviderSettings(configuration: null, hasApiKey: false);

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => null;

  @override
  Future<void> save(AiProviderSettingsInput input) async {}

  @override
  Future<void> clearApiKey() async {}
}

final class _MemoryFileStore implements BackupFileStore {
  @override
  Future<String?> saveExport({
    required String defaultFileName,
    required Uint8List bytes,
  }) async => defaultFileName;

  @override
  Future<Uint8List?> pickRestoreFile() async => null;
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'cap-${_value++}';
}
