import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_morph_chip.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_stat_tile.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';

/// 菜单 tab 的地点选择区（docs/28 §4.5）：标题 + 添加地点入口 + 地点 chips +
/// 目录统计。
///
/// 纯渲染 + 回调（写操作与弹层由 `MenuTabView` 编排），因此这里不知道仓库
/// 也不知道路由；拆成 section 让 `menu_tab_view.dart` 保持在 500 行预算内
/// （docs/07 §9.3）。
///
/// 旧实现把统计压成一句话「我的校园 · 1 个窗口 · 1 道菜 · 已分析 0」：四项
/// 事实写成等同密度的一串顿号，用户得在里面找数字。现在学校名降为副标题、
/// 三个数字各占一张小瓦片（`LfStatTile` 紧凑档）。
class CanteenVenueSelector extends StatelessWidget {
  const CanteenVenueSelector({
    super.key,
    required this.venues,
    required this.selected,
    required this.busy,
    required this.onAddVenue,
    required this.onSelectVenue,
  });

  final List<CanteenVenue> venues;
  final CanteenVenue selected;
  final bool busy;
  final VoidCallback onAddVenue;
  final ValueChanged<String> onSelectVenue;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LfDimens.pagePadding,
        LfDimens.spaceSmall,
        LfDimens.pagePadding,
        LfDimens.spaceSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '食堂地点',
                  // 与「我的」页分组标题同源（docs/28 §4.5）。
                  style: LfText.label.copyWith(color: c.mutedForeground),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              LfTextButton(
                key: const Key('canteen-add-venue'),
                icon: Icons.add_location_alt_outlined,
                label: '添加地点',
                onPressed: busy ? null : onAddVenue,
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          SizedBox(
            // 44 = 触达线（docs/21 §3.12）：地点 chip 不再低于最小可点高度。
            height: LfDimens.minTouchTarget,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: venues.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: LfDimens.spaceSmall),
              itemBuilder: (context, index) {
                final venue = venues[index];
                return AppMorphChip(
                  key: Key('canteen-venue-${venue.id}'),
                  label: venue.name,
                  selected: venue.id == selected.id,
                  variant: AppMorphChipVariant.outlined,
                  onSelected: (_) => onSelectVenue(venue.id),
                );
              },
            ),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          Text(
            selected.campusName,
            style: LfText.caption.copyWith(color: c.mutedForeground),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          // 三个小统计。值为个位数、单位一个字，放不下时值行由 `FittedBox`
          // 等比缩小、标签自己折行——所以不需要按实测宽度决定是否堆叠
          // （`LfStatTileRow.stacked` 的判据是给 `kcal/天` 这种长单位用的）。
          LfStatTileRow(
            key: const Key('canteen-venue-stats'),
            columns: 3,
            stacked: false,
            tiles: [
              LfStatTile(
                key: const Key('canteen-stat-windows'),
                compact: true,
                value: '${selected.windowCount}',
                unit: '个',
                label: '窗口',
              ),
              LfStatTile(
                key: const Key('canteen-stat-dishes'),
                compact: true,
                value: '${selected.dishCount}',
                unit: '道',
                label: '菜品',
              ),
              LfStatTile(
                key: const Key('canteen-stat-analyzed'),
                compact: true,
                value: '${selected.analyzedCount}',
                unit: '道',
                label: '已分析',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
