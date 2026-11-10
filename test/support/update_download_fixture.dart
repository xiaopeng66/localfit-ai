import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/settings/application/app_update_service.dart';

/// 只替换网络字节源和系统安装器：服务、写盘、进度与弹层仍走生产代码。
class UpdateDownloadFixture implements HttpClientAdapter {
  UpdateDownloadFixture({this.contentLength = 4 * 1024 * 1024}) {
    directory = Directory.systemTemp.createTempSync('localfit-update-sheet-');
    dio = Dio()..httpClientAdapter = this;
    service = AppUpdateService(dio: dio, supportDir: () async => directory);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          if (call.method == 'deviceInfo') {
            return <Object?, Object?>{
              'model': 'Update Test Device',
              'androidVersion': '15',
              'sdkInt': 35,
              'versionCode': 6073,
              'abi': 'x86_64',
            };
          }
          if (call.method == 'installApk') {
            installedPaths.add((call.arguments as Map)['path'] as String);
            return await (installerGate?.future ??
                Future.value(installOutcome));
          }
          return null;
        });
  }

  static const _channel = MethodChannel('localfit/platform');
  static const asset = AppReleaseAsset(
    name: 'LocalFitAI-vc6074-x86_64.apk',
    downloadUrl: 'https://example.com/LocalFitAI-vc6074-x86_64.apk',
    sizeBytes: 4 * 1024 * 1024,
  );

  final int? contentLength;
  final chunks = StreamController<Uint8List>();
  final installedPaths = <String>[];
  late final Directory directory;
  late final Dio dio;
  late final AppUpdateService service;
  Completer<String>? installerGate;
  String installOutcome = 'started';
  int requests = 0;

  File get file => File('${directory.path}/updates/${asset.name}');

  bool get downloadFilesCleared {
    final updates = Directory('${directory.path}/updates');
    return !updates.existsSync() || updates.listSync().isEmpty;
  }

  void sendBytes(int count) => chunks.add(Uint8List(count));

  void finish() => unawaited(chunks.close());

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody(
      chunks.stream,
      200,
      headers: {
        if (contentLength != null)
          Headers.contentLengthHeader: ['$contentLength'],
      },
    );
  }

  @override
  void close({bool force = false}) {
    if (!chunks.isClosed) unawaited(chunks.close());
  }

  Future<void> dispose() async {
    final gate = installerGate;
    if (gate != null && !gate.isCompleted) gate.complete('failed');
    dio.close(force: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

/// 文件写入在真实事件循环里完成；不对仍在转动的不确定进度条 pumpAndSettle。
Future<void> pumpDownloadUntil(
  WidgetTester tester,
  bool Function() ready, {
  String reason = '下载状态未及时更新',
}) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
  expect(ready(), isTrue, reason: reason);
}
