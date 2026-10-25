import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';

import '../../support/food_fixture.dart';

/// Round7 阶段 4 · 渲染审看抓到的两处缺陷（`renders/4a-training/` 的实测帧）。
///
/// ⑳ **容量图的空柱画不出来**：`FractionallySizedBox(heightFactor: 0)` 把
/// `Container` 的 `minHeight: 4` 一并压成 0——「无训练日」那一列在白卡上空白。
/// A（`app.js:210`）对 0 分钟日写的是 `height:3px` 的**最小可见柱**：一个
/// 「这周有 7 天、这天是空的」的骨架必须画得出来，否则读起来像数据缺失。
/// ㉑ **2.0× 下三段统计被 ellipsis 裁成「0…」**：A 的 `.training-overview b`
/// 是 750 字重 + `small` 单位，窄屏大字下**不裁字**；本仓口径是「放不下就
/// 等比缩小」（`fitsRow` / `FittedBox.scaleDown` 一族，与 2B 的记录页、2A 的
/// 值行同一条）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ExerciseRepository exercises;
  late WorkoutPlanRepository plans;
  late WorkoutSessionRepository sessions;
  final now = DateTime(2026, 10, 14, 10);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids('ex'),
      clock: FixedAppClock(now),
    );
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: _Ids('plan'),
      clock: FixedAppClock(now),
    );
    sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: _Ids('session'),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() => database.close());

  Future<void> pump(
    WidgetTester tester, {
    double width = 360,
    double height = 900,
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: TrainingPage(
          exerciseRepository: exercises,
          workoutPlanRepository: plans,
          workoutSessionRepository: sessions,
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('⑳ 容量图：无训练日也画出最小可见柱（7 列都不空）', (tester) async {
    // 只安排一次真实训练（周一），其余 6 天 0 分钟。
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '周一练',
        days: [
          WorkoutPlanDayDraft(
            weekday: 1,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-bench-press',
                targetSets: 3,
                targetReps: 8,
                targetWeightKg: 60,
              ),
            ],
          ),
        ],
      ),
    );
    final sessionId = await sessions.start(
      localDate: '2026-10-12',
      planId: planId,
    );
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-bench-press',
        weightKg: 60,
        reps: 8,
      ),
    );
    await sessions.finish(sessionId);

    await pump(tester);

    final chart = find.byKey(const Key('training-capacity-chart'));
    expect(chart, findsOneWidget);
    // 每一列的柱（`Container`）都必须在：用「柱底 = 图表底」逐列量。
    final chartRect = tester.getRect(chart);
    // 柱现在是 `DecoratedBox`（修复后不再用 `Container` 撑高度）。
    final bars = find
        .descendant(
          of: chart,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).borderRadius != null,
          ),
        )
        .evaluate()
        .toList();
    expect(bars.length, 7, reason: '7 天各一列柱');
    for (final bar in bars) {
      final rect = tester.getRect(find.byWidget(bar.widget));
      expect(
        rect.height,
        greaterThanOrEqualTo(3),
        reason: '0 分钟日也要有最小可见柱（A 是 3px）：高度 ${rect.height}',
      );
      expect(
        (rect.bottom - chartRect.bottom).abs(),
        lessThan(1),
        reason: '柱底贴图表底',
      );
    }
  });

  testWidgets('㉑ 2.0×：三段统计不裁字（不出现 ellipsis 省略号）', (tester) async {
    await pump(tester, width: 320, scale: 2);

    // 两张三段统计卡同口径（hero + 周统计卡）：都不得 ellipsis 裁字。
    for (final key in const ['training-hero-count', 'training-hero-duration']) {
      final text = tester.widget<Text>(
        find
            .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
            .first,
      );
      expect(
        text.overflow,
        anyOf(isNull, TextOverflow.visible, TextOverflow.clip),
        reason: '$key 在 2.0× 下不许用 ellipsis 静默裁字',
      );
      // 且真的没有溢出发生（RenderFlex/文本溢出都会被 takeException 捕获）。
      expect(tester.takeException(), isNull);
    }

    // 周统计卡（`_WeekStat`）——与 hero 是同一屏的两处。
    final weekCard = find.byKey(const Key('training-week-stats'));
    expect(weekCard, findsOneWidget);
    for (final text in tester.widgetList<Text>(
      find.descendant(of: weekCard, matching: find.byType(Text)),
    )) {
      expect(
        text.overflow,
        anyOf(isNull, TextOverflow.visible, TextOverflow.clip),
        reason: '周统计卡的「${text.data}」不许 ellipsis 裁字',
      );
    }
  });
}

final class _Ids implements IdGenerator {
  _Ids(this._prefix);

  final String _prefix;
  int _value = 0;

  @override
  String next() => '$_prefix-${_value++}';
}
