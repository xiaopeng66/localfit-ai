import 'package:flutter/services.dart';

/// 平台能力（需求 17e / 17b，2026-10-25）：**开外链**与**设备事实**。
///
/// 【为什么不引 url_launcher】新第三方依赖与既有约束冲突（`docs/60` §12.3
/// 明写）。开浏览器在 Android 上是三行 `Intent`，自己挂一条通道即可——与
/// `localfit/steps` / `localfit/scale` 同一做法（`MainActivity.kt`）。
///
/// 【诚实边界】`openUrl` 只认 http/https；其余 scheme 一律失败返回 false，
/// 调用方**必须**给一条退路（复制链接 + 如实说明），不许点了没反应。
///
/// `deviceInfo` 只读机型与 Android 版本——**不读任何标识符**（没有 IMEI /
/// ANDROID_ID / 序列号），这是「全数据本地 + 最小权限」的一贯口径。
class PlatformLinks {
  PlatformLinks({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'localfit/platform';

  final MethodChannel _channel;

  /// 用系统浏览器打开链接。返回 true = 真的打开了。
  ///
  /// 平台侧异常（通道缺失、Activity 不在）一律翻成 false——调用方据此走退路。
  Future<bool> openUrl(String url) async {
    try {
      final opened = await _channel.invokeMethod<bool>('openUrl', {'url': url});
      return opened ?? false;
    } on Object {
      return false;
    }
  }

  /// 机型 + Android 版本（反馈用）。读不到时字段为 null（如实缺省，不编）。
  Future<DeviceFacts> deviceFacts() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'deviceInfo',
      );
      if (raw == null) return const DeviceFacts();
      return DeviceFacts(
        model: (raw['model'] as String?)?.trim(),
        androidVersion: (raw['androidVersion'] as String?)?.trim(),
        sdkInt: raw['sdkInt'] as int?,
        // 在线更新（需求 17b）的判据：本包 versionCode + 本机 ABI。
        versionCode: (raw['versionCode'] as num?)?.toInt(),
        abi: (raw['abi'] as String?)?.trim(),
      );
    } on Object {
      return const DeviceFacts();
    }
  }

  /// 把下载好的 APK 交给系统安装器（需求 17b）。
  ///
  /// 返回 `started` / `needPermission` / `failed`（与 `MainActivity.installApk`
  /// 的三条结局一一对应）；通道异常一律 `failed`。
  Future<String> installApk(String path) async {
    try {
      final outcome = await _channel.invokeMethod<String>('installApk', {
        'path': path,
      });
      return outcome ?? 'failed';
    } on Object {
      return 'failed';
    }
  }
}

/// 设备事实（**只有机型、系统版本、本包 versionCode 与 ABI**，没有标识符）。
final class DeviceFacts {
  const DeviceFacts({
    this.model,
    this.androidVersion,
    this.sdkInt,
    this.versionCode,
    this.abi,
  });

  final String? model;
  final String? androidVersion;
  final int? sdkInt;

  /// 本包的 versionCode（系统读出来的，**不是**构建期注入的字符串）。
  final int? versionCode;

  /// 本机主 ABI（`arm64-v8a` / `x86_64` / `armeabi-v7a`）。
  final String? abi;

  bool get isEmpty =>
      (model == null || model!.isEmpty) &&
      (androidVersion == null || androidVersion!.isEmpty);

  /// 一行可读的机型描述（读不到就写「机型未知」——不编）。
  String get modelLabel => (model == null || model!.isEmpty) ? '机型未知' : model!;

  /// ABI 的可读说法（读不到写「未知 ABI」）。
  String get abiLabel {
    final value = abi;
    if (value == null || value.isEmpty) return '未知 ABI';
    return value;
  }

  String get androidLabel => (androidVersion == null || androidVersion!.isEmpty)
      ? 'Android 版本未知'
      : 'Android ${androidVersion!}';
}
