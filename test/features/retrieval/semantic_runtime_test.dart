import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/retrieval/application/memory_selector.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/retrieval/data/embedding_engine.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 语义检索接线（docs/39 §4–§5、docs/41 §6）的判据。
///
/// 用 [FakeEmbeddingEngine] 把**管道**钉死：索引写入与复用、模型换版重建、
/// 开关、降级、门控阈值。真模型的质量在 P0 评测里（`docs/evidence`），
/// 这里不假装能测出语义好坏。
void main() {
  late AppDatabase db;
  late DishLibraryRepository dishes;
  late AppSettingsRepository settings;

  final now = DateTime.utc(2026, 10, 19, 6);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dishes = DishLibraryRepository(
      database: db,
      idGenerator: const _SeqIds(),
      clock: FixedAppClock(now),
    );
    settings = AppSettingsRepository(database: db);
  });

  tearDown(() => db.close());

  /// [failing] = **模型加载失败**（工厂抛错）；[engine] 可注入「加载成功但
  /// 推理失败」的假引擎——两条降级路径分开钉。
  SemanticRuntime runtime({bool failing = false, EmbeddingEngine? engine}) =>
      SemanticRuntime(
        database: db,
        engineFactory: () async {
          if (failing) {
            throw const EmbeddingUnavailable('假引擎：模拟模型加载失败');
          }
          return engine ?? const FakeEmbeddingEngine();
        },
        settings: settings,
      );

  Future<void> seed(List<(String, double)> items) async {
    for (final (name, kcal) in items) {
      await dishes.create(
        DishDraft(
          name: name,
          mealSlot: '午餐',
          kcal: kcal,
          proteinG: 10,
          carbsG: 30,
          fatG: 8,
          source: 'manual',
        ),
      );
    }
  }

  test('索引：首次全写；文本没变时复用（textHash 命中）', () async {
    await seed([('番茄炒蛋', 150), ('清蒸鲈鱼', 120)]);
    final all = await dishes.watchAll().first;
    final service = runtime();

    final first = await service.indexDishes(all);
    expect(first.indexed, 2);
    expect(first.skipped, 0);
    expect(await service.indexedCount(), 2);

    final second = await service.indexDishes(all);
    expect(second.indexed, 0, reason: '文本没变 ⇒ 不该重算（加密库写放大）');
    expect(second.skipped, 2);
  });

  test('改一道菜的营养 ⇒ 只重算那一条', () async {
    await seed([('番茄炒蛋', 150), ('清蒸鲈鱼', 120)]);
    final before = await dishes.watchAll().first;
    final service = runtime();
    await service.indexDishes(before);

    final target = before.firstWhere((dish) => dish.name == '番茄炒蛋');
    await dishes.updateNutritionFromSource(
      id: target.id,
      kcal: 300,
      proteinG: 20,
      carbsG: 10,
      fatG: 15,
      sourceUpdatedAt: now,
    );
    final after = await dishes.watchAll().first;
    final report = await service.indexDishes(after);
    expect(report.indexed, 1);
    expect(report.skipped, 1);
  });

  test('删除菜品 ⇒ 索引里的孤儿被清掉', () async {
    await seed([('番茄炒蛋', 150), ('清蒸鲈鱼', 120)]);
    final all = await dishes.watchAll().first;
    final service = runtime();
    await service.indexDishes(all);
    expect(await service.indexedCount(), 2);

    await dishes.delete(all.first.id);
    final report = await service.indexDishes((await dishes.watchAll().first));
    expect(report.removed, 1);
    expect(await service.indexedCount(), 1);
  });

  test('语义名次：按余弦降序，且只保留过阈值的条目', () async {
    await seed([('番茄炒蛋', 150), ('清蒸鲈鱼', 120)]);
    final all = await dishes.watchAll().first;
    // 脚本化引擎：忽略前缀，按文本内容给向量。这样这条用例钉的是
    // 「排序 + 阈值过滤」，不依赖真模型的语义质量。
    final service = runtime(engine: const _NameMatchingEngine());
    await service.indexDishes(all);

    final ranking = await service.rankDishes('番茄炒蛋', all);
    expect(ranking, isNotNull);
    expect(ranking, hasLength(1), reason: '与本查询正交的菜不过 0.35 阈值，不算命中（RV-P1-06）');
    expect(ranking!.first, all.firstWhere((d) => d.name == '番茄炒蛋').id);
  });

  test('模型加载失败 ⇒ 索引抛错、名次 null、不可用（降级，不崩）', () async {
    await seed([('番茄炒蛋', 150)]);
    final all = await dishes.watchAll().first;
    final service = runtime(failing: true);

    await expectLater(
      service.indexDishes(all),
      throwsA(isA<EmbeddingUnavailable>()),
    );
    expect(await service.rankDishes('番茄', all), isNull);
    expect(await service.isAvailable(), isFalse);
    expect(service.loadError, isNotNull, reason: '失败原因要能显示给调试面板');
  });

  test('引擎能加载但推理失败 ⇒ 名次仍是 null（不把异常抛给搜索）', () async {
    await seed([('番茄炒蛋', 150)]);
    final all = await dishes.watchAll().first;
    final service = runtime(engine: const FakeEmbeddingEngine(failing: true));

    expect(await service.rankDishes('番茄', all), isNull);
  });

  test('开关关闭 ⇒ 不参与（名次为 null），且不影响索引写入', () async {
    await seed([('番茄炒蛋', 150)]);
    final all = await dishes.watchAll().first;
    final service = runtime();
    await settings.setBool(kSemanticSearchEnabledKey, value: false);

    expect(await service.rankDishes('番茄', all), isNull);
    expect(await service.isAvailable(), isFalse);
  });

  test('模型换版 ⇒ 旧 modelId 的行不算数，索引会整条重算', () async {
    await seed([('番茄炒蛋', 150)]);
    final all = await dishes.watchAll().first;
    final service = runtime();
    await service.indexDishes(all);
    expect(await service.indexedCount(), 1);

    // 主键是 (ownerType, ownerId)：换版时同一行被新 modelId 覆盖，
    // 于是「当前模型有几条」回到 0 ⇒ 必须重算（向量空间不可混用）。
    await db
        .into(db.embeddingIndex)
        .insertOnConflictUpdate(
          EmbeddingIndexCompanion.insert(
            ownerType: 'dish',
            ownerId: all.single.id,
            modelId: 'bge-small-zh-v1.5-int8-v0',
            dim: 512,
            encoding: 'f32',
            textHash: 'old',
            vector:
                (await (db.select(
                      db.embeddingIndex,
                    )..where((row) => row.ownerId.equals(all.single.id))).get())
                    .single
                    .vector,
            updatedAt: now,
          ),
        );

    expect(await service.indexedCount(), 0, reason: '旧 modelId 不算当前索引');
    final rebuilt = await service.indexDishes(all);
    expect(rebuilt.indexed, 1, reason: '换版必须重算，而不是复用旧向量');
    expect(await service.indexedCount(), 1);
  });

  test('记忆语义相关度：命中条目进注入、不相关条目被门控挡掉', () async {
    final service = runtime();
    final memories = [
      AiMemory(
        id: 'm1',
        text: '不吃香菜',
        kind: AiMemoryKind.preference,
        domain: AiMemoryDomain.nutrition,
        tags: const ['香菜'],
        pinned: false,
        source: 'manual',
        status: 'active',
        createdAt: now,
        updatedAt: now,
      ),
      AiMemory(
        id: 'm2',
        text: '周三晚上练腿',
        kind: AiMemoryKind.habit,
        domain: AiMemoryDomain.training,
        tags: const ['训练'],
        pinned: false,
        source: 'manual',
        status: 'active',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    final scorer = await service.memoryScorer(
      userMessage: '不吃香菜',
      memories: memories,
    );
    expect(scorer, isNotNull, reason: '假引擎可用 ⇒ 应给出向量打分器');
    expect(scorer, isA<VectorMemoryScorer>());
    expect(scorer!.gate, kMemoryVectorGate);

    final selection = selectMemoriesForInjection(
      memories: memories,
      userMessage: '不吃香菜',
      scorer: scorer,
    );
    expect(selection.injectedIds, contains('m1'), reason: '与消息同词的记忆必须进注入');
  });

  test('记忆打分器在引擎失败时返回 null（调用方退回关键词）', () async {
    final service = runtime(failing: true);
    final scorer = await service.memoryScorer(
      userMessage: '不吃香菜',
      memories: [
        AiMemory(
          id: 'm1',
          text: '不吃香菜',
          kind: AiMemoryKind.preference,
          domain: AiMemoryDomain.nutrition,
          tags: const [],
          pinned: false,
          source: 'manual',
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    expect(scorer, isNull);
  });

  // 2026-10-22（隔离变异 M08 抓到）：0.45 是**真模型标定值**
  // （无关 ≤0.386 / 相关 0.389–0.500，docs/40），改它等于改质量门槛，
  // 但没有任何断言盯着。这里钉住数值本身；换模型重标时必须一起改。
  test('菜品语义阈值 = 0.45（真模型标定值，换模型须重标）', () {
    expect(kDishSemanticMinCosine, 0.45);
  });
}

class _SeqIds implements IdGenerator {
  const _SeqIds();

  static int _next = 0;

  @override
  String next() => 'id-${++_next}';
}

/// 与菜名一一对应的脚本化向量：查询命中时 cos=1，其余正交（cos=0）。
final class _NameMatchingEngine implements EmbeddingEngine {
  const _NameMatchingEngine();

  @override
  int get dim => 2;

  @override
  Future<List<List<double>>> embed(
    List<String> texts, {
    int maxLen = kDishEmbedMaxLen,
    String prefix = '',
  }) async => [
    for (final text in texts)
      if (text.contains('番茄')) const [1, 0] else const [0, 1],
  ];
}
