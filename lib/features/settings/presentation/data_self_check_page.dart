import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/settings/application/data_self_check.dart';

/// 设置 → 数据管理 → 「数据自检」（D-1/D-2，docs/64）。
///
/// 顶部「最近一次备份」muted 块 + 每类问题一张 [DesignCard]
/// （卡头「问题名 + N 条」徽章、说明小字、右下角文字按钮动作）：
/// - 孤儿引用：**修复**（置空 `food_id`，快照列不动）→ 删后给「撤销」；
/// - 日期格式异常：**只报不修**（改写或删行都会丢记录，页面上如实说）；
/// - 过期手动步数行：**清理**（先取整行、删后给「撤销」）。
/// 没有问题时如实说「没有发现问题」，不编一个 0 计数列表。
class DataSelfCheckPage extends StatefulWidget {
  const DataSelfCheckPage({super.key, required this.selfCheck});

  final DataSelfCheck selfCheck;

  @override
  State<DataSelfCheckPage> createState() => _DataSelfCheckPageState();
}

class _DataSelfCheckPageState extends State<DataSelfCheckPage> {
  DataSelfCheckReport? _report;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final report = await widget.selfCheck.run();
    if (!mounted) return;
    setState(() => _report = report);
  }

  Future<void> _fixOrphans() async {
    final messenger = ScaffoldMessenger.of(context);
    final fixed = await widget.selfCheck.fixOrphanFoodIds();
    if (!mounted) return;
    await _reload();
    if (fixed == 0) return;
    AppSnackBar.showOn(
      messenger,
      '已置空 $fixed 条孤儿引用（餐记录内容不变）。',
      icon: AppSnackBar.successIcon,
      actionLabel: '撤销',
      duration: AppSnackBar.undoDuration,
      onAction: () async {
        try {
          await widget.selfCheck.undoFixOrphanFoodIds();
          await _reload();
        } catch (_) {
          AppSnackBar.showOn(
            messenger,
            '撤销失败，请重试。',
            icon: AppSnackBar.errorIcon,
          );
        }
      },
    );
  }

  Future<void> _fixStaleSteps() async {
    final messenger = ScaffoldMessenger.of(context);
    final removed = await widget.selfCheck.removeStaleManualStepRows();
    if (!mounted) return;
    await _reload();
    if (removed == 0) return;
    AppSnackBar.showOn(
      messenger,
      '已清理 $removed 条过期手动步数行。',
      icon: AppSnackBar.successIcon,
      actionLabel: '撤销',
      duration: AppSnackBar.undoDuration,
      onAction: () async {
        try {
          await widget.selfCheck.undoRemoveStaleManualStepRows();
          await _reload();
        } catch (_) {
          AppSnackBar.showOn(
            messenger,
            '撤销失败，请重试。',
            icon: AppSnackBar.errorIcon,
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final report = _report;
    return Column(
      key: const Key('data-self-check-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('数据自检', style: LfText.headline),
        const SizedBox(height: LfDimens.spaceXSmall),
        MutedBlock(
          child: Row(
            children: [
              Icon(
                Icons.backup_outlined,
                size: LfDimens.iconSm,
                color: c.mutedForeground,
              ),
              const SizedBox(width: LfDimens.spaceSmall),
              Expanded(
                child: Text(
                  _backupLabel(report),
                  key: const Key('data-self-check-backup'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        if (report == null)
          const Padding(
            padding: EdgeInsets.all(LfDimens.spaceLarge),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          )
        else if (!report.hasIssues)
          MutedBlock(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: LfDimens.iconMd,
                  color: c.success,
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '没有发现问题。',
                        key: const Key('data-self-check-clean'),
                        style: LfText.body.copyWith(color: c.foreground),
                      ),
                      const SizedBox(height: LfDimens.spaceMicro),
                      Text(
                        '三类检查：孤儿的食物引用、日期格式异常、过期手动步数行。'
                        '有问题会在这里列出。',
                        style: LfText.caption.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else ...[
          if (report.orphanFoodItems > 0)
            _IssueCard(
              title: '孤儿的食物引用',
              detail:
                  '${report.orphanFoodItems} 条餐记录指向已删除的食物。'
                  '修复只把引用置空，记录内容不变。',
              count: report.orphanFoodItems,
              actionLabel: '修复',
              actionKey: const Key('data-self-check-fix-orphans'),
              onAction: _fixOrphans,
            ),
          if (report.badDateTotal > 0)
            _IssueCard(
              title: '日期格式异常',
              detail:
                  '${report.badDateTotal} 行的日期不是 yyyy-MM-dd'
                  '（${report.badDateRows.keys.join('、')}）。'
                  '不自动修：改写或删行都会丢记录，先备份再手工处理。',
              count: report.badDateTotal,
            ),
          if (report.staleManualStepRows > 0)
            _IssueCard(
              title: '过期手动步数行',
              detail:
                  '${report.staleManualStepRows} 天前的手动步数还在，'
                  '自动读取一直被它挡着。清理后可撤销。',
              count: report.staleManualStepRows,
              actionLabel: '清理',
              actionKey: const Key('data-self-check-fix-steps'),
              onAction: _fixStaleSteps,
            ),
        ],
        const SizedBox(height: LfDimens.spaceXSmall),
      ],
    );
  }

  String _backupLabel(DataSelfCheckReport? report) {
    final at = report?.lastBackupAt;
    if (at == null) return '最近一次备份：还没有备份过';
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '最近一次备份：${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }
}

/// 一类问题一张卡：卡头「问题名 + N 条」徽章（320dp / 2.0× 下问题名最多
/// 两行截断，徽章固定不挤），说明小字，动作按钮收到右下角。
class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.title,
    required this.detail,
    required this.count,
    this.actionLabel,
    this.actionKey,
    this.onAction,
  });

  final String title;
  final String detail;
  final int count;
  final String? actionLabel;
  final Key? actionKey;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.only(bottom: LfDimens.spaceMedium),
      child: DesignCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: LfText.bodyStrong.copyWith(color: c.foreground),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                LfBadge.mint('$count 条'),
              ],
            ),
            const SizedBox(height: LfDimens.spaceMicro),
            Text(
              detail,
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: LfDimens.spaceXSmall),
              Align(
                alignment: Alignment.centerRight,
                child: LfTextButton(
                  key: actionKey,
                  icon: Icons.build_outlined,
                  label: actionLabel!,
                  onPressed: onAction,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 从设置页打开的壳：复用 [AppSheet.showCustom]（与其它设置弹层同一形态）。
///
/// **必须自带滚动**（2026-10-28 第二轮复核）：`showCustom` 的定制主体没有
/// 滚动层，只有「屏高 90%」的上限；三类问题卡片化后内容在大字号下远超一屏
/// ——真实壳实测 320dp × 2.0× 溢出 **547px**。这里包一层
/// `SingleChildScrollView`：内容短时弹层仍按内容定高，超一屏时整页可滚。
Future<void> showDataSelfCheckSheet(
  BuildContext context, {
  required DataSelfCheck selfCheck,
}) {
  return AppSheet.showCustom<void>(
    context,
    builder: (_) =>
        SingleChildScrollView(child: DataSelfCheckPage(selfCheck: selfCheck)),
  );
}
