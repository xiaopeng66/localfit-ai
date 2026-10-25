import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart'
    show AppFieldLabel, AppNumberField;
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/features/progress/domain/weight_measurement.dart';
import 'package:localfit_ai/features/progress/presentation/date_picker_sheet.dart';

class WeightEntryDialog extends StatefulWidget {
  const WeightEntryDialog({
    this.initialWeightKg,
    this.todayLocalDate,
    this.initialLocalDate,
    this.onDateChanged,
    this.onSubmit,
    super.key,
  });

  final double? initialWeightKg;

  // 体脂率 / 肌肉量的初值参数随字段一起删除（docs/31 S2，需求 45/46）。

  /// 「今天」的 `yyyy-MM-dd`（docs/29 §P9 需求 33）。
  ///
  /// **由调用方给，弹层不自己读时钟**：页面已经有 `_localDate`（跨零点走
  /// `DailyRollover`），弹层再读一次系统时间，跨零点前后两边会打架。
  /// 不给时（旧调用点/单测）退回「不显示日期字段」的旧形态——见 [initialLocalDate]。
  final String? todayLocalDate;

  /// 预选日期；默认 = [todayLocalDate]。
  final String? initialLocalDate;

  /// 日期被改成 [localDate] 时问调用方「那天记过什么」。
  ///
  /// 返回非 null = 那天已有记录，**字段回填成那天的值**；返回 null = 那天
  /// 没有记录，**字段清空**。清空而不是留着上一个日期的数字：留着的
  /// 话「先填体重再改日期」就把今天的体重写到了 8 月 3 日上——那是伪造
  /// 数据。字段清空是看得见的状态变化，用户可以重新填。
  ///
  /// 不给这个回调 = 日期字段不出现（旧调用点）。
  final Future<WeightEntryResult?> Function(String localDate)? onDateChanged;

  /// 保存动作（落库由调用方给）。返回 `null` = 保存成功并关窗；返回文案 =
  /// **留在弹层内显示、不关窗**，用户填的内容一个字都不丢（N7）。
  ///
  /// 给了它就由弹层负责提交态（按钮 busy + 失败文案内联）；不给则退回
  /// 「关窗后把结果交给调用方」的旧语义（`showCustom` 返回值路径）。
  final Future<String?> Function(WeightEntryResult result)? onSubmit;

  @override
  State<WeightEntryDialog> createState() => _WeightEntryDialogState();
}

class _WeightEntryDialogState extends State<WeightEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _weight;
  final _notes = TextEditingController();

  /// 选中的日期（`yyyy-MM-dd`）。仅当调用方给了 [WeightEntryDialog.todayLocalDate]
  /// 时使用——没给就不显示这一行（旧行为）。
  late String _localDate;

  /// 提交态（只在给了 [WeightEntryDialog.onSubmit] 时使用）。
  bool _saving = false;
  String? _errorText;

  static String _seed(double? value) =>
      value == null ? '' : value.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _weight = TextEditingController(text: _seed(widget.initialWeightKg));
    _localDate = widget.initialLocalDate ?? widget.todayLocalDate ?? '';
  }

  @override
  void dispose() {
    _weight.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          // 标题里的「今日」只在记的就是今天时才成立（需求 33 可回填历史）。
          widget.initialWeightKg == null
              ? '记录体重'
              : _localDate == widget.todayLocalDate
              ? '更新今日体重'
              : '更新 ${formatMonthDayLabel(_localDate)} 体重',
          style: LfText.headline,
        ),
        const SizedBox(height: 12),
        // 超高内容自己滚（弹层壳契约：壳只负责标题与行动行的固定位置，见
        // `app_sheet.dart` 的 `_AppSheetBody` 注释）。标签搬到框外后，字段区
        // 在 2.0× + 键盘下的自然高度曾超过 `0.9 × 屏高 − 键盘高`；schema 22
        // 删掉体脂率/肌肉量两个字段后余量宽了些，但这条滚动**仍然必需**：
        // 日期行 + 备注 + 错误行在 640dp 屏上照样会顶到键盘线。没有这层滚动，
        // RenderFlex 会溢出，行动行被画到弹层框之外（键盘底下）——保存按钮
        // 既看不见也点不到（设备实测 1080×2340 / 2.0× / 键盘顶 1563）。
        Flexible(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 需求 33：日期字段。**只在调用方给了「今天」时才出现**——
                  // 没给就没有可信的上下界（未来日不能选、下界从哪天算都是编的）。
                  if (widget.todayLocalDate case final today?)
                    _DateField(
                      localDate: _localDate,
                      today: today,
                      onPick: _pickDate,
                    ),
                  if (widget.todayLocalDate != null) const SizedBox(height: 12),
                  AppNumberField(
                    fieldKey: const Key('weight-input'),
                    label: '体重',
                    unit: 'kg',
                    controller: _weight,
                    autofocus: true,
                    validator: (value) {
                      final weight = double.tryParse(value?.trim() ?? '');
                      if (weight == null || !weight.isFinite) {
                        return '请输入有效体重';
                      }
                      if (weight < 35 || weight > 300) {
                        return '体重必须在 35–300 kg 之间';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  // 体脂率 / 肌肉量两个字段已删（docs/31 S2，需求 45/46）：
                  // 用户原话「添加的弹窗卡片去掉体脂率和肌肉量」。
                  LfTextField(
                    fieldKey: const Key('weight-notes'),
                    label: '备注',
                    optional: true,
                    controller: _notes,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 保存失败文案画在行动行上方（N7）：弹层不关，字段原样可改。
        if (_errorText case final error?)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LfFieldError(error, key: const Key('weight-error')),
          ),
        // 弹层底部行动（§3.4/§3.8）：左 = 取消（B6），右 = 主行动（B2）。
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(label: '取消', onPressed: () => Navigator.pop(context)),
            LfConfirmButton(
              key: const Key('weight-save'),
              label: '保存',
              expand: false,
              busy: _saving,
              onPressed: _saving ? null : _submit,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final today = widget.todayLocalDate;
    if (today == null) return;
    final picked = await showDatePickerSheet(
      context,
      selected: _localDate,
      // 下界 = 今天往前一年：更早的体重记录没有业务意义（趋势图只到 30 天），
      // 而无限回溯的日历要用户翻几十个月才到得了自己的目标日期。
      firstDate: formatIsoLocalDate(
        parseLocalDate(today).subtract(const Duration(days: 365)),
      ),
      // 上界 = 今天：未来日不能选（明天还没发生）。
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    await _adoptDate(picked);
  }

  /// 把日期换成 [date] 并**同步字段内容**（见 [WeightEntryDialog.onDateChanged]）。
  Future<void> _adoptDate(String date) async {
    setState(() {
      _localDate = date;
      _errorText = null;
    });
    final lookup = widget.onDateChanged;
    if (lookup == null) return;
    WeightEntryResult? existing;
    try {
      existing = await lookup(date);
    } catch (_) {
      // 查不到就按「那天没有记录」处理（清空）。**不弹错、不中止**：
      // 用户此刻要做的事是记体重，回填失败不该让它变成一件需要处理的事。
      existing = null;
    }
    if (!mounted || _localDate != date) return; // 回调期间又改了日期，丢弃
    _applySeed(existing);
  }

  /// 用 [seed] 重写字段（null = 清空，不沿用上一个日期的值）。
  void _applySeed(WeightEntryResult? seed) {
    setState(() {
      _weight.text = seed == null ? '' : _seed(seed.weightKg);
      _notes.text = seed?.notes ?? '';
    });
  }

  Future<void> _submit() async {
    // 双击/连点只落一次库：第一击同步把 `_saving` 置位，第二击直接返回。
    // （落库现在是异步的，`Navigator.pop` 不再在第一击里同步发生，所以
    // 旧版「第二次点击落在退场动画的 IgnorePointer 上」这条天然防护不存在了。）
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final notes = _notes.text.trim();
    final result = WeightEntryResult(
      weightKg: double.parse(_weight.text.trim()),
      notes: notes.isEmpty ? null : notes,
      localDate: _localDate.isEmpty ? null : _localDate,
    );
    final onSubmit = widget.onSubmit;
    if (onSubmit == null) {
      Navigator.pop(context, result);
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    String? failure;
    try {
      failure = await onSubmit(result);
    } catch (_) {
      failure = '体重保存失败，请重试。';
    }
    if (!mounted) return;
    if (failure == null) {
      Navigator.pop(context, result);
      return;
    }
    setState(() {
      _saving = false;
      _errorText = failure;
    });
  }
}

final class WeightEntryResult {
  const WeightEntryResult({required this.weightKg, this.notes, this.localDate});

  final double weightKg;
  // 体脂率 / 肌肉量两个字段随 schema 22 删除（docs/31 S2，需求 45/46）。
  final String? notes;

  /// 用户选的日期（`yyyy-MM-dd`）；**null = 弹层没显示日期字段**（旧调用点
  /// 没给 `todayLocalDate`），调用方仍按「今天」落库。
  final String? localDate;
}

/// 日期行（需求 33）：标签在框外上方，框内是「日期值 + 今天/修改」。
///
/// 可点**整行**（44dp），不只是右侧的「修改」二字——一个 24dp 的目标
/// 在真机上要瞄准。`InkWell` 落在整行上，`Key` 也放在整行。
class _DateField extends StatelessWidget {
  const _DateField({
    required this.localDate,
    required this.today,
    required this.onPick,
  });

  final String localDate;
  final String today;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final isToday = localDate == today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldLabel(label: '日期'),
        const SizedBox(height: LfDimens.spaceTiny),
        Semantics(
          button: true,
          label: '日期，$localDate${isToday ? '，今天' : ''}，点击修改',
          child: ExcludeSemantics(
            child: SizedBox(
              height: LfDimens.minTouchTarget,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(LfDimens.radiusMd),
                child: InkWell(
                  key: const Key('weight-entry-date'),
                  borderRadius: BorderRadius.circular(LfDimens.radiusMd),
                  onTap: onPick,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LfDimens.spaceMedium,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: c.input),
                      borderRadius: BorderRadius.circular(LfDimens.radiusMd),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            localDate,
                            key: const Key('weight-entry-date-value'),
                            style: LfText.body.copyWith(
                              color: c.cardForeground,
                            ),
                          ),
                        ),
                        Text(
                          isToday ? '今天 · 修改' : '修改',
                          style: LfText.label.copyWith(
                            color: LfColors.mintText(
                              Theme.of(context).brightness,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
