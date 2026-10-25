import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/retrieval/presentation/retrieval_debug_page.dart';

/// 搜索调试面板（G21）：只读诊断面，判据是「该显示的信息都在、且与检索一致」。
DishRecord _dish(String id, String name) => DishRecord(
  id: id,
  name: name,
  mealSlot: '午餐',
  kcal: 300,
  proteinG: 10,
  carbsG: 30,
  fatG: 10,
  source: 'manual',
  createdAt: DateTime.utc(2026, 10, 18),
  updatedAt: DateTime.utc(2026, 10, 18),
);

CanteenDish _canteenDish(String id, String name, List<String> tags) =>
    CanteenDish(
      id: id,
      windowId: 'w1',
      name: name,
      evidenceGrade: 'C',
      itemStatus: 'estimated',
      evidence: null,
      tags: tags,
    );

void main() {
  /// 面板新增「模式对比」第三行后整页变高：默认 800×600 视口里结果卡
  /// 落在屏外（ListView 不构建屏外子）。加高视口，**断言不变**。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('面板显示查询理解 / 各路命中 / 模式对比 / 前 5 条', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: RetrievalDebugPage(
          dishes: [_dish('d1', '清蒸鲈鱼')],
          canteenDishes: [
            _canteenDish('m1', '紫菜蛋花汤', const ['清淡', '汤']),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('retrieval-debug-title')), findsOneWidget);
    // 查询理解四行 + 语义路关闭（P0 结论）。
    expect(find.textContaining('关键词：'), findsOneWidget);
    expect(find.textContaining('语义路：关'), findsOneWidget);
    // 模式对比两种。
    expect(find.textContaining('BALANCED：'), findsOneWidget);
    expect(find.textContaining('KEYWORD_FIRST：'), findsOneWidget);
    // 命中列表非空且第一条是标签命中的汤。
    expect(find.byKey(const Key('retrieval-debug-results')), findsOneWidget);
    expect(find.byKey(const Key('retrieval-debug-hit-m1')), findsOneWidget);
  });

  testWidgets('改查询 ⇒ 命中随之变化（面板与检索同源）', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: RetrievalDebugPage(
          dishes: [_dish('d1', '清蒸鲈鱼'), _dish('d2', '红烧肉')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('retrieval-debug-query')),
      '想吃红烧肉',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('retrieval-debug-hit-d2')), findsOneWidget);
  });

  testWidgets('无命中时如实显示（不编造结果）', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(
      MaterialApp(home: RetrievalDebugPage(dishes: [_dish('d1', '清蒸鲈鱼')])),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('retrieval-debug-query')),
      'zzzz',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('（无命中'), findsOneWidget);
  });

  testWidgets('索引与后台任务：0 条也如实显示；任务显示进度/失败', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RetrievalDebugPage(
          dishes: [_dish('d1', '清蒸鲈鱼')],
          status: const RetrievalIndexStatus(
            indexedCount: 0,
            jobs: [
              RetrievalJobLine(
                type: 'indexRebuild',
                state: 'processing',
                progress: 40,
              ),
              RetrievalJobLine(
                type: 'ingredientTagging',
                state: 'failed',
                lastError: '磁盘已满',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('retrieval-debug-index')), findsOneWidget);
    // 向量条数只在「语义检索」卡里显示（避免同一面板两处数字打架），
    // 这一段只报后台任务。
    expect(find.textContaining('后台任务'), findsOneWidget);
    expect(find.textContaining('indexRebuild · processing'), findsOneWidget);
    expect(find.textContaining('进度 40%'), findsOneWidget);
    expect(find.textContaining('失败：磁盘已满'), findsOneWidget);
  });

  testWidgets('没有后台任务时写「无」（不编造任务）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RetrievalDebugPage(
          dishes: [_dish('d1', '清蒸鲈鱼')],
          status: const RetrievalIndexStatus(indexedCount: 0, jobs: []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('后台任务：无'), findsOneWidget);
  });
}
