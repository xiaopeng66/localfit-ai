import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/nutrition/data/food_csv_file_source.dart';
import 'package:localfit_ai/features/nutrition/data/food_csv_importer.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_import_preview_sheet.dart';

/// 食物写入的两条**共享通路**：CSV 导入与「食物数据」弹层。
///
/// 【为什么在这里】两条通路都有两处入口——设置页的「添加食物数据」组与食物库
/// 页尾（A `app.js:201` 的 `.library-footer`：`import-info` 与 `food-management`）。
/// 2026-10-14（Round7 阶段 3 · 3-2c）之前 CSV 通路内联在 `app_router.dart` 里，
/// 只有设置页能进；食物库页尾要接同一件事，只能把它提成共享件——**不做第二份
/// 实现**，CSV 列契约（ADR-036 官方 9 列）与单事务落库的守卫都只有一处。
///
/// 本文件只做编排与呈现：解析与落库都在 [FoodCsvImporter]（docs/31 §S5），
/// 这里不碰数据库、不改列契约。

/// 「从 CSV 文件导入食物数据」（docs/31 S5 需求 55/57）：挑文件 → 解析
/// 预览（三本账 + 重复样例）→ 用户决定 → 走 create 落库。每一步的失败都
/// 就地给出中文原因。
///
/// 落库现在**整批一个事务**（docs/32 §4 T11 验收 2），DB 级意外会上抛
/// （不再被吞成「failed 几条」）。抛出来就一定是「一条都没进去」，所以文案
/// 敢直接说「本地数据没有被改动」。
///
/// 调用方不需要自己刷新列表：`NutritionPage` / 设置页各自监听食物表变更
/// （`FoodRepository.watchChanges`），落库提交后自己会跟上。
Future<void> runFoodCsvImportFlow(
  BuildContext context,
  FoodRepository repository,
) async {
  final Uint8List? bytes;
  try {
    bytes = await const FilePickerFoodCsvSource().pickFoodCsv();
  } on FormatException catch (error) {
    if (context.mounted) {
      AppSnackBar.show(context, error.message, icon: AppSnackBar.errorIcon);
    }
    return;
  }
  if (bytes == null || !context.mounted) return;

  final importer = FoodCsvImporter(repository: repository);
  final FoodCsvImportPreview preview;
  try {
    preview = await importer.preview(bytes);
  } on FormatException catch (error) {
    if (!context.mounted) return;
    AppSnackBar.show(context, error.message, icon: AppSnackBar.errorIcon);
    return;
  }
  if (preview.hasNothingToImport) {
    if (!context.mounted) return;
    AppSnackBar.show(
      context,
      preview.errorCount > 0
          ? '文件里没有可导入的食物数据（${preview.errorCount} 行格式错误）。'
          : '文件里没有食物数据。',
      icon: AppSnackBar.errorIcon,
    );
    return;
  }
  if (!context.mounted) return;
  final policy = await showFoodImportPreviewSheet(context, preview);
  if (policy == null || !context.mounted) return;
  final FoodCsvImportResult result;
  try {
    result = await importer.execute(preview: preview, policy: policy);
  } on FormatException catch (error) {
    if (!context.mounted) return;
    AppSnackBar.show(context, error.message, icon: AppSnackBar.errorIcon);
    return;
  } catch (_) {
    if (!context.mounted) return;
    AppSnackBar.show(context, '导入失败，本地数据没有被改动。', icon: AppSnackBar.errorIcon);
    return;
  }
  if (!context.mounted) return;
  final message = StringBuffer('已导入 ${result.imported} 条食物（自建）。');
  if (result.skippedDuplicates > 0) {
    message.write('跳过重复 ${result.skippedDuplicates} 条。');
  }
  if (result.failed > 0) message.write('${result.failed} 条失败。');
  AppSnackBar.show(
    context,
    message.toString(),
    icon: result.failed > 0 ? AppSnackBar.errorIcon : AppSnackBar.successIcon,
  );
}

/// 「食物数据」弹层（docs/31 S5 需求 55）：两个动作——手动逐条（复用既有新建
/// 食物流程）与 CSV 批量导入。先关弹层再执行动作：导入有自己的预览弹层，
/// 叠着开会把导航栈搞乱。
///
/// [title] 随入口：设置页是「添加食物数据」（既有措辞，本轮不动——设置页的
/// 迁移在后面的阶段），食物库页尾按 A `app.js:517` 的字面用「食物库管理」。
/// 两处内容与 Key 完全相同（`food-data-sheet-*`），是同一个组件。
///
/// [onFoodWritten] 在每次动作返回后调用**一次**：设置页用它重读「食材数据库」
/// 计数行（那条 future 不随写库自动重读）；食物库不需要（页面监听食物表变更）。
///
/// 两个动作回调都没接时不渲染对应的行——不摆点了没反应的行。
Future<void> showFoodDataSheet(
  BuildContext context, {
  required String title,
  Future<void> Function()? onAddCustomFood,
  Future<void> Function()? onImportFoodCsv,
  VoidCallback? onFoodWritten,
}) async {
  await AppSheet.show<void>(
    context,
    title: title,
    content: const Text(
      '数据进入同一个本地食物库；导入行会标记为「自建」。',
      key: Key('food-data-sheet-body'),
    ),
    // 弹层走根导航器（docs/21 §3.6），动作闭包须用弹层内 context 弹出。
    actions: Builder(
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (onAddCustomFood != null)
            _FoodDataActionTile(
              actionKey: const Key('food-data-sheet-manual'),
              icon: Icons.add,
              title: '手动添加一种食物',
              subtitle: '填名称 / 品牌 / 种类 / 四大指标，逐条入库',
              onTap: () async {
                Navigator.pop(sheetContext);
                await onAddCustomFood();
                onFoodWritten?.call();
              },
            ),
          if (onImportFoodCsv != null) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            _FoodDataActionTile(
              actionKey: const Key('food-data-sheet-import'),
              icon: Icons.upload_file_outlined,
              title: '从 CSV 文件导入',
              subtitle: '支持本库导出的格式；重复项会先提示再决定',
              onTap: () async {
                Navigator.pop(sheetContext);
                await onImportFoodCsv();
                onFoodWritten?.call();
              },
            ),
          ],
          const SizedBox(height: LfDimens.spaceSmall),
          LfTextButton(
            label: '取消',
            onPressed: () => Navigator.pop(sheetContext),
          ),
        ],
      ),
    ),
  );
}

/// 弹层里的动作行（图标 + 标题 + 说明）。设置页与食物库共用同一枚。
class _FoodDataActionTile extends StatelessWidget {
  const _FoodDataActionTile({
    required this.actionKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key actionKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mint = LfColors.mint(Theme.of(context).brightness);
    return InkWell(
      key: actionKey,
      borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(LfDimens.spaceLarge),
        decoration: BoxDecoration(
          border: Border.all(color: context.lf.border),
          borderRadius: BorderRadius.circular(LfDimens.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: mint.tone(100),
                borderRadius: BorderRadius.circular(LfDimens.radiusSm),
              ),
              child: Icon(icon, size: 20, color: mint.tone(700)),
            ),
            const SizedBox(width: LfDimens.spaceLarge),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: LfText.body),
                  const SizedBox(height: LfDimens.spaceXSmall),
                  Text(
                    subtitle,
                    style: LfText.bodySmall.copyWith(
                      color: context.lf.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
