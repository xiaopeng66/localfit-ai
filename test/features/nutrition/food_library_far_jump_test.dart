import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/data/catalog_search_service.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_library_view.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart';

/// 大库（49,464 条）的分页列表：**行高必须已知**（docs/28 §8.4 判据 ①②③）。
///
/// **这一组是设备走查抓出来的真缺陷的回归**：原来用 `SliverList`（行高未知），
/// 拖滑条到底会 `jumpTo` 一个几百万像素的 offset，sliver 只能从当前位置逐行
/// 实体化到目标位置——一帧里要建上万行，主线程卡死（真机 ANR「输入分发超时」，
/// 见 `docs/evidence/2026-10-04-input-menu-foodlib-redesign.md` W7）。
/// 修法是让行高**已知**（`SliverPrototypeExtentList` + 最高变体原型卡），
/// 跳转变成算术，只实体化视口那几行。
///
/// 四条断言合起来钉住「行高已知」这件事：
///  ① 一次远跳只取落点附近的页，且落到**最后一页**（滑条长度 = 真实总量）；
///  ② 滑条长度按 49,464 条算，不是按已加载的 50 条；
///  ③ 完整卡与「营养不完整」卡占**同一行高**（原型取了最高变体）；
///  ④ 2.0× 字号下行高跟着放大（原型的行高是**实测**出来的，不是写死的数字）。
///
/// 注意：本文件**不能用 `pumpAndSettle`**——骨架里的 `SkeletonBox` 是
/// `repeat(reverse: true)` 的呼吸动画，只要有骨架在屏上就永不静止。
void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  FoodRepository repo() => FoodRepository(
    database: database,
    idGenerator: _Ids(),
    clock: FixedAppClock(DateTime.utc(2026, 10, 4)),
  );

  Future<void> pumpView(
    WidgetTester tester,
    FoodLibraryController controller, {
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodLibraryView(controller: controller, revision: 0),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('拖滑条到底：一次远跳只取落点那一页，不实体化中间上万行', (tester) async {
    final controller = _BigLibraryController(repository: repo());
    await pumpView(tester, controller);
    expect(controller.requestedOffsets, <int>[0]);

    final scrollbar = tester.getRect(find.byType(Scrollbar));
    final gesture = await tester.startGesture(
      Offset(scrollbar.right - 4, scrollbar.top + 8),
    );
    await gesture.moveBy(const Offset(0, 3000));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));

    // ① 只请求了落点附近那几页。行高未知时这里会先卡死（每帧实体化上千行）。
    expect(
      controller.requestedOffsets.length,
      lessThanOrEqualTo(6),
      reason: '一次远跳只该取落点附近的页；取了几百页说明跳转被逐行铺开了',
    );

    // 落点 = 最后一页：滑条长度代表真实总量（49,464），不是已加载量。
    const lastPageStart =
        (_BigLibraryController.total ~/ FoodLibraryController.pageSize) *
        FoodLibraryController.pageSize;
    expect(controller.requestedOffsets.last, lastPageStart);

    // 屏上是最末那几条真卡，且不重复（走查判据 ③ 的唯一键排序）。
    final rendered = tester
        .widgetList<FoodCard>(find.byType(FoodCard))
        .map((card) => card.id)
        .where((id) => id != 'food-library-row-prototype')
        .toList();
    expect(rendered, isNotEmpty);
    expect(rendered.toSet().length, rendered.length, reason: '同一张卡不得重复出现');
    final lastIds = {
      for (var i = lastPageStart; i < _BigLibraryController.total; i++)
        'food-${i.toString().padLeft(5, '0')}',
    };
    for (final id in rendered) {
      expect(lastIds, contains(id));
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('行高已知：滑条长度按真实总量算，不是已加载量', (tester) async {
    final controller = _BigLibraryController(repository: repo());
    await pumpView(tester, controller);

    // 取列表自己的 Scrollable：搜索框内部也有一个（EditableText 的），
    // `find.byType(Scrollable).first` 会先撞上它，量到 0。
    final position = _positionOf(tester);
    // 只加载了第 1 页（50 条）时，可滚动长度就已经按 49,464 条算好了。
    expect(controller.requestedOffsets, <int>[0]);

    // 行距从**屏上真卡实测**，不是写死的数字：单行化后行高由图标 40 决定
    // （≈56dp），不再是五段卡的 ≈136dp —— 「每行多少像素」这个量本身也得跟着
    // 量，否则这条断言只是在钉一个过期的魔数。Round7 阶段 3（D36）换成单卡
    // 列表后行距 = 行高（行与行之间只有 1px 分隔线，不再有 8dp 间距）。
    final cardHeight = tester
        .getSize(find.byKey(const Key('food-library-item-food-00000')))
        .height;
    final rowPitch = cardHeight;
    final expectedExtent = _BigLibraryController.total * rowPitch;
    // 视口高度只占内容高度的万分之几 ⇒ 1% 容差已经很紧。行高未知（`SliverList`）
    // 时这里量到的是「已加载 50 条」的长度，与目标差三个数量级。
    expect(
      position.maxScrollExtent,
      closeTo(expectedExtent, expectedExtent * 0.01),
      reason: '滑条长度必须对应 49,464 条 × 实测行距 $rowPitch，而不是已加载的 50 条',
    );
  });

  testWidgets('单行化后所有变体天然等高：完整卡与「营养不完整」卡同高、同步距', (tester) async {
    // 2026-10-08（docs/30 §2 D1）：卡压成单行三件后，「营养不完整」不再占独立
    // 行（只在名称后加一枚 12dp 图标）⇒ **所有变体天然等高**，原型不再需要
    // 「取最高变体」。这条断言就是那份「天然等高」的证据。
    final controller = _MixedController(repository: repo());
    await pumpView(tester, controller);

    expect(
      find.byKey(const Key('food-card-incomplete-food-incomplete')),
      findsOneWidget,
      reason: '不可加入计划改由名称后的警告图标承担（整行文字退场）',
    );
    final complete = tester.getSize(
      find.byKey(const Key('food-library-item-food-complete')),
    );
    final incomplete = tester.getSize(
      find.byKey(const Key('food-library-item-food-incomplete')),
    );
    expect(complete.height, incomplete.height);
    expect(
      complete.height,
      closeTo(LfDimens.foodCardIconSize + LfDimens.spaceSmall * 2, 0.5),
      reason: '单行卡高 = 图标 40 + 上下各 8（行高由最高的那一件决定）',
    );
    // 两行之间的「步距」= 行高本身（单卡列表里行与行之间只有分隔线），
    // 且两行一致（行高已知才有步距可言）。
    final first = tester.getTopLeft(
      find.byKey(const Key('food-library-item-food-complete')),
    );
    final second = tester.getTopLeft(
      find.byKey(const Key('food-library-item-food-incomplete')),
    );
    expect(second.dy - first.dy, complete.height);
  });

  testWidgets('2.0× 字号：行高跟着放大（原型的行高是实测的，不是写死的数字）', (tester) async {
    final controller = _MixedController(repository: repo());
    await pumpView(tester, controller);
    final atOne = tester
        .getSize(find.byKey(const Key('food-library-item-food-complete')))
        .height;

    await pumpView(tester, controller, textScale: 2.0);
    // 溢出会直接把这条用例判红（测试框架把 RenderFlex overflow 当异常）。
    final atTwo = tester
        .getSize(find.byKey(const Key('food-library-item-food-complete')))
        .height;
    expect(
      find.byKey(const Key('food-card-incomplete-food-incomplete')),
      findsOneWidget,
      reason: '2.0× 下警告图标同样在',
    );
    expect(atTwo, greaterThan(atOne), reason: '行高若写死，2.0× 下文字就会溢出固定行高');
  });
}

/// 列表自己的滚动位置（搜索框内部也有一个 Scrollable）。
ScrollPosition _positionOf(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('food-library-list')),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

/// 两张卡的极简库：一张完整、一张「营养不完整」（名称后多一枚警告图标）。
final class _MixedController extends FoodLibraryController {
  _MixedController({required super.repository})
    : super(catalogSearch: CatalogSearchService(shardPaths: const []));

  @override
  Future<int> count(String query, {FoodCategory? category}) async => 2;

  @override
  Future<List<FoodLibraryItem>> page(
    String query, {
    required int offset,
    required int limit,
    FoodCategory? category,
  }) async {
    if (offset > 0) return const <FoodLibraryItem>[];
    return const <FoodLibraryItem>[
      FoodLibraryItem(
        id: 'food-complete',
        name: '完整食物',
        source: 'seed',
        state: 'verified',
        canJoinPlan: true,
        brand: '品牌',
        kcalPer100g: 100,
        proteinPer100g: 1,
        carbsPer100g: 1,
        fatPer100g: 1,
      ),
      FoodLibraryItem(
        id: 'food-incomplete',
        name: '不完整食物',
        source: 'seed',
        state: 'incomplete',
        canJoinPlan: false,
        brand: '品牌',
        kcalPer100g: 100,
        proteinPer100g: 1,
        carbsPer100g: 1,
        fatPer100g: 1,
      ),
    ];
  }
}

/// 49,464 条的大库：`count()` 报真实总量，每页 50 条即时返回，
/// 并记录每一次取页请求（用来量「一次跳到底引发多少次取页」）。
final class _BigLibraryController extends FoodLibraryController {
  _BigLibraryController({required super.repository})
    : super(catalogSearch: CatalogSearchService(shardPaths: const []));

  static const int total = 49464;

  final List<int> requestedOffsets = <int>[];

  @override
  Future<int> count(String query, {FoodCategory? category}) async => total;

  @override
  Future<List<FoodLibraryItem>> page(
    String query, {
    required int offset,
    required int limit,
    FoodCategory? category,
  }) async {
    requestedOffsets.add(offset);
    final end = (offset + limit).clamp(0, total);
    return <FoodLibraryItem>[
      for (var i = offset; i < end; i++)
        FoodLibraryItem(
          id: 'food-${i.toString().padLeft(5, '0')}',
          name: '食物$i',
          source: 'seed',
          state: 'verified',
          canJoinPlan: true,
          kcalPer100g: 100,
          proteinPer100g: 1,
          carbsPer100g: 1,
          fatPer100g: 1,
        ),
    ];
  }
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'id-${_value++}';
}
