import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 统计瓦片（docs/27 §R1）：设计稿「健康数据/成就」网格的 Flutter 译法。
///
/// 结构（全部居中）：可选图标位 → 值行（大数字 + 小单位）→ 标签。
///  * 值 = `LfText.headline` w800，强调指标用 primary 色——「指标要有强调
///    的感觉」由它承担；中性数据传 [emphasized: false] 用前景色。
///  * 单位永远比值小一号且 muted（`LfText.micro`），与今日页趋势瓦片的
///    「69.4 + kg」同一语言：数字强调、单位弱化，长单位不再把值行挤折行。
///  * 标签 `height: 1.25`（设计稿 `leading-tight`），完整显示不省略。
///
/// **等高语义在组容器**：CSS grid 的行内项目天然等高，Flutter 必须由调用方
/// 用 `IntrinsicHeight` + `CrossAxisAlignment.stretch` 包住一组瓦片（见
/// [LfStatTileRow]），否则行内各卡随内容高低不齐——「健康数据中间卡比两边
/// 高」正是缺了这一层。
class LfStatTile extends StatelessWidget {
  const LfStatTile({
    super.key,
    this.icon,
    required this.label,
    this.value,
    this.unit,
    this.emphasized = true,
    this.strongLabel = false,
    this.compact = false,
  });

  /// 图标位（成就的 36dp 圆形图标；纯统计瓦片不传）。
  final Widget? icon;
  final String label;

  /// 值（纯数字/短数值）；null = 只有图标 + 标签（成就形态）。
  final String? value;

  /// 值后的小单位（`kcal/天`、`L`）；null = 无单位（BMI 本身无单位）。
  final String? unit;
  final bool emphasized;

  /// 标签用前景色（成就的名称是主体，设计稿 `--lf-foreground`）；
  /// 缺省 muted（统计瓦片的标签是辅助信息）。
  final bool strongLabel;

  /// 紧凑档（docs/28 §4.5 地点统计行）：内距 16→8、值降一档字号（headline
  /// → titleLarge）、去掉阴影。它是「一行里三个小统计」用的：这一行是地点
  /// 卡的**附属**信息，用全尺寸瓦片会跟窗口卡抢视觉重心。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final valueColor = emphasized ? c.primary : c.cardForeground;
    return Container(
      padding: EdgeInsets.all(
        compact ? LfDimens.spaceSmall : LfDimens.spaceMedium,
      ),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
        border: Border.all(color: c.border),
        boxShadow: compact
            ? null
            : LfShadows.surface(
                Theme.of(context).brightness == Brightness.light,
              ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon!, const SizedBox(height: 6)],
          if (value != null) ...[
            // FittedBox 只作兜底：极端字号下整行等比缩小也不折行、不出界。
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value!,
                    style: (compact ? LfText.titleLarge : LfText.headline)
                        .copyWith(
                          color: valueColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: LfDimens.spaceXSmall),
                    Text(
                      unit!,
                      style: LfText.micro.copyWith(color: c.mutedForeground),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: LfDimens.spaceXSmall),
          ],
          Text(
            label,
            textAlign: TextAlign.center,
            style: LfText.micro.copyWith(
              height: 1.25,
              color: strongLabel ? c.cardForeground : c.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一组统计瓦片：CSS grid 等高语义的 Flutter 落点（docs/27 §R1）。
///
/// [columns] = 每行瓦片数（健康数据 3、成就 4）；放得下时等宽等高一行的
/// stretch 网格；可用宽度容不下时整体改纵向堆叠（每块通栏），调用方用
/// [stacked] 传入判定结果（各自按文字实测，判据不同）。
class LfStatTileRow extends StatelessWidget {
  const LfStatTileRow({
    super.key,
    required this.tiles,
    required this.columns,
    required this.stacked,
  });

  final List<LfStatTile> tiles;
  final int columns;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final gap = LfDimens.spaceSmall;
    return IntrinsicHeight(
      child: Flex(
        direction: stacked ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0)
              SizedBox(width: stacked ? 0 : gap, height: stacked ? gap : 0),
            if (stacked) tiles[i] else Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}
