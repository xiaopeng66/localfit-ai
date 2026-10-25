@Tags(['interaction-gate'])
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/app_morph_chip.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_filter_chips.dart';
import 'package:localfit_ai/app/design/widgets/lf_segment_control.dart';
import 'package:localfit_ai/app/design/widgets/lf_segmented_toggle.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_editor_dialog.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_create_page.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';

/// L1 · 状态层门禁（`docs/58` §2.2）：**点一下必须产生可观察的变化**。
///
/// 只点「有状态语义」的控件实例（选择/开关/筛选），不追求点遍所有按钮。
/// 这一层能抓到「点了但值没变」，**抓不到**「值变了界面不重建」（那是 L2）
/// 和「界面说了但读屏说不出」（L3）——三层必须分别测。
///
/// 已知红（B1 故意，见 `docs/58` §2.6）：`plan-days-*` 目前只有 1..5，且
/// 点击后界面不重建。它在 B2 随 `RV4-P1-02` 一起转绿。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );

  group('L1 · 胶囊/筛选/分段：点击后选中态迁移', () {
    testWidgets('LfPillButton：点第二枚后只有它 selected', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                for (var i = 0; i < 3; i++)
                  LfPillButton(
                    key: Key('l1-pill-$i'),
                    label: '选项$i',
                    selected: selected == i,
                    onPressed: () => setState(() => selected = i),
                  ),
              ],
            ),
          ),
        ),
      );
      expect(_pillSelected(tester, 0), isTrue);
      await tester.tap(find.byKey(const Key('l1-pill-2')));
      await tester.pumpAndSettle();
      expect(_pillSelected(tester, 2), isTrue);
      expect(_pillSelected(tester, 0), isFalse);
    });

    testWidgets('LfFilterChip：点击后选中迁移（同组只有一枚）', (tester) async {
      var selected = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => Row(
              children: [
                for (var i = 0; i < 3; i++)
                  LfFilterChip(
                    key: Key('l1-chip-$i'),
                    label: '分类$i',
                    selected: selected == i,
                    onPressed: () => setState(() => selected = i),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('l1-chip-1')));
      await tester.pumpAndSettle();
      expect(_chipSelected(tester, 1), isTrue);
      expect(_chipSelected(tester, 0), isFalse);
    });

    testWidgets('LfSegmentControl：点击后 selected 与正文一起换', (tester) async {
      const values = ['记录', '菜单'];
      var selected = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                LfSegmentControl<String>(
                  segments: const [
                    LfSegment(value: '记录', label: '记录'),
                    LfSegment(value: '菜单', label: '菜单'),
                  ],
                  selected: values[selected],
                  onChanged: (value) =>
                      setState(() => selected = values.indexOf(value)),
                  segmentKeys: {
                    '记录': const Key('l1-seg-0'),
                    '菜单': const Key('l1-seg-1'),
                  },
                ),
                Text(selected == 0 ? '正文A' : '正文B'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('l1-seg-1')));
      await tester.pumpAndSettle();
      expect(find.text('正文B'), findsOneWidget);
      expect(find.text('正文A'), findsNothing);
    });

    testWidgets('LfSegmentedToggle：点击后 selectedIndex 迁移', (tester) async {
      var index = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => LfSegmentedToggle(
              segments: const ['周', '月'],
              selectedIndex: index,
              onChanged: (next) => setState(() => index = next),
              segmentKeys: const [Key('l1-toggle-0'), Key('l1-toggle-1')],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('l1-toggle-1')));
      await tester.pumpAndSettle();
      expect(index, 1);
    });

    testWidgets('AppMorphChip：点击后 selected 取反', (tester) async {
      var selected = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => AppMorphChip(
              key: const Key('l1-morph'),
              label: '一食堂',
              selected: selected,
              onSelected: (next) => setState(() => selected = next),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('l1-morph')));
      await tester.pumpAndSettle();
      final chip = tester.widget<AppMorphChip>(
        find.byKey(const Key('l1-morph')),
      );
      expect(chip.selected, isTrue);
    });
  });

  group('L1 · 餐次胶囊：点击后落进保存草稿', () {
    late AppDatabase database;
    late FoodRepository foods;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      foods = FoodRepository(
        database: database,
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime.utc(2026, 10, 24, 2)),
      );
    });
    tearDown(() => database.close());

    testWidgets('点「晚餐」→ 保存返回的 draft.slot == dinner', (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      MealDraft? saved;
      final now = DateTime.utc(2026, 10, 24, 2);
      final editor = MealEditorDialog(
        foodRepository: foods,
        localDate: '2026-10-24',
        initialMeal: MealRecord(
          id: 'meal-1',
          localDate: '2026-10-24',
          slot: MealSlot.lunch,
          eatenAt: now,
          source: 'manual',
          createdAt: now,
          updatedAt: now,
          items: [
            MealItemRecord(
              id: 'item-1',
              foodId: 'food-1',
              foodName: '鸡胸肉',
              grams: 100,
              nutrition: const NutritionValues(
                kcal: 165,
                proteinGrams: 31,
                carbsGrams: 0,
                fatGrams: 3.6,
              ),
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
        onSubmit: (draft) async {
          saved = draft;
          return null;
        },
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  AppSheet.showCustom<void>(context, builder: (_) => editor),
              child: const Text('打开编辑'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开编辑'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('meal-slot')),
          matching: find.text('晚餐'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('meal-save')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.slot, MealSlot.dinner, reason: '点「晚餐」后保存的必须真是晚餐');
    });
  });

  group('L1 · 训练页天数（RV4-P1-02）', () {
    late AppDatabase database;
    late ExerciseRepository exercises;
    late _RecordingProvider provider;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      exercises = ExerciseRepository(
        database: database,
        idGenerator: _Ids(),
        clock: FixedAppClock(DateTime.utc(2026, 10, 24, 2)),
      );
      provider = _RecordingProvider();
      await exercises.create(
        const NewExercise(
          name: '深蹲',
          muscleGroup: MuscleGroup.legs,
          equipment: Equipment.barbell,
        ),
      );
    });
    tearDown(() => database.close());

    testWidgets('点 plan-days-5 → 该枚 selected，且 1..7 七枚都在', (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: WorkoutPlanCreatePage(
            exerciseRepository: exercises,
            workoutPlanRepository: WorkoutPlanRepository(
              database: database,
              idGenerator: _Ids(),
              clock: FixedAppClock(DateTime.utc(2026, 10, 24, 2)),
            ),
            workoutPlanProvider: provider,
            loadWorkoutPlanDisclosure: LoadWorkoutPlanDisclosure(
              configurationReader: _FixedConfiguration(),
            ),
            now: DateTime(2026, 10, 24, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var d = 1; d <= 7; d++) {
        expect(
          find.byKey(Key('plan-days-$d')),
          findsOneWidget,
          reason: 'AiWorkoutPlanRequest.maxDays = 7，界面必须给到 7 天',
        );
      }

      await tester.tap(find.byKey(const Key('plan-days-5')));
      await tester.pumpAndSettle();

      expect(
        _pillSelectedByKey(tester, const Key('plan-days-5')),
        isTrue,
        reason: '点「5天」后该枚必须选中（当前实现：ValueNotifier 无监听 → 永远停在 3）',
      );
      expect(_pillSelectedByKey(tester, const Key('plan-days-3')), isFalse);
    });
  });
}

/// `LfPillButton` 把传入的 key 挂在内层 `TextButton` 上（`_innerKey`），
/// 所以按 key 拿到的 widget 是 `TextButton`，必须往上找一层。
bool _pillSelected(WidgetTester tester, int index) =>
    _pillSelectedByKey(tester, Key('l1-pill-$index'));

bool _pillSelectedByKey(WidgetTester tester, Key key) => tester
    .widget<LfPillButton>(
      find.ancestor(of: find.byKey(key), matching: find.byType(LfPillButton)),
    )
    .selected;

bool _chipSelected(WidgetTester tester, int index) => tester
    .widget<LfFilterChip>(
      find.ancestor(
        of: find.byKey(Key('l1-chip-$index')),
        matching: find.byType(LfFilterChip),
      ),
    )
    .selected;

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String next() => 'id-${value++}';
}

final class _RecordingProvider implements WorkoutPlanProvider {
  @override
  Future<AiWorkoutPlanDraft> generate(
    AiWorkoutPlanRequest request, {
    WorkoutPlanCancellationToken? cancellationToken,
  }) async => AiWorkoutPlanDraft(
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

final class _FixedConfiguration implements AiProviderConfigurationReader {
  @override
  Future<AiProviderConfiguration?> loadConfiguration() async =>
      AiProviderConfiguration(
        baseUrl: 'https://api.example.com/v1',
        model: 'test-model',
        protocol: AiProviderProtocol.chatCompletions,
      );
}
