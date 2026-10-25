import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// AI 回复的最小 Markdown 渲染器（`RV4-P2-02` / `docs/56` R13）。
///
/// **不新增第三方依赖**：这是自写的最小实现，只覆盖模型实际会用的语法。
/// 支持：`#`/`##` 标题、无序列表（`- `/`* `）、有序列表（`1. `）、行内
/// `**粗**`/`*斜*`/`` `代码` ``、块引用 `> `、``` 围栏（等宽 + 横向滚动）、
/// 分隔线 `---`。
///
/// **不支持**（按设计）：表格、图片、外链跳转。链接降级为文字 + 下划线，
/// **不打开外部浏览器**（隐私口径：AI 回复里的链接不主动出站）。
///
/// **容错**：任何畸形输入（未闭合 `**`、未闭合围栏、超长行、空串）都降级为
/// 纯文本显示，**不抛异常**。单条消息最多渲染 [maxLines] 行，超出折叠。
class LfMarkdown extends StatefulWidget {
  const LfMarkdown({
    super.key,
    required this.text,
    this.maxLines = 200,
    this.baseStyle,
  });

  final String text;

  /// 最多渲染多少行（超出折叠「展开全部」）。
  final int maxLines;

  /// 正文样式（缺省 `LfText.body`；编辑卡的 reply 气泡可传自己的）。
  final TextStyle? baseStyle;

  @override
  State<LfMarkdown> createState() => _LfMarkdownState();
}

class _LfMarkdownState extends State<LfMarkdown> {
  bool _expanded = false;

  @override
  void didUpdateWidget(LfMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 文本换了（例如重新生成）就回到折叠态，避免长文本把页面撑爆。
    if (oldWidget.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final base =
        widget.baseStyle ?? LfText.body.copyWith(color: c.cardForeground);
    final blocks = _parseBlocks(widget.text);
    final limited = _expanded ? blocks : blocks.take(widget.maxLines).toList();
    final truncated = blocks.length > limited.length;

    return Column(
      key: const Key('lf-markdown'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final block in limited) _block(context, block, base, c),
        if (truncated)
          TextButton(
            key: const Key('lf-markdown-expand'),
            onPressed: () => setState(() => _expanded = true),
            child: const Text('展开全部'),
          ),
      ],
    );
  }

  Widget _block(
    BuildContext context,
    _Block block,
    TextStyle base,
    LfSemanticColors c,
  ) {
    switch (block.kind) {
      case _BlockKind.heading1:
        return Padding(
          padding: const EdgeInsets.only(bottom: LfDimens.spaceXSmall),
          child: Text(
            block.text,
            style: LfText.title.copyWith(color: c.cardForeground),
          ),
        );
      case _BlockKind.heading2:
        return Padding(
          padding: const EdgeInsets.only(bottom: LfDimens.spaceXSmall),
          child: Text(
            block.text,
            style: LfText.bodyStrong.copyWith(color: c.cardForeground),
          ),
        );
      case _BlockKind.bullet:
        return _line(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: base),
              Expanded(child: _inline(block.text, base)),
            ],
          ),
        );
      case _BlockKind.ordered:
        return _line(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${block.order}.  ', style: base),
              Expanded(child: _inline(block.text, base)),
            ],
          ),
        );
      case _BlockKind.quote:
        return Padding(
          padding: const EdgeInsets.only(bottom: LfDimens.spaceXSmall),
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: c.border, width: 3)),
            ),
            padding: const EdgeInsets.only(left: LfDimens.spaceSmall),
            child: _inline(block.text, base.copyWith(color: c.mutedForeground)),
          ),
        );
      case _BlockKind.code:
        return Padding(
          padding: const EdgeInsets.only(bottom: LfDimens.spaceXSmall),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: c.muted,
              borderRadius: BorderRadius.circular(LfDimens.radiusSm),
            ),
            padding: const EdgeInsets.all(LfDimens.spaceSmall),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                block.text,
                style: base.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ),
        );
      case _BlockKind.divider:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: LfDimens.spaceXSmall),
          child: Divider(height: 1, thickness: 1),
        );
      case _BlockKind.paragraph:
        return _line(_inline(block.text, base));
    }
  }

  Widget _line(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: LfDimens.spaceXSmall),
    child: child,
  );

  /// 行内解析：`**粗**` / `*斜*` / `` `代码` `` / `[文字](url)`（降级为下划线文字）。
  ///
  /// 全部容错：未闭合的标记原样当文字（星号会留在屏上——但那是**未闭合**的
  /// 畸形输入，显示原文比吞掉更诚实）。
  Widget _inline(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'\*\*([^*]+)\*\*' // **粗**
      r'|\*([^*]+)\*' // *斜*
      r'|`([^`]+)`' // `代码`
      r'|\[([^\]]*)\]\(([^)]*)\)', // [文字](url)
    );
    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      if (match.group(1) != null) {
        spans.add(
          TextSpan(
            text: match.group(1),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (match.group(2) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else if (match.group(3) != null) {
        spans.add(
          TextSpan(
            text: match.group(3),
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        );
      } else {
        // 链接降级：只留文字 + 下划线，**不出站**。
        spans.add(
          TextSpan(
            text: match.group(4),
            style: const TextStyle(decoration: TextDecoration.underline),
          ),
        );
      }
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }
}

enum _BlockKind {
  heading1,
  heading2,
  paragraph,
  bullet,
  ordered,
  quote,
  code,
  divider,
}

class _Block {
  const _Block(this.kind, this.text, {this.order = 1});

  final _BlockKind kind;
  final String text;
  final int order;
}

/// 把原文切成块。**全容错**：不认识的形态一律当段落。
List<_Block> _parseBlocks(String text) {
  final normalized = text.replaceAll('\r\n', '\n');
  if (normalized.trim().isEmpty) return const [];
  final lines = normalized.split('\n');
  final blocks = <_Block>[];
  var inFence = false;
  final code = StringBuffer();

  for (final line in lines) {
    final trimmed = line.trimRight();
    if (trimmed.trimLeft().startsWith('```')) {
      if (inFence) {
        blocks.add(_Block(_BlockKind.code, code.toString().trimRight()));
        code.clear();
        inFence = false;
      } else {
        inFence = true;
      }
      continue;
    }
    if (inFence) {
      code.writeln(line);
      continue;
    }
    final t = trimmed.trim();
    if (t.isEmpty) continue;
    if (RegExp(r'^-{3,}$').hasMatch(t) || RegExp(r'^_{3,}$').hasMatch(t)) {
      blocks.add(const _Block(_BlockKind.divider, ''));
      continue;
    }
    if (t.startsWith('## ')) {
      blocks.add(_Block(_BlockKind.heading2, t.substring(3).trim()));
      continue;
    }
    if (t.startsWith('# ')) {
      blocks.add(_Block(_BlockKind.heading1, t.substring(2).trim()));
      continue;
    }
    if (t.startsWith('> ')) {
      blocks.add(_Block(_BlockKind.quote, t.substring(2).trim()));
      continue;
    }
    final bullet = RegExp(r'^[-*]\s+(.*)$').firstMatch(t);
    if (bullet != null) {
      blocks.add(_Block(_BlockKind.bullet, bullet.group(1)!));
      continue;
    }
    final ordered = RegExp(r'^(\d{1,3})[.)]\s+(.*)$').firstMatch(t);
    if (ordered != null) {
      blocks.add(
        _Block(
          _BlockKind.ordered,
          ordered.group(2)!,
          order: int.tryParse(ordered.group(1)!) ?? 1,
        ),
      );
      continue;
    }
    // 未闭合围栏里的残余文本：当代码块收尾（降级，不丢内容）。
    blocks.add(_Block(_BlockKind.paragraph, t));
  }
  if (inFence && code.isNotEmpty) {
    blocks.add(_Block(_BlockKind.code, code.toString().trimRight()));
  }
  return blocks;
}
