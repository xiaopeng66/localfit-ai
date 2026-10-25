import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';

/// 2.0-6g：今日页「AI 创作」入口 → route-level AI 工作台。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;
  final now = DateTime(2026, 9, 15, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => database.close());

  testWidgets('dashboard entry opens the route-level AI workbench', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ids = _IncrementingIdGenerator();
    final mealRepository = MealRepository(
      database: database,
      idGenerator: ids,
      clock: FixedAppClock(now.toUtc()),
    );
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.dashboard,
        mealRepository: mealRepository,
        now: now,
      ),
    );
    await tester.pumpAndSettle();

    // 入口是今日页的 AI 卡片（docs/21 §5.1 `cta-ai-workbench`，
    // 旧 AppBar 动作区的 `<Key>dashboard-ai-workbench-entry</Key>` 已随页头一起去掉）。
    final entry = find.byKey(const Key('cta-ai-workbench'));
    // 卡片在首屏下方，懒加载列表不滚过去就不会构建。
    await tester.scrollUntilVisible(
      entry,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.text('AI 创作'), findsOneWidget);
    // docs/32 §4 T6c：画廊渲染 `aiStarters` 的六张卡（旧「未配置」空态
    // 随任务注入退役——启动卡是静态规格，永远在全）。
    expect(
      find.byKey(const Key('ai-workbench-task-menu-normalize')),
      findsOneWidget,
    );
    expect(find.text('饮食'), findsOneWidget);
    expect(find.text('训练与搭配'), findsOneWidget);

    // drift stream 取消会留一个微任务定时器，先卸载再泵一帧收尾。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}

final class _IncrementingIdGenerator implements IdGenerator {
  int _next = 1;
  @override
  String next() => 'id-${_next++}';
}
