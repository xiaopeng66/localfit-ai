import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 主题内搜索输入框（docs/21 §3.3 输入框）。
///
/// **不用 Material 3 的 `SearchBar`**：本 App 的 `ThemeData` 没有
/// `searchBarTheme`（见 `app_theme.dart`），于是 `SearchBar` 会落地成 M3
/// 默认外观——`surfaceContainerHigh` 底 + 海拔 1 的阴影 + 28dp 圆角，与本
/// 设计稿的「muted 底 + 无描边 + 16 圆角」是两套语言；它出现在食物库与
/// 「记录一餐」弹层里时是两张页面里最突兀的元素（用户 2026-10-03 走查
/// 「弹窗卡片太丑」的一部分）。这里改用普通 [TextField]——主题的
/// `inputDecorationTheme` 已经把 fill/圆角/描边定好，只需补图标与紧凑内距。
class LfSearchField extends StatelessWidget {
  const LfSearchField({
    super.key,
    required this.fieldKey,
    required this.hintText,
    this.controller,
    this.onChanged,
    this.autofocus = false,
  });

  /// 落在输入框本身的 Key（测试按它输入与定位）。
  final Key fieldKey;
  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return TextField(
      key: fieldKey,
      controller: controller,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        fillColor: c.card,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LfDimens.inputRadius),
          borderSide: BorderSide(color: c.border),
        ),
        isDense: true,
        prefixIcon: Icon(
          Icons.search,
          size: LfDimens.iconMd,
          color: c.mutedForeground,
        ),
        // 主题给的 contentPadding 是 h16/v12；带 prefixIcon 时左侧内距由图标
        // 盒承担，这里把右侧与上下收一档，整行高度落在 44dp 触达线上。
        contentPadding: const EdgeInsets.symmetric(
          horizontal: LfDimens.spaceLarge,
          vertical: LfDimens.spaceMediumPlus,
        ),
      ),
    );
  }
}
