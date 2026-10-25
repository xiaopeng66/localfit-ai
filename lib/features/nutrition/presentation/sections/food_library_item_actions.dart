import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/presentation/new_food_dialog.dart';
import 'package:localfit_ai/utils/food_name.dart';
import 'package:localfit_ai/utils/text_utils.dart';

/// 食物库条目动作层（docs/07 §9.3「页面只负责布局和用户事件」；与
/// `NutritionActions` 同一取舍）：编辑 / 删除自建食物的完整流程——开弹层、
/// 落库、回显结果、触发列表重来——不再写在 [FoodLibraryView] 里。
///
/// 页面从 500 行预算里把这一块让出去（`ui_maintainability_audit_test`
/// 阶段 3 抓到的真实超限：598 行）；动作逻辑与渲染无关，挪走后页面只剩
/// 布局与事件。
final class FoodLibraryItemActions {
  const FoodLibraryItemActions({
    required this.context,
    required this.controller,
    required this.reload,
  });

  final BuildContext context;
  final FoodLibraryController controller;

  /// 落库成功后的重来（当前查询 + 分类、清页缓存）。
  final Future<void> Function() reload;

  /// 编辑一条自建食物（docs/28 §5.3，N8）。
  ///
  /// 走 [NewFoodDialog] 的提交型弹层：落库失败**不关窗**，错误留在弹层里，
  /// 用户输入原样保留（N7）。成功才回来重来，并明说改了哪一条。
  Future<void> edit(FoodLibraryItem item) async {
    final record = await controller.foodById(item.id);
    if (!context.mounted) return;
    if (record == null) {
      // 详情弹层开着的时候条目被别处删了：如实说，不要开一张空表单。
      _message('这条食物已不在本地数据里。', error: true);
      return;
    }
    final existingAliases = await controller.aliasesFor(item.id);
    if (!context.mounted) return;
    final saved = await NewFoodDialog.show(
      context,
      editing: record,
      existingAliases: existingAliases,
      onSubmit: (food) => controller.updateFood(item.id, food),
    );
    if (!context.mounted || saved == null) return;
    await reload();
    if (context.mounted) _message('已保存「${_displayName(saved.name)}」。');
  }

  /// 删除一条自建食物（docs/28 §5.3，N8）。
  ///
  /// 破坏性操作一律 B7 文字按钮 + 二次确认（设计系统约定）；确认浮层里也说清
  /// 楚「记过的餐次不受影响」——`meal_items` 存了当次的名称与热量快照，
  /// 删掉食物不会让历史记录凭空少一顿。
  Future<void> delete(FoodLibraryItem item) async {
    final name = _displayName(item.name);
    final confirmed = await AppSheet.show<bool>(
      context,
      title: '删除这条食物？',
      content: Text(
        '「$name」会从本地食物库移除。已经记过的餐次不受影响，'
        '那些记录里存着当次的名称与热量。',
      ),
      actions: Builder(
        builder: (dialogContext) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              label: '取消',
            ),
            LfDangerButton(
              key: const Key('food-library-delete-confirm'),
              onPressed: () => Navigator.pop(dialogContext, true),
              label: '删除',
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final failure = await controller.deleteFood(item.id);
    if (!context.mounted) return;
    if (failure != null) {
      // 内置条目 / 条目已消失：把数据层给的固定文案原样摆出来，
      // 不换一句更含糊的「删除失败」。
      _message(failure, error: true);
      return;
    }
    await reload();
    if (context.mounted) _message('已删除「$name」。');
  }

  /// 卡上/提示里用的产品名（与 `FoodCard` 同一套清洗：去掉品牌前缀）。
  String _displayName(String raw) => normalizeFoodName(splitFoodName(raw).name);

  void _message(String text, {bool error = false}) {
    AppSnackBar.show(
      context,
      text,
      icon: error ? AppSnackBar.errorIcon : AppSnackBar.deleteIcon,
    );
  }
}
