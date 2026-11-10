import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';

/// 页内「可用系统返回手势 / 返回键取消」的状态登记处（LIFO）。
///
/// 【为什么不用多个 PopScope】页面骨架是 StatefulShellRoute + 分支
/// Navigator，「双击返回才退出应用」的 PopScope 与页内状态（记录页多选）
/// 同挂在 shell 这条路由上，多个 PopScope 的 canPop 组合语义难推理。
/// 集中成一个 LIFO 栈 + shell 根部单一 PopScope，优先级明确（见
/// [AppExitGate.handleShellBack] 的分层说明）。
///
/// 【现在的登记方】记录页的多选模式（RecordTab 的 State 注册）：返回手势
/// 先退多选，而不是退出应用——用户 2026-10-31：「手势也可以取消，比如这个
/// 删除食物的选择弹出来的时候，手势返回会导致退出桌面」。
abstract final class AppBackInterceptors {
  static final List<bool Function()> _stack = <bool Function()>[];

  /// 注册拦截器，返回**注销函数**（State.dispose 里调用，防泄漏）。
  ///
  /// 拦截器返回 true = 这次返回已被消费（例如退出了多选），不再往下传；
  /// 返回 false = 该状态当前不活跃，继续找栈里更上面的。
  static VoidCallback register(bool Function() handler) {
    _stack.add(handler);
    return () {
      _stack.remove(handler);
    };
  }

  /// 自顶向下（后注册的先问）找第一个消费返回的拦截器。
  @visibleForTesting
  static bool maybeHandle() {
    for (final handler in _stack.reversed) {
      if (handler()) return true;
    }
    return false;
  }
}

/// shell 路由的返回出口（`AppShell` 的 PopScope 调 [handleShellBack]）。
///
/// 【能走到这里说明什么】go_router 的返回传播（`GoRouterDelegate.popRoute`）
/// 先从**最内层** Navigator 起逐层 `maybePop`：顶上的弹层/对话框、分支
/// Navigator 里压过的子页面都会在这两层被消费掉。到 shell 的 PopScope
/// （canPop=false）时，只剩两类事：
/// 1. 页内登记的可取消状态（[AppBackInterceptors]）被返回逐层取消；
/// 2. 都没有 ⇒ **双击返回才退出应用**：第一击只提示，2 秒内第二击才真正
///    退出（用户 2026-10-31：给软件加上手势退出需要二次滑动的限制）。
abstract final class AppExitGate {
  static DateTime? _lastBackAt;

  static const Duration _exitWindow = Duration(seconds: 2);

  /// 测试注入的时钟（默认真实时钟）。
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// 测试注入的退出动作（默认 [SystemNavigator.pop]）。
  @visibleForTesting
  static Future<void> Function()? onExit;

  @visibleForTesting
  static void resetForTest() {
    _lastBackAt = null;
    onExit = null;
    clock = DateTime.now;
  }

  static Future<void> handleShellBack(BuildContext context) async {
    // 1) 页内可取消状态（多选等）优先。
    if (AppBackInterceptors.maybeHandle()) return;

    // 2) 双击返回才退出：第一击只提示，第二击在窗口内才真退。
    final now = clock();
    final last = _lastBackAt;
    if (last != null && now.difference(last) < _exitWindow) {
      _lastBackAt = null;
      await (onExit ?? SystemNavigator.pop)();
      return;
    }
    _lastBackAt = now;
    if (!context.mounted) return;
    AppSnackBar.show(context, '再按一次返回键退出', icon: AppSnackBar.infoIcon);
  }
}
