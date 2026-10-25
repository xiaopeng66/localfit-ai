import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/app/design/widgets/text_fit.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';

/// 今日页饮水 / 步数两格（docs/21 §5.1 QuickStatsRow → Round7 A
/// `.water-steps-row` + `.metric-card`）。
///
/// A 有效值：`grid 1fr 1fr;gap:12px`；卡内 `padding:14px;gap:6px;
/// min-height:183px`（`refinement.css:7 .metric-card{gap:6px;...}`，后出的
/// refinement 覆盖 styles.css 的 7）；`metric-top` 标题 14px + 状态位
/// （pill / 图标）；
/// `metric-value{24px;font-weight:750}` + `small{12px}`（24 档按 docs/21
/// §2.6.2 复用 `displayLarge` 22，不新造 token）；`metric-label{11px}`；
/// 行动「+ 250 ml」是**文字色 `--brand-strong`、无底无框左对齐**。
///
/// 饮水卡读本地新增域；步数卡读本机计步传感器（docs/29 §P9 需求 34），
/// 没接仓储或设备没传感器时**诚实显示「暂无记录」**（§6.2 裁决 9：
/// 不显示隐含目标——这条不因「有了数据源」而失效，见 [StepsStatCard]）。
class DashboardQuickStatsRow extends StatelessWidget {
  const DashboardQuickStatsRow({
    super.key,
    required this.water,
    this.onTapWater,
    this.stepsRepository,
    this.localDate,
    this.stepGoal,
  });

  final WaterSummary water;
  final VoidCallback? onTapWater;

  /// 步数仓储；未接线时步数卡停在既有诚实空态（与 `waterRepository == null`
  /// 时饮水卡走 `WaterSummary.empty` 是同一个路子）。
  final StepsRepository? stepsRepository;

  /// 今日日期（`yyyy-MM-dd`）：步数按天落库，落库与订阅都要它。
  final String? localDate;

  /// 步数目标（docs/32 §3 D11 需求 64）：注入方给死值用（测试/其它调用点）。
  /// 生产不注入——卡片自己订阅仓储的目标流，设置页改完立刻跟着变。
  final int? stepGoal;

  @override
  Widget build(BuildContext context) {
    // 设计稿是 `grid-cols-2 gap-3` 的固定并排、无断点；能否并排由设计稿
    // 1.0× 内容预算 × 当前字号倍率判定（text_fit.dart）。旧代码的常量
    // `maxWidth < 300` 会把 360dp 手机误降级成竖排（docs/27 §6）。
    //
    // IntrinsicHeight 不能省：ListView 子项的纵向约束是无界的，Row 直接写
    // `CrossAxisAlignment.stretch` 会把「无限高」传给子项而抛
    // 「BoxConstraints forces an infinite height」。两格等高更好看，所以
    // 用一次固有高度量测换等高，而不是退回 `start`。
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!fitsRow(
          context,
          available: constraints.maxWidth,
          baseNeed: LfRowBudgets.quickStats,
        )) {
          return Column(
            children: [
              WaterStatCard(water: water, onTap: onTapWater),
              const SizedBox(height: LfDimens.spaceMedium),
              StepsStatCard(
                repository: stepsRepository,
                localDate: localDate,
                goal: stepGoal,
              ),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: WaterStatCard(water: water, onTap: onTapWater),
              ),
              const SizedBox(width: LfDimens.spaceMedium),
              Expanded(
                child: StepsStatCard(
                  repository: stepsRepository,
                  localDate: localDate,
                  goal: stepGoal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 指标卡骨架（A `.metric-card`）：内边距 14、纵向 6、最小高 183。
///
/// 高度是**卡的总高**（A `min-height:183px` 含内边距），两格并排时靠外层
/// `IntrinsicHeight` 取齐；单列降级时同一张卡不塌成内容高。
class _MetricCardShell extends StatelessWidget {
  const _MetricCardShell({
    required this.cardKey,
    required this.onTap,
    required this.semanticLabel,
    required this.children,
  });

  final Key cardKey;
  final VoidCallback? onTap;
  final String semanticLabel;
  final List<Widget> children;

  /// A `.metric-card{padding:14px}`。
  static const double padding = 14;

  /// **不再钉 A 的 `min-height:183px`**（2026-10-16 用户：「卡片高度需要调整，
  /// 底下太空白了」）：饮水/步数两卡的内容都是三行（标题 / 数值 / 进度条），
  /// 183 会留下约 80dp 的空底。高度改由内容决定——两卡结构同构 ⇒ 高度自然
  /// 相等（Row 里仍 `stretch`，不会出现一高一矮）。
  @override
  Widget build(BuildContext context) => DesignCard(
    key: cardKey,
    onTap: onTap,
    semanticLabel: semanticLabel,
    padding: const EdgeInsets.all(padding),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: _metricGap),
          children[i],
        ],
      ],
    ),
  );
}

/// A `.metric-card{gap:6px}`（`refinement.css:7`，亮暗同值）。
const double _metricGap = 6;

/// 步数卡标题行的恒高（= 「未授权」徽标盒高，实测）。三态必须同高：
/// 见 `_StepsCardShell` 里那行注释与需求 48 的断言。
const double stepsTitleRowHeight = 23;

/// A `.metric-card .data-track{margin:5px 0 0}`：进度轨在 6dp 间隔之外
/// **再**上移 5dp（轨与说明行之间的呼吸留白）。
const double _metricTrackMarginTop = 5;

/// 卡标题（A `.metric-top .section-title{font-size:14px}`）。
class _MetricTitle extends StatelessWidget {
  const _MetricTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: LfText.bodyStrong.copyWith(color: context.lf.cardForeground),
  );
}

/// 数值行（A `.metric-value`）：22 档数值（复用 `displayLarge`）+ 12px 单位。
class _MetricValue extends StatelessWidget {
  const _MetricValue({
    required this.value,
    this.unit,
    this.suffix,
    this.suffixKey,
    this.valueKey,
  });

  final String value;

  /// null = 不画单位（没有读数时不写「0 ml」）。
  final String? unit;

  /// 同一行里的小号后缀（2026-10-16：`/ 2,000 ml` 这样的「目标」段）。
  ///
  /// 为什么拆成两段而不是一个 `750 / 2,000` 字符串：卡片半宽只有 ≈130dp 可用，
  /// 13 个字符在 22 档下放不下——首拍帧里就是 `750 / 2,...`（真被截断）。
  /// 拆开后当前值保留 22 档、目标段走 caption 档，一行读作
  /// 「750 / 2,000 ml」，层次与「大数字 + 小单位」的既有语言一致。
  final String? suffix;
  final Key? suffixKey;
  final Key? valueKey;

  /// 第二行（目标段 / 空槽）的行高：`caption` 档的行高。
  ///
  /// **必须写死一个常数而不是量文本**：`suffix == null` 时那一行是空槽，
  /// 没有文本可量；而「有目标 / 没目标」两态卡高必须一致（R1 的判据）。
  /// 12px × 1.4 ≈ 17dp，取 `LfDimens.spaceSmall` 的邻居值 17。
  static const double _secondLineHeight = 17;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // `R1`（`docs/56` §3 / objective「两行数字卡」）：`n / n` **拆成上下两行**，
    // 第二行右对齐、预留高度不撑卡。
    //
    // 修前是 `Wrap`（`crossAxisAlignment: end`）——「大数字 + 单位 + 目标段」
    // 一行排，放不下就整段换行且**左对齐**；行数还随数字长度变（`750` 一行、
    // `123,456` 两行）⇒ 卡高不稳定、第二行不贴右。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 第一行用 `Wrap` 而不是 `Row`：2.0× 字号 + 320dp 半宽卡时
        // 「123,456 ml」的 `Row` 会溢出 4.5dp（实测）；`Wrap` 让单位在
        // 极端档位折到下一行**而不是画到卡外**——1.0× 下与 `Row` 视觉一致。
        Wrap(
          spacing: LfDimens.spaceMicro,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              value,
              key: valueKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LfText.displayLarge.copyWith(color: c.cardForeground),
            ),
            if (unit != null)
              Text(
                unit!,
                maxLines: 1,
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
          ],
        ),
        // 第二行：**恒占同高**（有目标画目标段、没目标留空槽）。
        // `Align(centerRight)` 就是「右对齐」的字面落点；`maxLines: 1` +
        // ellipsis 让超长目标先省略、不换行、不撑高。
        SizedBox(
          height: _secondLineHeight,
          child: Align(
            alignment: Alignment.centerRight,
            child: suffix == null
                ? const SizedBox.shrink()
                : Text(
                    suffix!,
                    key: suffixKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
          ),
        ),
      ],
    );
  }
}

class WaterStatCard extends StatelessWidget {
  const WaterStatCard({super.key, required this.water, this.onTap});

  final WaterSummary water;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final percent = water.percent;
    final target = water.targetMl;
    return _MetricCardShell(
      cardKey: const Key('dashboard-stat-water'),
      onTap: onTap,
      semanticLabel: '饮水，点击添加',
      children: [
        // 标题行：`Expanded(标题)` + 状态徽标 + 水滴图标。
        //
        // 【2.0× 窄卡下的溢出，R1 期间实测抓出】`达标 75000%` 这种长徽标在
        // 320dp 卡（内容宽 ≈ 167dp）+ 2.0× 字号下，光徽标就撑满整行，
        // 标题 + 徽标 + 间隔 + 图标会**溢出 4.5dp**（`RenderFlex overflowed`）。
        // 修法：徽标用 `Flexible` 包住（超宽时省略而不是画到卡外），
        // 图标保持固定尺寸（它是识别符，不能省）。
        Row(
          children: [
            Expanded(child: const _MetricTitle('饮水')),
            Flexible(
              child: percent == null
                  ? const LfBadge.neutral(
                      '未设目标',
                      key: Key('dashboard-water-status'),
                    )
                  : LfBadge.mint(
                      '达标 $percent%',
                      key: const Key('dashboard-water-status'),
                    ),
            ),
            const SizedBox(width: LfDimens.spaceXSmall),
            // A `refinement.css:7 .water-icon{color:#54839F}`：图标是固定蓝
            // 字面量，与进度轨的 `--water`（[LfSemanticColors.water]）不同值。
            Icon(
              Icons.water_drop_outlined,
              size: 18,
              color: context.lfc.waterIcon,
            ),
          ],
        ),
        // A `.metric-value{margin-top:3px}`（在统一 7 间隔上再补 3）。
        const SizedBox(height: 3),
        // 一条记录都没有时**不写「0 ml」**：没记录 ≠ 喝了 0 毫升（既有
        // 诚实口径；A 的原型有内存示例数据，不适用）。
        //
        // **2026-10-16 用户**：「饮水与步数卡能不能都做成 250ml/1000ml 这种」
        // ——当前值与目标并进**同一条数值行**（原「目标 N ml」独立行下线），
        // 与水卡状态徽标（「达标 N%」）同族。录入入口不丢：整卡仍然是既有
        // 取量弹层的入口（`onTap`），原「+ 250 ml」按钮按用户要求下线。
        if (water.records.isEmpty)
          const _MetricValue(
            value: '暂无记录',
            valueKey: Key('dashboard-water-value'),
          )
        else if (target == null)
          _MetricValue(
            value: withThousandsSeparator(water.consumedMl.round()),
            unit: 'ml',
            valueKey: const Key('dashboard-water-value'),
          )
        else
          _MetricValue(
            value: withThousandsSeparator(water.consumedMl.round()),
            suffix: '/ ${withThousandsSeparator(target.round())} ml',
            suffixKey: const Key('dashboard-water-target-inline'),
            valueKey: const Key('dashboard-water-value'),
          ),
        const SizedBox(height: _metricTrackMarginTop),
        LfProgressBar(value: water.progress, color: c.water),
      ],
    );
  }
}

/// 步数卡（docs/29 §P9 需求 34）：读本机计步传感器，**三种态各自说实话**。
///
/// - **有数据**：数字 + 「目标 N 步」+ 「还差 N 步」；
/// - **无传感器**：沿用既有空态 Key `dashboard-steps-empty`，文案说清是
///   「这台设备没有计步传感器」——不是「你还没走过路」；
/// - **未授权**：只有右上角 `未授权` 徽标（docs/31 需求 48，用户原话
///   「其他的文字和按钮不需要，不要影响卡片已授权状态的高度和布局」）；
///   点卡片仍可申请权限（可见按钮没了，路径不能跟着没了）。
///
/// **三种都不写「0 步」**：0 步是一个具体事实（今天确实走了 0 步），而
/// 传感器读不到时我们没有这个事实。§6.2 裁决 9 的「不显示隐含目标」也仍然
/// 成立——目标值是设置里那一个（默认 10,000），不是从别处反推的；没有数据时
/// 一个字都不显示。
class StepsStatCard extends StatefulWidget {
  const StepsStatCard({super.key, this.repository, this.localDate, this.goal});

  final StepsRepository? repository;

  /// 今日日期；为 null 时不做落库（只有订阅/展示，用于未接线的测试）。
  final String? localDate;

  /// 今日目标步数。给死值用（测试/无仓储的调用点）；为 null 时由
  /// [repository] 的目标流供给（docs/32 §3 D11 需求 64）。
  final int? goal;

  @override
  State<StepsStatCard> createState() => _StepsStatCardState();
}

class _StepsStatCardState extends State<StepsStatCard>
    with WidgetsBindingObserver {
  /// 首次同步的读数（无数据时决定画哪个空态）。
  StepsReadingKind _kind = StepsReadingKind.loading;

  /// 正在申请权限（防连点：系统对话框只该弹一次）。
  bool _requesting = false;

  /// 目标流（**在 initState 建一次**，不在 build 里建：build 里现建流会在
  /// 每次重建时重新订阅，把手拖动/父级 setState 都会触发一次重订阅——
  /// T5 修「抽屉拖动抖动」时定的口径）。
  Stream<int>? _goalStream;

  /// 应用内开关的变化流（设置页关掉/打开后，这张卡立刻跟着换态）。
  StreamSubscription<bool>? _enabledSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindGoalStream();
    _bindEnabledStream();
    _sync();
  }

  @override
  void dispose() {
    _enabledSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(StepsStatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _bindGoalStream();
      _bindEnabledStream();
    }
    // 跨零点：`localDate` 换了，今日步数要从新的基线起算。
    if (oldWidget.localDate != widget.localDate) _sync();
  }

  void _bindGoalStream() {
    _goalStream = widget.goal == null
        ? widget.repository?.watchDailyGoal()
        : null;
  }

  void _bindEnabledStream() {
    _enabledSub?.cancel();
    _enabledSub = null;
    final repository = widget.repository;
    if (repository == null) return;
    // 订阅会**立刻**推一次当前值：那一次不当作「变化」，否则每次建卡都多
    // 读一次传感器（既有「授权后重读」用例会数到多余的一次 read）。
    var first = true;
    _enabledSub = repository.watchEnabled().listen((_) {
      if (first) {
        first = false;
        return;
      }
      if (mounted) unawaited(_sync());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 前台才读（需求 34 的隐私/电量口径）：回到前台重新采一次，
    // 后台不断言任何事。
    //
    // 2026-10-23 用户：「授权后读不到步数」——用户多半是**去系统设置授完
    // 权再回来**，而首帧读数在原生 2s 窗口里没等到事件（`no_event`）是
    // 真机偶发。回前台改走带重试的路径（有界 2 次），不让用户看到一张
    // 「这次没读到」却点半天没反应的卡。
    if (state == AppLifecycleState.resumed) unawaited(_syncWithRetry());
  }

  /// 授权完成后遇到「这次没读到」时，最多再读几次（有界重试）。
  static const int syncRetryLimit = 2;

  /// 两次重读之间的等待（原生 read 的窗口是 2s，留一点余量）。
  static const Duration syncRetryDelay = Duration(seconds: 3);

  /// 采一次步数并落库。**不 await 出结果给界面**：界面订阅
  /// [StepsRepository.watchDate]，写库自然会推上来。
  Future<void> _sync() async {
    final repository = widget.repository;
    final localDate = widget.localDate;
    if (repository == null) {
      if (mounted) setState(() => _kind = StepsReadingKind.noSensor);
      return;
    }
    // **2026-10-16（数据卫生）**：没有日期就没有「哪一天」这件事——原先把
    // `localDate ?? ''` 传下去，会往步数表写一行 `local_date = ''`（回头
    // 真同步那天还会撞 UNIQUE）。没有日期时一个字都不写。
    if (localDate == null) return;
    final result = await repository.syncToday(localDate);
    if (!mounted) return;
    setState(() => _kind = result.availability.toReadKind());
  }

  /// 授权成功后**就地有界重读**（2026-10-16 用户：「授权后仍识别不了」）。
  ///
  /// 原生 read 的窗口只有 2s，`TYPE_STEP_COUNTER` 首帧偶发落在窗口之外
  /// （`no_event`）——刚关掉系统授权对话框时更容易撞上。只对「这次没读到」
  /// 重试（`noSensor` 重试也没意义），每次间隔 [syncRetryDelay]、最多
  /// [syncRetryLimit] 次，组件卸载即停。
  Future<void> _syncWithRetry() async {
    await _sync();
    for (var attempt = 0; attempt < syncRetryLimit; attempt++) {
      if (!mounted || _kind != StepsReadingKind.noReading) return;
      await Future<void>.delayed(syncRetryDelay);
      if (!mounted) return;
      await _sync();
    }
  }

  Future<void> _requestPermission() async {
    final repository = widget.repository;
    if (repository == null || _requesting) return;
    setState(() => _requesting = true);
    final granted = await repository.requestPermission();
    if (!mounted) return;
    setState(() => _requesting = false);
    // 刚授权成功时立刻采一次（并做有界重读），用户不必等下一个生命周期点。
    if (!granted) return;
    await _syncWithRetry();
  }

  @override
  Widget build(BuildContext context) {
    final injected = widget.goal;
    if (injected != null) return _buildWithGoal(injected);
    final goalStream = _goalStream;
    if (goalStream == null) {
      return _buildWithGoal(StepsRepository.defaultDailyGoal);
    }
    return StreamBuilder<int>(
      stream: goalStream,
      initialData: StepsRepository.defaultDailyGoal,
      builder: (context, snapshot) =>
          _buildWithGoal(snapshot.data ?? StepsRepository.defaultDailyGoal),
    );
  }

  Widget _buildWithGoal(int goal) {
    final mint = LfColors.mint(Theme.of(context).brightness);
    final repository = widget.repository;
    final localDate = widget.localDate;
    // 未接线或已判定为「没有传感器/没读到」：诚实空态，不订阅数据库。
    if (repository == null || localDate == null) {
      return _StepsCardShell(
        badge: null,
        body: _StepsPlaceholder(kind: StepsReadingKind.noSensor),
        progress: 0,
        onTap: null,
        semanticLabel: '步数，暂无记录',
      );
    }

    return StreamBuilder<int?>(
      stream: repository.watchDate(localDate),
      builder: (context, snapshot) {
        final steps = snapshot.data;
        // 有数据优先；没有数据才看本次读数给了哪种「没有」。
        if (steps != null) {
          return _StepsCardShell(
            // 2026-10-16 用户：「步数也加『达标 n%』标签」＋「右上角的图标
            // 没有了」——状态位＝**达标徽标 + 步行图标**（图标在徽标右侧、
            // 贴卡右缘，与水卡的「徽标 + 水滴图标」逐像素同构）。
            badge: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LfBadge.mint(
                  '达标 ${_stepsPercent(steps, goal)}%',
                  key: const Key('dashboard-steps-status'),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Icon(Icons.directions_walk, size: 18, color: mint.tone(600)),
              ],
            ),
            body: _StepsValue(steps: steps, goal: goal),
            // 目标由注入方/设置给出，理论上不会 ≤ 0；真给了也不画成「无限」。
            progress: goal <= 0 ? 0 : steps / goal,
            onTap: null,
            semanticLabel: '步数，今天 $steps 步',
            mint: mint,
          );
        }
        if (_kind == StepsReadingKind.disabled) {
          // 应用内开关关闭（2026-10-23 用户：「步数授权取消不掉」）：
          // 不读、不写、不申请；重新开启在设置页的同一张弹层里。
          return _StepsCardShell(
            badge: const LfBadge.neutral('已关闭'),
            body: const _StepsPlaceholder(kind: StepsReadingKind.disabled),
            progress: 0,
            onTap: null,
            semanticLabel: '步数，应用内已停止读取',
            mint: mint,
          );
        }
        if (_kind == StepsReadingKind.denied) {
          // 需求 48（docs/31）：未授权 = 只有右上角徽标。「—」/说明行/
          // 「去设置」全部退场；骨架与已授权态**逐像素同构**——正文高度由
          // [_StepsDeniedBody] 占住（同一组件藏形不缩格）。可见按钮没了，
          // 申请路径不能跟着没：整卡点击仍然申请（语义如实播报）。
          return _StepsCardShell(
            badge: const LfBadge.honey('未授权'),
            body: _StepsDeniedBody(goal: goal),
            progress: 0,
            onTap: _requesting ? null : _requestPermission,
            semanticLabel: '步数，未授权，点击申请',
            mint: mint,
          );
        }
        return _StepsCardShell(
          badge: null,
          body: _StepsPlaceholder(kind: _kind),
          progress: 0,
          // 「这次没读到」是可以自己救回来的：点一下重读一次（不是死路）。
          onTap: _kind == StepsReadingKind.noReading ? _sync : null,
          semanticLabel: _kind == StepsReadingKind.noReading
              ? '步数，这次没读到，点击重试'
              : '步数，暂无记录',
          mint: mint,
        );
      },
    );
  }
}

/// 一次读数在界面上的分类（与 [StepsAvailability] 一一对应，但**多一个
/// loading**：首帧还没读到之前不能先说「没有传感器」）。
enum StepsReadingKind {
  loading,
  available,
  noSensor,
  denied,
  noReading,
  disabled,
}

extension on StepsAvailability {
  StepsReadingKind toReadKind() => switch (this) {
    StepsAvailability.available => StepsReadingKind.available,
    StepsAvailability.noSensor => StepsReadingKind.noSensor,
    StepsAvailability.denied => StepsReadingKind.denied,
    StepsAvailability.noReading => StepsReadingKind.noReading,
    StepsAvailability.disabled => StepsReadingKind.disabled,
  };
}

/// 步数达标百分比（与水卡的 `WaterSummary.percent` 同口径：四舍五入取整）。
/// 目标 ≤ 0 时返回 0——不画成「无限」（`_buildWithGoal` 已把这种目标当 0 进度）。
int _stepsPercent(int steps, int goal) {
  if (goal <= 0) return 0;
  return (steps / goal * 100).round();
}

/// 卡片骨架（标题行 + 内容 + 进度条），各种态共用，保证几何一致。
class _StepsCardShell extends StatelessWidget {
  const _StepsCardShell({
    required this.badge,
    required this.body,
    required this.progress,
    required this.onTap,
    required this.semanticLabel,
    this.mint,
  });

  final Widget? badge;
  final Widget body;
  final double progress;
  final VoidCallback? onTap;

  /// 读屏标签（由调用方按当前态给，**不在这里猜**）。
  final String semanticLabel;

  /// 强调色阶（取 mint ramp 的具体档位）。
  final TonalRamp? mint;

  @override
  Widget build(BuildContext context) {
    final accent = mint ?? LfColors.mint(Theme.of(context).brightness);
    // A `.metric-top .section-title{font-size:14px}` + 标题 12px 的旧形态在此
    // 统一为 14；状态位（图标或 pill）落同一行。
    final trailing = badge;
    return _MetricCardShell(
      cardKey: const Key('dashboard-stat-steps'),
      onTap: onTap,
      // 语义标签描述卡内真实内容（读屏不该听到「暂无记录」而卡上写着 8,432）。
      semanticLabel: semanticLabel,
      children: [
        // 标题行**恒高** [stepsTitleRowHeight]（= 未授权徽标的盒高）：
        // trailing 可能是「未授权」徽标（盒高 23）或步行图标（18）或空，
        // 行高会跟着它变 ⇒ 卡高也跟着变。平时两张卡谁都不高过饮水卡时看
        // 不出来；一旦步骤卡成为行里最高的一张（本片按裁决 R11 加了
        // 「查看详情」行后就是如此），差值立刻露头（实测未授权 219 vs
        // 有数据 217，需求 48 的「同高同构」当场变红）。钉住行高即钉住契约。
        SizedBox(
          height: stepsTitleRowHeight,
          child: Row(
            children: [
              const Expanded(child: _MetricTitle('步数')),
              if (trailing != null) Center(child: trailing),
            ],
          ),
        ),
        // 与饮水卡逐行对齐（用户要求两卡内容对齐）：标题行 23 之后统一切
        // `_metricGap`，数值行与进度条之间也切 `_metricGap`。
        const SizedBox(height: _metricGap),
        body,
        const SizedBox(height: _metricGap),
        // 进度条留 0：没有数据时画任何长度都是在编事实。
        LfProgressBar(
          value: progress,
          color: progress > 0 ? accent.tone(500) : null,
        ),
        // 2026-10-16 用户要求删掉「查看详情」行（上一个裁决 R11 作废）：
        // 卡底不再有链接格；步数目标的差额行由 [_StepsValue] 自己给出。
      ],
    );
  }
}

/// 有数据态：`8,432 步` +「目标 10,000 步」「还差 1,568 步」（目标值是设置里
/// 的那条，未设置时才是 10,000——docs/32 §3 D11）。
class _StepsValue extends StatelessWidget {
  const _StepsValue({required this.steps, required this.goal});

  final int steps;
  final int goal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 2026-10-16 用户：与水卡同款的一行式「当前 / 目标 步」；原
        // 「目标 N 步」独立行下线（差额行保留——它给的是下一步该走多少）。
        _MetricValue(
          value: withThousandsSeparator(steps),
          suffix: '/ ${withThousandsSeparator(goal)} 步',
          suffixKey: const Key('dashboard-steps-target-inline'),
          valueKey: const Key('dashboard-steps-value'),
        ),
        // 2026-10-16 用户：「步数卡片删除『还差 n 步』」。达成度由右上角
        // 「达标 N%」徽标表达；卡内三行（标题 / 数值 / 进度条）与水卡对齐。
      ],
    );
  }
}

/// 没有数据时的三种说明（都不写「0 步」）。
class _StepsPlaceholder extends StatelessWidget {
  const _StepsPlaceholder({required this.kind});

  final StepsReadingKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final hint = switch (kind) {
      // 首帧：还不能断言任何事，用与文字同色的占位，不说「没有」。
      StepsReadingKind.loading => '正在读取…',
      StepsReadingKind.noSensor => '这台设备没有计步传感器',
      StepsReadingKind.noReading => '这次没读到步数',
      StepsReadingKind.denied => '未授权',
      StepsReadingKind.disabled => '应用内已停止读取（在设置页「步数与身体活动」里重新开启）',
      StepsReadingKind.available => '暂无记录',
    };
    return _StepsHint(
      key: const Key('dashboard-steps-empty'),
      headline: kind == StepsReadingKind.disabled ? '已关闭' : '暂无记录',
      hint: hint,
      style: kind == StepsReadingKind.available ? null : c.mutedForeground,
    );
  }
}

/// 未授权态的内容占位（docs/31 需求 48）：与有数据态的 [_StepsValue] 是
/// **同一个组件**（同字号/同间距/同目标值），`Visibility(maintainSize)`
/// 藏形不缩格 ⇒ 卡高与已授权态完全一致；外层 `ExcludeSemantics` 保证读屏
/// 听不到「0 / 目标 步」——未授权时 0 步不是事实（§6.2 裁决 9）。
class _StepsDeniedBody extends StatelessWidget {
  const _StepsDeniedBody({required this.goal});

  final int goal;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Visibility(
        visible: false,
        maintainSize: true,
        maintainState: true,
        maintainAnimation: true,
        child: _StepsValue(steps: 0, goal: goal),
      ),
    );
  }
}

/// 空/提示态的统一排版：一行 `headline` + 一行 `hint`。
class _StepsHint extends StatelessWidget {
  const _StepsHint({
    super.key,
    required this.headline,
    required this.hint,
    this.style,
  });

  final String headline;
  final String hint;
  final Color? style;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          headline,
          key: const Key('dashboard-steps-headline'),
          style: LfText.displayLarge.copyWith(color: style ?? c.cardForeground),
        ),
        const SizedBox(height: LfDimens.spaceXSmall),
        Text(hint, style: LfText.caption.copyWith(color: c.mutedForeground)),
      ],
    );
  }
}
