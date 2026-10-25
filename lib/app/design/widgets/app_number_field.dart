import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';

/// 数值输入框（docs/21 §3.3）：标签固定在框**外上方**，单位并进标签，
/// 不使用 Material 的浮动 label。
///
/// 两条实测依据（探针记录见 docs/21 §3.3）：
///
/// - **不用 `labelText`**：聚焦或有值时 Material 把浮动标签升到输入框顶边
///   **之上**（实测标签顶 15.4dp < 输入框顶 20.0dp）。输入框底是无描边的
///   surfaceAlt 色块，于是标签看起来是悬在色块外的一行小字；在「上一行是
///   文字、下一行是输入框」的密排布局里还会与上一行相撞——既有代码里
///   `// 浮动 label 会浮出输入框顶部边界，预留间距避免与食物名重叠` 加
///   `SizedBox(height: 12)` 就是在给这个机制打补丁。
/// - **不用 `prefixText`**：实测它在「空且未聚焦」时 `opacity=0`，标签根本
///   不可见（它跟随浮动 label 的显隐动画），空框上只剩 hint，用户不知道
///   该填什么。
///
/// 标签经 [Semantics] 并入输入框节点，读屏仍是「克数（g），150」一个节点
/// （对照：`prefixText` 会把字段的无障碍名退化成 hint，标签降级成兄弟节点）。
class AppNumberField extends StatelessWidget {
  const AppNumberField({
    required this.fieldKey,
    required this.label,
    this.unit,
    this.optional = false,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
    this.hintText,
    this.focusNode,
    this.errorText,
    this.validator,
    this.integerOnly = false,
    this.textInputAction,
    super.key,
  });

  /// 落在**内部输入框**上的 Key。
  ///
  /// 既有测试按这些 Key 直接取 `TextFormField`（如
  /// `scan-leftover-candidate-grams-0`）或 `enterText`，所以 Key 必须留在
  /// 输入框本身而不是外层包装上。
  final Key fieldKey;

  /// 字段名（如「克数」）。
  final String label;

  /// 单位（如「g」「份」）。给了就并进标签写成「克数（g）」，不再用
  /// `suffixText` 在输入行右侧占位——输入值本身常常比单位长，两者同基线
  /// 会互相挤。
  final String? unit;

  /// 选填字段：标签里带「可选」，不靠 placeholder 暗示。
  final bool optional;

  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;
  final String? hintText;
  final FocusNode? focusNode;

  /// 校验错误文案（沿用 Material 的错误描边 + 下方错误行）。
  final String? errorText;

  /// 表单校验（沿用 `TextFormField.validator`）。
  final FormFieldValidator<String>? validator;

  /// 只接受整数（年龄等）：关掉小数点键盘。
  final bool integerOnly;

  final TextInputAction? textInputAction;

  /// 标签文本：单位与「可选」并进括号。
  String get labelText => fieldLabel(label, unit, optional: optional);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: labelText,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFieldLabel(label: label, unit: unit, optional: optional),
          const SizedBox(height: LfDimens.spaceTiny),
          TextFormField(
            key: fieldKey,
            controller: controller,
            initialValue: initialValue,
            enabled: enabled,
            autofocus: autofocus,
            focusNode: focusNode,
            textInputAction: textInputAction,
            keyboardType: TextInputType.numberWithOptions(
              decimal: !integerOnly,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              errorText: errorText,
            ),
            validator: validator,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 字段标签文本：单位与「可选」并进括号。
///
/// `('克数', 'g')` → `克数（g）`；`('默认份量', 'g', optional: true)` →
/// `默认份量（g，可选）`。
String fieldLabel(String label, String? unit, {bool optional = false}) {
  final markers = [unit, if (optional) '可选'].nonNulls;
  return markers.isEmpty ? label : '$label（${markers.join('，')}）';
}

/// 框外字段标签。带步进按钮等自定义行布局的字段用它单独摆标签，
/// 保证全 App 字段标签的字号/颜色/间距一致。
///
/// **它不进语义树**：字段的可访问名由相邻输入框自己承载（`AppNumberField`
/// 内部的 `Semantics`，或手工 `Semantics(label:)` 包裹的输入框）。不排除的
/// 话读屏会把标签播报两遍（实测：`"克数（g）\n克数（g）"`）。所以用
/// [AppFieldLabel] 时，相邻输入框**必须**带同样的语义标签。
class AppFieldLabel extends StatelessWidget {
  const AppFieldLabel({
    required this.label,
    this.unit,
    this.optional = false,
    this.color,
    super.key,
  });

  final String label;
  final String? unit;
  final bool optional;

  /// 覆盖标签色（缺省 `mutedForeground`）。
  ///
  /// 2026-10-12（docs/32 T4）：`LfSelectField` 的校验错误态要把标签也转成
  /// 错误色——与 `LfTextField` 里 `errorText` 变红是同一套反馈。其余调用点
  /// 不传，行为不变。
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Text(
      fieldLabel(label, unit, optional: optional),
      style: LfText.bodySmall.copyWith(
        color: color ?? context.lf.mutedForeground,
      ),
    ),
  );
}
