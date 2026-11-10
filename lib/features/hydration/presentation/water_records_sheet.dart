import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/hydration/data/water_repository.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';

/// 当天饮水记录列表（长按饮水卡进入）——A-1（docs/64）。
///
/// 形态与餐食删除一致：**列表 → 删除（就地二次确认）→ 弹层关闭 → 页面
/// SnackBar「撤销」**（走 `restore` 回写同一条记录，不是重新 `add`）。
/// 弹层挂在根导航器上会盖住页面级 SnackBar，所以删除成功后先关弹层再提示。
///
/// 合计由 `watchDay` 流自己推（删完卡片立刻减少），这里**不手算**。
Future<void> showWaterRecordsSheet(
  BuildContext context, {
  required WaterRepository repository,
  required String localDate,
}) async {
  // 先捕获 messenger：await 之后 context 可能已失效。
  final messenger = ScaffoldMessenger.of(context);
  final deleted = await AppSheet.showCustom<WaterIntakeRecord>(
    context,
    builder: (_) =>
        WaterRecordsSheet(repository: repository, localDate: localDate),
  );
  if (deleted == null) return;
  AppSnackBar.showOn(
    messenger,
    '已删除 ${deleted.amountMl.round()} ml 饮水记录。',
    icon: AppSnackBar.deleteIcon,
    actionLabel: '撤销',
    // 删除族显式 6 秒（撤销是唯一的恢复通道）。
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

/// 弹层主体：当天每条记录一行（量 + 时刻 + 删除键），空态一行文案。
class WaterRecordsSheet extends StatefulWidget {
  const WaterRecordsSheet({
    super.key,
    required this.repository,
    required this.localDate,
  });

  final WaterRepository repository;
  final String localDate;

  @override
  State<WaterRecordsSheet> createState() => _WaterRecordsSheetState();
}

class _WaterRecordsSheetState extends State<WaterRecordsSheet> {
  // 流只建一次：每次 build 新建会让 StreamBuilder 反复重订阅。
  late final Stream<WaterSummary> _stream = widget.repository.watchDay(
    widget.localDate,
  );

  /// 正在二次确认的那一条（null = 没有）。
  String? _confirmingId;
  bool _deleting = false;

  Future<void> _delete(WaterIntakeRecord record) async {
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
    return StreamBuilder<WaterSummary>(
      stream: _stream,
      builder: (context, snapshot) {
        final records = snapshot.data?.records ?? const <WaterIntakeRecord>[];
        return Column(
          key: const Key('water-record-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('饮水记录', style: LfText.headline),
            const SizedBox(height: LfDimens.spaceXSmall),
            Text(
              records.isEmpty
                  ? '今天还没有记录'
                  : '共 ${records.length} 条 · '
                        '合计 ${records.fold<double>(0, (sum, r) => sum + r.amountMl).round()} ml',
              style: LfText.caption.copyWith(color: context.lf.mutedForeground),
            ),
            const SizedBox(height: LfDimens.spaceMedium),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: LfDimens.spaceLarge,
                ),
                child: Text(
                  '还没有饮水记录。点卡片可以记一杯。',
                  key: const Key('water-record-empty'),
                  style: LfText.body.copyWith(
                    color: context.lf.mutedForeground,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: records.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: LfDimens.spaceSmall),
                  itemBuilder: (context, index) => _WaterRecordRow(
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
      },
    );
  }
}

class _WaterRecordRow extends StatelessWidget {
  const _WaterRecordRow({
    required this.index,
    required this.record,
    required this.confirming,
    required this.busy,
    required this.onAskDelete,
    required this.onCancel,
    required this.onConfirm,
  });

  final int index;
  final WaterIntakeRecord record;
  final bool confirming;
  final bool busy;
  final VoidCallback onAskDelete;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final local = record.recordedAt.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return Container(
      key: Key('water-record-$index'),
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceMedium,
        vertical: LfDimens.spaceSmall,
      ),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      ),
      child: confirming
          // 确认态（2026-10-28 重设计）：确认语**独占整行**、两个按钮收在
          // 其下右对齐一行。不再与按钮同行——320×2.0 实测同行布局会把
          // 「250 ml 的记录？」挤到省略号截断（按钮占掉 ~240dp）。
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '删除这条 ${record.amountMl.round()} ml 的记录？',
                  key: const Key('water-record-confirm-text'),
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
                      key: const Key('water-record-confirm'),
                      label: '删除',
                      onPressed: busy ? null : onConfirm,
                    ),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Icon(
                  Icons.water_drop_outlined,
                  size: LfDimens.iconMd,
                  color: context.lfc.waterIcon,
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                // 大数字 + 小单位分两段（E-3 同口径）：整串一个 Text 在
                // 极端字号下折行，拆开后单位下沉、数值恒单行。
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: LfDimens.spaceMicro,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          Text(
                            record.amountMl.round().toString(),
                            maxLines: 1,
                            style: LfText.bodyStrong.copyWith(
                              color: c.foreground,
                            ),
                          ),
                          Text(
                            'ml',
                            maxLines: 1,
                            style: LfText.caption.copyWith(
                              color: c.mutedForeground,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        time,
                        style: LfText.caption.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
                LfIconButton(
                  key: Key('water-record-delete-$index'),
                  icon: Icons.delete_outline,
                  semanticLabel: '删除这条 ${record.amountMl.round()} 毫升饮水',
                  onPressed: busy ? null : onAskDelete,
                ),
              ],
            ),
    );
  }
}
