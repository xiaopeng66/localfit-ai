import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/user_avatar.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart'
    show parseLocalDate;

/// 今日页顶栏（docs/21 §5.1 GreetingHeader；2026-10-14 按 Round7 A `.page-head`）。
///
/// **无 AppBar**：问候语 / 日期 + 头像直接贴在页面顶部。A 的 `head()` 是
/// `<h1>你好，{name}</h1>` 在上、`<p class="page-date">` 在下，右侧 `.avatar`
/// 44dp 圆（`--brand-soft` 底 + `--brand-strong` 首字 + `1px --card` 描边）；
/// **没有第三行**——「还可摄入 N kcal」按 A 移进热量卡的 `.energy-foot`。
class DashboardGreetingHeader extends StatelessWidget {
  const DashboardGreetingHeader({
    super.key,
    required this.now,
    required this.localDate,
    this.displayName,
    this.avatarPath,
    this.onTapAvatar,
  });

  final DateTime now;
  final String localDate;

  /// 本地档案姓名。null/空 → 问候语退回「早安/午安/晚安」、头像显示「Fit」。
  final String? displayName;

  /// 头像文件路径（docs/32 §3 D9）。null/文件缺失 → 回退首字母。
  final String? avatarPath;
  final VoidCallback? onTapAvatar;

  /// 按小时切换问候（早/午/晚）。
  static String greetingFor(int hour) {
    if (hour < 11) return '早安';
    if (hour < 18) return '午安';
    return '晚安';
  }

  /// 头像首字：姓名第一个字；无档案回退「Fit」。
  static String avatarInitial(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return 'Fit';
    return trimmed.characters.first;
  }

  /// 「9月23日 周二」。
  static String formatDateLabel(DateTime value) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    // DateTime.weekday: 1=周一 … 7=周日。
    final weekday = weekdays[value.weekday - 1];
    return '${value.month}月${value.day}日 周$weekday';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final date = parseLocalDate(localDate);
    final name = displayName?.trim();
    final title = name == null || name.isEmpty
        ? greetingFor(now.hour)
        : '${greetingFor(now.hour)}，$name';

    return Row(
      // A `.page-head{min-height:50px;align-items:center}`。
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                key: const Key('dashboard-greeting'),
                style: LfText.displayLarge.copyWith(color: c.foreground),
              ),
              const SizedBox(height: 3),
              Text(
                formatDateLabel(date),
                key: const Key('dashboard-date-label'),
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            ],
          ),
        ),
        const SizedBox(width: LfDimens.spaceMedium),
        _Avatar(
          displayName: displayName,
          avatarPath: avatarPath,
          onTap: onTapAvatar,
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.displayName, this.avatarPath, this.onTap});

  final String? displayName;
  final String? avatarPath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // docs/32 §3 D9：共享 `UserAvatar`（有图显图、无图首字、无昵称「Fit」）。
    // 形态按 Round7 A `.avatar`：44dp **圆**（旧版是圆角 16 方块）、
    // `--brand-soft` 底、`--brand-strong` 首字、`1px --card` 描边。
    return Semantics(
      button: onTap != null,
      label: '个人资料',
      child: GestureDetector(
        key: const Key('dashboard-avatar'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: UserAvatar(
          displayName: displayName,
          avatarPath: avatarPath,
          size: LfDimens.minTouchTarget,
          circle: true,
          background: LfColors.brandSoft(Theme.of(context).brightness),
          foreground: LfColors.mintText(Theme.of(context).brightness),
          borderColor: c.card,
          imageKey: const Key('dashboard-avatar-image'),
          initialKey: const Key('dashboard-avatar-initial'),
        ),
      ),
    );
  }
}
