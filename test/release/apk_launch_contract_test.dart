import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 「装上去能启动」的构造期契约（2026-10-21 真实事故的回归钉子）。
///
/// **事故**：`android/app/build.gradle.kts` 的 `plugins {}` 里漏了 Kotlin 插件，
/// 而 `android/app/src/main/AndroidManifest.xml` 的 launcher activity 写的是
/// **相对名** `.MainActivity`（按 `namespace` 解析）。于是
/// ① Kotlin 源不参与编译 ⇒ APK 的 `classes.dex` 里根本没有 MainActivity；
/// ② 相对名解析到 `com.localfit.ai.MainActivity`，与 Kotlin 源里的包名也不一致。
/// 构建**成功**、`aapt2 dump badging` 也照样报出一个 launcher activity，
/// 只有装到设备上点开时才会 `ClassNotFoundException` 秒崩——
/// vc4043 / vc4044 两轮 APK 都栽在这里（设备实测：FATAL EXCEPTION: main）。
///
/// 这条测试不看设备、不联网，只把三件事对上：
/// 1. `build.gradle.kts` 的 `plugins {}` 里**必须**有 Kotlin 插件（否则 .kt 静默不编）；
/// 2. manifest 的 launcher activity 名解析后，**必须**在 Kotlin 源码里找得到同名类
///    （FQN 直接用；相对名按 `namespace` 拼接）；
/// 3. 找到的类所在文件的 `package` 声明必须与被解析出来的 FQN 一致。
void main() {
  final androidDir = Directory('android/app');
  late String gradle;
  late String manifest;
  late List<File> kotlinSources;

  setUpAll(() {
    gradle = File('${androidDir.path}/build.gradle.kts').readAsStringSync();
    manifest = File('${androidDir.path}/src/main/AndroidManifest.xml')
        .readAsStringSync();
    kotlinSources = Directory('${androidDir.path}/src/main/kotlin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.kt'))
        .toList();
  });

  test('build.gradle.kts 应用了 Kotlin 插件（漏了它 .kt 就不参与编译）', () {
    final pluginsBlock = RegExp(
      r'plugins\s*\{(.*?)\}',
      dotAll: true,
    ).firstMatch(gradle)?.group(1);
    expect(pluginsBlock, isNotNull, reason: '找不到 plugins {} 块');
    expect(
      pluginsBlock,
      matches(
        RegExp(r'id\("(org\.jetbrains\.kotlin\.android|kotlin-android)"\)'),
      ),
      reason:
          'plugins {} 里没有 Kotlin 插件：Gradle 会**静默**跳过 src/main/kotlin 下的 .kt'
          '（构建照样成功），APK 里没有 MainActivity，装到设备上一点就崩。'
          'settings.gradle.kts 已声明 `org.jetbrains.kotlin.android` 的版本，'
          '这里补 `id("org.jetbrains.kotlin.android")` 即可。',
    );
  });

  test('launcher activity 解析后在 Kotlin 源码里真的有这个类（含包名一致）', () {
    final namespace = RegExp(r'namespace\s*=\s*"([^"]+)"')
        .firstMatch(gradle)
        ?.group(1);
    expect(namespace, isNotNull, reason: 'build.gradle.kts 里找不到 namespace');

    final activityName = RegExp(
      r'<activity[^>]*?android:name="([^"]+)"',
      dotAll: true,
    ).firstMatch(manifest)?.group(1);
    expect(
      activityName,
      isNotNull,
      reason: 'manifest 里找不到 <activity android:name>',
    );

    // 相对名（`.MainActivity`）按 Android 的规则贴到 namespace 后面——**保留那个点**。
    final fqn = activityName!.startsWith('.')
        ? '$namespace$activityName'
        : activityName;
    final simpleName = fqn.split('.').last;
    final declaredPackage = fqn.substring(
      0,
      fqn.length - simpleName.length - 1,
    );

    final declaring = kotlinSources.where((file) {
      final source = file.readAsStringSync();
      return source.contains(
            RegExp(
              r'^\s*package\s+' + RegExp.escape(declaredPackage) + r'\s*$',
              multiLine: true,
            ),
          ) &&
          source.contains(
            RegExp(r'class\s+' + RegExp.escape(simpleName) + r'\b'),
          );
    }).toList();

    expect(
      declaring,
      hasLength(1),
      reason:
          'manifest 的 launcher activity「$activityName」解析成「$fqn」，'
          '但 android/app/src/main/kotlin 下找不到 `package $declaredPackage` + '
          '`class $simpleName`（找到 ${declaring.length} 处）。'
          '两种改法二选一：把 manifest 的 android:name 写成类的**全限定名**，'
          '或把类的 package 声明与 namespace（$namespace）对齐；'
          '不要留下「manifest 说一个名字、Kotlin 源说另一个包」的错位。',
    );
  });
}
