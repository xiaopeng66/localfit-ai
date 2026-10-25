import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

import 'support/round7_render.dart';

/// Round7 阶段 6 末批：**AI 配置弹层**（docs/29 §P4 需求 6 的四项收进同一弹层）
/// 与设置页里已接依赖时的数据组。
///
/// 4 帧：AI 配置弹层 浅/深 360-1.0 + 浅 320-2.0×、未配置态的 AI 行（浅 360-1.0）。
void main() {
  Future<void> pumpSettings(
    WidgetTester tester, {
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
          home: SettingsPage(settingsStore: _Store()),
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

  testWidgets('AI 配置弹层（浅/深 360 + 浅 320-2.0×）+ 未配置行（4 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    // 未配置态的页面段（AI 行显示「未配置」）
    await pumpSettings(tester, dark: false);
    // 页头加入后（Round7 逐页对账第一批）AI 行落在 900 高视口之外：
    // 懒建列表先把它滚进帧内再拍（与本文件下面对齐——判据只要求
    // 「AI 行在帧内」，不钉它的滚动位置）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-ai-model-row')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const Key('settings-ai-model-row')));
    await tester.pump(const Duration(milliseconds: 120));
    await shot(
      tester,
      'settings-ai-row-light-360-1.0',
      const Key('settings-ai-model-row'),
    );

    for (final (dark, width, height, scale, name) in [
      (false, 360.0, 900.0, 1.0, 'ai-config-sheet-light-360-1.0'),
      (true, 360.0, 900.0, 1.0, 'ai-config-sheet-dark-360-1.0'),
      (false, 320.0, 900.0, 2.0, 'ai-config-sheet-light-320-2.0'),
    ]) {
      await pumpSettings(
        tester,
        dark: dark,
        width: width,
        height: height,
        scale: scale,
      );
      // 懒建列表：先滚到 AI 行再点（320-2.0× 下它在视口外）。
      await tester.scrollUntilVisible(
        find.byKey(const Key('settings-ai-model-row')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(const Key('settings-ai-model-row')),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byKey(const Key('settings-ai-model-row')));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(
        find.byKey(const Key('ai-api-key')),
        findsOneWidget,
        reason: '$name：AI 配置弹层（API Key 字段）',
      );
      await captureRound7(tester, name);
      // 弹层内容比一屏长：再拍一帧滚到底的保存行。
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      if (find.byKey(const Key('ai-config-sheet-save')).evaluate().isNotEmpty) {
        await captureRound7(tester, '$name-bottom');
      }
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
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
