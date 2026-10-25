import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_evidence_badge.dart'
    show LfEvidenceGrade;
import 'package:localfit_ai/features/nutrition/domain/meal_evidence.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 当日置信摘要（docs/21 §3）：「已确认 N 项 · 估算 M 项」+ 环形小图。
///
/// 已确认 = 直接来自用户操作的记录（手动/历史复用；老库里的 `recipe` 行
/// 也属此类）；其余按估算计。
/// 口径来自 `meal_evidence.dart` 这一个映射表（与餐卡、菜品卡的徽标同源），
/// 本文件不再自己判一次来源字符串。按食物项计数；列表为空时不渲染，
/// 不显示 0/0 空转行。只读既有 [MealRecord] 事实，不做推断。
///
/// 设计稿的今日页没有这一格，按 docs/22 裁决 ② 收进二级入口：挂在饮食·
/// 记录页（阶段 I 补漏——此前重建后一度没有任何入口，先落到分析卡卡尾）。
///
/// 2026-10-14（docs/33 阶段 2）：Round7 A 的今日餐次卡**有**这一格
/// （`app.js:151` 的 `sourceSummary()`），A 记录页热量卡下也有；今日页按 A
/// 挂到餐次卡内（零餐不渲染，决策 D5），记录页按 A 挂成热量卡之下的页级
/// 一行（阶段 2B 步骤 4，`NutritionRecordSourceSummary`）。
class DashboardConfidenceSummary extends StatelessWidget {
  const DashboardConfidenceSummary({super.key, required this.meals});

  final List<MealRecord> meals;

  @override
  Widget build(BuildContext context) {
    if (meals.isEmpty) return const SizedBox.shrink();

    var confirmed = 0;
    var estimated = 0;
    for (final meal in meals) {
      if (evidenceGradeForSource(meal.source) == LfEvidenceGrade.confirmed) {
        confirmed += meal.items.length;
      } else {
        estimated += meal.items.length;
      }
    }

    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    // Round7 A `.source-summary`（refinement.css:5）：11px `--brand-strong`、
    // 环形 20、间距 8、上下 padding 4；「/ 估算 M 项」落在 `.muted` 档。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceXSmall),
      child: Row(
        key: const Key('confidence-summary'),
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CustomPaint(
              painter: ConfidenceRingPainter(
                confirmedItems: confirmed,
                totalItems: confirmed + estimated,
                trackColor: context.lfc.ringTrack,
                progressColor: c.primary,
              ),
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '已确认 $confirmed 项',
                    style: LfText.label.copyWith(
                      color: LfColors.mintText(brightness),
                    ),
                  ),
                  TextSpan(
                    text: ' / 估算 $estimated 项',
                    style: LfText.label.copyWith(color: c.mutedForeground),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 置信环小图：mint = 已确认占比，track = 通用环底轨；纯装饰不进语义树。
///
/// 颜色由调用方按当前主题解析后传入——`CustomPainter` 拿不到 `BuildContext`，
/// 在这里硬编码旧 token 会让暗色主题下的环停在亮色配色上。
class ConfidenceRingPainter extends CustomPainter {
  ConfidenceRingPainter({
    required this.confirmedItems,
    required this.totalItems,
    required this.trackColor,
    required this.progressColor,
  });

  final int confirmedItems;
  final int totalItems;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    const stroke = 3.0;
    final arcRect = Rect.fromCircle(
      center: center,
      radius: radius - stroke / 2,
    );

    canvas.drawCircle(
      center,
      radius - stroke / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    final progress = totalItems <= 0 ? 0.0 : confirmedItems / totalItems;
    if (progress <= 0) return;
    canvas.drawArc(
      arcRect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = progressColor,
    );
  }

  @override
  bool shouldRepaint(ConfidenceRingPainter oldDelegate) =>
      oldDelegate.confirmedItems != confirmedItems ||
      oldDelegate.totalItems != totalItems ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.progressColor != progressColor;
}
