import 'dart:async';

import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_number_field.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_toggle_switch.dart';
import 'package:localfit_ai/features/progress/data/steps_repository.dart';

/// 步数权限与开关弹层（docs/30 §2 D9；2026-10-23 用户：「步数授权取消不掉」）。
///
/// 两件事在同一个弹层里，**分开说**：
///  * **应用内开关**「读取本机步数」：关掉后 App 真的不再读数、不再落库
///    （`StepsRepository.setEnabled(false)`，步数卡显示「已关闭」）；
///  * **系统权限**：Android 的运行时权限只能在系统设置里撤销——应用内的
///    开关撤不掉它。所以「去系统设置」按钮两态都在，文案写明两者的区别。
///
/// R11 起本弹层由今日页步数卡与设置页「步数与身体活动」行共用。
///
/// 【2026-10-26 用户：「步数它读不到系统数据，也不能自己输入」】同一张弹层
/// 里补了**手动记录**：没有计步传感器、或系统权限/读数一直拿不到时，用户
/// 仍然知道自己走了多少——「读不到」不该等于「记不了」。手动值当天优先于
/// 传感器（`StepsRepository.syncToday` 会跳过 manual 行），随时可「恢复自动」。
Future<void> showStepsPermissionSheet(
  BuildContext context,
  StepsRepository repository, {
  String? localDate,
}) {
  return AppSheet.showStateful<void>(
    context,
    title: '步数与身体活动',
    bodyBuilder: (sheetContext) => _StepsPermissionBody(
      repository: repository,
      // 不给就按「本机今天」——设置页那边没有注入时钟，而手动记录就是记今天。
      localDate: localDate ?? _todayLocalDate(),
    ),
    // 弹层走根导航器（docs/21 §3.6），动作闭包须用弹层内 context 弹出。
  );
}

/// 「手动记录步数」弹层：一个数字输入 + 保存。
///
/// 返回写入的值（取消 / 校验失败返回 null）。校验在仓储里做（0–200,000），
/// 这里只负责把错误原样显示——不自己发明一套边界。
///
/// 【为什么是 StatefulWidget 而不是 `StatefulBuilder` + 外部 controller】
/// controller 若由调用方在这之外 dispose，弹层的**退场动画**还在重建
/// `TextFormField`，会撞「A TextEditingController was used after being
/// disposed」（实测 4 个异常）。让弹层自己持有、自己 dispose 才是对的。
Future<int?> showManualStepsDialog(
  BuildContext context, {
  required String localDate,
  required StepsRepository repository,
  int? initialSteps,
}) {
  return AppSheet.showStateful<int>(
    context,
    title: '手动记录步数',
    bodyBuilder: (sheetContext) => _ManualStepsBody(
      localDate: localDate,
      repository: repository,
      initialSteps: initialSteps,
    ),
  );
}

class _ManualStepsBody extends StatefulWidget {
  const _ManualStepsBody({
    required this.localDate,
    required this.repository,
    this.initialSteps,
  });

  final String localDate;
  final StepsRepository repository;
  final int? initialSteps;

  @override
  State<_ManualStepsBody> createState() => _ManualStepsBodyState();
}

class _ManualStepsBodyState extends State<_ManualStepsBody> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialSteps == null ? '' : '${widget.initialSteps}',
  );
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final steps = int.tryParse(_controller.text.trim());
    if (steps == null) {
      setState(() => _errorText = '请填一个整数步数。');
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.repository.saveManualSteps(
        localDate: widget.localDate,
        steps: steps,
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = error.message;
      });
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, steps);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '适合没有计步传感器、或系统读数一直拿不到的时候。手动值当天优先于'
          '传感器；之后要交还给系统，点「恢复自动读取」。',
          style: LfText.caption.copyWith(color: context.lf.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        AppNumberField(
          fieldKey: const Key('steps-manual-input'),
          label: '今天的步数',
          unit: '步',
          integerOnly: true,
          controller: _controller,
          autofocus: true,
          errorText: _errorText,
        ),
        const SizedBox(height: LfDimens.spaceLarge),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(label: '取消', onPressed: () => Navigator.pop(context)),
            LfConfirmButton(
              key: const Key('steps-manual-save'),
              label: '保存',
              expand: false,
              busy: _saving,
              onPressed: () => unawaited(_save()),
            ),
          ],
        ),
      ],
    );
  }
}

/// 本机今天的 `yyyy-MM-dd`（不引时钟：这里只用于「手动记录今天」）。
String _todayLocalDate() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

String _formatSteps(int steps) => steps.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);

/// `showStateful` 的 body 拿不到 actions 行，所以这里给一份自足的表体 +
/// 底部动作（含「去系统设置」）。
///
/// 【v2（design/round8/steps-sheet-v2.html，2026-10-30 用户批准实施）】
/// 用户原话「简单一点，不要写那么多说明，卡片也重新设计一下」：
///  - 原来 5 段说明文字（开关注释 2 行 + 状态段 2–3 行 + 权限段 2 行 +
///    手动区 4 行 + 按钮区重复）全部撤下，改成：
///    大数字卡（步数 + 来源胶囊 + 目标进度）+ 色点状态一句话；
///  - 提示句只在该说的时候出现同一行（未授权 / 设备不支持 / 这次没读到）；
///  - 按钮按状态出现（「去系统设置」只在两种「可以去设置」的状态出现；
///    「重新读取」只在有传感器时出现），最多三颗；
///  - 「自动读取本机步数」开关压到底部成为安静的一行。
/// 所有 key 与行为不变（steps-enabled-switch / steps-enabled-note /
/// steps-state-note / steps-permission-sheet-body / steps-manual-entry /
/// steps-manual-clear / steps-refresh / steps-retry /
/// cta-open-app-settings / steps-today-value）。
class _StepsPermissionBody extends StatefulWidget {
  const _StepsPermissionBody({required this.repository, this.localDate});

  final StepsRepository repository;

  /// 手动记录落在哪一天（null = 不显示手动区：没有日期就没有「哪一天」）。
  final String? localDate;

  @override
  State<_StepsPermissionBody> createState() => _StepsPermissionBodyState();
}

class _StepsPermissionBodyState extends State<_StepsPermissionBody> {
  bool? _enabled;

  /// 权限读数（需求 2：三态各自说实话，别让用户猜自己是哪一种）。
  StepsAvailability? _availability;

  /// 今天这一步（步数 + 来源）；null = 还没有行。
  StepsDayValue? _day;

  /// 今日目标（v2 大数字卡的目标行；读不到就不画进度，不编数字）。
  int? _goal;

  /// 「重新读取」进行中（2026-10-31 用户：「点击重新读取要显示动画或读取状态」）。
  ///
  /// 只驱动按钮的忙碌态，**不改大数字**——读数期间卡上仍是上一次的真实值，
  /// 不先把数字抹成「— —」再等回来（那会让用户以为数据被清空了）。
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final enabled = await widget.repository.readEnabled();
    final availability = await widget.repository.readAvailability();
    final localDate = widget.localDate;
    final day = localDate == null
        ? null
        : await widget.repository.readDay(localDate);
    final goal = await widget.repository.readDailyGoal();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _availability = availability;
      _day = day;
      _goal = goal;
    });
  }

  /// 「重新读取」：**真的同步一次**（读传感器 → 算差值 → 落库），再刷新本弹层。
  ///
  /// 忙碌态覆盖整段（含同步后的重读）：重试期间按钮显示「读取中…」且禁用，
  /// 连点不会排队发出第二次传感器读。异常也走 `finally` 复位——否则一次
  /// 平台异常会把按钮永久卡在禁用态（那是「点了没反应」的另一种形态）。
  Future<void> _refresh() async {
    final localDate = widget.localDate;
    if (localDate == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.repository.syncToday(localDate);
      if (!mounted) return;
      await _load();
    } catch (_) {
      // 读不到就是「这次没读到」：状态由 `_load` 的读数决定，这里不编结果。
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  /// 「重试」：只重读状态（不动开关）。给「这次没读到 / 状态未知」用。
  Future<void> _retry() async {
    setState(() => _availability = null);
    await _load();
  }

  /// 手动记录（写库后重读本弹层；步数卡的 DB 流会自己推上去）。
  Future<void> _manualEntry() async {
    final localDate = widget.localDate;
    if (localDate == null) return;
    final steps = await showManualStepsDialog(
      context,
      localDate: localDate,
      repository: widget.repository,
      initialSteps: _day?.steps,
    );
    if (steps == null || !mounted) return;
    await _load();
  }

  /// 恢复自动读取：**只清手动行**（传感器写的那行不是手动记录，不能删）。
  Future<void> _clearManual() async {
    final localDate = widget.localDate;
    if (localDate == null) return;
    await widget.repository.clearManualSteps(localDate);
    if (!mounted) return;
    await _load();
  }

  Future<void> _toggle() async {
    final current = _enabled;
    if (current == null) return;
    final next = !current;
    setState(() => _enabled = next);
    await widget.repository.setEnabled(next);
  }

  /// 状态行的一句话（v2：≤ 一句，不再带「怎么修」的长段落）。
  String get _stateNote => switch (_availability) {
    StepsAvailability.available => '已连接 · 自动读取中',
    StepsAvailability.denied => '未授权 · 需要系统「身体活动」权限',
    StepsAvailability.noSensor => '设备不支持计步',
    StepsAvailability.disabled => '应用内已停止读取',
    StepsAvailability.noReading => '这次没读到',
    null => '正在读取状态…',
  };

  /// 状态色点：绿=正常 / 琥珀=要用户动作 / 灰=不可用。
  Color _stateDotColor() {
    final c = context.lf;
    return switch (_availability) {
      StepsAvailability.available => c.success,
      StepsAvailability.denied || StepsAvailability.noReading => c.warning,
      StepsAvailability.noSensor ||
      StepsAvailability.disabled => c.mutedForeground,
      null => c.mutedForeground,
    };
  }

  /// 追加提示（v2：只有「要用户动作 / 不可用」的状态才有，最多一行）。
  String? get _stateHint => switch (_availability) {
    StepsAvailability.denied => '授权后自动开始读取；也可以先手动记录今天的步数。',
    StepsAvailability.noSensor => '这台设备没有计步传感器，手动记录不受影响。',
    StepsAvailability.noReading => '传感器在，但这次读数窗口里没有事件，可以点「重试」。',
    StepsAvailability.disabled => '打开下面的开关即可继续自动读取。',
    _ => null,
  };

  bool get _retryable =>
      _availability == StepsAvailability.noReading || _availability == null;

  bool get _canOpenSystemSettings =>
      _availability == StepsAvailability.available ||
      _availability == StepsAvailability.denied;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final enabled = _enabled;
    final day = _day;
    final goal = _goal;
    final steps = day?.steps;
    final isManual = day?.isManual ?? false;
    final progress = (goal != null && goal > 0 && steps != null)
        ? (steps / goal).clamp(0.0, 1.0)
        : null;
    final percent = (goal != null && goal > 0 && steps != null)
        ? ((steps / goal) * 100).round()
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 大数字卡（v2 的核心）────────────────────────────────────────
        Container(
          key: const Key('steps-summary-card'),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [LfColors.brandSoft(brightness), c.card],
            ),
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(LfDimens.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (steps == null)
                    Text(
                      '— —',
                      style: LfText.displayLarge.copyWith(
                        color: c.mutedForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    Text(
                      _formatSteps(steps),
                      key: const Key('steps-today-value'),
                      style: LfText.displayLarge.copyWith(
                        color: c.cardForeground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Text(
                    '步',
                    style: LfText.caption.copyWith(color: c.mutedForeground),
                  ),
                  const SizedBox(width: 8),
                  _StepsSourcePill(manual: isManual, hasData: steps != null),
                ],
              ),
              if (goal != null && goal > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '今日目标 ${_formatSteps(goal)}',
                        style: LfText.micro.copyWith(color: c.mutedForeground),
                      ),
                    ),
                    if (percent != null)
                      Text(
                        '$percent%',
                        style: LfText.micro.copyWith(color: c.mutedForeground),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      children: [
                        ColoredBox(
                          color: c.muted,
                          child: const SizedBox.expand(),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress ?? 0,
                          child: ColoredBox(
                            color: c.primary,
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        // ── 状态一行（色点 + 一句话）────────────────────────────────────
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _stateDotColor(),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: LfDimens.spaceSmall),
            Expanded(
              child: Text(
                _stateNote,
                key: const Key('steps-state-note'),
                style: LfText.body.copyWith(color: c.cardForeground),
              ),
            ),
          ],
        ),
        if (_stateHint case final hint?) ...[
          const SizedBox(height: 6),
          Text(
            hint,
            key: const Key('steps-permission-sheet-body'),
            style: LfText.caption.copyWith(color: c.mutedForeground),
          ),
        ],
        const SizedBox(height: LfDimens.spaceLarge),
        // ── 按钮（v2：按状态出现，最多三颗）──────────────────────────────
        Wrap(
          spacing: LfDimens.spaceSmall,
          runSpacing: LfDimens.spaceXSmall,
          children: [
            if (widget.localDate != null)
              LfSoftButton(
                key: const Key('steps-manual-entry'),
                label: isManual ? '修改手动记录' : '手动记录',
                icon: Icons.edit_note,
                dense: true,
                onPressed: () => unawaited(_manualEntry()),
              ),
            if (isManual)
              LfSoftButton(
                key: const Key('steps-manual-clear'),
                label: '恢复自动',
                icon: Icons.restart_alt,
                dense: true,
                onPressed: () => unawaited(_clearManual()),
              ),
            if (_retryable)
              LfTextButton(
                key: const Key('steps-retry'),
                label: '重试',
                onPressed: () => unawaited(_retry()),
              ),
            if (_availability == StepsAvailability.available ||
                _availability == StepsAvailability.noReading)
              LfSoftButton(
                key: const Key('steps-refresh'),
                // 【忙碌态为什么改标签而不只开 `busy`】`busy` 会把标签换成三颗
                // 点动画（`_lfButtonLabel` 的 loading 分支），读屏也只听到
                // 「处理中」——用户看到的是「点了以后字没了」。这里**保留
                // 文字**：「读取中…」既说清在干什么，也让忙碌态可被断言；
                // 同时禁用，连点不会再发一次传感器读。
                label: _refreshing ? '读取中…' : '重新读取',
                icon: _refreshing ? null : Icons.refresh,
                dense: true,
                onPressed: _refreshing ? null : () => unawaited(_refresh()),
              ),
            if (_canOpenSystemSettings)
              LfConfirmButton(
                key: const Key('cta-open-app-settings'),
                label: '去系统设置',
                expand: false,
                // 【2026-10-31 用户：去系统设置比左边两颗大很多】同一行混排
                // 时三颗按钮等高（dense h36，与 LfSoftButton.dense 同几何）。
                dense: true,
                onPressed: () async {
                  Navigator.pop(context);
                  await widget.repository.openAppSettings();
                },
              ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Container(height: 1, color: c.border),
        const SizedBox(height: 2),
        // ── 安静的一行开关（v2：压到底部）──────────────────────────────
        //
        // 旧弹层那段长说明（「关闭后 App 不再读取…」）**视觉撤下**，但那条
        // 事实不能丢：开关 ≠ 撤销系统权限。它整体进这一行的语义标签
        // （`steps-enabled-note`），读屏仍能听到完整表述。
        Semantics(
          key: const Key('steps-enabled-note'),
          label:
              '自动读取本机步数。关闭后 App 不再读取步数、不再写入步数记录；'
              '系统里的「身体活动」权限仍要在系统设置里单独撤销。',
          toggled: enabled ?? false,
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    '自动读取本机步数',
                    style: LfText.body.copyWith(color: c.cardForeground),
                  ),
                ),
              ),
              if (enabled == null)
                const SizedBox(
                  width: LfToggleSwitch.width,
                  height: LfToggleSwitch.height,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                ExcludeSemantics(
                  child: InkWell(
                    key: const Key('steps-enabled-switch'),
                    onTap: _toggle,
                    borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                    child: Padding(
                      padding: const EdgeInsets.all(LfDimens.spaceMicro),
                      child: LfToggleSwitch(value: enabled),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 来源胶囊（v2）：系统读取 / 手动记录 / 暂无数据。
class _StepsSourcePill extends StatelessWidget {
  const _StepsSourcePill({required this.manual, required this.hasData});

  final bool manual;
  final bool hasData;

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final brightness = Theme.of(context).brightness;
    final (bg, fg, label) = !hasData
        ? (c.muted, c.mutedForeground, '暂无数据')
        : manual
        ? (c.carbs100, c.warningText, '手动记录')
        : (
            LfColors.brandSoft(brightness),
            LfColors.mintText(brightness),
            '系统读取',
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(LfDimens.radiusFull),
      ),
      child: Text(
        label,
        style: LfText.micro.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
