import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/ai_workbench/application/ai_starter.dart';

// 分组画廊与描述框（docs/32 §4 T6a / §3 D5）。
// 从 `ai_workbench_page.dart` 拆出：维护性审计要求页面文件 ≤500 行。

class AiStarterGallery extends StatelessWidget {
  const AiStarterGallery({required this.starters, this.onGenerate, super.key});

  final List<AiStarter> starters;
  final ValueChanged<String>? onGenerate;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    // 视图 Key 沿用 `ai-workbench-hub`（既有可达性测试按它定位）。
    return Scaffold(
      appBar: AppBar(title: const Text('AI 创作')),
      body: SafeArea(
        child: ListView(
          key: const Key('ai-workbench-hub'),
          padding: const EdgeInsets.all(LfDimens.pagePadding),
          children: [
            for (final group in AiStarterGroup.values) ...[
              Builder(
                builder: (context) {
                  final items = [
                    for (final s in starters)
                      if (s.group == group) s,
                  ];
                  if (items.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.label,
                        style: LfText.captionStrong.copyWith(
                          color: c.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: LfDimens.spaceSmallPlus),
                      for (final starter in items) ...[
                        _StarterCard(
                          starter: starter,
                          onTap: () => _openSheet(context, starter),
                        ),
                        const SizedBox(height: LfDimens.spaceMedium),
                      ],
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: LfDimens.spaceSmall),
            Text(
              '每项任务先生成草案，本地校验通过后再独立确认写入；'
              '草案不会自动成为事实。',
              style: LfText.bodySmall.copyWith(color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context, AiStarter starter) {
    AiStarterSheet.show(context, starter: starter, onGenerate: onGenerate);
  }
}

/// 一张启动卡：图标 + 标题 + 既有描述 + 「描述需求」引导。
class _StarterCard extends StatelessWidget {
  const _StarterCard({required this.starter, required this.onTap});

  final AiStarter starter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final mint = LfColors.mint(brightness);
    return InkWell(
      key: Key('ai-workbench-task-${starter.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(LfDimens.radiusLg),
      child: Semantics(
        button: true,
        label: '${starter.title}：${starter.description}',
        child: Container(
          padding: const EdgeInsets.all(LfDimens.spaceLarge),
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(LfDimens.radiusLg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: mint.tone(100),
                  borderRadius: BorderRadius.circular(LfDimens.radiusSm),
                ),
                child: Icon(
                  starter.icon,
                  size: LfDimens.iconSm,
                  color: LfColors.mintText(brightness),
                ),
              ),
              const SizedBox(width: LfDimens.spaceMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      starter.title,
                      style: LfText.title.copyWith(color: c.cardForeground),
                    ),
                    const SizedBox(height: LfDimens.spaceXSmall),
                    Text(
                      starter.description,
                      style: LfText.label.copyWith(color: c.mutedForeground),
                    ),
                    const SizedBox(height: LfDimens.spaceSmall),
                    Text(
                      '描述需求 →',
                      style: LfText.captionStrong.copyWith(
                        color: LfColors.mintText(brightness),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 描述框弹层（docs/32 §3 D5）：标题=任务名、多行输入、placeholder=
/// 该任务既有 `inputHint`、主按钮「生成」**非空才可点**。
class AiStarterSheet extends StatefulWidget {
  const AiStarterSheet({required this.starter, this.onGenerate, super.key});

  final AiStarter starter;
  final ValueChanged<String>? onGenerate;

  static Future<void> show(
    BuildContext context, {
    required AiStarter starter,
    ValueChanged<String>? onGenerate,
  }) => AppSheet.showCustom<void>(
    context,
    builder: (_) => AiStarterSheet(starter: starter, onGenerate: onGenerate),
  );

  @override
  State<AiStarterSheet> createState() => _AiStarterSheetState();
}

class _AiStarterSheetState extends State<AiStarterSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canGenerate => _controller.text.trim().isNotEmpty;

  void _generate() {
    final input = _controller.text.trim();
    if (input.isEmpty) return;
    final prompt = widget.starter.promptBuilder(input);
    Navigator.of(context).pop();
    widget.onGenerate?.call(prompt);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      key: const Key('ai-starter-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.starter.title,
          style: LfText.title.copyWith(color: c.cardForeground),
        ),
        const SizedBox(height: LfDimens.spaceXSmall),
        Text(
          '描述你的需求，生成后会在「AI 工作台」对话里继续',
          style: LfText.label.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        TextField(
          key: const Key('ai-starter-input'),
          controller: _controller,
          maxLines: 4,
          minLines: 4,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(hintText: widget.starter.inputHint),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(
              label: '取消',
              onPressed: () => Navigator.of(context).pop(),
            ),
            LfConfirmButton(
              key: const Key('ai-starter-generate'),
              expand: false,
              label: '生成',
              onPressed: _canGenerate ? _generate : null,
            ),
          ],
        ),
      ],
    );
  }
}
