import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_manifest.dart';

/// 2.0-7d：把 docs/05 §4「安全与隐私门槛」和「商店隐私说明」里**机械可核对**
/// 的部分钉住（docs/07 §13 DoD 末条：文档、隐私声明、菜单来源许可证和实际
/// 网络行为一致）。
///
/// 这些是静态审计断言：改出网面、加权限、加依赖、随包换数据集都会先红一次，
/// 逼着人回答「隐私说明要不要跟着改」。动态行为（真实网络/存储/日志）由
/// `test/ai_evaluation/ai_egress_evaluation_test.dart`（五条 AI 出口）
/// 与 `test/privacy_logger_test.dart`（日志默认拒绝）覆盖。
void main() {
  final root = Directory.current.path;

  /// 递归列出某目录下的文件（相对仓库根的路径，`/` 分隔）。
  List<String> filesUnder(
    String relative, {
    Set<String> extensions = const {},
  }) {
    final directory = Directory('$root/$relative');
    if (!directory.existsSync()) {
      throw StateError('审计目标不存在：$relative（测试基准目录变了？）');
    }
    return [
      for (final entity in directory.listSync(
        recursive: true,
        followLinks: false,
      ))
        if (entity is File)
          if (extensions.isEmpty ||
              extensions.any((extension) => entity.path.endsWith(extension)))
            entity.path.replaceFirst('$root/', '').replaceAll('\\', '/'),
    ];
  }

  group('出网面（商店隐私说明里的「网络」一栏）', () {
    test('lib/ 里没有明文 http:// 出网字面量', () {
      final offenders = <String>[];
      for (final path in filesUnder('lib', extensions: {'.dart'})) {
        final source = File('$root/$path').readAsStringSync();
        // 只放过整行注释（历史说明里可能提到 http）。按 `//` 截断是错的：
        // `'http://…'` 这个 URL 自身的 `//` 会把命中切掉，等于没查。
        for (final line in source.split('\n')) {
          final trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) continue;
          if (line.contains('http://')) offenders.add('$path: ${line.trim()}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'AI/路线出口必须 https（明文流量同时被 AndroidManifest 的 '
            'usesCleartextTraffic=false 拒绝）：$offenders',
      );
    });

    test('Android 权限清单与隐私声明一致，且不申请任何定位权限', () {
      final manifest = File('$root/android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final permissions = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"')
          .allMatches(manifest)
          .map((match) => match.group(1))
          .toList();

      // 计步（ACTIVITY_RECOGNITION）读本机传感器算今日步数（docs/29 §P9 需求
      // 34）：数值只进本机数据库，不上传；顺序须与 AndroidManifest 声明一致。
      // P10（需求 36，2026-10-07）：语音输入整族删除，RECORD_AUDIO 随之移除。
      // 体重秤（docs/31 S6，需求 47 / D6，2026-10-10）：BLUETOOTH_SCAN/CONNECT
      // 只用于前台扫描与连接标准体重秤服务（0x181D），SCAN 带 neverForLocation
      // ——扫描结果不用于推导位置；legacy BLUETOOTH/BLUETOOTH_ADMIN 仅
      // maxSdkVersion=30（那些版本上本应用不扫描）。
      expect(permissions, [
        'android.permission.INTERNET',
        'android.permission.ACTIVITY_RECOGNITION',
        'android.permission.BLUETOOTH_SCAN',
        'android.permission.BLUETOOTH_CONNECT',
        'android.permission.BLUETOOTH',
        'android.permission.BLUETOOTH_ADMIN',
      ]);
      // neverForLocation 必须显式声明：丢了它，系统会把 BLE 扫描当位置用途。
      final scanTag = RegExp(
        r'<uses-permission[^>]*android:name="android\.permission\.BLUETOOTH_SCAN"[^>]*>',
      ).firstMatch(manifest)!;
      expect(scanTag.group(0), contains('neverForLocation'));
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
      // 位置/相机/存储权限一个都没有：手动地点优先、无后台定位（ADR-007），
      // 相机与文件走系统 Intent 而不是自己声明的权限。
      // D6 备注（2026-10-10）：体重秤扫描在 API ≤ 30 需要系统级定位权限，
      // 本仓明确**不加**——老设备诚实显示「设备不支持」，不拿零定位的姿态换
      // 老设备支持。加它之前必须先改这里 + docs/08 并说明理由。
      // （按字节面审：注释里也不许出现这个权限名，防「写进注释再放开」。）
      expect(manifest, isNot(contains('ACCESS_FINE_LOCATION')));
      expect(manifest, isNot(contains('ACCESS_BACKGROUND_LOCATION')));
    });

    test('关掉平台自动备份：明文库文件不许进云备份/换机迁移', () {
      final manifest = File('$root/android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      // 「全数据本地」不是靠应用自己不上传就够：android:allowBackup 默认
      // 为 true，平台会把 databases/、files/（含拍照照片、menu_raw/）与
      // shared_prefs/ 明文打包到 Google Drive，并从旧机迁到新机——用户的
      // 唯一出口必须是应用自己的密码加密 .lfb 包。
      expect(
        manifest,
        contains('android:allowBackup="false"'),
        reason: 'allowBackup 缺省为 true，必须显式写 false',
      );
      expect(manifest, contains('android:dataExtractionRules='));
      expect(manifest, contains('android:fullBackupContent='));

      // 规则文件是第二道防线（万一将来有人把 allowBackup 打开）：两个版本
      // 分支的规则都必须逐域排除，且一条 include 都不能有——include 会把
      // 对应域重新拉回备份集合。断言按「块」下钻（cloud-backup 与
      // device-transfer 各查一遍），否则「某个块漏排一域」这种变异会存活。
      const domains = {'root', 'file', 'database', 'sharedpref', 'external'};
      final extraction = File(
        '$root/android/app/src/main/res/xml/data_extraction_rules.xml',
      );
      expect(
        extraction.existsSync(),
        isTrue,
        reason: '缺少 data_extraction_rules.xml',
      );
      final extractionRules = extraction.readAsStringSync();
      const extractionBlocks = ['cloud-backup', 'device-transfer'];
      for (final name in extractionBlocks) {
        final match = RegExp(
          '<$name>(.*?)</$name>',
          dotAll: true,
        ).firstMatch(extractionRules);
        expect(
          match,
          isNotNull,
          reason: 'data_extraction_rules.xml 缺少 $name 块',
        );
        final block = match!.group(1)!;
        expect(
          block,
          isNot(contains('<include')),
          reason: '$name 块出现 include，会把该域重新纳入备份',
        );
        for (final domain in domains) {
          expect(
            block,
            contains('<exclude domain="$domain"'),
            reason: '$name 块没有排除 domain=$domain',
          );
        }
      }

      final legacy = File(
        '$root/android/app/src/main/res/xml/backup_rules.xml',
      );
      expect(legacy.existsSync(), isTrue, reason: '缺少 backup_rules.xml');
      final legacyRules = legacy.readAsStringSync();
      expect(legacyRules, isNot(contains('<include')));
      for (final domain in domains) {
        expect(
          legacyRules,
          contains('<exclude domain="$domain" path="."'),
          reason: 'API ≤ 30 规则没有排除 domain=$domain 整域',
        );
      }
    });

    test('依赖里没有分析/广告/崩溃上报 SDK', () {
      final pubspec = File('$root/pubspec.yaml').readAsStringSync();
      final packages = RegExp(
        r'^\s{2}([a-z0-9_]+):',
        multiLine: true,
      ).allMatches(pubspec).map((match) => match.group(1)!).toSet();
      const trackers = {
        'firebase_analytics',
        'firebase_crashlytics',
        'firebase_core',
        'google_mobile_ads',
        'sentry_flutter',
        'appsflyer_sdk',
        'amplitude_flutter',
        'mixpanel_flutter',
        'segment_analytics',
        'datadog_flutter_plugin',
        'bugsnag_flutter',
        'newrelic_mobile',
        'flutter_facebook_app_events',
        'onesignal_flutter',
        'umeng_common_sdk',
        'jpush_flutter',
        'bugly',
        'talkingdata',
        'sensors_analytics_flutter_plugin',
      };

      expect(
        packages.intersection(trackers),
        isEmpty,
        reason: '本地优先应用不引入分析/广告/崩溃上报 SDK（docs/07 §12）',
      );
    });
  });

  group('密钥与日志', () {
    test('lib/、随包资源、原生工程里没有形似真实 Key 的字面量', () {
      final patterns = <RegExp>[
        RegExp(r'sk-[A-Za-z0-9_\-]{20,}'),
        RegExp(r'AIza[0-9A-Za-z_\-]{30,}'),
        RegExp(r'xox[baprs]-[A-Za-z0-9\-]{10,}'),
        RegExp(r'ghp_[A-Za-z0-9]{30,}'),
      ];
      final offenders = <String>[];
      for (final path in [
        ...filesUnder('lib', extensions: {'.dart'}),
        ...filesUnder('assets'),
        ...filesUnder(
          'android',
          extensions: {'.xml', '.kts', '.gradle', '.properties'},
        ),
      ]) {
        // 用 latin1 读：assets/catalog 下是 ETL 产出的 SQLite 二进制（2.0-1），
        // 按 UTF-8 读会直接抛异常，而把整个 assets 目录从扫描里排除更糟。
        // Key 模式全是 ASCII，latin1 解码不会漏判。
        final text = File('$root/$path')
            .readAsBytesSync()
            .map((byte) => String.fromCharCode(byte))
            .join();
        for (final pattern in patterns) {
          if (pattern.hasMatch(text)) {
            offenders.add('$path: ${pattern.pattern}');
          }
        }
      }
      expect(offenders, isEmpty, reason: '源码/随包资源/构建配置里不许出现真实 Key（docs/05 §4）');
    });

    test('生产代码不构造 PrivacyLogger：线上日志出口为零', () {
      final offenders = filesUnder('lib', extensions: {'.dart'})
          .where(
            (path) =>
                path != 'lib/core/logging/privacy_logger.dart' &&
                File('$root/$path')
                    .readAsStringSync()
                    .contains('PrivacyLogger('),
          )
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            'PrivacyLogger 目前只在测试里注入（生产不写日志）。要接日志出口，'
            '必须先确认白名单（见 privacy_logger_test.dart）里只有四个指标，'
            '再把这条审计改成对日志文件的断言',
      );
    });
  });

  group('随包第三方数据与许可证', () {
    // assets/catalog 是 `tool/food_catalog/run_full_etl.sh` 的产物目录：里面有
    // manifest 与全部分片（发布目录 5 片 58.7 MiB），但**随包进 APK 的只有
    // manifest 与 core 分片**（docs/07 §5.6「首次安装只导入 core shard」），其余
    // 分片由用户放进 <supportDir>/catalog/ 后按需导入（main.dart 的
    // `_catalogShardPaths` 读的是那里）。所以这里分三种口径审：
    // 非目录的随包种子逐条过许可证审查、目录资产只允许 manifest + core 分片、
    // 整个产物目录必须与 manifest 的 sha256 对得上。
    List<String> catalogArtifacts() {
      final directory = Directory('$root/assets/catalog');
      if (!directory.existsSync()) return const [];
      return filesUnder('assets/catalog')..sort();
    }

    /// 随包的种子数据集（不含目录资产，也不含 UI 图标资源）。
    ///
    /// `assets/icons/` 是界面自带的分类图标（`food_category.dart` 逐条引用），
    /// 不是随包数据集：它们不含用户数据、也不在许可证审查范围内，所以这里
    /// 按目录排除，而不是塞进「审计过的那几个」白名单里蒙混过关。
    List<String> bundledDatasets() =>
        filesUnder('assets')
            .where((path) => !path.startsWith('assets/catalog/'))
            .where((path) => !path.startsWith('assets/icons/'))
            // `assets/models/` 是**模型权重**（BGE int8 ONNX + 词表），不是
            // 数据集：它不含用户数据、也不进「随包数据集」许可证白名单，
            // 许可证在 docs/THIRD_PARTY_LICENSES.md §6 单独登记（下一条测试
            // 会钉住「文件在、pubspec 声明了、许可证写到了」三件事，
            // 不允许靠这个排除静默绕过审查）。
            .where((path) => !path.startsWith('assets/models/'))
            .toList()
          ..sort();

    /// 真正随包的种子清单。
    ///
    /// 2026-10-13（docs/32 §4 T13 / §3 D13，需求 75）：**食物种子退役**——
    /// `foods.v4/v5.json` 已从仓库移出（归档在 `../archive/food-seed-2026-10-13/`），
    /// 所以原先那个「在盘上但不随包」的排除名单不再需要：盘上剩下的就都是随包的。
    /// 归档件不在仓库里，本审计只审仓库里的文件，故无需再排除任何东西。
    List<String> shippedDatasets() => bundledDatasets();

    /// 随包的非数据集资源目录：目前只有 UI 图标；出现新目录要先在这里登记，
    /// 否则「随包数据集」白名单会被静默绕过。
    List<String> bundledAssetDirectories() => <String>{
      for (final path in filesUnder('assets'))
        if (!path.startsWith('assets/catalog/') &&
            !path.startsWith('assets/seed/'))
          path.substring(0, path.lastIndexOf('/') + 1),
    }.toList()..sort();

    test('随包的非数据集资源目录已登记', () {
      expect(bundledAssetDirectories(), [
        'assets/icons/food_categories/',
        // 2026-10-19（S12 P0 稳态复测后启用向量）：端上嵌入模型与词表。
        // 它是什么：BAAI bge-small-zh-v1.5 int8 ONNX（512 维，MIT）+ WordPiece
        // 词表；要不要过许可证审查：**要**，已登记在
        // docs/THIRD_PARTY_LICENSES.md §6。
        'assets/models/',
      ], reason: '新增随包资源目录要先说明它是什么、要不要过许可证审查');
    });

    test('随包模型文件在盘上、在 pubspec 声明、许可证已登记', () {
      final pubspec = File('$root/pubspec.yaml').readAsStringSync();
      final licenses = File('$root/docs/THIRD_PARTY_LICENSES.md')
          .readAsStringSync();
      for (final path in const [
        'assets/models/model_int8.onnx',
        'assets/models/vocab.txt',
      ]) {
        expect(
          File('$root/$path').existsSync(),
          isTrue,
          reason: '$path 必须真的在盘上（模型缺失时语义检索应降级，而不是崩）',
        );
      }
      expect(
        pubspec,
        contains('- assets/models/'),
        reason: '模型目录必须在 pubspec 里声明（否则运行时 rootBundle 读不到）',
      );
      expect(
        licenses,
        contains('bge-small-zh-v1.5'),
        reason: '模型许可证必须登记（MIT，BAAI）',
      );
    });

    test('随包种子文件就是审计过的这几个（动作库 + 用户食物库）', () {
      // exercises.v1 是本仓库最初手写的 60 条动作；v2 是它的**同源**版本
      // （同样 60 条，只补了 difficulty/popularity 两列标注，没有引入任何新的
      // 第三方数据）。两者都还留在仓库/随包里，是为了向后兼容的导入测试与升级
      // 路径，许可证审查结论与 v1 逐条相同，故不新增审查项。
      // exercises.v3（2026-10-04）换了上游：312 条（305 条派生自
      // yuhonas/free-exercise-db，Unlicense/public domain；另 7 条沿用 v1/v2
      // 事实手写保留），已按 §3 过审查并登记到 docs/THIRD_PARTY_LICENSES.md。
      // 食物种子（FoodCalu）2026-10-02 换过源、2026-10-13（docs/32 §4 T13）
      // **整族退役**：v4/v5 都已移出仓库（归档在
      // `../archive/food-seed-2026-10-13/`，见其 README），App 不再随包任何
      // 食物数据；用户可见的来源标注随之改成「历史随包 · 现已不随包」。
      // 所以现在随包的数据集是动作库三件 + 用户食物库一份。
      //
      // 2026-10-20（用户提供并明确要求内置）：`user_foods_8col.v1.csv`
      // 23,919 条、8 列（名称/品牌/一级分类/四项营养）。**来源是混合的**：
      // S1 中国食物成分表 6 版公开转录（Sanotsu/china-food-composition-data，
      // MIT）、S2/S3/S3b 薄荷（Boohee）网页/SQL 历史存档（多个 GitHub 爬虫
      // 仓库，上游未声明许可证）、S5 台湾食药署开放数据（政府开放资料，
      // 需署名）。混合源的**再分发许可并不干净**——这是个人自用不分发的
      // 既有定位（ADR-020 补记 + ADR-025）涵盖的同类情形，已在
      // docs/THIRD_PARTY_LICENSES.md §1b 逐源登记风险；一旦对外分发，
      // 必须先处理该节的阻塞项。
      // 2026-10-21（ADR-037）：`food_library_normalization.v1.csv` 是上面那份
      // 用户食物库的**派生资产**（旧(名称,品牌)→新名称/品牌/分类/别名），
      // 由 `tool/food_catalog/normalize_food_library.py` 生成——没有引入任何
      // 新上游，来源与许可与 `user_foods_8col.v1.csv` 同一份（§1b）。
      expect(bundledDatasets(), [
        'assets/seed/exercises.v1.json',
        'assets/seed/exercises.v2.json',
        'assets/seed/exercises.v3.json',
        'assets/seed/food_library_normalization.v1.csv',
        'assets/seed/user_foods_8col.v1.csv',
      ], reason: '新增/替换随包数据集必须先过许可证审查并更新 7d 证据');
    });

    test('pubspec 只随包 manifest 与 core 分片（其余分片按需分发）', () {
      final pubspec = File('$root/pubspec.yaml').readAsStringSync();
      final declared = RegExp(
        r'^\s{4}- (assets/\S+)$',
        multiLine: true,
      ).allMatches(pubspec).map((match) => match.group(1)!).toList()..sort();

      expect(
        declared.where(
          (path) =>
              !path.startsWith('assets/catalog/') &&
              !path.startsWith('assets/icons/') &&
              // 模型权重另算：它由上面那条「在盘上 / 声明了 / 许可证登记了」
              // 的测试单独钉住（与图标目录同一个套路）。
              !path.startsWith('assets/models/'),
        ),
        shippedDatasets(),
        reason: '随包数据集要与 pubspec 声明一一对应（图标与模型目录另算）',
      );
      // 已退役的种子文件绝不能又被声明进 pubspec（会白扛 ~11 MB 且违反审查结论）。
      // 2026-10-13（docs/32 §4 T13）：食物种子整族退役、文件也移出了仓库，所以
      // 这份名单改成**写在测试里的历史事实**（两个具体文件名），而不是跟着仓库
      // 现状自动变化的变量——列表要是自动更新，这次退役就等于没被钉住。
      for (final retired in const [
        'assets/seed/foods.v4.json',
        'assets/seed/foods.v5.json',
      ]) {
        expect(
          declared,
          isNot(contains(retired)),
          reason: '退役种子 $retired 不该再随包',
        );
      }

      // **目录形式**声明的资源（图标 `assets/icons/food_categories/`、模型
      // 权重 `assets/models/`）与逐文件声明的数据集不同：这里只要求声明的目录
      // 确实存在，避免目录改名后 pubspec 静默失效、图标或模型在真机上全部丢失。
      final declaredResourceDirectories = declared
          .where(
            (path) =>
                path.endsWith('/') &&
                !path.startsWith('assets/catalog/') &&
                !path.startsWith('assets/seed/'),
          )
          .toList();
      expect(
        declaredResourceDirectories,
        bundledAssetDirectories(),
        reason: 'pubspec 声明的资源目录要与 assets/ 下实际存在的目录一致',
      );

      final declaredCatalog = declared
          .where((path) => path.startsWith('assets/catalog/'))
          .toList();
      final manifestFile = File('$root/assets/catalog/catalog.manifest.json');
      if (!manifestFile.existsSync()) {
        // 还没构建过目录（全新检出）：此时一条目录资产都不许声明。
        expect(declaredCatalog, isEmpty, reason: '没有构建产物却声明了目录资产，打出来的包会缺文件');
        return;
      }
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      final coreShard =
          ((manifest['shards']! as List).first as Map<String, Object?>)['file'];
      expect(declaredCatalog, [
        'assets/catalog/catalog.manifest.json',
        'assets/catalog/$coreShard',
      ], reason: 'docs/07 §5.6 只随包 core 分片（= manifest 的第一个分片）');
    });

    test('assets/catalog 里只有 manifest 和它列出的分片，且 sha256 对得上', () async {
      final artifacts = catalogArtifacts();
      if (artifacts.isEmpty) {
        // 还没构建过目录（全新检出）。构建命令见 PRIVACY 审计说明与 docs/09。
        return;
      }
      final manifestFile = File('$root/assets/catalog/catalog.manifest.json');
      expect(manifestFile.existsSync(), isTrue, reason: '有分片却没有 manifest');

      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      final shards = (manifest['shards'] as List<Object?>)
          .cast<Map<String, Object?>>();
      final expected = <String>['assets/catalog/catalog.manifest.json'];
      for (final shard in shards) {
        expected.add('assets/catalog/${shard['file']}');
        final digest = await Sha256().hash(
          File('$root/${expected.last}').readAsBytesSync(),
        );
        expect(
          digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          shard['sha256'],
          reason: '${shard['file']} 与 manifest 记录的 sha256 不一致（被改过？）',
        );
      }
      expect(artifacts, expected..sort(), reason: '目录里出现了 manifest 未列出的文件');
    });

    test('目录 manifest 的许可证白名单没有悄悄扩大', () {
      expect(allowedCatalogLicenses, {
        'odbl-1.0',
        'cc0-1.0',
        'cc-by-4.0',
        'cc-by-sa-3.0',
        'cc-by-sa-4.0',
        'public-domain',
      }, reason: '清单外来源不进发布包；扩清单要重新做许可证审查（docs/05 §5 质量门槛）');
    });

    // 【测试退役 + 断言改写，2026-10-25 用户裁决「数据层也删」】
    //
    // 原测试遍历 `foodDataAttributions`（App 内的来源清单）逐条核对上游/许可证/
    // 发货方式。用户要求把数据层也删掉之后，这个清单**不存在了**，遍历无对象。
    //
    // 但**不能整条删掉**——它里面还有一条与 App 清单无关、必须继续守的检查：
    // 「ETL 声明的许可证必须在**已审查的白名单**里」。原来那句话是拿 App 清单
    // 当白名单用；清单没了，改成直接对 manifest 白名单断言（更直接）。
    test('ETL 声明的许可证必须在目录 manifest 的白名单里（App 清单已删，改用 manifest）', () {
      final etl = File('$root/tool/food_catalog/etl_pipeline.py')
          .readAsStringSync();
      final declared = RegExp(r'"license": "([a-z0-9.\-]+)"')
          .allMatches(etl)
          .map((match) => match.group(1)!)
          .toSet();
      expect(declared, isNotEmpty, reason: 'ETL 必须显式声明来源许可证');
      for (final license in declared) {
        expect(
          allowedCatalogLicenses,
          contains(license),
          reason:
              'ETL 用了 $license，但目录 manifest 的许可证白名单里没有——'
              '新来源必须先过许可证审查（docs/05 §5）',
        );
      }
    });

    test('App 内的来源归属数据层已按用户要求删除（不留半套）', () {
      // 三层都删：公共值类型、食物清单、动作清单。
      // 留着「只有类型没有清单」或「只有清单没有 UI」都是半套，下一个人
      // 会以为它还在用。
      for (final path in [
        'lib/core/attribution.dart',
        'lib/features/nutrition/domain/data_attribution.dart',
        'lib/features/training/domain/data_attribution.dart',
      ]) {
        expect(
          File('$root/$path').existsSync(),
          isFalse,
          reason: '$path 应当已删除（2026-10-25 用户：「数据层也删」）',
        );
      }
      // lib/ 里不许再有 DataAttribution / dataAttribution 这类符号残留。
      final hits = <String>[];
      for (final entity in Directory('$root/lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final text = entity.readAsStringSync();
        if (text.contains('DataAttribution') ||
            text.contains('foodDataAttributions') ||
            text.contains('exerciseDataAttributions')) {
          hits.add(entity.path.replaceFirst('$root/', ''));
        }
      }
      expect(hits, isEmpty, reason: 'lib/ 里仍有来源归属符号：$hits');
    });

    test('docs/07 §5.3 的「删除/替换来源」脚本存在，且它的来源清单与种子里的一致', () {
      // docs/07 §5.3 末条要求「2.0 发布前生成第三方许可清单**和删除/替换来源的脚本**」。
      // 前半句由本文件覆盖，后半句原来只是 ADR-020 里的一句计划——这里把它钉成
      // 可执行的东西：脚本必须在、必须认识种子里的每一个来源前缀。
      final script = File('$root/tool/food_seed/strip_seed_source.py');
      expect(
        script.existsSync(),
        isTrue,
        reason: 'docs/07 §5.3 要求随包来源可删除：缺 tool/food_seed/strip_seed_source.py',
      );
      final source = script.readAsStringSync();

      // 脚本声明的来源前缀 → 去真实种子里数一遍，两个集合必须相等：
      // 漏一个来源就删不掉它；多一个就会把不存在的来源当成「已删除」而静默通过。
      final declared = RegExp(r'"(seed-[a-z0-9]+-)":')
          .allMatches(source)
          .map((match) => match.group(1)!)
          .toSet();
      expect(declared, isNotEmpty, reason: '脚本必须声明它认识的来源前缀（DECLARED_SOURCES）');
      // 脚本自己声明「只动目标来源」：剥一个来源不能碰另一个来源的条目。
      // （这条不依赖种子文件，所以放在「找得到种子才跑」的外面。）
      expect(
        source,
        contains('startswith'),
        reason: '剥离必须按 id 前缀（来源）精确匹配，不能按名字/字段猜',
      );

      // 脚本声明的来源前缀 → 去真实种子里数一遍，两个集合必须相等：
      // 漏一个来源就删不掉它；多一个就会把不存在的来源当成「已删除」而静默通过。
      //
      // 2026-10-13（docs/32 §4 T13）：`foods.v4/v5.json` 已移出仓库（归档在仓库外的
      // `../archive/food-seed-2026-10-13/`），仓库里已经没有这份种子了，所以这条对账
      // 改成**本机有归档才跑**（脚本自身的缺省路径也按同一次序找：
      // `$LOCALFIT_FOOD_SEED` → 仓库内旧路径 → 归档）。全新检出的机器上这半边不跑，
      // 覆盖损失如实记在 T13 证据里，而不是把断言删掉假装还覆盖着。
      final seedCandidates = [
        File('$root/assets/seed/foods.v4.json'),
        File('$root/../archive/food-seed-2026-10-13/foods.v4.json'),
      ];
      File? seedFile;
      for (final candidate in seedCandidates) {
        if (candidate.existsSync()) {
          seedFile = candidate;
          break;
        }
      }
      if (seedFile != null) {
        final seed =
            jsonDecode(seedFile.readAsStringSync()) as Map<String, Object?>;
        final inSeed = <String>{};
        for (final raw
            in (seed['foods']! as List).cast<Map<String, Object?>>()) {
          final id = raw['id']! as String;
          if (!id.startsWith('seed-')) continue;
          final parts = id.substring('seed-'.length).split('-');
          if (parts.length >= 2) inSeed.add('seed-${parts.first}-');
        }

        expect(declared, inSeed, reason: '删除脚本的来源清单与随包种子不一致：漏了来源就删不掉它');
      }
    });

    // 【测试退役 + 断言改写，2026-10-25】动作来源清单（`exerciseDataAttributions`）
    // 随数据层一起删除。原测试遍历它核对 README；清单没了，改为**直接守 README**
    // ——归属信息仍在仓库文档里（`tool/exercise_seed/README.md`），
    // 这条检查的价值（「上游与许可证别跟着代码一起消失」）因此保留。
    test('动作种子的上游与许可证仍写在 exercise_seed README 里', () {
      final readme = File('$root/tool/exercise_seed/README.md')
          .readAsStringSync();
      // 上游：owner/repo 或域名形态，不能是「某网站」这种模糊说法。
      expect(
        RegExp(r'[\w.\-]+/[\w.\-]+|[\w\-]+\.(?:org|com|cn)').hasMatch(readme),
        isTrue,
        reason: '动作种子的 README 必须写出上游（owner/repo 或域名）',
      );
      // 许可证：README 必须写明**具体**许可证名，且上游原文要在盘上。
      //
      // 不用 `allowedCatalogLicenses` 硬匹配——那是**目录食物**的白名单，
      // 动作种子是另一套来源（yuhonas/free-exercise-db，许可证写作
      // 「Unlicense / public domain」，与白名单的 `public-domain` 写法不同）。
      // 硬套白名单会误报（本轮踩过）。这里按「写出了许可证名 + 上游原文在盘」
      // 两条判据，比字符串比对更贴合这条测试的本意。
      final lower = readme.toLowerCase();
      final licenseWords = const [
        'unlicense',
        'public domain',
        'public-domain',
        'mit',
        'apache',
        'cc0',
        'cc-by',
        'odbl',
      ];
      expect(
        licenseWords.any(lower.contains),
        isTrue,
        reason: '动作种子的 README 必须写明许可证名（当前：Unlicense / public domain）',
      );
      expect(
        File('$root/tool/exercise_seed/raw/LICENSE.md').existsSync(),
        isTrue,
        reason: '上游许可证原文必须在盘上（raw/LICENSE.md）',
      );
    });

    test('docs/28 §7.5 的「删除/替换来源」脚本存在（动作种子那一份），且来源清单与种子里的一致', () {
      // 与食物侧同一条纪律：随包数据集必须有一条「停止分发某个来源」的命令，
      // 且脚本认识的来源集合 == 真实种子里的来源集合（漏一个就删不掉，
      // 多一个就会把不存在的来源当成「已删除」而静默通过）。
      final script = File('$root/tool/exercise_seed/strip_exercise_source.py');
      expect(
        script.existsSync(),
        isTrue,
        reason: '换源后随包来源仍须可删除：缺 tool/exercise_seed/strip_exercise_source.py',
      );
      final source = script.readAsStringSync();

      // 只截 DECLARED_ORIGINS 那一段再数键：整份脚本里还有 "exercises"、
      // "origin" 之类的字面量，不限定范围会被它们污染。
      final start = source.indexOf('DECLARED_ORIGINS = {');
      expect(start, isNonNegative, reason: '脚本必须声明它认识的来源（DECLARED_ORIGINS）');
      final end = source.indexOf('\n}', start);
      final declared = RegExp(r'^\s*"([a-z0-9\-]+)":', multiLine: true)
          .allMatches(source.substring(start, end))
          .map((match) => match.group(1)!)
          .toSet();
      expect(declared, isNotEmpty, reason: '脚本必须声明它认识的来源（DECLARED_ORIGINS）');

      final seed = jsonDecode(
        File('$root/assets/seed/exercises.v3.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final inSeed = <String>{
        for (final raw
            in (seed['exercises']! as List).cast<Map<String, Object?>>())
          raw['origin']! as String,
      };

      expect(declared, inSeed, reason: '删除脚本的来源清单与随包动作种子不一致：漏了来源就删不掉它');
      // 脚本自己声明「只动目标来源」：剥一个来源不能碰另一个来源的条目。
      expect(
        source,
        contains('exercise["origin"] != origin'),
        reason: '剥离必须按每条的 origin 精确匹配，不能按名字/字段猜',
      );
    });
  });
}
