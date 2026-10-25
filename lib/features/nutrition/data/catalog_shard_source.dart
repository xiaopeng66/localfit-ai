import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:localfit_ai/features/nutrition/data/catalog_manifest.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_shard_importer.dart';

/// 随包目录资产的读取口。生产实现走 Flutter `rootBundle`（见 `main.dart`），
/// 测试注入内存实现；返回 null 表示这个键不在随包资产里。
typedef CatalogAssetLoader = Future<Uint8List?> Function(String assetKey);

/// 随包目录分片在支持目录里的落地情况。
class CatalogMaterialization {
  const CatalogMaterialization({
    required this.written,
    required this.reused,
    required this.unavailable,
  });

  /// 本次从随包资产复制出来的分片文件名。
  final List<String> written;

  /// 已在支持目录里且与 manifest 记录一致、直接复用的分片文件名。
  final List<String> reused;

  /// manifest 里有、随包资产里没有的分片文件名（按需分发的那批）。
  final List<String> unavailable;

  List<String> get all => [...written, ...reused, ...unavailable];
}

/// 目录分片的本地来源（docs/07 §5.6）。
///
/// 分片有两个来源，解析顺序固定：
/// 1. **随包资产** `assets/catalog/<file>`——只放 core 分片，首次安装立即复制到
///    `<supportDir>/catalog/` 并导入，保证装完就能搜到食物、不依赖任何下载；
/// 2. **支持目录** `<supportDir>/catalog/<file>`——其余分片（品牌、长尾）由用户
///    自己放进这里后主动导入，应用不会自动联网下载。
///
/// 复制用「先写 `.tmp` 再改名」，所以目标文件出现即完整；再加一份
/// `.bundled-shards.json` 记录每个分片复制自哪个 sha256，升级到新目录版本时
/// （sha256 变了）会重新复制，而不是继续用旧副本让导入以 hash 不一致失败。
class CatalogShardSource {
  CatalogShardSource({
    required this.supportDir,
    required this.assetLoader,
    this.manifestAsset = defaultManifestAsset,
    this.assetDirectory = defaultAssetDirectory,
  });

  static const String defaultManifestAsset =
      'assets/catalog/catalog.manifest.json';
  static const String defaultAssetDirectory = 'assets/catalog';
  static const String bundledMarkerFile = '.bundled-shards.json';

  final String supportDir;
  final CatalogAssetLoader assetLoader;
  final String manifestAsset;
  final String assetDirectory;

  String get _shardDir => '$supportDir${Platform.pathSeparator}catalog';

  String shardPath(String file) => '$_shardDir${Platform.pathSeparator}$file';

  String get _markerPath =>
      '$_shardDir${Platform.pathSeparator}$bundledMarkerFile';

  String assetKey(String file) => '$assetDirectory/$file';

  /// 读随包 manifest。随包没有目录（开发构建、或还没把分片打进包）时返回 null。
  Future<CatalogManifest?> loadBundledManifest() async {
    final bytes = await assetLoader(manifestAsset);
    if (bytes == null) return null;
    final raw = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    return parseCatalogManifest(raw);
  }

  /// 把随包里的分片复制到支持目录；返回哪些是新写的、哪些复用了旧副本、
  /// 哪些随包没有。
  Future<CatalogMaterialization> materializeBundledShards(
    CatalogManifest manifest,
  ) async {
    final marker = await _readMarker();
    final written = <String>[];
    final reused = <String>[];
    final unavailable = <String>[];

    await Directory(_shardDir).create(recursive: true);

    for (final shard in manifest.shards) {
      final target = File(shardPath(shard.file));
      if (marker[shard.file] == shard.sha256 && target.existsSync()) {
        reused.add(shard.file);
        continue;
      }
      final bytes = await assetLoader(assetKey(shard.file));
      if (bytes == null) {
        unavailable.add(shard.file);
        continue;
      }
      await _writeAtomically(target, bytes);
      marker[shard.file] = shard.sha256;
      written.add(shard.file);
    }

    await _writeMarker(marker);
    return CatalogMaterialization(
      written: written,
      reused: reused,
      unavailable: unavailable,
    );
  }

  /// 把本地已有的分片按 manifest 顺序解析成导入输入；缺的分片如实列出来，
  /// 不猜也不静默跳过。
  Future<({List<ShardInput> available, List<CatalogManifestShard> missing})>
  resolveShards(CatalogManifest manifest) async {
    final available = <ShardInput>[];
    final missing = <CatalogManifestShard>[];
    for (final shard in manifest.shards) {
      final path = shardPath(shard.file);
      if (File(path).existsSync()) {
        available.add(ShardInput(meta: shard, path: path));
      } else {
        missing.add(shard);
      }
    }
    return (available: available, missing: missing);
  }

  Future<void> _writeAtomically(File target, Uint8List bytes) async {
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(bytes, flush: true);
    // 目标文件只会在字节全部落盘后出现；中途被杀掉时留下的是 .tmp。
    await temp.rename(target.path);
  }

  Future<Map<String, String>> _readMarker() async {
    final file = File(_markerPath);
    if (!await file.exists()) return <String, String>{};
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return <String, String>{};
      return {
        for (final entry in raw.entries)
          if (entry.value is String)
            entry.key.toString(): entry.value as String,
      };
    } on FormatException {
      // 标记文件坏了就当作没有：最坏情况是重新复制一次分片。
      return <String, String>{};
    }
  }

  Future<void> _writeMarker(Map<String, String> marker) async {
    final temp = File('$_markerPath.tmp');
    await temp.writeAsString(jsonEncode(marker), flush: true);
    await temp.rename(_markerPath);
  }
}
