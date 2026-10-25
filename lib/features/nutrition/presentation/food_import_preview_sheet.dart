import 'package:flutter/material.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/nutrition/data/food_csv_importer.dart';

/// 食物 CSV 导入的预览弹层（docs/31 S5 需求 57 / 稿 ④）。
///
/// 「提示去重」= **先给账再决定**：可导入 / 与库内重复 / 格式错误三本账
/// 一次摆开，重复项给样例与库内身份（内置/自建徽标），用户选
/// 「跳过重复」或「全部导入」——不静默丢弃、也不强制覆盖。
///
/// 返回用户的选择；null = 取消（什么也不导）。
Future<FoodCsvImportPolicy?> showFoodImportPreviewSheet(
  BuildContext context,
  FoodCsvImportPreview preview,
) {
  return AppSheet.show<FoodCsvImportPolicy>(
    context,
    title: '导入预览 · 食物.csv',
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 同排等高（Round7 阶段 3 · 3-4 审看）：2.0× 下三块说明行数不同
        // （「可导入」一行、另两块两行）⇒ 各块按自身高度居中会高低不齐；
        // `IntrinsicHeight` + `stretch` 让三块等高，不裁字、不改文案。
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ImportStat(
                  statKey: const Key('food-import-count-new'),
                  count: preview.newCount,
                  label: '可导入',
                  color: context.lf.cardForeground,
                ),
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              Expanded(
                child: _ImportStat(
                  statKey: const Key('food-import-count-dup'),
                  count: preview.duplicateCount,
                  label: '与库内重复',
                  color: context.lf.warning,
                ),
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              Expanded(
                child: _ImportStat(
                  statKey: const Key('food-import-count-error'),
                  count: preview.errorCount,
                  label: '格式错误跳过',
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ),
        ),
        if (preview.duplicates.isNotEmpty) ...[
          const SizedBox(height: LfDimens.spaceMedium),
          _DupSamples(duplicates: preview.duplicates),
        ],
        if (preview.errors.isNotEmpty) ...[
          const SizedBox(height: LfDimens.spaceMedium),
          // 错误只给首条样例 + 总数：十几行坏数据逐条列出会把弹层顶爆，
          // 数字与样例足够用户回去修文件。
          Text(
            preview.errors.first.message,
            key: const Key('food-import-error-sample'),
            style: LfText.bodySmall.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          if (preview.errorCount > 1)
            Text(
              '……共 ${preview.errorCount} 行格式错误，已跳过。',
              style: LfText.bodySmall.copyWith(
                color: context.lf.mutedForeground,
              ),
            ),
        ],
        if (preview.unknownCategories.isNotEmpty) ...[
          const SizedBox(height: LfDimens.spaceXSmall),
          // ADR-037 的硬门禁：分类只能是十档（或旧文件的 24 个库大类）。
          // 这里把「识别不了的分类」按取值去重列出来——用户改文件时照着改，
          // 不用在几百行错误里反推。
          Text(
            '无法识别的分类：'
            '${preview.unknownCategories.entries.map((entry) => '「${entry.key}」×${entry.value}').join('、')}'
            '。请先把它们改成：${FoodCategory.values.map((value) => value.label).join(' / ')}'
            '，再重新导入。',
            key: const Key('food-import-unknown-category'),
            style: LfText.bodySmall.copyWith(color: context.lf.warningText),
          ),
        ],
      ],
    ),
    // 弹层走根导航器（docs/21 §3.6），动作闭包须用弹层内 context 弹出。
    actions: Builder(
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 动作行的两条也等高（同上）：2.0× 下「跳过重复，导入 N 条」会折
          // 三行、「全部导入」折两行——stretch 让两钮等高（不裁字、不改文案）。
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (preview.newCount > 0) ...[
                  Expanded(
                    child: LfTextButton(
                      key: const Key('food-import-skip-dup'),
                      label: '跳过重复，导入 ${preview.newCount} 条',
                      onPressed: () => Navigator.pop(
                        sheetContext,
                        FoodCsvImportPolicy.skipDuplicates,
                      ),
                    ),
                  ),
                  const SizedBox(width: LfDimens.spaceSmall),
                ],
                Expanded(
                  child: LfConfirmButton(
                    key: const Key('food-import-import-all'),
                    label: '全部导入',
                    expand: false,
                    onPressed: () => Navigator.pop(
                      sheetContext,
                      FoodCsvImportPolicy.importAll,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          Center(
            child: LfTextButton(
              key: const Key('food-import-cancel'),
              label: '取消',
              onPressed: () => Navigator.pop(sheetContext),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 三本账的一格：大数字 + 说明。数字如实，0 也画出来——「0 条重复」
/// 本身就是用户想知道的账。
class _ImportStat extends StatelessWidget {
  const _ImportStat({
    required this.statKey,
    required this.count,
    required this.label,
    required this.color,
  });

  final Key statKey;
  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: statKey,
      padding: const EdgeInsets.symmetric(
        vertical: LfDimens.spaceMedium,
        horizontal: LfDimens.spaceSmall,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: context.lf.border),
        borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      ),
      child: Column(
        children: [
          Text('$count', style: LfText.title.copyWith(color: color)),
          const SizedBox(height: LfDimens.spaceXSmall),
          Text(
            label,
            style: LfText.micro.copyWith(color: context.lf.mutedForeground),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 重复样例（最多 4 行）：名称（品牌）+ 库内身份徽标，底部一行去重口径。
class _DupSamples extends StatelessWidget {
  const _DupSamples({required this.duplicates});

  final List<FoodCsvDuplicate> duplicates;

  @override
  Widget build(BuildContext context) {
    final samples = duplicates.take(4).toList(growable: false);
    return Container(
      key: const Key('food-import-dup-samples'),
      padding: const EdgeInsets.all(LfDimens.spaceMedium),
      decoration: BoxDecoration(
        border: Border.all(color: context.lf.border),
        borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final sample in samples)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${sample.name}（${sample.brandLabel}）',
                      style: LfText.bodySmall,
                    ),
                  ),
                  sample.existingIsUserCreated
                      ? LfBadge.neutral('自建')
                      : LfBadge.mint('内置'),
                ],
              ),
            ),
          if (duplicates.length > samples.length)
            Text(
              '……另有 ${duplicates.length - samples.length} 条重复。',
              style: LfText.micro.copyWith(color: context.lf.mutedForeground),
            ),
          const SizedBox(height: LfDimens.spaceXSmall),
          Text(
            '重复判定：名称 + 品牌（trim / 忽略大小写 / 全角半角归一）',
            style: LfText.micro.copyWith(color: context.lf.mutedForeground),
          ),
        ],
      ),
    );
  }
}
