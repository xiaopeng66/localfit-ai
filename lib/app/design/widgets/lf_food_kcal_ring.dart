import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_ring_painter.dart';

/// 食物卡右上角的「能量密度环」（docs/28 §5.1 N13）——44dp 迷你环 + 中心数字。
///
/// 口径**必须诚实**：刻度是**能量密度 0–1000 kcal/100g**（[kFoodDensityFullScaleKcal]
/// 单源），不是「相对每日目标」——那会把「每 100 克」与「一餐预算」两个单位
/// 混进一个环里（计划里点名不采用）。环下的 `每 100g` 与 `Semantics` 都照这个
/// 口径说，读屏得到「每 100 克 n 千卡，约为能量密度满刻度的 x%」。
///
/// 热量缺失（目录条目常见）时中心写 `—`、环为空、不画比例，也**不编 0**。
///
/// 与今日页 [LfCalorieRing] 的关系：同一段弧线数学（[LfRingPainter]），不同
/// 口径与尺寸。计划里写的是「`LfCaloriesRing` 的小尺寸档」，实现另起一件
/// 独立组件——名字只差一个字母（Calorie/Calories）的两件组件在调用点上分不清，
/// 而两者的入参语义没有任何重叠部分可以合并。
class LfFoodKcalRing extends StatelessWidget {
  const LfFoodKcalRing({
    super.key,
    this.kcalPer100g,
    this.keyPrefix,
    this.size = LfDimens.foodKcalRingSize,
    this.stroke = LfDimens.foodKcalRingStroke,
  });

  /// null = 该来源没有热量数据。
  final double? kcalPer100g;

  /// 给中心数字挂锚点（`<prefix>-kcal`），供测试与走查定位。
  final String? keyPrefix;

  /// 环外径：食物卡用 44dp 档（默认），食物详情弹层用大档
  /// （[LfDimens.foodKcalRingLargeSize]，2026-10-06 起 56dp）。
  final double size;

  /// 描边宽度。大档配粗描边（6dp），否则 56dp 的环看起来像细线框。
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final kcal = kcalPer100g;
    final ratio = kcal == null
        ? 0.0
        : (kcal / kFoodDensityFullScaleKcal).clamp(0.0, 1.0);
    final percent = (ratio * 100).round();
    return Semantics(
      key: keyPrefix == null ? null : Key('$keyPrefix-semantics'),
      container: true,
      label: kcal == null
          ? '每 100 克热量未知'
          : '每 100 克 ${kcal.round()} 千卡，约为能量密度满刻度的 $percent%',
      // 环与数字都是装饰：语义已经由上面一条说全，重复播报三个数字没有意义。
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: LfRingPainter(
                  track: c.muted,
                  progress: c.primary,
                  ratio: ratio,
                  radius: (size - stroke) / 2,
                  stroke: stroke,
                ),
              ),
              // 数字必须住进内孔：44dp 环的内孔只有 36dp，2.0× 字号下三位数
              // （「394」）会横向顶到描边上——`scaleDown` 在放不下时等比缩小，
              // 1.0× 不缩放，几何与设计稿一致。
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: size - stroke,
                  maxHeight: size - stroke,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    kcal == null ? '—' : '${kcal.round()}',
                    key: keyPrefix == null ? null : Key('$keyPrefix-kcal'),
                    style: _valueStyle.copyWith(
                      color: c.cardForeground,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 中心数字字阶：大档（详情弹层）用 14px，小档（行）用 caption 的 10px。
  ///
  /// Round7 阶段 3 · D37：小档（36dp）的中心数字按 A
  /// `.food-density .data-ring-center b{font-size:10px;font-weight:650}` 收到
  /// **10px**（原 caption 的 12px）。
  ///
  /// Round7 阶段 3 · 3-2d（D47）：大档按 A `.detail-density .data-ring-center b`
  /// 收到 **14px**（原 titleLarge 的 16px）。A 这里写的 w700 落回 600——字重由
  /// `build` 里统一 `.copyWith(fontWeight: FontWeight.w600)` 指定（仓内字阶只到
  /// 600，与「650 → 600」同一映射口径）。
  TextStyle get _valueStyle => size >= LfDimens.foodKcalRingLargeSize
      ? LfText.titleLarge.copyWith(fontSize: 14)
      : LfText.caption.copyWith(fontSize: 10);
}

/// 能量密度满刻度：1000 kcal/100g（docs/28 §5.1 的常量单源）。
///
/// **2026-10-09（docs/31 需求 49）由 900 改 1000**：用户原话「食物库的满刻度
/// 能不能设置为1000kcal/100g」。旧值 900 的理由是「纯油脂约 900 是常见食物
/// 物理上限」，但那会让纯油脂**顶格**——满环只属于极少数食物。改 1000 后
/// 纯油脂落在 90%，不再顶格；这是用户点名要的口径，不是回归。
/// 语义标签按比例如实报百分比（116 → 12%），环下说明句由本常量插值。
const double kFoodDensityFullScaleKcal = 1000;

/// 把环的满刻度写在明面上（docs/29 §P8a 需求 23）。
///
/// 用户 2026-10-05 走查：「圆环的『全部』代表什么热量值？」——在只有环的界面
/// 上，一个填满的环可以说成「1000 kcal/100g」也可以说成「100% 每日目标」，用户
/// 无从判断。列表头放**一句**（每张卡都写一遍同一常量只是把 1000 重复 50 次、
/// 还要跟名称抢宽度），环下那格只承担「每行都会变」的单位。
///
/// 数字由 [kFoodDensityFullScaleKcal] 插值而来：改刻度时这句话跟着变，不会
/// 出现「环按 1000 画、文字写 900」的分叉。
class FoodDensityScaleNote extends StatelessWidget {
  const FoodDensityScaleNote({super.key, this.textAlign});

  /// 对齐方式。默认 null = 按宿主（列表头在左对齐的列里）。
  ///
  /// Round7 阶段 3 · 3-2d（D48）：食物详情把这一句放成 A `.food-density-note`
  /// 的**居中**小字——同一句（刻度单源）在两种宿主里分列两侧，句子本身不改。
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      '环 = 每 100g 能量密度 · 满刻度 ${kFoodDensityFullScaleKcal.round()} kcal/100g',
      key: const Key('food-density-scale-note'),
      style: LfText.micro.copyWith(color: context.lf.mutedForeground),
      textAlign: textAlign,
    );
  }
}
