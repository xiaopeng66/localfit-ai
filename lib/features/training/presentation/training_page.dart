import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/app_haptics.dart';
import 'package:localfit_ai/app/design/widgets/app_celebration.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/placeholder_feature_page.dart';
import 'package:localfit_ai/core/time/daily_rollover.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart'
    show formatLocalDate;
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/application/training_stats.dart';
import 'package:localfit_ai/features/training/application/load_workout_plan_disclosure.dart';
import 'package:localfit_ai/features/training/application/progression_advisor.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_empty_state.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/training/presentation/rest_countdown.dart';
import 'package:localfit_ai/features/training/presentation/exercise_library_page.dart';
import 'package:localfit_ai/features/dashboard/presentation/sections/dashboard_training_targets.dart';
import 'package:localfit_ai/features/training/presentation/sections/planned_entry_sheet.dart';
import 'package:localfit_ai/features/training/presentation/sections/training_plan_fab.dart';
import 'package:localfit_ai/features/training/presentation/sections/training_hero.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/utils/number_format.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';

final class TrainingPage extends StatefulWidget {
  const TrainingPage({
    super.key,
    this.exerciseRepository,
    this.workoutPlanRepository,
    this.workoutSessionRepository,
    this.workoutPlanProvider,
    this.loadWorkoutPlanDisclosure,
    this.onOpenWorkoutPlanCreate,
    this.onOpenWorkoutPlanManual,
    this.now,
  });

  final ExerciseRepository? exerciseRepository;
  final WorkoutPlanRepository? workoutPlanRepository;
  final WorkoutSessionRepository? workoutSessionRepository;
  final WorkoutPlanProvider? workoutPlanProvider;
  final LoadWorkoutPlanDisclosure? loadWorkoutPlanDisclosure;

  /// `cta-new-plan` FAB 的模式弹层里「AI 生成」那一行的目标（docs/21 §5.5：
  /// `/workout-plan-create`）。为 null＝依赖不齐，此时该行**禁用但可见**并
  /// 说明「未配置 AI（我的 → AI 模型）」；导航本体在 `app_router`（页面不
  /// 持有路由）。
  final VoidCallback? onOpenWorkoutPlanCreate;

  /// 模式弹层里「手动创建」那一行的目标（`/workout-plan-manual`，
  /// docs/30 §2 D7）。只需 `exerciseRepository` + `workoutPlanRepository`
  /// ⇒ AI 没配置也可用。为 null 时（连这两个都没有）FAB 不给模式弹层。
  final VoidCallback? onOpenWorkoutPlanManual;

  final DateTime? now;

  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

// 页面常驻 IndexedStack；跨零点后「本周容量/完成率」窗口要前移一天。
final class _TrainingPageState extends State<TrainingPage> with DailyRollover {
  /// 分段（docs/21 §5.5 `SegmentedControl`：计划 / 历史）。计划是设计稿的
  /// 默认态——历史没被画到，但分段画了，所以它必须真的能切（裁决 ②）。
  _TrainingSegment _segment = _TrainingSegment.plan;

  /// 肌群筛选（docs/21 §5.5「支持分类筛选」）。null＝全部。
  ///
  /// 过滤的是**计划卡里的动作行**：§5.5 交互表写「肌肉 chips → 过滤动作」，
  /// 所以一张卡里没有匹配动作时整张卡不渲染（见 [_planSegment]）。
  MuscleGroup? _muscleFilter;

  // AI 计划流程入口先做一次异步查询再弹层，防止连点叠出两个相同弹层。
  Future<_TrainingSnapshot>? _snapshot;
  StreamSubscription<void>? _trainingChanges;

  @override
  void initState() {
    super.initState();
    _listenForTrainingChanges();
    _loadNextSnapshot();
  }

  @override
  void didUpdateWidget(covariant TrainingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final repositoriesChanged =
        oldWidget.exerciseRepository != widget.exerciseRepository ||
        oldWidget.workoutPlanRepository != widget.workoutPlanRepository ||
        oldWidget.workoutSessionRepository != widget.workoutSessionRepository;
    if (repositoriesChanged) _listenForTrainingChanges();
    if (repositoriesChanged || oldWidget.now != widget.now) {
      _loadNextSnapshot();
    }
  }

  void _listenForTrainingChanges() {
    unawaited(_trainingChanges?.cancel());
    _trainingChanges = widget.workoutPlanRepository
        ?.watchTrainingChanges()
        .listen((_) {
          if (mounted) setState(_loadNextSnapshot);
        });
  }

  void _loadNextSnapshot() {
    _snapshot =
        widget.exerciseRepository == null ||
            widget.workoutPlanRepository == null
        ? null
        : _loadSnapshot(widget.now ?? DateTime.now());
  }

  @override
  void onNewDay(DateTime previousDay) {
    if (widget.now == null) setState(_loadNextSnapshot);
  }

  @override
  void dispose() {
    unawaited(_trainingChanges?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final exerciseRepository = widget.exerciseRepository;
    final planRepository = widget.workoutPlanRepository;
    if (exerciseRepository == null || planRepository == null) {
      return const PlaceholderFeaturePage(
        title: '训练',
        icon: Icons.fitness_center_outlined,
        message: '训练计划、逐组记录和进步趋势将在这里管理。',
      );
    }
    final sessionRepository = widget.workoutSessionRepository;
    final today = widget.now ?? DateTime.now();
    return Scaffold(
      // 设计稿这一页没有 AppBar：暗色 hero 自身就是顶栏（docs/21 §5.5
      // 结构树的第一个节点），标题「训练」画在 hero 里。
      body: Stack(
        children: [
          FutureBuilder<_TrainingSnapshot>(
            // 写入与跨日才换 Future，普通重建不查库；FutureBuilder 的身份
            // 检查会丢弃旧 Future 的晚到结果，不把过期快照重新显示出来。
            future: _snapshot,
            builder: (context, snapshot) {
              // RV-P1-12：失败必须给错误态（原来只看 data==null ⇒ 永久 spinner）。
              if (snapshot.hasError) {
                return Padding(
                  padding: EdgeInsets.only(
                    top: LfDimens.pagePadding + LfInsets.top(context),
                    bottom: LfInsets.navReserve(context),
                  ),
                  child: Column(
                    children: [
                      AppErrorText('训练数据加载失败，请重试。'),
                      LfTextButton(
                        key: const Key('training-retry'),
                        label: '重试',
                        onPressed: () => setState(_loadNextSnapshot),
                      ),
                    ],
                  ),
                );
              }
              final data = snapshot.data;
              if (data == null) {
                // 载入中不预渲染一份「0 次训练」的 hero——那等于把未知当成
                // 事实（§6.1）。
                return const SizedBox(
                  height: 240,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return ListView(
                // 底栏是 shell 的 extendBody 覆盖层，页面自己留净空间
                // （§5.8.4）。必须走 padding：末尾塞 SizedBox 会让最后一次
                // 滚动差一截，最后一张卡压在底栏下。
                //
                // **顶部也走 padding**（2026-10-08，docs/30 §2 D6）：训练页
                // 顶部卡白卡化后不再铺到屏幕物理顶边，于是叠层改由页面让。
                // 与「我的」页同一处理：`pagePadding + LfInsets.top`——不是
                // 只给 `LfInsets.top`，那样卡片会贴到状态栏下缘、与页面左右
                // 的 16 留白不对称。
                padding: EdgeInsets.only(
                  top: LfDimens.pagePadding + LfInsets.top(context),
                  bottom: LfInsets.navReserve(context),
                ),
                children: [
                  TrainingHero(
                    weekIndex: data.weekIndex,
                    finishedCount: data.finishedCount,
                    totalDuration: data.totalDuration,
                    // 消耗 kcal 无数据源（`WorkoutSets` 没有热量列）→ 恒 null，
                    // hero 按 §6.1 渲染「—」而不是编一个数。
                    totalKcal: null,
                    capacityMinutes: data.capacityMinutes,
                    todayIndex: _mondayIndex(today.weekday),
                    restWeekdays: data.restWeekdays,
                  ),
                  if (data.active != null && sessionRepository != null)
                    TrainingActiveBanner(
                      sessionName: data.activeName,
                      completedSets: data.active!.completedSetCount,
                      plannedSets: data.activePlannedSets,
                      // 设计稿画了两个入口（继续训练 / 查看详情）。库里只有
                      // 「训练器 + 会话详情」这一个弹层，两个入口都打开它——
                      // 不为了对齐设计稿去造一块没有差别的第二份 UI。
                      onResume: () =>
                          _openActiveSession(context, sessionRepository),
                      onOpenDetail: () =>
                          _openActiveSession(context, sessionRepository),
                    ),
                  _TrainingSegmentRow(
                    segment: _segment,
                    onChanged: (value) => setState(() => _segment = value),
                  ),
                  if (_segment == _TrainingSegment.plan)
                    ..._planSegment(context, data, planRepository)
                  else
                    ..._historySegment(context, data),
                ],
              );
            },
          ),
          PositionedTrainingPlanFab(onPressed: () => _openNewPlan(context)),
        ],
      ),
    );
  }

  /// 计划分段（docs/21 §5.5）：肌群 chips → 周统计卡 → 计划卡 → 二级入口。
  List<Widget> _planSegment(
    BuildContext context,
    _TrainingSnapshot data,
    WorkoutPlanRepository planRepository,
  ) {
    final sessionRepository = widget.workoutSessionRepository;
    final today = widget.now ?? DateTime.now();
    final filter = _muscleFilter;
    final cards =
        <({_PlanCardData card, List<PlannedExerciseRecord> entries})>[];
    for (final card in data.planCards) {
      final entries = [
        for (final entry in card.day.entries)
          if (filter == null ||
              data.muscleByExerciseId[entry.exerciseId] == filter)
            entry,
      ];
      // 筛选下没有匹配动作的卡整张收掉；「全部」时保留空训练日——设计稿的
      // 卡就是「一个训练日」，空日也是一天。
      if (entries.isEmpty && filter != null) continue;
      cards.add((card: card, entries: entries));
    }
    // Round7 阶段 6 · 缺陷 ㉓：空态统一到 A 的 [LfEmptyState]（52 R18 图标块）
    // ——旧 [AppEmptyState] 是 80dp 渐变圆 + 32px **emoji**，本仓不随包 emoji
    // 字体 ⇒ 帧里是空方框；A 的空态语言是线稿图标。
    final emptyState = data.planCards.isEmpty
        ? const LfEmptyState(
            icon: Icons.fitness_center,
            title: '还没有本地训练计划。',
            message: '新建一个计划，安排本周训练日。',
          )
        : const LfEmptyState(
            icon: Icons.search_off,
            title: '没有匹配的动作。',
            message: '换个肌群筛选，或选「全部」看完整计划。',
          );
    return [
      Padding(
        padding: const EdgeInsets.only(top: LfDimens.spaceMedium),
        child: _TrainingMuscleChipRow(
          selected: filter,
          onChanged: (value) => setState(() => _muscleFilter = value),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          LfDimens.pagePadding,
          LfDimens.spaceMedium,
          LfDimens.pagePadding,
          LfDimens.cardGap,
        ),
        child: TrainingWeekStatsCard(
          weekIndex: data.weekIndex,
          finishedCount: data.finishedCount,
          totalDuration: data.totalDuration,
          totalKcal: null,
          rows: data.weekRows,
          volumeKg: data.weekVolumeKg,
          onOpenRecords: () {
            if (sessionRepository != null) {
              _openPersonalRecords(context, sessionRepository);
            }
          },
        ),
      ),
      if (cards.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: LfDimens.pagePadding),
          child: emptyState,
        ),
      for (final (index, row) in cards.indexed)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LfDimens.pagePadding,
            0,
            LfDimens.pagePadding,
            LfDimens.spaceSmallPlus,
          ),
          child: TrainingPlanCard(
            index: index + 1,
            plan: row.card.plan,
            weekday: row.card.day.weekday,
            entries: row.entries,
            // Round7 逐页对账批次 3：A `app.js:216` 的周安排日签与今日行。
            planWeekdays: row.card.planWeekdays,
            todayWeekday: today.weekday,
            muscleLabels: data.muscleLabelsOf(row.entries),
            isToday: row.card.day.weekday == today.weekday,
            // Round7 裁决 R1：A `app.js:216` 的 `.plan-today` 右端 CTA 只在
            // 「今天这张卡」上给（本仓一计划日一张卡；非今日卡画一枚永久
            // 禁用的按钮只是噪音——登记为与 A 的形态差异）。
            todayCtaLabel: row.card.day.weekday != today.weekday
                ? null
                : data.active != null && sessionRepository != null
                ? '继续训练'
                : '开始训练',
            onTodayCta: row.card.day.weekday != today.weekday
                ? null
                : data.active != null && sessionRepository != null
                ? () => _openActiveSession(context, sessionRepository)
                : () => _startSessionForPlan(
                    context,
                    null,
                    row.card.plan.id,
                    today.weekday,
                  ),
            onTap: () => _openPlanDetail(
              context,
              row.card.plan.id,
              row.card.plan.name,
              planRepository,
            ),
            onDelete: () => _confirmRemovePlan(
              context,
              row.card.plan.id,
              row.card.plan.name,
              planRepository,
            ),
          ),
        ),
      ..._secondaryEntries(context, data, planRepository),
    ];
  }

  /// 二级入口（docs/22 裁决 ②）：设计稿没画到、但数据与逻辑都要留的三件事，
  /// 各自只占一行。
  List<Widget> _secondaryEntries(
    BuildContext context,
    _TrainingSnapshot data,
    WorkoutPlanRepository planRepository,
  ) {
    final sessionRepository = widget.workoutSessionRepository;
    return [
      const SizedBox(height: LfDimens.spaceSmall),
      if (sessionRepository != null && data.history.isNotEmpty)
        _SecondaryEntry(
          entryKey: const Key('training-stats'),
          icon: Icons.assessment_outlined,
          label: '训练统计',
          onTap: () => _openStatistics(context, sessionRepository),
        ),
      // 训练达标（docs/21 §5.1 第 5 项）：设计稿的今日页没有这一格，
      // 按 docs/22 裁决 ② 由本页以弹层承载（阶段 I 补漏——此前只在旧今日
      // 首屏出现，重建后一度没有任何可达入口）。
      if (sessionRepository != null)
        _SecondaryEntry(
          entryKey: const Key('training-target-progress'),
          icon: Icons.flag_outlined,
          label: '训练达标',
          onTap: () =>
              _openTrainingTargets(context, planRepository, sessionRepository),
        ),
      // 2026-10-23 用户：「删『AI 生成训练计划』按钮，功能转移到 ➕」——
      // 入口只保留 FAB（`cta-new-plan` 的模式弹层里选「AI 生成」，走
      // `/workout-plan-create` 页）；这里不再有第二个入口。
      _SecondaryEntry(
        entryKey: const Key('training-exercise-library'),
        icon: Icons.fitness_center,
        label: '动作库',
        // A `app.js:216` 的 list-link 是两行：标题 + 「先了解动作，再开始训练」。
        subtitle: '先了解动作，再开始训练',
        onTap: () => _openExerciseLibrary(context),
      ),
    ];
  }

  /// 动作库二级页（docs/22 裁决 ②）。导航写在这里，页面本体不持有入口。
  void _openExerciseLibrary(BuildContext context) {
    final repository = widget.exerciseRepository;
    if (repository == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExerciseLibraryPage(repository: repository),
      ),
    );
  }

  /// 历史分段：已结束训练的逐次记录。设计稿没画这一屏，但分段画了，
  /// 所以它必须真的给出内容（用库里已有的真实数据，不造演示行）。
  List<Widget> _historySegment(BuildContext context, _TrainingSnapshot data) {
    final c = context.lf;
    if (data.history.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(
            LfDimens.pagePadding,
            LfDimens.spaceSmall,
            LfDimens.pagePadding,
            0,
          ),
          child: LfEmptyState(
            icon: Icons.event_note_outlined,
            title: '还没有已结束的训练。',
            message: '完成一次训练后，这里会留下逐次记录。',
          ),
        ),
      ];
    }
    return [
      for (final session in data.history)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LfDimens.pagePadding,
            LfDimens.spaceSmall,
            LfDimens.pagePadding,
            0,
          ),
          child: DesignCard(
            key: Key('training-history-${session.id}'),
            // Round7 逐页对账批次 4：A `app.js:559` 的历史行可点出
            // 「训练回顾」只读弹层（数据全在 WorkoutSessionRecord 里，
            // 不新增查询、不写库）。
            onTap: () => _openSessionReview(
              context,
              session,
              data.planNameOf(session.planId) ?? '自由训练',
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.planNameOf(session.planId) ?? '自由训练',
                        style: LfText.bodyStrong.copyWith(
                          color: c.cardForeground,
                        ),
                      ),
                      const SizedBox(height: LfDimens.spaceMicro),
                      Text(
                        '${session.localDate} · ${session.completedSetCount} 组 · '
                        '${session.totalVolumeKg.toStringAsFixed(1)}kg',
                        style: LfText.caption.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Text(
                  TrainingHero.formatDuration(_sessionDuration(session)),
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// 训练页一次构建需要的全部派生值（docs/21 §5.5「数据来源」）。
  Future<_TrainingSnapshot> _loadSnapshot(DateTime today) async {
    final exerciseRepository = widget.exerciseRepository!;
    final planRepository = widget.workoutPlanRepository!;
    final sessionRepository = widget.workoutSessionRepository;

    final summaries = await planRepository.list();
    final details = <String, WorkoutPlanRecord>{};
    for (final summary in summaries) {
      final detail = await planRepository.getById(summary.id);
      if (detail != null) details[summary.id] = detail;
    }
    final planCards = <_PlanCardData>[];
    for (final summary in summaries) {
      final days = details[summary.id]?.days ?? const <WorkoutPlanDayRecord>[];
      // 周安排日签的「计划日」（与休息日图例同口径：有编排才算训练日）。
      final planWeekdays = <int>{
        for (final day in days)
          if (day.entries.isNotEmpty) day.weekday,
      };
      for (final day in days) {
        planCards.add(
          _PlanCardData(
            plan: summary,
            day: day,
            dayCount: days.length,
            planWeekdays: planWeekdays,
          ),
        );
      }
    }
    // 休息日 = 计划里没有任何动作编排的星期（§6.2 裁决 4）。一个计划都没有
    // 时不渲染图例，否则会说「一周七天全是休息日」。
    final plannedWeekdays = <int>{
      for (final detail in details.values)
        for (final day in detail.days)
          if (day.entries.isNotEmpty) day.weekday,
    };
    final restWeekdays = plannedWeekdays.isEmpty
        ? const <int>[]
        : [
            for (var weekday = 1; weekday <= 7; weekday++)
              if (!plannedWeekdays.contains(weekday)) weekday,
          ];

    final weekStart = _mondayOf(today);
    final weekEnd = weekStart.add(const Duration(days: 6));
    var weekSessions = const <WorkoutSessionRecord>[];
    var history = const <WorkoutSessionRecord>[];
    WorkoutSessionRecord? active;
    if (sessionRepository != null) {
      weekSessions = await sessionRepository.listFinishedBetween(
        _dateOnly(weekStart),
        _dateOnly(weekEnd),
      );
      history = (await sessionRepository.listAllFinished()).reversed.toList(
        growable: false,
      );
      active = await sessionRepository.getActive();
    }

    var totalDuration = Duration.zero;
    final capacityMinutes = List<int>.filled(7, 0);
    for (final session in weekSessions) {
      final duration = _sessionDuration(session);
      totalDuration += duration;
      final weekday = weekdayOfLocalDate(session.localDate);
      if (weekday != null) {
        capacityMinutes[_mondayIndex(weekday)] += duration.inMinutes;
      }
    }
    final weekVolumeKg = const TrainingStatsCalculator().weeklyVolumeKg(
      weekSessions,
    );

    // 肌群按 id 逐个取（本周记录过的动作 + 计划里排过的动作），不从
    // `search('')` 整库拉——那是 limit 100 的接口，库一超就静默少数据。
    final neededIds = <String>{
      for (final session in weekSessions)
        for (final set in session.sets) set.exerciseId,
      for (final card in planCards)
        for (final entry in card.day.entries) entry.exerciseId,
    };
    final muscleByExerciseId = <String, MuscleGroup>{};
    for (final id in neededIds) {
      final exercise = await exerciseRepository.getById(id);
      if (exercise != null) muscleByExerciseId[id] = exercise.muscleGroup;
    }

    // 本周分肌群行按**已记录组次**聚合：不按时长分，避免一次跨肌群的训练
    // 被重复计入多行。
    final setsByMuscle = <MuscleGroup, int>{};
    final volumeByMuscle = <MuscleGroup, double>{};
    for (final session in weekSessions) {
      for (final set in session.sets) {
        final group = muscleByExerciseId[set.exerciseId];
        if (group == null) continue;
        setsByMuscle.update(group, (value) => value + 1, ifAbsent: () => 1);
        volumeByMuscle.update(
          group,
          (value) => value + set.weightKg * set.reps,
          ifAbsent: () => set.weightKg * set.reps,
        );
      }
    }
    final weekRows = <({String label, String value})>[
      for (final group in _muscleDisplayOrder)
        if (setsByMuscle[group] != null)
          (
            label: group.label,
            value:
                '${setsByMuscle[group]}组 · '
                '${(volumeByMuscle[group] ?? 0).toStringAsFixed(1)}kg',
          ),
    ];

    // 「第 N 周」= 从首个已结束训练起算的周序号（§7.1 派生只读）。
    int? weekIndex;
    if (history.isNotEmpty) {
      final first = DateTime.tryParse(history.last.localDate);
      if (first != null) {
        final weeks = _mondayOf(today).difference(_mondayOf(first)).inDays ~/ 7;
        if (weeks >= 0) weekIndex = weeks + 1;
      }
    }

    final planNames = {
      for (final summary in summaries) summary.id: summary.name,
    };
    final activeSession = active;
    return _TrainingSnapshot(
      planCards: planCards,
      weekIndex: weekIndex,
      finishedCount: weekSessions.length,
      totalDuration: totalDuration,
      weekVolumeKg: weekVolumeKg,
      capacityMinutes: capacityMinutes,
      weekRows: weekRows,
      restWeekdays: restWeekdays,
      active: activeSession,
      activeName: activeSession == null
          ? ''
          : planNames[activeSession.planId] ?? '自由训练',
      activePlannedSets: activeSession == null
          ? null
          : _plannedSetsFor(activeSession, details),
      history: history,
      planNames: planNames,
      muscleByExerciseId: muscleByExerciseId,
    );
  }

  /// 进行中会话的计划总组数。计划已删 / 当天没有编排 / 日期畸形 → null，
  /// 此时横幅不画进度条（不编一个假分母）。
  int? _plannedSetsFor(
    WorkoutSessionRecord session,
    Map<String, WorkoutPlanRecord> details,
  ) {
    final planId = session.planId;
    if (planId == null) return null;
    final weekday = weekdayOfLocalDate(session.localDate);
    if (weekday == null) return null;
    final day = details[planId]?.days
        .where((candidate) => candidate.weekday == weekday)
        .firstOrNull;
    if (day == null || day.entries.isEmpty) return null;
    return day.entries.fold<int>(0, (total, entry) => total + entry.targetSets);
  }

  /// 单次训练的时长（`finishedAt - startedAt`）。未结束或时钟回拨 → 0。
  Duration _sessionDuration(WorkoutSessionRecord session) {
    final finished = session.finishedAt;
    if (finished == null) return Duration.zero;
    final elapsed = finished.difference(session.startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// 周一..周日的 0 基索引（容量图与 `workoutWeekdayLabels` 同一约定）。
  int _mondayIndex(int weekday) => weekday - 1;

  /// `cta-new-plan`（docs/21 §5.5 交互表：**→ 现有计划新建页**）。
  ///
  /// 路由由 `app_router` 注入（页面不持有导航）：四项依赖齐全时推入
  /// `/workout-plan-create`；未接线时（`onOpenWorkoutPlanCreate == null`）
  /// 退回极简「计划名称」弹层——**宁可给一个能用的简化入口，也不把用户
  /// 送到「尚未配置」占位页**（docs/21 §6.1 诚实规则）。
  /// FAB `cta-new-plan`（docs/30 §2 D7）：**总是先问「怎么建」**。
  ///
  /// 旧动线是「AI 四项依赖齐全 → 直跳 AI 流程；否则 → 名称弹层建空计划」，
  /// 于是配好 AI 的用户**永远看不到**手动这条路（这正是用户说的「不能手动」），
  /// 而没配 AI 的用户只能建出空计划再逐个补动作。现在两条路都在弹层里，
  /// 且手动页本身就带完整表单 ⇒ 没配 AI 也能一次建出有内容的计划。
  Future<void> _openNewPlan(BuildContext context) async {
    final openAi = widget.onOpenWorkoutPlanCreate;
    final openManual = widget.onOpenWorkoutPlanManual;
    // 两条路都没有＝依赖不齐到连手动都做不了（连动作库或计划仓储都没接），
    // 此时不给一个点了没反应的 FAB。
    if (openAi == null && openManual == null) return;
    final choice = await AppSheet.show<PlanCreationMode>(
      context,
      title: '新建训练计划',
      // 【Builder 是必须的】弹层挂在**根**导航器上（`useRootNavigator: true`），
      // 而训练页住在 shell 的嵌套导航器里。直接用页面的 `context` 调
      // `Navigator.pop` 会弹掉**嵌套导航器的最后一页**（训练页本身），
      // go_router 随即断言 "You have popped the last page off of the stack"。
      // 取弹层内的 context 才是「关掉这个弹层」。
      content: Builder(
        builder: (sheetContext) => _PlanModeSheet(
          aiReady: openAi != null,
          onSelected: (mode) => Navigator.of(sheetContext).pop(mode),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case PlanCreationMode.ai:
        openAi?.call();
      case PlanCreationMode.manual:
        openManual?.call();
    }
  }

  // `_openCreatePlanDialog`（只输名称、`days: const []` 建空计划）已删除
  // （docs/30 §2 D7）：它的唯一调用点是旧 `_openNewPlan` 的 AI-依赖缺失分支。
  // 那条路径让用户「先建一个空计划，再进详情逐个补动作」，中途退出就留下一个
  // 空计划；现在手动页把整条动线收进一屏，**没内容就存不下来**。

  Future<void> _openPlanDetail(
    BuildContext context,
    String planId,
    String planName,
    WorkoutPlanRepository repository,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      // docs/21 附录 D8（RV-P1-11）：shell 是 extendBody 结构，必须挂根导航器。
      useRootNavigator: true,
      showDragHandle: true,
      // docs/32 §3 D15 方案 B（需求 79）：外层只认把手。
      // 整层可拖时把手位移按运行时 _childHeight 换算入场 progress，
      // 而内层 DraggableScrollableSheet 的 extent 变化会改变该高度 ⇒ 比例跳变。
      enableDrag: false,
      isScrollControlled: true,
      // 底部至少留 [LfDimens.sheetBottomMinInset]：这两个弹层走裸
      // `showModalBottomSheet`（DraggableScrollableSheet 形态），不经过
      // `AppSheet` 的共享壳——2026-10-16 用户要求「所有抽屉式卡片，最下边
      // 控件距底边间距合适」，这里用同一个计算函数补齐。
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: sheetBottomInset(sheetContext)),
        child: _PlanDetailSheet(
          planId: planId,
          planName: planName,
          repository: repository,
          exerciseRepository: widget.exerciseRepository!,
          sessionRepository: widget.workoutSessionRepository,
          now: widget.now,
          onStartDay: (weekday) =>
              _startSessionForPlan(context, sheetContext, planId, weekday),
          onDelete: () => _removePlanFromDetail(
            context,
            sheetContext,
            planId,
            planName,
            repository,
          ),
        ),
      ),
    );
  }

  /// 删除计划（docs/22 裁决 ②）。
  ///
  /// 新设计的计划卡没有行内删除钮（设计稿没画），删除入口收在**详情**这一层：
  /// 先关详情，确认弹层落在页面上——不叠在详情上面，否则用户点完「删除」
  /// 会看到两层弹层叠着，取消后还得再关一次。
  Future<void> _removePlanFromDetail(
    BuildContext pageContext,
    BuildContext sheetContext,
    String planId,
    String planName,
    WorkoutPlanRepository repository,
  ) async {
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
    await _confirmRemovePlan(pageContext, planId, planName, repository);
  }

  /// [sheetContext] 是「开始入口所在的弹层」：计划详情里点开始时要把它关掉，
  /// **计划卡卡面（Round7 裁决 R1）没有弹层** ⇒ 传 null，其余逻辑一字不差。
  Future<void> _startSessionForPlan(
    BuildContext pageContext,
    BuildContext? sheetContext,
    String planId,
    int weekday,
  ) async {
    final sessionRepository = widget.workoutSessionRepository;
    final planRepository = widget.workoutPlanRepository;
    if (sessionRepository == null || planRepository == null) return;

    void reject(String message) {
      // 页面 snackbar 会被详情遮住；先关弹层再解释为什么没有开始。
      if (sheetContext != null && sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
      if (!pageContext.mounted) return;
      AppSnackBar.show(pageContext, message, icon: AppSnackBar.errorIcon);
    }

    final requestedDate = widget.now ?? DateTime.now();
    if (weekday != requestedDate.weekday) {
      reject('仅可开始今天的训练；其他训练日仍可查看和编辑。');
      return;
    }
    final plan = await planRepository.getById(planId);
    if (!pageContext.mounted) return;
    if (sheetContext != null && !sheetContext.mounted) return;
    final day = plan?.days
        .where((candidate) => candidate.weekday == weekday)
        .firstOrNull;
    if (day == null || day.entries.isEmpty) {
      reject('该训练日没有可记录的动作，请先添加动作。');
      return;
    }
    // 详情可能跨零点常驻，读计划也可能跨天。写入前重新确认日期，绝不
    // 回填昨天或把用户点的那一行静默换成另一个训练日。
    final currentDate = widget.now ?? DateTime.now();
    if (formatLocalDate(currentDate) != formatLocalDate(requestedDate) ||
        weekday != currentDate.weekday) {
      reject('日期已变化，仅可开始今天的训练。请重新打开计划。');
      return;
    }
    try {
      await sessionRepository.start(
        localDate: formatLocalDate(currentDate),
        planId: planId,
      );
    } on StateError catch (error) {
      reject(error.message);
      return;
    } on FormatException catch (error) {
      reject(error.message);
      return;
    }
    // 计划详情弹层在 go_router 分支 Navigator 上，rootNavigator 的 popUntil
    // 关不掉它；用弹层自身 context 关掉，避免会话结束后残留详情叠层。
    if (sheetContext != null && sheetContext.mounted) {
      Navigator.of(sheetContext).pop();
    }
    if (!pageContext.mounted) return;
    await _openActiveSession(pageContext, sessionRepository);
    // 弹层挂在根导航器上，可能比本页活得久（docs/11 §3-E）：await 之后必须
    // 重新确认本页还在树上，否则弹层关闭时会 setState 到已销毁的 State。
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openActiveSession(
    BuildContext context,
    WorkoutSessionRepository sessionRepository,
  ) async {
    final active = await sessionRepository.getActive();
    if (active == null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      // docs/21 附录 D8（RV-P1-11）：同上，必须挂根导航器。
      useRootNavigator: true,
      showDragHandle: true,
      // 方案 B：外层只认把手（同上）。
      enableDrag: false,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        // 同 `_openPlanDetail`：裸弹层自己补最小底衬。
        padding: EdgeInsets.only(bottom: sheetBottomInset(sheetContext)),
        child: _ActiveSessionSheet(
          sessionRepository: sessionRepository,
          planRepository: widget.workoutPlanRepository!,
          exerciseRepository: widget.exerciseRepository!,
          now: widget.now,
        ),
      ),
    );
    // 同上：弹层关闭时本页可能已被销毁。
    if (!mounted) return;
    setState(() {});
  }

  /// 「训练回顾」只读弹层（Round7 逐页对账批次 4，A `app.js:559`）。
  ///
  /// A 的字段：已完成组数（大字）/ 名称 / 训练日期 / 训练时长 / 总容量 /
  /// **估算消耗**。本仓 `WorkoutSets` 没有热量列（docs/21 §5.5 已钉：
  /// `totalKcal` 恒传 null ⇒ 渲染「—」而不是编一个数）⇒ 这一格如实写「—」，
  /// 并在注里说明原因，不虚构卡路里。
  Future<void> _openSessionReview(
    BuildContext context,
    WorkoutSessionRecord session,
    String planName,
  ) {
    return AppSheet.show<void>(
      context,
      title: '训练回顾',
      content: _SessionReviewContent(
        session: session,
        planName: planName,
        durationLabel: TrainingHero.formatDuration(_sessionDuration(session)),
      ),
    );
  }

  Future<void> _openStatistics(
    BuildContext context,
    WorkoutSessionRepository sessionRepository,
  ) {
    // docs/32 §3 D15：本处**无拖动需求** ⇒ 迁统一壳 AppSheet
    // （enableDrag:false + 把手 + 90% 限高 + 统一动效）。
    return AppSheet.showCustom<void>(
      context,
      builder: (_) => _StatisticsSheetContent(
        sessionRepository: sessionRepository,
        // 缺陷 ㉖（批次 5 实测）：肌群分布要把 `set.exerciseId` 映射到
        // 肌群，而此前这里只传了会话仓储、动作列表恒为空 ⇒
        // 「肌群分布（按容量）」**永远**显示「暂无肌群分布数据。」。
        exerciseRepository: widget.exerciseRepository,
      ),
    );
  }

  /// 训练达标弹层（docs/21 §5.1 第 5 项，docs/22 裁决 ② 收进二级入口）。
  ///
  /// 弹层只承载 [DashboardTrainingTargets] 本身：计数口径、空态与加载态
  /// 都由它一处决定，本页不复制第二份算法。
  Future<void> _openTrainingTargets(
    BuildContext context,
    WorkoutPlanRepository planRepository,
    WorkoutSessionRepository sessionRepository,
  ) {
    // docs/32 §3 D15：无拖动需求 ⇒ 迁 AppSheet；顺带修掉原先缺
    // `isScrollControlled` 导致的 9/16 屏限高（内容被压扁）。
    return AppSheet.showCustom<void>(
      context,
      builder: (_) => Padding(
        padding: const EdgeInsets.only(bottom: LfDimens.spaceLarge),
        child: DashboardTrainingTargets(
          planRepository: planRepository,
          sessionRepository: sessionRepository,
          localDate: formatLocalDate(widget.now ?? DateTime.now()),
        ),
      ),
    );
  }

  Future<void> _openPersonalRecords(
    BuildContext context,
    WorkoutSessionRepository sessionRepository,
  ) {
    // docs/32 §3 D15：无拖动需求 ⇒ 迁 AppSheet；future 由子件 State 持有，
    // 不在 build 内创建（把手拖动会重建子树，build 内建 future 会重取）。
    return AppSheet.showCustom<void>(
      context,
      builder: (_) =>
          _PersonalRecordsSheet(sessionRepository: sessionRepository),
    );
  }

  Future<void> _confirmRemovePlan(
    BuildContext context,
    String planId,
    String planName,
    WorkoutPlanRepository repository,
  ) {
    return AppSheet.show<void>(
      context,
      title: '删除训练计划',
      content: Text('删除「$planName」后，其训练日和动作安排都会一并移除。'),
      actions: Builder(
        builder: (dialogContext) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 弹层行动档（§3.4/§3.8）：左 = 取消（B6），右 = 破坏性确认（B7）
            // （`我的.html:524-532` 的「清除所有数据」就是 error 字色的行，
            // 设计稿里没有实心 error 按钮）。原来手写 `FilledButton.styleFrom
            // (backgroundColor: error)` 正是设计稿没有的那种形态。
            LfTextButton(
              label: '取消',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            LfDangerButton(
              key: const Key('training-plan-delete-confirm'),
              label: '删除',
              onPressed: () async {
                try {
                  await repository.removePlan(planId);
                } catch (_) {
                  // 删除失败（如数据库异常）不能抛成未捕获异步错误、让弹层卡死。
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  AppSnackBar.show(
                    context,
                    '删除失败，请重试。',
                    icon: AppSnackBar.errorIcon,
                  );
                  return;
                }
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 训练统计底层内容（docs/21 §5.5）：显示训练趋势、肌群分布、常用动作。
final class _StatisticsSheetContent extends StatefulWidget {
  const _StatisticsSheetContent({
    required this.sessionRepository,
    this.exerciseRepository,
  });

  final WorkoutSessionRepository sessionRepository;

  /// 动作库（肌群归属的唯一来源）。null = 未接线 ⇒ 分布拿不到归属，
  /// 如实走空态（不猜肌群）。
  final ExerciseRepository? exerciseRepository;

  @override
  State<_StatisticsSheetContent> createState() =>
      _StatisticsSheetContentState();
}

final class _StatisticsSheetContentState
    extends State<_StatisticsSheetContent> {
  late final TrainingStatsCalculator _calculator;
  late Future<List<WorkoutSessionRecord>> _sessionsFuture;
  late List<ExerciseRecord> _exercises = const [];
  late DateTime _latestWeekMonday;

  @override
  void initState() {
    super.initState();
    _calculator = TrainingStatsCalculator();
    _sessionsFuture = widget.sessionRepository.listAllFinished().then((
      rows,
    ) async {
      // 动作表一次读完（312 条量级）：肌群归属只用它，不用会话里的名字猜。
      final repository = widget.exerciseRepository;
      if (repository != null) {
        _exercises = await repository.search('');
      }
      return rows;
    });
    final today = DateTime.now();
    _latestWeekMonday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<List<WorkoutSessionRecord>>(
        future: _sessionsFuture,
        builder: (context, snapshot) {
          final sessions = snapshot.data ?? const [];
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final trend = _calculator.trainingTrendWeeklyVolume(
            sessions: sessions,
            endOfLatestWeek: _latestWeekMonday,
            weeks: 4,
          );
          final muscleDist = _calculator.muscleGroupDistribution(
            sessions: sessions,
            exercises: _exercises,
          );
          final mostUsed = _calculator.mostUsedExercises(
            sessions: sessions,
            limit: 5,
          );
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text('训练统计', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('训练趋势、肌群分布、常用动作。'),
              const SizedBox(height: 16),
              _TrendSection(trend: trend),
              const SizedBox(height: 20),
              _MuscleDistributionSection(distribution: muscleDist),
              const SizedBox(height: 20),
              _MostUsedExercisesSection(exercises: mostUsed),
            ],
          );
        },
      ),
    );
  }
}

/// 容量图柱区高度（缺陷 ㉗）：`FractionallySizedBox` 的百分比高度必须落在
/// 有限高里，否则无界约束下直接抛 NaN。
const double _trendBarAreaHeight = 80;

final class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.trend});

  final List<double> trend;

  @override
  Widget build(BuildContext context) {
    final maxVolume = trend.isEmpty
        ? 1.0
        : trend.reduce((a, b) => a > b ? a : b);
    final maxValue = maxVolume > 0 ? maxVolume : 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('训练趋势（近 4 周容量）', style: LfText.headline),
        // Round7 裁决 R2：A `app.js:267` 的口径说明句（标题搬了、句子漏了）。
        const SizedBox(height: 2),
        Text(
          '容量 = 每组重量 × 次数的合计',
          key: const Key('training-trend-note'),
          style: LfText.caption.copyWith(color: context.lf.mutedForeground),
        ),
        const SizedBox(height: 8),
        if (trend.every((v) => v == 0))
          const Text('暂无训练记录。')
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < trend.length; i++)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 32,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Text(
                          trend[i] > 0 ? '${trend[i].toInt()}kg' : '',
                          style: LfText.label,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 缺陷 ㉗（批次 5 帧审看抓到）：柱体此前只有 `width: 32`
                    // **没有高度** —— 外层 `Column(mainAxisSize: min)` 给的是
                    // 无界高，`FractionallySizedBox` 拿不到有限高 ⇒
                    // 「BoxConstraints has NaN values in minHeight/maxHeight」
                    // 当场抛在 `RenderDecoratedBox` 上（带真实训练数据打开
                    // 「训练统计」必现；此前没有一条用例/帧走过这条路）。
                    // 柱区高度显式给出，百分比高度才有分母。
                    SizedBox(
                      width: 32,
                      height: _trendBarAreaHeight,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (trend[i] / maxValue).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: LfColors.mint(Theme.of(context).brightness)
                                  .tone(600),
                              borderRadius: BorderRadius.circular(
                                LfDimens.radiusSm,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 数据是时间升序（index 0 = 最早），所以「几周前」由
                    // 数组长度反推；末位才是本周。曾经按降序写成
                    // `trend.length - i`，改用升序后标签会整个反过来。
                    Text(
                      i == trend.length - 1
                          ? '本周'
                          : '${trend.length - 1 - i}周前',
                      style: LfText.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}

final class _MuscleDistributionSection extends StatelessWidget {
  const _MuscleDistributionSection({required this.distribution});

  final Map<MuscleGroup, double> distribution;

  @override
  Widget build(BuildContext context) {
    final total = distribution.values.fold(0.0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('肌群分布（按容量）', style: LfText.headline),
        const SizedBox(height: 8),
        if (distribution.isEmpty)
          const Text('暂无肌群分布数据。')
        else
          for (final entry in distribution.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A `app.js:267` 的图例是「名称 / 百分比 / kg」三件：
                  // 百分比说了占比，kg 才是这件事的绝对量（裁决 R2）。
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${entry.key.label} '
                          '${total > 0 ? ((entry.value / total) * 100).round() : 0}%',
                          style: LfText.body,
                        ),
                      ),
                      Text(
                        '${formatGroupedInt(entry.value.round())} kg',
                        key: Key('training-muscle-kg-${entry.key.name}'),
                        style: LfText.body.copyWith(
                          color: context.lf.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final barWidth = total > 0
                          ? (entry.value / total) * constraints.maxWidth
                          : 0.0;
                      return Stack(
                        children: [
                          Container(
                            height: 8,
                            width: constraints.maxWidth,
                            decoration: BoxDecoration(
                              color: context.lf.muted,
                              borderRadius: BorderRadius.circular(
                                LfDimens.radiusSm,
                              ),
                            ),
                          ),
                          if (barWidth > 0)
                            Positioned(
                              left: 0,
                              child: Container(
                                height: 8,
                                width: barWidth,
                                decoration: BoxDecoration(
                                  color: LfColors.mint(
                                    Theme.of(context).brightness,
                                  ).tone(600),
                                  borderRadius: BorderRadius.circular(
                                    LfDimens.radiusSm,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

final class _MostUsedExercisesSection extends StatelessWidget {
  const _MostUsedExercisesSection({required this.exercises});

  final List<MostUsedExercise> exercises;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('常用动作（按组数）', style: LfText.headline),
        const SizedBox(height: 8),
        if (exercises.isEmpty)
          const Text('暂无常用动作数据。')
        else
          for (final exercise in exercises)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: _LeadingBadge(
                icon: Icons.fitness_center_outlined,
                tint: LfColors.mint(Theme.of(context).brightness).tone(100),
                foreground: LfColors.mint(Theme.of(context).brightness)
                    .tone(600),
              ),
              title: Text(exercise.exerciseName, style: LfText.body),
              subtitle: Text(
                '${exercise.setCount} 组 · ${exercise.volume.toInt()}kg',
                style: LfText.bodySmall.copyWith(
                  color: context.lf.mutedForeground,
                ),
              ),
            ),
      ],
    );
  }
}

final class _PlanDetailSheet extends StatefulWidget {
  const _PlanDetailSheet({
    required this.planId,
    required this.planName,
    required this.repository,
    required this.exerciseRepository,
    required this.sessionRepository,
    required this.now,
    required this.onStartDay,
    required this.onDelete,
  });

  final String planId;

  /// 详情打开时的计划名（删除确认文案用；详情内部仍以库里读到的
  /// `plan.name` 为准显示）。
  final String planName;
  final WorkoutPlanRepository repository;
  final ExerciseRepository exerciseRepository;
  final WorkoutSessionRepository? sessionRepository;
  final DateTime? now;
  final ValueChanged<int> onStartDay;

  /// 删除这个计划（二级入口，见 [_TrainingPageState._removePlanFromDetail]）。
  final VoidCallback onDelete;

  @override
  State<_PlanDetailSheet> createState() => _PlanDetailSheetState();
}

final class _PlanDetailSheetState extends State<_PlanDetailSheet> {
  late Future<WorkoutPlanRecord?> _plan = widget.repository.getById(
    widget.planId,
  );

  void _reload() {
    setState(() {
      _plan = widget.repository.getById(widget.planId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<WorkoutPlanRecord?>(
        future: _plan,
        builder: (context, snapshot) {
          final plan = snapshot.data;
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (plan == null) {
            return const SizedBox(
              height: 160,
              child: Center(child: Text('计划不存在或已被删除。')),
            );
          }
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.3,
            // 方案 B：停靠点 + 缩到最小不关窗（Flutter 默认
            // shouldCloseOnMinExtent:true 会在内容缩到底时误关整个弹层）。
            snap: true,
            snapSizes: const [0.6, 0.9],
            shouldCloseOnMinExtent: false,
            builder: (context, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          plan.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      // 来源标签（docs/30 §2 D7 第 ⑥ 帧）：AI 排的计划改起来与
                      // 手动计划没有区别，但用户有权知道「这些动作是 AI 排的
                      // 还是我自己挑的」。`source` 列本来就落库（`ai`/`manual`），
                      // 这一步只是把它显示出来。
                      LfBadge(
                        key: const Key('training-plan-source'),
                        workoutPlanSourceLabel(plan.source),
                      ),
                      const SizedBox(width: LfDimens.spaceSmall),
                      // 弹层顶栏动作 = §3.8 B4 的圆形图标钮（裸 IconButton 的
                      // 48 方框会把这一行撑高）。
                      LfCircleIconButton(
                        key: Key('training-plan-delete-${widget.planId}'),
                        icon: Icons.delete_outline,
                        tooltip: '删除计划',
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: plan.days.isEmpty
                      ? const Center(child: Text('该计划还没有安排任何动作。'))
                      : ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          children: [
                            for (final day in plan.days) ...[
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 4,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '周${workoutWeekdayLabel(day.weekday)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                    ),
                                    // 计划日行内的「开始训练」= §3.8 B3 的
                                    // `soft` 档（内联动作、轻强调），比裸
                                    // TextButton 更像一个可点的入口。
                                    LfPillButton(
                                      key: const Key('training-session-start'),
                                      label: '开始训练',
                                      icon: Icons.play_arrow,
                                      tone: LfPillTone.soft,
                                      onPressed:
                                          widget.sessionRepository != null &&
                                              day.weekday ==
                                                  (widget.now ?? DateTime.now())
                                                      .weekday &&
                                              day.entries.isNotEmpty
                                          ? () => widget.onStartDay(day.weekday)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                              if (day.weekday !=
                                  (widget.now ?? DateTime.now()).weekday)
                                Text(
                                  '仅可开始今天的训练；其他训练日仍可查看和编辑。',
                                  style: LfText.caption.copyWith(
                                    color: context.lf.mutedForeground,
                                  ),
                                )
                              else if (day.entries.isEmpty)
                                Text(
                                  '该训练日没有可记录的动作，请先添加动作。',
                                  style: LfText.caption.copyWith(
                                    color: context.lf.mutedForeground,
                                  ),
                                ),
                              for (final entry in day.entries)
                                ListTile(
                                  key: Key('training-entry-${entry.id}'),
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(entry.exerciseName),
                                  subtitle: Text(
                                    '目标：${entry.targetSets} 组 × ${entry.targetReps} 次'
                                    '${entry.targetWeightKg == null ? '' : ' · ${_weightText(entry.targetWeightKg!)}kg'}',
                                  ),
                                  trailing: LfCircleIconButton(
                                    key: Key(
                                      'training-entry-delete-${entry.id}',
                                    ),
                                    icon: Icons.close,
                                    iconSize: LfDimens.iconMd,
                                    tooltip: '移除动作',
                                    onPressed: () async {
                                      await widget.repository.removeEntry(
                                        entry.id,
                                      );
                                      _reload();
                                    },
                                  ),
                                ),
                            ],
                            if (widget.sessionRepository != null)
                              _PlanCompletionLine(
                                sessionRepository: widget.sessionRepository!,
                                planId: plan.id,
                                planWeekdays: [
                                  for (final day in plan.days) day.weekday,
                                ],
                                now: widget.now,
                              ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: LfConfirmButton(
                    key: const Key('training-plan-entry-add'),
                    icon: Icons.add,
                    label: '添加动作',
                    onPressed: () => _openEntryDialog(context),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _weightText(double weight) =>
      weight == weight.roundToDouble() ? weight.toStringAsFixed(0) : '$weight';

  Future<void> _openEntryDialog(BuildContext context) async {
    // 走共享件（docs/30 §2 D7）：字段、校验、提示与「新建手动计划」页**同源**。
    // 这里曾有第二份逐字复刻的表单——两份校验迟早漂，而漂了之后用户看到的是
    // 同一件事在两张页面上说法不同。
    final options = await widget.exerciseRepository.search('');
    if (!context.mounted) return;
    final input = await showPlannedEntrySheet(
      context,
      options: options,
      // 落库失败**不关窗**：错误留在弹层里，用户填的组次/重量不丢。
      onSubmit: (input) async {
        try {
          await widget.repository.addEntry(
            widget.planId,
            input.weekday,
            input.entry,
          );
          return null;
        } on FormatException catch (error) {
          return error.message;
        } on StateError catch (error) {
          return error.message;
        }
      },
    );
    if (input == null || !mounted) return;
    _reload();
  }
}

final class _ActiveSessionSheet extends StatefulWidget {
  const _ActiveSessionSheet({
    required this.sessionRepository,
    required this.planRepository,
    required this.exerciseRepository,
    required this.now,
  });

  final WorkoutSessionRepository sessionRepository;
  final WorkoutPlanRepository planRepository;
  final ExerciseRepository exerciseRepository;
  final DateTime? now;

  @override
  State<_ActiveSessionSheet> createState() => _ActiveSessionSheetState();
}

final class _ActiveSessionSheetState extends State<_ActiveSessionSheet> {
  /// 组间休息默认 90 秒（docs/21 §5.5「设置组数/次数/重量/休息」）。
  static const defaultRestSeconds = 90;

  /// 本次训练的休息时长：记录一组时按该组填写的值重置倒计时，不填就用
  /// 默认值。刻意不做成全局设置——同日不同动作的合理间歇本来就不一样。
  int _restSeconds = defaultRestSeconds;

  late Future<WorkoutSessionRecord?> _session;
  DateTime? _restEnd;

  @override
  void initState() {
    super.initState();
    _reloadSession();
  }

  void _reloadSession() {
    _session = widget.sessionRepository.getActive();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<WorkoutSessionRecord?>(
        future: _session,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final session = snapshot.data;
          if (session == null || !session.isActive) {
            return const SizedBox(
              height: 160,
              child: Center(child: Text('训练会话不存在或已结束。')),
            );
          }
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            maxChildSize: 0.95,
            minChildSize: 0.4,
            // 方案 B：停靠点 + 缩到底不关窗（同上）。
            snap: true,
            snapSizes: const [0.75, 0.95],
            shouldCloseOnMinExtent: false,
            builder: (context, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '训练进行中',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                ),
                // 休息倒计时横幅（docs/21 §3）：环 + 最后 3 秒脉冲 + 结束轻震；
                // 常驻在记录弹层内而非全屏遮断——休息期间还要继续记组。
                if (_restEnd != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: RestCountdown(
                      restEnd: _restEnd!,
                      total: Duration(seconds: _restSeconds),
                    ),
                  ),
                if (session.planId != null)
                  _PlannedTargetsHeader(
                    planRepository: widget.planRepository,
                    planId: session.planId!,
                    weekday: weekdayOfLocalDate(session.localDate),
                  ),
                Expanded(
                  child: session.sets.isEmpty
                      ? const Center(child: Text('还没有记录任何组次。'))
                      : ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                          children: [
                            for (final set in session.sets)
                              ListTile(
                                key: Key('training-logged-set-${set.id}'),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Text('#${set.sortOrder + 1}'),
                                title: Text(
                                  '${set.exerciseName} ${set.weightKg}kg × ${set.reps} 次',
                                ),
                                subtitle: set.rpe == null
                                    ? null
                                    : Text('RPE ${set.rpe}'),
                              ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    children: [
                      LfConfirmButton(
                        key: const Key('training-set-log'),
                        icon: Icons.add,
                        label: '记录一组',
                        onPressed: () async {
                          await _openLogSetDialog(context, session);
                          _reloadSession();
                        },
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        // 次级（疼痛反馈）= §3.8 B3 muted 宽胶囊；主行动
                        // （结束训练）= B1 实心。设计语言里没有 outlined 档。
                        child: LfPillButton(
                          key: const Key('training-pain-report'),
                          label: '疼痛反馈',
                          icon: Icons.warning_amber_outlined,
                          tone: LfPillTone.muted,
                          onPressed: () => _openPainDialog(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: LfPrimaryButton(
                          key: const Key('training-session-finish'),
                          label: '结束训练',
                          expand: true,
                          onPressed: () => _confirmFinish(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openLogSetDialog(
    BuildContext context,
    WorkoutSessionRecord session,
  ) {
    final weekday = weekdayOfLocalDate(session.localDate);
    final optionsFuture = _exerciseOptions(session.planId, weekday);
    String? exerciseId;
    var weight = '';
    var reps = '';
    var rpe = '';
    var restSeconds = '';
    String? errorText;
    var saving = false;

    return AppSheet.showStateful<void>(
      context,
      title: '记录一组',
      bodyBuilder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) =>
            FutureBuilder<List<ExerciseRecord>>(
              future: optionsFuture,
              builder: (context, optionsSnapshot) {
                final options =
                    optionsSnapshot.data ?? const <ExerciseRecord>[];
                final loading =
                    optionsSnapshot.connectionState != ConnectionState.done;
                exerciseId ??= options.isEmpty ? null : options.first.id;
                final canRecord = !loading && options.isNotEmpty && !saving;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppFieldLabel(label: '动作'),
                    const SizedBox(height: LfDimens.spaceTiny),
                    LfSelectField<String>(
                      fieldKey: const Key('training-set-exercise'),
                      label: '动作',
                      value: exerciseId,
                      options: [for (final option in options) option.id],
                      enabled: canRecord,
                      optionLabel: (id) =>
                          options.firstWhere((option) => option.id == id).name,
                      onChanged: (value) =>
                          setDialogState(() => exerciseId = value),
                    ),
                    if (options.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: LfDimens.spaceSmall,
                        ),
                        child: Text(
                          loading
                              ? '正在读取可记录的动作…'
                              : optionsSnapshot.hasError
                              ? '动作读取失败，请取消后重试。'
                              : session.planId == null
                              ? '动作库中没有可记录的动作。可取消返回或结束训练。'
                              : '这次训练对应的计划日没有可记录的动作。可取消返回或结束训练。',
                          style: LfText.caption.copyWith(
                            color: context.lf.mutedForeground,
                          ),
                        ),
                      ),
                    AppNumberField(
                      fieldKey: const Key('training-set-weight'),
                      label: '重量',
                      unit: 'kg',
                      onChanged: (value) => weight = value,
                    ),
                    const SizedBox(height: 8),
                    AppNumberField(
                      fieldKey: const Key('training-set-reps'),
                      label: '次数',
                      unit: '次',
                      integerOnly: true,
                      onChanged: (value) => reps = value,
                    ),
                    const SizedBox(height: 8),
                    AppNumberField(
                      fieldKey: const Key('training-set-rpe'),
                      label: 'RPE',
                      unit: '1–10，可选',
                      onChanged: (value) => rpe = value,
                    ),
                    const SizedBox(height: 8),
                    AppNumberField(
                      fieldKey: const Key('training-set-rest'),
                      label: '休息',
                      unit: '秒，可选（默认 $_restSeconds）',
                      integerOnly: true,
                      onChanged: (value) => restSeconds = value,
                    ),
                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          errorText!,
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        LfTextButton(
                          label: '取消',
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                        LfConfirmButton(
                          key: const Key('training-set-save'),
                          label: '保存',
                          expand: false,
                          onPressed: !canRecord
                              ? null
                              : () async {
                                  // 防重复提交：logSet 为异步追加，连点两次会记录两组。
                                  if (saving) return;
                                  final parsedWeight = double.tryParse(
                                    weight.trim(),
                                  );
                                  final parsedReps = int.tryParse(reps.trim());
                                  final parsedRpe = rpe.trim().isEmpty
                                      ? null
                                      : double.tryParse(rpe.trim());
                                  if (exerciseId == null ||
                                      parsedWeight == null ||
                                      parsedReps == null) {
                                    setDialogState(
                                      () => errorText = '请选择动作并填写重量和次数。',
                                    );
                                    return;
                                  }
                                  // 休息是可选输入，但填了就必须能用：解析失败或超出
                                  // 合理区间时给提示，而不是悄悄退回默认值。
                                  final parsedRest = restSeconds.trim().isEmpty
                                      ? null
                                      : int.tryParse(restSeconds.trim());
                                  if (restSeconds.trim().isNotEmpty &&
                                      (parsedRest == null ||
                                          parsedRest < 10 ||
                                          parsedRest > 900)) {
                                    setDialogState(
                                      () => errorText =
                                          '休息时间请填 10–900 秒，或留空用默认值。',
                                    );
                                    return;
                                  }
                                  setDialogState(() => saving = true);
                                  try {
                                    await widget.sessionRepository.logSet(
                                      session.id,
                                      WorkoutSetDraft(
                                        exerciseId: exerciseId!,
                                        weightKg: parsedWeight,
                                        reps: parsedReps,
                                        rpe: parsedRpe,
                                      ),
                                    );
                                  } on FormatException catch (error) {
                                    if (!dialogContext.mounted) return;
                                    setDialogState(() {
                                      saving = false;
                                      errorText = error.message;
                                    });
                                    return;
                                  } on StateError catch (error) {
                                    if (!dialogContext.mounted) return;
                                    setDialogState(() {
                                      saving = false;
                                      errorText = error.message;
                                    });
                                    return;
                                  }
                                  if (!mounted) return;
                                  setState(() {
                                    if (parsedRest != null) {
                                      _restSeconds = parsedRest;
                                    }
                                    _restEnd = DateTime.now().add(
                                      Duration(seconds: _restSeconds),
                                    );
                                  });
                                  if (!dialogContext.mounted) return;
                                  Navigator.of(dialogContext).pop();
                                },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }

  Future<List<ExerciseRecord>> _exerciseOptions(
    String? planId,
    int? weekday,
  ) async {
    // 计划会话只认它存库日期对应的训练日。日期或计划日缺失时如实留空，
    // 不能悄悄换成其他星期或自由训练的动作。
    if (planId != null) {
      if (weekday == null) return const <ExerciseRecord>[];
      final plan = await widget.planRepository.getById(planId);
      final day = plan?.days
          .where((candidate) => candidate.weekday == weekday)
          .firstOrNull;
      if (day == null) return const <ExerciseRecord>[];
      return day.entries
          .map(
            (entry) => ExerciseRecord(
              id: entry.exerciseId,
              name: entry.exerciseName,
              equipment: entry.equipment,
              // 肌群信息不在计划条目快照中，仅作为下拉展示的占位值。
              muscleGroup: MuscleGroup.fullBody,
              // 难度/常用度同样不在快照里。这是下拉选项的占位记录，
              // 标成未标注，不编值。
              difficulty: null,
              popularity: null,
              isUserCreated: false,
              createdAt: DateTime.utc(0),
              updatedAt: DateTime.utc(0),
            ),
          )
          .toList(growable: false);
    }
    return widget.exerciseRepository.search('');
  }

  Future<void> _confirmFinish(BuildContext context) {
    return AppSheet.show<void>(
      context,
      title: '结束训练',
      content: const Text('结束后将生成训练总结，不能继续记录组次。'),
      actions: Builder(
        builder: (dialogContext) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(
              label: '取消',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            LfConfirmButton(
              key: const Key('training-session-finish-confirm'),
              label: '结束',
              expand: false,
              onPressed: () async {
                final active = await widget.sessionRepository.getActive();
                if (active != null) {
                  await widget.sessionRepository.finish(active.id);
                }
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                await _openSummaryDialog(context, active);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openSummaryDialog(
    BuildContext context,
    WorkoutSessionRecord? finished,
  ) async {
    if (finished == null) return;
    final all = await widget.sessionRepository.listAllFinished();
    final suggestions = const ProgressionAdvisor().advise(
      session: finished,
      previousSessions: [
        for (final candidate in all)
          if (candidate.id != finished.id) candidate,
      ],
    );
    if (!context.mounted) return;
    // docs/21 §2.9 庆祝时刻：完成训练→粒子爆发（每会话最多 1 次）+成功触觉。
    showAppCelebration(context);
    AppHaptics.success();
    await AppSheet.show<void>(
      context,
      title: '训练总结',
      content: Flexible(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '容量 ${finished.totalVolumeKg}kg · ${finished.completedSetCount} 组',
              ),
              const SizedBox(height: 8),
              for (final suggestion in suggestions) ...[
                Text('${suggestion.exerciseName}：${suggestion.message}'),
                const SizedBox(height: 4),
              ],
              const SizedBox(height: 8),
              const Text(
                '以上提示由本地规则生成，仅供参考，不构成医疗或专业训练建议。',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
      actions: Builder(
        builder: (dialogContext) => LfConfirmButton(
          key: const Key('training-summary-done'),
          label: '完成',
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _openPainDialog(BuildContext context) {
    return AppSheet.show<void>(
      context,
      title: '疼痛反馈',
      content: Builder(
        builder: (dialogContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('如训练中出现疼痛，请优先保证安全：'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: LfConfirmButton(
                key: const Key('training-pain-stop'),
                label: '停止训练',
                onPressed: () async {
                  final active = await widget.sessionRepository.getActive();
                  if (active != null) {
                    await widget.sessionRepository.finish(active.id);
                  }
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  Navigator.of(context).pop();
                },
              ),
            ),
            // 弹层内的次级选择 = §3.8 B6 文字按钮（弹层主行动已是上面的
            // B2「停止训练」）。两行文字入口比两个描边按钮更不抢安全动作。
            SizedBox(
              width: double.infinity,
              child: LfTextButton(
                label: '降低负荷',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: LfTextButton(
                label: '替换动作',
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ),
            const SizedBox(height: 12),
            const Text('疼痛持续或加重时请咨询专业人士；本应用不提供医疗建议。'),
          ],
        ),
      ),
    );
  }
}

final class _PlannedTargetsHeader extends StatelessWidget {
  const _PlannedTargetsHeader({
    required this.planRepository,
    required this.planId,
    required this.weekday,
  });

  final WorkoutPlanRepository planRepository;
  final String planId;

  /// 存库日期畸形时为 null——此时不显示「今日计划」，而不是让整页崩掉。
  final int? weekday;

  @override
  Widget build(BuildContext context) {
    final weekday = this.weekday;
    if (weekday == null) return const SizedBox.shrink();
    return FutureBuilder<WorkoutPlanRecord?>(
      future: planRepository.getById(planId),
      builder: (context, snapshot) {
        final plan = snapshot.data;
        final day = plan?.days
            .where((candidate) => candidate.weekday == weekday)
            .firstOrNull;
        if (day == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '今日计划：'
              '${day.entries.map((entry) => '${entry.exerciseName} ${entry.targetSets}×${entry.targetReps}').join('、')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        );
      },
    );
  }
}

String _dateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime _mondayOf(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  return local.subtract(Duration(days: local.weekday - 1));
}

final class _PlanCompletionLine extends StatelessWidget {
  const _PlanCompletionLine({
    required this.sessionRepository,
    required this.planId,
    required this.planWeekdays,
    required this.now,
  });

  final WorkoutSessionRepository sessionRepository;
  final String planId;
  final List<int> planWeekdays;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final today = now ?? DateTime.now();
    final weekStart = _mondayOf(today);
    final weekEnd = weekStart.add(const Duration(days: 6));
    return FutureBuilder<List<WorkoutSessionRecord>>(
      future: sessionRepository.listFinishedBetween(
        _dateOnly(weekStart),
        _dateOnly(weekEnd),
      ),
      builder: (context, snapshot) {
        final completion = const TrainingStatsCalculator().weeklyCompletion(
          planId: planId,
          planWeekdays: planWeekdays,
          weekStart: weekStart,
          today: today,
          finishedSessions: snapshot.data ?? const [],
        );
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            completion == null
                ? '本周暂无到期的计划训练日。'
                : '本周完成率 ${completion.completedDays}/${completion.scheduledDays}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }
}

/// 训练页分段（docs/21 §5.5 `SegmentedControl`：计划 / 历史）。
enum _TrainingSegment { plan, history }

/// 肌群 chips 的显示顺序（§5.5 设计稿：胸 / 背 / 肩 / 手臂 / 核心 / 腿）。
///
/// 与 [MuscleGroup] 的枚举顺序**不同**——枚举把腿排在第三，设计稿排在最后。
/// 界面顺序按设计稿走，不按枚举。
const _muscleDisplayOrder = <MuscleGroup>[
  MuscleGroup.chest,
  MuscleGroup.back,
  MuscleGroup.shoulders,
  MuscleGroup.arms,
  MuscleGroup.core,
  MuscleGroup.legs,
  MuscleGroup.fullBody,
];

/// 「训练回顾」弹层内容（Round7 逐页对账批次 4，A `app.js:559`）。
///
/// 只读：全部取值来自既有的 [WorkoutSessionRecord]（组数/日期/总容量由仓储
/// 派生），**新增零查询、零写入**。估算消耗一栏按本仓口径写「—」。
class _SessionReviewContent extends StatelessWidget {
  const _SessionReviewContent({
    required this.session,
    required this.planName,
    required this.durationLabel,
  });

  final WorkoutSessionRecord session;
  final String planName;
  final String durationLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      key: const Key('training-review-sheet'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // A `.detail-energy`：组数大字 + 说明。
        Text(
          '${session.completedSetCount}',
          key: const Key('training-review-sets'),
          textAlign: TextAlign.center,
          style: LfText.displayHero.copyWith(color: c.cardForeground),
        ),
        Text(
          '已完成组数',
          textAlign: TextAlign.center,
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Text(
          planName,
          textAlign: TextAlign.center,
          style: LfText.headline.copyWith(color: c.cardForeground),
        ),
        const SizedBox(height: LfDimens.spaceLarge),
        _ReviewRow(
          label: '训练日期',
          value: session.localDate,
          valueKey: const Key('training-review-date'),
        ),
        _ReviewRow(
          label: '训练时长',
          value: durationLabel,
          valueKey: const Key('training-review-duration'),
        ),
        _ReviewRow(
          label: '总容量',
          value: '${session.totalVolumeKg.toStringAsFixed(1)} kg',
          valueKey: const Key('training-review-volume'),
        ),
        // 本库不记录训练消耗估算 ⇒ 如实写「—」（docs/21 §5.5 的同一口径）。
        _ReviewRow(
          label: '估算消耗',
          value: '—',
          valueKey: const Key('training-review-kcal'),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        Text(
          '训练消耗估算不在本地记录范围内，这里不虚构数值。',
          style: LfText.micro.copyWith(color: c.mutedForeground),
        ),
      ],
    );
  }
}

/// 回顾弹层的一行：左标签（muted）+ 右值（卡面前景色）。
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceSmall),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          Text(
            value,
            key: valueKey,
            style: LfText.bodyStrong.copyWith(color: c.cardForeground),
          ),
        ],
      ),
    );
  }
}

/// 计划卡的数据：一个 `WorkoutDays` 行 = 一张卡。
final class _PlanCardData {
  const _PlanCardData({
    required this.plan,
    required this.day,
    required this.dayCount,
    required this.planWeekdays,
  });

  final WorkoutPlanSummary plan;
  final WorkoutPlanDayRecord day;

  /// 同一计划下的训练日数量（> 1 时卡片标题补星期，免得两张卡同名）。
  final int dayCount;

  /// **这份计划**编排了动作的星期集合（1=周一…7=周日）。
  ///
  /// 与休息日图例同一口径：有 `PlannedExercises` 才算训练日（§6.2 裁决 4）；
  /// Round7 逐页对账批次 3 起，卡面的周安排日签行读它（A `.plan-days`）。
  final Set<int> planWeekdays;
}

/// 训练页一次构建需要的全部派生值（docs/21 §5.5「数据来源」）。
///
/// 全部由既有表派生，不新建表、不写库——本类是只读视图。
final class _TrainingSnapshot {
  const _TrainingSnapshot({
    required this.planCards,
    required this.weekIndex,
    required this.finishedCount,
    required this.totalDuration,
    required this.weekVolumeKg,
    required this.capacityMinutes,
    required this.weekRows,
    required this.restWeekdays,
    required this.active,
    required this.activeName,
    required this.activePlannedSets,
    required this.history,
    required this.planNames,
    required this.muscleByExerciseId,
  });

  /// 展平后的计划卡（跨计划，按「计划创建时间倒序 × 周内升序」）。
  final List<_PlanCardData> planCards;

  /// 「第 N 周」。null = 还没有任何已结束训练。
  final int? weekIndex;
  final int finishedCount;
  final Duration totalDuration;

  /// 本周容量（kg），来自 `TrainingStats.weeklyVolumeKg`。
  final double weekVolumeKg;

  /// 周一到周日的训练分钟数（7 项，容量图的真值——不是组数）。
  final List<int> capacityMinutes;

  /// 本周分肌群统计行。
  final List<({String label, String value})> weekRows;

  /// 计划里没有动作编排的星期（1..7）。空 = 无计划，不渲染图例。
  final List<int> restWeekdays;

  final WorkoutSessionRecord? active;
  final String activeName;
  final int? activePlannedSets;

  /// 已结束训练，**新的在前**。
  final List<WorkoutSessionRecord> history;

  final Map<String, String> planNames;
  final Map<String, MuscleGroup> muscleByExerciseId;

  String? planNameOf(String? planId) =>
      planId == null ? null : planNames[planId];

  /// 一组动作行的肌群文字（「胸 · 背 · 肩」）。算不出肌群的动作不参与，
  /// 也不为凑数编一个——全算不出时返回空串，卡片不渲染这一行。
  String muscleLabelsOf(List<PlannedExerciseRecord> entries) {
    final groups = <MuscleGroup>[];
    for (final entry in entries) {
      final group = muscleByExerciseId[entry.exerciseId];
      if (group != null && !groups.contains(group)) groups.add(group);
    }
    groups.sort(
      (a, b) => _muscleDisplayOrder
          .indexOf(a)
          .compareTo(_muscleDisplayOrder.indexOf(b)),
    );
    return groups.map((group) => group.label).join(' · ');
  }
}

/// 分段控件（设计稿 `bg-[var(--lf-muted)] rounded-full p-1` + 选中白胶囊）。
final class _TrainingSegmentRow extends StatelessWidget {
  const _TrainingSegmentRow({required this.segment, required this.onChanged});

  final _TrainingSegment segment;
  final ValueChanged<_TrainingSegment> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LfDimens.pagePadding,
        LfDimens.spaceLarge,
        LfDimens.pagePadding,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(LfDimens.spaceMicro),
        decoration: BoxDecoration(
          color: c.muted,
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
        ),
        child: Row(
          children: [
            _SegmentPill(
              pillKey: const Key('training-segment-plan'),
              label: '我的计划',
              selected: segment == _TrainingSegment.plan,
              onTap: () => onChanged(_TrainingSegment.plan),
            ),
            _SegmentPill(
              pillKey: const Key('training-segment-history'),
              label: '训练历史',
              selected: segment == _TrainingSegment.history,
              onTap: () => onChanged(_TrainingSegment.history),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SegmentPill extends StatelessWidget {
  const _SegmentPill({
    required this.pillKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key pillKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? c.card : Colors.transparent,
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
          child: InkWell(
            key: pillKey,
            borderRadius: BorderRadius.circular(LfDimens.radiusFull),
            onTap: onTap,
            child: SizedBox(
              // 设计稿胶囊视觉高约 32；§5.8.3 要求 44dp 触达，直接按 44 给
              // 命中区（比「视觉 32 + 外层补命中」简单，也不会出现
              // 「看得见点不到」）。
              height: LfDimens.minTouchTarget,
              child: Center(
                child: Text(
                  label,
                  style: (selected ? LfText.captionStrong : LfText.caption)
                      .copyWith(
                        color: selected ? c.foreground : c.mutedForeground,
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 肌群 chips 行（设计稿 `<span>` 行：全部 / 胸 / 背 / 肩 / 手臂 / 核心 / 腿）。
///
/// 选中态是 **primary 实心胶囊白字**（设计稿
/// `bg-[var(--lf-primary)] text-white rounded-full px-3 py-1 text-xs`），
/// 与饮食页 sub-tab 胶囊行同一套写法。
final class _TrainingMuscleChipRow extends StatelessWidget {
  const _TrainingMuscleChipRow({
    required this.selected,
    required this.onChanged,
  });

  final MuscleGroup? selected;
  final ValueChanged<MuscleGroup?> onChanged;

  /// 行高（chip 视觉高 30 + 上下各 12）。与饮食页胶囊行同值。
  static const double barHeight = 54;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: barHeight,
      child: ListView(
        key: const Key('training-muscle-chips'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: LfDimens.pagePadding,
          vertical: LfDimens.spaceMedium,
        ),
        children: [
          _MuscleChip(
            chipKey: const Key('training-muscle-all'),
            label: '全部',
            selected: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final group in _muscleDisplayOrder)
            _MuscleChip(
              chipKey: Key('training-muscle-${group.name}'),
              label: group.label,
              selected: selected == group,
              onTap: () => onChanged(group),
            ),
        ],
      ),
    );
  }
}

final class _MuscleChip extends StatelessWidget {
  const _MuscleChip({
    required this.chipKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key chipKey;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.only(right: LfDimens.spaceSmall),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? c.primary : c.muted,
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
          child: InkWell(
            key: chipKey,
            borderRadius: BorderRadius.circular(LfDimens.radiusFull),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LfDimens.spaceLarge,
                vertical: LfDimens.spaceTiny,
              ),
              child: Text(
                label,
                style: (selected ? LfText.captionStrong : LfText.caption)
                    .copyWith(
                      color: selected ? c.primaryForeground : c.mutedForeground,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 新建计划的两条路（docs/30 §2 D7）。
enum PlanCreationMode {
  /// AI 生成：走 `/workout-plan-create`（表单 → 披露 → 生成 → 预览）。
  ai,

  /// 手动创建：走 `/workout-plan-manual`（完整表单，只依赖动作库 + 计划仓储）。
  manual,
}

/// 模式选择弹层内容（docs/30 §2 D7）。
///
/// **两行是同级的两个动作**，不是「主 + 次」：左图标 + 标题 + 一句说明 + 右
/// 箭头。这正是 `AppSheet` 的既有形态（标题 + 内容 + 无底部按钮，点行即走）。
///
/// **AI 行禁用但可见**：未配置 AI 时它留着并写明「未配置 AI（我的 → AI 模型）」
/// ——用户由此知道产品有这条能力、知道去哪打开、不会以为「AI 行不见了」是 bug。
/// 这与全仓「可选能力缺失时如实说明、不静默隐藏」的口径一致（对比：设置页的
/// AI 组未配置时显示「未配置」而不是整组消失）。
final class _PlanModeSheet extends StatelessWidget {
  const _PlanModeSheet({required this.aiReady, required this.onSelected});

  /// AI 四项依赖是否齐全（`exerciseRepository` / `workoutPlanRepository` /
  /// `workoutPlanProvider` / `loadWorkoutPlanDisclosure`）。
  final bool aiReady;
  final ValueChanged<PlanCreationMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PlanModeRow(
          rowKey: const Key('plan-mode-ai'),
          icon: Icons.auto_awesome_outlined,
          title: 'AI 生成',
          // 上限是这条说明；允许换行，不做省略号（「说明」被截掉半句比不显示
          // 更糟——同 `SettingRow.subtitle` 的口径）。
          description: aiReady
              ? '说清目标与每周练几天，AI 排好每天的动作与组次'
              : '未配置 AI（我的 → AI 模型）。配好后这里就能用。',
          badge: aiReady ? const LfBadge.mint('推荐') : const LfBadge('未配置'),
          enabled: aiReady,
          onTap: () => onSelected(PlanCreationMode.ai),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        _PlanModeRow(
          rowKey: const Key('plan-mode-manual'),
          icon: Icons.edit_outlined,
          title: '手动创建',
          // 手动行**两态下都可用**：它只需要动作库 + 计划仓储（训练页本身就在
          // 用这两个仓），AI 配没配都不影响。
          description: '自己挑动作、填组次，按周一到周日安排',
          badge: null,
          enabled: true,
          onTap: () => onSelected(PlanCreationMode.manual),
        ),
      ],
    );
  }
}

/// 模式弹层里的一行（DesignCard 形态：左图标方块 + 标题/说明 + 徽标 + 箭头）。
final class _PlanModeRow extends StatelessWidget {
  const _PlanModeRow({
    required this.rowKey,
    required this.icon,
    required this.title,
    required this.description,
    required this.badge,
    required this.enabled,
    required this.onTap,
  });

  final Key rowKey;
  final IconData icon;
  final String title;
  final String description;
  final Widget? badge;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final mint = LfColors.mint(brightness);
    // 禁用态整行降对比（标题与说明都退到 muted），但**文案照读**——用户要
    // 从那句话里知道「去哪打开」。
    final titleColor = enabled ? c.cardForeground : c.mutedForeground;
    final descColor = enabled ? c.mutedForeground : c.mutedForeground;
    return DesignCard(
      key: rowKey,
      // 禁用时不给 onTap：DesignCard 的可点态会画水波并按按钮语义朗读，
      // 一个点不动却说自己可点的行比一个明确的禁用行更糟。
      onTap: enabled ? onTap : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? mint.tone(100) : c.muted,
              borderRadius: BorderRadius.circular(LfDimens.radiusMd),
            ),
            child: Icon(
              icon,
              size: LfDimens.iconMd,
              color: enabled
                  ? LfColors.mintText(brightness)
                  : c.mutedForeground,
            ),
          ),
          const SizedBox(width: LfDimens.spaceMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: LfText.bodyStrong.copyWith(color: titleColor),
                      ),
                    ),
                    ?badge,
                  ],
                ),
                const SizedBox(height: LfDimens.spaceMicro),
                Text(
                  description,
                  style: LfText.caption.copyWith(color: descColor),
                ),
              ],
            ),
          ),
          if (enabled) ...[
            const SizedBox(width: LfDimens.spaceSmall),
            Icon(
              Icons.chevron_right,
              size: LfDimens.iconMd,
              color: c.mutedForeground,
            ),
          ],
        ],
      ),
    );
  }
}

/// 二级入口行（docs/22 裁决 ②）：设计稿没画的功能，各自只占一行。
///
/// `subtitle` 是 Round7 A 的 list-link 形态（`app.js:216` 的「动作库」两行：
/// 标题 + 一行说明）——只有 A 画了副题的行才传，其余行保持单行。
final class _SecondaryEntry extends StatelessWidget {
  const _SecondaryEntry({
    required this.entryKey,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final Key entryKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LfDimens.pagePadding,
        0,
        LfDimens.pagePadding,
        LfDimens.spaceSmallPlus,
      ),
      child: DesignCard(
        key: entryKey,
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: LfDimens.iconMd, color: c.primary),
            const SizedBox(width: LfDimens.spaceMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: LfText.body.copyWith(color: c.cardForeground),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: LfDimens.iconMd,
              color: c.mutedForeground,
            ),
          ],
        ),
      ),
    );
  }
}

/// 列表行首 36dp 浅底圆图标（docs/21 §3.3）。
///
/// 动作库网格与训练统计底层各有一处使用者，两页都在本文件之外/之内共用
/// 同一个形状——不复制第二份。
final class _LeadingBadge extends StatelessWidget {
  const _LeadingBadge({
    required this.icon,
    required this.tint,
    required this.foreground,
  });

  final IconData icon;
  final Color tint;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
    child: Icon(icon, size: 20, color: foreground),
  );
}

/// 个人纪录弹层内容（docs/32 §4 T5）。
///
/// `future` 在 `initState` 建一次：弹层内容会因把手拖动而起止重建，
/// 若 future 建在 build 内，每次重建都会重新查询（`food_detail_sheet` 的
/// 同一个缺陷形态）。
final class _PersonalRecordsSheet extends StatefulWidget {
  const _PersonalRecordsSheet({required this.sessionRepository});

  final WorkoutSessionRepository sessionRepository;

  @override
  State<_PersonalRecordsSheet> createState() => _PersonalRecordsSheetState();
}

final class _PersonalRecordsSheetState extends State<_PersonalRecordsSheet> {
  late final Future<List<WorkoutSessionRecord>> _records = widget
      .sessionRepository
      .listAllFinished();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkoutSessionRecord>>(
      future: _records,
      builder: (context, snapshot) {
        final records = const TrainingStatsCalculator().personalRecords(
          snapshot.data ?? const [],
        );
        return ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: LfDimens.spaceLarge),
          children: [
            Text('个人纪录', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('按已结束训练中的最重组次记录；同重量取次数更多的一次。'),
            if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('还没有可统计的已完成训练。'),
              )
            else
              for (final record in records)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${record.exerciseName} ${record.weightKg}kg × ${record.reps} 次',
                  ),
                  subtitle: Text(
                    '达成于 ${_dateOnly(record.achievedAt.toLocal())}',
                  ),
                ),
          ],
        );
      },
    );
  }
}
