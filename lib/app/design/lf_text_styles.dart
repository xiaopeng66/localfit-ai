import 'package:flutter/material.dart';

/// 新设计字阶（docs/21 §2.6.2，按设计稿实测用量建 11 档 + displayHero）。
///
/// 唯一字阶来源（旧 `AppTextStyles` 已于阶段 I-3 删除）；淡色文本取
/// `LfText.xxx.copyWith(color: context.lf.mutedForeground)`。
///
/// 设计稿的全局排版特征逐条落实：
///  * `body { font-feature-settings: "tnum" 1 }` → 所有档位带
///    `FontFeature.tabularFigures()`（全稿数字等宽，不止数值档）；
///  * `.lf-display`（w800 + tabular + `letter-spacing:-0.02em` + `line-height:1`）
///    → display* 三档，letterSpacing 按字号换算 `-0.02em`；
///  * 字重只用三档：w400 / w500（medium）/ w600（semibold）+ display 的 w800；
///  * 字体族用平台默认 CJK（docs/21 §2.6.1：不内置字体文件）。
abstract final class LfText {
  static const _num = [FontFeature.tabularFigures()];

  /// 10px w400 h1.4 — 底栏标签、图例、脚注、时间戳（用量 107，最大档）。
  static const TextStyle micro = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    height: 1.4,
    fontFeatures: _num,
  );

  /// 10px w500 — 同 micro 但需强调。
  static const TextStyle microStrong = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    height: 1.4,
    fontFeatures: _num,
  );

  /// 11px w500 — 徽章文字、卡内小标签、次要数值。
  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.4,
    fontFeatures: _num,
  );

  /// 12px w400 — 次要文字、说明、卡内描述（用量 167）。
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    fontFeatures: _num,
  );

  /// 12px w500 — 卡内小标题、时间线标题。
  static const TextStyle captionStrong = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.4,
    fontFeatures: _num,
  );

  /// 13px w400 — 少数说明文。
  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.4,
    fontFeatures: _num,
  );

  /// 14px w400 h1.5 — 正文、列表项、按钮文字。
  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    fontFeatures: _num,
  );

  /// 14px w600 — 段落小标题。
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
    fontFeatures: _num,
  );

  /// 15px w600 h1.3 — **卡片标题**（今日页三张卡）+ 今日页头像首字。
  static const TextStyle title = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFeatures: _num,
  );

  /// 16px w600 h1.3 — 二级页标题与菜品名、营养分析三数值。
  static const TextStyle titleLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFeatures: _num,
  );

  /// 18px w600 h1.3 — 身份卡姓名与统计值、菜单 hero 数值、饮水/步数数值。
  static const TextStyle headline = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
    fontFeatures: _num,
  );

  /// 22px w800 h1.1 — 今日页问候语（`.lf-display`）。
  static const TextStyle displayLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    height: 1.1,
    letterSpacing: -0.44, // -0.02em
    fontFeatures: _num,
  );

  /// 26px w800 h1.0 — 圆环中心数值（`.lf-display`）。
  static const TextStyle displayXLarge = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: -0.52, // -0.02em
    fontFeatures: _num,
  );

  /// 30px w800 h1.0 — 训练页 hero 三统计（`.lf-display`；24px 档复用本档或
  /// displayLarge，docs/21 §2.6.2 不另建 20/24px token）。
  static const TextStyle displayHero = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    height: 1.0,
    letterSpacing: -0.6, // -0.02em
    fontFeatures: _num,
  );
}
