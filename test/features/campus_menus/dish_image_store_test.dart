import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/features/campus_menus/data/dish_image_store.dart';
import 'package:path/path.dart' as path;

/// 菜品照片仓库（docs/29 §P7 需求 16）：与聊天图片同一个模式——存进
/// **应用文档目录**的 `localfit_ai/dish_images/`，原子写（partial + rename），
/// 删除不许越出本目录。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;
  late DishImageStore store;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('localfit-dish-image-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents.path;
          }
          return null;
        });
    store = DishImageStore(idGenerator: _Ids());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  String dishDir() => path.join(documents.path, 'localfit_ai', 'dish_images');

  test('copyBytes 落在文档目录的菜品子目录，文件名可读且不留 .partial', () async {
    final saved = await store.copyBytes(
      _bytes(4),
      createdAt: DateTime(2026, 10, 6, 15, 30, 12),
    );

    expect(saved, path.join(dishDir(), 'dish_20261006_153012_0001.jpg'));
    expect(File(saved).readAsBytesSync(), _bytes(4));
    expect(File('$saved.partial').existsSync(), isFalse);
    expect(Directory(dishDir()).listSync(), hasLength(1));
  });

  test('扩展名走白名单：非法后缀回落 .jpg，合法后缀保留', () async {
    final weird = await store.copyBytes(
      _bytes(2),
      createdAt: DateTime(2026, 10, 6, 9, 0, 0),
      extension: '../evil',
    );
    expect(weird, endsWith('.jpg'));

    final png = await store.copyBytes(
      _bytes(2),
      createdAt: DateTime(2026, 10, 6, 9, 0, 1),
      extension: '.png',
    );
    expect(png, endsWith('.png'));
  });

  test('同一秒内两次写入不互相覆盖（后缀取随机段）', () async {
    final at = DateTime(2026, 10, 6, 15, 30, 12);
    final first = await store.copyBytes(_bytes(1), createdAt: at);
    final second = await store.copyBytes(_bytes(2), createdAt: at);

    expect(first, isNot(second));
    expect(File(first).existsSync(), isTrue);
    expect(File(second).existsSync(), isTrue);
  });

  test('deleteQuietly 只删本目录内的文件', () async {
    final saved = await store.copyBytes(
      _bytes(3),
      createdAt: DateTime(2026, 10, 6, 8, 0, 0),
    );
    await store.deleteQuietly(saved);
    expect(File(saved).existsSync(), isFalse);

    // 目录外的文件（含 ../ 逃逸）必须原样保留 —— 备份包塞进来的恶意路径
    // 不能在恢复后被删掉。
    final outside = File(path.join(documents.path, 'outside.jpg'))
      ..writeAsBytesSync(_bytes(1));
    await store.deleteQuietly(outside.path);
    await store.deleteQuietly('../evil.jpg');
    await store.deleteQuietly(null);
    expect(outside.existsSync(), isTrue);
  });

  test('目录不可写时报为 DishImageStoreException（原始 IO 异常不外泄）', () async {
    // 用一个同名文件占住 localfit_ai 目录路径，让 create(recursive) 失败。
    File(path.join(documents.path, 'localfit_ai')).writeAsBytesSync(_bytes(1));

    await expectLater(
      store.copyBytes(_bytes(1), createdAt: DateTime(2026, 10, 6)),
      throwsA(
        isA<DishImageStoreException>().having(
          (error) => error.userMessage,
          'userMessage',
          contains('无法保存照片'),
        ),
      ),
    );
  });

  // 「清除全部本地数据」承诺「不留任何用户字节」：照片是文件不是行，
  // 只清库删不掉，所以 store 必须自己能整目录清掉（2026-10-08 缺陷排查）。
  test('clearAll 整目录删掉菜品照片', () async {
    await store.copyBytes(
      _bytes(4),
      createdAt: DateTime(2026, 10, 6, 15, 30, 12),
    );
    await store.copyBytes(
      _bytes(5),
      createdAt: DateTime(2026, 10, 6, 15, 30, 13),
    );
    expect(Directory(dishDir()).listSync(), hasLength(2));

    await store.clearAll();

    expect(Directory(dishDir()).existsSync(), isFalse);
  });

  test('clearAll 在目录还不存在时不抛错、也不反过来创建目录', () async {
    await store.clearAll();

    expect(Directory(dishDir()).existsSync(), isFalse);
  });
}

Uint8List _bytes(int value) =>
    Uint8List.fromList(List<int>.filled(8, value % 256));

/// 固定序列 id（后缀取尾部 4 位，够区分同秒写入）。
final class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String next() {
    _next++;
    return 'aabbccdd-0000-7000-8000-00000000${_next.toString().padLeft(4, '0')}';
  }
}
