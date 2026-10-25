import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_button_states.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/app/design/widgets/lf_evidence_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';
import 'package:localfit_ai/features/food_scan/application/meal_scan_candidate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_estimate.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';

/// 置信度 chip（docs/07 §6.3）：高 = mint-100 / 中 = carbs-100 / 低 = muted。
///
/// 拍照页的**结果卡**不用它（docs/21 §5.4 那里是「置信度」标签 + `h-1.5`
/// 进度条 + 百分比三件套）；本件保留给 `ScanDraftCard` 这类多候选并置的
/// 场景——那里一行放不下每项一条进度条。
final class ScanConfidenceChip extends StatelessWidget {
  const ScanConfidenceChip({required this.confidence, super.key});

  final double confidence;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final percent = (confidence * 100).round();
    final (label, background, foreground) = confidence >= 0.7
        ? ('高', c.evidenceA, c.cardForeground)
        : confidence >= 0.4
        ? ('中', c.evidenceB, c.cardForeground)
        : ('低', c.muted, c.mutedForeground);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.spaceSmall,
        vertical: LfDimens.spaceMicro,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(LfDimens.radiusFull),
      ),
      child: Text(
        '$label · 置信度 $percent%',
        style: LfText.label.copyWith(color: foreground),
      ),
    );
  }
}

final class ScanProgressCard extends StatelessWidget {
  const ScanProgressCard({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DesignCard(
      padding: const EdgeInsets.all(LfDimens.spaceLargePlus),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: LfDimens.spaceMedium),
          Text(
            message,
            textAlign: TextAlign.center,
            style: LfText.body.copyWith(color: c.cardForeground),
          ),
        ],
      ),
    );
  }
}

final class ScanRecognitionProgressCard extends StatefulWidget {
  const ScanRecognitionProgressCard({
    required this.onCancel,
    this.image,
    super.key,
  });

  final VoidCallback onCancel;

  /// 识别中的本地预览（docs/21 §3）：照片呼吸缩放 + 三行骨架；
  /// 传 null 时保持旧版纯进度卡形态。
  final PreparedMealImage? image;

  @override
  State<ScanRecognitionProgressCard> createState() =>
      _ScanRecognitionProgressCardState();
}

class _ScanRecognitionProgressCardState
    extends State<ScanRecognitionProgressCard>
    with SingleTickerProviderStateMixin {
  // 呼吸半周期 600ms：正反各 600ms 组成 1200ms 一个完整呼吸周期（同骨架）。
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
    reverseDuration: const Duration(milliseconds: 600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.image == null || AppMotion.reduced(context)) {
      _breath.stop();
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final image = widget.image;
    return DesignCard(
      key: const Key('scan-recognizing'),
      padding: const EdgeInsets.all(LfDimens.spaceLargePlus),
      child: Column(
        children: [
          if (image != null) ...[
            _BreathingPhoto(breath: _breath, image: image),
            const SizedBox(height: LfDimens.spaceMedium),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: LfDimens.spaceMedium),
          ] else
            const CircularProgressIndicator(),
          Text(
            '正在发送并分析当前图片…',
            textAlign: TextAlign.center,
            style: LfText.body.copyWith(color: c.cardForeground),
          ),
          const SizedBox(height: LfDimens.spaceSmall),
          Text(
            '不会自动重试；取消后本地预览会保留。',
            textAlign: TextAlign.center,
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          // 取消类动作 = §3.8 B6 文字按钮。
          LfTextButton(
            key: const Key('scan-cancel-recognition'),
            label: '取消分析',
            icon: Icons.cancel_outlined,
            onPressed: widget.onCancel,
          ),
        ],
      ),
    );
  }
}

/// 识别中的照片：减弱动画静止，否则 1200ms 呼吸缩放（1.00→1.03）。
class _BreathingPhoto extends StatelessWidget {
  const _BreathingPhoto({required this.breath, required this.image});

  final AnimationController breath;
  final PreparedMealImage image;

  @override
  Widget build(BuildContext context) {
    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(LfDimens.radiusLg),
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: Image.file(
          File(image.path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const SizedBox(
            height: 160,
            child: AppErrorText('照片预览暂时无法显示；识别完成后会恢复预览。'),
          ),
        ),
      ),
    );
    if (AppMotion.reduced(context)) return photo;
    return AnimatedBuilder(
      animation: breath,
      builder: (context, child) {
        final scale = 1.0 + 0.03 * breath.value;
        return Transform.scale(scale: scale, child: child);
      },
      child: photo,
    );
  }
}

final class ScanPreviewCard extends StatelessWidget {
  const ScanPreviewCard({
    required this.image,
    required this.onDiscard,
    required this.discardEnabled,
    this.aiEstimatedGrams,
    this.previewKey = const Key('scan-preview'),
    super.key,
  });

  final PreparedMealImage image;
  final VoidCallback onDiscard;
  final bool discardEnabled;

  /// 照片框的 Key。页面同时挂两张预览卡（餐前 + 剩余）时必须各自给一个，
  /// 否则同一个键同屏出现两次，`find.byKey` 直接抛 Too many elements。
  final Key previewKey;

  /// AI 估算的剩余/餐前克数，用于在预览卡底部展示简易坐标轴图。
  final double? aiEstimatedGrams;

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LfDimens.radiusLg),
            boxShadow: LfShadows.surface(isLight),
          ),
          child: ClipRRect(
            key: previewKey,
            borderRadius: BorderRadius.circular(LfDimens.radiusLg),
            // 4:3 稳定约束（docs/21 §5.8.3）：照片本身可能任意比例，
            // 让容器比例固定、照片 cover 填充，页面高度才不随每次拍摄变化。
            child: AspectRatio(
              key: const Key('scan-photo-preview'),
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(image.path),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(LfDimens.spaceLarge),
                        child: AppErrorText('预览加载失败，但你可以丢弃后重新选择。'),
                      ),
                    ),
                  ),
                  // 覆盖信息条（docs/21 §5.4「已拍摄」+ 照片实际参数）。
                  //
                  // 设计稿右上角是拍摄时间「12:15」，但 `PreparedMealImage`
                  // **没有时间戳字段**——按 §6.1 诚实规则不得编一个时间；
                  // 这里改用真实存在的图像参数（尺寸 / 体积 / 格式）。
                  Positioned(
                    top: LfDimens.spaceMedium,
                    left: LfDimens.spaceMedium,
                    child: _PreviewPill(
                      key: const Key('scan-photo-meta'),
                      text: '已拍摄 · ${imageSummary(image)}',
                    ),
                  ),
                  // 丢弃（左删右阅沿用到顶角：删除在左、信息在侧）。
                  // 压在照片上的动作 = §3.8 B4 的 `overlay` 档（card@90%）。
                  Positioned(
                    top: LfDimens.spaceSmall,
                    right: LfDimens.spaceSmall,
                    child: LfCircleIconButton(
                      key: const Key('scan-discard'),
                      icon: Icons.delete_outline,
                      tooltip: '丢弃此照片',
                      variant: LfCircleIconButtonVariant.overlay,
                      onPressed: discardEnabled ? onDiscard : null,
                    ),
                  ),
                  Positioned(
                    bottom: LfDimens.spaceMedium,
                    right: LfDimens.spaceMedium,
                    // 「重新拍摄」= §3.8 B3 的 `overlay` 档：`拍照识餐.html:327`
                    // 就是 card/90% + foreground 的带字胶囊（不是黑底白字，
                    // 暗色主题下前者仍可读）。
                    child: LfPillButton(
                      key: const Key('cta-retake'),
                      label: '重新拍摄',
                      icon: Icons.photo_camera_outlined,
                      tone: LfPillTone.overlay,
                      onPressed: discardEnabled ? onDiscard : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (aiEstimatedGrams != null) ...[
          const SizedBox(height: LfDimens.spaceSmall),
          _AiEstimateAxis(estimatedGrams: aiEstimatedGrams!),
        ],
      ],
    );
  }
}

/// 照片上的半透明信息药丸（设计稿 `rounded-full px-2.5 py-1 text-xs` 的
/// 「已拍摄」/时间标签）。
final class _PreviewPill extends StatelessWidget {
  const _PreviewPill({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    // 药丸宽度受限于照片宽度：长文案（尺寸 / 体积 / 格式拼起来不短）
    // 在 320dp 上与删除键同屏会顶到边界，所以限制在照片内宽的三分之二后
    // 换行，而不是让 Row 直接溢出。
    constraints: const BoxConstraints(maxWidth: 200),
    padding: const EdgeInsets.symmetric(
      horizontal: LfDimens.spaceSmallPlus,
      vertical: LfDimens.spaceXSmall,
    ),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(LfDimens.radiusFull),
    ),
    child: Text(text, style: LfText.label.copyWith(color: Colors.white)),
  );
}

/// 简易 AI 估算坐标轴：一条横线，末端标记估算克数。
class _AiEstimateAxis extends StatelessWidget {
  const _AiEstimateAxis({required this.estimatedGrams});

  final double estimatedGrams;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final fraction =
        (estimatedGrams / (estimatedGrams * 1.5).clamp(100.0, 2000.0)).clamp(
          0.0,
          1.0,
        );
    return Row(
      children: [
        Text('AI 估算', style: LfText.label.copyWith(color: c.mutedForeground)),
        const SizedBox(width: LfDimens.spaceSmall),
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: fraction),
            duration: const Duration(milliseconds: 200),
            builder: (context, value, child) =>
                LfProgressBar(value: value, height: LfDimens.spaceSmall),
          ),
        ),
        const SizedBox(width: LfDimens.spaceSmall),
        Text(
          '${estimatedGrams.toStringAsFixed(0)}g',
          style: LfText.label.copyWith(color: c.primary),
        ),
      ],
    );
  }
}

// (ScanUploadDisclosureDialog 已移除：它承载的「发送披露」内容——目的地
// 主机 / Base URL / 模型 / 本次发送范围——不改弹层形式，改为**常驻一行**
// 渲染在 food_scan_page.dart 的 `scan-disclosure` 处（用户已否决发送前的
// 二次确认弹层）。组件本身在删除前零生产引用，属 Stage 2 裁定的死组件。)
final class ScanMealSaveConfirmationDialog extends StatelessWidget {
  const ScanMealSaveConfirmationDialog({
    required this.draft,
    this.warnings = const [],
    super.key,
  });

  final MealDraft draft;

  /// 净摄入计算过程中的告警（如剩余量超过餐前量、该项按 0 克计）。
  /// 这些项会被整项扣掉，必须让用户在确认前看到原因。
  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('确认入账？', style: LfText.titleLarge.copyWith(color: c.foreground)),
        const SizedBox(height: LfDimens.spaceMedium),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '餐次：${draft.slot.label}',
                  style: LfText.body.copyWith(color: c.foreground),
                ),
                if (draft.notes case final notes?)
                  Text(
                    '备注：$notes',
                    style: LfText.body.copyWith(color: c.foreground),
                  ),
                const SizedBox(height: LfDimens.spaceMedium),
                for (final item in draft.items)
                  Text(
                    '${item.foodName} · ${number(item.grams)}g · ${item.nutrition.kcal.round()} kcal',
                    style: LfText.body.copyWith(color: c.foreground),
                  ),
                const SizedBox(height: LfDimens.spaceMedium),
                Text(
                  '本地合计 ${draft.nutrition.kcal.round()} kcal · '
                  '蛋白质 ${draft.nutrition.proteinGrams.toStringAsFixed(1)}g · '
                  '碳水 ${draft.nutrition.carbsGrams.toStringAsFixed(1)}g · '
                  '脂肪 ${draft.nutrition.fatGrams.toStringAsFixed(1)}g',
                  style: LfText.body.copyWith(color: c.foreground),
                ),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: LfDimens.spaceMedium),
                  for (final warning in warnings)
                    Text(
                      '提示：$warning',
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                ],
                const SizedBox(height: LfDimens.spaceMedium),
                Text(
                  '确认后将保存到本机并计入今日统计；本次临时图片会在保存成功后清理。',
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: LfDimens.spaceLarge),
        // 弹层底部行动（§3.8）：次级/取消 = B6 文字按钮，主行动 = B2 确认按钮。
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(
              key: const Key('scan-save-cancel'),
              label: '继续编辑',
              onPressed: () => Navigator.pop(context, false),
            ),
            LfConfirmButton(
              // 键名不能也叫 `cta-confirm-scan`：那个键现在属于页面的固定
              // 底部 CTA（docs/21 §5.4），而本弹层弹出时页面仍在树上，
              // 两个同键 widget 同屏会让 `find.byKey` 抛 Too many elements。
              // 这一个的语义是「弹层里最终拍板」，故叫 `scan-save-confirm`。
              key: const Key('scan-save-confirm'),
              label: '确认保存',
              expand: false,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ],
    );
  }
}

final class ScanDraftCard extends StatelessWidget {
  const ScanDraftCard({
    required this.draft,
    required this.onDismiss,
    super.key,
  });

  final MealEstimateDraft draft;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DesignCard(
      key: const Key('scan-draft-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'AI 识别候选',
                  style: LfText.title.copyWith(color: c.cardForeground),
                ),
              ),
              // 卡内关闭 = §3.8 B4 圆钮（muted 档）。
              LfCircleIconButton(
                key: const Key('scan-draft-close'),
                tooltip: '关闭候选草案',
                icon: Icons.close,
                onPressed: onDismiss,
              ),
            ],
          ),
          Text(
            '尚未保存，也未计入今日统计。此只读草案仅在本地食物匹配不可用时显示；确认入账将在下一步骤提供。',
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          for (final item in draft.items) ...[
            Text(
              item.name,
              style: LfText.bodyStrong.copyWith(color: c.cardForeground),
            ),
            const SizedBox(height: LfDimens.spaceMicro),
            Row(
              children: [
                ScanConfidenceChip(confidence: item.confidence),
                const SizedBox(width: LfDimens.spaceSmall),
                Flexible(
                  child: Text(
                    '估算 ${number(item.estimatedGrams)}g'
                    '（${number(item.gramsRange.min)}–${number(item.gramsRange.max)}g）',
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
                ),
              ],
            ),
            if (item.needsConfirmation)
              Text(
                '此项需要你确认。',
                style: LfText.caption.copyWith(color: c.cardForeground),
              ),
            const SizedBox(height: LfDimens.spaceMedium),
          ],
          if (draft.mealNotes case final notes?)
            Text(
              '备注：$notes',
              style: LfText.body.copyWith(color: c.cardForeground),
            ),
          if (draft.warnings.isNotEmpty) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            Text(
              '提示：${draft.warnings.join('；')}',
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }
}

/// 保存成功卡（docs/21 §3）：evidenceA 闪现 600ms 后停稳 + ✓ 300ms 弹簧
/// 弹出；减弱动画直显。成功文案由页面给出（逐字不变）。
final class ScanSuccessCard extends StatelessWidget {
  const ScanSuccessCard({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final row = Row(
      children: [
        AppSuccessCheck(
          icon: Icon(Icons.check_circle, size: 22, color: c.success),
        ),
        const SizedBox(width: LfDimens.spaceMedium),
        Expanded(
          child: Text(
            message,
            style: LfText.body.copyWith(color: c.cardForeground),
          ),
        ),
      ],
    );
    final reduced = AppMotion.reduced(context);
    return TweenAnimationBuilder<Color?>(
      // 闪现：从 primary 半透明淡入到 evidenceA 底（600ms 停稳）。
      tween: ColorTween(
        begin: c.primary.withValues(alpha: 0.30),
        end: c.evidenceA,
      ),
      duration: reduced ? Duration.zero : AppMotion.emphasis,
      builder: (context, color, child) => DecoratedBox(
        key: const Key('scan-success'),
        decoration: BoxDecoration(
          color: color ?? c.evidenceA,
          borderRadius: BorderRadius.circular(LfDimens.radiusLg),
          border: Border.all(color: c.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(LfDimens.cardPadding),
          child: child,
        ),
      ),
      child: row,
    );
  }
}

final class ScanErrorCard extends StatelessWidget {
  const ScanErrorCard({
    required this.message,
    required this.suggestSettings,
    this.onOpenSettings,
    this.onManualEntry,
    super.key,
  });

  final String message;
  final bool suggestSettings;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onManualEntry;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return DecoratedBox(
      key: const Key('scan-error'),
      decoration: BoxDecoration(
        color: c.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
        border: Border.all(color: c.error.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LfDimens.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: LfDimens.iconMd,
                  color: c.error,
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Expanded(
                  child: Text(
                    message,
                    style: LfText.body.copyWith(color: c.cardForeground),
                  ),
                ),
              ],
            ),
            if (suggestSettings && onOpenSettings != null) ...[
              const SizedBox(height: LfDimens.spaceSmall),
              // 错误卡上的行动入口 = §3.8 B6 文字按钮（卡内不做第二个实心
              // 按钮抢主行动）。
              LfTextButton(
                key: const Key('scan-open-settings'),
                label: '检查 AI 设置',
                onPressed: onOpenSettings,
              ),
            ],
            if (onManualEntry != null) ...[
              const SizedBox(height: LfDimens.spaceSmall),
              LfTextButton(label: '改为手动记餐', onPressed: onManualEntry),
            ],
          ],
        ),
      ),
    );
  }
}

String imageSummary(PreparedMealImage image) =>
    '${image.width} × ${image.height} · '
    '${(image.byteLength / 1024).toStringAsFixed(0)} KB · JPEG';

String number(double value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);

/// AI 识别结果卡（docs/21 §5.4 结构树）。
///
/// 只读摘要：菜名 + 来源徽章 + 置信度条 + 预估总热量 + 「修正」入口。
/// 真实的编辑面在候选编辑器里，本卡只回答「认出什么、有多少」。
/// 点击「修正」由页面打开候选编辑器（`cta-edit-items`，二级流程）。
///
/// 营养拆分与 AI 建议**不在本卡内**：设计稿把它们拆成独立的两张卡
/// （一张白卡 + 一张 mint-50 底卡），嵌进来会得到「卡中卡」的层次。
final class ScanResultOverviewCard extends StatelessWidget {
  const ScanResultOverviewCard({
    required this.candidates,
    this.onOpenAnalysis,
    this.onEditItems,
    super.key,
  });

  /// 已解析的候选条目列表（含食物名称与克数）。
  final List<MealScanCandidate> candidates;

  /// 「查看分析过程」——设计稿未画到，按裁决保留为卡内文字入口。
  final VoidCallback? onOpenAnalysis;

  /// 「修正」（`cta-edit-items`）→ 打开候选编辑器。
  final VoidCallback? onEditItems;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final confidence = _averageConfidence(candidates);
    return DesignCard(
      key: const Key('scan-result-overview'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: LfDimens.iconSm, color: c.primary),
              const SizedBox(width: LfDimens.spaceSmall),
              Expanded(
                child: Text(
                  'AI 识别结果',
                  style: LfText.bodyStrong.copyWith(color: c.cardForeground),
                ),
              ),
              if (onEditItems != null)
                // 「修正」= §3.8 B3 的 `soft` 档：`拍照识餐.html:341` 就是
                // mint-50 底 + 品牌字的带字胶囊。
                LfPillButton(
                  key: const Key('cta-edit-items'),
                  label: '修正',
                  icon: Icons.edit_outlined,
                  tone: LfPillTone.soft,
                  onPressed: onEditItems,
                ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          if (candidates.isEmpty)
            Text(
              '暂无识别结果',
              style: LfText.body.copyWith(color: c.mutedForeground),
            )
          else ...[
            Text(
              _dishName(candidates),
              key: const Key('scan-result-name'),
              style: LfText.headline.copyWith(color: c.cardForeground),
            ),
            const SizedBox(height: LfDimens.spaceMedium),
            // 置信度：标签 + h-1.5 进度条 + 百分比（设计稿三件套）。
            Row(
              children: [
                Text(
                  '置信度',
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Expanded(
                  child: LfProgressBar(
                    key: const Key('scan-result-confidence'),
                    value: confidence,
                    height: LfDimens.spaceTiny,
                  ),
                ),
                const SizedBox(width: LfDimens.spaceSmall),
                Text(
                  '${(confidence * 100).round()}%',
                  style: LfText.captionStrong.copyWith(color: c.primary),
                ),
              ],
            ),
          ],
          const SizedBox(height: LfDimens.spaceMedium),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_totalKcal(candidates)} kcal',
                      key: const Key('scan-result-kcal'),
                      style: LfText.displayXLarge.copyWith(
                        color: c.cardForeground,
                      ),
                    ),
                    const SizedBox(height: LfDimens.spaceMicro),
                    Text(
                      '预估总热量',
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                  ],
                ),
              ),
              LfEvidenceBadge.estimated(
                key: const Key('scan-result-source'),
                text: _sourceLabel(candidates),
              ),
            ],
          ),
          if (onOpenAnalysis != null) ...[
            const SizedBox(height: LfDimens.spaceSmall),
            Align(
              alignment: Alignment.centerLeft,
              child: LfTextButton(
                key: const Key('scan-analysis-open'),
                label: '查看分析过程',
                icon: Icons.manage_search_outlined,
                onPressed: onOpenAnalysis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 菜名：单项直接用其名称；多项时首项 + 计数（不把多个菜名硬拼成一句）。
  String _dishName(List<MealScanCandidate> candidates) => candidates.length == 1
      ? candidates.first.estimate.name
      : '${candidates.first.estimate.name} 等 ${candidates.length} 项';

  /// 来源徽章：全部走 AI 估算 = 「AI 估算」；有本地食物参与 = 「本地+AI」。
  ///
  /// 不写「已确认」——用户此刻还没确认任何东西，那档留给保存后的记录。
  String _sourceLabel(List<MealScanCandidate> candidates) =>
      candidates.every((c) => c.usesAiEstimate) ? 'AI 估算' : '含本地食物';

  int _totalKcal(List<MealScanCandidate> candidates) => candidates.fold<int>(
    0,
    (sum, c) => sum + (c.localNutrition?.nutrition.kcal.round() ?? 0),
  );

  double _averageConfidence(List<MealScanCandidate> candidates) =>
      candidates.isEmpty
      ? 0.0
      : candidates.fold(0.0, (sum, c) => sum + c.estimate.confidence) /
            candidates.length;
}

/// 识别食材列表（docs/21 §5.4）：**段标题在卡外**，卡内是带分隔线的行。
///
/// 每行 = 主要宏量色点 + 名称/克数 + 右侧 kcal（设计稿逐行结构）。
/// 「主要宏量」按 4/4/9 热量贡献取最大者，与餐卡的取色规则同一口径。
final class ScanIngredientsSection extends StatelessWidget {
  const ScanIngredientsSection({required this.candidates, super.key});

  final List<MealScanCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      key: const Key('scan-ingredients-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '识别食材',
                style: LfText.bodyStrong.copyWith(color: c.foreground),
              ),
            ),
            Text(
              '${candidates.length} 项',
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        DecoratedBox(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(LfDimens.radiusLg),
            border: Border.all(color: c.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LfDimens.radiusLg),
            child: candidates.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(LfDimens.cardPadding),
                    child: Text(
                      '无候选项',
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < candidates.length; i++) ...[
                        if (i > 0)
                          // 颜色/粗细由 dividerTheme 给（`app_theme.dart`），
                          // 行内只固定占位高度 1。
                          const Divider(height: 1),
                        _IngredientRow(
                          key: Key('scan-ingredient-$i'),
                          candidate: candidates[i],
                          index: i,
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.candidate,
    required this.index,
    super.key,
  });

  final MealScanCandidate candidate;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final nutrition = candidate.localNutrition;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LfDimens.cardPadding,
        vertical: LfDimens.spaceMedium,
      ),
      child: Row(
        children: [
          Container(
            width: LfDimens.spaceSmall,
            height: LfDimens.spaceSmall,
            decoration: BoxDecoration(
              color: _macroColor(c, nutrition?.nutrition),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: LfDimens.spaceMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.estimate.name,
                  style: LfText.bodyStrong.copyWith(color: c.cardForeground),
                ),
                Text(
                  '${number(candidate.grams)} g'
                  '${candidate.selectedFood == null ? ' · AI 估算' : ''}',
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          Text(
            '${nutrition?.nutrition.kcal.round() ?? 0} kcal',
            style: LfText.bodyStrong.copyWith(color: c.cardForeground),
          ),
        ],
      ),
    );
  }

  /// 主要宏量色（4/4/9 热量占比最大者）；无营养数据时用 muted 点。
  Color _macroColor(LfSemanticColors c, NutritionValues? nutrition) {
    if (nutrition == null) return c.mutedForeground;
    final protein = nutrition.proteinGrams * 4;
    final carbs = nutrition.carbsGrams * 4;
    final fat = nutrition.fatGrams * 9;
    if (protein >= carbs && protein >= fat) return c.protein;
    if (carbs >= fat) return c.carbs;
    return c.fat;
  }
}

/// 营养拆分明细（docs/21 §5.4）：总热量 + 三宏量（g + kcal + 占比条）
/// + 底部一条占比摘要。
///
/// **占比 = 该项热量 / 三宏量热量合计**。旧实现把「该项热量 / 该项热量」
/// 当成占比，于是三条横条恒为满格、百分比恒为 100%（脂肪因 4/9 系数不同
/// 得到 44%）——看着像「全是蛋白」，其实是分母用错。由 4/4/9 反推，三项
/// 占比之和恒为 100%，正是设计稿 27% / 40% / 33% 的来源。
final class ScanNutritionBreakdown extends StatelessWidget {
  const ScanNutritionBreakdown({required this.candidates, super.key});

  final List<MealScanCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final totals = _totals;
    return DesignCard(
      key: const Key('scan-nutrition-breakdown'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '营养拆分',
                  style: LfText.bodyStrong.copyWith(color: c.cardForeground),
                ),
              ),
              Text(
                '总 ${totals.kcal} kcal',
                key: const Key('scan-breakdown-total'),
                style: LfText.caption.copyWith(color: c.mutedForeground),
              ),
            ],
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          _MacroRow(
            key: const Key('scan-breakdown-protein'),
            label: '蛋白质',
            grams: totals.proteinGrams,
            kcal: totals.proteinKcal,
            ratio: totals.proteinRatio,
            color: c.protein,
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          _MacroRow(
            key: const Key('scan-breakdown-carbs'),
            label: '碳水',
            grams: totals.carbsGrams,
            kcal: totals.carbsKcal,
            ratio: totals.carbsRatio,
            color: c.carbs,
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          _MacroRow(
            key: const Key('scan-breakdown-fat'),
            label: '脂肪',
            grams: totals.fatGrams,
            kcal: totals.fatKcal,
            ratio: totals.fatRatio,
            color: c.fat,
          ),
          const SizedBox(height: LfDimens.spaceMedium),
          // 颜色/粗细交给 dividerTheme；这里只固定占位高度。
          const Divider(height: 1),
          const SizedBox(height: LfDimens.spaceMedium),
          Wrap(
            spacing: LfDimens.spaceSmall,
            runSpacing: LfDimens.spaceMicro,
            children: [
              Text(
                '蛋白质 ${totals.proteinPercent}%',
                style: LfText.micro.copyWith(color: c.mutedForeground),
              ),
              Text('·', style: LfText.micro.copyWith(color: c.mutedForeground)),
              Text(
                '碳水 ${totals.carbsPercent}%',
                style: LfText.micro.copyWith(color: c.mutedForeground),
              ),
              Text('·', style: LfText.micro.copyWith(color: c.mutedForeground)),
              Text(
                '脂肪 ${totals.fatPercent}%',
                style: LfText.micro.copyWith(color: c.mutedForeground),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ({
    int kcal,
    double proteinGrams,
    double carbsGrams,
    double fatGrams,
    int proteinKcal,
    int carbsKcal,
    int fatKcal,
    double proteinRatio,
    double carbsRatio,
    double fatRatio,
    int proteinPercent,
    int carbsPercent,
    int fatPercent,
  })
  get _totals {
    final protein = candidates.fold(
      0.0,
      (s, c) => s + (c.localNutrition?.nutrition.proteinGrams ?? 0),
    );
    final carbs = candidates.fold(
      0.0,
      (s, c) => s + (c.localNutrition?.nutrition.carbsGrams ?? 0),
    );
    final fat = candidates.fold(
      0.0,
      (s, c) => s + (c.localNutrition?.nutrition.fatGrams ?? 0),
    );
    final proteinKcal = (protein * 4).round();
    final carbsKcal = (carbs * 4).round();
    final fatKcal = (fat * 9).round();
    // 分母 = 三宏量热量之和，不是「总热量」——两者在有酒精/纤维等场景下会
    // 不同，而 4/4/9 反推的占比只在宏量之间分配，这样三项恰好合成 100%。
    final totalKcal = proteinKcal + carbsKcal + fatKcal;
    double ratio(int part) => totalKcal > 0 ? part / totalKcal : 0.0;
    int percent(int part) =>
        totalKcal > 0 ? (part * 100 / totalKcal).round() : 0;
    return (
      kcal: totalKcal,
      proteinGrams: protein,
      carbsGrams: carbs,
      fatGrams: fat,
      proteinKcal: proteinKcal,
      carbsKcal: carbsKcal,
      fatKcal: fatKcal,
      proteinRatio: ratio(proteinKcal),
      carbsRatio: ratio(carbsKcal),
      fatRatio: ratio(fatKcal),
      proteinPercent: percent(proteinKcal),
      carbsPercent: percent(carbsKcal),
      fatPercent: percent(fatKcal),
    );
  }
}

class _MacroRow extends StatelessWidget {
  const _MacroRow({
    required this.label,
    required this.grams,
    required this.kcal,
    required this.ratio,
    required this.color,
    super.key,
  });

  final String label;
  final double grams;
  final int kcal;
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: LfDimens.spaceSmall,
              height: LfDimens.spaceSmall,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: LfDimens.spaceTiny),
            Expanded(
              child: Text(
                label,
                style: LfText.caption.copyWith(color: c.cardForeground),
              ),
            ),
            // Flexible（loose）而不是裸 Text：320dp × 2.0× 字号下
            // 「50.0g · 186 kcal」一行放不下，裸 Text 会把圆点和间隙整个
            // 挤出行尾（实测溢出 14px）。允许它换行——§5.8.3「长标题允许
            // 换行，不得用不可见截断掩盖信息」；常规字号下单行原样。
            Flexible(
              child: Text(
                '${grams.toStringAsFixed(1)}g · $kcal kcal',
                style: LfText.caption.copyWith(color: c.cardForeground),
              ),
            ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceXSmall),
        LfProgressBar(value: ratio, color: color, height: LfDimens.spaceSmall),
      ],
    );
  }
}

/// AI 建议卡（docs/21 §5.4）：mint-50 底 + mint-200 描边 + lightbulb。
///
/// 内容来自候选的匹配状态（未匹配 → 走 AI 估算、有歧义 → 列出候选、
/// 需确认 → 提示核对），**不是**设计稿那句演示文案（§6.1 不得冒充事实）。
final class ScanAiAdviceCard extends StatelessWidget {
  const ScanAiAdviceCard({required this.candidates, super.key});

  final List<MealScanCandidate> candidates;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final mint50 = LfColors.mint(brightness).tone(50);
    final mint200 = LfColors.mint(brightness).tone(200);
    final advices = <String>[];
    for (final candidate in candidates) {
      if (candidate.usesAiEstimate) {
        advices.add(
          '「${candidate.estimate.name}」未匹配本地食物，使用 AI 估算营养，保存时会收录到本地食物库。',
        );
      }
      if (candidate.match.suggestions.isNotEmpty) {
        final names = candidate.match.suggestions.map((f) => f.name).join('、');
        advices.add(
          '「${candidate.estimate.name}」有 ${candidate.match.suggestions.length} 个候选：$names',
        );
      }
      if (candidate.estimate.needsConfirmation) {
        advices.add('「${candidate.estimate.name}」需要你确认克数或匹配结果。');
      }
    }
    if (advices.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      key: const Key('scan-ai-advice'),
      decoration: BoxDecoration(
        color: mint50,
        borderRadius: BorderRadius.circular(LfDimens.radiusLg),
        border: Border.all(color: mint200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(LfDimens.cardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: LfDimens.spaceMicro),
              child: Icon(
                Icons.lightbulb_outline,
                size: LfDimens.iconSm,
                color: c.primary,
              ),
            ),
            const SizedBox(width: LfDimens.spaceMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI 建议',
                    style: LfText.captionStrong.copyWith(color: c.primary),
                  ),
                  const SizedBox(height: LfDimens.spaceXSmall),
                  for (final advice in advices)
                    Text(
                      advice,
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
