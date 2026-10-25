import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/features/ai_conversation/data/file_chat_image_store.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:path/path.dart' as path;

/// 聊天图片仓库（docs/21 §5.7）：落在**应用文档目录**（不是可被系统回收的
/// 临时目录），删除不许越出聊天目录，整目录清理留给「清除全部本地数据」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documents;
  late FileChatImageStore store;

  setUp(() {
    documents = Directory.systemTemp.createTempSync('localfit-chat-image-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return documents.path;
          }
          return null;
        });
    store = FileChatImageStore(idGenerator: _Ids());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (documents.existsSync()) documents.deleteSync(recursive: true);
  });

  String chatDir() => path.join(documents.path, 'localfit_ai', 'chat_images');

  test('save 落在文档目录的聊天子目录，文件名可读且不留 .partial', () async {
    final saved = await store.save(
      _image(),
      createdAt: DateTime(2026, 10, 1, 15, 30, 12),
    );

    expect(saved.fileName, 'photo_20261001_153012_abc1.jpg');
    expect(saved.path, path.join(chatDir(), saved.fileName));
    expect(saved.width, 120);
    expect(saved.height, 90);
    expect(File(saved.path).readAsBytesSync(), _bytes);
    // 原子写：临时文件必须已经改名，不留残骸。
    expect(File('${saved.path}.partial').existsSync(), isFalse);
    expect(Directory(chatDir()).listSync(), hasLength(1));
  });

  test('同一秒内两次 save 不互相覆盖（后缀取随机段）', () async {
    final at = DateTime(2026, 10, 1, 15, 30, 12);
    final first = await store.save(_image(), createdAt: at);
    final second = await store.save(_other(), createdAt: at);

    expect(first.path, isNot(second.path));
    expect(first.fileName, isNot(second.fileName));
    expect(File(first.path).readAsBytesSync(), _bytes);
    expect(File(second.path).readAsBytesSync(), _otherBytes);
  });

  test('id 生成器恒定 + 同一秒：宁可报错也不覆盖已有图片', () async {
    final stubborn = FileChatImageStore(idGenerator: _ConstantIds());
    final at = DateTime(2026, 10, 1, 15, 30, 12);
    final first = await stubborn.save(_image(), createdAt: at);

    await expectLater(
      stubborn.save(_other(), createdAt: at),
      throwsA(
        isA<ChatImageFailure>().having(
          (failure) => failure.message,
          'message',
          contains('命名冲突'),
        ),
      ),
    );
    // 第一张图必须完好（没被静默覆盖）。
    expect(File(first.path).readAsBytesSync(), _bytes);
  });

  test('delete 删掉目录内的图片', () async {
    final saved = await store.save(_image(), createdAt: DateTime(2026, 10, 1));

    await store.delete(saved.path);

    expect(File(saved.path).existsSync(), isFalse);
  });

  test('delete 拒绝聊天目录之外的路径（防越权删除）', () async {
    final outside = File(path.join(documents.path, 'outside.jpg'))
      ..writeAsBytesSync(const [1, 2, 3]);

    await expectLater(
      store.delete(outside.path),
      throwsA(
        isA<ChatImageFailure>().having(
          (failure) => failure.message,
          'message',
          contains('拒绝删除'),
        ),
      ),
    );
    expect(outside.existsSync(), isTrue);
  });

  test('delete 不存在的文件静默成功（用户可能已从文件管理器删过）', () async {
    await store.delete(path.join(chatDir(), 'nope.jpg'));

    // 没抛异常即通过。
  });

  test('exists 如实报告文件在不在', () async {
    final saved = await store.save(_image(), createdAt: DateTime(2026, 10, 1));

    expect(await store.exists(saved.path), isTrue);
    await File(saved.path).delete();
    expect(await store.exists(saved.path), isFalse);
    expect(await store.exists(path.join(chatDir(), 'nope.jpg')), isFalse);
  });

  test('clearAll 整目录清空，且再调一次不报错（幂等）', () async {
    final saved = await store.save(_image(), createdAt: DateTime(2026, 10, 1));
    final leftovers = File(path.join(chatDir(), 'sub', 'stray.txt'))
      ..createSync(recursive: true);

    await store.clearAll();

    expect(Directory(chatDir()).existsSync(), isFalse);
    expect(File(saved.path).existsSync(), isFalse);
    expect(leftovers.existsSync(), isFalse);

    await store.clearAll(); // 幂等
  });

  test('clearAll 不创建目录（清理不该反过来新建目录）', () async {
    await store.clearAll();

    expect(Directory(chatDir()).existsSync(), isFalse);
  });

  test('路径不可用（被同名文件占位）时报 ChatImageFailure，不是原始 IO 异常', () async {
    // 用文件占住 chat_images 这个路径：目录建不出来。
    File(chatDir()).createSync(recursive: true);

    await expectLater(
      store.save(_image(), createdAt: DateTime(2026, 10, 1)),
      throwsA(isA<ChatImageFailure>()),
    );
    expect(File(chatDir()).existsSync(), isTrue); // 占位文件没被误删
  });

  test('清除占位文件后 clearAll 仍能收尾（异常状态不卡住全清）', () async {
    File(chatDir()).createSync(recursive: true);

    await store.clearAll();

    expect(File(chatDir()).existsSync(), isFalse);
  });
}

final _bytes = Uint8List.fromList(const [1, 2, 3, 4]);
final _otherBytes = Uint8List.fromList(const [9, 9, 9]);

ProcessedMealImage _image() =>
    ProcessedMealImage(bytes: _bytes, width: 120, height: 90);

ProcessedMealImage _other() =>
    ProcessedMealImage(bytes: _otherBytes, width: 120, height: 90);

/// 可预测 id：尾部不同即可（真实实现是 UuidV7，尾段随机）。
final class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String next() => '01926f5e-0000-7000-8000-0000000abc${++_next}';
}

/// 恒定 id：用来证明「撞名不覆盖」这条底线。
final class _ConstantIds implements IdGenerator {
  @override
  String next() => '01926f5e-0000-7000-8000-000000000000';
}
