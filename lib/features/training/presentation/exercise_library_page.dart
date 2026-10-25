import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_insets.dart';
import 'package:localfit_ai/app/design/widgets/app_morph_chip.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/entrance_item.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_empty_state.dart';
import 'package:localfit_ai/app/design/widgets/lf_scrollbar.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/app/design/widgets/pressable_scale.dart';
import 'package:localfit_ai/app/design/widgets/skeleton_box.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/domain/exercise_record.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';

/// 动作库二级页（docs/22 裁决 ②）。
///
/// 设计稿 `训练.html` 只画了 hero / 进行中横幅 / 分段 / 肌群 chips / 周统计 /
/// 计划卡 / FAB——**动作库不在其中**。按裁决 ②「HTML 未画到的现有功能保留
/// 数据与逻辑、收进二级入口」，它整页搬到这里：搜索、肌群筛选、网格、自建
/// 动作、同肌群替代详情，一件不少，键名也全部沿用（`training-exercise-*`、
/// `training-muscle-filter-*`），只是入口从「训练页的一个分段」变成「训练页
/// 底部的紧凑入口」。
///
/// 这一页的视觉形态在 docs/29 §P5 统一到新视觉：卡片分类串移到右上角、
/// 去掉把行高撑到 168 的垂直 `Spacer`、替代动作改成可点的行卡（此前是裸
/// `ListTile`），并把手写 `showModalBottomSheet` 换成 `AppSheet`（动效统一到
/// [AppMotion] 令牌）。行高按实测内容高重算（见 [_ExerciseLibraryGrid]）。
class ExerciseLibraryPage extends StatefulWidget {
  const ExerciseLibraryPage({super.key, required this.repository});

  final ExerciseRepository repository;

  /// 搜索防抖（docs/29 §P5 需求 11）：输入停顿这么久才查库。
  ///
  /// 公开给测试用：`pumpAndSettle` 不会跨过「还没到点的 Timer」推进时钟，
  /// 测试要显式 `pump(searchDebounce)` 才能让防抖到期。
  static const searchDebounce = Duration(milliseconds: 300);

  @override
  State<ExerciseLibraryPage> createState() => _ExerciseLibraryPageState();
}

final class _ExerciseLibraryPageState extends State<ExerciseLibraryPage> {
  String _query = '';

  /// 已提交给仓储的查询串（防抖后），与 [_query] 分离：键盘每敲一个字符
  /// 只更新 [_query]，不触发查库。
  String _committedQuery = '';

  /// 肌群筛选。null＝全部。
  MuscleGroup? _muscleFilter;

  /// 查询结果 future **由 state 持有**（docs/29 §P5 需求 11 真凶）：
  /// 原先它建在 `_ExerciseLibraryGrid.build` 里，于是任何重建（搜索框聚焦
  /// 引发键盘 inset 变化、字号变化、主题切换）都会重新发一次 DB 查询并
  /// 回到骨架屏——看起来就是「弹窗/输入不丝滑」。
  late Future<List<ExerciseRecord>> _results;

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _results = _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<ExerciseRecord>> _search() =>
      widget.repository.search(_committedQuery, muscleGroup: _muscleFilter);

  /// 立刻提交当前输入并重查（肌群 chip 走这条：筛选是离散动作，不该等防抖）。
  void _commitQueryNow() {
    _debounce?.cancel();
    _committedQuery = _query;
    _results = _search();
  }

  void _onSearchChanged(String value) {
    _query = value;
    setState(() {}); // 只更新输入框回显，不触碰 future
    _debounce?.cancel();
    _debounce = Timer(ExerciseLibraryPage.searchDebounce, () {
      if (!mounted) return;
      setState(_commitQueryNow);
    });
  }

  Future<void> _openExerciseDetail(ExerciseRecord exercise) {
    var current = exercise;
    var alternatives = widget.repository.listAlternatives(current.id);
    return AppSheet.showCustom<void>(
      context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => _ExerciseDetailSheet(
          current: current,
          alternatives: alternatives,
          // 点替代动作 = 抽屉内容**原地**换成该动作（不叠层、不关窗）。
          onSelect: (selected) => setSheetState(() {
            current = selected;
            alternatives = widget.repository.listAlternatives(selected.id);
          }),
        ),
      ),
    );
  }

  Future<void> _openCreateExerciseDialog() => showCreateExerciseSheet(
    context,
    repository: widget.repository,
    onSaved: () => setState(() {}),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: LfTopBar(
        title: '动作库',
        backKey: const Key('training-exercise-library-back'),
        actions: [
          LfCircleIconButton(
            key: const Key('training-exercise-add'),
            icon: Icons.add,
            tooltip: '新建动作',
            onPressed: _openCreateExerciseDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LfDimens.pagePadding,
              LfDimens.spaceSmall,
              LfDimens.pagePadding,
              LfDimens.spaceMicro,
            ),
            child: TextField(
              key: const Key('training-exercise-search'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索动作 / 肌群',
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              key: const Key('training-muscle-filter'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                LfDimens.pagePadding,
                LfDimens.spaceMicro,
                LfDimens.pagePadding,
                LfDimens.spaceMicro,
              ),
              children: [
                _MuscleFilterChip(
                  label: '全部',
                  selected: _muscleFilter == null,
                  onSelected: () => setState(() {
                    _muscleFilter = null;
                    _commitQueryNow();
                  }),
                ),
                for (final group in MuscleGroup.values)
                  _MuscleFilterChip(
                    label: group.label,
                    selected: _muscleFilter == group,
                    onSelected: () => setState(() {
                      _muscleFilter = group;
                      _commitQueryNow();
                    }),
                  ),
              ],
            ),
          ),
          // 结果计数（Round7 逐页对账批次 2：A `app.js:225` 的
          // `.library-result-count`「N 个动作」）。**加载中/失败不画数字**
          // （不能把「还没读到」说成 0）；有数据时 0 也照画（同食物库
          // D32「0 种食物也画」的口径）。位置固定在列表之上而非流内：本页是
          // 312 条的分页网格，计数滚走就没人看得见（与 D32 的位置裁决同向）。
          FutureBuilder<List<ExerciseRecord>>(
            future: _results,
            builder: (context, snapshot) {
              final records = snapshot.data;
              if (records == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  LfDimens.pagePadding,
                  LfDimens.spaceSmall,
                  LfDimens.pagePadding,
                  LfDimens.spaceMicro,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${records.length} 个动作',
                    key: const Key('exercise-result-count'),
                    style: LfText.label.copyWith(
                      color: context.lf.mutedForeground,
                    ),
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: _ExerciseLibraryGrid(
              results: _results,
              queryKey: '$_committedQuery|${_muscleFilter?.name ?? ''}',
              onExerciseTap: _openExerciseDetail,
            ),
          ),
        ],
      ),
    );
  }
}

/// 肌群筛选 chip（docs/21 §5.5「支持分类筛选」）。
final class _MuscleFilterChip extends StatelessWidget {
  const _MuscleFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: LfDimens.spaceMedium),
    child: AppMorphChip(
      key: Key('training-muscle-filter-$label'),
      label: label,
      selected: selected,
      onSelected: (_) => onSelected(),
    ),
  );
}

/// 动作库网格：名称 / 肌群 / 难度 / 常用度。
///
/// `future` 由父级 state 持有并传入（docs/29 §P5 需求 11）：本件只消费
/// [results]，重建不再产生新的 DB 查询。[queryKey] 用于在**查询真的变化**
/// 时让结果区的入场动画/滚动位置按新结果重建，键盘 inset 变化不会改它。
final class _ExerciseLibraryGrid extends StatelessWidget {
  const _ExerciseLibraryGrid({
    required this.results,
    required this.queryKey,
    required this.onExerciseTap,
  });

  final Future<List<ExerciseRecord>> results;
  final String queryKey;
  final void Function(ExerciseRecord) onExerciseTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ExerciseRecord>>(
      future: results,
      builder: (context, snapshot) {
        final records = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SkeletonCardList(
            count: 6,
            cardBuilder: (context) => const _ListTileSkeletonCard(),
          );
        }
        if (records == null || records.isEmpty) {
          return const LfEmptyState(
            icon: Icons.search_off,
            title: '没有匹配的本地动作。',
            message: '换个关键词，或新建一个自定义动作。',
          );
        }
        // 动作库也挂常显滑条（docs/28 §8.3）：约 300 条一屏看不完，
        // 用户要能看见「还有多少」并一把拖到目标肌群。
        return LfScrollbar(
          // 换查询词 ⇒ 换一份结果，滚动回到顶部（沿用旧 offset 会落在
          // 新列表中部）。字体缩放/键盘 inset 等重建不改 key，位置保持。
          key: ValueKey('exercise-grid-$queryKey'),
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(
              LfDimens.pagePadding,
              4,
              LfDimens.pagePadding,
              // 本页是**被推入的二级页**，但它挂在 shell 分支的 Navigator 上，
              // 底部仍是那条 `extendBody` 浮起的贴底栏（0-7 走查实测：栏体顶边
              // 在 y=2000，最后一格 2254~2340 全被吃掉且无法再滚）。末尾按
              // docs/21 §5.8.4 留出栏高 + 上凸 + 手势带。
              LfDimens.spaceLarge + LfInsets.navReserve(context),
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: LfDimens.spaceMedium,
              crossAxisSpacing: LfDimens.spaceMedium,
              // 卡内构成（docs/29 §P5 卡片，卡内 padding 12）：
              // 图标行 + 8 + 名称 + 6 + 标签行，行高 = **实测内容高 + 12**。
              // 1.0×/360dp 实测内容 112（36+8+21+6+17+24 内边距）⇒ 行高 124.2；
              // 旧值 168 是由 Spacer 空洞撑出来的虚高。
              mainAxisExtent: _cardExtent(context),
            ),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final exercise = records[index];
              return EntranceItem(
                index: index,
                child: _ExerciseGridTile(
                  exercise: exercise,
                  onTap: () => onExerciseTap(exercise),
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// 卡片行高：**实测内容高 + 12**（docs/29 §P5「先量后改」）。
  ///
  /// 1.0× 实测（`tmp/p5-measure`，2026-10-06）：卡内 36+8+21+6+17 = 88，
  /// 加卡内内边距 24 ⇒ 内容 112；320dp 窄屏标签行折两行 ⇒ 101+24 = 125。
  /// 基准取 360dp 的 112 + 12 = **124**（旧值 168 是 Spacer 空洞撑出的虚高，
  /// 320dp 的 125 由「标签行最多两行」的既有取舍兜住——Grid 允许 child 比
  /// 格子高，真溢出才会报 RenderFlex）。
  ///
  /// 字号放大时文字块（名称 + 标签行）随 `textScaler` 放大，图标行 36 与
  /// 两处间距、标签的内边距不随字号变。系数用 `scale(14)/14`（Android 非线性
  /// 字号下 `scale(1)` 不反映正文档的实际放大；`text_fit.dart` 同一口径）。
  ///
  /// 实测复核（tmp/p5-measure，1.0×/2.0× × 320/360dp）：公式 124.2/158.4，
  /// 实际内容 112/146，均为 +12 行距，无 RenderFlex 溢出。
  static double _cardExtent(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return exerciseCardExtent(
      bodyScale: scaler.scale(14) / 14,
      tagScale: scaler.scale(11) / 11,
    );
  }

  /// 器械标签配色（docs/21 §3.5：浅底 + `{色}-100` 档，文字用前景色；
  /// 只有薄荷用文字级绿）。
  static (Color, Color) _equipmentColors(
    BuildContext context,
    Equipment equipment,
  ) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    return switch (equipment) {
      Equipment.barbell => (
        mint.tone(100),
        LfColors.mintText(Theme.of(context).brightness),
      ),
      Equipment.dumbbell => (c.protein100, c.foreground),
      Equipment.machine => (c.carbs100, c.foreground),
      Equipment.cable => (c.fat100, c.foreground),
      Equipment.bodyweight || Equipment.other => (c.water, c.info),
    };
  }
}

/// 网格单格（名称 / 肌群 / 难度 / 常用度）。
final class _ExerciseGridTile extends StatelessWidget {
  const _ExerciseGridTile({required this.exercise, required this.onTap});

  final ExerciseRecord exercise;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (tint, foreground) = _ExerciseLibraryGrid._equipmentColors(
      context,
      exercise.equipment,
    );
    final difficulty = exercise.difficulty;
    final muscleIcon = _muscleIcon(exercise.muscleGroup);
    return PressableScale(
      // 卡片走 `DesignCard`（§2.3）：裸 `Card` 的 M3 默认 elevation /
      // surfaceTint 与主题的「1px 描边 + shadow-1 + 16 圆角」不是一套；
      // 整格可点由 `DesignCard.onTap` 承担（原先是卡内自绘 InkWell）。
      child: DesignCard(
        key: Key('training-exercise-${exercise.id}'),
        onTap: onTap,
        padding: const EdgeInsets.all(LfDimens.spaceMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图标行：图标（左）+ 分类串（右，docs/29 §P5 需求 9）。
            // 原先分类串在名称下方独占一行、左上角图标与右端之间还夹一个
            // 把高度撑到 168 的垂直 Spacer。现在分类串与本行同排、自建图标
            // 固定在分类串左侧（行内两端对齐，名称仍占满整行）。
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: 36),
              child: Row(
                children: [
                  _LeadingBadge(
                    icon: muscleIcon,
                    tint: tint,
                    foreground: foreground,
                  ),
                  const SizedBox(width: LfDimens.spaceSmall),
                  Expanded(
                    child: Text(
                      '${exercise.muscleGroup.label} · ${exercise.equipment.label}',
                      // 分类串与图标同行且右对齐；自建徽标固定在它左侧。
                      textAlign: TextAlign.right,
                      style: LfText.bodySmall.copyWith(
                        color: context.lf.mutedForeground,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (exercise.isUserCreated) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: context.lf.mutedForeground,
                    ),
                  ],
                ],
              ),
            ),
            // 图标 ↔ 标题显式 8dp（原来由 Spacer 撑开 ≈35.6dp）。
            const SizedBox(height: LfDimens.spaceSmall),
            // 名称按**一行**给高度：两行会把格子撑到需要 190+ 的
            // 行高，而 320dp 两列布局给不了。完整名字在详情弹层里
            // 始终可见，所以这里省略号是可接受的取舍。
            Text(
              exercise.name,
              style: LfText.body.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            // 标题 ↔ 标签行 6dp（原来是 12 + 分类行 18.2 + 4 ≈ 34dp）。
            const SizedBox(height: LfDimens.spaceTiny),
            // 难度 / 常用度：两枚小标签**一行放不下就只留难度**。
            // 320dp 窄屏 + 两枚标签换行会挤爆固定行高的格子
            // （narrow_layout_audit 实测溢出 7px），所以这里用 Row 而非
            // Wrap：常用度是可选的附加信息，截断它比撑破布局合理。
            Row(
              children: [
                _MiniTag(
                  label: difficulty?.label ?? '难度未知',
                  color: switch (difficulty) {
                    ExerciseDifficulty.beginner => context.lf.success,
                    ExerciseDifficulty.intermediate => context.lf.warningText,
                    ExerciseDifficulty.advanced => context.lf.errorText,
                    null => context.lf.mutedForeground,
                  },
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: _MiniTag(
                    label: exercise.popularity == null
                        ? '常用度未知'
                        : '常用度 ${exercise.popularity}',
                    color: context.lf.mutedForeground,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static IconData _muscleIcon(MuscleGroup group) => switch (group) {
    MuscleGroup.chest => Icons.fitness_center_outlined,
    MuscleGroup.back => Icons.self_improvement_outlined,
    MuscleGroup.shoulders => Icons.accessibility_new_outlined,
    MuscleGroup.arms => Icons.pan_tool_alt_outlined,
    MuscleGroup.core => Icons.heart_broken_outlined,
    MuscleGroup.legs => Icons.directions_walk_outlined,
    MuscleGroup.fullBody => Icons.auto_awesome_outlined,
  };
}

/// 网格内的极小标签（4dp 内边距，11 号字）。
final class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(LfDimens.radiusFull),
    ),
    child: Text(
      label,
      // 单行省略：两行会把固定行高的格子撑爆（2.0× 实测溢出 71px）。
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 11,
        height: 1.2,
        color: color,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// 列表行首 36dp 浅底圆图标（docs/21 §3.3）。
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

/// 详情抽屉主体（docs/29 §P5 需求 8）。
///
/// 替代动作从裸 `ListTile` 升级为「图标圆 + 名称 + 器械/难度 chip」的行卡，
/// **整行可点**：点它把抽屉内容原地换成该动作的详情（不叠层、不关窗），
/// 用户因此能在同肌群动作之间连续跳。
///
/// 加载中有独立分支（骨架行）：此前 `ConnectionState.waiting` 与「空结果」
/// 混在同一支，加载中先闪一句「暂无同肌群的本地替代动作」再跳成列表。
final class _ExerciseDetailSheet extends StatelessWidget {
  const _ExerciseDetailSheet({
    required this.current,
    required this.alternatives,
    required this.onSelect,
  });

  final ExerciseRecord current;
  final Future<List<ExerciseRecord>> alternatives;
  final void Function(ExerciseRecord) onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(0, 0, 0, LfDimens.spaceLargePlus),
      children: [
        Text(current.name, style: LfText.titleLarge),
        const SizedBox(height: 4),
        Text(
          '${current.muscleGroup.label} · ${current.equipment.label}',
          style: LfText.bodySmall.copyWith(color: context.lf.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceLarge),
        Text('同肌群替代动作', style: LfText.bodyStrong),
        const SizedBox(height: LfDimens.spaceSmall),
        FutureBuilder<List<ExerciseRecord>>(
          future: alternatives,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Column(
                children: [
                  _AlternativeSkeletonRow(),
                  SizedBox(height: LfDimens.spaceSmall),
                  _AlternativeSkeletonRow(),
                  SizedBox(height: LfDimens.spaceSmall),
                  _AlternativeSkeletonRow(),
                ],
              );
            }
            final records = snapshot.data ?? const <ExerciseRecord>[];
            if (records.isEmpty) {
              return Text(
                '暂无同肌群的本地替代动作。',
                style: LfText.bodySmall.copyWith(
                  color: context.lf.mutedForeground,
                ),
              );
            }
            return Column(
              children: [
                for (final alternative in records) ...[
                  _AlternativeRow(
                    exercise: alternative,
                    onTap: () => onSelect(alternative),
                  ),
                  const SizedBox(height: LfDimens.spaceSmall),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// 替代动作行卡（图标圆 + 名称 + 器械/难度 chip + 右侧箭头）。
final class _AlternativeRow extends StatelessWidget {
  const _AlternativeRow({required this.exercise, required this.onTap});

  final ExerciseRecord exercise;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (tint, foreground) = _ExerciseLibraryGrid._equipmentColors(
      context,
      exercise.equipment,
    );
    final difficulty = exercise.difficulty;
    return Material(
      color: context.lf.card,
      borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      child: InkWell(
        // 刻意不复用 `training-exercise-` 前缀：那个命名空间被
        // `training_muscle_filter_test.visibleExerciseIds` 当作「网格里
        // 渲染了哪些动作 id」逐条反查仓储，行卡混进去会让它把
        // `alternative-xxx` 当动作 id。
        key: Key('exercise-alternative-${exercise.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(LfDimens.radiusMd),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LfDimens.radiusMd),
            border: Border.all(color: context.lf.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: LfDimens.spaceSmallPlus,
              vertical: LfDimens.spaceSmall,
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _ExerciseGridTile._muscleIcon(exercise.muscleGroup),
                    size: 18,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: LfDimens.spaceSmallPlus),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: LfText.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _MiniTag(
                            label: difficulty?.label ?? '难度未知',
                            color: switch (difficulty) {
                              ExerciseDifficulty.beginner => context.lf.success,
                              ExerciseDifficulty.intermediate =>
                                context.lf.warningText,
                              ExerciseDifficulty.advanced =>
                                context.lf.errorText,
                              null => context.lf.mutedForeground,
                            },
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: _MiniTag(
                              label: exercise.isUserCreated
                                  ? '自建 · ${exercise.equipment.label}'
                                  : exercise.equipment.label,
                              color: exercise.isUserCreated
                                  ? context.lf.primary
                                  : context.lf.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: context.lf.mutedForeground,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 替代动作加载中的骨架行（与 [_AlternativeRow] 同构，避免尺寸跳动）。
final class _AlternativeSkeletonRow extends StatelessWidget {
  const _AlternativeSkeletonRow();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      border: Border.all(color: context.lf.border),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(
        horizontal: LfDimens.spaceSmallPlus,
        vertical: LfDimens.spaceSmall,
      ),
      child: Row(
        children: [
          SkeletonBox(
            width: 36,
            height: 36,
            borderRadius: BorderRadius.all(Radius.circular(18)),
          ),
          SizedBox(width: LfDimens.spaceSmallPlus),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 15, width: 96),
                SizedBox(height: 6),
                SkeletonBox(height: 13, width: 72),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// 与动作/计划列表卡（Card + ListTile）同构的骨架占位（docs/21 §3.1）。
final class _ListTileSkeletonCard extends StatelessWidget {
  const _ListTileSkeletonCard();

  @override
  Widget build(BuildContext context) => DesignCard(
    padding: const EdgeInsets.symmetric(
      horizontal: LfDimens.pagePadding,
      vertical: LfDimens.spaceMedium,
    ),
    child: SizedBox(
      height: 72,
      child: Center(
        child: Row(
          children: [
            const SkeletonBox(
              width: 36,
              height: 36,
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            const SizedBox(width: LfDimens.spaceLarge),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(height: 17, width: 128),
                  SizedBox(height: 6),
                  SkeletonBox(height: 13, width: 88),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 动作库卡片单格高度（需求 68，docs/32 §4 T3）。
///
/// 内容高 = 图标行 36 + 图标↔标题 8 + 名称 + 标题↔标签 6 + 标签行 + 卡内内边距 24。
/// **不再额外 +12**：那 12dp 是历史遗留行距（`DesignCard` 的 padding 已是上下
/// 对称 12），叠加后就成了卡片底部多出来的空白——2026-10-11 用户反馈需求 68。
///
/// 提为顶层纯函数是为了可测：`_cardExtent` 依赖 `BuildContext` 取字号缩放，
/// 这里的比例入参是纯数值，测试可直接钉公式（含 2.0× 字号档）。
double exerciseCardExtent({
  required double bodyScale,
  required double tagScale,
}) =>
    36 + // 图标行（36 圆不随字号）
    8 + // 图标 ↔ 标题
    21 * bodyScale + // 名称（14 号 h1.5）
    6 + // 标题 ↔ 标签
    (13.2 * tagScale + 4) + // 标签行（11 号 h1.2 + 上下内边距 4）
    24; // 卡内内边距（上下各 12，对称）

/// 测试入口：按「字号倍数」取高度（1.0× ⇒ bodyScale = tagScale = 1）。
/// 【`RV4-P3-02` 复核结论：**保留**】生产代码零调用，名字里的
/// `ForTesting` 就是它的身份：`round5_small_styles_test` 用它钉住「行高公式
/// 不含额外底部留白」这条几何契约。删掉等于把那条断言一起废掉。
double exerciseCardExtentForTesting({required double fontScale}) =>
    exerciseCardExtent(bodyScale: fontScale, tagScale: fontScale);

Future<void> showCreateExerciseSheet(
  BuildContext context, {
  required ExerciseRepository repository,
  String? prefillName,
  VoidCallback? onSaved,
}) {
  var name = prefillName ?? '';
  var muscleGroup = MuscleGroup.chest;
  var equipment = Equipment.barbell;
  String? errorText;
  var saving = false;

  return AppSheet.showForm<void>(
    context,
    title: '新建动作',
    body: (dialogContext, setDialogState) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LfTextField(
          fieldKey: const Key('training-exercise-name'),
          label: '动作名称',
          autofocus: true,
          initialValue: prefillName,
          errorText: errorText,
          onChanged: (value) => name = value,
        ),
        const SizedBox(height: 8),
        LfSelectField<MuscleGroup>(
          fieldKey: const Key('training-exercise-muscle-group'),
          label: '目标肌群',
          value: muscleGroup,
          options: MuscleGroup.values,
          optionLabel: (group) => group.label,
          onChanged: (value) => setDialogState(() => muscleGroup = value),
        ),
        const SizedBox(height: 8),
        LfSelectField<Equipment>(
          fieldKey: const Key('training-exercise-equipment'),
          label: '器械类型',
          value: equipment,
          options: Equipment.values,
          optionLabel: (item) => item.label,
          onChanged: (value) => setDialogState(() => equipment = value),
        ),
      ],
    ),
    // 弹层底部行动（§3.4/§3.8）：左 = 取消（B6），右 = 主行动（B2）；
    // 两档分居两端，行宽固定，按钮不再随文案长短左右漂。
    actions: (dialogContext, setDialogState) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        LfTextButton(
          label: '取消',
          onPressed: () => Navigator.of(dialogContext).pop(),
        ),
        LfConfirmButton(
          key: const Key('training-exercise-save'),
          label: '保存',
          expand: false,
          onPressed: () async {
            if (saving) return;
            setDialogState(() => saving = true);
            try {
              await repository.create(
                NewExercise(
                  name: name,
                  muscleGroup: muscleGroup,
                  equipment: equipment,
                ),
              );
            } on FormatException catch (error) {
              // 异步期间用户可能已点遮罩/返回关掉弹层，setDialogState 会
              // 打在已销毁的 State 上。
              if (!dialogContext.mounted) return;
              setDialogState(() {
                saving = false;
                errorText = error.message;
              });
              return;
            }
            if (!dialogContext.mounted) return;
            Navigator.of(dialogContext).pop();
            onSaved?.call();
          },
        ),
      ],
    ),
  );
}
