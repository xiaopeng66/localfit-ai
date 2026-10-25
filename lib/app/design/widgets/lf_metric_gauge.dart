/// 健康数据的两张图形卡（docs/29 §P2 / 裁决 D10；2026-10-16 用户删掉第三张
/// 饮水进度环 ⇒ 三件变两件，见下）。
/// **为什么是分开的件而不是一根条**：D10 的原话——「BMI 有公认分档，BMR 是
/// 单值目标，套同一根条会伪造语义」。两件各说各的一件事：
/// - [LfBandedScaleGauge]：**分档刻度尺**——把一个值放到若干**有名字的档**里
///   （BMI 的偏瘦/正常/超重/肥胖），指示器落在轴上的真实位置。
/// - [LfBandTargetGauge]：**区间指示**——一个值 + 一段**目标区间**，回答
///   「值在区间的哪一边」。没有区间就不画（无从比较 ≠ 在中间）。
///
/// （原第三件 `LfProgressRingGauge`（饮水达成环）随水分卡一起删除：它在
/// 生产上没有调用方了，按死代码纪律下线；饮水达成度现在由今日页饮水卡的
/// 「已饮 / 目标 + 达标 N%」表达。）
///
/// **本文件是纯画法**：档位口径（谁算正常、边界在哪）在
/// `lib/features/settings/domain/health_metric_bands.dart`，调用方把分好档的
/// 结果传进来。这样设计层不认识「BMI」这类业务词，业务层也不用重画一遍。
/// 颜色只用既有 token（`LfColors` 语义色 + neutral/mint ramp），不新造色。
///
/// 空态一律「不给假档」：值为空 ⇒ 轨道全灰、无指示器、**不放档位徽标**，
/// 由调用方传 `valueLabel: '—'`。
library;

import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 语义色调：档位/位置 → 设计系统的既有色 token。
///
/// 只有四个角色（灰/绿/橙/红），映射写在 [gaugeToneColors] 一处：
/// neutral=中性（无好坏），success=正常，warning=需注意，danger=超标。
enum LfGaugeTone { neutral, success, warning, danger }

/// (底色, 文字色, 轨道色)。
///
/// 为什么轨道色要单列一个：`content` 是**在 container 上写字的颜色**，
/// 而轨道是**填色**——两者对 warning 档恰好不是同一个 token。设备实测
/// （2026-10-05，360dp debug 包）抓到过：轨道直接用 `content`，超重段就画成
/// 近黑色，四段语言「灰/绿/橙/红」里的橙整个丢了。所以：
/// - `container`/`content` 给徽标（浅底 + 深字，可读）；
/// - `track` 给刻度尺/进度条（数据色，用 `macro_bar.dart` 同一族的数据色）。
///
/// 危险档没有现成容器色，用 `error` 低透明度做底色（仍是同一 token，只是叠加
/// 了透明度），文字与轨道用 `error` 本体。
({Color container, Color content, Color track}) gaugeToneColors(
  BuildContext context,
  LfGaugeTone tone,
) {
  final c = context.lf;
  final brightness = Theme.of(context).brightness;
  final mint = LfColors.mint(brightness);
  return switch (tone) {
    LfGaugeTone.neutral => (
      container: c.muted,
      content: c.mutedForeground,
      track: c.mutedForeground,
    ),
    LfGaugeTone.success => (
      container: mint.tone(100),
      content: LfColors.mintText(brightness),
      track: LfColors.mintText(brightness),
    ),
    LfGaugeTone.warning => (
      container: c.carbs100,
      content: c.cardForeground,
      track: c.carbs,
    ),
    LfGaugeTone.danger => (
      container: c.error.withValues(alpha: 0.14),
      content: c.error,
      track: c.error,
    ),
  };
}

/// 刻度尺上的一档：`[lowerBound, upperBound)`，最后一档用 `null` 表示「开到轴顶」。
class LfGaugeBand {
  const LfGaugeBand({
    required this.upperBound,
    required this.label,
    required this.tone,
  });

  final double? upperBound;
  final String label;
  final LfGaugeTone tone;
}

/// 分档刻度尺（变体 1，BMI 用）。
///
/// 轴 = `[axisMin, axisMax]`，档位宽度**按真实数值区间成比例**（不是等宽：
/// 等宽会把「18.5–24 有 5.5 个点宽」和「≥28 无上界」画成一样长，读起来是假的）。
/// 档名贴在各段下面，档界数字贴在轴上的真实位置。
class LfBandedScaleGauge extends StatelessWidget {
  const LfBandedScaleGauge({
    super.key,
    required this.title,
    required this.valueLabel,
    required this.axisMin,
    required this.axisMax,
    required this.bands,
    this.badgeLabel,
    this.badgeTone = LfGaugeTone.neutral,
    this.marker,
  });

  final String title;
  final String valueLabel;

  /// 指示器位置（真实数值，如 22.6）。null = 空态：不画指示器、轨道全灰。
  final double? marker;

  final double axisMin;
  final double axisMax;

  /// 从左到右的档位；最后一档 `upperBound` 传 null。
  final List<LfGaugeBand> bands;

  final String? badgeLabel;
  final LfGaugeTone badgeTone;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final neutral = LfColors.neutral(brightness);
    final span = (axisMax - axisMin).abs() < 1e-9 ? 1.0 : axisMax - axisMin;
    double pos(double v) => ((v - axisMin) / span).clamp(0.0, 1.0);
    final empty = marker == null;

    final edges = <double>[axisMin];
    for (final band in bands) {
      edges.add(band.upperBound ?? axisMax);
    }

    return _MetricCard(
      title: title,
      badgeLabel: badgeLabel,
      badgeTone: badgeTone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ValueRow(value: valueLabel),
          const SizedBox(height: LfDimens.spaceSmallPlus),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return SizedBox(
                height: 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                      child: Row(
                        children: [
                          for (var i = 0; i < bands.length; i++)
                            Expanded(
                              flex: _flexFor(edges[i], edges[i + 1], span),
                              child: ColoredBox(
                                // 段色取 `track`（数据色），不是 `content`
                                // （那是徽标上写字的颜色，见 gaugeToneColors）。
                                color: empty
                                    ? c.muted
                                    : gaugeToneColors(
                                        context,
                                        bands[i].tone,
                                      ).track,
                                child: const SizedBox.expand(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!empty)
                      Positioned(
                        // 白描边竖条压在档位色上，明暗两态都看得见；夹在两端
                        // 之内，值超界时贴边而不是画到卡外。
                        left: pos(marker!) * width - 2,
                        top: -3,
                        child: Container(
                          // 空态**没有**这枚指示器（不指一个不存在的值），
                          // key 就是这条契约的抓手。
                          key: const Key('lf-gauge-marker'),
                          width: 4,
                          height: 14,
                          decoration: BoxDecoration(
                            color: c.foreground,
                            borderRadius: BorderRadius.circular(
                              LfDimens.radiusFull,
                            ),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: LfDimens.spaceXSmall),
          // 档界数字：贴在轴上的真实位置（只标中间几档的边界，轴两端不标——
          // 15/35 不是判断依据，标了反而抢视线）。
          //
          // 位置怎么算：行左沿起 `pos(档界) × 行宽` 处（行宽就是上面色条的宽度）
          // 放下数字的**左沿**，再向左挪半个字宽（`FractionalTranslation` 是
          // 相对自身尺寸的比例位移，所以不需要预先知道字有多宽）⇒ 数字中心
          // 正落在档界上。**不能用 `Align(Alignment(x, 0))`**：那是往「剩余
          // 空间」按比例摆（x 只分配减掉字宽之后的空间），字越宽越向中间挤
          // ——设备实测 2.0× 下三档数字跨度比应有值窄 19px。
          // 行高仍由文字自己撑开（1.0× ≈14px、2.0× ≈28px），不写死。
          if (!empty)
            LayoutBuilder(
              builder: (context, constraints) => SizedBox(
                // 撑满行宽：Stack 本来会缩到内容宽度，那样「相对行宽的比例位置」
                // 就没有一个稳定的基准了（测试也拿不到可对账的行宽）。
                key: const Key('lf-gauge-ticks'),
                width: double.infinity,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < bands.length - 1; i++)
                      Padding(
                        padding: EdgeInsets.only(
                          left: pos(edges[i + 1]) * constraints.maxWidth,
                        ),
                        child: FractionalTranslation(
                          translation: const Offset(-0.5, 0),
                          child: Text(
                            _trimNumber(edges[i + 1]),
                            maxLines: 1,
                            softWrap: false,
                            style: LfText.micro.copyWith(
                              color: c.mutedForeground,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: LfDimens.spaceMicro),
          // 档名：与档位同比宽，居中贴在各段下方（尺子的「刻度」部分）。
          Row(
            children: [
              for (var i = 0; i < bands.length; i++)
                Expanded(
                  flex: _flexFor(edges[i], edges[i + 1], span),
                  child: Text(
                    bands[i].label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: LfText.micro.copyWith(
                      color: empty ? neutral.tone(400) : c.mutedForeground,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 档段权重：`Expanded.flex` 只能取整数，按 0.1% 精度折算（BMI 轴 20 个点，
  /// 精度绰绰有余）。
  static int _flexFor(double lower, double upper, double span) {
    final flex = ((upper - lower) / span * 1000).round();
    return flex < 1 ? 1 : flex;
  }

  /// 轴上的数字：整数不印小数点（18.5 保留，24 / 28 印成整数）。
  static String _trimNumber(double value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}

/// 区间指示（变体 2，基础代谢率用）。
///
/// 一条轨 + 一段**目标区间** + 一个值标记；轴范围由值和区间自动撑开
/// （各让 25% 留白），所以标记永远看得见。区间缺失 ⇒ 整块图形不画：
/// 没有参照物的一根条不传达任何信息。
class LfBandTargetGauge extends StatelessWidget {
  const LfBandTargetGauge({
    super.key,
    required this.title,
    required this.valueLabel,
    this.unit,
    this.badgeLabel,
    this.badgeTone = LfGaugeTone.neutral,
    this.marker,
    this.targetMin,
    this.targetMax,
    this.targetLabel,
  });

  final String title;
  final String valueLabel;
  final String? unit;
  final String? badgeLabel;
  final LfGaugeTone badgeTone;

  /// 值（如 1,480）；null = 空态。
  final double? marker;

  /// 目标区间；任一为 null（或区间反向）⇒ 不画图形。
  final double? targetMin;
  final double? targetMax;

  /// 区间下方的说明（如「目标 1,900–2,100」），只在画区间时显示。
  final String? targetLabel;

  bool get _hasBand {
    final lo = targetMin;
    final hi = targetMax;
    return marker != null && lo != null && hi != null && hi >= lo;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final mint = LfColors.mint(brightness);
    final hasBand = _hasBand;

    Widget? band;
    if (hasBand) {
      final lo = targetMin!;
      final hi = targetMax!;
      final value = marker!;
      final rawLow = value < lo ? value : lo;
      final rawHigh = value > hi ? value : hi;
      final pad = (rawHigh - rawLow) * 0.25;
      final safePad = pad <= 0 ? (rawHigh.abs() * 0.1 + 1) : pad;
      final axisMin = rawLow - safePad;
      final axisMax = rawHigh + safePad;
      final span = axisMax - axisMin;
      double pos(double v) => ((v - axisMin) / span).clamp(0.0, 1.0);
      band = Padding(
        padding: const EdgeInsets.only(top: LfDimens.spaceSmallPlus),
        child: SizedBox(
          height: 16,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      key: const Key('lf-gauge-band-track'),
                      height: 8,
                      decoration: BoxDecoration(
                        color: c.muted,
                        borderRadius: BorderRadius.circular(
                          LfDimens.radiusFull,
                        ),
                      ),
                    ),
                  ),
                  // 区间填充必须与灰轨**同轴**。容器高 16，轨走
                  // `Align(centerLeft)` ⇒ 占 y 4..12；填充是以 `Positioned`
                  // 摆的，得显式写 `top: (16 - 8) / 2` 才落在同一条线上。
                  // 写成 `top: 0` 会高出 4dp —— 2026-10-08 用户走查点名的
                  // 「绿色填充和进度条有偏移，偏上了一点」就是这个。
                  // 几何由 `health_metrics_graphic_test.dart` 的
                  // 「区间填充与灰轨同轴」一条钉住。
                  Positioned(
                    key: const Key('lf-gauge-band-fill'),
                    left: pos(lo) * width,
                    width: ((pos(hi) - pos(lo)) * width).clamp(6.0, width),
                    top: (16 - 8) / 2,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: mint.tone(200),
                        border: Border.all(color: mint.tone(500)),
                        borderRadius: BorderRadius.circular(
                          LfDimens.radiusFull,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: pos(value) * width - 8,
                    top: 0,
                    child: Container(
                      // 与分档刻度尺同一条契约：没有区间/没有值就整块不画，
                      // 这枚标记点也不会存在（key 供「不给假位置」断言用）。
                      key: const Key('lf-gauge-value-dot'),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: c.foreground,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.surface,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    return _MetricCard(
      title: title,
      badgeLabel: badgeLabel,
      badgeTone: badgeTone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ValueRow(value: valueLabel, unit: unit),
          if (band != null) ...<Widget>[
            band,
            if (targetLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: LfDimens.spaceXSmall),
                child: Align(
                  alignment: Alignment.center,
                  // 2.0× 字号下这句比卡片内宽还长（实测 385 > 332），
                  // `softWrap: false` 的默认结局是**静默裁掉尾巴**。整句等比
                  // 缩到装得下：区间说明必须完整可读，它是这块图形的判据。
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      targetLabel!,
                      maxLines: 1,
                      softWrap: false,
                      style: LfText.micro.copyWith(color: c.mutedForeground),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 卡片外壳（三件共用）：标题 +（可选）档位徽标 + 内容。
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.child,
    this.badgeLabel,
    this.badgeTone = LfGaugeTone.neutral,
  });

  final String title;
  final Widget child;
  final String? badgeLabel;
  final LfGaugeTone badgeTone;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final badge = badgeLabel;
    return Container(
      padding: const EdgeInsets.all(LfDimens.spaceMedium),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
        border: Border.all(color: c.border),
        boxShadow: LfShadows.surface(isLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  style: LfText.label.copyWith(color: c.mutedForeground),
                ),
              ),
              if (badge != null) _ToneChip(label: badge, tone: badgeTone),
            ],
          ),
          child,
        ],
      ),
    );
  }
}

/// 档位徽标（灰/绿/橙/红四色，取自既有 token，见 [gaugeToneColors]）。
class _ToneChip extends StatelessWidget {
  const _ToneChip({required this.label, required this.tone});

  final String label;
  final LfGaugeTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = gaugeToneColors(context, tone);
    return Container(
      // 徽标只在调用方**判出了档位**时才存在（空态没有这枚 chip），
      // key 供「缺数据不给假档位」断言按卡取文字。
      key: const Key('lf-gauge-badge'),
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceSmall,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colors.container,
        borderRadius: BorderRadius.circular(LfDimens.radiusFull),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: LfText.label.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.content,
        ),
      ),
    );
  }
}

/// 值行：大数字（强调色）+ 小一号单位。整行 `FittedBox` 兜底，极端字号下
/// 等比缩小也不折行、不出界（与 `LfStatTile` 同一套处理）。
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.value, this.unit});

  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              // 刻度尺上会有和值**一模一样**的数字（18.5 既是 BMI 值也是档界），
              // 所以「值是哪个」必须能单独取到，不能靠 find.text 碰运气。
              key: const Key('lf-gauge-value'),
              maxLines: 1,
              softWrap: false,
              style: LfText.headline.copyWith(
                color: c.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: LfDimens.spaceXSmall),
              Text(
                unit!,
                maxLines: 1,
                softWrap: false,
                style: LfText.micro.copyWith(color: c.mutedForeground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
