import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/features/settings/application/app_update_service.dart';
import 'package:localfit_ai/features/settings/presentation/update_download_sheet.dart';

import '../../support/update_download_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mib = 1024 * 1024;

  Future<UpdateDownloadFixture> fixture(
    WidgetTester tester, {
    int? contentLength = 4 * mib,
  }) async {
    final value = UpdateDownloadFixture(contentLength: contentLength);
    addTearDown(value.dispose);
    return value;
  }

  Future<void> cancelAndWait(
    WidgetTester tester,
    UpdateDownloadFixture download,
    _SheetResult result,
  ) async {
    await tester.tap(find.byKey(const Key('update-download-cancel')));
    await pumpDownloadUntil(tester, () => result.completed);
    await pumpDownloadUntil(tester, () => download.downloadFilesCleared);
    await tester.pump(const Duration(milliseconds: 300));
    expect(result.value?.kind, AppUpdateInstallKind.cancelled);
    expect(download.installedPaths, isEmpty);
    expect(tester.takeException(), isNull);
  }

  testWidgets('下载分块会刷新进度条、百分比和字节，不重新发起下载', (tester) async {
    final download = await fixture(tester);
    final result = await _openSheet(tester, download);
    expect(find.byKey(const Key('update-download-sheet')), findsOneWidget);
    expect(find.byKey(const Key('update-download-phase')), findsOneWidget);
    expect(find.byKey(const Key('update-download-bytes')), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);

    download.sendBytes(mib);
    await pumpDownloadUntil(
      tester,
      () => find.text('25%').evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<LfProgressBar>(
            find.byKey(const Key('update-download-progress')),
          )
          .value,
      0.25,
    );
    expect(find.text('已下载 1.0 MB / 共 4.0 MB'), findsOneWidget);
    final progressSemantics = tester.getSemantics(
      find.byKey(const Key('update-download-progress')),
    );
    expect(progressSemantics.label, '下载进度');
    expect(progressSemantics.value, '25%');

    download.sendBytes(mib);
    await pumpDownloadUntil(
      tester,
      () => find.text('50%').evaluate().isNotEmpty,
    );
    expect(
      tester
          .widget<LfProgressBar>(
            find.byKey(const Key('update-download-progress')),
          )
          .value,
      0.5,
    );
    expect(find.text('已下载 2.0 MB / 共 4.0 MB'), findsOneWidget);
    expect(download.requests, 1, reason: '进度重建不能重新下载');
    await cancelAndWait(tester, download, result);
  });

  testWidgets('两处都没有总大小时只显示已下载字节，不显示假百分比', (tester) async {
    final download = await fixture(tester, contentLength: null);
    final result = await _openSheet(
      tester,
      download,
      asset: const AppReleaseAsset(
        name: 'LocalFitAI-vc6074-x86_64.apk',
        downloadUrl: 'https://example.com/LocalFitAI-vc6074-x86_64.apk',
      ),
    );
    download.sendBytes(mib);
    await pumpDownloadUntil(
      tester,
      () => find.textContaining('已下载 1.0 MB').evaluate().isNotEmpty,
    );
    expect(find.byKey(const Key('update-download-percent')), findsNothing);
    expect(find.byType(LfProgressBar), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('总大小'), findsOneWidget);
    await cancelAndWait(tester, download, result);
  });

  testWidgets('响应长度未知时发布清单的大小仍能提供实际百分比', (tester) async {
    final download = await fixture(tester, contentLength: null);
    final result = await _openSheet(tester, download);
    download.sendBytes(mib);
    await pumpDownloadUntil(
      tester,
      () => find.text('25%').evaluate().isNotEmpty,
    );
    expect(find.text('已下载 1.0 MB / 共 4.0 MB'), findsOneWidget);
    await cancelAndWait(tester, download, result);
  });

  testWidgets('服务端长度优先于旧发布清单，未满的进度不能四舍五入成 100%', (tester) async {
    final download = await fixture(tester, contentLength: 1000);
    final result = await _openSheet(tester, download);
    download.sendBytes(996);
    await pumpDownloadUntil(
      tester,
      () => find.text('99%').evaluate().isNotEmpty,
    );
    expect(find.text('99%'), findsOneWidget);
    expect(find.text('100%'), findsNothing, reason: '仍缺字节时不能显示下载完成');
    await cancelAndWait(tester, download, result);
  });

  testWidgets('点遮罩即取消，在退场动画里下载结束也不能二次 pop 或打开安装器', (tester) async {
    final download = await fixture(tester);
    final result = await _openSheet(tester, download);
    download.sendBytes(mib);
    await pumpDownloadUntil(
      tester,
      () => find.text('25%').evaluate().isNotEmpty,
    );

    await tester.tapAt(const Offset(20, 20));
    // 不推进退场动画：此时 State 还 mounted，正是只靠 dispose 会漏掉的空窗。
    download.sendBytes(3 * mib);
    download.finish();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    expect(download.installedPaths, isEmpty, reason: '关闭弹层后不能偷偷打开系统安装');
    await tester.pump(const Duration(milliseconds: 300));
    await pumpDownloadUntil(tester, () => download.downloadFilesCleared);
    expect(find.text('open update'), findsOneWidget, reason: '不能顺手把宿主页 pop 掉');
    expect(result.completed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('系统返回会中止未完成的下载且不影响宿主页', (tester) async {
    final download = await fixture(tester);
    final result = await _openSheet(tester, download);
    download.sendBytes(mib);
    await pumpDownloadUntil(
      tester,
      () => find.text('25%').evaluate().isNotEmpty,
    );
    await tester.binding.handlePopRoute();
    await pumpDownloadUntil(tester, () => result.completed);
    await pumpDownloadUntil(tester, () => download.downloadFilesCleared);
    await tester.pump(const Duration(milliseconds: 300));
    expect(download.installedPaths, isEmpty);
    expect(find.text('open update'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('宿主销毁时取消网络流，后续回调不会 setState 或打开安装器', (tester) async {
    final download = await fixture(tester);
    await _openSheet(tester, download);
    download.sendBytes(mib);
    await pumpDownloadUntil(
      tester,
      () => find.text('25%').evaluate().isNotEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpDownloadUntil(tester, () => download.downloadFilesCleared);
    expect(download.installedPaths, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('交接阶段才显示完成；交接中返回键不能谎报取消', (tester) async {
    final download = await fixture(tester, contentLength: null);
    download.installerGate = Completer<String>();
    final result = await _openSheet(
      tester,
      download,
      asset: const AppReleaseAsset(
        name: 'LocalFitAI-vc6074-x86_64.apk',
        downloadUrl: 'https://example.com/LocalFitAI-vc6074-x86_64.apk',
      ),
    );
    download.sendBytes(mib);
    download.finish();
    await pumpDownloadUntil(tester, () => download.installedPaths.isNotEmpty);
    expect(find.textContaining('下载完成'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget, reason: '未知长度也必须在文件落盘后结束下载态');
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('update-download-cancel')))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));
    expect(result.completed, isFalse, reason: '安装器交接已经发生，不能再称为取消下载');
    download.installerGate!.complete('started');
    await pumpDownloadUntil(tester, () => result.completed);
    await tester.pump(const Duration(milliseconds: 300));
    expect(result.value?.kind, AppUpdateInstallKind.installerOpened);
    expect(download.file.existsSync(), isTrue, reason: '安装器仍需要完整 APK');
    expect(tester.takeException(), isNull);
  });

  testWidgets('安装交接时即使路由被移除，也返回安装器的真实结果而不是取消', (tester) async {
    final download = await fixture(tester);
    download.installerGate = Completer<String>();
    final result = await _openSheet(tester, download);
    download.sendBytes(4 * mib);
    download.finish();
    await pumpDownloadUntil(tester, () => download.installedPaths.isNotEmpty);
    // 把手关闭/外层导航可能直接 pop，不经过 maybePop 的 canPop 守卫。
    result.root.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 300));
    download.installerGate!.complete('started');
    await pumpDownloadUntil(tester, () => result.completed);
    expect(result.value?.kind, AppUpdateInstallKind.installerOpened);
    expect(download.file.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('下载流报错返回失败，不打开安装器且删掉残片', (tester) async {
    final download = await fixture(tester);
    final result = await _openSheet(tester, download);
    download.sendBytes(mib);
    await pumpDownloadUntil(
      tester,
      () => find.text('25%').evaluate().isNotEmpty,
    );
    download.chunks.addError(StateError('断网'));
    await pumpDownloadUntil(tester, () => result.completed);
    await pumpDownloadUntil(tester, () => download.downloadFilesCleared);
    await tester.pump(const Duration(milliseconds: 300));
    expect(result.value?.kind, AppUpdateInstallKind.failed);
    expect(result.value?.message, contains('下载失败'));
    expect(download.installedPaths, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('嵌套导航器上弹层走根导航器，取消不影响内页', (tester) async {
    final download = await fixture(tester);
    final result = await _openSheet(tester, download, nestedNavigator: true);
    expect(result.root.currentState!.canPop(), isTrue);
    expect(result.inner.currentState!.canPop(), isFalse);
    download.sendBytes(mib);
    await pumpDownloadUntil(
      tester,
      () => find.text('25%').evaluate().isNotEmpty,
    );
    await cancelAndWait(tester, download, result);
    expect(result.root.currentState!.canPop(), isFalse);
    expect(find.text('open update'), findsOneWidget);
  });

  testWidgets('320dp×2.0×短屏：下载信息可滚动，取消按钮可达且不溢出', (tester) async {
    final download = await fixture(tester);
    final result = await _openSheet(
      tester,
      download,
      size: const Size(320, 480),
      scale: 2,
    );
    download.sendBytes(mib);
    await pumpDownloadUntil(
      tester,
      () => find.text('25%').evaluate().isNotEmpty,
    );
    expect(tester.takeException(), isNull, reason: '进度弹层必须适配窄屏与大字号');
    await tester.ensureVisible(find.byKey(const Key('update-download-cancel')));
    await cancelAndWait(tester, download, result);
  });
}

class _SheetResult {
  final root = GlobalKey<NavigatorState>();
  final inner = GlobalKey<NavigatorState>();
  bool completed = false;
  AppUpdateInstallResult? value;
}

Future<_SheetResult> _openSheet(
  WidgetTester tester,
  UpdateDownloadFixture download, {
  AppReleaseAsset asset = UpdateDownloadFixture.asset,
  bool nestedNavigator = false,
  Size size = const Size(412, 892),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
  });
  final result = _SheetResult();
  final page = Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            result.value = await showUpdateDownloadSheet(
              context,
              service: download.service,
              asset: asset,
            );
            result.completed = true;
          },
          child: const Text('open update'),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: result.root,
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: nestedNavigator
          ? Navigator(
              key: result.inner,
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => page),
            )
          : page,
    ),
  );
  await tester.tap(find.text('open update'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await pumpDownloadUntil(tester, () => download.requests == 1);
  return result;
}
