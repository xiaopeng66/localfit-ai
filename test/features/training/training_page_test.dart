import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/presentation/rest_countdown.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';

import '../../support/food_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 活动横幅的呼吸点是无限动画（animate-pulse），pumpAndSettle 永远等不完。
  // 全文件按「系统开启减弱动画」跑：_PulseDot 本就按此降级为实心点
  // （docs/21 §2.9 装饰动效退化），其余动效也退化为瞬时可 settle。
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );
  late AppDatabase database;
  late ExerciseRepository exercises;
  late WorkoutPlanRepository plans;
  late WorkoutSessionRepository sessions;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedFoodFixture(database);
    await const ExerciseSeedImporter().importIfNeeded(database);
    exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids('ex-user'),
      clock: FixedAppClock(DateTime.utc(2026, 9, 12, 10)),
    );
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: _Ids('plan'),
      clock: FixedAppClock(DateTime.utc(2026, 9, 12, 10)),
    );
    sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: _Ids('session'),
      clock: FixedAppClock(DateTime.utc(2026, 9, 12, 10)),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Widget page({DateTime? now}) => MaterialApp(
    home: TrainingPage(
      exerciseRepository: exercises,
      workoutPlanRepository: plans,
      workoutSessionRepository: sessions,
      now: now,
    ),
  );

  testWidgets('周容量图按真实星期定位「今天」并报真实分钟数（docs/21 §5.5／§6.2 裁决 4）', (tester) async {
    _useTallViewport(tester);
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
                targetWeightKg: 60,
              ),
            ],
          ),
        ],
      ),
    );
    // 会话必须真有时长才测得出「分钟」这条口径：时钟停在 10:00 开始、
    // 走到 10:45 结束 ⇒ 周六这一格是 45 分钟。旧实现把**组数**塞进名为
    // mondayMinutes 的变量喂给这张图（口径是错的），本测试就是它的哨兵。
    final clock = _SteppingClock(DateTime.utc(2026, 9, 12, 10));
    final stepping = WorkoutSessionRepository(
      database: database,
      idGenerator: _Ids('session-stepping'),
      clock: clock,
    );
    final sessionId = await stepping.start(
      localDate: '2026-09-12',
      planId: planId,
    );
    await stepping.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );
    clock.value = DateTime.utc(2026, 9, 12, 10, 45);
    await stepping.finish(sessionId);

    // 语义摘要是读屏路径（§5.8.3「图表必须有文字等价物」），语义树要先开
    // 才编得出来；句柄必须在测试体结束前显式释放（绑定期末会检查）。
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('training-capacity-chart')), findsOneWidget);
    // 「今天」柱由 now.weekday 推导（2026-09-12 是周六 → 第 6 格），不是
    // 设计稿里写死的周一；语义摘要（ChartSemantics 单节点）必须同时报出
    // 真实分钟数与今天——这是旧实现「把组数当分钟喂给图表」缺陷的哨兵。
    expect(find.bySemanticsLabel('本周容量图：周六 45 分钟；今天是周六。'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('shows weekly stats, completion, and personal records', (
    tester,
  ) async {
    _useTallViewport(tester);
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
                targetWeightKg: 60,
              ),
            ],
          ),
        ],
      ),
    );
    final sessionId = await sessions.start(
      localDate: '2026-09-12',
      planId: planId,
    );
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );
    await sessions.finish(sessionId);

    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    expect(find.textContaining('本周容量 480.0kg'), findsOneWidget);
    // hero 三段只渲染数值（「1」/「0min」/「—」），文案在 label 里。
    expect(_heroStatText(tester, 'training-hero-count'), '1');
    expect(find.byKey(const Key('training-week-stats')), findsOneWidget);

    await tester.tap(find.text('下肢日'));
    await tester.pumpAndSettle();
    expect(find.text('本周完成率 1/1'), findsOneWidget);

    // 详情弹层挂着全屏 barrier：不先关掉它，下面的 tap 会打在 barrier 上
    // 把弹层关掉、而不是点中周统计卡里的「个人纪录」。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('training-personal-records')));
    await tester.pumpAndSettle();
    expect(find.text('杠铃深蹲 60.0kg × 8 次'), findsOneWidget);
  });

  testWidgets('reports pain with safe options and can stop the session', (
    tester,
  ) async {
    _useTallViewport(tester);
    await sessions.start(localDate: '2026-09-12');
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cta-continue-session')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('training-pain-report')));
    await tester.pumpAndSettle();
    expect(find.text('停止训练'), findsOneWidget);
    expect(find.text('降低负荷'), findsOneWidget);
    expect(find.text('替换动作'), findsOneWidget);
    expect(find.textContaining('咨询专业人士'), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-pain-stop')));
    await tester.pumpAndSettle();

    expect(
      (await database.select(database.workoutSessions).get()).single.status,
      'finished',
    );
  });

  testWidgets('shows a training summary with progression hints on finish', (
    tester,
  ) async {
    _useTallViewport(tester);
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );
    final sessionId = await sessions.start(
      localDate: '2026-09-12',
      planId: planId,
    );
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cta-continue-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-session-finish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-session-finish-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('训练总结'), findsOneWidget);
    // 后台周统计现在会随结束写入即时刷新；只断言总结本身，不混入周统计文案。
    expect(find.text('容量 480.0kg · 1 组'), findsOneWidget);
    expect(find.textContaining('杠铃深蹲：'), findsOneWidget);
    expect(find.textContaining('仅供参考'), findsOneWidget);
  });

  // 2026-10-23 用户：「删『AI 生成训练计划』按钮，功能转移到 ➕」——
  // 页内那张 AI 流程弹层整条下线（四个用例随之退役；同一条链路的
  // 表单/披露/生成/保存断言在 `workout_plan_create_page_test.dart` 里保留）。
  testWidgets('closes the plan detail sheet when starting a session', (
    tester,
  ) async {
    _useTallViewport(tester);
    await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下肢日'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('training-session-start')), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-session-start')));
    await tester.pumpAndSettle();

    // 详情弹层必须随会话启动一起关闭；rootNavigator 的 popUntil 对
    // 分支 Navigator 上的弹层是 no-op，修复前详情会残留在页面栈里。
    expect(find.byKey(const Key('training-session-start')), findsNothing);
    expect(find.text('训练进行中'), findsOneWidget);
    expect(
      (await database.select(database.workoutSessions).get()).single.planId,
      isNotNull,
    );
  });

  testWidgets('已有进行中会话时点「开始训练」：先关详情弹层，失败提示才看得见', (tester) async {
    // 同类缺陷回归（2026-10-02）：snackbar 画在页面 Scaffold 里，详情弹层
    // 还开着时会被盖住——用户只会看到「点了没反应」。修复＝先 pop 弹层再提示。
    // 断言锁「弹层已关 + 提示可见」两者同时成立：只查文案抓不住被盖住的情况。
    _useTallViewport(tester);
    await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );
    // 先制造一个进行中的会话（仓库对并发 active 会话是硬拒绝的）。
    await sessions.start(localDate: '2026-09-12');

    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下肢日'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-session-start')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('training-session-start')), findsNothing);
    expect(find.text('已有一个进行中的训练会话，请先结束或继续它。'), findsOneWidget);
  });

  testWidgets('计划详情显示来源标签：AI 排的还是自己挑的（docs/30 §2 D7 第⑥帧）', (tester) async {
    _useTallViewport(tester);
    // 手动建的：`create` 默认 source = 'manual'。
    await plans.create(
      const WorkoutPlanDraft(
        name: '手动计划',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await tester.tap(find.text('手动计划'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LfBadge>(find.byKey(const Key('training-plan-source')))
          .text,
      '手动创建',
      reason: '`source` 列本就落库，这一步只是把它显示出来',
    );
    // 关掉弹层再做另一半（同一用例内避免重开 app）。
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  });

  testWidgets('计划详情：AI 来源写「AI 生成」，未知来源原样透出（不编一个词）', (tester) async {
    _useTallViewport(tester);
    final aiPlanId = await plans.create(
      const WorkoutPlanDraft(
        name: 'AI 计划',
        days: [
          WorkoutPlanDayDraft(
            weekday: 3,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
      source: 'ai',
    );
    // 将来多出来的来源：直接写库，看页面怎么显示它。
    await database
        .into(database.workoutPlans)
        .insert(
          WorkoutPlansCompanion.insert(
            id: 'plan-imported',
            name: '导入计划',
            source: 'imported',
            createdAt: DateTime.utc(2026, 9, 12, 10),
            updatedAt: DateTime.utc(2026, 9, 12, 10),
          ),
        );
    // 计划卡是**按训练日**铺开的（一个 `WorkoutDays` 行 = 一张卡）：没有训练日
    // 的计划在页面上不可见，也就点不开详情。这条 day 只是为了让它有一张卡。
    await database
        .into(database.workoutDays)
        .insert(
          WorkoutDaysCompanion.insert(
            id: 'plan-imported-day',
            planId: 'plan-imported',
            weekday: 4,
            sortOrder: 4,
          ),
        );
    await database
        .into(database.plannedExercises)
        .insert(
          PlannedExercisesCompanion.insert(
            id: 'plan-imported-entry',
            dayId: 'plan-imported-day',
            exerciseId: 'ex-plank',
            sortOrder: 0,
            targetSets: 3,
            targetReps: 60,
            createdAt: DateTime.utc(2026, 9, 12, 10),
            updatedAt: DateTime.utc(2026, 9, 12, 10),
          ),
        );
    // 计划卡按创建时间倒序：先建的 `AI 计划` 要后点，所以先点 `导入计划`。
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();

    expect(aiPlanId, isNotEmpty);
    await tester.tap(find.text('导入计划'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<LfBadge>(find.byKey(const Key('training-plan-source')))
          .text,
      'imported',
      reason: '不认识的 source 原样透出：把它显示成上次匹配到的中文词就是编造',
    );
  });

  testWidgets('deletes a plan after confirmation', (tester) async {
    _useTallViewport(tester);
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '待删除计划',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('待删除计划'), findsOneWidget);

    // 行内删除钮不在设计稿里（docs/22 裁决 ②）：删除入口移进计划详情。
    await tester.tap(find.text('待删除计划'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('training-plan-delete-$planId')));
    await tester.pumpAndSettle();
    // 破坏性确认 = §3.8 B7：error 字色的**文字**按钮（`我的.html:524-532`
    // 的「清除所有数据」就是 error 字色的一行，设计稿里没有实心 error 按钮）。
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('training-plan-delete-confirm')),
          )
          .style
          ?.foregroundColor
          ?.resolve(<WidgetState>{}),
      LfSemanticColors.light.error,
    );
    await tester.tap(find.byKey(const Key('training-plan-delete-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('待删除计划'), findsNothing);
    expect(find.text('还没有本地训练计划。'), findsOneWidget);
    expect(await database.select(database.workoutPlans).get(), isEmpty);
  });

  testWidgets('starts a session from a plan day and logs a set', (
    tester,
  ) async {
    _useTallViewport(tester);
    await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
                targetWeightKg: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下肢日'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-session-start')));
    await tester.pumpAndSettle();
    expect(find.text('训练进行中'), findsOneWidget);
    expect(find.textContaining('今日计划'), findsOneWidget);

    // 弹层底部主行动 = §3.8 B2（full 圆角实心）：仍是 FilledButton 本体，
    // 换回文字型（B6）会被这一行抓住。
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('training-set-log'))),
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('training-set-log')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('training-set-weight')), '60');
    await tester.enterText(find.byKey(const Key('training-set-reps')), '8');
    await tester.tap(find.byKey(const Key('training-set-save')));
    await tester.pump();
    await tester.pump();

    expect(find.text('杠铃深蹲 60.0kg × 8 次'), findsOneWidget);
    expect(find.byKey(const Key('training-rest-countdown')), findsOneWidget);
    // docs/21 §3：休息倒计时升级为环形横幅，且是记录弹层内的常驻组件
    // （非全屏遮断）——环 painter 在树上，已记录组次仍同屏可见。
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is RestRingPainter,
      ),
      findsOneWidget,
    );
    expect(await database.select(database.workoutSets).get(), hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    addTearDown(() async {});
  });

  testWidgets('组间休息：按本组填写的秒数重置倒计时（docs/21 §5.5）', (tester) async {
    _useTallViewport(tester);
    await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
                targetWeightKg: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下肢日'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-session-start')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('training-set-log')));
    await tester.pumpAndSettle();
    // 休息输入存在且默认值写在提示里。
    expect(find.byKey(const Key('training-set-rest')), findsOneWidget);
    expect(find.textContaining('默认 90'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('training-set-weight')), '60');
    await tester.enterText(find.byKey(const Key('training-set-reps')), '8');
    await tester.enterText(find.byKey(const Key('training-set-rest')), '180');
    await tester.tap(find.byKey(const Key('training-set-save')));
    await tester.pump();
    await tester.pump();

    // 倒计时总时长跟着这一组的填写值走，而不是恒定 90 秒。
    expect(
      tester.widget<RestCountdown>(find.byType(RestCountdown)).total,
      const Duration(seconds: 180),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    addTearDown(() async {});
  });

  testWidgets('组间休息：越界或非数字给提示且不落库', (tester) async {
    _useTallViewport(tester);
    await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
                targetWeightKg: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下肢日'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-session-start')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('training-set-log')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('training-set-weight')), '60');
    await tester.enterText(find.byKey(const Key('training-set-reps')), '8');
    await tester.enterText(find.byKey(const Key('training-set-rest')), '5');
    await tester.tap(find.byKey(const Key('training-set-save')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('10–900 秒'), findsOneWidget);
    // 校验失败不得写库，也不得开始倒计时。
    expect(await database.select(database.workoutSets).get(), isEmpty);
    expect(find.byKey(const Key('training-rest-countdown')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    addTearDown(() async {});
  });

  testWidgets('finishes the active session with a confirmation', (
    tester,
  ) async {
    _useTallViewport(tester);
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );
    final sessionId = await sessions.start(
      localDate: '2026-09-12',
      planId: planId,
    );
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cta-continue-session')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cta-continue-session')));
    await tester.pumpAndSettle();
    expect(find.text('杠铃深蹲 60.0kg × 8 次'), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-session-finish')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-session-finish-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('训练总结'), findsOneWidget);
    await tester.tap(find.byKey(const Key('training-summary-done')));
    await tester.pumpAndSettle();

    expect(
      (await database.select(database.workoutSessions).get()).single.status,
      'finished',
    );
    expect(find.byKey(const Key('cta-continue-session')), findsNothing);
  });

  testWidgets('页面在会话弹层仍打开时被销毁，弹层关闭不得 setState 到已销毁的 State', (tester) async {
    _useTallViewport(tester);
    // docs/11 §3-E：`_openActiveSession` 里 `await showModalBottomSheet(...)`
    // 之后直接 `setState`。弹层挂在根导航器上（AppSheet 的 useRootNavigator
    // 同款行为），页面路由先被移除、弹层仍活着，之后弹层关闭时 future 才完成
    // ——此时页面 State 已销毁，无守卫的 setState 会抛「called after dispose」。
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '腿日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );
    await sessions.start(localDate: '2026-09-12', planId: planId);

    final showPage = ValueNotifier<bool>(true);
    addTearDown(showPage.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: showPage,
          builder: (context, show, _) => Navigator(
            pages: [
              const MaterialPage(child: SizedBox()),
              if (show)
                MaterialPage(
                  child: TrainingPage(
                    exerciseRepository: exercises,
                    workoutPlanRepository: plans,
                    workoutSessionRepository: sessions,
                    now: DateTime(2026, 9, 12),
                  ),
                ),
            ],
            onDidRemovePage: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cta-continue-session')));
    await tester.pumpAndSettle();

    // 页面路由被移除（State 销毁），根导航器上的弹层留下。
    showPage.value = false;
    await tester.pumpAndSettle();

    // 关闭仍然活着的弹层：future 此刻才完成。
    final navigator = tester.state<NavigatorState>(find.byType(Navigator).last);
    navigator.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('活动会话的存库日期畸形时，恢复训练弹层不得抛 FormatException', (tester) async {
    _useTallViewport(tester);
    // docs/11 §3-F：`workout_sessions.localDate` 是未加约束的 TextColumn，
    // 恢复备份只校验 JSON 形状、不校验字段值，畸形日期可以落库。恢复会话时
    // `_weekdayOf` 裸 `int.parse` 会在 build 里抛 FormatException（红屏），
    // 而且每次进页都复现——用户没有任何自助出路。
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '腿日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );
    await sessions.start(localDate: '2026-09-12', planId: planId);
    // 模拟畸形日期落库（正常写入路径经 formatLocalDate 只会产出 YYYY-MM-DD）。
    await database.customStatement(
      "UPDATE workout_sessions SET local_date = 'not-a-date'",
    );

    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cta-continue-session')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  // ───────────── §5.5 规格测试（新增断言，全部配隔离变异红证） ─────────────

  testWidgets('分段默认是「计划」且真的能切到「历史」（docs/21 §5.5）', (tester) async {
    _useTallViewport(tester);
    await plans.create(
      const WorkoutPlanDraft(
        name: '分段计划',
        days: [
          WorkoutPlanDayDraft(
            weekday: 3,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
    );
    final sessionId = await sessions.start(localDate: '2026-09-12');
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(exerciseId: 'ex-plank', weightKg: 0, reps: 10),
    );
    await sessions.finish(sessionId);

    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();

    // 默认分段是计划：计划卡在树上，历史卡不在。
    expect(find.byKey(const Key('training-segment-plan')), findsOneWidget);
    expect(find.text('分段计划'), findsOneWidget);
    expect(find.byKey(Key('training-history-$sessionId')), findsNothing);

    await tester.tap(find.byKey(const Key('training-segment-history')));
    await tester.pumpAndSettle();
    expect(find.text('分段计划'), findsNothing);
    expect(find.byKey(Key('training-history-$sessionId')), findsOneWidget);
    // 这条会话没挂计划：历史卡按真实数据叫「自由训练」，不编计划名。
    expect(find.text('自由训练'), findsOneWidget);
  });

  testWidgets('Round7 逐页对账：分段与动作库行按 A 的文案（app.js:216）', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();

    // A `app.js:216` 的 tabs 是四字标签：我的计划 / 训练历史。
    expect(find.text('我的计划'), findsOneWidget);
    expect(find.text('训练历史'), findsOneWidget);
    // A 的 list-link「动作库」带副题（先了解动作，再开始训练）。
    expect(find.text('先了解动作，再开始训练'), findsOneWidget);
  });

  testWidgets('Round7 逐页对账批次 3：计划卡补「一~日」日签行与今日行（A app.js:216）', (tester) async {
    _useTallViewport(tester);
    // 2026-09-12 是周六；计划安排在周二/周四 ⇒ 今天不是训练日。
    await plans.create(
      const WorkoutPlanDraft(
        name: '周中两练',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
          WorkoutPlanDayDraft(
            weekday: 4,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();

    // 七枚日签（一~日）都在卡上（A `.plan-days` 的 7 枚）。
    expect(find.byKey(const Key('training-plan-weekdays-1')), findsOneWidget);
    for (var n = 1; n <= 7; n++) {
      expect(find.byKey(Key('training-plan-weekday-1-$n')), findsOneWidget);
    }

    Color chipColor(int n) {
      final box = tester.widget<Container>(
        find.byKey(Key('training-plan-weekday-1-$n')),
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    final c = tester
        .element(find.byKey(const Key('training-plan-weekdays-1')))
        .lf;
    final brandSoft = LfColors.mint(Brightness.light).tone(50);
    // 计划日（二 / 四）= 品牌浅底；休息日（一）= 轨道底；
    // 今天（六）即使不是计划日也走**实心**档（A `.day-chip.today` 后置覆盖
    // `.on`——自纠：本条一开始写成「六 = 轨道底」，被实现按 A 的优先级纠正）。
    expect(chipColor(2), brandSoft);
    expect(chipColor(4), brandSoft);
    expect(chipColor(1), c.muted);
    expect(chipColor(6), c.primary);

    // 今日行说真话：周六不在计划里。
    expect(
      tester
          .widget<Text>(find.byKey(const Key('training-plan-today-note-1')))
          .data,
      '今天休息，恢复也很重要',
    );
  });

  testWidgets('Round7 逐页对账批次 3：今天落在计划日时写「今天是训练日」且日签高亮', (tester) async {
    _useTallViewport(tester);
    // 2026-09-12 是周六 ⇒ 计划安排在周六时今天就是训练日。
    await plans.create(
      const WorkoutPlanDraft(
        name: '周末练',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();

    final c = tester
        .element(find.byKey(const Key('training-plan-weekdays-1')))
        .lf;
    final box = tester.widget<Container>(
      find.byKey(const Key('training-plan-weekday-1-6')),
    );
    // 今天 = 品牌实心底（A `.day-chip.today` 的填充档）。
    expect((box.decoration! as BoxDecoration).color, c.primary);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('training-plan-today-note-1')))
          .data,
      '今天是训练日',
    );
  });

  testWidgets('Round7 逐页对账批次 4：历史行可点出「训练回顾」只读弹层（A app.js:559）', (tester) async {
    _useTallViewport(tester);
    final sessionId = await sessions.start(localDate: '2026-09-12');
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(exerciseId: 'ex-plank', weightKg: 20, reps: 10),
    );
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(exerciseId: 'ex-plank', weightKg: 20, reps: 8),
    );
    await sessions.finish(sessionId);
    final row = (await sessions.listAllFinished()).single;

    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-segment-history')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('training-history-$sessionId')));
    await tester.pumpAndSettle();

    // A `app.js:559` 的回顾弹层：组数大字 + 名称 + 日期/时长/总容量/估算消耗。
    expect(find.byKey(const Key('training-review-sheet')), findsOneWidget);
    expect(find.text('训练回顾'), findsOneWidget);
    expect(find.text('已完成组数'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('training-review-sets'))).data,
      '${row.completedSetCount}',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('training-review-date'))).data,
      row.localDate,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('training-review-volume'))).data,
      '${row.totalVolumeKg.toStringAsFixed(1)} kg',
    );
    // 消耗：本库不记录训练消耗估算 ⇒ 如实显示「—」，不编数字
    // （docs/21 §5.5「`totalKcal` 恒传 null ⇒ 渲染「—」」的同一口径）。
    expect(
      tester.widget<Text>(find.byKey(const Key('training-review-kcal'))).data,
      '—',
    );
  });

  testWidgets('Round7 裁决 R1：今日计划卡卡面补「开始训练」CTA 且真能开始（A app.js:216）', (
    tester,
  ) async {
    _useTallViewport(tester);
    // 2026-09-12 是周六 ⇒ 计划安排在周六时，这张卡就是「今天」。
    await plans.create(
      const WorkoutPlanDraft(
        name: '周末练',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();

    // 今日卡：CTA 在（A 的 `.plan-today` 右端按钮）；非今日卡：不在。
    expect(find.byKey(const Key('training-plan-start-1')), findsOneWidget);
    expect(find.text('开始训练'), findsOneWidget);

    await tester.tap(find.byKey(const Key('training-plan-start-1')));
    await tester.pumpAndSettle();

    // 同一条写入路径：真的开了一次会话（详情里的按钮走的就是它）。
    final active = await sessions.getActive();
    expect(active, isNotNull);
    expect(active!.localDate, '2026-09-12');
    // 开完会话，卡面 CTA 变成「继续训练」（A：state.active 时写继续训练）。
    expect(find.text('继续训练'), findsWidgets);
  });

  testWidgets('Round7 裁决 R2：训练统计弹层补容量口径说明句与肌群 kg 值', (tester) async {
    _useTallViewport(tester);
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '腿部日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
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
      localDate: '2026-09-12',
      planId: planId,
    );
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );
    await sessions.finish(sessionId);

    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-stats')));
    await tester.pumpAndSettle();

    // A `app.js:267` 的口径说明句（此前只搬了标题，句子漏了）。
    expect(find.text('容量 = 每组重量 × 次数的合计'), findsOneWidget);
    // 肌群分布行带 kg 值（A 的图例是「名称 / 百分比 / kg」三件）。
    final legKg = tester.widget<Text>(
      find.byKey(const Key('training-muscle-kg-legs')),
    );
    expect(legKg.data, '480 kg');
  });

  testWidgets('肌群 chips 过滤计划卡：无匹配动作的卡整张收起（docs/21 §5.5）', (tester) async {
    _useTallViewport(tester);
    // 2026-09-12 是周六，两张卡都不在「今天」，避开今日竖条分支。
    await plans.create(
      const WorkoutPlanDraft(
        name: '腿部日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );
    await plans.create(
      const WorkoutPlanDraft(
        name: '核心日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 4,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    expect(find.text('腿部日'), findsOneWidget);
    expect(find.text('核心日'), findsOneWidget);

    // 过滤「腿」：核心卡整张收起，而不是留一张空卡。
    await tester.tap(find.byKey(const Key('training-muscle-legs')));
    await tester.pumpAndSettle();
    expect(find.text('腿部日'), findsOneWidget);
    expect(find.text('核心日'), findsNothing);

    // 「全部」恢复两张卡。
    await tester.tap(find.byKey(const Key('training-muscle-all')));
    await tester.pumpAndSettle();
    expect(find.text('核心日'), findsOneWidget);
  });

  testWidgets('无数据时 hero 走诚实空态（§6.1）：kcal「—」、计数 0、不渲染周数', (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();

    // kcal 无数据源（WorkoutSets 没有热量列）→ 渲染「—」而不是编 0。
    expect(_heroStatText(tester, 'training-hero-kcal'), '—');
    expect(_heroStatText(tester, 'training-hero-count'), '0');
    // 「第N周」是演示值：无训练历史时整行不渲染。
    expect(find.byKey(const Key('training-hero-week')), findsNothing);
    expect(find.text('还没有本地训练计划。'), findsOneWidget);
  });

  testWidgets('休息日图例按计划训练日推导，全周排满时隐藏（§6.2 裁决 4）', (tester) async {
    _useTallViewport(tester);
    await plans.create(
      const WorkoutPlanDraft(
        name: '腿部日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    // 只排了周六 ⇒ 其余 6 天都是休息日，图例如实列出。
    expect(find.byKey(const Key('training-rest-legend')), findsOneWidget);
    expect(find.textContaining('休息日 · 一 / 二 / 三 / 四 / 五 / 日'), findsOneWidget);

    // 全周排满 ⇒ 没有休息日，图例整行不渲染。
    await plans.create(
      WorkoutPlanDraft(
        name: '全周计划',
        days: [
          for (var weekday = 1; weekday <= 7; weekday++)
            WorkoutPlanDayDraft(
              weekday: weekday,
              entries: [
                PlannedExerciseDraft(
                  exerciseId: 'ex-plank',
                  targetSets: 2,
                  targetReps: 30,
                ),
              ],
            ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('training-rest-legend')), findsNothing);
  });

  testWidgets('进行中横幅：进度条只在有计划组数分母时渲染（§7.1 派生）', (tester) async {
    _useTallViewport(tester);
    // 无计划会话：分母缺失 ⇒ 进度条整条不渲染（设计稿的 65% 是演示值，不能编）。
    await sessions.start(localDate: '2026-09-12');
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('training-active-banner')), findsOneWidget);
    expect(find.byKey(const Key('training-active-progress')), findsNothing);

    // 结束自由会话，再起一条挂在计划上的：分母就位，进度条出现。
    final freeId =
        (await database.select(database.workoutSessions).get()).single.id;
    await sessions.finish(freeId);
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '腿部日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
              ),
            ],
          ),
        ],
      ),
    );
    await sessions.start(localDate: '2026-09-12', planId: planId);
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('training-active-banner')), findsOneWidget);
    expect(find.byKey(const Key('training-active-progress')), findsOneWidget);
  });

  // ───────────── 几何探针（320dp / 1.3× / 2.0×，docs/22 §5.5 收口项） ─────────────

  testWidgets('320dp 窄屏：训练页整页不溢出（几何探针）', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await plans.create(
      const WorkoutPlanDraft(
        name: '超长计划名称下肢二头肌三头肌综合体能训练安排示范卡',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
                targetWeightKg: 60,
              ),
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // ── T5（docs/32 §4 T5 / §3 D15 方案 B / 需求 79）────────────────────────
  // 训练页两处内嵌 DraggableScrollableSheet 的弹层，必须满足方案 B 三条：
  //   ① 外层 `enableDrag: false`（整层不再截胡手势 ⇒ 不再与内层 extent 打架）；
  //   ② 内层 `snap: true` + `snapSizes`（松手停在停靠点，高度不自由漂移）；
  //   ③ 内层 `shouldCloseOnMinExtent: false`（内容缩到最小不误关整个弹层）。
  // 这里走**真实入口**打开弹层，断言的是生产接线本身（改接线即红）。
  testWidgets('T5 方案 B：计划详情弹层外层只认把手、内层 snap 且缩到底不关窗', (tester) async {
    _useTallViewport(tester);
    await plans.create(
      const WorkoutPlanDraft(
        name: '方案B计划',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.text('方案B计划'));
    await tester.pumpAndSettle();

    // ① 外层不整层可拖。
    final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(
      bottomSheet.enableDrag,
      isFalse,
      reason: '外层必须只认把手（整层拖拽按运行时高度换算，与内层 extent 打架）',
    );

    // ②③ 内层三件套（计划详情档位 0.6 / 0.9）。
    final inner = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(inner.snap, isTrue, reason: '内层要 snap');
    expect(inner.snapSizes, [0.6, 0.9], reason: '计划详情停靠点 0.6 / 0.9');
    expect(
      inner.shouldCloseOnMinExtent,
      isFalse,
      reason: '缩到最小不得关掉整个弹层（Flutter 默认 true 正是缺陷）',
    );
    expect(inner.expand, isFalse, reason: 'expand:false 保留（否则撑满与 modal 打架）');
  });

  testWidgets('T5 方案 B：训练进行中弹层同样满足三条（0.75 / 0.95）', (tester) async {
    _useTallViewport(tester);
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '进行中计划',
        days: [
          WorkoutPlanDayDraft(
            weekday: 2,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-plank',
                targetSets: 3,
                targetReps: 60,
              ),
            ],
          ),
        ],
      ),
    );
    await sessions.start(localDate: '2026-09-12', planId: planId);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    // 进行中横幅的「查看详情」入口。
    await tester.tap(find.text('查看详情'));
    await tester.pumpAndSettle();

    final bottomSheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    expect(bottomSheet.enableDrag, isFalse);
    final inner = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    expect(inner.snap, isTrue);
    expect(
      inner.snapSizes,
      containsAll(<double>[0.75, 0.95]),
      reason: '训练进行中停靠点至少含 0.75 / 0.95（动态内容重算后仍在）',
    );
    expect(inner.shouldCloseOnMinExtent, isFalse);
  });

  testWidgets('1.3× 与 2.0× 字号：hero 与计划卡不溢出（几何探针）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await plans.create(
      const WorkoutPlanDraft(
        name: '腿部日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
                targetWeightKg: 60,
              ),
            ],
          ),
        ],
      ),
    );
    for (final scale in const <double>[1.3, 2.0]) {
      // copyWith 保住全局注入的 disableAnimations（呼吸点不起搏），只覆盖
      // 字号档。
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: TrainingPage(
            exerciseRepository: exercises,
            workoutPlanRepository: plans,
            workoutSessionRepository: sessions,
            now: DateTime(2026, 9, 12),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$scale× 字号下溢出');
    }
  });

  // ---- docs/21 §5.5 Key 表覆盖（阶段 I-4：Key 是设计契约）----
  testWidgets('docs/21 §5.5 Key 覆盖：hero 四段 / 计划卡 / 会话详情入口', (tester) async {
    _useTallViewport(tester);
    final planId = await plans.create(
      const WorkoutPlanDraft(
        name: '下肢日',
        days: [
          WorkoutPlanDayDraft(
            weekday: 6,
            entries: [
              PlannedExerciseDraft(
                exerciseId: 'ex-barbell-squat',
                targetSets: 4,
                targetReps: 8,
                targetWeightKg: 60,
              ),
            ],
          ),
        ],
      ),
    );
    // 先完成一条会话（hero 的「第 N 周」只在有训练历史时渲染），再起一条
    // 进行中的（活动横幅 + 「查看详情」只在进行中渲染）。
    final finished = await sessions.start(
      localDate: '2026-09-12',
      planId: planId,
    );
    await sessions.logSet(
      finished,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );
    await sessions.finish(finished);
    final sessionId = await sessions.start(
      localDate: '2026-09-12',
      planId: planId,
    );
    await sessions.logSet(
      sessionId,
      const WorkoutSetDraft(
        exerciseId: 'ex-barbell-squat',
        weightKg: 60,
        reps: 8,
      ),
    );

    await tester.pumpWidget(page(now: DateTime(2026, 9, 12)));
    await tester.pumpAndSettle();

    // 页面主滚动体（不能用 `find.byType(Scrollable).first`：训练页还有一条
    // 横向肌群 chips 行，抓到横向滚动体时纵向拖动无效，永远滚不到底下的卡）。
    final vertical = find
        .byWidgetPredicate(
          (w) =>
              w is Scrollable &&
              axisDirectionToAxis(w.axisDirection) == Axis.vertical,
        )
        .first;
    final missing = <String>[];
    for (final key in [
      'training-hero',
      'training-hero-week',
      'training-hero-count',
      'training-hero-duration',
      'training-hero-kcal',
      'training-active-banner',
      // 进行中才有「查看详情」（空闲态没有这条入口）。
      'training-session-detail',
      'training-capacity-chart',
      'training-rest-legend',
      // 序号 1 起（`TrainingPlanCard(index: index + 1)`）。
      'training-plan-card-1',
      'training-week-stats',
      'cta-new-plan',
    ]) {
      if (!await _reveal(tester, vertical, key)) missing.add(key);
    }
    expect(missing, isEmpty, reason: '未在训练页找到：${missing.join('、')}');
  });
}

final class _Ids implements IdGenerator {
  _Ids(this._prefix);

  final String _prefix;
  int _value = 0;

  @override
  String next() => '$_prefix-${_value++}';
}

/// 新设计的训练页首屏比旧版高（暗色 hero ≈ 300dp + 分段 + chips + 周统计 +
/// 计划卡 + 二级入口）。默认 800×600 视口下后半屏根本没被构建，点不到也断言
/// 不到，所以统一换成 900×1700：一屏内全部可断言，面板/详情层也放得下。
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// hero 单段统计的数值文本（Key 挂在 Column 上，第一个 Text 是数值）。
String _heroStatText(WidgetTester tester, String key) {
  final finder = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(Text),
  );
  return tester.widgetList<Text>(finder).first.data!;
}

/// 逐步向下滚，直到 [key] 被真正构建出来（懒加载 ListView 不构建视口外的项）。
/// 返回是否找到；不抛异常，便于一次跑出「哪些 Key 根本没渲染」的清单。
Future<bool> _reveal(WidgetTester tester, Finder scrollable, String key) async {
  for (var i = 0; i < 12; i++) {
    if (find.byKey(Key(key)).evaluate().isNotEmpty) return true;
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pump();
  }
  return find.byKey(Key(key)).evaluate().isNotEmpty;
}

/// 可推进的时钟。固定时钟只能造出 `startedAt == finishedAt` 的 0 分钟会话，
/// 而容量图/总时长都按「结束−开始」算，没有可推进时钟就测不到这条口径。
final class _SteppingClock implements AppClock {
  _SteppingClock(this.value);

  DateTime value;

  @override
  DateTime nowUtc() => value.toUtc();
}
