import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 「复用历史餐食」弹层（docs/21 §5.3 二级流程；裁决 ② 保留逻辑）。
///
/// **2026-10-16 用户**：「复用历史餐食的界面有点丑，重新优化」——原来是纯
/// `ListTile` 列表（标题 + 三行副题 + 分隔线），在一屏里像一张原始的设置
/// 列表。现在每顿是一条 `DesignCard` 卡片行：
///
/// ```
/// ┌──────────────────────────────────────────────┐
/// │ 09/08 · 早餐                [ 254 kcal ]  (↻) │
/// │ 鸡蛋、鸡蛋 · 备注：早起赶课                    │
/// └──────────────────────────────────────────────┘
/// ```
///
/// * 日期写成 `MM/DD`（弹层里空间紧，年份对「最近记录」没有信息量）；
/// * kcal 用 `LfBadge.mint` —— 与饮食页其余 kcal 徽标同一件；
/// * 右侧圆形复用钮（有 tooltip「复用这一餐」），整卡也可点：行为与原
///   `ListTile` 完全一致（点 = 复用这一餐，返回值是那一餐）。
class MealHistoryDialog extends StatelessWidget {
  const MealHistoryDialog({required this.meals, super.key});

  final List<MealRecord> meals;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '复用历史餐食',
          // 原写法只给了字号没给色 ⇒ 落到 `TextTheme` 默认的纯黑/纯白。
          style: LfText.headline.copyWith(color: c.cardForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Flexible(
          child: SizedBox(
            height: 480,
            child: meals.isEmpty
                ? Center(
                    child: Text(
                      '暂无可复用的历史餐食。',
                      style: LfText.body.copyWith(color: c.mutedForeground),
                    ),
                  )
                : ListView.separated(
                    itemCount: meals.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: LfDimens.spaceSmall),
                    itemBuilder: (context, index) =>
                        _HistoryMealCard(meal: meals[index]),
                  ),
          ),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        Align(
          alignment: Alignment.centerLeft,
          // 弹层内的次级行动归 B6（§3.8）。
          child: LfTextButton(
            label: '取消',
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }
}

class _HistoryMealCard extends StatelessWidget {
  const _HistoryMealCard({required this.meal});

  final MealRecord meal;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final kcal = meal.nutrition.kcal.round();
    final notes = meal.notes?.trim() ?? '';
    final summary = meal.items.map((item) => item.foodName).join('、');
    return DesignCard(
      key: Key('history-meal-card-${meal.localDate}'),
      padding: const EdgeInsets.fromLTRB(
        LfDimens.spaceMedium,
        LfDimens.spaceSmallPlus,
        LfDimens.spaceSmall,
        LfDimens.spaceSmallPlus,
      ),
      onTap: () => Navigator.pop(context, meal),
      semanticLabel: '复用 ${meal.slot.label}：$summary，$kcal 千卡',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${_monthDay(meal.localDate)} · ${meal.slot.label}',
                      style: LfText.body.copyWith(
                        color: c.cardForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: LfDimens.spaceSmall),
                    LfBadge.mint('$kcal kcal'),
                  ],
                ),
                const SizedBox(height: LfDimens.spaceXSmall),
                Text(
                  notes.isEmpty ? summary : '$summary · 备注：$notes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          // 圆形复用钮：视觉是「再吃一次」，命中与整卡同一条行为（不新增
          // 写入路径——返回选中的那一餐，复用仍由调用方负责）。
          LfCircleIconButton(
            key: Key('history-meal-reuse-${meal.localDate}'),
            icon: Icons.refresh,
            tooltip: '复用这一餐',
            onPressed: () => Navigator.pop(context, meal),
          ),
        ],
      ),
    );
  }
}

/// `yyyy-MM-dd` → `MM/DD`（弹层里年份没有信息量；异常输入原样回显）。
String _monthDay(String localDate) {
  final parts = localDate.split('-');
  if (parts.length != 3) return localDate;
  return '${parts[1]}/${parts[2]}';
}
