/// 随包兜底的版本号（versionCode）——**绝不再显示「版本未知」**。
///
/// 由来（需求 17c，docs/09 §D.2）：用户看到的「版本未知」根因不是显示逻辑，
/// 而是构建时没传 `--dart-define=APP_VERSION=`（`main.dart` 读不到就返回空）。
/// 修法两层：
/// 1. `tool/build_release.dart` 固化「从 pubspec 读版本 → 按 ABI 算
///    versionCode → 拼完整命令」，手敲命令不能漏；
/// 2. **App 自己**有一个随包的兜底值（本文件）——有人直接 `flutter build`
///    没带 define 时也不显示「未知」，而是显示随包的真实号。
///
/// 与 `pubspec.yaml` 的 `+构建号` 的一致性由 `test/release/app_version_test.dart`
/// 钉住（改版本忘了改这里会红）。
///
/// 【为什么是 versionCode 而不是 `0.1.0`】在线更新比对的是 versionCode
/// （每个 ABI 一个号，见 docs/09 §D.1）；语义版本在同一代内不变，比不出新旧。
const String kAppVersionFallback = '2140';

/// 解析要展示的版本号：**define 注入优先，缺失/空白回落到随包兜底值**。
///
/// 返回**非空**字符串是本函数的契约（页面直接拼 `v…`，不再自己判空）。
String resolveAppVersion({String? injected}) {
  final value = injected?.trim();
  if (value == null || value.isEmpty) return kAppVersionFallback;
  return value;
}
