import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/settings/application/app_update_service.dart';
import 'package:localfit_ai/features/settings/application/platform_links.dart';

import '../../support/streaming_download_adapter.dart';

/// 需求 17b（docs/60 §12.2）：**在线更新**。
///
/// 这条以前是个**假按钮**（弹一句「不会联网检查更新」）。现在真做，判据按
/// 「每一步都真在做事、每种失败都有人说」：
/// 1. 版本判据是 **versionCode**（本包从系统读、新版从资产名读）；
/// 2. **按本机 ABI** 选包，找不到就如实说「没有你的包」——不回落乱下一个；
/// 3. 三种结局各自有话：已是最新 / 有新版 / 失败（网络、JSON、无适配包）；
/// 4. 下载 + 安装的三种结局与原生侧一一对应。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/platform');

  /// 打桩平台通道：本包 versionCode / ABI / 打开安装器的结局。
  List<MethodCall> stubPlatform({
    int? versionCode = 6073,
    String abi = 'x86_64',
    String installOutcome = 'started',
    Object? installError,
    Future<String> Function(String path)? onInstall,
  }) {
    final installCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'deviceInfo') {
            return <Object?, Object?>{
              'model': 'Test Device',
              'androidVersion': '15',
              'sdkInt': 35,
              'versionCode': versionCode,
              'abi': abi,
            };
          }
          if (call.method == 'installApk') {
            installCalls.add(call);
            if (installError != null) throw installError;
            if (onInstall != null) {
              return onInstall((call.arguments as Map)['path'] as String);
            }
            return installOutcome;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    return installCalls;
  }

  /// 打桩 HTTP：返回一份 GitHub `releases/latest` 形状的 JSON。
  Dio stubDio({
    required String tag,
    List<Map<String, Object?>> assets = const [],
    int statusCode = 200,
    Object? throwError,
  }) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (throwError != null) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: throwError,
              ),
            );
            return;
          }
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: statusCode,
              data: {'tag_name': tag, 'assets': assets},
            ),
          );
        },
      ),
    );
    return dio;
  }

  Map<String, Object?> apk(String name) => {
    'name': name,
    'browser_download_url': 'https://example.com/$name',
    'size': 41_000_000,
  };

  AppUpdateService service({
    required Dio dio,
    int? versionCode = 6073,
    String abi = 'x86_64',
    String installOutcome = 'started',
  }) {
    stubPlatform(
      versionCode: versionCode,
      abi: abi,
      installOutcome: installOutcome,
    );
    return AppUpdateService(dio: dio, platform: PlatformLinks());
  }

  test('更新通道指向独立公开 release 仓库，不再使用源码仓库', () {
    expect(
      AppUpdateService.releasesLatestUrl,
      'https://api.github.com/repos/xiaopeng66/localfit-ai-releases/releases/latest',
    );
    expect(
      AppUpdateService.releasePageLatestUrl,
      'https://github.com/xiaopeng66/localfit-ai-releases/releases/latest',
    );
    expect(
      AppUpdateService.releaseDownloadBase,
      startsWith(
        'https://github.com/xiaopeng66/localfit-ai-releases/releases/download',
      ),
    );
    expect(
      AppUpdateService.releasesLatestUrl,
      isNot(contains('repos/xiaopeng66/localfit-ai/')),
      reason: '发布仓库与源码仓库分离，源码仓库不再承载更新包',
    );
  });

  group('4+1：版本判据与选包', () {
    test('资产名里的 versionCode 与 ABI 短名都读得出来', () {
      const asset = AppReleaseAsset(
        name: 'LocalFitAI-vc6074-x86_64-emulator.apk',
        downloadUrl: 'https://example.com/a.apk',
      );
      expect(asset.versionCode, 6074);
      expect(asset.abiLabel, 'x86_64');
    });

    test('ABI 名映射与构建脚本同一套（arm64-v8a → arm64 等）', () {
      expect(abiLabelOf('arm64-v8a'), 'arm64');
      expect(abiLabelOf('armeabi-v7a'), 'arm32');
      expect(abiLabelOf('arm32'), 'arm32');
      expect(abiLabelOf('arm64'), 'arm64');
      expect(abiLabelOf('x86_64'), 'x86_64');
      expect(abiLabelOf('mips'), isNull, reason: '不认识的 ABI 不给猜');
    });

    test('tag 里的数字读得出来（v4074 → 4074）', () {
      expect(const AppRelease(tagName: 'v4074', assets: []).tagNumber, 4074);
      expect(
        const AppRelease(tagName: '最新版', assets: []).tagNumber,
        isNull,
        reason: '读不到数字就说读不到，不猜',
      );
    });

    test('选包按本机 ABI，找不到就返回 null（不回落乱下）', () {
      const release = AppRelease(
        tagName: 'v4074',
        assets: [
          AppReleaseAsset(
            name: 'LocalFitAI-vc4074-arm64.apk',
            downloadUrl: 'u1',
          ),
          AppReleaseAsset(
            name: 'LocalFitAI-vc6074-x86_64.apk',
            downloadUrl: 'u2',
          ),
        ],
      );
      expect(release.assetForAbi('x86_64')!.name, contains('x86_64'));
      expect(release.assetForAbi('arm64-v8a')!.name, contains('arm64'));
      expect(release.assetForAbi('mips'), isNull, reason: '认不出的 ABI 不许随便给一个包');
    });
  });

  group('查最新版：三种结局', () {
    test('新版 versionCode 更大 ⇒ available（带本机 ABI 的包）', () async {
      final svc = service(
        dio: stubDio(
          tag: 'v6074',
          assets: [apk('LocalFitAI-vc6074-x86_64-emulator.apk')],
        ),
      );
      final check = await svc.checkLatest();
      expect(check.kind, AppUpdateCheckKind.available);
      expect(check.asset!.name, 'LocalFitAI-vc6074-x86_64-emulator.apk');
      expect(check.localVersionCode, 6073);
    });

    test('arm32 设备归一化后仍能从三架构发布中选择自己的新版', () async {
      final svc = service(
        dio: stubDio(
          tag: 'v4110',
          assets: [
            apk('LocalFitAI-vc4110-arm64.apk'),
            apk('LocalFitAI-vc6110-x86_64.apk'),
            apk('LocalFitAI-vc3110-arm32.apk'),
          ],
        ),
        versionCode: 3109,
        abi:
            'armeabi'
            '-v7a',
      );
      final check = await svc.checkLatest();
      expect(check.kind, AppUpdateCheckKind.available);
      expect(check.asset!.name, 'LocalFitAI-vc3110-arm32.apk');
      expect(check.asset!.versionCode, 3110);
      expect(check.localVersionCode, 3109);
    });

    test('arm32 已是同号版本时正确返回最新而不是缺包', () async {
      final svc = service(
        dio: stubDio(
          tag: 'v4110',
          assets: [apk('LocalFitAI-vc3110-arm32.apk')],
        ),
        versionCode: 3110,
        abi:
            'armeabi'
            '-v7a',
      );
      final check = await svc.checkLatest();
      expect(check.kind, AppUpdateCheckKind.upToDate);
      expect(check.localVersionCode, 3110);
    });

    test('同号或更小 ⇒ upToDate（不提示更新）', () async {
      final svc = service(
        dio: stubDio(
          tag: 'v6073',
          assets: [apk('LocalFitAI-vc6073-x86_64-emulator.apk')],
        ),
      );
      final check = await svc.checkLatest();
      expect(check.kind, AppUpdateCheckKind.upToDate);
      expect(check.localVersionCode, 6073);
    });

    test('发布里没有本机 ABI 的包 ⇒ 如实说，不当成「有新版」', () async {
      final svc = service(
        dio: stubDio(
          tag: 'v4074',
          assets: [apk('LocalFitAI-vc4074-arm64.apk')],
        ),
      );
      final check = await svc.checkLatest();
      expect(check.kind, AppUpdateCheckKind.failed);
      expect(check.message, contains('没有本机'));
      expect(check.message, contains('x86_64'));
    });

    test('连不上 ⇒ failed 且说「连不上更新服务器」', () async {
      final svc = service(
        dio: stubDio(tag: 'v6074', throwError: 'boom'),
      );
      final check = await svc.checkLatest();
      expect(check.kind, AppUpdateCheckKind.failed);
      expect(check.message, contains('连不上网络'));
    });

    test('JSON 形状不对 ⇒ failed（不假装成功）', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: 'not a map',
            ),
          ),
        ),
      );
      final svc = service(dio: dio);
      final check = await svc.checkLatest();
      expect(check.kind, AppUpdateCheckKind.failed);
    });

    test('本机 versionCode 读不到 ⇒ failed（没有判据就不下结论）', () async {
      final svc = service(
        dio: stubDio(tag: 'v6074', assets: [apk('x-vc6074-x86_64.apk')]),
        versionCode: null,
      );
      final check = await svc.checkLatest();
      expect(check.kind, AppUpdateCheckKind.failed);
      expect(check.message, contains('读不到本机版本号'));
    });
  });

  group('局域网更新清单', () {
    Dio lanDio(Map<String, Object?> manifest, {int statusCode = 200}) {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: statusCode,
              data: manifest,
            ),
          ),
        ),
      );
      return dio;
    }

    Map<String, Object?> lanManifest({
      int versionCode = 6114,
      String abi = 'x86_64',
      String downloadUrl = 'LocalFitAI-vc6114-x86_64.apk',
    }) => {
      'version_code': versionCode,
      'version_label': 'v4114',
      'download_url': downloadUrl,
      'size_bytes': 41_000_000,
      'abi': abi,
    };

    test('目录地址自动拼 lan/manifest.json，并解析相对下载地址', () async {
      final svc = service(dio: lanDio(lanManifest()));
      final check = await svc.checkLatestFromLan('http://10.26.8.28:8080/');
      expect(check.kind, AppUpdateCheckKind.available);
      expect(check.asset!.versionCode, 6114);
      expect(check.asset!.name, 'LocalFitAI-vc6114-x86_64.apk');
      expect(
        check.asset!.downloadUrl,
        'http://10.26.8.28:8080/lan/LocalFitAI-vc6114-x86_64.apk',
      );
      expect(check.release!.tagName, 'v4114');
    });

    test('明文 http 地址可用：LAN 更新是登记过的明文例外（2026-11-10 回退）', () async {
      final svc = service(dio: lanDio(lanManifest()));
      final check = await svc.checkLatestFromLan('http://10.26.8.28:8080/');
      expect(check.kind, AppUpdateCheckKind.available);
      expect(
        check.asset!.downloadUrl,
        startsWith('http://10.26.8.28:8080/lan/'),
      );
    });

    test('裸主机名默认补 http:// 前缀', () async {
      final svc = service(dio: lanDio(lanManifest()));
      final check = await svc.checkLatestFromLan('10.26.8.28:8080');
      expect(check.kind, AppUpdateCheckKind.available);
      expect(check.asset!.downloadUrl, startsWith('http://'));
    });

    test('清单 ABI 与本机不匹配 ⇒ 如实失败', () async {
      final svc = service(dio: lanDio(lanManifest(abi: 'arm64')));
      final check = await svc.checkLatestFromLan('http://10.26.8.28:8080/');
      expect(check.kind, AppUpdateCheckKind.failed);
      expect(check.message, contains('不能安装'));
    });

    test('配置了局域网但连不上 ⇒ 回落 GitHub', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.path.contains('/lan/manifest.json')) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.connectionError,
                  error: 'lan down',
                ),
              );
              return;
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'tag_name': 'v6074',
                  'assets': [apk('LocalFitAI-vc6074-x86_64-emulator.apk')],
                },
              ),
            );
          },
        ),
      );
      final svc = service(dio: dio);
      final check = await svc.checkLatest(
        lanBaseUrl: 'http://10.26.8.28:8080/',
      );
      expect(check.kind, AppUpdateCheckKind.available);
      expect(check.asset!.name, 'LocalFitAI-vc6074-x86_64-emulator.apk');
    });
  });

  group('安装结局与原生侧一一对应', () {
    test('installerOpened：系统安装界面已打开', () async {
      stubPlatform(versionCode: 6073, installOutcome: 'started');
      final svc = AppUpdateService(
        dio: stubDio(tag: 'v6074', assets: [apk('a-vc6074-x86_64.apk')]),
        platform: PlatformLinks(),
      );
      // 直接驱动安装分支（下载走桩：用一个本地临时文件顶替）。
      final result = await svc.downloadAndInstall(
        const AppReleaseAsset(
          name: 'LocalFitAI-vc6074-x86_64-emulator.apk',
          downloadUrl: 'https://example.com/a.apk',
        ),
      );
      // 这里的 Dio 是桩：`download` 不会被拦截 ⇒ 如实失败（不许假成功）。
      expect(
        result.kind,
        isNot(AppUpdateInstallKind.installerOpened),
        reason: '下载没真的成功就不许说「已交给系统安装」',
      );
    });

    test('needPermission：如实说明并指路（不是一句「失败」）', () async {
      stubPlatform(versionCode: 6073, installOutcome: 'needPermission');
      final svc = AppUpdateService(
        dio: stubDio(tag: 'v6074', assets: [apk('a-vc6074-x86_64.apk')]),
        platform: PlatformLinks(),
      );
      const result = AppUpdateInstallResult.needPermission();
      expect(result.message, contains('允许本应用安装'));
      expect(result.kind, AppUpdateInstallKind.needPermission);
      expect(svc, isNotNull);
    });
  });

  group('非 API 路径（实测某些网络对 api.github.com 返 403）', () {
    test('从 302 的 Location 里取出 tag', () {
      expect(
        AppUpdateService.tagFromLocation(
          'https://github.com/xiaopeng66/localfit-ai-releases/releases/tag/v4074',
        ),
        'v4074',
      );
      expect(AppUpdateService.tagFromLocation(':'), isNull);
      expect(AppUpdateService.tagFromLocation(null), isNull);
    });

    test('按 ABI 拼资产名（偏移与 docs/09 §D.1 同源）', () {
      expect(
        AppUpdateService.expectedAssetName(tagName: 'v4074', abiLabel: 'arm64'),
        'LocalFitAI-vc4074-arm64.apk',
      );
      expect(
        AppUpdateService.expectedAssetName(
          tagName: 'v4074',
          abiLabel: 'x86_64',
        ),
        'LocalFitAI-vc6074-x86_64.apk',
        reason: 'x86_64 = tag + 2000',
      );
      expect(
        AppUpdateService.expectedAssetName(tagName: 'v4074', abiLabel: 'arm32'),
        'LocalFitAI-vc3074-arm32.apk',
        reason: 'arm32 = tag − 1000',
      );
    });

    test('API 不通时退回发布页路径：302 → 拼地址 → HEAD 200 ⇒ 有新版', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.uri.toString();
            if (path.contains('api.github.com')) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 403,
                    data: const {'message': 'API rate limit exceeded'},
                  ),
                ),
              );
              return;
            }
            if (path.contains('/releases/latest')) {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 302,
                  headers: Headers.fromMap({
                    'location': [
                      // tag 按 **arm64** 的 versionCode 记（既有约定：v4073 ↔ arm64 4073），
                      // x86_64 的包名要按 docs/09 §D.1 的偏移 +2000 算出来。
                      'https://github.com/xiaopeng66/localfit-ai-releases/releases/tag/v4074',
                    ],
                  }),
                ),
              );
              return;
            }
            // HEAD 探包存在。
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                headers: Headers.fromMap({
                  'content-length': ['41966953'],
                }),
              ),
            );
          },
        ),
      );
      final svc = AppUpdateService(dio: dio, platform: PlatformLinks());
      stubPlatform(versionCode: 6073, abi: 'x86_64');
      final check = await svc.checkLatest();
      expect(check.kind, AppUpdateCheckKind.available);
      expect(check.asset!.name, 'LocalFitAI-vc6074-x86_64.apk');
      expect(check.asset!.downloadUrl, contains('/releases/download/v4074/'));
    });

    test('两条路都不通 ⇒ 错误里带**各自的原因**（不是一句「失败」）', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: 'socket down',
            ),
          ),
        ),
      );
      stubPlatform(versionCode: 6073, abi: 'x86_64');
      final svc = AppUpdateService(dio: dio, platform: PlatformLinks());
      final check = await svc.checkLatest();
      expect(check.kind, AppUpdateCheckKind.failed);
      expect(check.message, contains('连不上网络'));
      expect(check.message, contains('发布页也不通'));
    });

    test('403 的原因带上服务端那句话（限流 / 被拦分得清）', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.toString().contains('api.github.com')) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.badResponse,
                  response: Response<dynamic>(
                    requestOptions: options,
                    statusCode: 403,
                    data: const {'message': 'API rate limit exceeded'},
                  ),
                ),
              );
              return;
            }
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionError,
                error: 'x',
              ),
            );
          },
        ),
      );
      stubPlatform(versionCode: 6073, abi: 'x86_64');
      final svc = AppUpdateService(dio: dio, platform: PlatformLinks());
      final check = await svc.checkLatest();
      expect(check.message, contains('403'));
      expect(check.message, contains('rate limit'));
    });
  });

  group('下载进度与取消（2026-11-04 用户：不知道下载到什么进度）', () {
    /// 建一个用完即删的临时目录当 supportDir（updates/ 建在它下面）。
    Directory tempSupportDir() {
      final dir = Directory.systemTemp.createTempSync('localfit-update-dl-');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      return dir;
    }

    const asset = AppReleaseAsset(
      name: 'LocalFitAI-vc6074-x86_64.apk',
      downloadUrl: 'https://example.com/LocalFitAI-vc6074-x86_64.apk',
    );

    test('下载按块上报进度：received 累加、total 来自 content-length', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform(
        versionCode: 6073,
        installOutcome: 'started',
      );
      final dio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [
            List<int>.filled(100, 1),
            List<int>.filled(120, 2),
            List<int>.filled(140, 3),
          ],
          contentLength: 360,
        );
      addTearDown(() => dio.close(force: true));
      final svc = AppUpdateService(
        dio: dio,
        platform: PlatformLinks(),
        supportDir: () async => dir,
      );
      final progress = <(int, int)>[];
      final phases = <AppUpdateInstallPhase>[];
      final savedAtProgress = <List<int>>[];
      final file = File('${dir.path}/updates/${asset.name}');
      final result = await svc.downloadAndInstall(
        asset,
        onProgress: (received, total) {
          progress.add((received, total));
          final writing = Directory('${dir.path}/updates')
              .listSync()
              .whereType<File>()
              .single;
          savedAtProgress.add(writing.readAsBytesSync());
        },
        onPhase: phases.add,
      );
      expect(
        result.kind,
        AppUpdateInstallKind.installerOpened,
        reason: '真的写完 360 字节才许说「已交给系统安装」',
      );
      expect(progress.map((e) => e.$1).toList(), [
        100,
        220,
        360,
      ], reason: 'received 是「写完一块后」的累加值');
      expect(
        progress.every((e) => e.$2 == 360),
        isTrue,
        reason: 'total 必须来自 content-length，界面才能算百分比',
      );
      expect(phases, [
        AppUpdateInstallPhase.downloading,
        AppUpdateInstallPhase.handingOff,
      ], reason: '阶段信号要按「下载中 → 交接中」各报一次');
      expect(
        File('${dir.path}/updates/${asset.name}').lengthSync(),
        360,
        reason: '下载产物落在 updates/ 下（FileProvider 只认这个目录）',
      );
      expect(savedAtProgress, [
        List<int>.filled(100, 1),
        [...List<int>.filled(100, 1), ...List<int>.filled(120, 2)],
        [
          ...List<int>.filled(100, 1),
          ...List<int>.filled(120, 2),
          ...List<int>.filled(140, 3),
        ],
      ], reason: '每次进度回调时该块已经真实写盘，不只是收到网络数据');
      expect(installs, hasLength(1));
      expect((installs.single.arguments as Map)['path'], file.path);
    });

    test('服务器没给 content-length ⇒ total 如实是 -1，不编数字', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform(
        versionCode: 6073,
        installOutcome: 'started',
      );
      final dio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [List<int>.filled(50, 1), List<int>.filled(60, 2)],
        );
      addTearDown(() => dio.close(force: true));
      final svc = AppUpdateService(
        dio: dio,
        platform: PlatformLinks(),
        supportDir: () async => dir,
      );
      final progress = <(int, int)>[];
      final phases = <AppUpdateInstallPhase>[];
      final result = await svc.downloadAndInstall(
        AppReleaseAsset(
          name: asset.name,
          downloadUrl: asset.downloadUrl,
          sizeBytes: 9999,
        ),
        onProgress: (received, total) => progress.add((received, total)),
        onPhase: phases.add,
      );
      expect(result.kind, AppUpdateInstallKind.installerOpened);
      expect(
        progress.every((e) => e.$2 == -1),
        isTrue,
        reason: 'dio 的口径：拿不到总大小就是 -1，界面据此只显示已下载字节',
      );
      expect(progress, [(50, -1), (110, -1)], reason: '不拿清单大小篡改网络进度');
      expect(phases, [
        AppUpdateInstallPhase.downloading,
        AppUpdateInstallPhase.handingOff,
      ]);
      expect(File('${dir.path}/updates/${asset.name}').readAsBytesSync(), [
        ...List<int>.filled(50, 1),
        ...List<int>.filled(60, 2),
      ]);
      expect(installs, hasLength(1));
    });

    test('取消下载 ⇒ cancelled（不冒充失败/成功），半截文件被删掉', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform(
        versionCode: 6073,
        installOutcome: 'started',
      );
      final dio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [List<int>.filled(100, 7)],
          contentLength: 360,
          // 流保持开着：收完一块就停，等用户取消。
          closeStream: false,
        );
      final svc = AppUpdateService(
        dio: dio,
        platform: PlatformLinks(),
        supportDir: () async => dir,
      );
      final token = CancelToken();
      final progress = <(int, int)>[];
      final result = await svc.downloadAndInstall(
        asset,
        cancelToken: token,
        onProgress: (received, total) {
          progress.add((received, total));
          token.cancel('测试里模拟用户点「取消下载」');
        },
      );
      expect(
        result.kind,
        AppUpdateInstallKind.cancelled,
        reason: '用户取消不是网络故障，也不是安装成功',
      );
      expect(result.message, contains('已取消'));
      // 取消的报错走在文件删除完成之前（dio 的 Future.any 竞速）：轮询等删除。
      final file = File('${dir.path}/updates/${asset.name}');
      var deleted = false;
      for (var i = 0; i < 100 && !deleted; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        deleted =
            !file.existsSync() &&
            Directory('${dir.path}/updates').listSync().isEmpty;
      }
      expect(
        deleted,
        isTrue,
        reason: '半截 APK 不许留在 updates/ 里（deleteOnError 默认开着）',
      );
      expect(progress, [(100, 360)]);
      expect(installs, isEmpty);
      dio.close(force: true);
    });

    test('旧取消清理晚于同名重试，不能删除第二次的完整包', () async {
      final dir = tempSupportDir();
      final finalFile = File('${dir.path}/updates/${asset.name}');
      final installs = stubPlatform();
      final firstDio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [
            [1, 2],
          ],
          contentLength: 4,
          closeStream: false,
        );
      final retryDio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [
            [7, 8],
            [9],
          ],
        );
      addTearDown(() => firstDio.close(force: true));
      addTearDown(() => retryDio.close(force: true));
      final cleanupStarted = Completer<void>();
      final releaseCleanup = Completer<void>();
      final cleanupFinished = Completer<void>();
      addTearDown(() async {
        if (!releaseCleanup.isCompleted) releaseCleanup.complete();
        if (cleanupStarted.isCompleted) await cleanupFinished.future;
      });
      final ioZone = Zone.current;
      final token = CancelToken();
      final first = AppUpdateService(
        dio: firstDio,
        supportDir: () async => dir,
      );
      final firstResult = await IOOverrides.runZoned(
        () => first.downloadAndInstall(
          asset,
          cancelToken: token,
          onProgress: (_, _) => token.cancel('cancel first download'),
        ),
        createFile: (path) => DownloadDeleteFile(
          ioZone.run(() => File(path)),
          beforeDelete: () async {
            cleanupStarted.complete();
            await releaseCleanup.future;
          },
          afterDelete: cleanupFinished.complete,
        ),
      );
      expect(firstResult.kind, AppUpdateInstallKind.cancelled);
      await cleanupStarted.future;
      expect(installs, isEmpty);

      final retry = AppUpdateService(
        dio: retryDio,
        supportDir: () async => dir,
      );
      final retryResult = await retry.downloadAndInstall(asset);
      expect(retryResult.kind, AppUpdateInstallKind.installerOpened);
      expect(finalFile.readAsBytesSync(), [7, 8, 9]);
      expect(installs, hasLength(1));
      expect((installs.single.arguments as Map)['path'], finalFile.path);

      releaseCleanup.complete();
      await cleanupFinished.future;
      expect(finalFile.existsSync(), isTrue, reason: '旧清理不得删掉重试的新安装包');
      expect(finalFile.readAsBytesSync(), [7, 8, 9]);
      expect(installs, hasLength(1), reason: '只有第二次完整下载允许调用安装器');
      expect(Directory('${dir.path}/updates').listSync(), hasLength(1));
    });

    for (final cancelOnLastChunk in [false, true]) {
      test('${cancelOnLastChunk ? '最后一' : '第一'}块取消不会覆盖已有最终包', () async {
        final dir = tempSupportDir();
        final finalFile = File('${dir.path}/updates/${asset.name}')
          ..createSync(recursive: true)
          ..writeAsBytesSync([40, 41, 42]);
        final installs = stubPlatform();
        final dio = Dio()
          ..httpClientAdapter = StreamingDownloadAdapter(
            chunks: [
              [1, 2],
              [3, 4],
            ],
            contentLength: 4,
          );
        addTearDown(() => dio.close(force: true));
        final cleanupFinished = Completer<void>();
        final token = CancelToken();
        final ioZone = Zone.current;
        final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
        final result = await IOOverrides.runZoned(
          () => svc.downloadAndInstall(
            asset,
            cancelToken: token,
            onProgress: (received, total) {
              if (!cancelOnLastChunk || received == total) {
                token.cancel('keep previous complete APK');
              }
            },
          ),
          createFile: (path) => DownloadDeleteFile(
            ioZone.run(() => File(path)),
            afterDelete: cleanupFinished.complete,
          ),
        );
        expect(result.kind, AppUpdateInstallKind.cancelled);
        await cleanupFinished.future;
        expect(finalFile.existsSync(), isTrue, reason: '下载取消不能移除上次完整包');
        expect(finalFile.readAsBytesSync(), [40, 41, 42]);
        expect(installs, isEmpty);
        expect(Directory('${dir.path}/updates').listSync(), hasLength(1));
      });
    }

    test('临时包不能重命名到最终路径时，如实失败且清理临时文件', () async {
      final dir = tempSupportDir();
      final finalDirectory = Directory('${dir.path}/updates/${asset.name}')
        ..createSync(recursive: true);
      final installs = stubPlatform();
      final dio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [
            [1, 2, 3],
          ],
        );
      addTearDown(() => dio.close(force: true));
      final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
      final result = await svc.downloadAndInstall(asset);
      expect(result.kind, AppUpdateInstallKind.failed);
      expect(result.message, contains('保存下载文件失败'));
      expect(installs, isEmpty);
      expect(finalDirectory.existsSync(), isTrue);
      expect(Directory('${dir.path}/updates').listSync(), hasLength(1));
    });

    test('预先取消不读目录、不下载、不发阶段、不调用安装器', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform();
      final token = CancelToken()..cancel('already cancelled');
      var directoryCalls = 0;
      final adapter = StreamingDownloadAdapter(
        chunks: [
          [1, 2, 3],
        ],
      );
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final phases = <AppUpdateInstallPhase>[];
      final svc = AppUpdateService(
        dio: dio,
        supportDir: () async {
          directoryCalls++;
          return dir;
        },
      );
      final result = await svc.downloadAndInstall(
        asset,
        cancelToken: token,
        onPhase: phases.add,
      );
      expect(result.kind, AppUpdateInstallKind.cancelled);
      expect(result.message, contains('已取消'));
      expect(directoryCalls, 0, reason: '预先取消不得启动新的文件系统工作');
      expect(phases, isEmpty);
      expect(installs, isEmpty);
      expect(dir.listSync(), isEmpty);
    });

    for (final directoryFails in [false, true]) {
      test('等待存储目录时取消，目录${directoryFails ? '失败' : '返回'}也应取消', () async {
        final dir = tempSupportDir();
        final installs = stubPlatform();
        final token = CancelToken();
        final requested = Completer<void>();
        final support = Completer<Directory>();
        final dio = Dio()
          ..httpClientAdapter = StreamingDownloadAdapter(
            chunks: [
              [1, 2, 3],
            ],
          );
        addTearDown(() => dio.close(force: true));
        final phases = <AppUpdateInstallPhase>[];
        final svc = AppUpdateService(
          dio: dio,
          supportDir: () {
            requested.complete();
            return support.future;
          },
        );
        final pending = svc.downloadAndInstall(
          asset,
          cancelToken: token,
          onPhase: phases.add,
        );
        await requested.future;
        token.cancel('cancel while awaiting support directory');
        if (directoryFails) {
          support.completeError(const FileSystemException('unavailable'));
        } else {
          support.complete(dir);
        }
        final result = await pending;
        expect(result.kind, AppUpdateInstallKind.cancelled);
        expect(phases, isEmpty, reason: '取消后不再开始下载');
        expect(installs, isEmpty);
        expect(dir.listSync(), isEmpty);
      });
    }

    test('downloading 阶段回调取消，不发请求也不安装', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform();
      final token = CancelToken();
      var requests = 0;
      final dio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [
            [1, 2, 3],
          ],
        );
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests++;
            handler.next(options);
          },
        ),
      );
      addTearDown(() => dio.close(force: true));
      final phases = <AppUpdateInstallPhase>[];
      final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
      final result = await svc.downloadAndInstall(
        asset,
        cancelToken: token,
        onPhase: (phase) {
          phases.add(phase);
          token.cancel('cancel from phase callback');
        },
      );
      expect(result.kind, AppUpdateInstallKind.cancelled);
      expect(phases, [AppUpdateInstallPhase.downloading]);
      expect(requests, 0);
      expect(installs, isEmpty);
      expect(File('${dir.path}/updates/${asset.name}').existsSync(), isFalse);
    });

    test('最后一块进度回调取消，不交接安装并删除文件', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform();
      final token = CancelToken();
      final dio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [
            [1, 2],
            [3, 4],
          ],
          contentLength: 4,
        );
      addTearDown(() => dio.close(force: true));
      final phases = <AppUpdateInstallPhase>[];
      final progress = <(int, int)>[];
      final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
      final result = await svc.downloadAndInstall(
        asset,
        cancelToken: token,
        onProgress: (received, total) {
          progress.add((received, total));
          if (received == total) token.cancel('cancel on final chunk');
        },
        onPhase: phases.add,
      );
      expect(result.kind, AppUpdateInstallKind.cancelled);
      expect(progress, [(2, 4), (4, 4)]);
      expect(phases, [AppUpdateInstallPhase.downloading]);
      expect(installs, isEmpty);
      await expectEventuallyDeleted(File('${dir.path}/updates/${asset.name}'));
    });

    for (final check in ['exists', 'length']) {
      test('文件 $check 检查等待期间取消，检查后不能交接安装', () async {
        final dir = tempSupportDir();
        final file = File('${dir.path}/updates/${asset.name}');
        final installs = stubPlatform();
        final token = CancelToken();
        final checking = Completer<void>();
        final resumeCheck = Completer<void>();
        final dio = Dio()
          ..httpClientAdapter = StreamingDownloadAdapter(
            chunks: [
              [1, 2, 3],
            ],
          );
        addTearDown(() => dio.close(force: true));
        final phases = <AppUpdateInstallPhase>[];
        final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
        final ioZone = Zone.current;
        final pending = IOOverrides.runZoned(
          () => svc.downloadAndInstall(
            asset,
            cancelToken: token,
            onPhase: phases.add,
          ),
          createFile: (path) => path != file.path
              ? ioZone.run(() => File(path))
              : DownloadCheckFile(
                  file,
                  onExists: check == 'exists'
                      ? () async {
                          if (!checking.isCompleted) {
                            checking.complete();
                            await resumeCheck.future;
                          }
                        }
                      : null,
                  onLength: check == 'length'
                      ? () async {
                          if (!checking.isCompleted) {
                            checking.complete();
                            await resumeCheck.future;
                          }
                        }
                      : null,
                ),
        );
        await checking.future;
        token.cancel('cancel during $check');
        resumeCheck.complete();
        final result = await pending;
        expect(result.kind, AppUpdateInstallKind.cancelled);
        expect(phases, [AppUpdateInstallPhase.downloading]);
        expect(installs, isEmpty);
        expect(file.existsSync(), isFalse, reason: 'Dio 已结束，这里的清理必须由服务完成');
      });
    }

    test('handingOff 回调同步取消，不能调用安装器并应清理完整下载', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform();
      final token = CancelToken();
      final dio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [
            [1, 2, 3],
          ],
        );
      addTearDown(() => dio.close(force: true));
      final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
      final phases = <AppUpdateInstallPhase>[];
      final result = await svc.downloadAndInstall(
        asset,
        cancelToken: token,
        onPhase: (phase) {
          phases.add(phase);
          if (phase == AppUpdateInstallPhase.handingOff) {
            token.cancel('cancel before platform invocation');
          }
        },
      );
      expect(result.kind, AppUpdateInstallKind.cancelled);
      expect(phases, [
        AppUpdateInstallPhase.downloading,
        AppUpdateInstallPhase.handingOff,
      ]);
      expect(installs, isEmpty);
      expect(File('${dir.path}/updates/${asset.name}').existsSync(), isFalse);
    });

    test('安装器调用后才取消，保留完整文件并返回真实安装结果', () async {
      final dir = tempSupportDir();
      final file = File('${dir.path}/updates/${asset.name}');
      final token = CancelToken();
      final installed = Completer<void>();
      final outcome = Completer<String>();
      final installs = stubPlatform(
        onInstall: (path) {
          expect(path, file.path);
          expect(file.readAsBytesSync(), [1, 2, 3]);
          installed.complete();
          return outcome.future;
        },
      );
      final dio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [
            [1, 2, 3],
          ],
        );
      addTearDown(() => dio.close(force: true));
      final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
      final pending = svc.downloadAndInstall(asset, cancelToken: token);
      await installed.future;
      token.cancel('sheet disposed after platform invocation');
      outcome.complete('started');
      final result = await pending;
      expect(result.kind, AppUpdateInstallKind.installerOpened);
      expect(installs, hasLength(1));
      expect(file.readAsBytesSync(), [1, 2, 3]);
    });

    test('Dio 明确的 cancel 异常即使没有传入 token 也不能冒充网络失败', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform();
      final dio = Dio()
        ..httpClientAdapter = DownloadResponseAdapter((options) {
          throw DioException.requestCancelled(
            requestOptions: options,
            reason: 'request cancelled by transport',
          );
        });
      addTearDown(() => dio.close(force: true));
      final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
      final result = await svc.downloadAndInstall(asset);
      expect(result.kind, AppUpdateInstallKind.cancelled);
      expect(result.message, contains('已取消'));
      expect(installs, isEmpty);
      expect(File('${dir.path}/updates/${asset.name}').existsSync(), isFalse);
    });

    test('收到一块后真实流断开，报告网络失败、无安装并删除半截文件', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform();
      final firstProgress = Completer<void>();
      Stream<Uint8List> body(RequestOptions options) async* {
        yield Uint8List.fromList([1, 2]);
        await firstProgress.future;
        throw DioException.connectionError(
          requestOptions: options,
          reason: 'connection lost',
        );
      }

      final dio = Dio()
        ..httpClientAdapter = DownloadResponseAdapter(
          (options) => ResponseBody(
            body(options),
            200,
            headers: {
              Headers.contentLengthHeader: ['6'],
            },
          ),
        );
      addTearDown(() => dio.close(force: true));
      final progress = <(int, int)>[];
      final phases = <AppUpdateInstallPhase>[];
      final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
      final result = await svc.downloadAndInstall(
        asset,
        onProgress: (received, total) {
          progress.add((received, total));
          firstProgress.complete();
        },
        onPhase: phases.add,
      );
      expect(result.kind, AppUpdateInstallKind.failed);
      expect(result.message, contains('连不上网络'));
      expect(progress, [(2, 6)]);
      expect(phases, [AppUpdateInstallPhase.downloading]);
      expect(installs, isEmpty);
      await expectEventuallyDeleted(File('${dir.path}/updates/${asset.name}'));
    });

    test('下载 HTTP 错误保留状态码和服务端原因，不交接安装', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform();
      final dio = Dio()
        ..httpClientAdapter = DownloadResponseAdapter(
          (_) => ResponseBody.fromString(
            '{"message":"release temporarily unavailable"}',
            503,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          ),
        );
      addTearDown(() => dio.close(force: true));
      final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
      final result = await svc.downloadAndInstall(asset);
      expect(result.kind, AppUpdateInstallKind.failed);
      expect(result.message, contains('503'));
      expect(result.message, contains('release temporarily unavailable'));
      expect(installs, isEmpty);
      expect(File('${dir.path}/updates/${asset.name}').existsSync(), isFalse);
    });

    for (final outcome in ['needPermission', 'failed', 'unexpected']) {
      test('真实下载后安装器返回 $outcome，只调用一次并如实上报', () async {
        final dir = tempSupportDir();
        final installs = stubPlatform(installOutcome: outcome);
        final dio = Dio()
          ..httpClientAdapter = StreamingDownloadAdapter(
            chunks: [
              [1, 2, 3],
            ],
          );
        addTearDown(() => dio.close(force: true));
        final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
        final result = await svc.downloadAndInstall(asset);
        expect(
          result.kind,
          outcome == 'needPermission'
              ? AppUpdateInstallKind.needPermission
              : AppUpdateInstallKind.failed,
        );
        expect(
          result.message,
          contains(outcome == 'needPermission' ? '允许本应用安装' : '系统没能打开安装界面'),
        );
        expect(installs, hasLength(1));
        expect(File('${dir.path}/updates/${asset.name}').readAsBytesSync(), [
          1,
          2,
          3,
        ]);
      });
    }

    test('安装器平台通道异常如实失败，不重复调用或误报取消', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform(
        installError: PlatformException(code: 'unavailable'),
      );
      final dio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [
            [1, 2, 3],
          ],
        );
      addTearDown(() => dio.close(force: true));
      final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
      final result = await svc.downloadAndInstall(asset);
      expect(result.kind, AppUpdateInstallKind.failed);
      expect(result.message, contains('系统没能打开安装界面'));
      expect(installs, hasLength(1));
    });

    test('零字节下载不能交接安装', () async {
      final dir = tempSupportDir();
      final installs = stubPlatform();
      final dio = Dio()
        ..httpClientAdapter = StreamingDownloadAdapter(
          chunks: [],
          contentLength: 0,
        );
      addTearDown(() => dio.close(force: true));
      final phases = <AppUpdateInstallPhase>[];
      final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
      final result = await svc.downloadAndInstall(asset, onPhase: phases.add);
      expect(result.kind, AppUpdateInstallKind.failed);
      expect(result.message, contains('文件是空的'));
      expect(phases, [AppUpdateInstallPhase.downloading]);
      expect(installs, isEmpty);
    });

    test('存储目录读取失败仍保留原有准确错误', () async {
      final installs = stubPlatform();
      final svc = AppUpdateService(
        supportDir: () async {
          throw const FileSystemException('storage unavailable');
        },
      );
      final result = await svc.downloadAndInstall(asset);
      expect(result.kind, AppUpdateInstallKind.failed);
      expect(result.message, '读不到应用的存储目录。');
      expect(installs, isEmpty);
    });

    test('updates 被文件占用时报告创建目录失败，不下载或安装', () async {
      final dir = tempSupportDir();
      File('${dir.path}/updates').writeAsBytesSync([1]);
      final installs = stubPlatform();
      final phases = <AppUpdateInstallPhase>[];
      final svc = AppUpdateService(supportDir: () async => dir);
      final result = await svc.downloadAndInstall(asset, onPhase: phases.add);
      expect(result.kind, AppUpdateInstallKind.failed);
      expect(result.message, '建不了下载目录。');
      expect(phases, isEmpty);
      expect(installs, isEmpty);
    });

    for (final check in ['exists', 'length']) {
      test('文件 $check 检查异常返回本地文件错误，不冒充网络失败', () async {
        final dir = tempSupportDir();
        final file = File('${dir.path}/updates/${asset.name}');
        final installs = stubPlatform();
        final dio = Dio()
          ..httpClientAdapter = StreamingDownloadAdapter(
            chunks: [
              [1, 2, 3],
            ],
          );
        addTearDown(() => dio.close(force: true));
        final phases = <AppUpdateInstallPhase>[];
        final svc = AppUpdateService(dio: dio, supportDir: () async => dir);
        Future<void> failCheck() async {
          throw const FileSystemException('cannot inspect APK');
        }

        final ioZone = Zone.current;
        final result = await IOOverrides.runZoned(
          () => svc.downloadAndInstall(asset, onPhase: phases.add),
          createFile: (path) => path != file.path
              ? ioZone.run(() => File(path))
              : DownloadCheckFile(
                  file,
                  onExists: check == 'exists' ? failCheck : null,
                  onLength: check == 'length' ? failCheck : null,
                ),
        );
        expect(result.kind, AppUpdateInstallKind.failed);
        expect(result.message, contains('文件'));
        expect(result.message, isNot(contains('网络')));
        expect(phases, [AppUpdateInstallPhase.downloading]);
        expect(installs, isEmpty);
      });
    }
  });
}

Future<void> expectEventuallyDeleted(File file) async {
  for (var i = 0; i < 100 && file.parent.listSync().isNotEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(file.existsSync(), isFalse, reason: '取消/失败后不保留半截 APK');
  expect(file.parent.listSync(), isEmpty, reason: '独立 part 文件也必须清理');
}

/// 只替换网络响应，保留真实 Dio 的 HTTP 状态处理、写盘和清理。
class DownloadResponseAdapter implements HttpClientAdapter {
  DownloadResponseAdapter(this.respond);

  final ResponseBody Function(RequestOptions) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

/// 在真实文件已经关闭后控制删除，稳定复现旧 Dio 清理与重试的交错。
class DownloadDeleteFile extends DownloadCheckFile {
  DownloadDeleteFile(
    super.file, {
    this.beforeDelete,
    required this.afterDelete,
  });

  final Future<void> Function()? beforeDelete;
  final void Function() afterDelete;

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    await beforeDelete?.call();
    try {
      return await file.delete(recursive: recursive);
    } finally {
      afterDelete();
    }
  }
}

/// 只在下载后的异步文件检查处停住，Dio 的创建、写盘、关闭仍走真实文件。
class DownloadCheckFile implements File {
  DownloadCheckFile(this.file, {this.onExists, this.onLength});

  final File file;
  final Future<void> Function()? onExists;
  final Future<void> Function()? onLength;

  @override
  String get path => file.path;

  @override
  void createSync({bool recursive = false, bool exclusive = false}) =>
      file.createSync(recursive: recursive, exclusive: exclusive);

  @override
  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      file.openSync(mode: mode);

  @override
  bool existsSync() => file.existsSync();

  @override
  Future<bool> exists() async {
    await onExists?.call();
    return file.exists();
  }

  @override
  Future<int> length() async {
    await onLength?.call();
    return file.length();
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
