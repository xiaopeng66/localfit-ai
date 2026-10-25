import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/retrieval/data/embedding_engine.dart';
import 'package:localfit_ai/features/retrieval/presentation/retrieval_debug_page.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 调试面板第三档（docs/43 A4 / docs/39 G21）：模式对比三行都在，
/// SEMANTIC_FIRST 的首条与语义名次一致。
void main() {
  late AppDatabase db;
  late DishLibraryRepository dishes;

  final now = DateTime.utc(2026, 10, 19, 6);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dishes = DishLibraryRepository(
      database: db,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() async => db.close());

  Future<void> pumpPanel(
    WidgetTester tester, {
    SemanticRuntime? semantic,
  }) async {
    tester.view.physicalSize = const Size(420, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 直接读表（drift 的 watch 流在 widget 测试的 fake async 下不 pump 不发射）。
    final rows = await db.select(db.dishLibrary).get();
    final dishRecords = [
      for (final row in rows)
        DishRecord(
          id: row.id,
          name: row.name,
          mealSlot: row.mealSlot,
          kcal: row.kcal,
          proteinG: row.proteinG,
          carbsG: row.carbsG,
          fatG: row.fatG,
          source: row.source,
          createdAt: row.createdAt,
          updatedAt: row.updatedAt,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: RetrievalDebugPage(dishes: dishRecords, semantic: semantic),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('模式对比三行都在（含 SEMANTIC_FIRST）', (tester) async {
    for (final name in ['红烧肉', '番茄炒蛋', '清蒸鲈鱼']) {
      await dishes.create(
        DishDraft(
          name: name,
          mealSlot: '午餐',
          kcal: 200,
          proteinG: 10,
          carbsG: 20,
          fatG: 8,
          source: 'manual',
        ),
      );
    }
    await pumpPanel(tester);

    expect(
      find.byKey(const Key('retrieval-debug-mode-balanced')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('retrieval-debug-mode-keyword')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('retrieval-debug-mode-semantic')),
      findsOneWidget,
    );
    expect(find.textContaining('SEMANTIC_FIRST'), findsOneWidget);
  });

  testWidgets('语义不可用时如实显示原因（Key retrieval-debug-semantic-reason）', (
    tester,
  ) async {
    for (final name in ['红烧肉']) {
      await dishes.create(
        DishDraft(
          name: name,
          mealSlot: '午餐',
          kcal: 200,
          proteinG: 10,
          carbsG: 20,
          fatG: 8,
          source: 'manual',
        ),
      );
    }
    final runtime = SemanticRuntime(
      database: db,
      engineFactory: () async =>
          throw const EmbeddingUnavailable('假引擎：模拟模型加载失败'),
      settings: AppSettingsRepository(database: db),
    );
    await pumpPanel(tester, semantic: runtime);
    expect(
      find.byKey(const Key('retrieval-debug-semantic-reason')),
      findsOneWidget,
      reason: 'docs/43 A1：降级原因必须在调试面板可见',
    );
    expect(find.textContaining('未参与原因'), findsOneWidget);
  });

  testWidgets('SEMANTIC_FIRST 首条与语义名次一致（仅语义命中）', (tester) async {
    for (final name in ['红烧肉', '番茄炒蛋', '米饭']) {
      await dishes.create(
        DishDraft(
          name: name,
          mealSlot: '午餐',
          kcal: 200,
          proteinG: 10,
          carbsG: 20,
          fatG: 8,
          source: 'manual',
        ),
      );
    }
    final runtime = SemanticRuntime(
      database: db,
      engineFactory: () async => const _ScriptedEngine(),
      settings: AppSettingsRepository(database: db),
    );
    await pumpPanel(tester, semantic: runtime);

    // 面板默认查询「想吃点清淡的汤」与菜名无字面重叠；脚本引擎把
    // 「清淡」映射到红烧肉的向量。
    final row = tester.widget<Text>(
      find.byKey(const Key('retrieval-debug-mode-semantic')),
    );
    expect(row.data, contains('首条 红烧肉'));
  });
}

/// 脚本化引擎：「清淡」与「红烧肉」共享同一向量；其余正交。
class _ScriptedEngine implements EmbeddingEngine {
  const _ScriptedEngine();

  @override
  int get dim => 4;

  @override
  Future<List<List<double>>> embed(
    List<String> texts, {
    int maxLen = kDishEmbedMaxLen,
    String prefix = '',
  }) async => [
    for (final text in texts)
      if ('$prefix$text'.contains('红烧肉') ||
          '$prefix$text'.contains('清淡') ||
          '$prefix$text'.contains('想吃点'))
        const [1, 0, 0, 0]
      else
        const [0, 1, 0, 0],
  ];
}

class _SeqIds implements IdGenerator {
  int _n = 0;
  @override
  String next() => 'dish-${_n++}';
}
