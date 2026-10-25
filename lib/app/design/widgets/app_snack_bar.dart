import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';

/// 统一 SnackBar 出口（docs/21 §3.1）：左图标槽 + 可选操作按钮 +
/// 连续弹合并（替换式，屏上只留最新一条）。
///
/// 底色/圆角/浮动/文字色全部由 `snackBarTheme`（墨绿浮岛）提供，组件层
/// 不写死颜色，亮/暗/高对比随主题自动切换；图标取 `onSnackBar` 与文案同色。
///
/// 与「进出 spring」的差异：`SnackBar` 未暴露入场动画钩子（`showSnackBar`
/// 的 250ms 淡入由框架内部写死），主题与 helper 层都无注入点，保留框架淡入
/// （与 docs/21 §2.9 `easeInfo 250ms` 的 SnackBar 条目一致）。
abstract final class AppSnackBar {
  /// 删除族（破坏性操作 + 撤销）的时长：**6 秒**，比默认 4 秒长。
  ///
  /// 显式常量的理由：撤销是破坏性操作**唯一的恢复通道**，4 秒对「看清 →
  /// 决定 → 点中」偏紧；而全局放宽会拖慢所有轻提示。所以只给删除族加长。
  static const Duration undoDuration = Duration(seconds: 6);

  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    showOn(
      ScaffoldMessenger.of(context),
      message,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// 已捕获 `ScaffoldMessenger` 的调用点用这个变体（删除流先捕获再 await，
  /// 避免异步间隙后 `ScaffoldMessenger.of` 落到失效 context 上）。
  static void showOn(
    ScaffoldMessengerState messenger,
    String message, {
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    messenger
      // 替换式合并：清掉排队/在屏的旧条，最新一条立即顶上。
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          // null = 框架默认时长（4 s）；一次性轻提示（如「已复制」）传短值。
          duration: duration ?? const Duration(seconds: 4),
          // 【SDK 陷阱，必须显式传】`SnackBar` 的构造器里写着
          // `persist = persist ?? action != null`：**只要带 action 就默认
          // 永不过期**。删除流正好命中——「餐食已删除 · 撤销」会永久挂在屏上，
          // 直到下一条 `clearSnackBars()` 把它顶掉（`RV4-P1-01`，2856 条测试
          // 全绿也没抓到，因为没有一条推进过时间）。
          // 这里传 `false`：带 action 的提示条也必须到期消失。
          persist: false,
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  // 与文案同色；messenger 已失效时退回默认 IconTheme。
                  color: messenger.mounted
                      ? messenger.context.lfc.onSnackBar
                      : null,
                ),
                const SizedBox(width: LfDimens.spaceMedium),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          action: actionLabel == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  // 显式取主题动作色：`SnackBarAction` 内部是普通 `Text`，
                  // 不吃 `contentTextStyle`，不传就回落 `ColorScheme.secondary`。
                  textColor: messenger.mounted
                      ? Theme.of(messenger.context)
                            .snackBarTheme
                            .actionTextColor
                      : null,
                  onPressed: onAction ?? () {},
                ),
        ),
      );
  }

  /// 成功/已保存/已创建族（✓）。
  static const IconData successIcon = Icons.check_circle_outline;

  /// 失败/错误族（!）。
  static const IconData errorIcon = Icons.error_outline;

  /// 删除族（含「撤销」操作）。
  static const IconData deleteIcon = Icons.delete_outline;

  /// 中性/取消族（用户主动中止，非成功也非失败）。
  static const IconData infoIcon = Icons.info_outline;
}
