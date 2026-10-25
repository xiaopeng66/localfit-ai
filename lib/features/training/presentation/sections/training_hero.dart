import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/chart_semantics.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/training/domain/workout_plan.dart';

/// 训练页顶部卡（docs/21 §5.5 `训练.html` §1；docs/30 §2 D6 白卡化）。
///
/// 设计稿是 `background: var(--lf-neutral-900); color: var(--lf-primary-foreground)`
/// + `rounded-b-[16px]` + `p-5 pb-8`——**纯色**，不是 hero 渐变（§2.5 的 9 条
/// 渐变里没有它）。旧实现按设计稿取 `LfColors.neutral(brightness).tone(900)`
/// （亮色近黑、暗色近白）铺成贴顶色块。
///
/// **2026-10-08 白卡化**（用户走查需求 6「训练界面的黑色数据卡都很丑，请重新
/// 设计」）：现在是**标准 [DesignCard]**（白底 + 1px 描边 + 16 圆角 + 浅阴影），
/// 与记录 / 菜单 / 我的身份卡同一个方向（`docs/30 §2 D4/D5/D6`）：用户连续点名
/// 四张「大色块数据卡」丑（绿×3 + 黑×1）⇒ **大色块退场**。
///
/// 三处随之调整：
///
///  1. **文字全部改卡色**：`displayHero` 30px w800 的**量级感保留**（那是这张卡
///     的视觉重心），但颜色从「hero 反色」改为 `cardForeground` / `mutedForeground`；
///  2. **容量图改白底配色**：训练日 `mint-400`、**今日** `mint-600`、无训练
///     `muted`。改造前「今日」用 mint-300（比其余训练日**更浅**）——在近黑底上
///     「更浅 = 更亮 = 更近」的语义是对的，但白底上必须反过来：**更饱和才更近**；
///  3. **不再铺到屏幕物理顶边** ⇒ 顶部留白改由页面给
///     （`pagePadding + LfInsets.top`，与我的页同一处理），本组件不再读
///     `LfInsets.top`。
class TrainingHero extends StatelessWidget {
  const TrainingHero({
    super.key,
    required this.weekIndex,
    required this.finishedCount,
    required this.totalDuration,
    required this.totalKcal,
    required this.capacityMinutes,
    required this.todayIndex,
    this.restWeekdays = const <int>[],
  });

  /// 「第 N 周」= 从首个 session 起算的周序号（§7.1 派生）。null = 无训练历史。
  final int? weekIndex;

  /// 本周已完成训练次数 / 总时长 / 消耗 kcal。
  final int finishedCount;
  final Duration totalDuration;

  /// 消耗 kcal。**当前无数据源**（`WorkoutSets` 没有热量列，也没有心率/体重
  /// 参与的有氧公式），恒为 null → 按 §6.1 渲染「—」而不是编一个数。
  final double? totalKcal;

  /// 周一到周日的训练分钟数（7 项）。
  final List<int> capacityMinutes;

  /// 今日在周一..周日中的索引（0..6）。
  final int todayIndex;

  /// 计划中的休息日（weekday 1..7，来自计划的 `WorkoutDays`）。
  final List<int> restWeekdays;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    // 卡片左右与底部留 16（与全 App 其余卡同一间距语言）；**顶部不再自己吃
    // 叠层**——不再贴顶，留白由页面给 `pagePadding + LfInsets.top`。
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LfDimens.pagePadding,
        0,
        LfDimens.pagePadding,
        LfDimens.pagePadding,
      ),
      child: DesignCard(
        key: const Key('training-hero'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '训练',
                    key: const Key('training-title'),
                    style: LfText.title.copyWith(color: c.cardForeground),
                  ),
                ),
                // 「第38周」是演示值（§6.1）。无训练历史时不渲染这一行。
                if (weekIndex != null)
                  Text(
                    '第$weekIndex周',
                    key: const Key('training-hero-week'),
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
              ],
            ),
            const SizedBox(height: LfDimens.spaceMedium),
            // 三段统计恒并排（A `.training-overview` 的一行）：窄屏大字时各段
            // 的数值**等比缩小**（`_HeroStat` 里的 scaleDown），不折行、不改结构；
            // 列间 8 间距保证缩到贴边时两个数不会读成一个（缺陷 ㉑ 的实测：
            // 无间距时 2.0× 下「0min」与「—」贴成「0min—」）。
            Row(
              children: [
                _HeroStat(
                  value: finishedCount.toString(),
                  label: '已完成训练',
                  semanticKey: const Key('training-hero-count'),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                _HeroStat(
                  value: formatDuration(totalDuration),
                  label: '总时长',
                  semanticKey: const Key('training-hero-duration'),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                _HeroStat(
                  value: totalKcal == null
                      ? '—'
                      : totalKcal!.round().toString(),
                  label: '消耗 kcal',
                  semanticKey: const Key('training-hero-kcal'),
                ),
              ],
            ),
            const SizedBox(height: LfDimens.spaceLargePlus),
            _CapacityChart(
              minutes: capacityMinutes,
              todayIndex: todayIndex,
              // 白底上「更饱和 = 更近」：今日用 mint-600（比其余训练日更深），
              // 而不是旧暗色底上的 mint-300（更浅）。旧配色在近黑底上成立，
              // 搬到白底会反过来读成「今天最不重要」。
              todayColor: mint.tone(600),
              normalColor: mint.tone(400),
            ),
            const SizedBox(height: LfDimens.spaceMedium),
            _RestLegend(restWeekdays: restWeekdays, dotColor: mint.tone(400)),
          ],
        ),
      ),
    );
  }

  /// 「2.8h」/「45min」——设计稿两处用 h、一处用 min，按量级二选一。
  /// 0 分钟写 `0min` 而不是 `0.0h`。
  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    if (minutes < 60) return '${minutes}min';
    final hours = minutes / 60;
    // 保留一位小数，但整点写整数（「2h」不写「2.0h」）。
    final text = hours == hours.roundToDouble()
        ? hours.round().toString()
        : hours.toStringAsFixed(1);
    return '${text}h';
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.label,
    required this.semanticKey,
  });

  final String value;
  final String label;
  final Key semanticKey;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Expanded(
      // 三段等宽：设计稿是 `flex gap-4`，每段按内容宽度。用 Expanded 让
      // 三段在窄屏上也均匀分栏（设计稿的三个数位数相近，视觉等价）。
      child: Column(
        key: semanticKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 【为什么是 scaleDown 而不是 ellipsis】（Round7 阶段 4 · 缺陷 ㉑，
          // 实测 320dp + 2.0× 帧）：`displayHero` 30px 在 2.0× 下是 60px，
          // 三分宽放不下「0min」⇒ ellipsis 把它静默裁成「0…」，数值这一格
          // 就成了假信息。A 的 `.training-overview b` 是 750 字重 + 单位小字
          // （窄屏不裁）。本仓口径是「放不下就等比缩小」——`LfStatTile`、
          // `MacroDotLine`、2A 的下一餐值行都是这一条。
          // 无界宽度下 `Text` 不折行 ⇒ scaleDown 只管缩、不改行数。
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                // 设计稿 `text-3xl`（30px）→ `.lf-display` → displayHero。
                // **白卡化不动字阶**：这个 30 是这张卡的量级感来源。
                style: LfText.displayHero.copyWith(color: c.cardForeground),
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(height: LfDimens.spaceTiny),
          Text(label, style: LfText.micro.copyWith(color: c.mutedForeground)),
        ],
      ),
    );
  }
}

/// 周容量柱状图（设计稿 `#capacityChart`：7 柱、圆角 8、`maxY: 60`、
/// 今日柱用 mint-300、其余训练日 mint-400、0 分钟日 `rgba(255,255,255,.12)`）。
///
/// **手绘而非 fl_chart**：设计稿的 x 轴只有 10px 白色 35% 的星期字母，y 轴完全
/// 隐藏，且要在暗色 hero 上取色——fl_chart 的 `BarChart` 在暗底上的网格/边框
/// 清理反而更啰嗦（旧实现就要写 5 个 `show: false`）。docs/22 §2.6 允许「手绘
/// 折线的取舍」，同理适用于本图。
class _CapacityChart extends StatelessWidget {
  const _CapacityChart({
    required this.minutes,
    required this.todayIndex,
    required this.todayColor,
    required this.normalColor,
  });

  final List<int> minutes;
  final int todayIndex;
  final Color todayColor;
  final Color normalColor;

  /// 设计稿 `y.max = 60`。超过 60 分钟的日子按满格画（不裁数据，只是视觉封顶），
  /// 并在语义标签里报真实分钟数。
  static const _maxMinutes = 60.0;

  /// 柱区高度（外层 `SizedBox(height: 72)` 就是它；显式算高度后柱底贴底）。
  static const _chartHeight = 72.0;

  /// 无训练日的最小可见柱（A `height:3px`）。
  static const _emptyBarHeight = 3.0;

  /// 有训练分钟时的下限（比空柱高一档，两者在灰阶上也能分辨）。
  static const _minTrainedBarHeight = 6.0;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 7 柱是设计稿的固定形态；短列表按 0 补齐而不是少画几柱——柱子数量变化
    // 会让「今天」的位置漂移。
    final values = List<int>.generate(
      7,
      (i) => i < minutes.length ? minutes[i] : 0,
    );
    final labels = workoutWeekdayLabels;
    // 图表语义走全仓统一的 ChartSemantics 模式（docs/21 §3「图表必须有文字
    // 等价物」/§5.8.3）：整张图一个文字摘要节点，图形与轴标 excludeSemantics。
    // （曾按柱给 `Semantics(label: …)`：实测 7 条标注全部并进 hero 的单个
    // 语义节点，label 成了整段拼接文本——读屏和 `find.bySemanticsLabel` 都
    // 拿不到单柱。）
    final trainedParts = [
      for (var i = 0; i < 7; i++)
        if (values[i] > 0) '周${labels[i]} ${values[i]} 分钟',
    ];
    final summary = trainedParts.isEmpty
        ? '本周容量图：还没有训练记录；今天是周${labels[todayIndex]}。'
        : '本周容量图：${trainedParts.join('、')}；今天是周${labels[todayIndex]}。';
    return ChartSemantics(
      summary: summary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            key: const Key('training-capacity-chart'),
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    // barPercentage 0.5 / categoryPercentage 0.7 ⇒ 柱宽约占
                    // 每格的 35%，两侧留白。
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4.5),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        // 【为什么不是 FractionallySizedBox】（Round7 阶段 4 ·
                        // 缺陷 ⑳，实测帧抓到）：`heightFactor: 0` 会把子件的
                        // `minHeight` **一并压成 0** ⇒ 无训练日那一列在白卡上
                        // 空白，读起来像数据缺失。A（`app.js:210`）对 0 分钟日
                        // 写的是 `height:3px` 的最小可见柱——「这周有 7 天、
                        // 这天是空的」这层意思必须画得出来。显式算高度：
                        // 有训练分钟 ⇒ 按比例（下限 4）；0 ⇒ 固定 3。
                        child: SizedBox(
                          height: values[i] == 0
                              ? _emptyBarHeight
                              : (values[i] / _maxMinutes * _chartHeight).clamp(
                                  _minTrainedBarHeight,
                                  _chartHeight,
                                ),
                          width: double.infinity,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: values[i] == 0
                                  // 无训练日 = `muted`（旧实现是 hero 前景色
                                  // 的 12% 透明——那是「压深色底」的画法，
                                  // 搬到白卡上会变成一条几乎看不见的灰）。
                                  ? c.muted
                                  : i == todayIndex
                                  ? todayColor
                                  : normalColor,
                              borderRadius: BorderRadius.circular(
                                LfDimens.radiusSm,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: LfText.micro.copyWith(color: c.mutedForeground),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 休息日图例（设计稿：月亮图标 + 「休息日 · 二 / 四 / 日」+ 训练日圆点）。
///
/// **休息日来自计划**（§6.2 裁决 4）：传进来的 [restWeekdays] 是计划里没有
/// 动作的那些星期；一个都没有时不渲染该行（不硬编码「二 / 四 / 日」）。
class _RestLegend extends StatelessWidget {
  const _RestLegend({required this.restWeekdays, required this.dotColor});

  final List<int> restWeekdays;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    if (restWeekdays.isEmpty) return const SizedBox.shrink();
    final c = context.lf;
    final sorted = [...restWeekdays]..sort();
    final labels = sorted
        .where((day) => day >= 1 && day <= 7)
        .map((day) => workoutWeekdayLabel(day))
        .join(' / ');
    if (labels.isEmpty) return const SizedBox.shrink();
    return Row(
      key: const Key('training-rest-legend'),
      children: [
        Icon(Icons.bedtime_outlined, size: 12, color: c.mutedForeground),
        const SizedBox(width: LfDimens.spaceXSmall),
        Expanded(
          child: Text(
            '休息日 · $labels',
            style: LfText.micro.copyWith(color: c.mutedForeground),
          ),
        ),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: LfDimens.spaceXSmall),
        Text('训练日', style: LfText.micro.copyWith(color: c.cardForeground)),
      ],
    );
  }
}

/// 进行中训练横幅（docs/21 §5.5 §2）：hero 渐变 + 上叠 + 脉冲白点。
///
/// 渐变取 `LfGradients.activeBanner`（§2.5 里「进行中横幅」是**独立一条**，
/// 与 hero 变量不同）；阴影取 `LfShadows.activeBanner`（primary 25%）。
class TrainingActiveBanner extends StatelessWidget {
  const TrainingActiveBanner({
    super.key,
    required this.sessionName,
    required this.completedSets,
    required this.plannedSets,
    required this.onResume,
    required this.onOpenDetail,
  });

  /// 会话名。有 `planId` 时用计划名，否则「自由训练」。
  final String sessionName;
  final int completedSets;

  /// 计划总组数。null = 无法得出分母（计划已删或自由训练）→ 不渲染进度条。
  final int? plannedSets;

  final VoidCallback onResume;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    // 进度 = 已完成组数 / 计划组数（§7.1 派生）。分母缺失时进度条整条不渲染：
    // 设计稿的「65%」是演示值，编一个进度比不画更糟。
    final progress = plannedSets == null || plannedSets == 0
        ? null
        : (completedSets / plannedSets!).clamp(0.0, 1.0);
    return Container(
      key: const Key('training-active-banner'),
      // 设计稿这里是 `-mt-4`（横幅上叠进 hero 的底部留白）。Flutter 的
      // Container 拒收负 margin（debug 断言 `margin.isNonNegative`，一渲染
      // 就红屏——有活动会话就必现）。横幅是不透明渐变卡，「上叠 16dp」与
      // 「紧贴 + hero 底部留白 16dp」视觉等价（重叠区域被横幅完全盖住），
      // 所以落成 0 间距，hero 的 pb 已按此调成 16。docs/21 §6 允许这类
      // 像素级等价改写。
      margin: const EdgeInsets.fromLTRB(
        LfDimens.pagePadding,
        0,
        LfDimens.pagePadding,
        0,
      ),
      padding: const EdgeInsets.all(LfDimens.spaceLarge),
      decoration: BoxDecoration(
        gradient: LfGradients.activeBanner(c.primary, brightness),
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
        boxShadow: LfShadows.activeBanner(c.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _PulseDot(),
              const SizedBox(width: LfDimens.spaceSmall),
              Text(
                '进行中',
                style: LfText.caption.copyWith(
                  color: c.primaryForeground,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '已记录 $completedSets 组',
                style: LfText.caption.copyWith(
                  color: c.primaryForeground.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          Text(
            sessionName,
            key: const Key('training-active-name'),
            style: LfText.titleLarge.copyWith(color: c.primaryForeground),
          ),
          if (progress != null) ...[
            const SizedBox(height: LfDimens.spaceMedium),
            ClipRRect(
              borderRadius: BorderRadius.circular(LfDimens.radiusFull),
              child: LinearProgressIndicator(
                key: const Key('training-active-progress'),
                value: progress,
                minHeight: 6,
                backgroundColor: c.primaryForeground.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(c.primaryForeground),
              ),
            ),
          ],
          const SizedBox(height: LfDimens.spaceMedium),
          Wrap(
            spacing: LfDimens.spaceSmall,
            runSpacing: LfDimens.spaceSmall,
            children: [
              // 【刻意保留手写反色档】这两颗压在**品牌实色 hero** 上：主题给的
              // 实心档是 mint-600（与 hero 底同色系，会糊成一片），文字档是
              // 品牌字色（在近黑底上不可读）。§3.8 没有「反色档」，所以这里
              // 保留显式反色（白底 + mint-700 字 / 白字 + 15% 白底），是
              // 与 `_AlbumBadge` 同类的「压在图上」例外，不是未收敛的散件。
              FilledButton.icon(
                key: const Key('cta-continue-session'),
                onPressed: onResume,
                style: FilledButton.styleFrom(
                  backgroundColor: c.primaryForeground,
                  foregroundColor: LfColors.mint(brightness).tone(700),
                  padding: const EdgeInsets.symmetric(
                    horizontal: LfDimens.spaceLarge,
                    vertical: LfDimens.spaceSmall,
                  ),
                  textStyle: LfText.caption,
                  minimumSize: const Size(0, LfDimens.minTouchTarget),
                ),
                icon: const Icon(Icons.play_arrow, size: 14),
                label: const Text('继续训练'),
              ),
              TextButton.icon(
                key: const Key('training-session-detail'),
                onPressed: onOpenDetail,
                style: TextButton.styleFrom(
                  foregroundColor: c.primaryForeground,
                  backgroundColor: c.primaryForeground.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(
                    horizontal: LfDimens.spaceLarge,
                    vertical: LfDimens.spaceSmall,
                  ),
                  textStyle: LfText.caption,
                  minimumSize: const Size(0, LfDimens.minTouchTarget),
                ),
                iconAlignment: IconAlignment.end,
                icon: const Icon(Icons.chevron_right, size: 14),
                label: const Text('查看详情'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 脉冲白点（设计稿 `w-2 h-2 rounded-full bg-white animate-pulse`）。
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // RV-P2-24：系统要求「减少动画」时不做无限脉冲（也不能让它阻塞 settle）。
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // reducedMotion（docs/21 §5.8.3）：关掉动画时保留实心点（信息不丢，
    // 只是不动）。
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: c.primaryForeground,
          shape: BoxShape.circle,
        ),
      );
    }
    return FadeTransition(
      // animate-pulse = opacity 1 → 0.5。
      opacity: Tween<double>(begin: 1, end: 0.5).animate(_controller),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: c.primaryForeground,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// 计划卡（docs/21 §5.5 `PlanCard`）：计划名 + 星期标签 + 动作列表 +
/// 元信息行。
///
/// **只渲染库里真有的字段**（§6.1）。设计稿卡片上的这些一律**不上屏**，因为
/// 没有对应列：
///  * 「45分钟 / 中等强度 / 320 kcal」——`WorkoutPlans` 无时长/强度/热量列；
///  * 每个动作的「配速6:30」「阻力4」「10min」——`CardioPrescriptions` 表
///    虽然存在，但**全仓零写入者**，读它只会得到空；
///  * 「胸 · 背 · 肩」——可由 `Exercises.muscleGroup` 真实聚合，**保留**，
///    但只在能算出肌群时渲染。
///
/// 【与设计稿的差异】设计稿的卡片标题是**训练日名**（「上肢力量训练」
/// 「跑步间歇训练」…），而 `WorkoutDays` 没有名称列，所以标题取计划名；
/// 一个计划下有多张卡时补上星期（`计划名 · 周三`）以免同名难辨。
/// 设计稿的标题**不带序号前缀**，这里也不加——加了会让卡片名与计划名对不上，
/// 也让「按名字点这张卡」变得不可能。
class TrainingPlanCard extends StatelessWidget {
  const TrainingPlanCard({
    super.key,
    required this.index,
    required this.plan,
    required this.weekday,
    required this.entries,
    required this.muscleLabels,
    required this.onTap,
    required this.onDelete,
    this.isToday = false,
    this.planWeekdays = const <int>{},
    this.todayWeekday,
    this.todayCtaLabel,
    this.onTodayCta,
  });

  /// 卡片序号（1 起），同时是 `training-plan-card-<n>` 的键值。
  final int index;
  final WorkoutPlanSummary plan;

  /// 这一卡对应的星期（1=周一 … 7=周日，来自 `WorkoutDays.weekday`）。
  final int weekday;

  /// 本卡要渲染的动作行。**已按肌群 chips 过滤**（§5.5「肌肉 chips → 过滤
  /// 动作」），所以它不一定是计划日的全部动作——这正是它单独传入、而不是
  /// 从 `day.entries` 现取的原因。
  final List<PlannedExerciseRecord> entries;

  /// 肌群文字（如「胸 · 背 · 肩」）。空 ⇒ 不渲染该段。
  final String muscleLabels;

  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// 今日（`weekday == now.weekday`）→ 左侧 3dp primary 竖条 + 「今天」徽章。
  final bool isToday;

  /// **这份计划**编排了动作的星期集合（1=周一…7=周日）。
  ///
  /// Round7 逐页对账批次 3：A `app.js:216` 的计划卡有 `.plan-days` 七枚日签
  /// （`on` = 计划日）。本仓口径与休息日图例同一处来源——「该 weekday 有
  /// `PlannedExercises` 才是训练日」（§6.2 裁决 4）。
  final Set<int> planWeekdays;

  /// 今天的星期（1..7）。null = 不知道（不画今日行的高亮判断，
  /// 但今日行本身仍按「今天休息」渲染——计划日集合为空时它恒真）。
  final int? todayWeekday;

  /// 今日行右端的 CTA 文案（Round7 裁决 R1，A `app.js:216` 的 `.plan-today`
  /// 右端按钮：「开始训练」/ 有进行中会话时「继续训练」）。
  ///
  /// **只在今天这张卡给**（null ⇒ 不画按钮）。A 画在每张卡、非今日
  /// `disabled`；本仓一计划日一张卡，画一枚永久禁用的按钮只是噪音，
  /// 登记为形态差异。
  final String? todayCtaLabel;
  final VoidCallback? onTodayCta;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 今天 = 左侧 3dp primary 竖条 + 「今天」徽章（设计稿的既定形态）。
    // 外层这圈只给圆角、不裁剪也不画边框：竖条自带左侧圆角。
    // （曾在这里放一条**全透明**的 3dp 左边框占位，除了把今日卡的内容
    // 整体缩进 3dp、与其余卡错位之外没有任何视觉作用，已删。）
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
      ),
      child: DesignCard(
        key: Key('training-plan-card-$index'),
        padding: EdgeInsets.zero,
        onTap: onTap,
        onLongPress: onDelete,
        // 今日卡左侧那根 3dp 竖条要**撑满卡片高度**。卡片在 ListView 里高度
        // 不受限，直接给 Row 用 `CrossAxisAlignment.stretch` 会得到
        // `minHeight: Infinity`；这个约束一旦落到自带约束的子渲染对象上
        // （今天的竖条是 `Container(width: 3)` → RenderConstrainedBox），
        // 就会抛「BoxConstraints forces an infinite height」——**只在「今天」
        // 这一张卡上红屏**，其余六天看不出来。IntrinsicHeight 先把行高定成
        // 内容高度，stretch 才成立。
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isToday)
                Container(
                  key: const Key('training-plan-today-bar'),
                  width: 3,
                  decoration: BoxDecoration(
                    color: c.primary,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(LfDimens.radiusLg),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(LfDimens.cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.fitness_center_outlined,
                            size: 16,
                            color: c.primary,
                          ),
                          const SizedBox(width: LfDimens.spaceSmall),
                          Expanded(
                            child: Text(
                              // 2026-10-16：标题不再补「· 周一」。星期由右侧
                              // `_DayBadge`（`周一` / `今天`）承担——两处各写
                              // 一遍是重复，且 320dp + 2.0× 字号下后缀会被挤
                              // 到第二行（训练页帧实看抓到：「推拉腿 · 三练」
                              // 换行后单独一行「· 周一」，右侧徽章同时写着
                              // 「周一」）。多张卡仍需分辨是哪个训练日 ⇒ 由
                              // 徽章的星期 + 七枚日签两点共同给出。
                              plan.name,
                              key: Key('training-plan-name-$index'),
                              style: LfText.bodyStrong.copyWith(
                                color: c.cardForeground,
                              ),
                            ),
                          ),
                          _DayBadge(weekday: weekday, isToday: isToday),
                        ],
                      ),
                      const SizedBox(height: LfDimens.spaceXSmall),
                      // 「N 个动作」是真实计数（本卡实际渲染的动作行数，
                      // 已含肌群筛选的效果）。
                      Text(
                        '${entries.length} 个动作',
                        style: LfText.caption.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                      // Round7 逐页对账批次 3：A `app.js:216` 的周安排块——
                      // `.plan-days` 七枚日签 + `.plan-today` 今日行。
                      _PlanWeekdaysRow(
                        cardIndex: index,
                        planWeekdays: planWeekdays,
                        todayWeekday: todayWeekday,
                        todayCtaLabel: todayCtaLabel,
                        onTodayCta: onTodayCta,
                      ),
                      if (entries.isNotEmpty) ...[
                        const SizedBox(height: LfDimens.spaceMedium),
                        for (final entry in entries)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: LfDimens.spaceSmall,
                            ),
                            child: _PlannedExerciseRow(
                              key: Key(
                                'training-plan-$index-entry-${entry.sortOrder}',
                              ),
                              name: entry.exerciseName,
                              entry: entry,
                            ),
                          ),
                      ],
                      Row(
                        children: [
                          // 肌群圆点：设计稿三个彩色圆点 + 文字。三色按 §2.1.3
                          // 分类色固定编码（protein/carbs/fat），此处只作装饰性
                          // 分色，文字才是信息本体。
                          if (muscleLabels.isNotEmpty) ...[
                            _Dot(color: c.protein),
                            _Dot(color: c.carbs),
                            _Dot(color: c.fat),
                            const SizedBox(width: LfDimens.spaceXSmall),
                            Expanded(
                              child: Text(
                                muscleLabels,
                                key: Key('training-plan-muscles-$index'),
                                style: LfText.caption.copyWith(
                                  color: c.mutedForeground,
                                ),
                              ),
                            ),
                          ] else
                            const Spacer(),
                          Text(
                            '${plan.entryCount} 个动作',
                            style: LfText.label.copyWith(
                              color: c.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 计划卡的周安排块（Round7 逐页对账批次 3，A `app.js:216` 的
/// `.plan-days` + `.plan-today`）：七枚 31dp 圆签 + 一行今日状态。
///
/// 三档取色按 A 的 `.day-chip`（`styles.css:351-353`）：计划日 = 品牌浅底 +
/// 强调字；今天 = **品牌实心底** + 主按钮前景（A 写的是 `--brand-strong`
/// 实底——本仓的「实心品牌」角色是 `primary`/`primaryForeground`，见
/// `LfPrimaryButton`，不在这里硬写色值）；其余 = 轨道底 + 次文。
///
/// 圆签用 `minWidth/minHeight` 而不是死高 31：大字档下字符本身会长，
/// 固定盒会把「一」挤成溢出（A 无此档位）。
class _PlanWeekdaysRow extends StatelessWidget {
  const _PlanWeekdaysRow({
    required this.cardIndex,
    required this.planWeekdays,
    required this.todayWeekday,
    this.todayCtaLabel,
    this.onTodayCta,
  });

  final int cardIndex;
  final Set<int> planWeekdays;
  final int? todayWeekday;

  /// 今日行右端 CTA（Round7 裁决 R1）：null ⇒ 只画文字行。
  final String? todayCtaLabel;
  final VoidCallback? onTodayCta;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brandSoft = LfColors.mint(Theme.of(context).brightness).tone(50);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          key: Key('training-plan-weekdays-$cardIndex'),
          padding: const EdgeInsets.only(top: LfDimens.spaceSmall),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var n = 1; n <= 7; n++)
                Container(
                  key: Key('training-plan-weekday-$cardIndex-$n'),
                  constraints: const BoxConstraints(
                    minWidth: 31,
                    minHeight: 31,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: n == todayWeekday
                        ? c.primary
                        : planWeekdays.contains(n)
                        ? brandSoft
                        : c.muted,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    workoutWeekdayLabel(n),
                    style: LfText.micro.copyWith(
                      color: n == todayWeekday
                          ? c.primaryForeground
                          : planWeekdays.contains(n)
                          ? LfColors.mintText(Theme.of(context).brightness)
                          : c.mutedForeground,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        // A `.plan-today`：左一句真话（今天的计划状态）+ 右端可选 CTA。
        Row(
          children: [
            Expanded(
              child: Text(
                todayWeekday != null && planWeekdays.contains(todayWeekday)
                    ? '今天是训练日'
                    : '今天休息，恢复也很重要',
                key: Key('training-plan-today-note-$cardIndex'),
                style: LfText.label.copyWith(color: c.mutedForeground),
              ),
            ),
            if (todayCtaLabel != null && onTodayCta != null) ...[
              const SizedBox(width: LfDimens.spaceSmall),
              // A `.plan-today .btn`：窄一点的内联主行动（B3 soft 档，
              // 与计划详情里的同一枚 `LfPillButton`，不另造一档）。
              LfPillButton(
                key: Key('training-plan-start-$cardIndex'),
                label: todayCtaLabel!,
                icon: Icons.play_arrow,
                tone: LfPillTone.soft,
                onPressed: onTodayCta,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 计划日的星期徽章：今天 = mint-50 底 + primary 字；其余 = muted 底。
class _DayBadge extends StatelessWidget {
  const _DayBadge({required this.weekday, required this.isToday});

  final int weekday;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    return Container(
      key: isToday ? const Key('training-plan-today-badge') : null,
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceSmall,
        vertical: LfDimens.spaceMicro,
      ),
      decoration: BoxDecoration(
        color: isToday ? mint.tone(50) : c.muted,
        borderRadius: BorderRadius.circular(LfDimens.radiusFull),
      ),
      child: Text(
        isToday ? '今天' : '周${workoutWeekdayLabel(weekday)}',
        style: LfText.micro.copyWith(
          color: isToday ? c.primary : c.mutedForeground,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: LfDimens.spaceMicro),
    child: Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    ),
  );
}

/// 计划里的单个动作行：名字（左）+ 组次×重量（右）。
///
/// 右侧只渲染 `PlannedExercises` 真有的列：`targetSets` / `targetReps` /
/// `targetWeightKg`。设计稿的有氧行（「配速6:30」「阻力4」「10min」）来自
/// `CardioPrescriptions`，而那张表**没有任何写入路径**——读出来必为空，
/// 所以这里只可能渲染力量型处方（`4 × 8 · 60kg`）。无重量写「自重」。
class _PlannedExerciseRow extends StatelessWidget {
  const _PlannedExerciseRow({
    super.key,
    required this.name,
    required this.entry,
  });

  final String name;
  final PlannedExerciseRecord entry;

  /// 「4 × 8 · 60kg」/「4 × 8 · 自重」。
  static String targetLabel(PlannedExerciseRecord entry) {
    final base = '${entry.targetSets} × ${entry.targetReps}';
    final weight = entry.targetWeightKg;
    if (weight == null || weight <= 0) return '$base · 自重';
    // 整数公斤不写小数点（「60kg」不写「60.0kg」）；带小数的保留一位。
    final text = weight == weight.roundToDouble()
        ? weight.round().toString()
        : weight.toStringAsFixed(1);
    return '$base · ${text}kg';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Row(
      children: [
        Icon(Icons.fitness_center, size: 14, color: c.mutedForeground),
        const SizedBox(width: LfDimens.spaceSmall),
        Expanded(
          child: Text(
            name,
            style: LfText.caption.copyWith(color: c.cardForeground),
            // §5.8.3：长标题允许换行，不得不可见截断。
          ),
        ),
        const SizedBox(width: LfDimens.spaceSmall),
        Text(
          targetLabel(entry),
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
      ],
    );
  }
}

/// 本周训练统计卡（docs/21 §5.5 §5 第一张卡）：三段汇总 + 分类型行。
class TrainingWeekStatsCard extends StatelessWidget {
  const TrainingWeekStatsCard({
    super.key,
    required this.weekIndex,
    required this.finishedCount,
    required this.totalDuration,
    required this.totalKcal,
    required this.rows,
    required this.volumeKg,
    required this.onOpenRecords,
  });

  final int? weekIndex;
  final int finishedCount;
  final Duration totalDuration;
  final double? totalKcal;

  /// 本周分肌群统计行（`label` + 已格式化好的右值，如 `12组 · 480kg`）。
  ///
  /// 【与设计稿的差异】设计稿按「训练类型」分行（力量训练 / 跑步 / 骑行 /
  /// 核心），但库里**没有训练类型这一维**——`Exercises` 只有肌群与器械。
  /// 这里改按 `Exercises.muscleGroup` 聚合本周已记录组次：同一根轴上的
  /// 真实数据，而且与顶部肌群 chips 是同一根轴，两处不会互相打架。
  final List<({String label, String value})> rows;

  /// 本周容量（kg）。0 ⇒ 不渲染该行。
  final double volumeKg;

  final VoidCallback onOpenRecords;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DesignCard(
      key: const Key('training-week-stats'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '本周训练统计',
                  style: LfText.title.copyWith(color: c.cardForeground),
                ),
              ),
              if (weekIndex != null)
                Text(
                  '第$weekIndex周',
                  style: LfText.micro.copyWith(color: c.mutedForeground),
                ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          // 同 hero：恒并排 + 列间 8 + 数值 scaleDown（缺陷 ㉑）。
          Row(
            children: [
              _WeekStat(value: finishedCount.toString(), label: '次训练'),
              const SizedBox(width: LfDimens.spaceSmall),
              _WeekStat(
                value: TrainingHero.formatDuration(totalDuration),
                label: '总时长',
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              _WeekStat(
                value: totalKcal == null ? '—' : totalKcal!.round().toString(),
                label: '消耗 kcal',
              ),
            ],
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: LfDimens.spaceLarge),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: LfDimens.spaceSmallPlus),
                child: Row(
                  children: [
                    _Dot(color: c.primary),
                    const SizedBox(width: LfDimens.spaceXSmall),
                    Expanded(
                      child: Text(
                        row.label,
                        style: LfText.caption.copyWith(color: c.cardForeground),
                      ),
                    ),
                    Text(
                      row.value,
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
          ],
          if (volumeKg > 0) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            Text(
              // 本周容量（`TrainingStats.weeklyVolumeKg`）是真实派生值，
              // 设计稿没有这一行——它属于「Hero 与周统计卡的重复是有意的」
              // 之外的补充指标，保留一小行好过把它藏进二级入口。
              '本周容量 ${volumeKg.toStringAsFixed(1)}kg',
              key: const Key('training-week-volume'),
              style: LfText.micro.copyWith(color: c.mutedForeground),
            ),
          ],
          const SizedBox(height: LfDimens.spaceMedium),
          Align(
            alignment: Alignment.centerLeft,
            // 卡尾次级动作 = §3.8 B6（原手写 `TextButton.styleFrom`，只为了
            // 把字色改回品牌色——主题的 `textButtonTheme` 本就是品牌字色，
            // 那份覆盖等于把主题又抄了一遍）。B6 的触达由
            // `tapTargetSize: padded`（≥48）保证，不比原来的 44 低。
            child: LfTextButton(
              key: const Key('training-personal-records'),
              label: '个人纪录',
              onPressed: onOpenRecords,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekStat extends StatelessWidget {
  const _WeekStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 同 `_HeroStat`（缺陷 ㉑）：窄屏大字下按比例缩小，不 ellipsis 裁字
          // ——两处是同一屏的两张三段统计卡，口径必须一致。
          Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: LfText.displayLarge.copyWith(color: c.cardForeground),
                maxLines: 1,
              ),
            ),
          ),
          const SizedBox(height: LfDimens.spaceMicro),
          Text(label, style: LfText.micro.copyWith(color: c.mutedForeground)),
        ],
      ),
    );
  }
}
