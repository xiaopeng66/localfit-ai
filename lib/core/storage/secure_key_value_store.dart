import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class PlatformSecureKeyValueStore implements SecureKeyValueStore {
  PlatformSecureKeyValueStore({FlutterSecureStorage? storage})
    : storage =
          storage ??
          FlutterSecureStorage(
            aOptions: const AndroidOptions(resetOnError: false),
            // DB 密钥与 API Key 必须留在本机：默认 unlocked 可访问级别会把
            // 条目连同加密数据库一起带进 iTunes 加密备份并随恢复迁移到
            // 其他设备，与「数据不出设备」的硬约束冲突。
            iOptions: const IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}
