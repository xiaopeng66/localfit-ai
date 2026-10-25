import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_conversation/data/chat_edit_context_loader.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';
import 'package:localfit_ai/features/retrieval/application/feedback_store.dart';
import 'package:localfit_ai/features/retrieval/application/ranking.dart';
import 'package:localfit_ai/features/retrieval/application/taste_profile.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';

/// AI 短名单接线（docs/43 A2 / docs/39 §8）：吃/推荐意图才注入，top 30，
/// 按窗口分组，每行带 id；空库不写段；其它段变化不影响本段缓存。
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

  DriftChatEditContextLoader loader({DishSearchService? search}) =>
      DriftChatEditContextLoader(
        database: db,
        clock: FixedAppClock(now),
        mealRepository: MealRepository(
          database: db,
          idGenerator: _SeqIds(),
          clock: FixedAppClock(now),
        ),
        dishLibraryRepository: dishes,
        waterRepository: WaterRepository(
          database: db,
          idGenerator: _SeqIds(),
          clock: FixedAppClock(now),
        ),
        canteenRepository: CanteenRepository(
          database: db,
          idGenerator: _SeqIds(),
          clock: FixedAppClock(now),
        ),
        workoutPlanRepository: WorkoutPlanRepository(
          database: db,
          idGenerator: _SeqIds(),
          clock: FixedAppClock(now),
        ),
        workoutSessionRepository: WorkoutSessionRepository(
          database: db,
          clock: FixedAppClock(now),
          idGenerator: _SeqIds(),
        ),
        dishSearch: search ?? const DishSearchService(),
      );

  Future<List<DishRecord>> seedDishes({
    int count = 6,
    String? servingWindow,
    String prefix = '菜',
  }) async {
    final out = <DishRecord>[];
    for (var i = 0; i < count; i++) {
      out.add(
        await dishes.create(
          DishDraft(
            name: '$prefix$i',
            mealSlot: '午餐',
            kcal: (180 + i).toDouble(),
            proteinG: 10,
            carbsG: 20,
            fatG: 6,
            source: 'manual',
            servingWindow: servingWindow,
          ),
        ),
      );
    }
    return out;
  }

  test('有吃/推荐意图 → 段存在、行数 ≤30、每行带 id', () async {
    await seedDishes(count: 40);
    final snapshot = await loader().build(userMessage: '今天午餐吃什么好');

    expect(snapshot, contains('【候选菜品（本地检索）】'));
    final section = snapshot.split('【候选菜品（本地检索）】').last;
    final lines = section
        .split('\n')
        .where((line) => line.startsWith('[dish:'))
        .toList();
    expect(lines.length, lessThanOrEqualTo(30));
    expect(lines, isNotEmpty);
    expect(
      lines.every((line) => RegExp(r'^\[dish:[^\]]+\]').hasMatch(line)),
      isTrue,
    );
    expect(lines.first, contains('kcal/份'));
  });

  test('无意图（帮我改目标）→ 不注入该段', () async {
    await seedDishes();
    final snapshot = await loader().build(userMessage: '帮我改目标');
    expect(snapshot, isNot(contains('【候选菜品（本地检索）】')));
  });

  test('空库 → 不注入（不写「（空）」占位）', () async {
    final snapshot = await loader().build(userMessage: '今天吃什么');
    expect(snapshot, isNot(contains('【候选菜品（本地检索）】')));
  });

  test('分组正确：同一窗口的菜相邻', () async {
    await seedDishes(count: 2, servingWindow: '06:30-09:30', prefix: '甲');
    await seedDishes(count: 2, servingWindow: '11:00-13:00', prefix: '乙');
    final snapshot = await loader().build(userMessage: '今天午餐吃什么');
    final section = snapshot.split('【候选菜品（本地检索）】').last;
    final aHeader = section.indexOf('【窗口：06:30-09:30】');
    final bHeader = section.indexOf('【窗口：11:00-13:00】');
    expect(aHeader, greaterThanOrEqualTo(0));
    expect(bHeader, greaterThan(aHeader));
    final aLines = section
        .substring(aHeader, bHeader)
        .split('\n')
        .where((line) => line.startsWith('[dish:'))
        .length;
    expect(aLines, 2, reason: 'A 窗口的两道菜必须在 A 段内且相邻');
    final bLines = section
        .substring(bHeader)
        .split('\n')
        .where((line) => line.startsWith('[dish:'))
        .length;
    expect(bLines, 2);
  });

  test('段级缓存：其它表变化不重跑本段（同一消息复用）', () async {
    await seedDishes();
    final counting = _CountingSearch();
    final builder = loader(search: counting);
    final first = await builder.build(userMessage: '今天午餐吃什么');
    expect(counting.calls, 1);

    // 只动饮水表：本段不脏。
    await db
        .into(db.waterIntakes)
        .insert(
          WaterIntakesCompanion.insert(
            id: 'water-1',
            localDate: '2026-10-19',
            amountMl: 250,
            recordedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final second = await builder.build(userMessage: '今天午餐吃什么');
    expect(counting.calls, 1, reason: '未变更段必须复用缓存，不得重跑检索');
    // 饮水段变了（那是另一段），但候选菜品段逐字节不变。
    String section(String text) =>
        text.split('【候选菜品（本地检索）】').last.split('【').first;
    expect(section(second), section(first));
  });
}

/// 计数检索：钉「段级缓存命中时不再跑检索」。
class _CountingSearch extends DishSearchService {
  _CountingSearch();

  int calls = 0;

  @override
  RetrievalResult search({
    required String query,
    required List<DishRecord> dishes,
    List<CanteenDish> canteenDishes = const [],
    List<String>? semanticRanking,
    Set<String>? todayMenuItemIds,
    RetrievalMode mode = RetrievalMode.balanced,
    String? targetSlot,
    Set<String> recentlyEatenNames = const {},
    TasteProfile? taste,
    TasteVectorProfile? tasteVector,
    Map<String, List<double>> dishVectors = const {},
    SoftExclusionRules exclusions = SoftExclusionRules.empty,
    FeedbackStore? feedback,
    int limit = 50,
  }) {
    calls++;
    return super.search(
      query: query,
      dishes: dishes,
      canteenDishes: canteenDishes,
      semanticRanking: semanticRanking,
      todayMenuItemIds: todayMenuItemIds,
      mode: mode,
      targetSlot: targetSlot,
      recentlyEatenNames: recentlyEatenNames,
      taste: taste,
      tasteVector: tasteVector,
      dishVectors: dishVectors,
      exclusions: exclusions,
      feedback: feedback,
      limit: limit,
    );
  }
}

class _SeqIds implements IdGenerator {
  int _n = 0;
  @override
  String next() => 'dish-${_n++}';
}
