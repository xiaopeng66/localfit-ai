import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';

import 'package:localfit_ai/app/design/app_motion.dart';

/// 规范统一的加载/读取错误占位：居中、错误色（docs/21 §3），文案由调用方给出。
/// 句式约定「X失败，请重试。」；有针对性恢复动作时由调用方追加指引。
/// 出现时水平抖动 2 周期 ±4dp（400ms 正弦）；减弱动画（disableAnimations）
/// 静止直显不跑抖动层。
final class AppErrorText extends StatefulWidget {
  const AppErrorText(this.message, {super.key, this.color});

  final String message;
  final Color? color;

  @override
  State<AppErrorText> createState() => _AppErrorTextState();
}

class _AppErrorTextState extends State<AppErrorText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: AppMotion.shake,
  );

  bool _armed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    _armed = true;
    if (!AppMotion.reduced(context)) {
      _shake.forward();
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Text(
      widget.message,
      style: LfText.bodySmall
          .copyWith(color: context.lf.mutedForeground)
          .copyWith(color: widget.color ?? Theme.of(context).colorScheme.error),
      textAlign: TextAlign.center,
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LfDimens.spaceLargePlus),
        child: AppMotion.reduced(context)
            ? content
            : AnimatedBuilder(
                animation: _shake,
                builder: (context, _) {
                  // 2 周期正弦：sin(4πt) 在 400ms 内两次全振荡，峰 ±4dp。
                  return Transform.translate(
                    offset: Offset(
                      AppMotion.shakeAmplitude *
                          math.sin(2 * math.pi * 2 * _shake.value),
                      0,
                    ),
                    child: content,
                  );
                },
              ),
      ),
    );
  }
}
