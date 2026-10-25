import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_quick_stats_row.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';

/// `R1`（`docs/56` §3 R1 / objective【交付】「两行数字卡」）：
/// **`n / n` 拆成上下两行，第二行右对齐，预留高度不撑卡。**
///
/// 修前：`_MetricValue` 用 `Wrap`（`crossAxisAlignment: end`）把
/// 「大数字 / 单位 / 小号后缀」排成**一行可换行**的弹性布局 ——
/// 放不下时整段换行且左对齐，行数不稳定 ⇒ **卡高随数字长度变化**。
///
/// 修后：第一行 `Row(大号当前值 + 单位)`；第二行 `Align(centerRight)` 包
/// `suffix`（`maxLines: 1` + ellipsis）；`suffix == null` 也渲染**同高空槽**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/steps');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') {
            return <Object?, Object?>{
              'status': 'ok',
              'counter': 8432,
              'atMs': 1,
            };
          }
          if (call.method == 'requestPermission') {
            return <Object?, Object?>{'status': 'granted'};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SizedBox(width: 195, child: child)),
  );

  WaterSummary summary({required double consumed, double? target}) =>
      WaterSummary(
        consumedMl: consumed,
        targetMl: target,
        records: [
          WaterIntakeRecord(
            id: 'w1',
            localDate: '2026-10-24',
            amountMl: consumed,
            recordedAt: DateTime.utc(2026, 10, 24, 2),
            createdAt: DateTime.utc(2026, 10, 24, 2),
            updatedAt: DateTime.utc(2026, 10, 24, 2),
          ),
        ],
      );

  group('R1 · 两行形态：第二行右对齐', () {
    testWidgets('目标段在第二行且贴卡内容右边缘（≤1dp）', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(WaterStatCard(water: summary(consumed: 750, target: 2000))),
      );
      await tester.pumpAndSettle();

      // 卡有 14dp 内衬（A `.metric-card{padding:14px}`），所以「内容右边缘」
      // = 卡右边缘 − 14；右对齐的判据要对**内容区**成立。
      const cardPadding = 14.0;
      final card = tester.getRect(find.byType(WaterStatCard));
      final value = tester.getRect(
        find.byKey(const Key('dashboard-water-value')),
      );
      final target = tester.getRect(
        find.byKey(const Key('dashboard-water-target-inline')),
      );

      expect(
        target.top,
        greaterThanOrEqualTo(value.bottom - 0.5),
        reason:
            '目标段必须在**第二行**（修前同一行 Wrap：'
            'target.top=${target.top} / value.bottom=${value.bottom}）',
      );
      final contentRight = card.right - cardPadding;
      expect(
        contentRight - target.right,
        lessThanOrEqualTo(1.0),
        reason: '第二行必须右对齐（内容区右侧留白 ${contentRight - target.right}）',
      );
    });
  });

  group('R1 · 预留高度：三种数字长度 / 与无目标态卡高一致', () {
    testWidgets('750 / 12,345 / 123,456 三种长度：卡高逐个相等（±0.5）', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final heights = <String, double>{};
      for (final (consumed, target) in [
        (750.0, 2000.0),
        (12345.0, 20000.0),
        (123456.0, 200000.0),
      ]) {
        await tester.pumpWidget(
          host(
            WaterStatCard(
              water: summary(consumed: consumed, target: target),
            ),
          ),
        );
        await tester.pumpAndSettle();
        heights[consumed.toString()] = tester
            .getSize(find.byType(WaterStatCard))
            .height;
      }
      final values = heights.values.toList();
      for (var i = 1; i < values.length; i++) {
        expect(
          values[i],
          closeTo(values[0], 0.5),
          reason: '卡高随数字长度变化了：$heights（R1：预留高度，不许撑卡）',
        );
      }
    });

    testWidgets('「有目标」与「没目标」卡高一致（空槽占位）', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        host(WaterStatCard(water: summary(consumed: 750, target: 2000))),
      );
      await tester.pumpAndSettle();
      final withTarget = tester.getSize(find.byType(WaterStatCard)).height;

      await tester.pumpWidget(
        host(WaterStatCard(water: summary(consumed: 750))),
      );
      await tester.pumpAndSettle();
      final withoutTarget = tester.getSize(find.byType(WaterStatCard)).height;

      expect(
        withoutTarget,
        closeTo(withTarget, 0.5),
        reason:
            '没目标时卡高 $withoutTarget ≠ 有目标 $withTarget'
            '（R1：suffix 为 null 也要留同高空槽）',
      );
    });

    testWidgets('最长数字 + 2.0× 不溢出，目标段仍单行', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        host(WaterStatCard(water: summary(consumed: 123456, target: 200000))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(const Key('dashboard-water-target-inline')),
      );
      expect(paragraph.maxLines, 1, reason: '第二行 maxLines: 1（超长先省略）');
    });
  });

  group('R1 · 步数卡同样两行', () {
    testWidgets('目标段在数值下方', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = StepsRepository(
        database: database,
        channel: StepsChannel(),
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime.utc(2026, 10, 24, 2)),
      );

      await tester.pumpWidget(
        host(
          StepsStatCard(
            repository: repository,
            localDate: '2026-10-24',
            goal: 10000,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final value = tester.getRect(
        find.byKey(const Key('dashboard-steps-value')),
      );
      final target = tester.getRect(
        find.byKey(const Key('dashboard-steps-target-inline')),
      );
      expect(
        target.top,
        greaterThanOrEqualTo(value.bottom - 0.5),
        reason: '步数卡目标段也必须在第二行',
      );
      // 步数仓储订阅了一条 drift 流：卸载整棵树让 stream-close 定时器跑掉，
      // 否则 teardown 报「Pending timers」（与其它 drift 测试同一手法）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });
}

final class _Ids implements IdGenerator {
  int _v = 0;

  @override
  String next() => 'id-${_v++}';
}
