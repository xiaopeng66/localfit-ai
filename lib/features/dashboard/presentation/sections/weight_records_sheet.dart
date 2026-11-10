import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

/// 体重记录列表（体重卡 ⋮ 进入）——A-2（docs/64）。
///
/// 形态与 A-1（饮水）一致：**列表 → 删除（就地确认）→ 弹层关闭 → 页面
/// SnackBar「撤销」**（`restore` 回写原 id）。删除后「最近记录」由
/// `watchWeightOverview` 流自己回退，这里**不手算**。
Future<void> showWeightRecordsSheet(
  BuildContext context, {
  required MeasurementRepository repository,
  required List<WeightMeasurement> measurements,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final deleted = await AppSheet.showCustom<WeightMeasurement>(
    context,
    builder: (_) =>
        WeightRecordsSheet(repository: repository, measurements: measurements),
  );
  if (deleted == null) return;
  AppSnackBar.showOn(
    messenger,
    '已删除 ${deleted.localDate} 的 ${deleted.weightKg.toStringAsFixed(1)} kg 记录。',
    icon: AppSnackBar.deleteIcon,
    actionLabel: '撤销',
    duration: AppSnackBar.undoDuration,
    onAction: () async {
      try {
        await repository.restore(deleted);
      } catch (_) {
        AppSnackBar.showOn(messenger, '撤销失败，请重试。', icon: AppSnackBar.errorIcon);
      }
    },
  );
}

/// 弹层主体：按日期倒序列出记录，每条可删（就地二次确认）。
class WeightRecordsSheet extends StatefulWidget {
  const WeightRecordsSheet({
    super.key,
    required this.repository,
    required this.measurements,
  });

  final MeasurementRepository repository;

  /// 入参已按 `localDate DESC` 排好（来自 `watchWeightOverview`）。
  final List<WeightMeasurement> measurements;

  @override
  State<WeightRecordsSheet> createState() => _WeightRecordsSheetState();
}

class _WeightRecordsSheetState extends State<WeightRecordsSheet> {
  String? _confirmingId;
  bool _deleting = false;

  Future<void> _delete(WeightMeasurement record) async {
    if (_deleting) return;
    setState(() => _deleting = true);
    final deleted = await widget.repository.delete(record.id);
    if (!mounted) return;
    if (deleted == null) {
      setState(() {
        _deleting = false;
        _confirmingId = null;
      });
      AppSnackBar.show(context, '这条记录已不存在。', icon: AppSnackBar.errorIcon);
      return;
    }
    Navigator.of(context).pop(deleted);
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.measurements;
    return Column(
      key: const Key('weight-record-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('体重记录', style: LfText.headline),
        const SizedBox(height: LfDimens.spaceXSmall),
        Text(
          records.isEmpty ? '还没有记录' : '最近 ${records.length} 条（近一年）',
          style: LfText.caption.copyWith(color: context.lf.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        if (records.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: LfDimens.spaceLarge),
            child: Text(
              '还没有体重记录。点「+」记第一条。',
              key: const Key('weight-record-empty'),
              style: LfText.body.copyWith(color: context.lf.mutedForeground),
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: records.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: LfDimens.spaceSmall),
              itemBuilder: (context, index) => _WeightRecordRow(
                index: index,
                record: records[index],
                confirming: _confirmingId == records[index].id,
                busy: _deleting,
                onAskDelete: () =>
                    setState(() => _confirmingId = records[index].id),
                onCancel: () => setState(() => _confirmingId = null),
                onConfirm: () => _delete(records[index]),
              ),
            ),
          ),
        const SizedBox(height: LfDimens.spaceSmall),
      ],
    );
  }
}

class _WeightRecordRow extends StatelessWidget {
  const _WeightRecordRow({
    required this.index,
    required this.record,
    required this.confirming,
    required this.busy,
    required this.onAskDelete,
    required this.onCancel,
    required this.onConfirm,
  });

  final int index;
  final WeightMeasurement record;
  final bool confirming;
  final bool busy;
  final VoidCallback onAskDelete;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 来源只说事实（`ble_scale` = 秤同步，其余 = 手输），不为 null 猜值。
    final source = record.source == 'ble_scale' ? '秤同步' : '手输';
    return Container(
      key: Key('weight-record-$index'),
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceMedium,
        vertical: LfDimens.spaceSmall,
      ),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      ),
      // 确认态（2026-10-28 第二轮复核）：与饮水表同一形态——确认语独占整行、
      // 两钮收在其下右对齐。旧版按钮与「70.5 kg / 日期」同行，320dp×2.0×
      // 下把文字挤成多行（饮水表同款缺陷，当时只修了那张表）。
      child: confirming
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '删除 ${record.localDate} 的 '
                  '${record.weightKg.toStringAsFixed(1)} kg 记录？',
                  key: const Key('weight-record-confirm-text'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: LfText.body.copyWith(color: c.foreground),
                ),
                const SizedBox(height: LfDimens.spaceMicro),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    LfTextButton(
                      label: '取消',
                      onPressed: busy ? null : onCancel,
                    ),
                    LfDangerButton(
                      key: const Key('weight-record-confirm'),
                      label: '删除',
                      onPressed: busy ? null : onConfirm,
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${record.weightKg.toStringAsFixed(1)} kg',
                        style: LfText.bodyStrong.copyWith(color: c.foreground),
                      ),
                      Text(
                        '${record.localDate} · $source',
                        style: LfText.caption.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                LfIconButton(
                  key: Key('weight-record-delete-$index'),
                  icon: Icons.delete_outline,
                  semanticLabel:
                      '删除 ${record.localDate} 的 '
                      '${record.weightKg.toStringAsFixed(1)} 公斤记录',
                  onPressed: busy ? null : onAskDelete,
                ),
              ],
            ),
    );
  }
}
