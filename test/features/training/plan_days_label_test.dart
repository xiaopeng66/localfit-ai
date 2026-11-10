import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_create_page.dart';

import '../../support/food_fixture.dart';

/// 需求 12（docs/60 §11「训练计划天数按钮文字水平居中」）。
///
/// 【取帧后的实测（2026-10-25）】不是「文字略偏左」这么轻——真机档
/// （412dp / 1.0×）下七枚胶囊各只分到 ≈50dp，而 `LfPillButton` 的标签
/// `Text` 是**可换行**的：`3天` 被折成上下两行（「3」/「天」），
/// 两行还都贴着胶囊左边。用户看到的是一列歪着的数字 + 碎字。
///
/// 判据（两条都要）：
/// 1. **单行**：标签不折行（`softWrap == false`）；
/// 2. **居中**：文字几何中心与胶囊几何中心偏差 ≤ 1dp（`getCenter` 差值）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ExerciseRepository exercises;
  late WorkoutPlanRepository plans;
  final now = DateTime(2026, 10, 25, 10);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: WorkoutPlanCreatePage(
          exerciseRepository: exercises,
          workoutPlanRepository: plans,
          workoutPlanProvider: const _NeverCalledProvider(),
          loadWorkoutPlanDisclosure: LoadWorkoutPlanDisclosure(
            configurationReader: const _StubConfigReader(),
          ),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Iterable<Text> dayTexts(WidgetTester tester) sync* {
    for (final d in const [1, 2, 3, 4, 5, 6, 7]) {
      final finder = find.descendant(
        of: find.byKey(Key('plan-days-$d')),
        matching: find.byType(Text),
      );
      for (final text in tester.widgetList<Text>(finder)) {
        yield text;
      }
    }
  }

  testWidgets('天数标签单行不折行（「3天」不许断成两行）', (tester) async {
    await pumpPage(tester);
    final labels = dayTexts(tester).toList();
    expect(labels, isNotEmpty, reason: '七枚天数按钮都得在');
    for (final label in labels) {
      expect(
        label.softWrap,
        isFalse,
        reason: '「${label.data}」折行了——412dp 下七枚各 ≈50dp，可换行的标签会被断成两行',
      );
    }
  });

  testWidgets('天数文字几何中心与胶囊中心偏差 ≤ 1dp', (tester) async {
    await pumpPage(tester);
    for (final d in const [1, 3, 7]) {
      final pill = tester.getRect(find.byKey(Key('plan-days-$d')));
      final text = tester.getRect(
        find
            .descendant(
              of: find.byKey(Key('plan-days-$d')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(
        (text.center.dx - pill.center.dx).abs(),
        lessThanOrEqualTo(1.0),
        reason:
            '第 $d 天的文字中心 ${text.center.dx} ≠ 胶囊中心 ${pill.center.dx}'
            '（差 ${(text.center.dx - pill.center.dx).abs()}dp）',
      );
      expect(
        (text.center.dy - pill.center.dy).abs(),
        lessThanOrEqualTo(1.0),
        reason: '第 $d 天的文字垂直方向也偏心',
      );
    }
  });

  testWidgets('320dp × 2.0× 不溢出（七枚同排）', (tester) async {
    tester.view.physicalSize = const Size(320, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 1400),
            textScaler: TextScaler.linear(2),
          ),
          child: WorkoutPlanCreatePage(
            exerciseRepository: exercises,
            workoutPlanRepository: plans,
            workoutPlanProvider: const _NeverCalledProvider(),
            loadWorkoutPlanDisclosure: LoadWorkoutPlanDisclosure(
              configurationReader: const _StubConfigReader(),
            ),
            now: now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'rd-${_value++}';
}

final class _NeverCalledProvider implements WorkoutPlanProvider {
  const _NeverCalledProvider();

  @override
  Future<AiWorkoutPlanDraft> generate(
    AiWorkoutPlanRequest request, {
    WorkoutPlanCancellationToken? cancellationToken,
  }) {
    throw StateError('测试不得生成训练计划（会真的发请求）');
  }
}

final class _StubConfigReader implements AiProviderConfigurationReader {
  const _StubConfigReader();

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => null;
}
