import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_create_page.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';

/// 训练计划创建页（AI 表单）——2026-10-16 用户实测三条：
///  * 「训练计划生成应由 AI **从动作库中选动作**」——候选原本只有用户点选的
///    **那 1 条**，AI 根本没得选；
///  * 「根据所填目标（**目标不能是可选**）」——目标原本可留空；
///  * 「生成的计划界面太丑 / 预览显示 ex-xxx」——预览原本直接画动作 id。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ExerciseRepository exercises;
  late _RecordingProvider provider;
  final now = DateTime(2026, 10, 16, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now.toUtc()),
    );
    provider = _RecordingProvider();
  });

  tearDown(() => database.close());

  /// 灌 N 条动作（覆盖「整库 > 60」这一档：种子库 312 条）。
  Future<void> seedExercises(int count) async {
    for (var i = 0; i < count; i++) {
      await exercises.create(
        NewExercise(
          name: '动作${i.toString().padLeft(3, '0')}',
          muscleGroup: MuscleGroup.chest,
          equipment: Equipment.barbell,
        ),
      );
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: WorkoutPlanCreatePage(
          exerciseRepository: exercises,
          workoutPlanRepository: WorkoutPlanRepository(
            database: database,
            idGenerator: _Ids(),
            clock: FixedAppClock(now.toUtc()),
          ),
          workoutPlanProvider: provider,
          loadWorkoutPlanDisclosure: LoadWorkoutPlanDisclosure(
            configurationReader: _FixedConfiguration(),
          ),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('目标必填：不填就点下一步 → 本地拦下并给出人话，不发起 AI 请求', (tester) async {
    await seedExercises(3);
    await pumpPage(tester);

    // 目标字段不再是「可选」：标签行不再带「（可选）」标记。
    expect(find.textContaining('（可选'), findsNothing);

    // 2026-10-23：不再要求先点动作，只填目标就能前进。
    await tester.tap(find.text('下一步：查看披露'));
    await tester.pumpAndSettle();

    expect(find.text('请填写训练目标。'), findsOneWidget);
    expect(provider.requests, isEmpty, reason: '本地校验没过就不该发请求');
  });

  testWidgets('候选动作 = 整库（>60 条也全给 AI），不是「用户点选的那 1 条」', (tester) async {
    await seedExercises(75);
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('plan-create-goal')),
      '增肌，练胸背腿',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步：查看披露'));
    await tester.pumpAndSettle();
    // 披露页 → 确认继续（按钮文案见披露页实现）。
    await tester.tap(find.text('确认生成'));
    await tester.pumpAndSettle();

    expect(provider.requests, hasLength(1));
    final request = provider.requests.single;
    expect(request.goalText, '增肌，练胸背腿');
    expect(
      request.exercises.length,
      75,
      reason: '整库 75 条都要发给 AI（旧实现只发点选的那 1 条）',
    );
  });

  // 2026-10-23 用户：「先选/填目标关键词，再由 AI 从动作库选动作」。
  testWidgets('目标关键词 chip：点一下填进目标、再点移除；不再要求先选动作', (tester) async {
    await seedExercises(3);
    await pumpPage(tester);

    expect(
      find.byKey(const Key('plan-create-exercise-hint')),
      findsOneWidget,
      reason: '表单要说清 AI 会从动作库选动作',
    );
    expect(find.text('选择训练动作'), findsNothing, reason: '不再让用户先点一条动作');

    await tester.tap(find.byKey(const Key('plan-goal-keyword-增肌')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plan-goal-keyword-减脂')));
    await tester.pumpAndSettle();
    var field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('plan-create-goal')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, '增肌、减脂');

    // 再点一次 = 移除。
    await tester.tap(find.byKey(const Key('plan-goal-keyword-减脂')));
    await tester.pumpAndSettle();
    field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('plan-create-goal')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.controller!.text, '增肌');
  });

  testWidgets('预览显示动作名而不是 id', (tester) async {
    await seedExercises(3);
    provider.draft = AiWorkoutPlanDraft(
      name: '示范计划',
      warnings: const [],
      days: [
        AiWorkoutPlanDayDraft(
          weekday: 1,
          entries: [
            PlannedExerciseDraft(
              exerciseId: (await exercises.search('动作001')).single.id,
              targetSets: 3,
              targetReps: 10,
              targetWeightKg: 40,
            ),
          ],
        ),
      ],
    );
    await pumpPage(tester);

    await tester.enterText(find.byKey(const Key('plan-create-goal')), '增肌');
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步：查看披露'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认生成'));
    await tester.pumpAndSettle();

    expect(find.textContaining('动作001'), findsOneWidget);
    expect(
      find.textContaining('exercise-'),
      findsNothing,
      reason: '预览里不许出现内部 id（用户看到的是动作名）',
    );
  });
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'exercise-${value++}';
}

final class _RecordingProvider implements WorkoutPlanProvider {
  final List<AiWorkoutPlanRequest> requests = [];
  AiWorkoutPlanDraft? draft;

  @override
  Future<AiWorkoutPlanDraft> generate(
    AiWorkoutPlanRequest request, {
    WorkoutPlanCancellationToken? cancellationToken,
  }) async {
    requests.add(request);
    return draft ??
        AiWorkoutPlanDraft(
          name: 'AI 计划',
          warnings: const [],
          days: [
            AiWorkoutPlanDayDraft(
              weekday: 1,
              entries: [
                PlannedExerciseDraft(
                  exerciseId: request.exercises.first.id,
                  targetSets: 3,
                  targetReps: 10,
                ),
              ],
            ),
          ],
        );
  }
}

final class _FixedConfiguration implements AiProviderConfigurationReader {
  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      AiProviderConfiguration(
        baseUrl: 'https://api.example.com/v1',
        model: 'test-model',
        protocol: AiProviderProtocol.chatCompletions,
      );
}
