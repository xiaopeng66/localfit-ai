import 'dart:async';

import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
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
Future<void> showStepsPermissionSheet(
  BuildContext context,
  StepsRepository repository,
) {
  return AppSheet.showStateful<void>(
    context,
    title: '步数与身体活动',
    bodyBuilder: (sheetContext) => _StepsPermissionBody(repository: repository),
    // 弹层走根导航器（docs/21 §3.6），动作闭包须用弹层内 context 弹出。
  );
}

/// `showStateful` 的 body 拿不到 actions 行，所以这里给一份自足的表体 +
/// 底部动作（含「去系统设置」）。
class _StepsPermissionBody extends StatefulWidget {
  const _StepsPermissionBody({required this.repository});

  final StepsRepository repository;

  @override
  State<_StepsPermissionBody> createState() => _StepsPermissionBodyState();
}

class _StepsPermissionBodyState extends State<_StepsPermissionBody> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final enabled = await widget.repository.readEnabled();
    if (!mounted) return;
    setState(() => _enabled = enabled);
  }

  Future<void> _toggle() async {
    final current = _enabled;
    if (current == null) return;
    final next = !current;
    setState(() => _enabled = next);
    await widget.repository.setEnabled(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final enabled = _enabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '读取本机步数',
                style: LfText.body.copyWith(color: c.cardForeground),
              ),
            ),
            if (enabled == null)
              const SizedBox(
                width: LfToggleSwitch.width,
                height: LfToggleSwitch.height,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              InkWell(
                key: const Key('steps-enabled-switch'),
                onTap: _toggle,
                borderRadius: BorderRadius.circular(LfDimens.radiusFull),
                child: Padding(
                  padding: const EdgeInsets.all(LfDimens.spaceMicro),
                  child: LfToggleSwitch(value: enabled),
                ),
              ),
          ],
        ),
        const SizedBox(height: LfDimens.spaceSmall),
        Text(
          '关闭后 App 不再读取步数、不再写入步数记录；系统里的「身体活动」'
          '权限仍要在系统设置里单独撤销。',
          key: const Key('steps-enabled-note'),
          style: LfText.micro.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceMedium),
        Text(
          '步数权限由系统管理。要取消，请在系统设置里关闭「身体活动」权限；'
          '取消后步数卡显示「未授权」，其余功能不受影响。',
          key: const Key('steps-permission-sheet-body'),
          style: LfText.caption.copyWith(color: c.mutedForeground),
        ),
        const SizedBox(height: LfDimens.spaceLarge),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            LfTextButton(label: '取消', onPressed: () => Navigator.pop(context)),
            // 「去系统设置」在两态下都是同一个动作：已授权时它是「去撤销」
            // 的入口，未授权时是「去开启」的入口。
            LfConfirmButton(
              key: const Key('cta-open-app-settings'),
              label: '去系统设置',
              expand: false,
              onPressed: () async {
                Navigator.pop(context);
                await widget.repository.openAppSettings();
              },
            ),
          ],
        ),
      ],
    );
  }
}
