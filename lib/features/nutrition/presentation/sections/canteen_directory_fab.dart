import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/widgets/lf_float_actions.dart';

/// 菜单页右下「管理食堂目录」浮钮（需求 13a，2026-10-25）。
///
/// 【它为什么单独成件】`nutrition_page.dart` 有一条**维护性预算**：
/// 「饮食页只留布局与用户事件，不超过 400 行」（`ui_maintainability_audit_test`）。
/// 把这一块的构造（图标/文案/导航）留在页里会顶破预算——而放宽预算正是那条
/// 测试明令不许做的事。所以按既有 `PositionedRecordFab` 的同一手法拆出来：
/// 页里只留一行挂载。
///
/// 【位置】与记录页 FAB 同一层、同一右下角（`LfFloatingActions` 负责按
/// `LfInsets.bottom` 抬起，避开 `extendBody` 的底栏）。
class PositionedCanteenDirectoryFab extends StatelessWidget {
  const PositionedCanteenDirectoryFab({
    super.key,
    required this.onOpen,
    this.bottomOffset = PositionedLfFloatingActions.defaultBottomOffset,
  });

  /// 打开食堂目录（路由由调用方给，本件不做导航决策）。
  final VoidCallback onOpen;

  final double bottomOffset;

  @override
  Widget build(BuildContext context) {
    return PositionedLfFloatingActions(
      bottomOffset: bottomOffset,
      actions: [
        LfFloatingAction(
          actionKey: const Key('cta-manage-canteen'),
          // 【2026-11-02 用户】不要带字的胶囊，只要圆形图标钮。图标用
          // 店面（storefront）而不是书：它表达的是「食堂/窗口」，书更像
          // 「文件」。纯图标钮的可识别性由 tooltip + 读屏标签兜底。
          icon: Icons.storefront_outlined,
          semanticLabel: '管理食堂目录',
          onPressed: onOpen,
        ),
      ],
    );
  }
}
