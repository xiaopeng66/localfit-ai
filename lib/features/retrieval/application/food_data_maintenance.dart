import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/domain/ingredients.dart';
import 'package:localfit_ai/features/jobs/data/background_job_repository.dart';
import 'package:localfit_ai/features/retrieval/application/feedback_store.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/retrieval/data/feedback_repository.dart';

/// P4 整理工具（docs/41 P4 / G7）：批量打标、重复合并建议、反馈。
///
/// 三条纪律：
/// * **批量打标不调 AI**：用本地词典（`dictionaryIngredients`）离线跑，
///   猜测一律标 `dictionary`；AI 打标将来走同一个队列类型，不换写路径。
/// * **没有重复可整理**（2026-10-24 用户：「食堂目录和菜品库就是一个库」）：
///   食堂菜写出营养即自动进菜品库、按来源键更新，同名副本不再产生，
///   所以「整理重复菜品 / 关联到食堂菜品」整条功能下线。
/// * **反馈不静默**：只在用户点「不错/换一个」时写，样本不足不生效。

/// 批量打标结果。
final class BatchTaggingResult {
  const BatchTaggingResult({
    required this.tagged,
    required this.skipped,
    required this.enqueued,
  });

  final int tagged;
  final int skipped;

  /// 入队条数（走 `background_jobs`；离线词典路径为 0）。
  final int enqueued;
}

/// 批量整理工具。
final class FoodDataMaintenance {
  const FoodDataMaintenance({
    required this.database,
    required this.canteen,
    required this.jobs,
    this.semantic,
    this.memoryRepository,
  });

  final AppDatabase database;
  final CanteenRepository canteen;
  final BackgroundJobRepository jobs;

  /// 记忆向量索引（docs/43 B6）：恢复后重建覆盖 `ownerType='memory'`。
  final SemanticRuntime? semantic;
  final AiMemoryRepository? memoryRepository;

  /// 给**没有配料**的食堂菜跑一遍本地词典打标。
  ///
  /// [limit] 限流（一次最多处理多少道）；已确认/用户改过的菜**跳过**
  /// （不覆盖用户结果）。
  Future<BatchTaggingResult> tagCanteenDishesWithDictionary({
    int limit = 200,
  }) async {
    var tagged = 0;
    var skipped = 0;
    final windows = await canteen.listWindowsByVenue();
    for (final window in windows.values.expand((value) => value)) {
      for (final dish in window.dishes) {
        if (tagged >= limit) break;
        if (!dish.ingredients.isEmpty) {
          skipped++;
          continue;
        }
        final guess = dictionaryIngredients(dish.name);
        if (guess.isEmpty) {
          skipped++;
          continue;
        }
        await canteen.updateDishTagsAndIngredients(
          dishId: dish.id,
          tags: dish.tags,
          ingredients: CanteenIngredientInfo(entries: guess),
        );
        tagged++;
      }
    }
    return BatchTaggingResult(tagged: tagged, skipped: skipped, enqueued: 0);
  }

  /// 把「批量打标」入队（走 G11 调度：空闲即可跑，不必充电）。
  ///
  /// 幂等键固定 ⇒ 重复点不会堆任务；执行器就是上面的离线词典路径。
  Future<String> enqueueDictionaryTagging() => jobs.enqueue(
    type: 'ingredientTagging',
    dedupeKey: 'ingredientTagging:dictionary',
    payload: const {},
  );

  /// 记一次推荐反馈并落库（「不错 / 换一个」）。
  Future<FeedbackStore> recordFeedback(
    String dishName,
    FeedbackVote vote,
  ) async {
    final repository = FeedbackRepository(database: database);
    return repository.record(dishName, vote);
  }

  /// 恢复备份后的索引重建任务（G14）。
  ///
  /// P0 结论是**不上向量**，所以「重建」当前等价于**清掉恢复前的派生索引**
  /// （向量与旧库对应，恢复后必须失效）；任务照常入队，进度/断点由队列给。
  Future<String> enqueueIndexRebuildAfterRestore() => jobs.enqueue(
    type: 'indexRebuild',
    dedupeKey: 'indexRebuild:afterRestore',
    payload: const {'reason': 'restore'},
  );

  /// 执行一次索引重建（清空派生索引 + 进度上报）。
  ///
  /// 恢复备份后备份里没有向量（D7）：清空是必须的；随后把**记忆**重新
  /// 索引一遍（docs/43 B6「恢复后重建覆盖 memory」）。菜品向量由菜单页
  /// 进页/调试面板的 `indexDishes` 幂等补齐。
  Future<int> rebuildIndexRows() async {
    final cleared = await database.delete(database.embeddingIndex).go();
    final index = semantic;
    final memories = memoryRepository;
    if (index != null && memories != null) {
      try {
        final rows = await memories.history(limit: kAiMemoryHardCap);
        await index.rebuild(rows);
      } on Object {
        // 引擎不可用：索引保持为空，检索降级为关键词；不阻断恢复流程。
      }
    }
    return cleared;
  }
}

/// 任务类型 → 处理器的默认装配（调度器用）。
///
/// 与 [FoodDataMaintenance] 分开，是为了让「任务定义」不依赖具体实现类；
/// 测试可以只替换一个 handler。
Map<String, Future<bool> Function(JobRecord)> defaultJobHandlers({
  required FoodDataMaintenance maintenance,
}) => {
  'ingredientTagging': (job) async {
    await maintenance.tagCanteenDishesWithDictionary();
    return true;
  },
  'indexRebuild': (job) async {
    await maintenance.rebuildIndexRows();
    return true;
  },
};
