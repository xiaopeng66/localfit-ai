import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_quick_stats_row.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';

/// 需求 10（docs/60 §11「饮水/步数卡**内容**高度对齐」）：**两卡内的每一行
/// 必须落在同一条水平线上**（标题行 / 数值行 / 第二行 / 进度条）。
///
/// 【取帧后的实测（2026-10-25）】外层 `IntrinsicHeight` + `stretch` 已经把
/// **卡高**取齐了，偏心在**卡内行距**：两卡对同一条间隙用了不同的值——
/// * 饮水卡：标题行之后 `SizedBox(3)`，数值行与进度条之间 `_metricTrackMarginTop`(5)；
/// * 步数卡：标题行之后 `_metricGap`(6)，数值行与进度条之间也是 `_metricGap`(6)。
///
/// ⇒ 数值行差 **3dp**、进度条差 **4dp**。两张卡并排时肉眼可见「数字不在一条线
/// 上、进度条一高一低」——正是用户说的「内容没对齐」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('localfit/steps');

  late AppDatabase database;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'read') {
            return <Object?, Object?>{
              'status': 'ok',
              'counter': 8432,
              'atMs': 1,
            };
          }
          return null;
        });
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  WaterSummary waterWithData() => WaterSummary(
    consumedMl: 1250,
    targetMl: 2000,
    records: [
      WaterIntakeRecord(
        id: 'w1',
        localDate: '2026-10-25',
        amountMl: 1250,
        recordedAt: DateTime.utc(2026, 10, 25, 2),
        createdAt: DateTime.utc(2026, 10, 25, 2),
        updatedAt: DateTime.utc(2026, 10, 25, 2),
      ),
    ],
  );

  Future<void> pumpRow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412 * 2, 320 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final repository = StepsRepository(
      database: database,
      channel: StepsChannel(),
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 25, 10)),
    );
    // 【2026-10-26 前置】步数首次读只立基线、不落行（用户：「读不到」的
    // 真假 0 之辨）。这里先同步两次，把一行**真实**数据准备好，再量两卡的
    // 行基线——否则卡上是「刚开始读取」空态，根本没有数值行可量。
    await repository.syncToday('2026-10-25');
    await repository.syncToday('2026-10-25');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: DashboardQuickStatsRow(
              water: waterWithData(),
              stepsRepository: repository,
              localDate: '2026-10-25',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 先卸页面（取消 drift 流订阅）→ pump 一拍 → 关库（顺序反了会挂到超时）。
  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await database.close();
  }

  testWidgets('两卡「数值行」在同一水平线（差 ≤1dp）', (tester) async {
    await pumpRow(tester);
    final water = tester.getRect(
      find.byKey(const Key('dashboard-water-value')),
    );
    final steps = tester.getRect(
      find.byKey(const Key('dashboard-steps-value')),
    );
    expect(
      (water.top - steps.top).abs(),
      lessThanOrEqualTo(1.0),
      reason:
          '饮水数值 top=${water.top} / 步数数值 top=${steps.top} ——'
          '两卡标题行之后用了不同的间隙（3 vs 6）',
    );
    await disposePage(tester);
  });

  testWidgets('两卡「第二行（目标段）」在同一水平线（差 ≤1dp）', (tester) async {
    await pumpRow(tester);
    final water = tester.getRect(
      find.byKey(const Key('dashboard-water-target-inline')),
    );
    final steps = tester.getRect(
      find.byKey(const Key('dashboard-steps-target-inline')),
    );
    expect(
      (water.top - steps.top).abs(),
      lessThanOrEqualTo(1.0),
      reason: '饮水目标 top=${water.top} / 步数目标 top=${steps.top}',
    );
    await disposePage(tester);
  });

  testWidgets('两卡「进度条」在同一水平线（差 ≤1dp）', (tester) async {
    await pumpRow(tester);
    final water = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('dashboard-stat-water')),
        matching: find.byType(LfProgressBar),
      ),
    );
    final steps = tester.getRect(
      find.descendant(
        of: find.byKey(const Key('dashboard-stat-steps')),
        matching: find.byType(LfProgressBar),
      ),
    );
    expect(
      (water.top - steps.top).abs(),
      lessThanOrEqualTo(1.0),
      reason:
          '饮水进度条 top=${water.top} / 步数进度条 top=${steps.top} ——'
          '水卡用 `_metricTrackMarginTop`(5)、步数卡用 `_metricGap`(6)',
    );
    await disposePage(tester);
  });

  testWidgets('两卡标题行也在同一水平线（对照：这条本来就对）', (tester) async {
    await pumpRow(tester);
    final water = tester.getRect(find.text('饮水'));
    final steps = tester.getRect(find.text('步数'));
    expect((water.top - steps.top).abs(), lessThanOrEqualTo(1.0));
    await disposePage(tester);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'qa-${_value++}';
}
