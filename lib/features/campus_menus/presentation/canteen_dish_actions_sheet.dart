import 'package:flutter/material.dart';

/// 菜品动作清单（docs/21 §3.6 弹层）：改名/改价 · AI 分析 · 删除。
///
/// 从 `menu_tab_view.dart` 拆出来的一件纯表现件——动作项与 key 是它的全部
/// 内容，编排（拿到结果后调哪个仓库）仍在页面里。拆分的直接理由是 500 行
/// 预算（docs/07 §9.3）：页面加完 `AppSheet` 编排后越线。
///
/// 关闭用自身 `context`：本件渲染在 `AppSheet` 的子树里（弹层挂在根导航器
/// 上），因此直接 `Navigator.of(context).pop` 弹的就是这个弹层。
class CanteenDishActionsSheet extends StatelessWidget {
  const CanteenDishActionsSheet({required this.showAnalyze, super.key});

  /// 未分析营养且接线方提供了 AI 回调时才给「AI 分析这道菜」。
  final bool showAnalyze;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const Key('canteen-dish-edit'),
          leading: const Icon(Icons.edit_outlined),
          title: const Text('改名/改价'),
          onTap: () => Navigator.of(context).pop('edit'),
        ),
        if (showAnalyze)
          ListTile(
            key: const Key('canteen-dish-analyze'),
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('AI 分析这道菜'),
            onTap: () => Navigator.of(context).pop('analyze'),
          ),
        ListTile(
          key: const Key('canteen-dish-manual-nutrition'),
          leading: const Icon(Icons.edit_note_outlined),
          title: const Text('手动填写营养（每 100g）'),
          onTap: () => Navigator.of(context).pop('manual'),
        ),
        ListTile(
          key: const Key('canteen-dish-delete'),
          leading: const Icon(Icons.delete_outline),
          title: const Text('删除'),
          onTap: () => Navigator.of(context).pop('delete'),
        ),
      ],
    );
  }
}
