import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/number_format.dart';
import 'package:localfit_ai/app/design/widgets/lf_ring_painter.dart';

/// 新设计热量圆环（docs/21 §3.2 **重写**；2026-10-14 按 Round7 A 中心文案调整）：
/// 完整圆环 120×120，r=52，线宽 10；轨道 = muted，进度 = primary，
/// `stroke-linecap=round`，从 -90° 起。
///
/// 中心三段文字（A `ring()` 的 `.data-ring-center`）：`b 26px` 数值 /
/// 11px muted「已摄入 kcal」/ 11px w600 mint-600 百分比。A 的中心只有
/// 「值 + 标签」两行，**目标移到了卡脚注**（`.energy-foot` 的「目标 N kcal」）
/// 与「还可摄入 N kcal」；百分比保留第三行（阶段 2 D6：现有可见事实，
/// 含超目标时的未截断值，不因换图丢掉）。无目标时不画百分比（没有分母）。
/// 旧件的宏量内段、拖拽明细、辉光**全部移除**（旧半圆件 `CalorieRing`
/// 保留到今日页重建完成后删除）。
///
/// [keyPrefix] 给三段文字挂锚点（`<prefix>-consumed` / `-percent`）。
/// docs/21 §5.1 要求今日页圆环中心各段文字可定位（`dashboard-ring-consumed`
/// 等），但取色/布局是页面无关的，所以锚点由调用方注入；不传则不挂键。
class LfCalorieRing extends StatelessWidget {
  const LfCalorieRing({
    super.key,
    required this.consumedKcal,
    required this.targetKcal,
    this.targetMinKcal,
    this.keyPrefix,
  });

  final int consumedKcal;
  final int targetKcal;

  /// 目标区间**下限**（需求 1，2026-10-25）。非 null 且 > 0 时环画**区间带 +
  /// 指针**（带 = 目标区间、指针 = 当前位置），不再是单值进度弧。
  ///
  /// 刻度口径（2026-10-31 用户三轮定稿，原话：「一个圆的后边部分是一个浅色
  /// 的区间，然后已摄入是深色的进度，超出以后就变色警告」）：整圈 = `0 → 上限`
  /// 的线性刻度；浅色宽带 = 区间在**环的后段的真实位置**（`min/max → 1.0`）；
  /// 进度弧 = **深色**（brandStrong）；超过上限整弧转暖色。无区间时同刻度，
  /// 满环 = 达标。
  final int? targetMinKcal;

  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final track = context.lfc.ringTrack;
    final target = targetKcal > 0 ? targetKcal : 0;
    final bandMin = targetMinKcal;
    final over = target > 0 && consumedKcal > target;
    // 区间的「带」只在有上下限且上限 > 0 时成立。
    final hasBand = target > 0 && bandMin != null && bandMin > 0;
    final ratio = target > 0 ? (consumedKcal / target).clamp(0.0, 1.0) : 0.0;
    final percent = target > 0 ? ((consumedKcal / target) * 100).round() : 0;
    final bandStart = hasBand ? (bandMin / target).clamp(0.0, 1.0) : null;
    final bandEnd = hasBand ? 1.0 : null;
    // 超上界 ⇒ 带变暖色（浅绿 = 区间位置，暖 = 已破上限）。
    final bandColor = hasBand ? (over ? c.warning : c.primary) : null;
    return SizedBox(
      key: const Key('lf-calorie-ring'),
      width: LfDimens.calorieRingSize,
      height: LfDimens.calorieRingSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(LfDimens.calorieRingSize),
            painter: LfRingPainter(
              track: track,
              // 【2026-10-31 用户定稿】进度弧 = 深色（brandStrong），超上限转暖。
              progress: over
                  ? c.warning
                  : LfColors.brandStrong(Theme.of(context).brightness),
              ratio: ratio,
              radius: LfDimens.calorieRingRadius,
              stroke: LfDimens.calorieRingStroke,
              // 需求 1：有区间 ⇒ 浅色带画在环后段真实位置（与环同宽）。
              bandStart: bandStart,
              bandEnd: bandEnd,
              bandColor: bandColor,
              // 【2026-10-31 用户：浅带与环同宽 + 不要多余的点】指针（圆钮）
              // 整件退役——深色弧的圆头线帽本身就是尖端标记，带与弧同宽后
              // 圆钮只会突兀地鼓出环外。
              pointerRatio: null,
            ),
          ),
          // 三段文字对外是一个语义节点（旧半圆件的可访问性契约在取代件上
          // 恢复）：读屏一次得到「完成度 N% · 已摄入 X kcal」，而不是把三个
          // 数字当三段无关文本依次念。
          //
          // `FittedBox.scaleDown`：圆环几何是设计稿定死的 120×120
          // （docs/21 §3.2），但中心三行（数值/标签/百分比）会被字号放大
          // 撑破——2.0× 字号下窄屏暴力测试抓到这里纵向溢出 25dp。
          // 与其裁掉看不见的数字，不如整体等比缩进框内：数字仍然完整可见。
          // 1.0× 下内容本来就在框内，`scaleDown` 不缩放。
          //
          // 上限取**内孔**而不是 120dp 外框：只按外框缩放时，2.0× 真机上最
          // 宽的一行会横跨到轨道描边上（撑满框宽但压住了环）。
          Semantics(
            container: true,
            label: targetKcal > 0
                ? (hasBand
                      ? '目标区间 ${withThousandsSeparator(bandMin)}'
                            ' 到 ${withThousandsSeparator(targetKcal)} kcal，'
                            '完成度 $percent%'
                      : '完成度 $percent%')
                : '无热量目标',
            value: '${withThousandsSeparator(consumedKcal)} kcal',
            child: ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: LfDimens.calorieRingInnerSize,
                  maxHeight: LfDimens.calorieRingInnerSize,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        // A 的环心值是 `format(total.kcal)`（`toLocaleString`
                        // ⇒ 四位起带千分位）；数值语义不变（调用方已取整）。
                        withThousandsSeparator(consumedKcal),
                        key: keyPrefix == null
                            ? null
                            : Key('$keyPrefix-consumed'),
                        style: LfText.displayXLarge.copyWith(
                          color: c.foreground,
                        ),
                      ),
                      Text(
                        '已摄入 kcal',
                        style: LfText.label.copyWith(color: c.mutedForeground),
                      ),
                      if (targetKcal > 0)
                        Text(
                          // 需求 1：超上界时第三行如实说「超上限 X」
                          // （`超了` 这件事比「完成度 118%」更该被一眼看到）。
                          over
                              ? '超上限 ${withThousandsSeparator((consumedKcal - target).round())}'
                              : '$percent%',
                          key: keyPrefix == null
                              ? null
                              : Key('$keyPrefix-percent'),
                          style: LfText.label.copyWith(
                            color: over
                                ? c.warningText
                                : LfColors.mint(Theme.of(context).brightness)
                                      .tone(600),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
