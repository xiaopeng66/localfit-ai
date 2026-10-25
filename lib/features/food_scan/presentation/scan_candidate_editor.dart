import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/widgets/app_morph_chip.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_search_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/food_scan/application/conversational_recognition_correction.dart';
import 'package:localfit_ai/features/food_scan/application/meal_scan_candidate.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_widgets.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/app/design/widgets/lf_select_field.dart';

/// 扫描候选编辑器：展示识别结果、克数增减、餐次选择、备注及确认流。
///
/// **docs/21 §3 组件表叫 `MealRecognitionCandidateCard`**，本类是其容器。
/// 候选项卡片由内部 `_CandidateItemCard` 渲染，各自拥有「修正识别」按钮。
class ScanCandidateEditor extends StatefulWidget {
  const ScanCandidateEditor({
    required this.draft,
    required this.searchFoods,
    required this.onChanged,
    required this.onConfirm,
    required this.confirmEnabled,
    required this.saving,
    required this.onDismiss,
    this.onCorrection,
    this.keyPrefix = 'scan-candidate',
    this.confirmLabel = '确认入账',
    super.key,
  });

  final MealScanCandidateDraft draft;
  final Future<List<FoodRecord>> Function(String query) searchFoods;
  final ValueChanged<MealScanCandidateDraft> onChanged;
  final VoidCallback onConfirm;
  final bool confirmEnabled;
  final bool saving;
  final VoidCallback onDismiss;
  final String keyPrefix;

  /// 确认按钮文案；剩余餐食编辑器用「按净摄入入账」区分两者。
  final String confirmLabel;

  /// 对话式识别修正回调：收到 (index, correctedCandidate)。
  final void Function(int index, MealScanCandidate corrected)? onCorrection;

  @override
  State<ScanCandidateEditor> createState() => _ScanCandidateEditorState();
}

class _ScanCandidateEditorState extends State<ScanCandidateEditor> {
  void _openCorrectionForFirst(BuildContext context) {
    final draft = widget.draft;
    if (draft.items.isEmpty) return;
    final firstItem = draft.items.first;
    AppSheet.showCustom<void>(
      context,
      builder: (context) => ScanCorrectionSheet(
        candidate: firstItem,
        onSubmit: (corrected) {
          Navigator.pop(context);
          widget.onCorrection?.call(0, corrected);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DesignCard(
    // 四个键随 [ScanCandidateEditor.keyPrefix] 生成（Round7 阶段 3 · 3-3，D53）：
    // 两个编辑器（餐前 + 剩餐）**可同屏**，此前这四处硬编码 ⇒ 同键两份、
    // 剩餐那把「餐次」根本找不到自己（探针实测 slot=0）。主编辑器的
    // prefix 就是 `scan-candidate` ⇒ 它自己的键名一字不变。
    key: Key('${widget.keyPrefix}-card'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '识别候选与本地营养',
                style: LfText.titleLarge.copyWith(
                  color: context.lf.cardForeground,
                ),
              ),
            ),
            // §3.8 B4：弹层/卡片上的「关闭」是圆形图标钮。
            LfCircleIconButton(
              tooltip: '关闭候选草案',
              icon: Icons.close,
              onPressed: widget.saving ? null : widget.onDismiss,
            ),
          ],
        ),
        Text(
          '营养按匹配的本地食物计算；未匹配项使用 AI 估算营养，保存时自动收录到本地食物库。',
          style: LfText.bodySmall.copyWith(color: context.lf.mutedForeground),
        ),
        Align(
          alignment: Alignment.centerLeft,
          // 次级行动一律 B6（§3.8）。
          child: LfTextButton(
            key: Key('${widget.keyPrefix}-analysis-open'),
            icon: Icons.manage_search_outlined,
            label: '查看分析过程',
            onPressed: () => AppSheet.showCustom<void>(
              context,
              builder: (context) => ScanAnalysisSheet(draft: widget.draft),
            ),
          ),
        ),
        const SizedBox(height: 4),
        // docs/32 §3 D7（需求 66）：统一下拉；保存中禁用（enabled: false）。
        LfSelectField<MealSlot>(
          fieldKey: Key('${widget.keyPrefix}-slot'),
          label: '餐次',
          value: widget.draft.slot,
          options: MealSlot.values,
          optionLabel: (slot) => slot.label,
          enabled: !widget.saving,
          onChanged: (value) =>
              widget.onChanged(widget.draft.copyWith(slot: value)),
        ),
        const SizedBox(height: 8),
        LfTextField(
          fieldKey: Key('${widget.keyPrefix}-notes'),
          label: '备注',
          optional: true,
          initialValue: widget.draft.notes ?? '',
          maxLines: 2,
          onChanged: widget.saving
              ? null
              : (value) {
                  final notes = value.trim();
                  widget.onChanged(
                    notes.isEmpty
                        ? widget.draft.copyWith(clearNotes: true)
                        : widget.draft.copyWith(notes: notes),
                  );
                },
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < widget.draft.items.length; index++) ...[
          _CandidateItemCard(
            // 用估算条目对象做 key：按位置（index）做 key 时移除中间项
            // 会让后续卡片的元素复用错位，克数/备注输入框保留被删项的
            // 文本（initialValue 在元素更新时被忽略），显示与保存不一致。
            key: ObjectKey(widget.draft.items[index].estimate),
            index: index,
            item: widget.draft.items[index],
            keyPrefix: widget.keyPrefix,
            searchFoods: widget.searchFoods,
            onChanged: widget.saving
                ? null
                : (value) =>
                      widget.onChanged(widget.draft.replaceItem(index, value)),
            onRemove: widget.saving
                ? null
                : () => widget.onChanged(widget.draft.removeItem(index)),
            onCorrect: widget.saving
                ? null
                : (corrected) => widget.onCorrection?.call(index, corrected),
          ),
          const SizedBox(height: 12),
        ],
        if (widget.draft.items.isEmpty) const Text('没有保留的候选项；请重新识别或改为手动记餐。'),
        if (widget.draft.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('AI 提示：${widget.draft.warnings.join('；')}'),
        ],
        const SizedBox(height: 12),
        Text(
          '本地合计 ${widget.draft.nutrition.kcal.round()} kcal · '
          '蛋白质 ${widget.draft.nutrition.proteinGrams.toStringAsFixed(1)}g · '
          '碳水 ${widget.draft.nutrition.carbsGrams.toStringAsFixed(1)}g · '
          '脂肪 ${widget.draft.nutrition.fatGrams.toStringAsFixed(1)}g',
        ),
        const SizedBox(height: 8),
        if (widget.saving) ...[
          const Text('正在保存到本机…'),
          const SizedBox(height: 8),
        ] else if (!widget.confirmEnabled) ...[
          const Text('请为每个保留候选项填写有效克数（或移除该项）后再确认入账。'),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              // 并列的三格动作条：取消 = B6，两枚实心 = B1（同高 40，行内
              // 齐平）。B2（h48 + 彩色阴影）只给独立成行/固定底栏的终端确认。
              child: LfTextButton(
                key: Key('${widget.keyPrefix}-cancel'),
                label: '取消',
                onPressed: widget.saving ? null : widget.onDismiss,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LfPrimaryButton(
                // 键名随 [ScanCandidateEditor.keyPrefix] 走，**不叫**
                // `cta-edit-items`：那个键属于结果卡上的「修正」（进编辑面，
                // docs/21 §5.4），而这里的作用是「打开修正弹层」——两件事。
                // 页面上两个编辑器可能并存（餐前 + 剩余），固定键会撞。
                key: Key('${widget.keyPrefix}-edit'),
                expand: true,
                // 裁决 ③（2026-10-15）：与逐项「修正识别」**同一术语**——
                // 这枚钮的动作就是打开修正弹层（只作用于第一项），叫「编辑」
                // 会让人以为它与逐项修正、与结果卡上的「修正」是三件事。
                label: '修正识别',
                onPressed:
                    widget.saving ||
                        widget.draft.items.isEmpty ||
                        widget.onCorrection == null
                    ? null
                    : () => _openCorrectionForFirst(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LfPrimaryButton(
                key: Key('${widget.keyPrefix}-confirm'),
                expand: true,
                busy: widget.saving,
                // 裁决 ④：剩餐编辑器换用 5 字标签后仍可能折行（三分之一宽坑位），
                // 拍死为「单行 + 必要时等比缩小」——整排按钮等高。
                fitLabel: true,
                label: widget.confirmLabel,
                onPressed: widget.confirmEnabled && !widget.saving
                    ? widget.onConfirm
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('确认后将保存到本机并计入今日统计；保存成功后会清理本次临时图片。'),
      ],
    ),
  );
}

final class ScanAnalysisSheet extends StatelessWidget {
  const ScanAnalysisSheet({required this.draft, super.key});

  final MealScanCandidateDraft draft;

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('scan-analysis-sheet'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '分析过程',
        style: LfText.headline.copyWith(color: context.lf.cardForeground),
      ),
      const SizedBox(height: 8),
      Text(
        '这里展示 AI 返回的结构化识别依据，不会展示模型内部思考。营养仍以本地食物库重算为准。',
        style: LfText.bodySmall.copyWith(color: context.lf.mutedForeground),
      ),
      const SizedBox(height: 16),
      Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: draft.items.length,
          separatorBuilder: (_, _) => const Divider(height: 24),
          itemBuilder: (context, index) {
            final item = draft.items[index].estimate;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '估算份量：${number(item.estimatedGrams)}g'
                  '（${number(item.gramsRange.min)}–${number(item.gramsRange.max)}g）',
                ),
                Text('置信度：${(item.confidence * 100).round()}%'),
                Text(
                  draft.items[index].selectedFood == null
                      ? '本地匹配：尚未匹配'
                      : '本地匹配：${draft.items[index].selectedFood!.name}',
                ),
              ],
            );
          },
        ),
      ),
      if (draft.warnings.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('识别提示：${draft.warnings.join('；')}'),
      ],
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerRight,
        child: LfTextButton(
          label: '关闭',
          onPressed: () => Navigator.pop(context),
        ),
      ),
    ],
  );
}

/// 单条识别候选的编辑卡。
///
/// **docs/21 §3 组件表里叫 `MealRecognitionCandidateCard`**，本类即该表的
/// 实现，渲染在 [ScanCandidateEditor] 的候选列表里（`scan-draft` 子树）：
/// 每个候选一行，含克数增减、本地食物匹配、对话式修正与移除。
/// 保持私有 + 现名的原因与 `MealCard` 同（命名口径差异，不是缺失）。
final class _CandidateItemCard extends StatefulWidget {
  const _CandidateItemCard({
    required this.index,
    required this.item,
    required this.keyPrefix,
    required this.searchFoods,
    required this.onChanged,
    required this.onRemove,
    required this.onCorrect,
    super.key,
  });

  final int index;
  final MealScanCandidate item;
  final String keyPrefix;
  final Future<List<FoodRecord>> Function(String query) searchFoods;
  final ValueChanged<MealScanCandidate>? onChanged;
  final VoidCallback? onRemove;

  /// 对话式修正入口。
  final void Function(MealScanCandidate candidate)? onCorrect;

  @override
  State<_CandidateItemCard> createState() => _CandidateItemCardState();
}

/// 克数步进（docs/21 §3）：胶囊 [− 数字 +]，±10g；直接输入保留。
class _CandidateItemCardState extends State<_CandidateItemCard> {
  static const _step = 10.0;

  late final TextEditingController _grams = TextEditingController(
    text: number(widget.item.grams),
  );

  @override
  void didUpdateWidget(_CandidateItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（步进/换食物/删除）更新了克数时同步文本；用户正在输入的
    // 非法中间态（NaN）不覆盖，避免打断键入。
    // `isFinite` 这半个条件才是这句话真正成立的前提：清空输入框或打进非法
    // 字符时 item.grams 就是 NaN，`parsed != NaN` 恒真（NaN ≠ 任何值），
    // 于是每次重建都把文本框回写成 "NaN" —— 用户再也清不掉、也改不动。
    final parsed = double.tryParse(_grams.text.trim());
    if (widget.item.grams.isFinite && parsed != widget.item.grams) {
      _grams.text = number(widget.item.grams);
    }
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  void _stepBy(double delta) {
    // NaN 也是 `double.tryParse('NaN')` 的返回值（不是 null），所以非法
    // 中间态要按「没解析出数字」处理，退回 AI 估算值继续步进；否则
    // `math.max(1.0, NaN)` 仍是 NaN，± 会一起卡死。
    final parsed = double.tryParse(_grams.text.trim());
    final current = parsed != null && parsed.isFinite
        ? parsed
        : widget.item.estimate.estimatedGrams;
    final next = math.max(1.0, current + delta);
    _grams.text = number(next);
    widget.onChanged?.call(widget.item.withGrams(next));
  }

  @override
  Widget build(BuildContext context) {
    final nutrition = widget.item.localNutrition;
    final item = widget.item;
    final onChanged = widget.onChanged;
    // 卡内子块收归 §3.1 的 MutedBlock（原手写 1px outlineVariant + 12 圆角的
    // 描边盒）——设计稿卡内子块一律 muted 底，不叠第二层描边。
    return MutedBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.estimate.name,
                  style: LfText.title.copyWith(
                    color: context.lf.cardForeground,
                  ),
                ),
              ),
              // 卡内移除 = §3.8 B4 圆钮（muted 档）。
              LfCircleIconButton(
                key: Key('${widget.keyPrefix}-remove-${widget.index}'),
                tooltip: '移除 ${item.estimate.name}',
                onPressed: widget.onRemove,
                icon: Icons.remove_circle_outline,
              ),
            ],
          ),
          Text(
            'AI 估算 ${number(item.estimate.estimatedGrams)}g '
            '（${number(item.estimate.gramsRange.min)}–${number(item.estimate.gramsRange.max)}g）',
            style: LfText.bodySmall.copyWith(color: context.lf.mutedForeground),
          ),
          const SizedBox(height: 4),
          ScanConfidenceChip(confidence: item.estimate.confidence),
          const SizedBox(height: 8),
          // 标签在步进器行**上方**（docs/21 §3.3）：放在行内会与 ± 按钮
          // 抢水平空间，窄屏/大字号下先把标签挤成两行。
          const AppFieldLabel(label: '确认克数', unit: 'g'),
          const SizedBox(height: LfDimens.spaceTiny),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 【刻意保留裸 `IconButton`】± 是**贴着输入框**的数值步进控件，
              // 不是独立动作：换成 36dp 圆形底（§3.8 B4）会与输入框的高度/
              // 内边距打架，且步进器在设计稿里从未以圆钮形态出现。字色仍由
              // `iconButtonTheme`（mutedForeground）给，未脱主题。
              IconButton(
                key: Key('${widget.keyPrefix}-grams-minus-${widget.index}'),
                tooltip: '减少 10g',
                onPressed: onChanged == null ? null : () => _stepBy(-_step),
                icon: const Icon(Icons.remove),
              ),
              Expanded(
                child: Semantics(
                  label: '确认克数（g）',
                  child: TextFormField(
                    key: Key('${widget.keyPrefix}-grams-${widget.index}'),
                    controller: _grams,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    enabled: onChanged != null,
                    onChanged: (value) {
                      final grams = double.tryParse(value.trim());
                      onChanged?.call(item.withGrams(grams ?? double.nan));
                    },
                  ),
                ),
              ),
              IconButton(
                key: Key('${widget.keyPrefix}-grams-plus-${widget.index}'),
                tooltip: '增加 10g',
                onPressed: onChanged == null ? null : () => _stepBy(_step),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (item.selectedFood case final food?) ...[
            Text('本地食物：${food.name}'),
            if (nutrition != null) Text(_nutritionText(nutrition)),
          ] else ...[
            // 没匹配本地食物不等于没营养：AI 给了估算时 `localNutrition`
            // 会用它兜底，这一项照样计入合计并按它入账。此时说「无法计算
            // 营养」会让用户以为这一项没进合计（net-intake 审计 D4）。
            if (item.usesAiEstimate) ...[
              const Text('尚未匹配本地食物，本项营养暂用 AI 估算（保存时自动收录到本地食物库）。'),
              if (nutrition != null) Text(_nutritionText(nutrition)),
            ] else
              Text(_unresolvedMessage(item.match.status)),
            if (item.match.suggestions.isNotEmpty)
              Wrap(
                spacing: 8,
                children: item.match.suggestions
                    .map(
                      // 裸 ActionChip 换成 §3 的 AppMorphChip（动作语义走
                      // `onPressed`，与原生 Chip 一致）。
                      (food) => AppMorphChip(
                        label: food.name,
                        onPressed: onChanged == null
                            ? null
                            : () => onChanged(item.withSelectedFood(food)),
                      ),
                    )
                    .toList(growable: false),
              ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: LfTextButton(
              key: Key('scan-candidate-search-${widget.index}'),
              icon: Icons.search,
              label: '从本地食物库选择',
              onPressed: onChanged == null ? null : () => _selectFood(context),
            ),
          ),
          if (widget.onCorrect != null) ...[
            const SizedBox(height: 4),
            LfTextButton(
              key: Key('${widget.keyPrefix}-correct-${widget.index}'),
              icon: Icons.edit_note_outlined,
              label: '修正识别',
              onPressed: () => _openCorrection(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selectFood(BuildContext context) async {
    final selected = await AppSheet.showCustom<FoodRecord>(
      context,
      builder: (context) =>
          _LocalFoodPickerDialog(searchFoods: widget.searchFoods),
    );
    if (selected != null) {
      widget.onChanged?.call(widget.item.withSelectedFood(selected));
    }
  }

  void _openCorrection(BuildContext context) {
    AppSheet.showCustom<void>(
      context,
      builder: (context) => ScanCorrectionSheet(
        candidate: widget.item,
        onSubmit: (corrected) {
          Navigator.pop(context);
          widget.onCorrect?.call(corrected);
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  /// 四项营养的同一套渲染：本地食物与 AI 估算两条来源共用，避免只有一处
  /// 显示数字、另一处只给结论。
  String _nutritionText(MealItemDraft nutrition) =>
      '${nutrition.nutrition.kcal.round()} kcal · '
      '蛋白质 ${nutrition.nutrition.proteinGrams.toStringAsFixed(1)}g · '
      '碳水 ${nutrition.nutrition.carbsGrams.toStringAsFixed(1)}g · '
      '脂肪 ${nutrition.nutrition.fatGrams.toStringAsFixed(1)}g';

  String _unresolvedMessage(LocalFoodMatchStatus status) => switch (status) {
    LocalFoodMatchStatus.ambiguous => '匹配结果不唯一，请选择正确的本地食物。',
    LocalFoodMatchStatus.suggestion => '以下仅为建议，请确认本地食物。',
    LocalFoodMatchStatus.unmatched => '尚未匹配本地食物，无法计算营养。',
    _ => '请选择本地食物。',
  };
}

final class _LocalFoodPickerDialog extends StatefulWidget {
  const _LocalFoodPickerDialog({required this.searchFoods});

  final Future<List<FoodRecord>> Function(String query) searchFoods;

  @override
  State<_LocalFoodPickerDialog> createState() => _LocalFoodPickerDialogState();
}

class _LocalFoodPickerDialogState extends State<_LocalFoodPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '选择本地食物',
        style: LfText.headline.copyWith(color: context.lf.cardForeground),
      ),
      const SizedBox(height: 12),
      // 弹层限高 0.9 屏高：固定 420 在矮窗口（小窗/横屏）会溢出，用 Flexible 收缩。
      Flexible(
        child: SizedBox(
          height: 420,
          child: Column(
            children: [
              LfSearchField(
                fieldKey: const Key('scan-food-search'),
                hintText: '搜索本地食物',
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<FoodRecord>>(
                  future: widget.searchFoods(_query),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const AppErrorText('本地食物加载失败，请重试。');
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final foods = snapshot.data!;
                    if (foods.isEmpty) {
                      return const Center(child: Text('未找到本地食物。'));
                    }
                    // 行文字显式并入主题字体（Round7 阶段 3 · 3-3，D54）：
                    // `ListTile` 的标题/副标题走它自己的 `titleTextStyle`
                    // （M3 默认来自 `textTheme`），而本仓主题的正文档不带族
                    // ——测试帧里渲染成 `.notdef` 空方框（与 3-2b 缺陷 ⑫
                    // 同族同因）。merge 只补族与色，字号/字重仍由 LfText 说。
                    final textTheme = Theme.of(context).textTheme;
                    final c = context.lf;
                    return ListView.builder(
                      itemCount: foods.length,
                      itemBuilder: (context, index) {
                        final food = foods[index];
                        return ListTile(
                          title: Text(
                            food.name,
                            style: textTheme.bodyMedium?.merge(
                              LfText.body.copyWith(color: c.cardForeground),
                            ),
                          ),
                          subtitle: Text(
                            // 品牌要进这一行：同名不同品牌（「米饭」在真实库
                            // 有四条）时只印热量会让用户选错一条、记错营养。
                            '${food.brand?.trim().isEmpty ?? true ? '' : '${food.brand!.trim()} · '}'
                            '${food.kcalPer100g.round()} kcal / 100g',
                            style: textTheme.bodyMedium?.merge(
                              LfText.caption.copyWith(color: c.mutedForeground),
                            ),
                          ),
                          onTap: () => Navigator.pop(context, food),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: LfTextButton(
          label: '取消',
          onPressed: () => Navigator.pop(context),
        ),
      ),
    ],
  );
}

/// 对话式修正 sheet：编辑名称 + 克数，本地重新计算。
final class ScanCorrectionSheet extends StatefulWidget {
  const ScanCorrectionSheet({
    required this.candidate,
    required this.onSubmit,
    required this.onCancel,
    super.key,
  });

  final MealScanCandidate candidate;
  final void Function(MealScanCandidate corrected) onSubmit;
  final VoidCallback onCancel;

  @override
  State<ScanCorrectionSheet> createState() => _ScanCorrectionSheetState();
}

class _ScanCorrectionSheetState extends State<ScanCorrectionSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.candidate.estimate.name,
  );
  late final TextEditingController _grams = TextEditingController(
    text: number(widget.candidate.grams),
  );

  /// 拒绝原因画在弹层里：弹层挂根导航器盖住页面，页面级 snackbar 会被挡住，
  /// 用户只会看到「点了应用没反应」。
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _grams.dispose();
    super.dispose();
  }

  void _done() {
    final correction = ConversationalRecognitionCorrection(
      candidate: widget.candidate,
      searchFoods: (_) async => [],
    );
    final nameResult = correction.correctName(_name.text);
    if (nameResult.isRejected) {
      setState(() => _error = nameResult.rejection);
      return;
    }
    final gramsResult = correction.correctGrams(
      double.tryParse(_grams.text.trim()) ?? double.nan,
    );
    if (gramsResult.isRejected) {
      setState(() => _error = gramsResult.rejection);
      return;
    }
    // 链式应用：先改名，再改克数。
    final corrected = nameResult.value!.withGrams(gramsResult.value!.grams);
    widget.onSubmit(corrected);
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('scan-correction-sheet'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        '修正识别',
        style: LfText.headline.copyWith(color: context.lf.cardForeground),
      ),
      const SizedBox(height: 16),
      LfTextField(
        fieldKey: const Key('scan-correction-name'),
        label: '食物名称',
        controller: _name,
      ),
      const SizedBox(height: 12),
      AppNumberField(
        fieldKey: const Key('scan-correction-grams'),
        label: '克数',
        unit: 'g',
        controller: _grams,
        hintText: '如 150',
      ),
      if (_error case final error?) ...[
        const SizedBox(height: 12),
        Text(
          error,
          key: const Key('scan-correction-error'),
          style: LfText.bodySmall.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          // 弹层内的次级取消 = B6，终端确认 = B2（§3.8）。
          LfTextButton(
            key: const Key('scan-correction-cancel'),
            label: '取消',
            onPressed: widget.onCancel,
          ),
          LfConfirmButton(
            key: const Key('scan-correction-submit'),
            expand: false,
            label: '应用',
            onPressed: _done,
          ),
        ],
      ),
    ],
  );
}
