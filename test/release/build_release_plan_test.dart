import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/build_release.dart';

/// 17c：**版本号不许再写「未知」**。
///
/// 用户看到的「版本未知」根因不是显示逻辑，而是**构建时没传
/// `--dart-define=APP_VERSION=`**（`main.dart` 读不到就返回 null）。
/// 手敲命令一定会再漏一次，所以把「版本从哪来、每个 ABI 的 versionCode 是
/// 多少」固化成 `tool/build_release.dart`，在这里钉死。
void main() {
  group('pubspec 版本解析', () {
    test('读出语义版本与构建号', () {
      final version = parsePubspecVersion('''
name: localfit_ai
version: 0.1.0+2074
environment:
  sdk: ^3.13.2
''');
      expect(version.name, '0.1.0');
      expect(version.buildNumber, 2074);
      expect(version.full, '0.1.0+2074');
    });

    test('真实 pubspec.yaml 能被解析（工程本身必须过这条）', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = parsePubspecVersion(pubspec);
      expect(version.buildNumber, greaterThan(0));
      expect(version.name, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    });

    test('缺 +构建号时如实报错（不许瞎猜一个 0）', () {
      expect(
        () => parsePubspecVersion('version: 0.1.0\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('不误命中依赖里的 version 字段', () {
      final pubspec = '''
name: x
version: 1.2.3+45
dependencies:
  foo:
    version: 9.9.9+99
''';
      expect(parsePubspecVersion(pubspec).buildNumber, 45);
    });
  });

  group('ABI × versionCode 偏移（docs/09 §D.1 实测值）', () {
    test('arm32 +1000 / arm64 +2000 / x86_64 +4000', () {
      final plan = planRelease('version: 0.1.0+2074\n');
      expect(plan.builds.map((b) => b.abi.name), ['arm32', 'arm64', 'x86_64']);
      expect(plan.builds.map((b) => b.versionCode), [3074, 4074, 6074]);
    });

    test('偏移只体现在 versionCode，--build-number 仍传基础值（不叠加）', () {
      final plan = planRelease('version: 0.1.0+2074\n');
      for (final build in plan.builds) {
        expect(
          build.buildNumber,
          2074,
          reason: 'Flutter 自己会按 ABI 加偏移；传 offset 后的值会叠加成 2N 系',
        );
        final args = build.flutterArgs;
        final index = args.indexOf('--build-number');
        expect(args[index + 1], '2074');
      }
    });

    test('versionCode 单调递增（docs/09 §D.3）', () {
      final plan = planRelease('version: 0.1.0+2074\n');
      expect(() => assertPlanSane(plan), returnsNormally);
    });

    test('计划自洽检查会拒绝乱序', () {
      final plan = planRelease('version: 0.1.0+2074\n');
      final broken = ReleasePlan(
        version: plan.version,
        builds: [plan.builds[1], plan.builds[0], plan.builds[2]],
      );
      expect(() => assertPlanSane(broken), throwsStateError);
    });
  });

  group('注入 APP_VERSION（17c 的核心判据）', () {
    test('每个包都注入它自己的 versionCode 作为 APP_VERSION', () {
      final plan = planRelease('version: 0.1.0+2074\n');
      for (final build in plan.builds) {
        expect(
          build.defines,
          contains('--dart-define=APP_VERSION=${build.versionCode}'),
          reason: '漏了它就又是「版本未知」',
        );
      }
    });

    test('构建参数必须带 --release --split-per-abi --target-platform', () {
      final plan = planRelease('version: 0.1.0+2074\n');
      for (final build in plan.builds) {
        final args = build.flutterArgs;
        expect(args, containsAll(['build', 'apk', '--release']));
        // docs/09 §D.2：单 ABI 交付必须同时给 --split-per-abi，否则混进三个 ABI。
        expect(args, contains('--split-per-abi'));
        expect(
          args[args.indexOf('--target-platform') + 1],
          build.abi.targetPlatform,
        );
      }
    });

    test('交付文件名带 versionCode 与 ABI 短名', () {
      final plan = planRelease('version: 0.1.0+2074\n');
      expect(plan.builds[0].apkName, 'LocalFitAI-vc3074-arm32.apk');
      expect(plan.builds[1].apkName, 'LocalFitAI-vc4074-arm64.apk');
      expect(plan.builds[2].apkName, 'LocalFitAI-vc6074-x86_64.apk');
    });
  });

  group('构建脚本存在且是可执行的入口', () {
    test('tool/build_release.bat 存在、是 ASCII、调用 dart run build_release', () {
      final file = File('tool/build_release.bat');
      expect(file.existsSync(), isTrue, reason: '17c 要求固化构建命令');
      final bytes = file.readAsBytesSync();
      expect(
        bytes.every((b) => b < 0x80),
        isTrue,
        reason: 'AGENTS.md：.bat 正文必须保持 ASCII',
      );
      final text = file.readAsStringSync();
      expect(text, contains('tool\\build_release.dart'));
      expect(text, contains('FLUTTER_HOME'));
    });
  });
}
