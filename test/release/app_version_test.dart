import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_version.dart';

/// 17c：**版本号不许再写「未知」**。
///
/// 用户看到的「版本未知」根因不是显示逻辑，而是**构建时没传
/// `--dart-define=APP_VERSION=`**（`main.dart` 读不到就返回 null）。
///
/// 修法两层，缺一层都会再犯：
/// 1. `tool/build_release.dart` 固化「从 pubspec 读版本 → 每个 ABI 的
///    versionCode → 完整命令」，手敲命令不能漏；
/// 2. **App 自己**有随包的兜底值（`lib/app/app_version.dart`）——有人
///    `flutter build` 不带 define 时也不显示「未知」，而是显示随包的真实号。
///    兜底值与 pubspec 的一致性由本文件钉住（漂了就红）。
void main() {
  group('随包兜底版本（App 侧，define 缺失时的最后一道）', () {
    test('兜底值不为空、是纯数字 versionCode', () {
      expect(kAppVersionFallback, isNotEmpty, reason: '空串就等于又把「未知」放回来了');
      expect(
        kAppVersionFallback,
        matches(RegExp(r'^\d+$')),
        reason: '在线更新比对的是 versionCode；语义版本（0.1.0）比不出新旧',
      );
    });

    test('兜底值与 pubspec.yaml 的构建号一致（改版本时忘了改它会红）', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final buildNumber = RegExp(
        r'^version:\s*[0-9]+\.[0-9]+\.[0-9]+\+([0-9]+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1);
      expect(buildNumber, isNotNull);
      expect(
        kAppVersionFallback,
        buildNumber,
        reason: 'lib/app/app_version.dart 的 kAppVersionFallback 必须等于 pubspec 的 +构建号',
      );
    });

    test('define 注入时用注入值（构建脚本传的 versionCode 优先）', () {
      expect(resolveAppVersion(injected: '4074'), '4074');
    });

    test('define 缺失时回落到随包兜底值，绝不返回 null', () {
      expect(resolveAppVersion(injected: ''), kAppVersionFallback);
      expect(resolveAppVersion(injected: null), kAppVersionFallback);
      expect(resolveAppVersion(injected: '   '), kAppVersionFallback);
    });
  });
}
