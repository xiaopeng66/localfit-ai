import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/pressable_scale.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_evidence.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 记录页餐食卡（docs/21 §5.2 MealCard，3.1 唯一卡片形态）。
///
/// 结构（自上而下）：餐次 + 时间 + 合计 kcal ／ 逐条菜品行（右侧挂该项
/// **主要宏量**的彩点与克数）／ 合计三色 chips ／ 来源徽标。
///
/// 「主要宏量」= 该项热量贡献最大的宏量（4/4/9 kcal/g 换算），不是固定写
/// 蛋白质——否则一碗米饭会被标成「碳水 25g」之外还挂个蛋白质彩点，与设计
/// 稿每行只挂一个点不符。
///
/// 2026-10-14(docs/33 阶段 2B D16):新增 [embedded] 形态,供记录页的槽位
/// 分组卡内使用。它去掉 `DesignCard` 外壳与 `PressableScale`(避免**卡中
/// 卡**),但保留点击 / 长按 / 多选圈、全部内容与全部 Key。默认 false =
/// 独立白卡,既有调用点行为不变。
class MealRecordCard extends StatelessWidget {
  const MealRecordCard({
    super.key,
    required this.meal,
    required this.onEdit,
    required this.onDelete,
    this.embedded = false,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
    this.onToggleSelected,
  });

  final MealRecord meal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// 内嵌形态(阶段 2B D16):宿主本身已经是卡(记录页槽位分组卡)时用。
  /// 去掉 `DesignCard` 外壳与 `PressableScale`,行内容与 Key 不变。
  final bool embedded;

  /// docs/21 §3 多选模式:点击切换勾选、勾选圈常驻左侧;进入模式靠长按。
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;

  /// 多选模式下点击卡片（回调走这里，而不是 [onEdit]）。
  final VoidCallback? onToggleSelected;

  /// 该项的「主要宏量」：按 4/4/9 热量贡献取最大者。
  static MacroKind dominantMacro(NutritionValues nutrition) {
    final protein = nutrition.proteinGrams * 4;
    final carbs = nutrition.carbsGrams * 4;
    final fat = nutrition.fatGrams * 9;
    if (protein >= carbs && protein >= fat) return MacroKind.protein;
    if (carbs >= fat) return MacroKind.carbs;
    return MacroKind.fat;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final nutrition = meal.nutrition;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 设计稿是 `flex items-center justify-between`:左「时间 + 餐次」、
        // 右「合计 kcal」。这里改用 [Wrap] 的同款对齐——宽屏一行两端分开,
        // 320dp + 1.5× 字号放不下时右侧整组折到下一行。
        // 固定 Row 在这个规模下会溢出 73px(左侧 91 + kcal 182 + 管理键
        // 48 已超过卡片内宽 256),且没有任何子项可压缩。
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: LfDimens.spaceXSmall,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: LfDimens.spaceSmall),
                    // 勾选圈:「吞没」变形(圆点 → 实心对勾),语义 ='选中'。
                    child: Container(
                      key: Key('meal-select-circle-${meal.id}'),
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? c.primary : c.muted,
                      ),
                      child: selected
                          ? Icon(
                              Icons.check,
                              size: 16,
                              color: c.primaryForeground,
                            )
                          : null,
                    ),
                  ),
                Text(
                  _clockLabel(meal.eatenAt),
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Text(
                  meal.slot.label,
                  style: LfText.bodyStrong.copyWith(color: c.cardForeground),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一案（2026-10-16 用户选定）：热量写成「大数字 + 小单位」，
                // 与今日页/趋势卡的数字语言一致。
                Text(
                  '${nutrition.kcal.round()}',
                  style: LfText.title.copyWith(color: c.cardForeground),
                ),
                const SizedBox(width: LfDimens.spaceMicro),
                Text(
                  'kcal',
                  style: LfText.micro.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          ],
        ),
        if (meal.items.isNotEmpty) ...[
          const SizedBox(height: LfDimens.spaceMedium),
          for (final item in meal.items)
            Padding(
              padding: const EdgeInsets.only(bottom: LfDimens.spaceSmall),
              child: _ItemRow(item: item),
            ),
        ],
        // 2026-10-16（用户选定第一案）：分隔线把「条目区」与「合计区」分开，
        // 合计宏量 + 来源徽标 + 管理菜单收进同一行——原来徽标另起一行，卡底
        // 显得空、行数也多。
        const SizedBox(height: LfDimens.spaceSmall),
        Container(height: 1, color: c.border),
        const SizedBox(height: LfDimens.spaceSmall),
        Row(
          children: [
            // 合计宏量（读屏是完整一句；视觉一行小字）。左端合计、右端
            // 徽标与备注；最右的管理按钮不可压缩（2.0× 下也不会溢出）。
            Flexible(
              child: Text(
                '蛋白质 ${_grams(nutrition.proteinGrams)}g · '
                '碳水 ${_grams(nutrition.carbsGrams)}g · '
                '脂肪 ${_grams(nutrition.fatGrams)}g',
                key: Key('meal-totals-${meal.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            ),
            const SizedBox(width: LfDimens.spaceSmall),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  evidenceBadgeForSource(
                    meal.source,
                    key: Key('meal-source-${meal.id}'),
                  ),
                  if (meal.notes case final notes?) ...[
                    const SizedBox(width: LfDimens.spaceSmall),
                    Expanded(
                      child: Text(
                        notes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LfText.caption.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 逐餐的编辑/删除入口:设计稿没画管理菜单,但取消全局 AppBar
            // 后这两个动作没有别处可放(长按多选只覆盖批量删除),按裁决 2
            // 收进卡内二级入口。放在底行而不是表头——表头右侧的 kcal 在
            // 2.0× 字号下已经吃掉全部余量,再挂一个 48dp 按钮就会溢出
            // (实测 34px)。
            PopupMenuButton<_MealAction>(
              key: Key('meal-manage-${meal.id}'),
              tooltip: '管理 ${meal.slot.label}',
              icon: Icon(
                Icons.more_vert,
                size: LfDimens.iconMd,
                color: c.mutedForeground,
              ),
              onSelected: (action) => switch (action) {
                _MealAction.edit => onEdit(),
                _MealAction.delete => onDelete(),
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: _MealAction.edit, child: Text('编辑')),
                PopupMenuItem(value: _MealAction.delete, child: Text('删除')),
              ],
            ),
          ],
        ),
      ],
    );
    // 内嵌形态(D16):宿主(记录页槽位卡)已经是卡,这里不再套第二层
    // `DesignCard`(描边 + 阴影 + 16 内边距会变成「卡中卡」),也不要
    // `PressableScale`(缩放动画在卡内会像整卡在抖)。点击 / 长按与全部
    // 内容、全部 Key 一个不少。
    if (embedded) {
      return GestureDetector(
        key: Key('meal-${meal.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: selectionMode ? onToggleSelected : onEdit,
        onLongPress: onLongPress,
        child: content,
      );
    }
    return PressableScale(
      child: DesignCard(
        key: Key('meal-${meal.id}'),
        onTap: selectionMode ? onToggleSelected : onEdit,
        onLongPress: onLongPress,
        child: content,
      ),
    );
  }
}

/// 单条菜品行：菜名 + 克数（左）／ 主要宏量彩点 + 克数（右）。
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final MealItemRecord item;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final macro = MealRecordCard.dominantMacro(item.nutrition);
    final (color, grams, label) = switch (macro) {
      MacroKind.protein => (c.protein, item.nutrition.proteinGrams, '蛋白质'),
      MacroKind.carbs => (c.carbs, item.nutrition.carbsGrams, '碳水'),
      MacroKind.fat => (c.fat, item.nutrition.fatGrams, '脂肪'),
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            // 第一案（用户选定）：每项一行「名称 克数g」——克数只出现一次，
            // 宏量只留行尾那枚彩点（色标）。
            '${item.foodName} ${_grams(item.grams)}g',
            style: LfText.body.copyWith(color: c.cardForeground),
            // 2026-10-14(docs/33 阶段 2B,2A 渲染审看登记的缺陷 3):原先
            // `maxLines: 1 + ellipsis` 会把长菜名裁成「番茄牛腩煲 32...」。
            // 数据必须原样交给界面,截断只能由渲染层做——而这里正确的做法是
            // **折行扩高**(A `.meal-meta{overflow-wrap:anywhere}` 同义):
            // 行高随内容长,克数/宏量点/读屏语义都不动。
          ),
        ),
        const SizedBox(width: LfDimens.spaceSmall),
        // 主导宏量：**只留 8dp 彩点**（色标），不再在项行里再报一次克数
        // ——2026-10-16 用户「很多标签文字」：每行两个数字（食物克数 + 宏量
        // 克数）在条目多时互相干扰，而食物克数才是这一行的主信息。
        // 读屏仍把彩点补成完整一句（小彩点不能是唯一信息来源，docs/21 §2.6.3）。
        Semantics(
          label: '主要$label ${_grams(grams)} 克',
          child: ExcludeSemantics(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      ],
    );
  }
}

enum MacroKind { protein, carbs, fat }

/// 卡内管理菜单的两项动作。
enum _MealAction { edit, delete }

/// `HH:mm`（本地时区）。
String _clockLabel(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}

/// 克数显示：整数不拖小数点（与页面既有格式一致）。
String _grams(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
