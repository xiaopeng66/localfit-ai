import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'package:localfit_ai/features/settings/application/platform_links.dart';

/// 在线更新（需求 17b，2026-10-25）：查最新版 → 下载 → 交给系统安装器。
///
/// 【为什么用 GitHub Releases 当更新通道】发布仓库 `localfit-ai-releases`
/// 是 **public、只放 APK 与说明**（源码仓库保持独立）。Release 带三个 ABI 的
/// APK，可匿名下载；App 不需要自建服务器，也不必把 token 塞进包里。
///
/// 【版本判据是 **versionCode**，不是语义版本】`0.1.0` 在同一代内不变，比不出
/// 新旧；而 versionCode 每个 ABI 一个号（docs/09 §D.1）。所以：
/// * **本包的号**从系统读（`PlatformLinks.deviceFacts().versionCode`）——
///   最准，不依赖构建期注入的字符串；
/// * **新版的号**从资产文件名里读（`LocalFitAI-vc6074-x86_64.apk` → 6074）——
///   这正是构建脚本固化的命名（需求 17c 的产物）。
///
/// 【诚实边界】任何一步失败都如实返回（网络、JSON、找不到适配本机的包、
/// 下载中断），由页面说清「哪一步、为什么」；**不假装检查过**。
class AppUpdateService {
  AppUpdateService({
    Dio? dio,
    PlatformLinks? platform,
    Future<Directory> Function()? supportDir,
  }) : _dio = dio ?? Dio(),
       _platform = platform ?? PlatformLinks(),
       _supportDir = supportDir ?? getApplicationSupportDirectory;

  /// 发布清单地址（`releases/latest`，API）。
  static const String releasesLatestUrl =
      'https://api.github.com/repos/xiaopeng66/localfit-ai-releases/releases/latest';

  /// 发布页地址（**非 API**）：它 302 到 `/releases/tag/<tag>`。
  ///
  /// 【为什么需要它】实测（2026-10-25，自有 AVD）：某些网络对
  /// `api.github.com` 直接返 **403**，而 `github.com` 照常可访问。而下载包本身
  /// 就走 `github.com`——所以「读最新版」也不该被 API 一侧卡死。
  /// 这条路径只用两件不必调 API 的事：302 的 Location，与**由命名约定拼出来**
  /// 的资产地址（`releases/download/<tag>/<name>`，命名由 `tool/build_release.dart`
  /// 固化）。拼出来的地址用 HEAD 探一次，存在才算数。
  static const String releasePageLatestUrl =
      'https://github.com/xiaopeng66/localfit-ai-releases/releases/latest';

  /// 资产下载地址前缀（`releases/download/<tag>/<name>`）。
  static const String releaseDownloadBase =
      'https://github.com/xiaopeng66/localfit-ai-releases/releases/download';

  /// 下载目录名（与 `res/xml/file_paths.xml` 里暴露的 `updates/` **必须一致**：
  /// 那条路径是 FileProvider 允许交接的范围）。
  static const String updatesDirName = 'updates';

  // 跨服务实例共享序号，避免同一时刻重试复用旧下载的临时路径。
  static int _downloadSequence = 0;

  final Dio _dio;
  final PlatformLinks _platform;
  final Future<Directory> Function() _supportDir;

  /// 查一次最新版；与**本包**比较后给出三种结局之一。
  ///
  /// 两条路径：**先 API**（信息最全）；API 不通就退回**发布页 302 + 约定拼名**
  /// （`github.com` 通常可达，下载也走它）。两条都失败时，错误信息里带
  /// **各自的原因**——用户拿到的不是一句「失败了」。
  Future<AppUpdateCheck> checkLatest({String? lanBaseUrl}) async {
    final DeviceFacts facts;
    try {
      facts = await _platform.deviceFacts();
    } on Object {
      return const AppUpdateCheck.failed('读不到本机版本号，没法比对。');
    }
    final localCode = facts.versionCode;
    if (localCode == null || localCode <= 0) {
      return const AppUpdateCheck.failed('读不到本机版本号，没法比对。');
    }
    // 局域网源优先：配置了地址就先用它（Wi-Fi 通常比 GitHub 快得多）；
    // 局域网不可用时再退 GitHub，不让一个填错的地址把更新彻底挡死。
    if (lanBaseUrl != null && lanBaseUrl.trim().isNotEmpty) {
      final viaLan = await checkLatestFromLan(
        lanBaseUrl,
        localCode: localCode,
        deviceAbi: facts.abi,
      );
      if (viaLan.kind != AppUpdateCheckKind.failed) return viaLan;
    }
    final abiLabel = abiLabelOf(facts.abi);
    if (abiLabel == null) {
      return AppUpdateCheck.failed('认不出本机架构（${facts.abiLabel}）。');
    }

    final viaApi = await _checkViaApi(localCode: localCode, abiLabel: abiLabel);
    if (viaApi != null) return viaApi;
    final apiReason = _lastApiReason ?? 'API 不可用';
    final viaPage = await _checkViaReleasePage(
      localCode: localCode,
      abiLabel: abiLabel,
    );
    if (viaPage != null) return viaPage;
    return AppUpdateCheck.failed(
      '连不上更新服务器（$apiReason；发布页也不通：${_lastPageReason ?? '未知'}）。',
    );
  }

  /// 从局域网清单检查更新。清单地址可以是：
  /// * 目录（如 `http://10.26.8.28:8080/`）⇒ 自动拼 `lan/manifest.json`；
  /// * 完整清单 URL（`.../lan/manifest.json`）；裸主机名默认补 `http://`。
  ///
  /// 2026-11-10 用户反馈：v4137 把 LAN 改成只收 https 后，`http://10.26.8.28:8080/`
  /// 直接被 App 自己拦了——这条通道是**用户显式填本机地址、同一 Wi-Fi、
  /// 主动触发**的（docs/evidence/2026-10-30-lan-update §六），是隐私审计里
  /// 登记过的唯一合法明文例外。manifest 现为 `usesCleartextTraffic="true"`
  /// （回到 v4131 及之前的行为）；privacy 审计继续钉死 lib/ 无明文 AI/业务
  /// 出网字面量（AI 等业务出口仍全部 https）。
  ///
  /// 清单字段：`version_code`、`version_label`、`download_url`、`size_bytes`、
  /// `abi`。`download_url` 支持绝对地址或相对清单的地址。
  Future<AppUpdateCheck> checkLatestFromLan(
    String baseUrl, {
    int? localCode,
    String? deviceAbi,
  }) async {
    final facts = localCode == null || deviceAbi == null
        ? await _platform.deviceFacts()
        : null;
    final code = localCode ?? facts?.versionCode;
    final abi = deviceAbi ?? facts?.abi;
    if (code == null || code <= 0) {
      return const AppUpdateCheck.failed('读不到本机版本号，没法比对。');
    }
    final manifestUri = _lanManifestUri(baseUrl);
    if (manifestUri == null) {
      return const AppUpdateCheck.failed(
        '局域网更新地址格式不对，应类似 http://10.26.8.28:8080/。',
      );
    }
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        manifestUri.toString(),
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
    } on Object catch (error) {
      return AppUpdateCheck.failed('连不上局域网更新地址：${_shortReason(error)}');
    }
    final data = response.data;
    if (data is! Map) {
      return const AppUpdateCheck.failed('局域网清单内容看不懂（不是 JSON 对象）。');
    }
    final rawCode = data['version_code'];
    final versionCode = rawCode is int
        ? rawCode
        : int.tryParse('${rawCode ?? ''}');
    if (versionCode == null || versionCode <= 0) {
      return const AppUpdateCheck.failed('局域网清单缺少有效的 version_code。');
    }
    final rawUrl = data['download_url'];
    if (rawUrl is! String || rawUrl.trim().isEmpty) {
      return const AppUpdateCheck.failed('局域网清单缺少 download_url。');
    }
    final rawAbi = data['abi'];
    final manifestAbi = rawAbi is String ? abiLabelOf(rawAbi) : null;
    final localAbi = abiLabelOf(abi);
    if (manifestAbi != null && localAbi != null && manifestAbi != localAbi) {
      return AppUpdateCheck.failed('局域网清单是 $manifestAbi 包，本机是 $localAbi，不能安装。');
    }
    final downloadUrl = manifestUri.resolve(rawUrl.trim()).toString();
    final name = Uri.parse(downloadUrl).pathSegments.isEmpty
        ? 'update.apk'
        : Uri.parse(downloadUrl).pathSegments.last;
    final rawSize = data['size_bytes'];
    final size = rawSize is int ? rawSize : int.tryParse('${rawSize ?? ''}');
    final label = data['version_label'] is String
        ? data['version_label'] as String
        : 'v$versionCode';
    final asset = AppReleaseAsset(
      name: name,
      downloadUrl: downloadUrl,
      sizeBytes: size,
      explicitVersionCode: versionCode,
    );
    return _compare(localCode: code, asset: asset, tagName: label);
  }

  static Uri? _lanManifestUri(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    // 明文与 https 都接受：LAN 更新是用户显式填地址的例外通道（docs/
    // evidence/2026-10-30-lan-update §六）；裸主机名默认补 http://。
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      text = 'http://$text';
    }
    final parsed = Uri.tryParse(text);
    if (parsed == null || parsed.host.isEmpty) return null;
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
    if (parsed.path.endsWith('.json')) return parsed;
    final basePath = parsed.path.isEmpty || parsed.path.endsWith('/')
        ? parsed.path
        : '${parsed.path}/';
    return parsed.replace(path: '${basePath}lan/manifest.json');
  }

  /// API 路径；返回 null = 「这条路没走通，试下一条」（原因记在 [_lastApiReason]）。
  /// API 路径；返回 null = 「这条路没走通，试下一条」（原因记在 [_lastApiReason]）。
  Future<AppUpdateCheck?> _checkViaApi({
    required int localCode,
    required String abiLabel,
  }) async {
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        releasesLatestUrl,
        options: Options(
          headers: const {'Accept': 'application/vnd.github+json'},
          followRedirects: true,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
    } on Object catch (error) {
      _lastApiReason = _shortReason(error);
      return null;
    }
    final data = response.data;
    if (data is! Map) {
      _lastApiReason = '返回内容看不懂';
      return null;
    }
    final release = AppRelease.fromGitHubJson(data);
    if (release == null) {
      _lastApiReason = '发布里没有可下载的安装包';
      return null;
    }
    final asset = release.assetForAbi(abiLabel);
    if (asset == null) {
      // API **通了**，只是没有本机可用的包：这是结论，不再退路径。
      return AppUpdateCheck.failed(
        '最新版（${release.tagName}）没有本机（$abiLabel）可用的安装包。',
        tagName: release.tagName,
      );
    }
    return _compare(
      localCode: localCode,
      asset: asset,
      tagName: release.tagName,
    );
  }

  /// 发布页路径：302 拿 tag → 按命名约定拼资产地址 → HEAD 探存在。
  Future<AppUpdateCheck?> _checkViaReleasePage({
    required int localCode,
    required String abiLabel,
  }) async {
    final String? tag;
    try {
      // 不跟随重定向：`Location` 就是我们要的 tag。
      final response = await _dio.get<dynamic>(
        releasePageLatestUrl,
        options: Options(
          followRedirects: false,
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      tag = tagFromLocation(response.headers.value('location'));
    } on Object catch (error) {
      _lastPageReason = _shortReason(error);
      return null;
    }
    if (tag == null) {
      _lastPageReason = '没读到发布版本号';
      return null;
    }
    final expected = expectedAssetName(tagName: tag, abiLabel: abiLabel);
    final url = '$releaseDownloadBase/$tag/$expected';
    final int? size;
    try {
      final head = await _dio.head<dynamic>(
        url,
        options: Options(
          followRedirects: true,
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      if (head.statusCode != 200) {
        // 有 tag 但没这个 ABI 的包：如实说（不当成「路径不通」）。
        return AppUpdateCheck.failed(
          '最新版（$tag）没有本机（$abiLabel）可用的安装包。',
          tagName: tag,
        );
      }
      size = int.tryParse(head.headers.value('content-length') ?? '');
    } on Object catch (error) {
      _lastPageReason = _shortReason(error);
      return null;
    }
    return _compare(
      localCode: localCode,
      asset: AppReleaseAsset(name: expected, downloadUrl: url, sizeBytes: size),
      tagName: tag,
    );
  }

  /// 比较本包与新包：**只比 versionCode**（语义版本在同一代内不变）。
  AppUpdateCheck _compare({
    required int localCode,
    required AppReleaseAsset asset,
    required String tagName,
  }) {
    if (asset.versionCode <= localCode) {
      return AppUpdateCheck.upToDate(
        localVersionCode: localCode,
        tagName: tagName,
      );
    }
    return AppUpdateCheck.available(
      localVersionCode: localCode,
      release: AppRelease(tagName: tagName, assets: [asset]),
      asset: asset,
    );
  }

  String? _lastApiReason;
  String? _lastPageReason;

  /// 从 302 的 `Location`（`…/releases/tag/v4074`）里取 tag。
  static String? tagFromLocation(String? location) {
    if (location == null || location.trim().isEmpty) return null;
    final match = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(location);
    final tag = match?.group(1)?.trim();
    return (tag == null || tag.isEmpty) ? null : tag;
  }

  /// 按命名约定拼资产名：`LocalFitAI-vc<code>-<abi>.apk`。
  ///
  /// 【编号怎么算】Release 的 tag 按 **arm64 的 versionCode** 记（既有约定：
  /// `v4073` ↔ arm64 4073），而资产名里的 `vc` 号是**该 ABI** 的 versionCode：
  /// arm32 = tag − 1000、arm64 = tag、x86_64 = tag + 2000（docs/09 §D.1 的偏移表，
  /// 与构建脚本同源）。tag 里没有数字时**不猜**，直接用 tag 当短名。
  static String expectedAssetName({
    required String tagName,
    required String abiLabel,
  }) {
    final base = RegExp(r'(\d+)\s*$').firstMatch(tagName)?.group(1);
    final tagCode = int.tryParse(base ?? '');
    final offset = switch (abiLabel) {
      'arm32' => -1000,
      'arm64' => 0,
      'x86_64' => 2000,
      _ => 0,
    };
    final abiCode = tagCode == null ? null : tagCode + offset;
    final suffix = abiCode == null ? tagName : 'vc$abiCode';
    return 'LocalFitAI-$suffix-$abiLabel.apk';
  }

  /// 下载并交给系统安装器。返回的结局与 Kotlin 侧一一对应。
  ///
  /// [onProgress] 每写完一个网络分块回调一次 `(已收字节, 总字节)`；**总字节为
  /// `-1` 表示服务器没给 `content-length`**（GitHub 走压缩传输时如此），
  /// 此时调用方只该说「已下载多少」，不该编一个百分比。
  ///
  /// [cancelToken] 在调用系统安装器之前有效；每次异步准备/文件检查返回后都
  /// 重新检查取消，`handingOff` 回调内同步取消也能阻止交接。
  /// 下载中的半截文件由 Dio 异步清理（取消结果可能先于清理完成）；每次都
  /// 使用独立 `.part`，旧清理不会删掉重试的包。下载正常结束后才改名到最终
  /// 路径。安装器一旦调用，取消不撤回交接、不删完整文件。
  ///
  /// [onPhase] 两个阶段的信号（下载中 → 下载完、正在交给系统安装）。
  /// 进度回调只能说明「收到了多少字节」，**说明不了下载结束**（服务器不给
  /// 总大小时 `total` 恒为 -1），所以阶段必须单独给，界面才不用猜。
  Future<AppUpdateInstallResult> downloadAndInstall(
    AppReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
    void Function(AppUpdateInstallPhase phase)? onPhase,
    CancelToken? cancelToken,
  }) async {
    bool isCancelled() => cancelToken?.isCancelled ?? false;
    if (isCancelled()) return const AppUpdateInstallResult.cancelled();

    final Directory support;
    try {
      support = await _supportDir();
    } on Object {
      if (isCancelled()) return const AppUpdateInstallResult.cancelled();
      return const AppUpdateInstallResult.failed('读不到应用的存储目录。');
    }
    if (isCancelled()) return const AppUpdateInstallResult.cancelled();

    final dir = Directory('${support.path}/$updatesDirName');
    try {
      final exists = await dir.exists();
      if (isCancelled()) return const AppUpdateInstallResult.cancelled();
      if (!exists) await dir.create(recursive: true);
    } on Object {
      if (isCancelled()) return const AppUpdateInstallResult.cancelled();
      return const AppUpdateInstallResult.failed('建不了下载目录。');
    }
    if (isCancelled()) return const AppUpdateInstallResult.cancelled();

    final path = '${dir.path}/${asset.name}';
    final partPath =
        '$path.${DateTime.now().microsecondsSinceEpoch}.${_downloadSequence++}.part';
    onPhase?.call(AppUpdateInstallPhase.downloading);
    if (isCancelled()) return const AppUpdateInstallResult.cancelled();
    try {
      await _dio.download(
        asset.downloadUrl,
        partPath,
        onReceiveProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
    } on Object catch (error) {
      // Dio 的取消 Future 可能早于它的关闭/删除完成；不再并发删除同一文件。
      if (isCancelled() ||
          (error is DioException && CancelToken.isCancel(error))) {
        return const AppUpdateInstallResult.cancelled();
      }
      return AppUpdateInstallResult.failed('下载失败（${_shortReason(error)}）。');
    }

    var file = File(partPath);
    // 只清理本次持有的路径；Dio 正常返回后才由服务接管清理责任。
    Future<AppUpdateInstallResult> discardDownloadedFile(
      AppUpdateInstallResult result,
    ) async {
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // 清理失败不升级成成功，也不改变取消/本地文件错误的真实结局。
      }
      return result;
    }

    Future<AppUpdateInstallResult> cancelDownloadedFile() =>
        discardDownloadedFile(const AppUpdateInstallResult.cancelled());

    if (isCancelled()) return cancelDownloadedFile();
    try {
      if (!await file.exists() || await file.length() == 0) {
        if (isCancelled()) return await cancelDownloadedFile();
        return await discardDownloadedFile(
          const AppUpdateInstallResult.failed('下载下来的文件是空的。'),
        );
      }
      if (isCancelled()) return await cancelDownloadedFile();
      // 与最终 APK 在同一目录，只在完整下载成功且未取消时替换最终文件。
      await file.rename(path);
      file = File(path);
    } on Object {
      if (isCancelled()) return cancelDownloadedFile();
      return discardDownloadedFile(
        const AppUpdateInstallResult.failed('保存下载文件失败。'),
      );
    }
    if (isCancelled()) return cancelDownloadedFile();
    try {
      final exists = await file.exists();
      if (isCancelled()) return await cancelDownloadedFile();
      final length = exists ? await file.length() : 0;
      if (isCancelled()) return await cancelDownloadedFile();
      if (length == 0) {
        return const AppUpdateInstallResult.failed('下载下来的文件是空的。');
      }
    } on Object {
      if (isCancelled()) return cancelDownloadedFile();
      return const AppUpdateInstallResult.failed('检查下载文件失败。');
    }

    onPhase?.call(AppUpdateInstallPhase.handingOff);
    if (isCancelled()) return cancelDownloadedFile();
    // 从最后一次取消检查到平台调用之间没有 await，交接后保留文件及真实结果。
    final outcome = await _platform.installApk(path);
    return switch (outcome) {
      'started' => const AppUpdateInstallResult.installerOpened(),
      'needPermission' => const AppUpdateInstallResult.needPermission(),
      _ => const AppUpdateInstallResult.failed('系统没能打开安装界面。'),
    };
  }

  /// HTTP 非 2xx 的原因：**带上服务端说的那句话**（只写「403」用户没法判断
  /// 是限流、是网络设备拦的、还是仓库变了）。取 JSON 的 `message`，没有截原文。
  static String _badResponseReason(DioException error) {
    final status = error.response?.statusCode ?? '错误';
    final data = error.response?.data;
    String? detail;
    if (data is Map && data['message'] is String) {
      detail = (data['message'] as String).trim();
    } else if (data is String) {
      detail = data.trim();
    }
    if (detail == null || detail.isEmpty) return '服务器返回 $status';
    final short = detail.length > 80 ? '${detail.substring(0, 80)}…' : detail;
    return '服务器返回 $status：$short';
  }

  /// 失败原因压成一句人话（原始异常里全是英文类名，不该甩给用户）。
  static String _shortReason(Object error) {
    final text = error.toString();
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => '超时',
        DioExceptionType.connectionError => '连不上网络',
        DioExceptionType.badResponse => _badResponseReason(error),
        _ => '请求失败',
      };
    }
    return text.length > 40 ? '网络异常' : text;
  }
}

/// 一次检查的结局（三态，各自都有话可说）。
final class AppUpdateCheck {
  const AppUpdateCheck._({
    required this.kind,
    this.message,
    this.localVersionCode,
    this.release,
    this.asset,
    this.tagName,
  });

  const AppUpdateCheck.upToDate({
    required int localVersionCode,
    required String tagName,
  }) : this._(
         kind: AppUpdateCheckKind.upToDate,
         localVersionCode: localVersionCode,
         tagName: tagName,
       );

  const AppUpdateCheck.available({
    required int localVersionCode,
    required AppRelease release,
    required AppReleaseAsset asset,
  }) : this._(
         kind: AppUpdateCheckKind.available,
         localVersionCode: localVersionCode,
         release: release,
         asset: asset,
       );

  const AppUpdateCheck.failed(String message, {String? tagName})
    : this._(
        kind: AppUpdateCheckKind.failed,
        message: message,
        tagName: tagName,
      );

  final AppUpdateCheckKind kind;
  final String? message;
  final int? localVersionCode;
  final AppRelease? release;
  final AppReleaseAsset? asset;
  final String? tagName;

  bool get hasUpdate => kind == AppUpdateCheckKind.available;
}

enum AppUpdateCheckKind { upToDate, available, failed }

/// 下载 + 安装的结局。
final class AppUpdateInstallResult {
  const AppUpdateInstallResult._(this.kind, this.message);

  const AppUpdateInstallResult.installerOpened()
    : this._(AppUpdateInstallKind.installerOpened, null);

  const AppUpdateInstallResult.needPermission()
    : this._(
        AppUpdateInstallKind.needPermission,
        '系统还没允许本应用安装其它应用：已打开那个设置页，打开开关后回到这里再点一次。',
      );

  const AppUpdateInstallResult.failed(String message)
    : this._(AppUpdateInstallKind.failed, message);

  const AppUpdateInstallResult.cancelled()
    : this._(AppUpdateInstallKind.cancelled, '已取消下载。');

  final AppUpdateInstallKind kind;
  final String? message;
}

enum AppUpdateInstallKind { installerOpened, needPermission, failed, cancelled }

/// 下载 + 安装的两个阶段。界面据此换文案，**不靠进度数字猜**：
/// 服务器不给总大小时 `total` 恒为 -1，收到最后一块也说明不了「下载完了」。
enum AppUpdateInstallPhase {
  /// 正在接收网络数据。
  downloading,

  /// 文件已落盘，正在交给系统安装器。
  handingOff,
}

/// 一次发布（GitHub Release 的最小投影）。
final class AppRelease {
  const AppRelease({required this.tagName, required this.assets});

  final String tagName;
  final List<AppReleaseAsset> assets;

  /// tag 里的数字（`v4074` → 4074）；没有数字返回 null（不猜）。
  int? get tagNumber {
    final digits = RegExp(r'(\d+)\s*$').firstMatch(tagName.trim())?.group(1);
    return digits == null ? null : int.tryParse(digits);
  }

  /// 从 GitHub `releases/latest` 的 JSON 里解析；缺关键字段返回 null。
  static AppRelease? fromGitHubJson(Object? raw) {
    if (raw is! Map) return null;
    final tag = raw['tag_name'];
    if (tag is! String || tag.trim().isEmpty) return null;
    final rawAssets = raw['assets'];
    final assets = <AppReleaseAsset>[];
    if (rawAssets is List) {
      for (final entry in rawAssets) {
        final asset = AppReleaseAsset.fromGitHubJson(entry);
        if (asset != null) assets.add(asset);
      }
    }
    return AppRelease(tagName: tag.trim(), assets: assets);
  }

  /// 给这个 ABI 找包：按**文件名里的 ABI 短名**匹配（`-x86_64` / `-arm64` /
  /// `-arm32`）。Abi 名走 [abiLabelOf] 的同一套映射。
  ///
  /// 找不到精确匹配时**不回落**到「随便给一个」——下错包（arm64 装到 x86_64
  /// 机器上）会直接失败，那比说「没有你的包」更糟。
  AppReleaseAsset? assetForAbi(String? abi) {
    final label = abiLabelOf(abi);
    if (label == null) return null;
    for (final asset in assets) {
      if (asset.abiLabel == label) return asset;
    }
    return null;
  }
}

/// 一个可下载的资产（APK）。
final class AppReleaseAsset {
  const AppReleaseAsset({
    required this.name,
    required this.downloadUrl,
    this.sizeBytes,
    this.explicitVersionCode,
  });

  final String name;
  final String downloadUrl;
  final int? sizeBytes;

  /// 清单**显式**给的 versionCode（局域网通道用；GitHub 通道为 null）。
  ///
  /// 为什么需要它：GitHub 通道可以从资产文件名（`LocalFitAI-vc6074-arm64.apk`）
  /// 解析出号，而局域网清单里的文件名是发布方随手起的（`app.apk` 也可能）
  /// ——只靠文件名会把版本号读成 0，于是永远判「已是最新」。
  final int? explicitVersionCode;

  /// 这版 APK 的 versionCode：显式值优先，其次从文件名（`vc6074`）解析。
  ///
  /// 都给不出时返回 0（= 不可能比任何已装版本更新 ⇒ 不会被误当成「有新版」）。
  int get versionCode {
    final explicit = explicitVersionCode;
    if (explicit != null && explicit > 0) return explicit;
    final digits = RegExp(r'vc(\d+)').firstMatch(name)?.group(1);
    return int.tryParse(digits ?? '') ?? 0;
  }

  /// 文件名里的 ABI 短名（与 dist 命名一致）。
  String? get abiLabel {
    for (final label in const ['arm32', 'arm64', 'x86_64']) {
      if (name.contains('-$label')) return label;
    }
    return null;
  }

  static AppReleaseAsset? fromGitHubJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final url = raw['browser_download_url'];
    if (name is! String || url is! String) return null;
    if (!name.toLowerCase().endsWith('.apk')) return null;
    final size = raw['size'];
    return AppReleaseAsset(
      name: name,
      downloadUrl: url,
      sizeBytes: size is int ? size : null,
    );
  }
}

/// Android ABI 名 → dist 命名里的短名（`x86_64` 原样，`arm64-v8a` → `arm64`）。
///
/// 与 `tool/build_release.dart` 的 ABI 表**同一套名字**：那边决定包名，这边
/// 按包名找包，两处各写一份必然漂。
String? abiLabelOf(String? abi) {
  if (abi == null) return null;
  final normalized = abi.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  // 幂等：本函数的输出（`arm32`/`arm64`/`x86_64`）也必须是合法输入。
  // `arm32` 不含 `armeabi`/`v7a`，过去二次解析会归零，arm32 用户被误报「没有本机可用的包」。
  if (normalized == 'arm32' ||
      normalized == 'arm64' ||
      normalized == 'x86_64') {
    return normalized;
  }
  if (normalized.contains('x86_64')) return 'x86_64';
  if (normalized.contains('arm64')) return 'arm64';
  if (normalized.contains('armeabi') || normalized.contains('v7a')) {
    return 'arm32';
  }
  return null;
}
