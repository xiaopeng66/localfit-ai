import 'package:flutter/material.dart';

import 'package:localfit_ai/features/ai_conversation/domain/chat_image.dart';

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
    this.canSend = true,
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

  /// 发送键是否可用（2026-11-07 用户：图片副本还没就绪时**置灰**，
  /// 就绪后才能点——避免把系统缓存路径写进聊天记录）。
  ///
  /// false 时按钮变中性灰、不可点；输入框仍可继续打字。
  final bool canSend;

  /// 输入框占位（`RV4-P2-05`：会话结束后变「开始新对话…」）。null = 默认文案。
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
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
              background: LfColors.brandStrong(brightness),
              iconColor: LfColors.onBrandStrong(brightness),
              onPressed: onStop,
            )
          else
            LfCircleIconButton(
              key: const Key('btn-send'),
              icon: Icons.send_rounded,
              iconSize: LfDimens.iconSm,
              tooltip: canSend ? '发送' : '图片还在处理，马上就好',
              // 副本未就绪：中性灰 + 不可点（用户明确要求「变灰」）。
              background: canSend ? LfColors.brandStrong(brightness) : c.muted,
              iconColor: canSend
                  ? LfColors.onBrandStrong(brightness)
                  : c.mutedForeground,
              onPressed: canSend ? () => onSendText(controller.text) : null,
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
/// 与编辑卡上的「应用」是同一个动作、同一个执行器。
///
/// 【2026-10-25 用户（8c）：按文字长度调整大小】三枚文案长度差一倍
/// （「今天还剩多少」6 字 vs「记一餐」3 字），等分时长的被挤到换行。
///
/// 两版之间的取舍（**都实测过**，别再走一遍）：
/// * 「按内容宽 + 外层 `Wrap`」→ 320dp × 2.0× 下溢出 170px（`Wrap` 不收缩子项）；
/// * 「纯等分 + `FittedBox`」→ 不溢出，但宽度与文字长度无关（用户要的正是这个）。
///
/// 现在是**两条路的合取**：`LayoutBuilder` 先量可用宽，再看「三枚按内容宽的
/// 自然总宽 + 间距」放不放得下——
/// * 放得下（390dp 常见档）⇒ `MainAxisSize.min` + `MainAxisAlignment.center`
///   按内容宽居中排；某枚仍可能被大字号撑宽到超出，所以每枚内容里保留
///   `Flexible + FittedBox.scaleDown` 兜底；
/// * 放不下（320dp × 2.0×）⇒ 回落等分（`Expanded`），与前一版逐字一致。
class ChatQuickChips extends StatelessWidget {
  const ChatQuickChips({super.key, required this.onChipTap});

  /// 整行容器 key（输入区顺序断言用）。
  static const Key rowKey = Key('ai-chat-quick-chips');

  /// chip key → 文案已固定（applyEdits / can-i-eat / ai-create）。
  final ValueChanged<ChatQuickChip> onChipTap;

  /// 三枚 chip 的（key, 文案, 图标, 底色档, 描边档, 字色档）。
  ///
  /// 抽成静态表是**为了能先量自然宽**：`LayoutBuilder` 那一版需要「同一份文案」
  /// 既参与测量又参与渲染，两处各写一遍必然漂。
  static const List<({String key, String label, ChatQuickChip chip})> _chips = [
    (
      key: 'ai-chat-chip-remaining',
      label: '今天还剩多少',
      chip: ChatQuickChip.remainingToday,
    ),
    (key: 'ai-chat-chip-log-meal', label: '记一餐', chip: ChatQuickChip.logMeal),
    (
      key: 'ai-chat-chip-ai-create',
      label: 'AI 创作',
      chip: ChatQuickChip.aiCreate,
    ),
  ];

  static const Map<String, IconData> _icons = {
    'ai-chat-chip-remaining': Icons.pie_chart_outline,
    'ai-chat-chip-log-meal': Icons.restaurant_menu,
    'ai-chat-chip-ai-create': Icons.auto_awesome_outlined,
  };

  /// chip 的水平内边距（与渲染处**同源**：测量与绘制必须用同一个值）。
  static const EdgeInsets _chipPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 8,
  );

  /// 图标 + 图标与文字间距（同上，测量与渲染共用）。
  static const double _chipIconSize = 14;
  static const double _chipGap = LfDimens.spaceTiny;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final mint = LfColors.mint(Theme.of(context).brightness);
    final textStyle = LfText.captionStrong;

    /// 这一枚 chip 的「自然宽」：内边距 + 图标 + 间距 + 文字宽。
    ///
    /// 用 `TextPainter` 在**当前 `textScaler`** 下量——`Text` 的宽度就是它，
    /// 不依赖布局是否已经跑过一轮（`LayoutBuilder` 里还没有子项尺寸可读）。
    double naturalWidth(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final width =
          _chipPadding.horizontal +
          _chipIconSize +
          _chipGap +
          painter.size.width;
      painter.dispose();
      return width;
    }

    Widget chip(
      String label,
      String chipKey,
      ChatQuickChip chipValue, {
      required Color bg,
      Color? border,
      required Color fg,
    }) {
      return InkWell(
        key: Key(chipKey),
        onTap: () => onChipTap(chipValue),
        borderRadius: BorderRadius.circular(LfDimens.radiusFull),
        child: Container(
          padding: _chipPadding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(LfDimens.radiusFull),
            border: Border.all(color: border ?? c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icons[chipKey], size: _chipIconSize, color: fg),
              const SizedBox(width: _chipGap),
              // 【2026-10-25 用户：「今天还剩多少的按钮文字换行了」】
              // 单行 + 居中 + 放不下按比例缩小（`FittedBox.scaleDown`，
              // 与 `LfStatTile` / `MacroDotLine` 同一套大字兜底）。
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    softWrap: false,
                    style: textStyle.copyWith(color: fg),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    /// 配色：第一枚是品牌色（「能立刻做事」），后两枚 muted（次级）。
    ///
    /// 【2026-11-09 审查修复】第一枚原来用 `c.primary` 当文字：压 mint-50
    /// 只有 2.22:1（浅色主题 12px 文字 + 14dp 图标都不达标）。改用文字档
    /// `mintText`（5.24:1）；描边仍用 mint-200 保留「品牌感」。
    (Color bg, Color? border, Color fg) tonesOf(ChatQuickChip value) =>
        value == ChatQuickChip.remainingToday
        ? (
            mint.tone(50),
            mint.tone(200),
            LfColors.mintText(Theme.of(context).brightness),
          )
        : (c.muted, null, c.foreground);

    Widget buildChipAt(int index) {
      final spec = _chips[index];
      final (bg, border, fg) = tonesOf(spec.chip);
      return chip(
        spec.label,
        spec.key,
        spec.chip,
        bg: bg,
        border: border,
        fg: fg,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final naturalTotal =
              [for (final spec in _chips) naturalWidth(spec.label)]
                  .reduce((a, b) => a + b) +
              LfDimens.spaceSmall * (_chips.length - 1);
          // 放得下 ⇒ 按内容宽居中排（用户要的「按文字长度调整」）。
          if (naturalTotal <= constraints.maxWidth) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: LfDimens.spaceSmall),
                  buildChipAt(i),
                ],
              ],
            );
          }
          // 放不下 ⇒ 回落等分（经过验证不溢出的形态；320dp × 2.0× 走这里）。
          return Row(
            children: [
              for (var i = 0; i < _chips.length; i++) ...[
                if (i > 0) const SizedBox(width: LfDimens.spaceSmall),
                Expanded(child: buildChipAt(i)),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 快捷 chip 的语义（`RV4-R16` 改版后只剩三枚）。
///
/// 退役的两个值（`applyEdits` / `canIEat`）**不保留占位**：留着就是死枚举，
/// 而且会让人以为「确认应用」还能用（行级应用已经在编辑卡每一行上）。
enum ChatQuickChip { remainingToday, logMeal, aiCreate }

/// 已选图片预览条（2026-10-29 R-10 重做）。
///
/// 用户原话：「图片添加后，我希望就显示一个很好看的图片缩略图，像我的图片
/// 里的那样，而不是显示很详细的图片信息，另外，图片右边不要出现添加按钮，
/// 功能重复了，而且，我希望能多加图片，而不是只能加一张，然后新加入的会
/// 替换上一个」。
///
/// 形态（2026-10-31 用户二轮）：**悬浮卡**——卡片底色 + 16 圆角 + 阴影，
/// 浮在输入栏上方独立呈现；一排 56×56 缩略图，**点缩略图全屏放大**；右上角
/// 移除圆钮不变；**文字说明整行退役**（「一条消息发 1 张…」随多图一次发送
/// 的批量通道一并作废，不静默丢弃任何一张）。
class ImagePreviewStrip extends StatelessWidget {
  const ImagePreviewStrip({
    super.key,
    required this.images,
    required this.onRemove,
    this.onInspect,
    this.thumbnailBuilder,
  });

  final List<ChatImage> images;

  /// 按下标移除（第 0 张起）。
  final ValueChanged<int> onRemove;

  /// 点缩略图全屏放大（null = 不可点）。
  final ValueChanged<ChatImage>? onInspect;

  /// 缩略图构建（默认按 `ChatImage.path` 渲染文件图）。
  final Widget Function(ChatImage image, int index)? thumbnailBuilder;

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
      child: Container(
        padding: const EdgeInsets.all(LfDimens.spaceSmall),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(LfDimens.radiusLg),
          // 浮层阴影走设计稿公式（docs/21 §2.4 `--lf-shadow-float`），
          // 不在业务件里自造 Color 字面量（ui_literal_budget 门禁）。
          boxShadow: LfShadows.float(
            Theme.of(context).brightness == Brightness.light,
          ),
        ),
        // 【2026-11-07 多选 9 张】`Wrap` 会折成三行把输入区顶高；改横向滚动
        // ——预览条固定一行高度，左右滑看全部（预览是辅助，不该占主输入区）。
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: LfDimens.spaceSmall,
            children: [
              for (var i = 0; i < images.length; i++)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      key: Key('image-preview-thumb-$i'),
                      onTap: onInspect == null
                          ? null
                          : () => onInspect!(images[i]),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            LfDimens.radiusMd,
                          ),
                          border: Border.all(color: mint.tone(200), width: 2),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            LfDimens.radiusMd - 2,
                          ),
                          child: thumbnailBuilder?.call(images[i], i),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      // 【2026-11-09 审查修复】视觉圆仍是 20dp（不挤压缩略图），
                      // 但命中盒扩到 40dp 并居中覆盖：原来 20dp 的
                      // GestureDetector 还被 Positioned 裁掉溢出部分，
                      // 有效热区约 14dp，小屏/大字下很难点中。
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(
                          child: Semantics(
                            button: true,
                            label: '移除第 ${i + 1} 张图片',
                            child: GestureDetector(
                              key: i == 0
                                  ? const Key('btn-remove-image')
                                  : Key('btn-remove-image-$i'),
                              behavior: HitTestBehavior.opaque,
                              onTap: () => onRemove(i),
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
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
