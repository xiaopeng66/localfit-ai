import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';
import 'package:localfit_ai/features/backup/application/clear_all_local_data.dart';
import 'package:localfit_ai/features/campus_menus/domain/menu_raw_content_store.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/main.dart' show createAppDataClearer;

/// RV-P1-08：「清除全部本地数据」的生产装配必须把 `dishImageStore` 传下去。
///
/// 2026-10-08 曾修过一次（`ClearAllLocalData` 支持该参数），但
/// `createAppDataClearer` 组合函数漏传 ⇒ 参数恒 null ⇒ 用户拍的菜品照片残留。
/// 这里直接调**生产组合函数**，用一个记录型实现断言它真的被调用。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('生产装配会把菜品照片清理口传进 ClearAllLocalData', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dishStore = _RecordingDishImageStore();

    final clearer = createAppDataClearer(
      database,
      temporaryMealImageStore: _NoopTemporaryMealImageStore(),
      menuRawContentStore: _NoopMenuRawContentStore(),
      apiKeyStore: _NoopApiKeyStore(),
      chatImageStore: _NoopChatImageStore(),
      dishImageStore: dishStore,
      avatarImageStore: _NoopAvatarImageStore(),
    );
    await clearer.clear();

    expect(dishStore.clearAllCalls, 1, reason: '全清必须清菜品照片（漏传时这里会是 0）');
  });
}

final class _RecordingDishImageStore implements DishImageStoreRef {
  int clearAllCalls = 0;

  @override
  Future<void> clearAll() async {
    clearAllCalls++;
  }
}

final class _NoopTemporaryMealImageStore implements TemporaryMealImageStore {
  @override
  Future<void> clearAll() async {}

  @override
  Future<void> clearStale() async {}

  @override
  Future<void> delete(PreparedMealImage image) async {}

  @override
  Future<PreparedMealImage> save(ProcessedMealImage image) async =>
      throw UnimplementedError();
}

final class _NoopMenuRawContentStore implements MenuRawContentStore {
  @override
  Future<void> clearAll() async {}

  @override
  String resolve(String relativePath) => relativePath;

  @override
  Future<String> save({
    required String snapshotId,
    required String rawText,
  }) async => 'menu_raw/$snapshotId.raw';
}

final class _NoopChatImageStore implements ChatImageStore {
  @override
  Future<void> clearAll() async {}

  @override
  Future<void> delete(String path) async {}

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<ChatImage> save(
    ProcessedMealImage image, {
    required DateTime createdAt,
  }) async =>
      const ChatImage(path: '', fileName: 'noop.jpg', width: 1, height: 1);
}

final class _NoopAvatarImageStore implements AvatarImageStoreRef {
  @override
  Future<void> clearAll() async {}
}

final class _NoopApiKeyStore implements AiApiKeyStoreRef {
  @override
  Future<void> clear() async {}
}
