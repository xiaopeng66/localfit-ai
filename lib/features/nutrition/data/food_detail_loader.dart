import 'package:localfit_ai/features/nutrition/data/catalog_shard_detail_source.dart';
import 'package:localfit_ai/features/nutrition/data/food_detail_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/food_detail.dart';

/// 食物详情路由（2.0-1j）：搜索结果里的行有两个来源，读的地方不一样。
///
/// - `source == 'main'`：主库（用户自建、种子、已导入的目录条目）→ 读 SQLCipher 主库；
/// - `source == 'catalog'`：只在分片里（还没导入）→ 读分片文件；分片里没有
///   （用户把分片删了/换了版本）时回主库再找一次，仍没有就如实返回 null。
///
/// 界面拿到的都是同一个 [FoodDetail]，不关心是哪来的。
final class FoodDetailLoader {
  const FoodDetailLoader({required this.databaseDetails, this.shardDetails});

  final FoodDetailRepository databaseDetails;

  /// 没配分片（例如没随包目录的开发构建）时只为 null：详情退化成主库一档。
  final CatalogShardDetailSource? shardDetails;

  Future<FoodDetail?> load(String foodId, {required String source}) async {
    if (source == 'catalog') {
      final fromShard = await shardDetails?.load(foodId);
      if (fromShard != null) return fromShard;
    }
    return databaseDetails.load(foodId);
  }
}
