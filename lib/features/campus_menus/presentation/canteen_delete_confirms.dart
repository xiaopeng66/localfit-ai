import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';

/// 食堂目录共用的删除确认弹层（docs/32 §3 D8/D15：统一弹层壳 `AppSheet`，
/// 原为体系外的 `AlertDialog`）。返回值语义与按钮档位不变：true = 确认删除。
///
/// 从 [MenuTabView] 拆出（500 行预算）：窗口与菜品的删除确认是同一条
/// 交互（B7 危险字色 + 二次确认），没有理由各写一份。
Future<bool> confirmCanteenDelete(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  // docs/32 §3 D8/D15：收敛到统一弹层壳 `AppSheet`（原为体系外的
  // `AlertDialog`）。返回值语义与按钮档位不变。
  //
  // **必须用弹层内 context 弹**：`AppSheet` 走 `useRootNavigator: true`，
  // 弹层挂在根导航器上；这里若用页面 context（`Navigator.of(context)` 解析
  // 到 shell 分支导航器），点「删除」会把**食堂目录页**弹掉、弹层还留着，
  // 用户看到的是「点了删除跳回上一页、菜却没删」（2026-10-23 用户实测）。
  // `Builder` 给出一个位于弹层路由下的 context。
  final result = await AppSheet.show<bool>(
    context,
    title: title,
    content: Text(message),
    actions: Builder(
      builder: (sheetContext) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 弹层行动档（§3.8）：破坏性确认 = B7（error 字色 + 二次确认浮层），
          // 取消 = B6。设计稿里没有实心 error 按钮（`我的.html:524-532`）。
          LfTextButton(
            onPressed: () => Navigator.of(sheetContext).pop(false),
            label: '取消',
          ),
          LfDangerButton(
            onPressed: () => Navigator.of(sheetContext).pop(true),
            label: '删除',
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
