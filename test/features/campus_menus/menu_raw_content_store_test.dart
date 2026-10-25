import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/campus_menus/data/file_menu_raw_content_store.dart';
import 'package:localfit_ai/features/campus_menus/domain/menu_raw_content_store.dart';
import 'package:path/path.dart' as path;

/// 2.0-7b：菜单原文存私有目录、数据库只存相对路径（docs/07 §6.1），
/// 清除全部本地数据时整目录删除。
void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('localfit-menuraw-');
  });
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('saving returns a relative path and writes inside the root', () async {
    final store = FileMenuRawContentStore(root.path);

    final relative = await store.save(
      snapshotId: 'snap-1',
      rawText: '鸡蛋炒饭 800',
    );

    expect(relative, '${FileMenuRawContentStore.directoryName}/snap-1.raw');
    expect(path.isAbsolute(relative), isFalse);
    expect(File(store.resolve(relative)).readAsStringSync(), '鸡蛋炒饭 800');
    // 文件确实落在应用私有根目录下，而不是当前工作目录。
    expect(
      path.isWithin(root.path, path.canonicalize(store.resolve(relative))),
      isTrue,
    );
  });

  test(
    'clearAll removes every saved raw file and is a no-op when empty',
    () async {
      final store = FileMenuRawContentStore(root.path);
      await store.save(snapshotId: 'snap-1', rawText: 'a');
      await store.save(snapshotId: 'snap-2', rawText: 'b');

      await store.clearAll();

      expect(
        File(
          store.resolve('${FileMenuRawContentStore.directoryName}/snap-1.raw'),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          store.resolve('${FileMenuRawContentStore.directoryName}/snap-2.raw'),
        ).existsSync(),
        isFalse,
      );
      // 二次调用（没有目录）不抛异常。
      await store.clearAll();
      expect(root.existsSync(), isTrue);
    },
  );

  test('clearAll also removes legacy root-level raw files', () async {
    final store = FileMenuRawContentStore(root.path);
    // 2.0-7b 之前写在根目录下的原文 + 一份不该被误删的非 .raw 文件。
    final legacy = File(path.join(root.path, 'snap-legacy.raw'))
      ..writeAsStringSync('旧原文');
    final unrelated = File(path.join(root.path, 'catalog.manifest.json'))
      ..writeAsStringSync('{}');

    await store.clearAll();

    expect(legacy.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });

  test('a legacy absolute path still resolves to the original file', () async {
    final store = FileMenuRawContentStore(root.path);
    final legacy = File(path.join(root.path, 'snap-legacy.raw'))
      ..writeAsStringSync('旧原文');

    expect(store.resolve(legacy.path), legacy.path);
    expect(File(store.resolve(legacy.path)).readAsStringSync(), '旧原文');
  });

  group('resolve 的目录边界（docs/25 §5 L1）', () {
    test('相对路径里的回退段被拒绝', () {
      final store = FileMenuRawContentStore(root.path);

      // 入库的路径可能来自被篡改/迁移的备份包：让恢复后的应用按
      // `../..` 读（或写）私有目录之外的文件，是拿备份当入口的越界读写。
      for (final escaping in [
        '../escape.raw',
        'menu_raw/../../escape.raw',
        r'..\escape.raw',
      ]) {
        expect(
          () => store.resolve(escaping),
          throwsA(isA<MenuRawContentFailure>()),
          reason: '$escaping 必须被拒绝',
        );
      }
    });

    test('历史绝对路径只在私有根目录下放行', () {
      final store = FileMenuRawContentStore(root.path);

      final legacy = path.join(root.path, 'snap-legacy.raw');
      expect(store.resolve(legacy), legacy);
      expect(
        () => store.resolve(path.join(path.dirname(root.path), 'evil.raw')),
        throwsA(isA<MenuRawContentFailure>()),
      );
    });

    test('正常相对路径仍落在根目录内', () {
      final store = FileMenuRawContentStore(root.path);

      final resolved = store.resolve('menu_raw/snap-1.raw');
      expect(path.isWithin(root.path, resolved), isTrue);
    });
  });

  test('a snapshot id cannot escape the raw content directory', () async {
    final store = FileMenuRawContentStore(root.path);

    await expectLater(
      store.save(snapshotId: '../escape', rawText: 'x'),
      throwsA(isA<MenuRawContentFailure>()),
    );
    await expectLater(
      store.save(snapshotId: '', rawText: 'x'),
      throwsA(isA<MenuRawContentFailure>()),
    );

    expect(
      File(path.join(path.dirname(root.path), 'escape.raw')).existsSync(),
      isFalse,
    );
  });
}
