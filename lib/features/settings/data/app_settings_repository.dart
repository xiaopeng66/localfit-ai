import 'package:localfit_ai/data/database/app_database.dart';

/// 「我的」页的键值设置存取（docs/21 §7.2 `AppSettings`）。
///
/// 首个使用方是「自动本地备份」开关（裁决 ⑦：设计稿的「数据同步」降级为
/// 本地语义，开关值存本地设置，不引入任何云端含义）。
final class AppSettingsRepository {
  const AppSettingsRepository({required this.database});

  final AppDatabase database;

  static const autoBackupEnabledKey = 'auto_backup_enabled';
  static const lastBackupAtKey = 'last_backup_at_ms';

  Future<String?> getString(String key) async {
    final row = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setString(String key, String value) async {
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<void> remove(String key) async {
    await (database.delete(
      database.appSettings,
    )..where((row) => row.key.equals(key))).go();
  }

  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final value = await getString(key);
    if (value == null) return defaultValue;
    return value == 'true';
  }

  Future<void> setBool(String key, {required bool value}) =>
      setString(key, value ? 'true' : 'false');
}
