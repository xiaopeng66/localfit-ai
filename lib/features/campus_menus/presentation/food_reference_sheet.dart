import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/campus_menus/application/food_reference_service.dart';

/// 「参考食物库」三选一弹层（docs/40 §3.1 / docs/41 §7 建菜匹配）。
///
/// 建食堂菜/改名后本地跑一次匹配（精确名 → 别名 → 归一化），命中就问一次
/// **引用食物库营养（默认） / AI 重新分析 / 先不填**。**不静默填**：
/// 食堂做法（油/盐/份量）与通用食物条目可能不同，自动填会把「引用」伪装成
/// 「实测」；界面上永远并排显示两边的每 100g 值，由用户点一下。
enum FoodReferenceChoice {
  /// 引用食物库营养（把 per100g 写进证据表，origin=food_library，链接 confirmed）。
  adopt,

  /// 走既有 AI 分析（链接保留 suggested，营养由分析落）。
  analyze,

  /// 先不填（什么都不写；证据保持「未分析」）。
  skip,
}

/// 弹层结果：选择 + （adopt 时）用户点中的那条候选。
/// 2026-10-22 用户：「我可以选择用哪一个食物的数据，而不是点击引入后默认第一个」。
class FoodReferenceDecision {
  const FoodReferenceDecision({required this.choice, this.candidate});

  final FoodReferenceChoice choice;

  /// choice == adopt 时非空：用户点中的那条食物。
  final FoodReferenceCandidate? candidate;
}

/// 弹层本体；[FoodReferenceService] 的建议由调用方读好传入（弹层不查库）。
class FoodReferenceSheet extends StatefulWidget {
  const FoodReferenceSheet({
    super.key,
    required this.dishName,
    required this.candidates,
  });

  final String dishName;

  /// 本地匹配候选（2026-10-22 起放宽到包含匹配的**全部**候选，默认 12 条，
  /// 置信度降序）。空列表的弹层没有意义——调用方只在非空时打开本件。
  final List<FoodReferenceCandidate> candidates;

  /// 2026-10-22 用户：「我可以选择用哪一个食物的数据，而不是点击引入后
  /// 默认第一个」——点哪条候选就引用哪条。返回 null = 用户取消。
  static Future<FoodReferenceDecision?> show(
    BuildContext context, {
    required String dishName,
    required List<FoodReferenceCandidate> candidates,
  }) => AppSheet.showCustom<FoodReferenceDecision>(
    context,
    builder: (_) =>
        FoodReferenceSheet(dishName: dishName, candidates: candidates),
  );

  @override
  State<FoodReferenceSheet> createState() => _FoodReferenceSheetState();
}

class _FoodReferenceSheetState extends State<FoodReferenceSheet> {
  /// 用户点中的候选（默认第一条，与旧行为兼容；用户可换成任意一条）。
  late FoodReferenceCandidate _picked = widget.candidates.first;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final top = widget.candidates.first;
    return Column(
      key: const Key('food-reference-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '食物库里有「${widget.dishName}」吗？',
          style: LfText.headline.copyWith(color: c.cardForeground),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        Text(
          // 把「为什么不自动填」一句话说清（docs/40 §3.1 的理由）。
          '本地匹配到食物库条目。点选要用哪一条（品牌会显示），再点「引用食物库营养」；食堂做法可能不同，也可以走 AI 分析或先不填。',
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Flexible(
          child: SingleChildScrollView(
            // `RV4-P2-12`（R6）：候选卡之间必须有间距。原来 `Column` 直排 +
            // 每张自带 1px 描边 ⇒ 相邻两张贴在一起像共享一条边（用户原话
            // 「边缘重叠」）。用 `ListView.separated` 给 8dp 间隙。
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: widget.candidates.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: LfDimens.spaceSmall),
              itemBuilder: (context, index) {
                final candidate = widget.candidates[index];
                return _CandidateRow(
                  candidate: candidate,
                  picked: candidate.foodId == _picked.foodId,
                  onTap: () => setState(() => _picked = candidate),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        LfPrimaryButton(
          key: const Key('food-reference-adopt'),
          label: '引用食物库营养',
          onPressed: () => Navigator.of(context).pop(
            FoodReferenceDecision(
              choice: FoodReferenceChoice.adopt,
              candidate: _picked,
            ),
          ),
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        // `RV4-P2-12`（R7）：两枚次级动作**并排**（原来上下堆叠占两行）。
        // 320dp + 2.0× 下两个 `Expanded` 会挤字，所以用 `Wrap` 兜底折行。
        Wrap(
          spacing: LfDimens.spaceSmall,
          runSpacing: LfDimens.spaceXSmall,
          children: [
            LfTextButton(
              key: const Key('food-reference-analyze'),
              icon: Icons.auto_awesome_outlined,
              label: '让 AI 重新分析',
              onPressed: () => Navigator.of(context).pop(
                const FoodReferenceDecision(
                  choice: FoodReferenceChoice.analyze,
                ),
              ),
            ),
            LfTextButton(
              key: const Key('food-reference-skip'),
              label: '先不填',
              onPressed: () => Navigator.of(context).pop(
                const FoodReferenceDecision(choice: FoodReferenceChoice.skip),
              ),
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        // `RV4-P2-12`（R7）：来源/证据双徽标**删掉**——弹层在「决策前」，
        // 菜还没有营养、来源尚未确定，这两枚徽标在这个语境里没有信息量。
        // （docs/21 附录 D2 已同步标注退役。）
        Text(
          // 机器口吻（「匹配分 0.95」）改成一句人话，但保留精确/模糊的判断。
          top.recommendAdopt
              ? '按名称精确匹配到；点哪条就用它的每 100g 数据。'
              : '按名称模糊匹配到的候选；点哪条就用它的每 100g 数据。',
          textAlign: TextAlign.center,
          style: LfText.micro.copyWith(color: c.mutedForeground),
        ),
      ],
    );
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow({
    required this.candidate,
    required this.picked,
    required this.onTap,
  });

  final FoodReferenceCandidate candidate;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brand = candidate.brand?.trim() ?? '';
    return GestureDetector(
      key: Key('food-reference-candidate-${candidate.foodId}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(LfDimens.spaceSmall),
        decoration: BoxDecoration(
          color: picked ? c.primary.withValues(alpha: 0.08) : c.background,
          borderRadius: BorderRadius.circular(LfDimens.radiusMd),
          // `RV4-P2-12`（R6）：描边宽度**恒定**。原来选中 1.5 / 未选 1 ⇒
          // 选中时卡片高 1dp，整列会跳一下。选中改用颜色 + 底色表达。
          border: Border.all(color: picked ? c.primary : c.border, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 2026-10-22 用户：「引用食物库的数据一定要显示品牌」。
                  Text(
                    brand.isEmpty
                        ? candidate.foodName
                        : '${candidate.foodName}（$brand）',
                    style: LfText.bodyStrong.copyWith(color: c.cardForeground),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${candidate.kcalPer100g.toStringAsFixed(0)} kcal/100g · '
                    '蛋白 ${candidate.proteinPer100g.toStringAsFixed(1)}g · '
                    '碳水 ${candidate.carbsPer100g.toStringAsFixed(1)}g · '
                    '脂肪 ${candidate.fatPer100g.toStringAsFixed(1)}g',
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
                ],
              ),
            ),
            if (picked) Icon(Icons.check_circle, size: 20, color: c.primary),
          ],
        ),
      ),
    );
  }
}
