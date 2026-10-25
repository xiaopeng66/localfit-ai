import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/dish_library_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/retrieval/application/dish_search.dart';
import 'package:localfit_ai/features/retrieval/application/feedback_store.dart';
import 'package:localfit_ai/features/retrieval/application/ranking.dart';
import 'package:localfit_ai/features/retrieval/application/semantic_runtime.dart';
import 'package:localfit_ai/features/retrieval/application/taste_profile.dart';
import 'package:localfit_ai/features/retrieval/data/embedding_engine.dart';
import 'package:localfit_ai/features/settings/data/app_settings_repository.dart';

/// 菜单页搜索框（docs/43 A1 / docs/39 §8）。
///
/// 钉住六件事：防抖 200ms、关键词命中、**仅语义命中**（查询与菜名无字面
/// 重叠）、空态、清空恢复推荐区、320dp + 2.0× 不溢出。
void main() {
  late AppDatabase database;
  late DishLibraryRepository dishes;

  final now = DateTime(2026, 10, 19, 9);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    dishes = DishLibraryRepository(
      database: database,
      idGenerator: _SeqIds(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 19, 1)),
    );
  });

  tearDown(() async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
    await database.close();
  });

  Future<List<DishRecord>> seed() async {
    final out = <DishRecord>[];
    for (final (name, slot) in [
      ('番茄炒蛋', '午餐'),
      ('红烧肉', '午餐'),
      ('清蒸鲈鱼', '晚餐'),
      ('小米粥', '早餐'),
    ]) {
      out.add(
        await dishes.create(
          DishDraft(
            name: name,
            mealSlot: slot,
            kcal: 200,
            proteinG: 10,
            carbsG: 20,
            fatG: 8,
            source: 'manual',
          ),
        ),
      );
    }
    return out;
  }

  Future<void> pumpMenu(
    WidgetTester tester, {
    SemanticRuntime? semantic,
    DishSearchService? search,
    Future<void> Function(DishRecord dish)? onAddToMeal,
    Size size = const Size(420, 2400),
  }) async {
    final view = tester.view;
    view.physicalSize = size;
    view.devicePixelRatio = 1;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuDishList(
            repository: dishes,
            now: now,
            semantic: semantic,
            searchService: search ?? const DishSearchService(),
            onAddToMeal: onAddToMeal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// drift 的流在取消时会排一个 0 时长的 Timer（`markAsClosed`）：拆树后
  /// 泵一帧让它跑掉（本仓既有的收尾写法，必须在测试体内调用）。
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('防抖：连续输入 3 次只触发 1 次检索', (tester) async {
    await seed();
    final counting = _CountingSearch();
    await pumpMenu(tester, search: counting);

    final field = find.byKey(const Key('nutrition-menu-search'));
    expect(field, findsOneWidget);

    await tester.enterText(field, '番');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.enterText(field, '番茄');
    await tester.pump(const Duration(milliseconds: 80));
    await tester.enterText(field, '番茄炒蛋');
    await tester.pump(const Duration(milliseconds: 100));
    expect(counting.calls, 0, reason: '200ms 防抖窗口内不应触发');

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    expect(counting.calls, 1, reason: '三次输入只应触发一次检索');
    await drain(tester);
  });

  testWidgets('关键词命中：行上有「加入餐」', (tester) async {
    final seeded = await seed();
    final added = <DishRecord>[];
    await pumpMenu(tester, onAddToMeal: (dish) async => added.add(dish));

    await tester.enterText(
      find.byKey(const Key('nutrition-menu-search')),
      '番茄炒蛋',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    final intro = tester.widget<Text>(
      find.byKey(const Key('nutrition-menu-intro')),
    );
    expect(intro.data, contains('搜索本地已分析的菜品'), reason: '搜索态指引行换成搜索口径');
    final target = seeded.firstWhere((dish) => dish.name == '番茄炒蛋');
    expect(
      find.byKey(Key('nutrition-menu-search-hit-${target.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('nutrition-menu-search-count')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(Key('nutrition-menu-search-add-${target.id}')));
    await tester.pumpAndSettle();
    expect(added.single.id, target.id);
    await drain(tester);
  });

  testWidgets('仅语义命中：无字面重叠也能命中，reasons 含「语义」', (tester) async {
    final seeded = await seed();
    final runtime = SemanticRuntime(
      database: database,
      engineFactory: () async => const _ScriptedEngine(),
      settings: AppSettingsRepository(database: database),
    );
    await pumpMenu(tester, semantic: runtime);

    // 进页空闲索引已经跑过（pumpAndSettle 等到了 post-frame 的那次）。
    expect(await runtime.indexedCount(), seeded.length);

    await tester.enterText(
      find.byKey(const Key('nutrition-menu-search')),
      '来点硬菜',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    final target = seeded.firstWhere((dish) => dish.name == '红烧肉');
    expect(
      find.byKey(Key('nutrition-menu-search-hit-${target.id}')),
      findsOneWidget,
      reason: '语义名次必须把红烧肉带进结果',
    );
    expect(
      find.byKey(Key('nutrition-menu-search-reasons-${target.id}')),
      findsOneWidget,
    );
    expect(find.textContaining('语义'), findsWidgets);
    await drain(tester);
  });

  testWidgets('空态：没有匹配时显示空态且不显示「找到 0 道」', (tester) async {
    await seed();
    await pumpMenu(tester);

    await tester.enterText(
      find.byKey(const Key('nutrition-menu-search')),
      '不存在的菜',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('nutrition-menu-search-empty')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('nutrition-menu-search-count')), findsNothing);
    await drain(tester);
  });

  testWidgets('清空恢复推荐区', (tester) async {
    await seed();
    await pumpMenu(tester);

    await tester.enterText(
      find.byKey(const Key('nutrition-menu-search')),
      '番茄',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('nutrition-menu-search-count')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('nutrition-menu-search-clear')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nutrition-menu-search-count')), findsNothing);
    expect(
      find.byKey(const Key('nutrition-menu-meal-breakfast')),
      findsOneWidget,
      reason: '清空后必须回到三餐推荐区',
    );
    await drain(tester);
  });

  testWidgets('320dp + 2.0×：搜索框与结果行不溢出', (tester) async {
    await seed();
    final view = tester.view;
    // 逻辑 320dp 宽、2.0× 字号：physicalSize = 640 × 1600，dpr = 2。
    view.physicalSize = const Size(640, 1600);
    view.devicePixelRatio = 2;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuDishList(repository: dishes, now: now),
        ),
      ),
    );
    // 2.0× 下页面里常驻的入场动画不会自然 settle：用定长 pump 走完
    // 防抖窗口，再连泵两帧把结果画出来（不靠 pumpAndSettle）。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(
      find.byKey(const Key('nutrition-menu-search')),
      '番茄',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    final box = tester.getSize(find.byKey(const Key('nutrition-menu-search')));
    expect(box.width, lessThanOrEqualTo(320));
    await drain(tester);
  });
}

/// 计数检索（防抖断言用）：只数调用次数，结果仍走默认实现。
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

/// 脚本化引擎：按「文本里包含哪个关键词」给固定向量。
///
/// 「来点硬菜」与「红烧肉」都给 `[1,0,0,0]`，其余给 `[0,1,0,0]`——查询与
/// 菜名**没有任何字面重叠**，只有语义路能把它带进结果。
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
      if ('$prefix$text'.contains('红烧肉') || '$prefix$text'.contains('来点硬菜'))
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
