import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_top_bar.dart';

/// 输入栏（docs/21 §3.4 / §5.7 结构树；P10 需求 36 删语音后**单状态**）：
///  * 行 = 图片按钮 + 文字输入 + 发送按钮（AI 回复中变停止按钮）。
///
/// 原「录音行」（脉冲红点 + 波形 + 计时）与麦克风按钮已随语音输入整族删除；
/// 「双状态」中另一态 = 发送按钮 ⇄ 停止按钮。
class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSendText,
    this.onPickImage,
    this.focusNode,
    this.sending = false,
    this.onStop,
    this.enabled = true,
    this.hintText,
  });

  final TextEditingController controller;

  /// 输入框焦点（「我可以吃吗」chip 预填后聚焦用）。
  final FocusNode? focusNode;
  final ValueChanged<String> onSendText;
  final VoidCallback? onPickImage;

  /// AI 正在流式回复：发送按钮变成停止按钮（`btn-stop`）。
  final bool sending;
  final VoidCallback? onStop;
  final bool enabled;

  /// 输入框占位（`RV4-P2-05`：会话结束后变「开始新对话…」）。null = 默认文案。
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      key: const Key('input-row-text'),
      padding: const EdgeInsets.fromLTRB(
        LfDimens.spaceMedium,
        0,
        LfDimens.spaceMedium,
        LfDimens.spaceSmall,
      ),
      child: Row(
        children: [
          LfCircleIconButton(
            key: const Key('btn-image-upload'),
            icon: Icons.add,
            tooltip: '添加图片',
            onPressed: onPickImage,
          ),
          Expanded(
            child: TextField(
              key: const Key('ai-chat-text-input'),
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              style: LfText.body.copyWith(color: c.cardForeground),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.muted,
                hintText: hintText ?? '对话记录饮食和运动',
                hintStyle: LfText.body.copyWith(color: c.mutedForeground),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LfDimens.radiusLg),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LfDimens.radiusLg),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LfDimens.radiusLg),
                  borderSide: BorderSide(color: c.ring, width: 2),
                ),
              ),
              onSubmitted: onSendText,
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          if (sending)
            LfCircleIconButton(
              key: const Key('btn-stop'),
              icon: Icons.stop_rounded,
              iconSize: LfDimens.iconSm,
              tooltip: '停止生成',
              background: c.primary,
              iconColor: c.primaryForeground,
              onPressed: onStop,
            )
          else
            LfCircleIconButton(
              key: const Key('btn-send'),
              icon: Icons.send_rounded,
              iconSize: LfDimens.iconSm,
              tooltip: '发送',
              background: c.primary,
              iconColor: c.primaryForeground,
              onPressed: () => onSendText(controller.text),
            ),
        ],
      ),
    );
  }
}

/// 输入栏上方快捷 chip（docs/21 §3.4 / AI 工作.html）：
/// **`确认应用`**（check + mint-50 底 + mint-200 描边 + primary 文字）、
/// `我可以吃吗`（utensils）、`AI 创作`（spark，A `app.js:207` 的第三条
/// quick chip）——后两个是 muted 底。
///
/// **2026-10-23 用户**：「底部拍照识别删掉改『确认应用』」——第一枚 chip
/// 从 `拍照识别`（推入 `/meal-recognition`）换成「应用当前这条 AI 提议」，
/// 与编辑卡上的「应用」是同一个动作、同一个执行器。三枚仍**等宽占满一整行**
/// （2026-10-16 用户裁决：`手动记录` 下线后不横滑），大字体下文案折行而不是
/// 溢出（与 `LfSegmentControl` 同一套大字策略）。
class ChatQuickChips extends StatelessWidget {
  const ChatQuickChips({super.key, required this.onChipTap});

  /// chip key → 文案已固定（applyEdits / can-i-eat / ai-create）。
  final ValueChanged<ChatQuickChip> onChipTap;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    Widget chip(
      String label,
      IconData icon,
      ChatQuickChip chipKey, {
      required Color bg,
      Color? border,
      required Color fg,
      required Key key,
    }) {
      return InkWell(
        key: key,
        onTap: () => onChipTap(chipKey),
        borderRadius: BorderRadius.circular(LfDimens.radiusFull),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(LfDimens.radiusFull),
            border: Border.all(color: border ?? c.border),
          ),
          // 【2026-10-25 用户：「今天还剩多少的按钮文字换行了」】
          // 原来三枚 chip 用 `Expanded` **等分**整行，而文案长度不同
          // （「今天还剩多少」6 字 vs「记一餐」3 字），六字那枚被挤到换行。
          // 改成**按内容宽度**布局（外层 `Wrap` + 居中），文字单行不折。
          //
          // 但大字号的极端情况（320dp × 1.3×）下「今天还剩多少」单行**比
          // 半屏还宽**，`softWrap: false` 会溢出 52px（实测）。所以：
          // 内容宽度排版 + 允许在**极窄时**按比例缩小（`FittedBox.scaleDown`，
          // 与 `LfStatTile` / `MacroDotLine` 同一套大字兜底），既不折行
          // 也不溢出。
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: LfDimens.spaceTiny),
              // 【2026-10-25 用户：「今天还剩多少的按钮文字换行了」】
              // 布局仍是**等分弹**（`Expanded`）——这是经过验证不溢出的形态；
              // 溢出问题出在「按内容宽 + Wrap」那一版（320dp × 2.0× 实测
              // overflow 170px）。所以保留等分，只把**文字**改成
              // 单行 + 居中 + 放不下按比例缩小（`FittedBox.scaleDown`）。
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    softWrap: false,
                    style: LfText.captionStrong.copyWith(color: fg),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      key: const Key('chat-quick-chips'),
      padding: const EdgeInsets.fromLTRB(
        LfDimens.spaceMedium,
        10,
        LfDimens.spaceMedium,
        4,
      ),
      child: Row(
        children: [
          // `RV4-R16`（`docs/56` §8 已裁决方案 A）：
          // 原「确认应用」（R15 行级应用之后多余）与「我可以吃吗」（只往输入框
          // 塞 5 个字，用户还得自己补后半句）双双退役，换成两枚**能立刻做事** 的：
          //   · 今天还剩多少 —— 本地算，**不发模型**；
          //   · 记一餐 —— 复用 B3 的 `openMealRecordSheet`，不离开对话页。
          Expanded(
            child: chip(
              '今天还剩多少',
              Icons.pie_chart_outline,
              ChatQuickChip.remainingToday,
              bg: mint.tone(50),
              border: mint.tone(200),
              fg: c.primary,
              key: const Key('ai-chat-chip-remaining'),
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          Expanded(
            child: chip(
              '记一餐',
              Icons.restaurant_menu,
              ChatQuickChip.logMeal,
              bg: c.muted,
              fg: c.foreground,
              key: const Key('ai-chat-chip-log-meal'),
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          Expanded(
            child: chip(
              'AI 创作',
              Icons.auto_awesome_outlined,
              ChatQuickChip.aiCreate,
              bg: c.muted,
              fg: c.foreground,
              key: const Key('ai-chat-chip-ai-create'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 快捷 chip 的语义（`RV4-R16` 改版后只剩三枚）。
///
/// 退役的两个值（`applyEdits` / `canIEat`）**不保留占位**：留着就是死枚举，
/// 而且会让人以为「确认应用」还能用（行级应用已经在编辑卡每一行上）。
enum ChatQuickChip { remainingToday, logMeal, aiCreate }

/// 已选图片预览条（docs/21 §3.4 / AI 工作.html）：56×56 缩略（12 圆角 +
/// 2px mint-200 描边）+ 右上角移除圆钮（error 底）+ 文件名 + 「已添加 1 张
/// 图片」+「添加」虚线圈按钮。
///
/// **一个槽位一张图**（§5.7 的图片消息形态是单图 + 说明文字），再点「添加」
/// 是替换而不是追加，因此文案固定为 1 张。
class ImagePreviewStrip extends StatelessWidget {
  const ImagePreviewStrip({
    super.key,
    required this.fileName,
    required this.thumbnail,
    required this.onRemove,
    required this.onAdd,
  });

  final String fileName;
  final Widget thumbnail;
  final VoidCallback onRemove;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    return Padding(
      key: const Key('image-preview-bar'),
      padding: const EdgeInsets.fromLTRB(
        LfDimens.spaceMedium,
        8,
        LfDimens.spaceMedium,
        4,
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(LfDimens.radiusMd),
                  border: Border.all(color: mint.tone(200), width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(LfDimens.radiusMd - 2),
                  child: thumbnail,
                ),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: GestureDetector(
                  key: const Key('btn-remove-image'),
                  onTap: onRemove,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.error,
                      shape: BoxShape.circle,
                      boxShadow: LfShadows.removeImage,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 12,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: LfDimens.spaceSmallPlus),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: LfText.captionStrong.copyWith(color: c.foreground),
                ),
                Text(
                  '已添加 1 张图片',
                  style: LfText.micro.copyWith(color: c.mutedForeground),
                ),
              ],
            ),
          ),
          const SizedBox(width: LfDimens.spaceSmall),
          InkWell(
            key: const Key('add-image'),
            onTap: onAdd,
            borderRadius: BorderRadius.circular(LfDimens.radiusFull),
            child: CustomPaint(
              foregroundPainter: _DashedPillPainter(color: mint.tone(300)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 12, color: c.primary),
                    const SizedBox(width: 4),
                    Text(
                      '添加',
                      style: LfText.microStrong.copyWith(color: c.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 带图时的一行**发送披露**（2026-10-16，S1）：图会随这条消息真的发出去，
/// 目的地是用户自己配置的供应商——把这句话常驻在输入区，而不是等发送前弹
/// 二次确认（与拍照识别页 `scan-disclosure` 同一条产品口径）。
class ImageSendDisclosure extends StatelessWidget {
  const ImageSendDisclosure({super.key, this.count = 1});

  /// 本次会发送的图片张数（当前输入区一个槽位一张）。
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      key: const Key('image-send-disclosure'),
      padding: const EdgeInsets.fromLTRB(
        LfDimens.spaceMedium,
        0,
        LfDimens.spaceMedium,
        6,
      ),
      child: Text(
        '发送时这 $count 张图片会随这条消息一起发给你配置的 AI 服务'
        '（供应商与模型见「我的 · AI 服务」）。',
        style: LfText.micro.copyWith(color: c.mutedForeground),
      ),
    );
  }
}

/// 预览条虚线药丸（4/4，对齐 DesignCard.dashed 的虚线口径）。
class _DashedPillPainter extends CustomPainter {
  _DashedPillPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(LfDimens.radiusFull),
    );
    final path = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in path.computeMetrics()) {
      var draw = true;
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + 4).clamp(0.0, metric.length);
        if (draw) {
          dashed.addPath(metric.extractPath(distance, next), Offset.zero);
        }
        draw = !draw;
        distance = next + 4;
      }
    }
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_DashedPillPainter oldDelegate) =>
      oldDelegate.color != color;
}
