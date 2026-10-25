import java.util.Properties

plugins {
    id("com.android.application")
    // Kotlin 插件**必须**在这里应用：漏了它 Gradle 会静默跳过 src/main/kotlin 下的
    // .kt（构建照样成功，APK 里却没有 MainActivity），装到设备上一点就
    // ClassNotFoundException 秒崩——2026-10-21 vc4043/vc4044 两轮 APK 的真实事故。
    // 版本由 settings.gradle.kts 的 pluginManagement 统一钉住。
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名：密钥与口令在 android/key.properties（不入版本库）。
// keystore 备份在 E:/AI/Zcode/backups/localfit/ —— 丢失后无法对已安装版本做升级。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.localfit.ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.localfit.ai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // 有 key.properties 时用正式密钥；没有（如 CI 裸检出）则退回 debug 密钥，
        // 保证 `flutter build apk --release` 在缺密钥的机器上仍能产出可跑包。
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    // Flutter 默认把 .so 以 STORED（未压缩）打包进 APK——AGP 3.6 之后的标准
    // 行为，因为压缩过的原生库没法直接 mmap。代价是下载体积：本包 lib/ 有
    // 28.99 MB 未压缩原生库，压一遍能省下约 16.4 MB（≈ 一半下载量）。
    // 打开 useLegacyPackaging 让 AGP 在构建时压缩 .so，安装时解压到应用私有
    // 目录：代价是安装包体积（在设备上解压后的占用不变）与首次安装多几秒。
    // 个人自用、单 ABI（arm64）的分发场景下这笔交换很划算。docs/25 §6。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
