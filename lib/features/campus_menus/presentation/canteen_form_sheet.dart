import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/core/validation/entity_name.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';

/// 表单字段描述（[CanteenFormSheet] 用）。
class CanteenField {
  const CanteenField({
    required this.key,
    required this.label,
    this.hint,
    this.initialValue = '',
    this.autofocus = false,
    this.numeric = false,
    this.photo = false,
    this.onPickPhoto,
  });

  final String key;
  final String label;
  final String? hint;
  final String initialValue;
  final bool autofocus;
  final bool numeric;

  /// 照片档（docs/29 §P7 需求 16）：不渲染输入框，渲染「缩略图/虚线框 +
  /// 拍照 / 从相册选 / 移除」行；字段值 = 当前照片路径（空串＝无照片）。
  /// 可选可删——没有的事不画，移除后回到虚线空态。
  final bool photo;

  /// 照片档的取图回调：source 为 true＝拍照、false＝从相册选；返回新路径
  ///（null＝用户取消或失败，失败方自行提示）。null＝不渲染取图动作。
  final Future<String?> Function(bool fromCamera)? onPickPhoto;
}

/// 通用「多字段 + 取消/保存」底部表单。
///
/// 自持 [TextEditingController]（在 State 里创建与释放）：控制器生命周期
/// 跟着弹层走，调用方拿到的只是 `key → 文本` 的只读快照，不需要管释放。
/// 取消/点遮罩返回 null，保存返回快照。
///
/// 「不改任何字段直接保存」也要能拿到初始值，所以首帧就回调一次
/// [onSubmit]，之后每次输入再刷新。
class CanteenFormSheet extends StatefulWidget {
  const CanteenFormSheet({
    super.key,
    required this.title,
    required this.fields,
    required this.onSubmit,
  });

  final String title;
  final List<CanteenField> fields;
  final void Function(Map<String, String> values) onSubmit;

  static Future<Map<String, String>?> show(
    BuildContext context, {
    required String title,
    required List<CanteenField> fields,

    /// 保存动作：**表现层校验 + 落库**都由调用方在这里做完（仓库层仍会
    /// 再校验一次）。返回 `null` = 保存成功并关窗；返回文案 = 留在弹层内
    /// 显示这条错误，**弹层不关、输入不丢**（N7）。
    Future<String?> Function(Map<String, String> values)? onSubmit,
  }) {
    // 保存按钮读的是这份快照；它由表单在首帧与每次输入后刷新，
    // 所以「不改任何字段直接保存」也能拿到初始值。
    var result = <String, String>{};
    return AppSheet.showSubmitForm<Map<String, String>>(
      context,
      title: title,
      submitKey: const Key('canteen-form-submit'),
      errorKey: const Key('canteen-form-error'),
      // 弹层行动档（§3.4/§3.8）：统一行动行由 `AppSheet.showSubmitForm`
      // 渲染（左取消 B6 / 右主行动 B2，`expand: false`）。
      // 校验或落库失败都不关窗：错误画在按钮行上方，输入内容原样保留。
      body: (_, _) => CanteenFormSheet(
        title: title,
        fields: fields,
        onSubmit: (values) => result = values,
      ),
      onSubmit: () async => onSubmit == null ? null : await onSubmit(result),
      resultBuilder: () => result,
    );
  }

  @override
  State<CanteenFormSheet> createState() => _CanteenFormSheetState();
}

class _CanteenFormSheetState extends State<CanteenFormSheet> {
  late final Map<String, TextEditingController> _controllers = {
    for (final field in widget.fields)
      if (!field.photo)
        field.key: TextEditingController(text: field.initialValue),
  };

  /// 照片档的当前值（路径；空串＝无照片）。与文本控制器分开存，
  /// 快照时合并——调用方拿到的仍是同一个 `key → 值` 只读视图。
  late final Map<String, String> _photoValues = {
    for (final field in widget.fields)
      if (field.photo) field.key: field.initialValue,
  };

  @override
  void initState() {
    super.initState();
    // 首帧就把初始值交给调用方，避免「原样保存」拿到空快照。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifySubmit();
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, field) in widget.fields.indexed) ...[
          if (index > 0) const SizedBox(height: LfDimens.spaceMedium),
          if (field.photo)
            _DishPhotoField(
              fieldKey: Key(field.key),
              label: field.label,
              initialPath: field.initialValue,
              onPickPhoto: field.onPickPhoto,
              onChanged: (value) {
                setState(() => _photoValues[field.key] = value);
                _notifySubmit();
              },
            )
          // 数值字段走统一数值输入框；文本字段走统一文本输入框
          // （标签都在框外上方，docs/21 §3.3/§3.10）：浮动 label 在密排表单里
          // 会压到上一行字段上，用户点名的「添加窗口」就是这个形态。
          else if (field.numeric)
            AppNumberField(
              fieldKey: Key(field.key),
              label: field.label,
              controller: _controllers[field.key],
              autofocus: field.autofocus,
              hintText: field.hint,
              onChanged: (_) => _notifySubmit(),
            )
          else
            LfTextField(
              fieldKey: Key(field.key),
              label: field.label,
              maxLength: field.numeric ? null : kMaxEntityNameLength,
              controller: _controllers[field.key],
              autofocus: field.autofocus,
              hintText: field.hint,
              onChanged: (_) => _notifySubmit(),
            ),
        ],
      ],
    );
  }

  void _notifySubmit() {
    widget.onSubmit({
      for (final entry in _controllers.entries) entry.key: entry.value.text,
      ..._photoValues,
    });
  }
}

/// 菜品照片字段（docs/21 §3.10 形态，docs/29 §P7 需求 16）：
/// 无图 = 72dp 虚线框 + 「添加照片」；有图 = 72dp 圆角缩略图 +
/// 「拍照 / 从相册选 / 移除照片」。选完立即换预览——不等保存
/// （保存失败整窗留驻，预览与字段值同源，不会出现「看着有图其实没存」）。
class _DishPhotoField extends StatefulWidget {
  const _DishPhotoField({
    required this.fieldKey,
    required this.label,
    required this.initialPath,
    required this.onChanged,
    required this.onPickPhoto,
  });

  final Key fieldKey;
  final String label;
  final String initialPath;
  final ValueChanged<String> onChanged;
  final Future<String?> Function(bool fromCamera)? onPickPhoto;

  @override
  State<_DishPhotoField> createState() => _DishPhotoFieldState();
}

class _DishPhotoFieldState extends State<_DishPhotoField> {
  late String _path = widget.initialPath;
  bool _busy = false;
  String? _error;

  Future<void> _pick(bool fromCamera) async {
    final pick = widget.onPickPhoto;
    if (pick == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final newPath = await pick(fromCamera);
      if (!mounted) return;
      if (newPath == null) return; // 用户取消
      widget.onChanged(newPath);
      setState(() => _path = newPath);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '照片保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _remove() {
    widget.onChanged('');
    setState(() {
      _path = '';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceXSmall),
        Row(
          key: widget.fieldKey,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _busy ? null : () => _pick(false),
              child: _path.isEmpty ? _emptyBox(context) : _preview(),
            ),
            const SizedBox(width: LfDimens.spaceMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.onPickPhoto != null) ...[
                    _action('拍照', () => _pick(true), actionKey: 'shoot'),
                    _action('从相册选', () => _pick(false), actionKey: 'gallery'),
                  ],
                  if (_path.isNotEmpty)
                    _action('移除照片', _remove, actionKey: 'remove', muted: true),
                ],
              ),
            ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: LfDimens.spaceXSmall),
            child: Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _emptyBox(BuildContext context) {
    final c = context.lf;
    return Container(
      key: const Key('canteen-dish-photo-empty'),
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Icon(Icons.photo_outlined, size: 22, color: c.mutedForeground),
    );
  }

  Widget _preview() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.file(
        File(_path),
        key: const Key('canteen-dish-photo-preview'),
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _emptyBox(context),
      ),
    );
  }

  Widget _action(
    String label,
    VoidCallback onPressed, {
    required String actionKey,
    bool muted = false,
  }) {
    final c = context.lf;
    return GestureDetector(
      key: Key('canteen-dish-photo-$actionKey'),
      onTap: _busy ? null : onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: muted
                ? c.mutedForeground
                : LfColors.mintText(Theme.of(context).brightness),
          ),
        ),
      ),
    );
  }
}
