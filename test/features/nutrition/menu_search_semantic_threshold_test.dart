import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/retrieval/data/embedding_engine.dart';

/// RV-P1-06：语义路必须有**最低相关度**。没有阈值时任意查询都会把
/// 全部菜品当命中（设备实测：查「不存在的菜」→「找到 1 道 · 命中：语义」）。
class _ScriptedEngine implements EmbeddingEngine {
  const _ScriptedEngine();

  @override
  int get dim => 2;

  @override
  Future<List<List<double>>> embed(
    List<String> texts, {
    int maxLen = kDishEmbedMaxLen,
    String prefix = '',
  }) async => [
    for (final text in texts)
      if ('$prefix$text'.contains('无关')) const [1, 0] else const [0, 1],
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 10, 20, 12);
  late AppDatabase database;
  late DishLibraryRepository dishes;
  late SemanticRuntime runtime;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(now.toUtc()),
    );
    runtime = SemanticRuntime(
      database: database,
      engineFactory: () async => const _ScriptedEngine(),
    );
    await dishes.create(
      DishDraft(
        name: '红烧肉',
        mealSlot: '午餐',
        kcal: 300,
        proteinG: 10,
        carbsG: 20,
        fatG: 18,
        source: 'manual',
      ),
    );
    await runtime.indexDishes(await dishes.watchAll().first);
  });

  tearDown(() => database.close());

  test('与菜名正交的查询：不过阈值 ⇒ 不参与（返回 null）', () async {
    final ranking = await runtime.rankDishes(
      '无关查询',
      await dishes.watchAll().first,
    );
    expect(ranking, isNull, reason: '全体 cos=0 时不能把全部菜当「语义命中」；应降级为关键词+标签');
    expect(runtime.lastRankError, isNotNull);
  });

  test('相关查询：过阈值 ⇒ 返回名次', () async {
    final ranking = await runtime.rankDishes(
      '红烧肉',
      await dishes.watchAll().first,
    );
    expect(ranking, isNotNull);
    expect(ranking!.length, 1);
  });
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
