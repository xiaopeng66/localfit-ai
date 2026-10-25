import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/retrieval/application/feedback_store.dart';

/// 反馈的落库读（`app_settings` KV；**不新增表**）。
///
/// 为什么不用新表：`docs/41` §11 是数据库变更的白名单，反馈表不在里面。
/// 一张「菜名 → 两个计数」的映射用 KV + JSON 完全够用，也天然不进备份的
/// 结构变更面（`app_settings` 本来就在备份里）。
final class FeedbackRepository {
  const FeedbackRepository({required this.database});

  final AppDatabase database;

  Future<FeedbackStore> load() async {
    final row = await (database.select(
      database.appSettings,
    )..where((item) => item.key.equals(kFeedbackStoreKey))).getSingleOrNull();
    return FeedbackStore.decode(row?.value);
  }

  Future<void> save(FeedbackStore store) async {
    await database
        .into(database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: kFeedbackStoreKey,
            value: store.encode(),
          ),
        );
  }

  /// 记一次反馈并落库，返回最新存储（调用方用于刷新排序）。
  Future<FeedbackStore> record(String dishName, FeedbackVote vote) async {
    final store = await load();
    store.record(dishName, vote);
    await save(store);
    return store;
  }
}
