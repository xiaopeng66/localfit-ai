import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_ring_painter.dart';

/// 成就等级（铜 / 银 / 金）——**设计层的等级色板**。
///
/// 业务层的 `AchievementLevel` 由页面映射过来（与 `BmiTier` → `LfGaugeTone`
/// 同一套做法）：设计层只认「三档等级」，不认识「连续打卡 7 天」这类业务词。
enum LfMedalTier { bronze, silver, gold }

/// 等级 →（强调色 = 进度弧 + 进度条，徽标文字）。
///
/// 三色都取自既有 token，一个都不新造：
/// - 铜 = `weight`（数据色里唯一的暖棕）；
/// - 银 = `mutedForeground`（中性灰）；
/// - 金 = `carbs`（琥珀金，与「超重档」共用同一支数据色是允许的——两者的
///   语境（成就算法 / BMI 分档）在页面上从不同框，不会互相误读）。
({Color accent, String label}) medalTierStyle(
  BuildContext context,
  LfMedalTier tier,
) {
  final c = context.lf;
  return switch (tier) {
    LfMedalTier.bronze => (accent: c.weight, label: '铜'),
    LfMedalTier.silver => (accent: c.mutedForeground, label: '银'),
    LfMedalTier.gold => (accent: c.carbs, label: '金'),
  };
}

/// 成就行卡（docs/29 §P3 需求 5）：勋章环（进度 + 等级色）+ 名称 + 等级徽标
/// + 进度条 + `n / 目标`（解锁后原位换「已解锁」）。
///
/// 三条硬约束（都进测试）：
/// 1. **名称单行**：`maxLines: 1` + `FittedBox(scaleDown)`——信息性文本不许被
///    省略号吃掉；放不下时整体等比缩小（设备实测：最长的「7天连续打卡」在
///    2.0× / 320dp 下仍排得下，缩放只是兜底）。
/// 2. **行高与解锁状态无关**：解锁只在第 2 行**原位**把 `n/目标` 换成「已解锁」，
///    不新增行、不加徽章块，所以四行永远等高（`SettingsGroup` 的分隔线在行
///    **之间**，不落在行盒里）。
/// 3. **等级/计数由调用方算好传进来**：档位口径在
///    `features/settings/domain/achievement_levels.dart`，这里只负责画。
class LfAchievementRow extends StatelessWidget {
  const LfAchievementRow({
    super.key,
    required this.label,
    required this.tier,
    required this.progress,
    required this.unlocked,
    required this.count,
    required this.target,
    this.icon,
  });

  final String label;
  final LfMedalTier tier;

  /// 0..1（历史最大值）。非有限值按 0 画，不画半格脏数据。
  final double progress;
  final bool unlocked;

  /// 未解锁时显示的「当前」计数（`achievementCountOf` 的结果，与 [progress]
  /// 同源——拿实时计数去配历史进度会自相矛盾）。
  final int count;

  /// 达标值（分母）。`<= 0` ⇒ 不给分数（只画「—」），也不编一个目标出来。
  final int target;

  /// 解锁后勋章盘上的图标；null = 未解锁（盘上画挂锁）。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final style = medalTierStyle(context, tier);
    final ratio = progress.isFinite ? progress.clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.all(LfDimens.spaceMedium),
      child: Row(
        children: [
          _Medal(style: style, ratio: ratio, unlocked: unlocked, icon: icon),
          const SizedBox(width: LfDimens.spaceMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          key: const Key('lf-achievement-name'),
                          maxLines: 1,
                          softWrap: false,
                          style: LfText.bodySmall.copyWith(
                            fontWeight: FontWeight.w600,
                            color: c.foreground,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: LfDimens.spaceSmall),
                    _TierChip(style: style),
                  ],
                ),
                const SizedBox(height: LfDimens.spaceTiny),
                Row(
                  children: [
                    Expanded(
                      child: LfProgressBar(value: ratio, color: style.accent),
                    ),
                    const SizedBox(width: LfDimens.spaceSmall),
                    Text(
                      unlocked ? '已解锁' : (target > 0 ? '$count/$target' : '—'),
                      key: const Key('lf-achievement-count'),
                      maxLines: 1,
                      softWrap: false,
                      style: LfText.label.copyWith(
                        color: unlocked ? c.foreground : c.mutedForeground,
                        fontWeight: unlocked
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 勋章环：外环 = 等级色进度弧 + muted 轨道，内盘 = 未解锁 muted + 挂锁 /
/// 已解锁**实心等级色** + 该成就自己的图标（需求 5 的「换实心色」）。
class _Medal extends StatelessWidget {
  const _Medal({
    required this.style,
    required this.ratio,
    required this.unlocked,
    this.icon,
  });

  final ({Color accent, String label}) style;
  final double ratio;
  final bool unlocked;
  final IconData? icon;

  static const double _size = LfDimens.achievementMedalSize;
  static const double _stroke = LfDimens.achievementMedalStroke;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return SizedBox(
      key: const Key('lf-achievement-medal'),
      width: _size,
      height: _size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(_size),
            painter: LfRingPainter(
              track: c.muted,
              progress: style.accent,
              ratio: ratio,
              radius: (_size - _stroke) / 2,
              stroke: _stroke,
            ),
          ),
          Container(
            width: _size - 2 * _stroke,
            height: _size - 2 * _stroke,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unlocked ? style.accent : c.muted,
            ),
            child: Icon(
              unlocked ? (icon ?? Icons.emoji_events) : Icons.lock_outline,
              size: LfDimens.iconSm,
              color: unlocked ? _medalInk : c.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

/// 等级徽标：等级色**淡染**底 + 前景色文字。
///
/// 为什么底色不直接用等级色、文字不用白色：金色（`carbs`）在亮色主题下是亮琥珀，
/// 白字压上去看不清；反过来银灰底也压不住深字。淡染（同一 token + alpha）在
/// 两套主题下都是「浅色底」，配前景色恒定可读，且等级感仍由色相传达。
class _TierChip extends StatelessWidget {
  const _TierChip({required this.style});

  final ({Color accent, String label}) style;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('lf-achievement-tier'),
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceSmall,
        vertical: LfDimens.spaceMicro,
      ),
      decoration: BoxDecoration(
        color: style.accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(LfDimens.radiusFull),
      ),
      child: Text(
        style.label,
        maxLines: 1,
        softWrap: false,
        style: LfText.label.copyWith(
          fontWeight: FontWeight.w600,
          color: context.lf.foreground,
        ),
      ),
    );
  }
}

/// 解锁勋章盘（实心等级色）上的图标墨色。
///
/// 为什么不用 `foreground`：金牌在暗色主题下同样是**亮金**（`carbsDark`
/// #FFD56B），而 `foreground` 在暗色下是近白（#E8EFEB）——白图标画在亮金上
/// 等于看不见。中性 900（`neutralLight.tone(900)` = #1A201D）在两套主题下对
/// 金牌都有约 12:1 对比，所以按字面量钉死在这里；不能写成
/// `LfColors.neutral(brightness).tone(900)`——暗色 ramp 的 900 是浅色，正好反过来。
const Color _medalInk = Color(0xFF1A201D);
