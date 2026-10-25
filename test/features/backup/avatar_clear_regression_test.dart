import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/data/file_chat_image_store.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/campus_menus/data/dish_image_store.dart';
import 'package:localfit_ai/features/campus_menus/data/file_menu_raw_content_store.dart';
import 'package:localfit_ai/features/food_scan/data/temporary_meal_image_store.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';
import 'package:localfit_ai/features/settings/data/avatar_image_store.dart';
import 'package:localfit_ai/main.dart' show createAppDataClearer;
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  const store = AvatarImageStore(idGenerator: UuidV7Generator());
  final now = DateTime.utc(2026, 10, 13);
  late AppDatabase database;
  late Directory sandbox;
  late Directory documents;
  var failDocumentLookup = false;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    sandbox = Directory.systemTemp.createTempSync('localfit-avatar-clear-');
    documents = Directory(path.join(sandbox.path, 'documents'))..createSync();
    failDocumentLookup = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            if (failDocumentLookup) {
              throw PlatformException(code: 'private-directory-unavailable');
            }
            return documents.path;
          }
          if (call.method == 'getTemporaryDirectory') {
            return path.join(sandbox.path, 'cache');
          }
          throw StateError('Unexpected path request: ${call.method}');
        });
  });

  tearDown(() async {
    await database.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  String avatarDirectory() =>
      path.join(documents.path, 'localfit_ai', 'avatar');

  // main 使用的生产组合：漏注入头像清理时，真实文件断言会失败。
  ClearAllLocalData clearUseCase() => createAppDataClearer(
    database,
    temporaryMealImageStore: const FileTemporaryMealImageStore(
      idGenerator: UuidV7Generator(),
    ),
    menuRawContentStore: FileMenuRawContentStore(
      path.join(sandbox.path, 'support'),
    ),
    apiKeyStore: AiApiKeyStore(store: _MemorySecureStore()),
    chatImageStore: const FileChatImageStore(idGenerator: UuidV7Generator()),
    dishImageStore: const DishImageStore(idGenerator: UuidV7Generator()),
  );

  Future<void> seedProfile(String avatarPath) => database
      .into(database.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: 'avatar-clear-profile',
          activityLevel: 'moderate',
          avatarPath: Value(avatarPath),
          createdAt: now,
          updatedAt: now,
        ),
      );

  test('full clear removes private avatar bytes and leaves unrelated files', () async {
    final source = File(path.join(sandbox.path, 'gallery.png'))
      ..writeAsBytesSync([1, 2, 3, 4]);
    final saved = await store.copyBytes(
      source.readAsBytesSync(),
      createdAt: now,
    );
    final orphan = File(path.join(avatarDirectory(), 'old-avatar.png'))
      ..writeAsBytesSync([5, 6]);
    final partial = File(path.join(avatarDirectory(), 'unfinished.partial'))
      ..writeAsBytesSync([7]);
    final unrelated = File(path.join(documents.path, 'localfit_ai', 'keep.txt'))
      ..writeAsStringSync('unrelated document');
    final backup = File(path.join(sandbox.path, 'exported.lfb'))
      ..writeAsBytesSync([8, 9]);
    await seedProfile(saved);

    await clearUseCase().clear();

    for (final table in database.allTables) {
      expect(await database.select(table).get(), isEmpty);
    }
    expect(
      File(saved).existsSync(),
      isFalse,
      reason:
          'Deleting the profile row must also remove its private avatar bytes.',
    );
    expect(orphan.existsSync(), isFalse);
    expect(partial.existsSync(), isFalse);
    expect(Directory(avatarDirectory()).existsSync(), isFalse);
    expect(source.readAsBytesSync(), [1, 2, 3, 4]);
    expect(unrelated.readAsStringSync(), 'unrelated document');
    expect(backup.readAsBytesSync(), [8, 9]);
  });

  test(
    'full clear uses the private directory rather than stored profile paths',
    () async {
      final outside = File(path.join(sandbox.path, 'outside.png'))
        ..writeAsBytesSync([11, 12]);
      final saved = await store.copyBytes(
        Uint8List.fromList([13, 14]),
        createdAt: now,
      );
      await seedProfile(outside.path);

      await clearUseCase().clear();

      expect(await database.select(database.profiles).get(), isEmpty);
      expect(File(saved).existsSync(), isFalse);
      expect(outside.readAsBytesSync(), [11, 12]);
    },
  );

  test('database-only clear preserves avatar files for restore', () async {
    final saved = await store.copyBytes(
      Uint8List.fromList([21, 22]),
      createdAt: now,
    );
    await seedProfile(saved);

    await clearUseCase().clearDatabaseRowsOnly();

    expect(await database.select(database.profiles).get(), isEmpty);
    expect(File(saved).readAsBytesSync(), [21, 22]);
  });

  test(
    'missing avatar directory remains absent after repeated full clear',
    () async {
      await clearUseCase().clear();
      await clearUseCase().clear();

      expect(Directory(avatarDirectory()).existsSync(), isFalse);
      expect(
        Directory(path.join(documents.path, 'localfit_ai')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'full clear removes a stray file occupying only the avatar directory path',
    () async {
      Directory(path.join(documents.path, 'localfit_ai')).createSync();
      final stray = File(avatarDirectory())..writeAsBytesSync([31]);
      final sibling = File(path.join(documents.path, 'localfit_ai', 'keep.txt'))
        ..writeAsStringSync('keep');

      await clearUseCase().clear();

      expect(stray.existsSync(), isFalse);
      expect(sibling.readAsStringSync(), 'keep');
    },
  );

  test(
    'avatar cleanup failure is reported after the database commit',
    () async {
      final saved = await store.copyBytes(
        Uint8List.fromList([41, 42]),
        createdAt: now,
      );
      await seedProfile(saved);
      failDocumentLookup = true;

      await expectLater(
        ClearAllLocalData(database, avatarImageStore: store).clear(),
        throwsA(
          isA<AvatarStoreException>().having(
            (error) => error.message,
            'message',
            '本地头像清理失败，请重试。',
          ),
        ),
      );

      expect(await database.select(database.profiles).get(), isEmpty);
      expect(File(saved).readAsBytesSync(), [41, 42]);
    },
  );
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}
