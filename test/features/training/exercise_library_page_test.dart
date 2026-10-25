import 'package:drift/native.dart';
import 'package:drift/src/runtime/executor/executor.dart';
import 'package:drift/src/runtime/executor/interceptor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/presentation/exercise_library_page.dart';

import '../../support/food_fixture.dart';

/// 动作库二级页（docs/22 裁决 ②）的行为测试。
///
/// 这四条原先挂在训练页测试里——那时动作库是训练页的一个分段。新设计把
/// 动作库收进二级入口后，从训练页点进去会**同时留下两页在树上**（推入式
/// 路由不移除上一页），`find.text('杠铃深蹲')` 之类会双命中，测试就再也
/// 测不准这一页。所以这里直 pump `ExerciseLibraryPage`，不经过训练页。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  late ExerciseRepository exercises;

  /// 计数包装：每次 `runSelect` 记一次（drift 的轻量拦截器）。
  late _CountingInterceptor counter;
  late AppDatabase counted;
  late ExerciseRepository countedRepository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids('ex-user'),
      clock: FixedAppClock(DateTime.utc(2026, 9, 12, 10)),
    );

    // 计数库（可注入查询延迟）：流畅度与 waiting 分支断言共用。
    counter = _CountingInterceptor();
    counted = AppDatabase(NativeDatabase.memory().interceptWith(counter));
    await seedFoodFixture(counted);
    await const ExerciseSeedImporter().importIfNeeded(counted);
    countedRepository = ExerciseRepository(
      database: counted,
      idGenerator: _Ids('ex-user'),
      clock: FixedAppClock(DateTime.utc(2026, 9, 12, 10)),
    );
  });

  tearDown(() async {
    await database.close();
    await counted.close();
  });

  Widget page() =>
      MaterialApp(home: ExerciseLibraryPage(repository: exercises));

  /// 输搜索词并等防抖（300ms）与查询结果都落定。
  ///
  /// docs/29 §P5 给搜索加了 300ms 防抖：`enterText` 本身不触发查询，
  /// `pumpAndSettle` 也不会主动跨过「还没到点的 Timer」——它只在有帧在被
  /// 调度时推进。所以这里显式 `pump(300ms)` 让 Timer 到期，再 settle 等
  /// 新结果 future 完成（完成前网格是骨架屏，找不到任何卡片）。
  Future<void> search(WidgetTester tester, String keyword) async {
    await tester.enterText(
      find.byKey(const Key('training-exercise-search')),
      keyword,
    );
    await tester.pump(ExerciseLibraryPage.searchDebounce);
    await tester.pumpAndSettle();
  }

  /// 把动作卡滚进视野再断言。
  ///
  /// 扩到 312 条（2026-10-04）后「用搜索把目标筛出来」不再等于「目标在首屏」：
  /// 一个词能命中十几条（「俯卧撑」12 条、「深蹲」24 条），格子是懒构建的，
  /// 目标可能在第 3 屏外。旧的 `findsOneWidget` 因此在**目标其实存在**时也会
  /// 假红——判据是「屏上有没有建出来」，不是「库里有没有」，所以必须滚动。
  Future<void> revealCard(WidgetTester tester, String exerciseId) async {
    await tester.scrollUntilVisible(
      find.byKey(Key('training-exercise-$exerciseId')),
      200,
      // 只能钉到网格自己的 Scrollable：搜索框内部与肌群 chip 行各有一个，
      // 不限定范围会挑错滚动体（`scrollUntilVisible` 要求恰好命中一个）。
      scrollable: find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    );
  }

  testWidgets('shows the seeded library and filters by search', (tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    // 搜索框自身也含同名文本，断言限定在动作卡片上（按 key）。
    await search(tester, '俯卧撑');
    await revealCard(tester, 'ex-push-up');
    expect(
      find.byKey(const Key('training-exercise-ex-push-up')),
      findsOneWidget,
    );

    await search(tester, '哑铃卧推');
    await revealCard(tester, 'ex-dumbbell-bench-press');
    expect(
      find.byKey(const Key('training-exercise-ex-dumbbell-bench-press')),
      findsOneWidget,
    );

    await search(tester, '深蹲');
    await revealCard(tester, 'ex-barbell-squat');
    expect(
      find.byKey(const Key('training-exercise-ex-barbell-squat')),
      findsOneWidget,
    );
    // 「俯卧撑」根本不在这次结果里（不是「滚出去了」）。
    expect(find.byKey(const Key('training-exercise-ex-push-up')), findsNothing);
  });

  testWidgets('Round7 逐页对账：结果计数「N 个动作」按 A（app.js:225）', (tester) async {
    final all = await exercises.search('');
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('exercise-result-count')), findsOneWidget);
    expect(find.text('${all.length} 个动作'), findsOneWidget);

    // A 的计数行在 0 条时照样渲染（`${rows.length} 个动作` 在空态之上），
    // 与食物库「0 种食物也画」同一口径（D32/D38 的既有裁决方向）。
    await search(tester, '没有这个动作名');
    expect(find.byKey(const Key('exercise-result-count')), findsOneWidget);
    expect(find.text('0 个动作'), findsOneWidget);
  });

  testWidgets('shows same-muscle alternatives in the detail sheet', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await search(tester, '深蹲');
    await revealCard(tester, 'ex-barbell-squat');
    await tester.tap(
      find.byKey(const Key('training-exercise-ex-barbell-squat')),
    );
    await tester.pumpAndSettle();

    expect(find.text('同肌群替代动作'), findsOneWidget);
    expect(find.text('杠铃深蹲'), findsWidgets);
    // 同类替代按名称升序取前 6 条，具体成员随动作库扩充会变：这里不硬编码
    // 名字，而是用仓库的同一条查询做基准，断言面板**确实渲染了它给出的第一条**
    // （2026-10-04 之前的写法是找「器械」二字；动作库扩到 312 条后前 6 条里不再
    // 有器械档动作，那是文案耦合，不是行为判据）。
    final alternatives = await exercises.listAlternatives('ex-barbell-squat');
    expect(alternatives, isNotEmpty);
    expect(find.text(alternatives.first.name), findsOneWidget);
    expect(find.text('暂无同肌群的本地替代动作。'), findsNothing);
  });

  testWidgets('creates a user exercise from the dialog', (tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('training-exercise-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('training-exercise-name')),
      '自定义罗马尼亚硬拉',
    );
    await tester.tap(find.byKey(const Key('training-exercise-save')));
    await tester.pumpAndSettle();

    final rows = await database.select(database.exercises).get();
    expect(rows.where((row) => row.isUserCreated).map((row) => row.name), [
      '自定义罗马尼亚硬拉',
    ]);
    // 不假设新动作落在第一屏——随包 312 条，格子是懒构建的。
    await search(tester, '自定义');
    expect(find.text('自定义罗马尼亚硬拉'), findsOneWidget);
  });

  testWidgets('rejects a blank exercise name inside the dialog', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('training-exercise-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-exercise-save')));
    await tester.pumpAndSettle();

    expect(find.text('动作名称不能为空。'), findsOneWidget);
    expect(
      (await database.select(database.exercises).get()).where(
        (row) => row.isUserCreated,
      ),
      isEmpty,
    );
  });

  testWidgets('the grid carries a persistent, draggable scrollbar', (
    tester,
  ) async {
    // docs/28 §8.3：动作库也挂同一个 `LfScrollbar`（常显 + 可拖动）。
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
  });

  // ── docs/29 §P5 ────────────────────────────────────────────────────────

  group('P5 卡片（需求 9/10）', () {
    /// 首格卡的卡内 Column 直接孩子（图标行 / 8 / 名称 / 6 / 标签行）。
    List<RenderBox> cardChildren(WidgetTester tester, String exerciseId) {
      final card = find.byKey(Key('training-exercise-$exerciseId'));
      final column = find.descendant(of: card, matching: find.byType(Column));
      final flex = column.evaluate().first.renderObject! as RenderFlex;
      final boxes = <RenderBox>[];
      flex.visitChildren((child) => boxes.add(child as RenderBox));
      return boxes;
    }

    testWidgets('分类串与图标同一行、右对齐（不再独占名称下方一行）', (tester) async {
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await search(tester, '杠铃深蹲');
      await revealCard(tester, 'ex-barbell-squat');

      final category = find.descendant(
        of: find.byKey(const Key('training-exercise-ex-barbell-squat')),
        matching: find.text('腿 · 杠铃'),
      );
      expect(category, findsOneWidget);
      final text = tester.widget<Text>(category);
      expect(text.textAlign, TextAlign.right, reason: '分类串应右对齐到卡片右上角');

      // 与图标同一行：两者垂直区间重叠。
      final badge = find.descendant(
        of: find.byKey(const Key('training-exercise-ex-barbell-squat')),
        matching: find.byType(Icon),
      );
      final categoryCenter = tester.getCenter(category);
      final badgeRect = tester.getRect(badge.first);
      expect(
        categoryCenter.dy,
        inInclusiveRange(badgeRect.top, badgeRect.bottom),
        reason: '分类串应与图标行同高（原先在名称下方独占一行）',
      );
    });

    testWidgets('卡内构成：图标行 36 + 8 + 名称 + 6 + 标签行（无 Spacer 空洞）', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await search(tester, '杠铃深蹲');
      await revealCard(tester, 'ex-barbell-squat');

      final children = cardChildren(tester, 'ex-barbell-squat');
      expect(children, hasLength(5), reason: '图标行 / 间距 / 名称 / 间距 / 标签行');
      expect(children[0].size.height, 36, reason: '图标行（36dp 圆图标）');
      expect(children[1].size.height, LfDimens.spaceSmall, reason: '图标↔标题 8dp');
      expect(
        children[3].size.height,
        LfDimens.spaceTiny,
        reason: '标题↔标签 6dp（原为 12 + 分类行 + 4 ≈ 34dp）',
      );
    });

    testWidgets('行高 = 实测内容高（底距不再多 12；docs/32 需求 68）', (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await search(tester, '杠铃深蹲');
      await revealCard(tester, 'ex-barbell-squat');

      final children = cardChildren(tester, 'ex-barbell-squat');
      final content =
          children.fold<double>(0, (sum, box) => sum + box.size.height) + 24;
      final card = tester.getSize(
        find.byKey(const Key('training-exercise-ex-barbell-squat')),
      );
      // 需求 68（docs/32 §4 T3）：行高公式里历史遗留的 `+12` 已删除——
      // 卡片高度应等于内容高（卡内内边距上下对称 12）。误差 1dp 内；
      // 旧口径在这里会多出 +12（原来断言的就是那 12）。
      expect(
        card.height - content,
        inInclusiveRange(-1, 1),
        reason:
            '行高应为实测内容高（$content），不再额外 +12（实测差 '
            '${(card.height - content).toStringAsFixed(1)}）',
      );
      expect(
        card.height,
        lessThanOrEqualTo(140),
        reason: 'docs/29 §P5 目标 ≤140（新口径更矮，仍须守住上限）',
      );
    });

    testWidgets('2.0× 大字下卡片不溢出（行高按字号档加高）', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      // 溢出重定向：不收集的话 FlutterError 会直接判测试失败。
      final overflows = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) =>
          overflows.add(details.exceptionAsString().split('\n').first);
      addTearDown(() => FlutterError.onError = previous);

      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      expect(overflows, isEmpty, reason: overflows.join('\n'));
    });
  });

  group('P5 详情抽屉（需求 8）', () {
    Future<void> openSquatDetail(WidgetTester tester) async {
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await search(tester, '深蹲');
      await revealCard(tester, 'ex-barbell-squat');
      await tester.tap(
        find.byKey(const Key('training-exercise-ex-barbell-squat')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('替代动作是行卡（图标圆 + 名称 + 器械/难度 chip）', (tester) async {
      await openSquatDetail(tester);

      final alternatives = await exercises.listAlternatives('ex-barbell-squat');
      expect(alternatives, isNotEmpty);
      final first = alternatives.first;

      final row = find.byKey(Key('exercise-alternative-${first.id}'));
      expect(row, findsOneWidget, reason: '每行应有自己的 key（可点与可断言）');

      // 行卡内：名称 + 器械 chip（原先 subtitle 只有器械，没有难度、没有图标）。
      expect(
        find.descendant(of: row, matching: find.text(first.name)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text(first.equipment.label)),
        findsOneWidget,
        reason: '器械应作为 chip 留在行卡里',
      );
      expect(
        find.descendant(of: row, matching: find.byType(Container)),
        findsWidgets,
        reason: '图标圆（Container 圆底）',
      );
    });

    testWidgets('点替代动作原地切换详情（不叠层、不关窗）', (tester) async {
      await openSquatDetail(tester);

      final alternatives = await exercises.listAlternatives('ex-barbell-squat');
      final target = alternatives.first;

      await tester.tap(find.byKey(Key('exercise-alternative-${target.id}')));
      await tester.pumpAndSettle();

      // 标题换成了被点的动作，抽屉仍只有一个。
      expect(find.text(target.name), findsWidgets);
      final sheetTitles = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(target.name),
      );
      expect(sheetTitles, findsOneWidget, reason: '抽屉内容原地换成该动作详情');
      expect(find.byType(BottomSheet), findsOneWidget, reason: '不应叠出第二层抽屉');

      // 被点动作的替代动作里**不含它自己**（列表真的换了一份）。
      final next = await exercises.listAlternatives(target.id);
      expect(next.map((item) => item.id), isNot(contains(target.id)));
    });

    testWidgets('加载中显示骨架行，不先闪「暂无替代动作」', (tester) async {
      // 给该测试的库注入查询延迟，构造真实的 waiting 窗口。
      counter.delay = const Duration(milliseconds: 400);
      await tester.pumpWidget(
        MaterialApp(home: ExerciseLibraryPage(repository: countedRepository)),
      );
      await tester.pumpAndSettle();
      await search(tester, '深蹲');
      await revealCard(tester, 'ex-barbell-squat');

      await tester.tap(
        find.byKey(const Key('training-exercise-ex-barbell-squat')),
      );
      // 弹层入场一帧后、future 完成前（< 400ms）：应命中 waiting 分支。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('暂无同肌群的本地替代动作。'),
        findsNothing,
        reason: 'waiting 分支不得先显示空态文案',
      );
      expect(find.byType(SkeletonBox), findsWidgets, reason: 'waiting 分支应有骨架行');

      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBox), findsNothing, reason: '加载完成后骨架行应消失');
    });
  });

  group('P5 流畅度（需求 11）', () {
    testWidgets('连续输入只触发 1 次查询（300ms 防抖）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ExerciseLibraryPage(repository: countedRepository)),
      );
      await tester.pumpAndSettle();

      counter.selects = 0;
      final field = find.byKey(const Key('training-exercise-search'));
      // 逐字输入，间隔 < 防抖窗口：只有最后一次应落地。
      for (final char in ['深', '蹲', '训']) {
        await tester.enterText(field, char);
        await tester.pump(const Duration(milliseconds: 100));
      }
      // 尚未到期：仍未查询。
      expect(counter.selects, 0, reason: '防抖窗口内不应查库');

      await tester.pump(ExerciseLibraryPage.searchDebounce);
      await tester.pumpAndSettle();
      expect(counter.selects, 1, reason: '5 次输入合并为 1 次查询');
    });

    testWidgets('重复输入同一关键词也只查一次（防抖去抖）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ExerciseLibraryPage(repository: countedRepository)),
      );
      await tester.pumpAndSettle();

      counter.selects = 0;
      final field = find.byKey(const Key('training-exercise-search'));
      for (var i = 0; i < 5; i++) {
        await tester.enterText(field, '深蹲');
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(ExerciseLibraryPage.searchDebounce);
      await tester.pumpAndSettle();
      expect(counter.selects, 1);
    });

    testWidgets('聚焦/失焦与键盘 inset 变化不触发新查询', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ExerciseLibraryPage(repository: countedRepository)),
      );
      await tester.pumpAndSettle();

      counter.selects = 0;
      // 聚焦搜索框（真实场景里键盘随之弹出）。
      await tester.tap(find.byKey(const Key('training-exercise-search')));
      await tester.pumpAndSettle();

      // 逐条重建路径，全部不该产生新查询：
      // ① 键盘弹出 = inset 变化 ⇒ MediaQuery 变；
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      tester.binding.handleMetricsChanged();
      await tester.pumpAndSettle();
      // ② 旋转/分屏 = 尺寸变化（默认视口 800×600，换成仍在手机比例内的
      //    700×1000，避免把顶栏挤溢出这种无关失败混进来）；
      tester.view.physicalSize = const Size(700, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      tester.binding.handleMetricsChanged();
      await tester.pumpAndSettle();
      // ③ 宿主重建（键盘弹出时根 widget 也会重建；这一条是**确定会驱动
      //    整棵树重建**的路径——①② 在测试环境里未必广播到 MediaQuery）。
      //    同 runtimeType 重挂 ⇒ State 保留、不重跑 initState。
      await tester.pumpWidget(
        MaterialApp(home: ExerciseLibraryPage(repository: countedRepository)),
      );
      await tester.pumpAndSettle();

      expect(
        counter.selects,
        0,
        reason: 'future 提在 initState，重建不得重查 DB（原实现在 build 里建 future）',
      );
    });
  });
}

/// 数 `runSelect` 次数并可注入延迟（drift `QueryInterceptor`）。
///
/// 延迟用来构造「查询还没回来」的窗口：内存库的查询通常在同一 microtask
/// 后就完成，waiting 分支根本没有机会上屏（实测 `pump()` 一帧就已经拿到
/// 结果），骨架行因此测不到。
final class _CountingInterceptor extends QueryInterceptor {
  int selects = 0;
  Duration? delay;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    final pending = super.runSelect(executor, statement, args);
    final hold = delay;
    if (hold == null) return pending;
    return Future<void>.delayed(hold).then((_) => pending);
  }
}

final class _Ids implements IdGenerator {
  _Ids(this._prefix);

  final String _prefix;
  int _value = 0;

  @override
  String next() => '$_prefix-${_value++}';
}
