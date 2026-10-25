import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/onboarding/presentation/onboarding_page.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/presentation/profile_edit_page.dart';

import 'support/round7_render.dart';

/// Round7 阶段 6 余下两页的渲染矩阵：**引导页**（建档）与**资料编辑页**。
///
/// 6 帧：引导页浅/深 360-1.0、引导页浅 320-2.0×、资料编辑浅 360-1.0、
/// 资料编辑浅 320-2.0×、资料编辑深 430-1.5×。
///
/// 两页的 A 事实：引导页按 docs/32 §4 T15 收官形态（阶段条 4×24×4 + 分组卡 +
/// 性别分段 + 安全筛查 + 固定主行动 h48）；资料编辑按 docs/21 §5.6 的身份/目标
/// 编辑族。本批用于核对本轮 ㉓（emoji → 图标）后的实际渲染与深浅/大字。
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  Future<void> pumpTree(
    WidgetTester tester,
    Widget page, {
    required bool dark,
    double width = 360,
    double height = 900,
    double scale = 1,
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
          home: page,
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

  testWidgets('引导页（建档）：浅/深 360 + 浅 320-2.0×（3 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    for (final (dark, width, height, scale, name) in [
      (false, 360.0, 900.0, 1.0, 'onboarding-light-360-1.0'),
      (true, 360.0, 900.0, 1.0, 'onboarding-dark-360-1.0'),
      (false, 320.0, 900.0, 2.0, 'onboarding-light-320-2.0'),
    ]) {
      await pumpTree(
        tester,
        OnboardingPage(
          completeOnboarding: (input) async => throw UnimplementedError(),
        ),
        dark: dark,
        width: width,
        height: height,
        scale: scale,
      );
      await shot(tester, name, const Key('onboarding-progress'));
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });

  testWidgets('资料编辑：浅 360/320-2.0× + 深 430-1.5×（3 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    final repository = ProfileIdentityRepository(database: database);

    for (final (dark, width, height, scale, name) in [
      (false, 360.0, 900.0, 1.0, 'profile-edit-light-360-1.0'),
      (false, 320.0, 900.0, 2.0, 'profile-edit-light-320-2.0'),
      (true, 430.0, 1000.0, 1.5, 'profile-edit-dark-430-1.5'),
    ]) {
      await pumpTree(
        tester,
        ProfileEditPage(
          repository: repository,
          currentGoal: null,
          onClose: () {},
          now: DateTime(2026, 10, 15),
        ),
        dark: dark,
        width: width,
        height: height,
        scale: scale,
      );
      expect(tester.takeException(), isNull, reason: '$name：布局溢出');
      await captureRound7(tester, name);
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}
