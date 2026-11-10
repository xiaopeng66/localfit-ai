// 发布构建的**唯一真相**（17c / 17b 的地基）。
//
// 为什么要有这个文件：版本号曾经靠手敲 `--dart-define=APP_VERSION=`，我漏传了
// 一次，设置页就显示「版本未知」（用户 2026-10-25 实测）。手敲的命令一定会再漏
// 第二次，所以把「从 pubspec 读版本 → 每个 ABI 的 versionCode → 完整命令」都固化成
// 代码，并用 `test/release/build_release_plan_test.dart` 钉住。
//
// 【versionCode 与 ABI 的对应】Flutter `--split-per-abi` 自动给每个 ABI 加固定偏移
// （docs/09 §D.1，aapt2 实测）：arm32 +1000 / arm64 +2000 / x86_64 +4000。
// 所以 `--build-number N` 一次渲染出的三个包分别是 N+1000 / N+2000 / N+4000。
// **不能**把偏移后再当 `--build-number` 传（会叠加成 2N 系）。
//
// 【APP_VERSION 是 versionCode 而不是语义版本】更新比对的是「谁的包更新」，
// 那是 versionCode 的事；语义版本（0.1.0）在同一代内不变，比不出东西。
import 'dart:io';

/// 一个 ABI 的发布目标。
final class ReleaseAbi {
  const ReleaseAbi({
    required this.name,
    required this.targetPlatform,
    required this.versionCodeOffset,
    required this.apkSuffix,
  });

  /// 短名（`arm32` / `arm64` / `x86_64`），用于文件名与 `--dart-define`。
  final String name;

  /// `flutter build apk --target-platform` 的取值。
  final String targetPlatform;

  /// `--split-per-abi` 的 versionCode 偏移（docs/09 §D.1 实测值）。
  final int versionCodeOffset;

  /// 产物在 `build/app/outputs/flutter-apk/` 里的文件名后缀。
  final String apkSuffix;

  /// `flutter build` 产出的 APK 路径（相对工程根）。
  String get apkPath =>
      'build/app/outputs/flutter-apk/app-$apkSuffix-release.apk';
}

/// 三种交付目标（顺序即构建顺序，与 dist 命名一致）。
const List<ReleaseAbi> releaseAbis = [
  ReleaseAbi(
    name: 'arm32',
    targetPlatform: 'android-arm',
    versionCodeOffset: 1000,
    apkSuffix: 'armeabi-v7a',
  ),
  ReleaseAbi(
    name: 'arm64',
    targetPlatform: 'android-arm64',
    versionCodeOffset: 2000,
    apkSuffix: 'arm64-v8a',
  ),
  ReleaseAbi(
    name: 'x86_64',
    targetPlatform: 'android-x64',
    versionCodeOffset: 4000,
    apkSuffix: 'x86_64',
  ),
];

/// pubspec 的 `version: 0.1.0+2074` 解析结果。
final class PubspecVersion {
  const PubspecVersion({required this.name, required this.buildNumber});

  /// 语义版本（`0.1.0`），不带 `+build`。
  final String name;

  /// `+` 后面的构建号（`--build-number` 的基础值）。
  final int buildNumber;

  /// 上屏串：`<name>+<buildNumber>`。
  String get full => '$name+$buildNumber';
}

/// 从 pubspec.yaml 文本里读 `version:`。
///
/// 只认顶行的 `version:`（`^version:`），不会误命中依赖里的 version 字段。
PubspecVersion parsePubspecVersion(String pubspec) {
  final match = RegExp(
    r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw const FormatException('pubspec.yaml 里找不到 `version: x.y.z+N`');
  }
  final build = int.tryParse(match.group(2) ?? '');
  if (build == null) {
    throw const FormatException(
      'pubspec.yaml 的 version 缺 `+构建号`：--build-number 无从取值',
    );
  }
  return PubspecVersion(name: match.group(1)!, buildNumber: build);
}

/// 一个 ABI 的完整构建计划。
final class AbiBuild {
  const AbiBuild({
    required this.abi,
    required this.buildNumber,
    required this.versionCode,
    required this.apkName,
  });

  final ReleaseAbi abi;

  /// 传给 `--build-number` 的基础值（**未经偏移**，避免与 Flutter 自动偏移叠加）。
  final int buildNumber;

  /// 这个包最终的 versionCode（= buildNumber + 偏移）。也是注入的 `APP_VERSION`。
  final int versionCode;

  /// 交付文件名：`LocalFitAI-vc<versionCode>-<abi>.apk`。
  final String apkName;

  /// 注入给 Dart 的 `--dart-define` 参数。
  List<String> get defines => [
    '--dart-define=APP_VERSION=$versionCode',
    '--dart-define=APP_ABI=${abi.name}',
  ];

  /// 完整的 flutter 构建参数（不含可执行文件本身）。
  ///
  /// **`--split-per-abi` 必须给**：docs/09 §D.2——只写 `--target-platform`
  /// 不裁剪其它 ABI 的原生依赖，产物会混进三个 ABI。
  List<String> get flutterArgs => [
    'build',
    'apk',
    '--release',
    '--split-per-abi',
    '--target-platform',
    abi.targetPlatform,
    '--build-number',
    '$buildNumber',
    ...defines,
  ];
}

/// 整份发布计划。
final class ReleasePlan {
  const ReleasePlan({required this.version, required this.builds});

  final PubspecVersion version;
  final List<AbiBuild> builds;

  /// 供 `--build-number` 用的基础值（不经偏移）。
  int get buildNumber => version.buildNumber;
}

/// 由 pubspec 文本生成发布计划（纯函数，测试直接调）。
ReleasePlan planRelease(String pubspec) {
  final version = parsePubspecVersion(pubspec);
  return ReleasePlan(
    version: version,
    builds: [
      for (final abi in releaseAbis)
        AbiBuild(
          abi: abi,
          buildNumber: version.buildNumber,
          versionCode: version.buildNumber + abi.versionCodeOffset,
          apkName:
              'LocalFitAI-vc${version.buildNumber + abi.versionCodeOffset}'
              '-${abi.name}.apk',
        ),
    ],
  );
}

/// 校验计划自洽：versionCode 单调递增（docs/09 §D.3），且三者互不相同。
void assertPlanSane(ReleasePlan plan) {
  final codes = [for (final build in plan.builds) build.versionCode];
  if (codes.toSet().length != codes.length) {
    throw StateError('versionCode 重复：$codes');
  }
  for (var i = 1; i < codes.length; i++) {
    if (codes[i] <= codes[i - 1]) {
      throw StateError(
        'versionCode 必须按 arm32 < arm64 < x86_64 递增（docs/09 §D.3）：$codes',
      );
    }
  }
}

/// 命令行入口：`dart run tool/build_release.dart [--dry-run]`。
Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final plan = planRelease(pubspec);
  assertPlanSane(plan);
  stdout.writeln('版本 ${plan.version.full}（build ${plan.buildNumber}）');
  for (final build in plan.builds) {
    stdout.writeln(
      '  ${build.abi.name.padRight(7)} versionCode=${build.versionCode}  '
      '${build.apkName}',
    );
  }
  if (dryRun) return;
  final flutterHome = Platform.environment['FLUTTER_HOME'];
  final flutter = flutterHome == null || flutterHome.isEmpty
      ? 'flutter.bat'
      : '$flutterHome/bin/flutter.bat';
  for (final build in plan.builds) {
    final argv = build.flutterArgs;
    stdout.writeln('> $flutter ${argv.join(' ')}');
    final result = await Process.run(flutter, argv, runInShell: true);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) {
      stderr.writeln('构建失败（${build.abi.name}，exit ${result.exitCode}）');
      exit(result.exitCode);
    }
    final apk = File(build.abi.apkPath);
    if (!apk.existsSync()) {
      stderr.writeln('构建成功但找不到产物：${build.abi.apkPath}');
      exit(2);
    }
    final dist = Directory('dist')..createSync(recursive: true);
    apk.copySync('${dist.path}/${build.apkName}');
    stdout.writeln('→ dist/${build.apkName}（versionCode ${build.versionCode}）');
  }
}
