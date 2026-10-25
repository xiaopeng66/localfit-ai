import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_evidence_badge.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/food_card.dart'
    show MacroDotLine;

/// 单个窗口卡（docs/28 §4.6）：窗口名 + 时段徽标 + 菜品行 +
/// 添加菜品 / AI 分析 / 加入菜品库（一行右对齐）。
///
/// 纯渲染 + 回调（写操作与弹层由 [MenuTabView] 编排），因此窗口卡
/// 自己不知道仓库也不知道路由。
class CanteenWindowCard extends StatelessWidget {
  const CanteenWindowCard({
    super.key,
    required this.window,
    required this.busy,
    required this.onAddDish,
    required this.onDeleteWindow,
    required this.onDishTap,
    this.onAnalyzeDishes,
  });

  final CanteenWindow window;
  final bool busy;
  final VoidCallback onAddDish;
  final VoidCallback onDeleteWindow;
  final void Function(CanteenDish dish) onDishTap;

  /// 「AI 分析这些未分析菜品」；null＝不渲染该入口。
  final void Function(List<CanteenDish> dishes)? onAnalyzeDishes;

  /// 「加入菜品库」：把本窗口**已分析**的菜品写进 `DishLibrary`
  /// （菜单页的唯一主来源，docs/21 §5.3 写入路径 1）。null＝不渲染。

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.lf;
    final unanalyzed = [
      for (final dish in window.dishes)
        if (!dish.hasNutrition) dish,
    ];
    // 没有营养值的菜品不进菜品库：写进去只会得到一张全是「—」的卡，
    // 还会污染菜品卡的「每日目标进度」分母。
    return DesignCard(
      key: Key('canteen-window-${window.id}'),
      padding: const EdgeInsets.all(LfDimens.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 窗口名 + 时段徽标（docs/28 §4.6）：时段从「一句话里的
                    // 一段」升为可扫的徽章，一行扫下来先看到几点到几点。
                    Wrap(
                      spacing: LfDimens.spaceSmall,
                      runSpacing: LfDimens.spaceXSmall,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(window.name, style: theme.textTheme.titleSmall),
                        LfBadge.neutral(
                          window.windowLabel,
                          key: Key('canteen-window-window-${window.id}'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${window.dishes.length} 道菜 · 每 100g'
                      '${window.analyzedCount == 0 ? '' : ' · 已分析 ${window.analyzedCount}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              LfCircleIconButton(
                key: Key('canteen-delete-window-${window.id}'),
                tooltip: '删除窗口',
                icon: Icons.delete_outline,
                iconSize: 20,
                onPressed: busy ? null : onDeleteWindow,
              ),
            ],
          ),
          if (window.dishes.isNotEmpty) ...[
            const SizedBox(height: 8),
            // 行间节奏（docs/29 §P7 需求 17）：行内纵padding 8 + 行间
            // 1px 分隔线嵌在上下各 8dp 间距正中。旧实现只有 6dp 内边距、
            // 无分隔、无行头，10+ 行时挤成一坨。
            for (var index = 0; index < window.dishes.length; index++) ...[
              if (index > 0) ...[
                const SizedBox(height: 8),
                Divider(height: 1, thickness: 1, color: c.border),
                const SizedBox(height: 8),
              ],
              CanteenDishRow(
                dish: window.dishes[index],
                index: index + 1,
                onTap: busy ? null : () => onDishTap(window.dishes[index]),
              ),
            ],
          ],
          const SizedBox(height: LfDimens.spaceSmall),
          // 三钮统一为一行、右对齐、放不下就整行换行（docs/28 §4.6）。
          //
          // 必须包一层 `Align`：外层 Column 的 crossAxisAlignment 是 start，
          // 直接挂 `Wrap` 时它的宽度等于内容宽（比卡窄），`WrapAlignment.end`
          // 只在**行内**生效，于是三枚按钮实际贴在卡的左缘（自测抓出：
          // 右缘差 339.6px）。`Align` 给出全宽再把内容推到右边，同时保留
          // `Wrap` 的换行能力——换回 `Row + Spacer` 会在窄屏溢出。
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: LfDimens.spaceSmall,
              runSpacing: LfDimens.spaceSmall,
              children: [
                // 「添加」类动作 = B5 虚线按钮（§3.8），设计稿的 `AI 工作.html:583`。
                LfDashedButton(
                  key: Key('canteen-add-dish-${window.id}'),
                  label: '添加菜品',
                  icon: Icons.add,
                  onPressed: busy ? null : onAddDish,
                ),
                if (unanalyzed.isNotEmpty && onAnalyzeDishes != null)
                  // 卡内的主行动用 B3 胶囊实心档，而不是 FilledButton.tonal
                  // ——后者补全 ColorScheme 之前走回落链 `secondaryContainer
                  // ?? secondary`，与实心主按钮同色的 mint-600。
                  LfPillButton(
                    key: Key('canteen-analyze-${window.id}'),
                    label: 'AI 分析 ${unanalyzed.length} 道',
                    icon: Icons.auto_awesome_outlined,
                    tone: LfPillTone.solid,
                    onPressed: busy ? null : () => onAnalyzeDishes!(unanalyzed),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 菜品行（docs/29 §P7 需求 17）：
/// **行头（序号圆 / 缩略图）+ 名称/档口副行/证据徽标 + 三彩点宏量 + 右列
///（kcal 与价格上下两行）**。
///
/// 旧形态是裸行（名称 + 一堆行内徽标 + 右侧 `kcal` 与 `8.00 元` 并排），
/// 行的起点对齐不了（无行头）、价格与热量混在一行里读不出层级。现在：
///  * 无照片 → 24dp 序号圆（`muted` 底 + `mutedForeground` 字）：给用户
///    一个「第几道」的定位锚，也让所有行的左缘对齐；序号是**窗口内顺序**
///    的展示值，不入库（顺序即 `createdAt` 升序，与列表来源一致）。
///  * 有照片 → 44dp 圆角缩略图（`Image.file`，cover）；文件被系统清掉时
///    errorBuilder 回落序号圆——诚实空态，**不伪造占位照片**。
///  * `stationName`（档口）存在时做名称下方的副行；不存在不画。
///  * 右列 kcal 与价格上下两行（价格在下，弱一档），不再与宏量抢同一行。
class CanteenDishRow extends StatelessWidget {
  const CanteenDishRow({
    super.key,
    required this.dish,
    required this.index,
    this.onTap,
  });

  final CanteenDish dish;

  /// 窗口内的展示序号（1 起）。**不是**数据库字段：由窗口卡按列表顺序给。
  final int index;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.lf;
    return InkWell(
      key: Key('canteen-dish-${dish.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _DishLead(dish: dish, index: index),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: LfDimens.spaceSmall,
                    runSpacing: LfDimens.spaceXSmall,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(dish.name, style: theme.textTheme.bodyMedium),
                      // 证据等级保留（docs/07 §9.2：营养值必须带证据表达）。
                      if (dish.hasNutrition)
                        AppEvidenceBadge(
                          key: Key('canteen-dish-grade-${dish.id}'),
                          grade: dish.evidenceGrade,
                        ),
                      // 未分析只说事实，不给假数值（docs/21 §6.2 裁决 10）。
                      if (!dish.hasNutrition)
                        LfBadge.neutral(
                          '未分析营养',
                          key: Key('canteen-dish-unanalyzed-${dish.id}'),
                        ),
                    ],
                  ),
                  // 档口副行（需求 17）：列本来就有，此前读取侧整列丢弃。
                  if (dish.stationName case final station?
                      when station.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      station,
                      key: Key('canteen-dish-station-${dish.id}'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                  if (dish.hasNutrition) ...[
                    const SizedBox(height: 3),
                    MacroDotLine(
                      protein: dish.proteinPer100g,
                      carbs: dish.carbsPer100g,
                      fat: dish.fatPer100g,
                    ),
                  ],
                ],
              ),
            ),
            // 右列一行：营养热量（2026-10-16 用户要求删掉价格——`price_minor`
            // 列已随 v26 迁移退役，这里不再有第二行）。
            if (dish.hasNutrition) ...[
              const SizedBox(width: LfDimens.spaceSmall),
              Text(
                '${dish.kcalPer100g!.round()} kcal',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: c.foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 行头：有照片画缩略图（44dp 圆角 8，cover），否则画序号圆（24dp）。
/// 缩略图加载失败（文件被系统清理）回落序号圆——两种行头都在同一条
/// 中轴线上，行高变化只体现在**有图行**（44 > 24），由 [Row] 的
/// `crossAxisAlignment.center` 自然居中。
class _DishLead extends StatelessWidget {
  const _DishLead({required this.dish, required this.index});

  final CanteenDish dish;
  final int index;

  @override
  Widget build(BuildContext context) {
    final path = dish.imagePath;
    if (path == null || path.isEmpty) return _indexCircle(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path),
        key: Key('canteen-dish-photo-thumb-${dish.id}'),
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _indexCircle(context),
      ),
    );
  }

  Widget _indexCircle(BuildContext context) {
    final c = context.lf;
    final theme = Theme.of(context);
    return Container(
      key: Key('canteen-dish-index-${dish.id}'),
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
      child: Text(
        '$index',
        style: theme.textTheme.labelMedium?.copyWith(color: c.mutedForeground),
      ),
    );
  }
}
