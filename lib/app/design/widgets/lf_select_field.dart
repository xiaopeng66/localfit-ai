import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';

/// 统一下拉选择器（docs/32 §3 D7 / 需求 66）。
///
/// **外观**＝输入框形：框外标签（与 `LfTextField`/`AppNumberField` 同源的
/// [AppFieldLabel]）+ 当前值 + chevron；**点开**＝[AppSheet] 单选列表
/// （行高 44、选中项主色 + ✓、超长列表可滚并自动滚到选中项）。
///
/// 【为什么不用 `DropdownButtonFormField`】M3 的锚定菜单在长列表下观感差、
/// 无法统一主题（字号/行高/配色都不可控），且 12 处调用里只有 3 处做过精修
/// ⇒ 9 处风格不一致。用户原话「优化软件内所有下拉选项弹窗的流畅性和显示风格
/// 和大小」。自绘弹层在本仓已有两个先例（餐次胶囊、选日期）。
///
/// 【返回值语义】弹层只在**确定选中**时回写：`onChanged` 永不收到 null。
/// 旧调用点里 `onChanged(null)` 被忽略的写法（`value ?? 旧值`）因此等价——
/// 这正是迁移时「返回值与旧下拉一致」的判据。
///
/// 【禁用】`enabled: false` ⇒ 不可点开、muted 底、字与箭头降级
/// （识别候选页保存中必须保持不可点）。
class LfSelectField<T> extends StatelessWidget {
  const LfSelectField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabel,
    required this.onChanged,
    this.optional = false,
    this.enabled = true,
    this.errorText,
    this.semanticLabel,
  });

  /// 落在**关闭态那枚可点控件**上的 Key（与旧 `DropdownButtonFormField` 的
  /// Key 约定一致：11 个站点的既有断言直接沿用）。
  final Key fieldKey;

  final String label;

  /// 当前值。为 null 时显示占位文案（灰色）。
  final T? value;

  /// 候选值（按显示顺序）。长列表按需滚动。
  final List<T> options;

  final String Function(T option) optionLabel;

  /// 只在确定选中时回调；**不会**传 null。
  final ValueChanged<T> onChanged;

  /// 框外标签追加「（可选）」。
  final bool optional;

  /// false = 不可点开（禁用态）。
  final bool enabled;

  /// 校验错误文案：非空时框描边转错误色、标签也转错误色（与 `LfTextField` 同法）。
  final String? errorText;

  /// 关态控件的读屏标签；缺省用「标签 当前值」。
  final String? semanticLabel;

  /// 关态框高（与 `LfTextField` 的 44 对齐）。
  static const double fieldHeight = 44;

  /// 弹层选项行高。
  static const double optionHeight = 44;

  Future<void> _open(BuildContext context) async {
    final selected = await AppSheet.showCustom<T>(
      context,
      builder: (sheetContext) => _SelectOptionsSheet<T>(
        title: label,
        options: options,
        selected: value,
        optionLabel: optionLabel,
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final hasError = errorText != null && errorText!.isNotEmpty;
    final current = value;
    final display = current == null ? '请选择' : optionLabel(current);
    final isPlaceholder = current == null;

    return Semantics(
      label: semanticLabel ?? '$label $display',
      button: true,
      enabled: enabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFieldLabel(
            label: label,
            optional: optional,
            // 错误态标签同色（与 LfTextField 的 errorText 行为一致）。
            color: hasError ? c.error : null,
          ),
          const SizedBox(height: LfDimens.spaceTiny),
          GestureDetector(
            key: fieldKey,
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => _open(context) : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: fieldHeight),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: enabled ? c.card : c.muted,
                border: Border.all(
                  color: hasError ? c.error : (enabled ? c.border : c.border),
                ),
                borderRadius: BorderRadius.circular(LfDimens.radiusMd),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      display,
                      softWrap: true,
                      style: LfText.body.copyWith(
                        color: isPlaceholder || !enabled
                            ? c.mutedForeground
                            : c.foreground,
                      ),
                    ),
                  ),
                  const SizedBox(width: LfDimens.spaceSmall),
                  ExcludeSemantics(
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: LfDimens.iconSm,
                      color: enabled ? c.mutedForeground : c.border,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 弹层里的单选列表：标题 = 字段名，行高 44，选中项主色 + ✓。
///
/// 打开时自动滚到选中项（长列表里「当前是哪一项」必须一眼可见）。
class _SelectOptionsSheet<T> extends StatefulWidget {
  const _SelectOptionsSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.optionLabel,
  });

  final String title;
  final List<T> options;
  final T? selected;
  final String Function(T option) optionLabel;

  @override
  State<_SelectOptionsSheet<T>> createState() => _SelectOptionsSheetState<T>();
}

class _SelectOptionsSheetState<T> extends State<_SelectOptionsSheet<T>> {
  static const double _maxListHeight = 320;

  final _scrollController = ScrollController();
  bool _positioned = false;

  void _revealSelection(List<double> heights) {
    if (_positioned) return;
    _positioned = true;
    final selected = widget.selected;
    final index = selected == null ? -1 : widget.options.indexOf(selected);
    if (index <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      final preceding = heights
          .take(index)
          .fold(0.0, (sum, height) => sum + height);
      final target =
          preceding - (position.viewportDimension - heights[index]) / 2;
      _scrollController.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    });
  }

  TextStyle _optionStyle(BuildContext context, bool selected) =>
      DefaultTextStyle.of(context).style.merge(
        LfText.body.copyWith(
          color: selected
              ? LfColors.mintText(Theme.of(context).brightness)
              : context.lf.foreground,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxListHeight + 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: LfDimens.spaceSmall),
            child: Text(
              widget.title,
              key: const Key('lf-select-sheet-title'),
              style: LfText.title.copyWith(color: c.cardForeground),
            ),
          ),
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final heights = <double>[];
                for (final option in widget.options) {
                  final selected = option == widget.selected;
                  final painter =
                      TextPainter(
                        text: TextSpan(
                          text: widget.optionLabel(option),
                          style: _optionStyle(context, selected),
                        ),
                        textDirection: Directionality.of(context),
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout(
                        maxWidth:
                            constraints.maxWidth -
                            2 * LfDimens.spaceSmall -
                            (selected ? LfDimens.iconSm : 0),
                      );
                  heights.add(
                    (painter.height.ceilToDouble() + 21).clamp(
                      LfSelectField.optionHeight,
                      double.infinity,
                    ),
                  );
                  painter.dispose();
                }
                _revealSelection(heights);
                return ListView.builder(
                  key: const Key('lf-select-options'),
                  controller: _scrollController,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: widget.options.length,
                  itemExtentBuilder: (index, _) => heights[index],
                  itemBuilder: (context, index) {
                    final option = widget.options[index];
                    final on = option == widget.selected;
                    return InkWell(
                      key: Key('lf-select-option-$index'),
                      onTap: () => Navigator.pop(context, option),
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: LfSelectField.optionHeight,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: LfDimens.spaceSmall,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: index == 0
                              ? null
                              : Border(
                                  top: BorderSide(
                                    color: c.border.withValues(alpha: 0.6),
                                  ),
                                ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.optionLabel(option),
                                softWrap: true,
                                style: _optionStyle(context, on),
                              ),
                            ),
                            if (on)
                              Icon(
                                Icons.check,
                                size: LfDimens.iconSm,
                                color: LfColors.mintText(brightness),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
