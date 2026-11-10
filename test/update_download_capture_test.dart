@Tags(['capture'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/features/settings/application/app_update_service.dart';
import 'package:localfit_ai/features/settings/presentation/update_download_sheet.dart';

import 'support/round7_render.dart';
import 'support/update_download_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (name, width, scale, dark, unknown, handoff) in [
    ('progress-25-light', 412.0, 1.0, false, false, false),
    ('progress-25-dark', 412.0, 1.0, true, false, false),
    ('progress-25-320x2', 320.0, 2.0, false, false, false),
    ('unknown-total', 412.0, 1.0, false, true, false),
    ('installer-handoff', 412.0, 1.0, false, true, true),
  ]) {
    testWidgets(name, (tester) async {
      await tester.runAsync(loadRound7Fonts);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 780);
      addTearDown(tester.view.reset);
      final download = UpdateDownloadFixture(
        contentLength: unknown ? null : 4 * 1024 * 1024,
      );
      addTearDown(download.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
      });
      if (handoff) download.installerGate = Completer<String>();
      final asset = unknown
          ? const AppReleaseAsset(
              name: 'LocalFitAI-vc6074-x86_64.apk',
              downloadUrl: 'https://example.com/LocalFitAI-vc6074-x86_64.apk',
            )
          : UpdateDownloadFixture.asset;
      await tester.pumpWidget(
        RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(
              dark ? AppTheme.dark() : AppTheme.light(),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('关于与帮助')),
                body: Padding(
                  padding: const EdgeInsets.all(LfDimens.pagePadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('LocalFit AI', style: LfText.headline),
                      const SizedBox(height: LfDimens.spaceLarge),
                      ListTile(
                        leading: const Icon(Icons.system_update_outlined),
                        title: const Text('检查更新'),
                        onTap: () => showUpdateDownloadSheet(
                          context,
                          service: download.service,
                          asset: asset,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('检查更新'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      download.sendBytes(1024 * 1024);
      if (handoff) download.finish();
      await pumpDownloadUntil(
        tester,
        () => handoff
            ? find.text('100%').evaluate().isNotEmpty
            : find.textContaining('已下载 1.0 MB').evaluate().isNotEmpty,
      );
      expect(find.byKey(const Key('update-download-sheet')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureRound7(tester, name);
      if (handoff) {
        download.installerGate!.complete('started');
      } else {
        await tester.tap(find.byKey(const Key('update-download-cancel')));
      }
      await pumpDownloadUntil(
        tester,
        () => find.byKey(const Key('update-download-sheet')).evaluate().isEmpty,
      );
      if (!handoff) {
        await pumpDownloadUntil(tester, () => download.downloadFilesCleared);
      }
    });
  }
}
