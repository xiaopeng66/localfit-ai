import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/domain/degradation_matrix.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/retrieval/data/embedding_engine.dart';

/// RV-P1-09：语义不可用时，搜索必须**如实标注**（docs/41 §10「禁止静默降级」）。
///
/// 矩阵里 `onDeviceModelUnavailable × search` 的 notice 一直是死文本：
/// `degradationNotice` 在 `lib/` 下零调用。这条把文案接到搜索结果区。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DishLibraryRepository dishes;
  final now = DateTime(2026, 10, 20, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(now.toUtc()),
    );
    await dishes.create(
      DishDraft(
        name: '番茄牛腩饭',
        mealSlot: '午餐',
        kcal: 200,
        proteinG: 8,
        carbsG: 30,
        fatG: 5,
        source: 'manual',
      ),
    );
  });

  tearDown(() => database.close());

  testWidgets('语义引擎失败时，搜索结果区显示矩阵里的降级文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuDishList(
            repository: dishes,
            now: now,
            semantic: SemanticRuntime(
              database: database,
              engineFactory: () async =>
                  const FakeEmbeddingEngine(failing: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(
      find.byKey(const Key('nutrition-menu-search')),
      '不存在的菜',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 400));

    final note = find.byKey(const Key('nutrition-menu-degraded-note'));
    expect(note, findsOneWidget, reason: '语义不可用必须上屏，不许静默降级');
    expect(
      tester.widget<Text>(note).data,
      degradationNotice(
        DegradationRow.onDeviceModelUnavailable,
        DegradationColumn.search,
      ),
      reason: '文案必须取矩阵单源（页面不许另写一份）',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('引擎可用但候选不过阈值：提示「相关度不足」而不是「不可用」', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuDishList(
            repository: dishes,
            now: now,
            semantic: SemanticRuntime(
              database: database,
              // 查询与菜名正交（cos=0）⇒ 全部被 0.45 阈值过滤。
              engineFactory: () async => const _OrthogonalEngine(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(
      find.byKey(const Key('nutrition-menu-search')),
      '无关查询',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester
          .widget<Text>(find.byKey(const Key('nutrition-menu-degraded-note')))
          .data,
      kSemanticBelowThresholdNotice,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _OrthogonalEngine implements EmbeddingEngine {
  const _OrthogonalEngine();

  @override
  int get dim => 2;

  @override
  Future<List<List<double>>> embed(
    List<String> texts, {
    int maxLen = kDishEmbedMaxLen,
    String prefix = '',
  }) async => [
    for (final text in texts)
      if (text.contains('无关')) const [1, 0] else const [0, 1],
  ];
}

final class _SeqIds implements IdGenerator {
  int _n = 0;

  @override
  String next() => 'id-${_n++}';
}
