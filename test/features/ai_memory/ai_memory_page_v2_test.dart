import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/presentation/ai_memory_page.dart';

/// 【v2（design/round8/memory-v2.html，2026-10-30 用户批准实施）】
///
/// 结构门禁：设置项全部收进 ⚙️ 弹层、首屏只剩「统计行 + 搜索 + 记忆列表」；
/// 记忆按领域分组（置顶组最上）、类型有彩色标；搜索时退化为平铺并高亮。
void main() {
  late AppDatabase db;
  late AiMemoryRepository memories;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    memories = AiMemoryRepository(
      database: db,
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 30, 9)),
    );
  });

  tearDown(() async => db.close());

  /// drift 的流在取消时会排一个 0 时长 Timer：拆树后泵一帧让它跑掉
  /// （与 `ai_memory_page_test.dart` 的 `disposePage` 同一手法；否则
  /// 「A Timer is still pending」会让用例末尾假红）。
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AiMemoryPage(repository: memories),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('首屏没有设置项：开关/待确认/整理/规则/清空都不在（v2 收进 ⚙️）', (tester) async {
    await memories.remember(text: '喜欢清淡');
    await pumpPage(tester);

    for (final key in const [
      'ai-memory-injection-toggle',
      'ai-memory-auto-extract-toggle',
      'ai-memory-pending-row',
      'ai-memory-hygiene',
      'ai-memory-rules',
      'ai-memory-clear-all',
    ]) {
      expect(
        find.byKey(Key(key)),
        findsNothing,
        reason: '$key 属于设置项，v2 首屏不该出现',
      );
    }
    // 首屏三件套都在。
    expect(find.byKey(const Key('ai-memory-usage')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-search')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-list')), findsOneWidget);
    // 两个常驻动作还在（按日期回看 / 复制全部）。
    expect(find.byKey(const Key('ai-memory-asof')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-copy-all')), findsOneWidget);
    await drain(tester);
  });

  testWidgets('⚙️ 打开设置弹层：五项设置齐全（注入/自动提炼/规则/复制/清空）', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const Key('ai-memory-settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-memory-settings-sheet')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-injection-toggle')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-rules')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-copy-all-sheet')), findsOneWidget);
    expect(find.byKey(const Key('ai-memory-clear-all')), findsOneWidget);
    await drain(tester);
  });

  testWidgets('按领域分组：组头带领域名与条数（v2）', (tester) async {
    await memories.remember(text: '早餐喜欢燕麦', domain: AiMemoryDomain.nutrition);
    await memories.remember(text: '周三晚上练腿', domain: AiMemoryDomain.training);
    await pumpPage(tester);

    // 组头 = 领域名 + `· n`；两个领域各一组。
    expect(find.text('饮食'), findsWidgets);
    expect(find.text('训练'), findsWidgets);
    expect(find.text('· 1'), findsWidgets, reason: '每组各 1 条');
    await drain(tester);
  });

  testWidgets('置顶组排在最前（v2）', (tester) async {
    await memories.remember(text: '普通饮食记忆', domain: AiMemoryDomain.nutrition);
    await memories.remember(
      text: '置顶的训练记忆',
      domain: AiMemoryDomain.training,
      pinned: true,
    );
    await pumpPage(tester);

    final pinnedHeader = tester.getRect(find.text('置顶'));
    final nutritionHeader = tester.getRect(find.text('饮食'));
    expect(
      pinnedHeader.top,
      lessThan(nutritionHeader.top),
      reason: '置顶组必须在领域组之前',
    );
    await drain(tester);
  });

  testWidgets('搜索态：取消分组、命中词垫底色（v2）', (tester) async {
    await memories.remember(text: '早餐喜欢燕麦酸奶', domain: AiMemoryDomain.nutrition);
    await memories.remember(text: '周三晚上练腿', domain: AiMemoryDomain.training);
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('ai-memory-search')), '燕麦');
    await tester.pumpAndSettle();

    expect(find.text('置顶'), findsNothing, reason: '搜索态不分组');
    expect(find.text('饮食'), findsNothing, reason: '搜索态不分组');
    // 命中的一条在、没命中的不在。范围限定在列表里：搜索框自身也含「燕麦」。
    final list = find.byKey(const Key('ai-memory-list'));
    expect(
      find.descendant(of: list, matching: find.textContaining('燕麦')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: list, matching: find.textContaining('练腿')),
      findsNothing,
    );
    await drain(tester);
  });

  testWidgets('320dp × 2.0× 不溢出（v2 首屏 + 设置弹层）', (tester) async {
    await memories.remember(
      text: '早餐喜欢燕麦酸奶碗',
      domain: AiMemoryDomain.nutrition,
    );
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1200),
            textScaler: TextScaler.linear(2.0),
          ),
          child: AiMemoryPage(repository: memories),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '首屏在极限字号下不溢出');

    await tester.tap(find.byKey(const Key('ai-memory-settings')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '设置弹层在极限字号下不溢出');
    await drain(tester);
  });
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'mem-${value++}';
}
