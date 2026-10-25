import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/features/progress/data/measurement_repository.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';

/// 体重记录**只读**弹层（Round7 裁决 R5，A `app.js:570` 的「体重记录」）。
///
/// A 的形态：大字体重卡 + 全部记录行。**裁决只批了只读**：
/// - 大字 = 最新一条（无记录时如实写「还没有体重记录」，不写 0 kg）；
/// - 行 = 日期 + 体重 + 来源（`manual`→手输 / `ble_scale`→秤同步；
///   旧数据 source 为 null ⇒ 不贴徽标，不猜一个来源）；
/// - **不搬** A 的「记录今天的体重」按钮：写入通路已经存在（今日页体重卡
///   的「+」），在只读列表里再放一个写入口会把「看记录」这件事变浑
///   （登记在证据里）。
Future<void> showWeightHistorySheet(
  BuildContext context,
  MeasurementRepository repository,
) {
  return AppSheet.show<void>(
    context,
    title: '体重记录',
    content: _WeightHistoryBody(repository: repository),
  );
}

class _WeightHistoryBody extends StatelessWidget {
  const _WeightHistoryBody({required this.repository});

  final MeasurementRepository repository;

  /// 落库来源的中文标签。**不认识的值不猜**（`null` / 未知 ⇒ 不贴徽标）。
  static String? _sourceLabel(String? source) => switch (source) {
    'manual' => '手输',
    'ble_scale' => '秤同步',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return StreamBuilder<List<WeightMeasurement>>(
      stream: repository.watchAllMeasurements(),
      builder: (context, snapshot) {
        final rows = snapshot.data;
        if (rows == null) {
          return const Padding(
            padding: EdgeInsets.all(LfDimens.spaceLarge),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          );
        }
        final latest = rows.isEmpty ? null : rows.first;
        return Column(
          key: const Key('weight-history-sheet'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 大字体重卡（A `.detail-energy` 的位置放了「最新一条」这件事）。
            Text(
              latest == null
                  ? '还没有体重记录'
                  : '${latest.weightKg.toStringAsFixed(1)} kg',
              key: const Key('weight-history-latest'),
              textAlign: TextAlign.center,
              style: (latest == null ? LfText.headline : LfText.displayHero)
                  .copyWith(color: c.cardForeground),
            ),
            Text(
              latest == null ? '记录一次体重后，这里会留下逐次历史。' : '最近一次记录',
              textAlign: TextAlign.center,
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
            const SizedBox(height: LfDimens.spaceLarge),
            if (rows.isEmpty)
              Text(
                '暂无历史记录。',
                key: const Key('weight-history-empty'),
                style: LfText.body.copyWith(color: c.mutedForeground),
              )
            else
              // 弹层限高由 AppSheet 统一给（90%）；记录多时内部滚动。
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final row in rows)
                      Padding(
                        key: Key('weight-history-row-${row.localDate}'),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.localDate,
                                style: LfText.body.copyWith(
                                  color: c.mutedForeground,
                                ),
                              ),
                            ),
                            if (_sourceLabel(row.source) != null) ...[
                              LfBadge.neutral(_sourceLabel(row.source)!),
                              const SizedBox(width: LfDimens.spaceSmall),
                            ],
                            Text(
                              '${row.weightKg.toStringAsFixed(1)} kg',
                              style: LfText.bodyStrong.copyWith(
                                color: c.cardForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
