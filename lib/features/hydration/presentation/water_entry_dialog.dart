import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/features/hydration/domain/water_intake.dart';

/// 加水弹层（docs/21 §5.1 饮水卡：+250ml 等快捷值）。
///
/// 默认返回要加的量（ml），用户关闭则不返回任何值（调用方不写库）。
/// 给了 [onSubmit] 则改由弹层提交：返回文案 = **留在弹层内显示、不关窗**
/// （N7；快捷值与手填毫升数走同一条提交路径）。
class WaterEntryDialog extends StatefulWidget {
  const WaterEntryDialog({super.key, this.todayConsumedMl = 0, this.onSubmit});

  final double todayConsumedMl;

  /// 落库动作（由调用方给）。返回 `null` = 成功并关窗；返回文案 = 弹层内联
  /// 显示这条错误、不关窗，用户输入不丢。
  final Future<String?> Function(double amountMl)? onSubmit;

  @override
  State<WaterEntryDialog> createState() => _WaterEntryDialogState();
}

class _WaterEntryDialogState extends State<WaterEntryDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 快捷值与手填走同一条提交路径。
  Future<void> _submitAmount(double amount) async {
    final onSubmit = widget.onSubmit;
    if (onSubmit == null) {
      Navigator.of(context).pop(amount);
      return;
    }
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? failure;
    try {
      failure = await onSubmit(amount);
    } catch (_) {
      failure = '饮水记录失败，请重试。';
    }
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(amount);
      return;
    }
    setState(() {
      _saving = false;
      _error = failure;
    });
  }

  void _submitManual() {
    if (_saving) return;
    final raw = _controller.text.trim();
    final parsed = double.tryParse(raw);
    if (parsed == null) {
      setState(() => _error = '请输入数字（毫升）。');
      return;
    }
    try {
      _submitAmount(validateWaterAmountMl(parsed));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    return Padding(
      // 键盘内边距由弹层壳（`AppSheet.showCustom`）统一给，这里不再自己加一遍
      // ——两层叠加会把可用高度吃掉整整一个键盘高，2.0× 下直接把内容挤溢出。
      padding: const EdgeInsets.only(
        left: LfDimens.spaceLargePlus,
        right: LfDimens.spaceLargePlus,
        top: LfDimens.spaceLargePlus,
        bottom: LfDimens.spaceLargePlus,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('记录饮水', style: LfText.headline.copyWith(color: c.foreground)),
          const SizedBox(height: LfDimens.spaceMicro),
          Text(
            '今天已记录 ${widget.todayConsumedMl.round()} ml',
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
          const SizedBox(height: LfDimens.spaceLarge),
          // 超高内容自己滚（弹层壳契约）：2.0× + 键盘下「快捷值 + 输入框」的
          // 自然高度会超过可用高度——溢出会把行动行画到弹层框之外（点不到）。
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 快捷值**等宽满行**（docs/27 §R7）：Wrap 换行时最后一块孤行
                  // （用户实测「500ml 独挂在 200ml 下边、右边一大片空」）——
                  // Expanded 等分列在任何宽度下都填满整行，没有孤块。
                  Row(
                    children: [
                      for (var i = 0; i < waterQuickAmountsMl.length; i++) ...[
                        if (i > 0) const SizedBox(width: LfDimens.spaceSmall),
                        Expanded(
                          // 快捷值 = B3 胶囊 `soft` 档（§3.8）。
                          child: LfPillButton(
                            key: Key(
                              'water-quick-${waterQuickAmountsMl[i].round()}',
                            ),
                            label: '+${waterQuickAmountsMl[i].round()} ml',
                            tone: LfPillTone.soft,
                            onPressed: _saving
                                ? null
                                : () => _submitAmount(waterQuickAmountsMl[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: LfDimens.spaceLarge),
                  LfTextField(
                    fieldKey: const Key('water-amount-input'),
                    label: '自定义毫升数',
                    controller: _controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    errorText: _error,
                    onFieldSubmitted: (_) => _submitManual(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: LfDimens.spaceLarge),
          Row(
            children: [
              Expanded(
                child: LfTextButton(
                  label: '取消',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: LfDimens.spaceMedium),
              Expanded(
                // 弹层底部主行动归 B2（§3.8 裁决）。
                child: LfConfirmButton(
                  key: const Key('water-amount-submit'),
                  label: '记录',
                  busy: _saving,
                  onPressed: _saving ? null : _submitManual,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
