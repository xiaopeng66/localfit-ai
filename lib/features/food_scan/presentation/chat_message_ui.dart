import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';

/// 对话式识别消息气泡（docs/21 §5.4）：用户消息靠右、AI 消息靠左、
/// 系统消息居中，另有加载 / 错误两种状态。
///
/// 只用真实存在的 token：品牌交互色取语义层 `context.lf.primary`，
/// 辅助文本用 `LfText.bodySmall` + `context.lf.mutedForeground`。
class ChatMessageUI extends StatelessWidget {
  const ChatMessageUI({
    super.key,
    required this.message,
    required this.type,
    this.imageUrl,
    this.isLoading = false,
    this.errorMessage,
    this.timestamp,
    this.showAvatar = true,
    this.aiTyping = false,
  });

  /// 消息内容
  final String message;

  /// 消息类型
  final MessageType type;

  /// 图片地址（可选）
  final String? imageUrl;

  /// 是否为加载中状态
  final bool isLoading;

  /// 错误信息（可选）
  final String? errorMessage;

  /// 时间戳（可选）
  final DateTime? timestamp;

  /// 是否显示头像
  final bool showAvatar;

  /// 是否为 AI 正在输入状态
  final bool aiTyping;

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      MessageType.user => _user(context),
      MessageType.ai => _ai(context),
      MessageType.system => _system(context),
      MessageType.loading => _loading(context),
      MessageType.error => _error(context),
    };
  }

  /// 用户消息：品牌实底、`primaryForeground` 字，右下角收窄。
  ///
  /// 气泡的四个非对称圆角必须自绘（`DesignCard`/`MutedBlock` 只有统一圆角），
  /// 但**取色一律走 token**：设计稿的对话气泡是 `var(--lf-primary)` +
  /// `var(--lf-primary-foreground)`，写死 `Colors.white` 会在暗色主题下
  /// 与主题给的 `primaryForeground` 不一致。
  Widget _user(BuildContext context) {
    final c = context.lf;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.all(LfDimens.spaceMedium),
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(LfDimens.radiusMd),
            topRight: Radius.circular(LfDimens.radiusMd),
            bottomLeft: Radius.circular(LfDimens.radiusMd),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message,
              style: LfText.body.copyWith(color: c.primaryForeground),
            ),
            if (imageUrl != null) ...[
              const SizedBox(height: LfDimens.radiusSm),
              _messageImage(context, imageUrl!),
            ],
            if (timestamp != null) ...[
              const SizedBox(height: 4),
              Text(
                formatRelativeTime(timestamp!),
                style: LfText.bodySmall.copyWith(
                  color: c.primaryForeground.withValues(alpha: 0.75),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// AI 消息：浅底 + 边框，左上角收窄。
  Widget _ai(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.all(LfDimens.spaceMedium),
        decoration: BoxDecoration(
          color: context.lf.muted,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(LfDimens.radiusMd),
            bottomLeft: Radius.circular(LfDimens.radiusMd),
            bottomRight: Radius.circular(LfDimens.radiusMd),
          ),
          border: Border.all(color: context.lf.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAvatar) ...[
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: LfColors.mint(Theme.of(context).brightness)
                          .tone(100),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: LfColors.mintText(Theme.of(context).brightness),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'AI 助手',
                    style: LfText.bodySmall.copyWith(
                      color: LfColors.mintText(Theme.of(context).brightness),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Text(
              message,
              style: LfText.body.copyWith(color: context.lf.foreground),
            ),
            if (imageUrl != null) ...[
              const SizedBox(height: LfDimens.radiusSm),
              _messageImage(context, imageUrl!),
            ],
            if (aiTyping) ...[
              const SizedBox(height: 8),
              _typingIndicator(context),
            ],
            if (timestamp != null) ...[
              const SizedBox(height: 4),
              Text(
                formatRelativeTime(timestamp!),
                style: LfText.bodySmall.copyWith(
                  color: context.lf.mutedForeground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 系统消息：居中胶囊。
  Widget _system(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: context.lf.muted,
          borderRadius: BorderRadius.circular(LfDimens.radiusFull),
        ),
        child: Text(
          message,
          style: LfText.bodySmall.copyWith(color: context.lf.mutedForeground),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _loading(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.all(LfDimens.spaceMedium),
        decoration: BoxDecoration(
          color: context.lf.muted,
          borderRadius: BorderRadius.circular(LfDimens.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.lf.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              message.isEmpty ? 'AI 正在分析…' : message,
              style: LfText.bodySmall.copyWith(
                color: context.lf.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _error(BuildContext context) {
    final color = context.lf.error;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.all(LfDimens.spaceMedium),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(LfDimens.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: color, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: SheetMessage(errorMessage ?? message, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageImage(BuildContext context, String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(LfDimens.radiusMd),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => ColoredBox(
            color: context.lf.muted,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image_outlined,
                    color: context.lf.mutedForeground,
                    size: 32,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '图片加载失败',
                    style: LfText.bodySmall.copyWith(
                      color: context.lf.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _typingIndicator(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.lf.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'AI 正在输入…',
          style: LfText.bodySmall.copyWith(color: context.lf.mutedForeground),
        ),
      ],
    );
  }
}

/// 消息类型枚举。
enum MessageType { user, ai, system, loading, error }

/// 相对时间文案（「刚刚」/「N 分钟前」…）。抽成顶层函数便于单测。
String formatRelativeTime(DateTime dateTime, {DateTime? now}) {
  final difference = (now ?? DateTime.now()).difference(dateTime);
  if (difference.inMinutes < 1) return '刚刚';
  if (difference.inHours < 1) return '${difference.inMinutes} 分钟前';
  if (difference.inDays < 1) return '${difference.inHours} 小时前';
  return '${difference.inDays} 天前';
}
