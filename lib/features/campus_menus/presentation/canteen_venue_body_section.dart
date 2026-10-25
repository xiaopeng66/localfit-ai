import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/canteen_window_card.dart';

/// 地点正文：窗口列表 slivers（从 [MenuTabView] 拆出守 500 行预算）。
///
/// 数据来自页面传入的**上一份成功结果**（需求 18 的 stale-while-revalidate）：
/// 刷新中继续画旧列表 + 顶部 2dp 细进度条，绝不进 `SliverFillRemaining`
/// 加载分支（那会把滚动视图压成零内容高、offset 夹回 0 ⇒ 跳顶）。只有
/// 「从未拿到过数据」的地点才允许加载/错误占位。
class CanteenVenueBodySection extends StatelessWidget {
  const CanteenVenueBodySection({
    super.key,
    required this.venue,
    required this.windows,
    required this.fetching,
    required this.failed,
    required this.busy,
    required this.onAddDish,
    required this.onDeleteWindow,
    required this.onDishTap,
    required this.onAddWindow,
    required this.onRetry,
    required this.onAnalyze,
  });

  final CanteenVenue venue;
  final List<CanteenWindow>? windows;
  final bool fetching;
  final bool failed;
  final bool busy;
  final void Function(CanteenWindow window) onAddDish;
  final void Function(CanteenWindow window) onDeleteWindow;
  final void Function(CanteenDish dish) onDishTap;
  final VoidCallback onAddWindow;
  final VoidCallback onRetry;
  final Future<void> Function(List<CanteenDish> dishes)? onAnalyze;

  @override
  Widget build(BuildContext context) =>
      SliverMainAxisGroup(slivers: buildSlivers(context));

  /// 宿主也可以 `...spread` 本方法的结果（不用 SliverMainAxisGroup 包一层）。
  List<Widget> buildSlivers(BuildContext context) {
    final windows = this.windows;
    final fetching = this.fetching;
    final failed = this.failed;
    if (windows == null) {
      if (fetching) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          ),
        ];
      }
      // 首拉失败且无旧数据：整块错误 + 重试（旧 FutureBuilder 没有重试，
      // 错误后会一直挂到下一次写操作为止）。
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('窗口加载失败，请重试。'),
              const SizedBox(height: 8),
              LfTextButton(
                key: const Key('canteen-windows-retry'),
                label: '重试',
                onPressed: fetching ? null : () => onRetry(),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      if (fetching)
        const SliverToBoxAdapter(child: LinearProgressIndicator(minHeight: 2)),
      if (failed)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '窗口刷新失败，显示的是上一次的结果。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverList.list(
          children: [
            if (windows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '这个地点还没有窗口。先添加一个窗口（如「一楼快餐」）。',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              for (final window in windows) ...[
                CanteenWindowCard(
                  window: window,
                  busy: busy,
                  onAddDish: () => onAddDish(window),
                  onDeleteWindow: () => onDeleteWindow(window),
                  onDishTap: onDishTap,
                  onAnalyzeDishes: onAnalyze,
                ),
                const SizedBox(height: 12),
              ],
            // 「添加」类动作 = B5 虚线按钮（§3.8）；原先裸 `OutlinedButton`
            // 走 M3 基线（描边色曾是纯黑/纯白）。
            Align(
              alignment: Alignment.centerLeft,
              child: LfDashedButton(
                key: const Key('canteen-add-window'),
                label: '添加窗口',
                icon: Icons.add_outlined,
                onPressed: busy ? null : () => onAddWindow(),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}
