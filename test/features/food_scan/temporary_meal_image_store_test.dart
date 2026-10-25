import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/features/food_scan/data/temporary_meal_image_store.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:path/path.dart' as path;

/// 临时餐照仓库：写入落在应用临时目录内、删除不越界、`clearStale` 只清
/// 过期文件，而「清除全部本地数据」走的是整目录清理 [clearAll]。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tempRoot;
  late FileTemporaryMealImageStore store;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('localfit-meal-image-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getTemporaryDirectory') return tempRoot.path;
          return null;
        });
    store = FileTemporaryMealImageStore(idGenerator: _Ids());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test(
    'save writes into the app temp directory and delete removes it',
    () async {
      final prepared = await store.save(_image());

      expect(prepared.path, contains(path.join('localfit_ai', 'meal_scan')));
      expect(File(prepared.path).existsSync(), isTrue);
      expect(prepared.byteLength, 3);

      await store.delete(prepared);

      expect(File(prepared.path).existsSync(), isFalse);
    },
  );

  test('delete refuses a path outside the app temp directory', () async {
    final outside = File(path.join(tempRoot.path, 'outside.jpg'))
      ..writeAsBytesSync(const [1, 2, 3]);

    await expectLater(
      store.delete(
        PreparedMealImage(
          path: outside.path,
          width: 1,
          height: 1,
          byteLength: 3,
        ),
      ),
      throwsA(isA<MealImageFailure>()),
    );

    expect(outside.existsSync(), isTrue);
  });

  test('clearStale removes only images older than the window', () async {
    final fresh = await store.save(_image());
    final stale = await store.save(_image());
    File(
      stale.path,
    ).setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 25)));

    await store.clearStale();

    expect(File(fresh.path).existsSync(), isTrue);
    expect(File(stale.path).existsSync(), isFalse);
  });

  test('clearAll removes freshly saved images, not just stale ones', () async {
    // 「清除全部本地数据」的规范是不留任何用户字节（docs 2.0 invariant）：
    // 用户十分钟前拍的餐照也是用户字节，不能靠 clearStale 的 24h 窗口留在盘上。
    final fresh = await store.save(_image());
    final leftover = File(path.join(path.dirname(fresh.path), 'x.partial'))
      ..writeAsBytesSync(const [9]);

    await store.clearAll();

    expect(File(fresh.path).existsSync(), isFalse);
    expect(leftover.existsSync(), isFalse);
  });
}

class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String next() => 'image-${++_next}';
}

ProcessedMealImage _image() => ProcessedMealImage(
  bytes: Uint8List.fromList(const [1, 2, 3]),
  width: 1,
  height: 1,
);
