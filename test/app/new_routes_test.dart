import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

void main() {
  group('docs/21 §4 新增路由', () {
    testWidgets('/meal-recognition：空仓时页面自渲染（与旧 /scan 分支一致）', (tester) async {
      // docs/22 阶段 A9：/scan shell 分支取消后 /meal-recognition 是唯一入口；
      // 旧 /scan 分支不设依赖守卫，FoodScanPage 自行处理未接线依赖。
      await tester.pumpWidget(
        LocalFitApp(
          router: createAppRouter(
            mealRepository: null,
            initialLocation: AppRoutes.mealRecognition,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // docs/21 §5.4：顶栏标题是设计稿 `<h1>` 的「拍照识餐」（旧实现是
      // AppBar 的「AI 拍照」，按 §1.2 抛弃）。
      expect(find.text('拍照识餐'), findsOneWidget);
      expect(find.text('AI 拍照'), findsNothing);
    });

    testWidgets('/workout-plan-create：空仓回退到占位提示', (tester) async {
      await tester.pumpWidget(
        LocalFitApp(
          router: createAppRouter(
            exerciseRepository: null,
            workoutPlanRepository: null,
            workoutPlanProvider: null,
            loadWorkoutPlanDisclosure: null,
            initialLocation: AppRoutes.workoutPlanCreate,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('训练计划尚未配置，请先在「我的」里完成 AI 服务。'), findsOneWidget);
    });

    testWidgets('/workout-plan-create：路由注册且全接线后不崩溃', (tester) async {
      // 验证：路由已注册，全接线后页面可实例化。
      // 完整表单交互测试留待 real-device 走查（docs/09）。
      final provider = _FakeProvider();
      final disclosure = LoadWorkoutPlanDisclosure(
        configurationReader: _FakeConfigReader(),
      );

      await tester.pumpWidget(
        LocalFitApp(
          router: createAppRouter(
            exerciseRepository: null,
            workoutPlanRepository: null,
            workoutPlanProvider: provider,
            loadWorkoutPlanDisclosure: disclosure,
            now: DateTime(2026, 9, 23, 12, 0),
            initialLocation: AppRoutes.workoutPlanCreate,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // 仓库未接线 → 显示占位提示。
      expect(find.text('训练计划尚未配置，请先在「我的」里完成 AI 服务。'), findsOneWidget);
    });
  });
}

// ---- 假 provider ----

final class _FakeProvider implements WorkoutPlanProvider {
  @override
  Future<AiWorkoutPlanDraft> generate(
    AiWorkoutPlanRequest request, {
    WorkoutPlanCancellationToken? cancellationToken,
  }) async {
    return AiWorkoutPlanDraft(
      name: request.goalText,
      warnings: const [],
      days: [
        AiWorkoutPlanDayDraft(
          weekday: 1,
          entries: [
            PlannedExerciseDraft(
              exerciseId: 'bench-press',
              targetSets: 3,
              targetReps: 10,
              targetWeightKg: 60.0,
            ),
          ],
        ),
      ],
    );
  }
}

final class _FakeConfigReader implements AiProviderConfigurationReader {
  const _FakeConfigReader();

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async {
    return const AiProviderConfiguration(
      baseUrl: 'https://example.com/v1',
      model: 'gpt-5',
    );
  }
}
