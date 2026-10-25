import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart'
    show AppFieldLabel, fieldLabel;

/// 文本输入框（docs/21 §3.10 输入框类）。
///
/// 与 [AppNumberField] 同一套形态语言：标签固定在框**外上方**，不使用
/// Material 的浮动 label。浮动 label 的问题是它在聚焦/有值时被抬到输入框
/// 顶边之上，正好压在 `enabledBorder` 上——用户 2026-10-03 点名的「添加窗口」
/// 弹窗就是这个形态（标签骑在框上、框内还留着独立的 hint）。
///
/// 底色/圆角/描边走主题（`app_theme.dart` 的 `inputDecorationTheme`：
/// `--lf-muted` 底、16 圆角、常态无描边、聚焦 2px `--lf-ring`、错误 1px
/// `--lf-error`）；本件只把「标签在外 + 框外错误行保持可编辑」这两件事
/// 固化下来。
///
/// Key 落在**内部输入框**上（沿用 [AppNumberField] 约定），既有测试的
/// `enterText` / `tester.widget<TextFormField>()` 才不会失配。
class LfTextField extends StatelessWidget {
  const LfTextField({
    required this.fieldKey,
    required this.label,
    this.unit,
    this.optional = false,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.onFieldSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.hintText,
    this.focusNode,
    this.errorText,
    this.helperText,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.prefixIcon,
    this.suffixIcon,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = true,
    this.enableSuggestions = true,
    super.key,
  });

  /// 落在**内部输入框**上的 Key（见类文档）。
  final Key fieldKey;

  /// 字段名（如「食物名称」）。
  final String label;

  /// 单位（如「g」）。给了就并进标签，不在输入行右侧占位。
  final String? unit;

  /// 选填字段：标签里带「可选」，不靠 placeholder 暗示。
  final bool optional;

  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;
  final bool autofocus;
  final String? hintText;
  final FocusNode? focusNode;

  /// 校验错误文案：框下 `bodySmall` + error 色（主题的 1px `--lf-error` 描边），
  /// **框内保持可编辑**（用户 N7 的诉求）。
  final String? errorText;

  /// 框下辅助说明（如「AI 原名：…」）。与 `errorText` 同位置，二选一时
  /// 由 Material 自己处理（错误优先）。
  final String? helperText;

  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int maxLines;
  final int? minLines;
  final int? maxLength;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool autocorrect;

  /// 键盘联想（口令等敏感字段关掉）。
  final bool enableSuggestions;

  /// 标签文本：单位与「可选」并进括号（与 [AppNumberField] 同源）。
  String get labelText => fieldLabel(label, unit, optional: optional);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: labelText,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标签经 ExcludeSemantics 排除，可访问名由下面的 Semantics 承载
          // （与 AppNumberField 同法，读屏只播报一次）。
          AppFieldLabel(label: label, unit: unit, optional: optional),
          const SizedBox(height: LfDimens.spaceTiny),
          TextFormField(
            key: fieldKey,
            controller: controller,
            initialValue: initialValue,
            enabled: enabled,
            autofocus: autofocus,
            focusNode: focusNode,
            obscureText: obscureText,
            keyboardType: keyboardType,
            maxLines: maxLines,
            minLines: minLines,
            maxLength: maxLength,
            textInputAction: textInputAction,
            textCapitalization: textCapitalization,
            autocorrect: autocorrect,
            enableSuggestions: enableSuggestions,
            decoration: InputDecoration(
              hintText: hintText,
              errorText: errorText,
              helperText: helperText,
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              // 整行高 44（`px-3.5 py-2.5` + 14px 文字）。
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            validator: validator,
            onChanged: onChanged,
            onFieldSubmitted: onFieldSubmitted,
          ),
        ],
      ),
    );
  }
}

/// 输入框错误行（框外错误文案的统一形态）。当调用方需要把错误画在
/// [LfTextField] 之外的固定位置（如弹层底部行动行上方）时用它，保证
/// 字号/颜色与框内错误一致。
class LfFieldError extends StatelessWidget {
  const LfFieldError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) =>
      Text(message, style: LfText.bodySmall.copyWith(color: context.lf.error));
}
