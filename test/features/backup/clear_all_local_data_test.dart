import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/storage/secure_key_value_store.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/backup/application/export_localfit_data.dart';
import 'package:localfit_ai/features/backup/application/restore_localfit_data.dart';
import 'package:localfit_ai/features/campus_menus/data/file_menu_raw_content_store.dart';
import 'package:localfit_ai/features/campus_menus/domain/menu_raw_content_store.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/settings/data/ai_api_key_store.dart';

import '../../support/food_fixture.dart';

/// 2.0-0 clear-safety base tests: a full clear must delete database rows,
/// cached scan media, and the AI API key; a restore must only clear database
/// rows; and any failure must leave the previous state intact.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late _FakeTemporaryMealImageStore imageStore;
  late _MemorySecureStore secureStore;
  late Directory rawDir;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    imageStore = _FakeTemporaryMealImageStore();
    secureStore = _MemorySecureStore();
    rawDir = Directory.systemTemp.createTempSync('localfit-clear-raw-');
    final now = DateTime.utc(2026, 9, 15, 10);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
          ),
        );
  });

  tearDown(() async {
    await database.close();
    if (rawDir.existsSync()) rawDir.deleteSync(recursive: true);
  });

  ClearAllLocalData createClear() => ClearAllLocalData(
    database,
    temporaryMealImageStore: imageStore,
    menuRawContentStore: FileMenuRawContentStore(rawDir.path),
    apiKeyStore: AiApiKeyStore(store: secureStore),
  );

  /// 2026-10-23 用户：清除本地数据不清内置食物（导入行也是内置）。
  Future<void> seedUserCreatedFood() async {
    final now = DateTime.utc(2026, 9, 15, 10);
    await database
        .into(database.foods)
        .insert(
          FoodsCompanion.insert(
            id: 'user-food-1',
            name: '我的自建食物',
            kcalPer100g: 120,
            proteinPer100g: 2,
            carbsPer100g: 20,
            fatPer100g: 3,
            source: 'user',
            isUserCreated: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  test('a full clear removes user rows, keeps builtin foods, media, and the AI API key', () async {
    await AiApiKeyStore(store: secureStore).save('secret');
    await seedUserCreatedFood();

    await createClear().clear();

    expect(await database.select(database.profiles).get(), isEmpty);
    final foods = await database.select(database.foods).get();
    expect(foods, isNotEmpty, reason: '内置食物库保留');
    expect(
      foods.every((row) => !row.isUserCreated),
      isTrue,
      reason: '自建食物被清、内置食物留下',
    );
    expect(
      foods.any((row) => row.id == 'user-food-1'),
      isFalse,
      reason: 'App 内新建的那条必须被清掉',
    );
    expect(imageStore.clearAllCalls, 1);
    expect(secureStore.values.containsKey(AiApiKeyStore.storageKey), isFalse);
  });

  test(
    'a restore only clears database rows, keeping media and the API key',
    () async {
      await AiApiKeyStore(store: secureStore).save('secret');
      final backup = await ExportLocalFitData(database).exportJson();

      await RestoreLocalFitData(database).restore(backup);

      expect(
        (await database.select(database.profiles).get()).single.id,
        'profile-1',
      );
      expect(imageStore.clearAllCalls, 0);
      expect(secureStore.values[AiApiKeyStore.storageKey], 'secret');
    },
  );

  test('a restore with a bad payload leaves existing rows untouched', () async {
    final before = await database.select(database.profiles).get();
    final badBackup = '{not-valid-json}'.codeUnits;

    expect(
      () => RestoreLocalFitData(database).restore(_bytes(badBackup)),
      throwsFormatException,
    );

    expect(await database.select(database.profiles).get(), before);
  });

  test(
    'a clear without optional dependencies still removes all user rows',
    () async {
      await seedUserCreatedFood();
      await ClearAllLocalData(database).clear();

      expect(await database.select(database.profiles).get(), isEmpty);
      final foods = await database.select(database.foods).get();
      expect(foods, isNotEmpty, reason: '内置食物保留');
      expect(foods.every((row) => !row.isUserCreated), isTrue);
    },
  );

  test('a full clear also removes imported menu raw text', () async {
    final rawStore = FileMenuRawContentStore(rawDir.path);
    await rawStore.save(snapshotId: 'snap-1', rawText: '鸡蛋炒饭 800');

    await createClear().clear();

    expect(File(rawStore.resolve('menu_raw/snap-1.raw')).existsSync(), isFalse);
  });

  test('a restore keeps imported menu raw text', () async {
    final rawStore = FileMenuRawContentStore(rawDir.path);
    await rawStore.save(snapshotId: 'snap-1', rawText: '鸡蛋炒饭 800');
    final backup = await ExportLocalFitData(database).exportJson();

    await RestoreLocalFitData(database).restore(backup);

    expect(File(rawStore.resolve('menu_raw/snap-1.raw')).existsSync(), isTrue);
  });

  test('media cleanup failure surfaces instead of being swallowed', () async {
    final clear = ClearAllLocalData(
      database,
      temporaryMealImageStore: _ThrowingMealImageStore(),
      apiKeyStore: AiApiKeyStore(store: secureStore),
    );

    await expectLater(clear.clear(), throwsA(isA<MealImageFailure>()));

    // 数据库行已删除（先于媒体清理）；失败显式冒出而不是被吞掉。
    expect(await database.select(database.profiles).get(), isEmpty);
  });

  test(
    'menu raw cleanup failure surfaces instead of being swallowed',
    () async {
      final clear = ClearAllLocalData(
        database,
        temporaryMealImageStore: imageStore,
        menuRawContentStore: _ThrowingMenuRawContentStore(),
        apiKeyStore: AiApiKeyStore(store: secureStore),
      );

      await expectLater(clear.clear(), throwsA(isA<MenuRawContentFailure>()));

      expect(await database.select(database.profiles).get(), isEmpty);
    },
  );

  test('a full clear also removes chat images', () async {
    final chatImages = _FakeChatImageStore();

    await ClearAllLocalData(
      database,
      temporaryMealImageStore: imageStore,
      chatImageStore: chatImages,
      apiKeyStore: AiApiKeyStore(store: secureStore),
    ).clear();

    expect(chatImages.clearAllCalls, 1);
  });

  test('clearDatabaseRowsOnly（还原前）不动聊天图片', () async {
    final chatImages = _FakeChatImageStore();

    await ClearAllLocalData(
      database,
      chatImageStore: chatImages,
    ).clearDatabaseRowsOnly();

    expect(chatImages.clearAllCalls, 0);
  });

  // 菜品照片（docs/29 §P7 需求 16）与聊天图片同类：文件不是行，只清库
  // 删不掉。此前 `DishImageStore` 连 clearAll 都没有、也没接到全清流程上，
  // 于是「清除全部本地数据」之后用户拍的每一张菜品照片都还在私有目录里。
  test('a full clear also removes dish photos', () async {
    final dishImages = _FakeDishImageStore();

    await ClearAllLocalData(database, dishImageStore: dishImages).clear();

    expect(dishImages.clearAllCalls, 1);
  });

  test('clearDatabaseRowsOnly（还原前）不动菜品照片', () async {
    final dishImages = _FakeDishImageStore();

    await ClearAllLocalData(
      database,
      dishImageStore: dishImages,
    ).clearDatabaseRowsOnly();

    expect(dishImages.clearAllCalls, 0);
  });

  // ── 全清必须覆盖全部表（docs/21 §5.8.1）────────────────────────────────
  //
  // 缺陷背景：schema 17 新增的 7 张表（水 / 成就 / 菜品库 / 心血管处方 /
  // 识别结果 / 聊天记录 / 设置）曾整批漏在人工维护的删除清单之外——
  // 「清除全部本地数据」清完，这些数据还留在盘上。修法是加一轮
  // `database.allTables` 全表兜底，所以下面的断言也按**全表**扫，
  // 以后新增表自动纳入（不再靠人工清单）。

  test(
    'a full clear empties every table except the preserved builtin foods',
    () async {
      final seeded = await _seedPreviouslyMissedTables(database);
      seeded['foods'] = (await database.select(database.foods).get()).length;
      seeded['profiles'] =
          (await database.select(database.profiles).get()).length;
      await seedUserCreatedFood();
      // 先证明种子真的写进去了：否则「清空后为空」可能只是因为从来没写过。
      for (final entry in seeded.entries) {
        expect(entry.value, greaterThan(0), reason: '${entry.key} 的种子没落库');
      }

      await createClear().clear();

      // 2026-10-23 用户：内置食物（含导入）要活过全清；食物五表是显式例外。
      const preservedFoodTables = {
        'foods',
        'food_aliases',
        'food_nutrition_revisions',
        'food_portions',
        'food_evidence',
      };
      final leftover = <String>[];
      for (final table in database.allTables) {
        if (preservedFoodTables.contains(table.actualTableName)) continue;
        final rows = await database.select(table).get();
        if (rows.isNotEmpty) {
          leftover.add('${table.actualTableName}=${rows.length}');
        }
      }
      expect(leftover, isEmpty, reason: '全清后仍有残留：$leftover');

      // 例外本身也要有判据：内置行在、自建行没了。
      final foods = await database.select(database.foods).get();
      expect(foods, isNotEmpty, reason: '内置食物保留');
      expect(
        foods.any((row) => row.id == 'user-food-1'),
        isFalse,
        reason: '自建食物必须被清',
      );
    },
  );

  test('还原前清行也覆盖全部表（否则旧数据会混进恢复后的库）', () async {
    final seeded = await _seedPreviouslyMissedTables(database);
    expect(seeded, isNotEmpty);

    await ClearAllLocalData(database).clearDatabaseRowsOnly();

    for (final table in database.allTables) {
      expect(
        await database.select(table).get(),
        isEmpty,
        reason: '${table.actualTableName} 没被清空',
      );
    }
  });

  test('曾漏掉的表逐个点名清空（回归锚点，不是全表扫描的替代）', () async {
    await _seedPreviouslyMissedTables(database);

    await createClear().clear();

    expect(await database.select(database.waterIntakes).get(), isEmpty);
    expect(await database.select(database.achievements).get(), isEmpty);
    expect(await database.select(database.dishLibrary).get(), isEmpty);
    expect(await database.select(database.recognitionResults).get(), isEmpty);
    expect(await database.select(database.conversationMessages).get(), isEmpty);
    expect(await database.select(database.appSettings).get(), isEmpty);
  });
}

/// 往「schema 17 曾漏掉」的表里各写一行（CardioPrescriptions 需要先造
/// 训练计划整条外键链，代价过高，由全表扫描覆盖）。
///
/// 返回各表写入的行数，供调用方断言种子非空。
Future<Map<String, int>> _seedPreviouslyMissedTables(
  AppDatabase database,
) async {
  final now = DateTime.utc(2026, 9, 30, 12);
  await database
      .into(database.waterIntakes)
      .insert(
        WaterIntakesCompanion.insert(
          id: 'water-1',
          localDate: '2026-09-30',
          amountMl: 250,
          recordedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.achievements)
      .insert(AchievementsCompanion.insert(id: 'achievement-1', key: 'first'));
  await database
      .into(database.dishLibrary)
      .insert(
        DishLibraryCompanion.insert(
          id: 'dish-1',
          name: '鸡蛋炒饭',
          mealSlot: '午餐',
          kcal: 600,
          proteinG: 20,
          carbsG: 80,
          fatG: 15,
          source: 'canteen',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.recognitionResults)
      .insert(
        RecognitionResultsCompanion.insert(
          id: 'recognition-1',
          capturedAt: now,
          dishName: '鸡蛋炒饭',
          confidence: 0.8,
          imagePath: '/tmp/photo.jpg',
          estimatedKcal: 600,
          ingredientsJson: '[]',
          macroJson: '{}',
        ),
      );
  await database
      .into(database.conversationMessages)
      .insert(
        ConversationMessagesCompanion.insert(
          id: 'message-1',
          sessionId: 'default',
          role: 'user',
          textContent: '在吗',
          createdAt: now,
          status: 'sent',
        ),
      );
  await database
      .into(database.appSettings)
      .insert(AppSettingsCompanion.insert(key: 'auto_backup', value: 'on'));
  return {
    'waterIntakes': 1,
    'achievements': 1,
    'dishLibrary': 1,
    'recognitionResults': 1,
    'conversationMessages': 1,
    'appSettings': 1,
  };
}

final class _FakeChatImageStore implements ChatImageStore {
  int clearAllCalls = 0;

  @override
  Future<void> clearAll() async => clearAllCalls += 1;

  @override
  Future<void> delete(String path) async {}

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<ChatImage> save(
    ProcessedMealImage image, {
    required DateTime createdAt,
  }) async => throw UnimplementedError();
}

final class _ThrowingMenuRawContentStore implements MenuRawContentStore {
  @override
  Future<void> clearAll() async {
    throw const MenuRawContentFailure('本地菜单原文清理失败，请重试。');
  }

  @override
  String resolve(String relativePath) => relativePath;

  @override
  Future<String> save({
    required String snapshotId,
    required String rawText,
  }) async => throw UnimplementedError();
}

Uint8List _bytes(List<int> codeUnits) => Uint8List.fromList(codeUnits);

final class _FakeTemporaryMealImageStore implements TemporaryMealImageStore {
  int clearStaleCalls = 0;
  int clearAllCalls = 0;

  @override
  Future<void> clearStale() async {
    clearStaleCalls += 1;
  }

  @override
  Future<void> clearAll() async {
    clearAllCalls += 1;
  }

  @override
  Future<void> delete(PreparedMealImage image) async {}

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async =>
      throw UnimplementedError();
}

final class _ThrowingMealImageStore implements TemporaryMealImageStore {
  @override
  Future<void> clearStale() async {}

  @override
  Future<void> clearAll() async {
    throw const MealImageFailure('清理失败');
  }

  @override
  Future<void> delete(PreparedMealImage image) async {}

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async =>
      throw UnimplementedError();
}

final class _MemorySecureStore implements SecureKeyValueStore {
  final values = <String, String?>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

/// 记录调用次数的假菜品照片存储：只验证全清是否真的去清了文件
/// （真实文件 IO 由 `dish_image_store_test` 覆盖）。
final class _FakeDishImageStore implements DishImageStoreRef {
  int clearAllCalls = 0;

  @override
  Future<void> clearAll() async => clearAllCalls += 1;
}
