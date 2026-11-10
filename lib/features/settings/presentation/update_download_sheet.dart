import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/features/settings/application/app_update_service.dart';
import 'package:localfit_ai/utils/number_format.dart';

/// 「正在下载新版」弹层（2026-11-04 用户：*「根本不知道下载到什么进度了」*）。
///
/// 【为什么要弹层，而不是一条 SnackBar】原来下载期间只有一句「正在下载新版…」，
/// 40 MB 的包在慢网下要几分钟，用户既看不出进度，也没法中止。进度条放在页面
/// SnackBar 里既太窄也留不住（4 秒就消失），所以改为**根导航器弹层**：看得见
/// 百分比与已下载字节，随时能取消。
///
/// 【诚实边界】
/// * 百分比只在**知道总大小**时给：优先用服务器 `content-length`，没有就用发布
///   清单里的 `size`；两者都没有时**不编数字**，只显示已下载多少 + 不确定转圈。
/// * 「下载完成」由服务层的阶段信号说，不由进度数字猜（总大小未知时最后一块
///   和中间任何一块长得一样）。
/// * 弹层关闭时立即取消，销毁时再次兜底；token 由弹层 State 独占。
///
/// 返回的结局交给调用方提示（弹层挂在根导航器上会盖住页面级 SnackBar，
/// 所以弹层先关，再由页面说结果）。
Future<AppUpdateInstallResult?> showUpdateDownloadSheet(
  BuildContext context, {
  required AppUpdateService service,
  required AppReleaseAsset asset,
}) async {
  Future<AppUpdateInstallResult>? operation;
  final result = await AppSheet.showCustom<AppUpdateInstallResult>(
    context,
    builder: (_) => _UpdateDownloadBody(
      service: service,
      asset: asset,
      onStarted: (future) => operation = future,
    ),
  );
  // 把手/外层导航直接 pop 可绕过 canPop。安装已交接时仍须等真实结果，
  // 不能一律把 route 的 null 解释成「取消下载」。
  return result ?? await operation;
}

class _UpdateDownloadBody extends StatefulWidget {
  const _UpdateDownloadBody({
    required this.service,
    required this.asset,
    required this.onStarted,
  });

  final AppUpdateService service;
  final AppReleaseAsset asset;
  final ValueChanged<Future<AppUpdateInstallResult>> onStarted;

  @override
  State<_UpdateDownloadBody> createState() => _UpdateDownloadBodyState();
}

class _UpdateDownloadBodyState extends State<_UpdateDownloadBody> {
  /// 用户取消 / 弹层关闭都走它：Dio 会取消订阅并删掉半截文件。
  final _cancelToken = CancelToken();

  int _received = 0;

  /// 服务器给的总字节；`<= 0` 或 null 表示没给（压缩传输常见）。
  int? _wireTotal;

  AppUpdateInstallPhase _phase = AppUpdateInstallPhase.downloading;

  /// 已经点了取消：按钮转入「正在取消…」，不再重复取消。
  bool _cancelling = false;

  /// 结果已返回或弹层已关闭，退场动画期间也不能再更新、再 pop。
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.onStarted(_run());
  }

  @override
  void dispose() {
    // 遮罩点掉 / 返回键：弹层已经没了，下载不该在后台无声继续。
    if (!_cancelToken.isCancelled) _cancelToken.cancel('弹层已关闭');
    super.dispose();
  }

  /// 总大小的显示口径：服务器没给就用发布清单里的 `size`（GitHub 的
  /// `size` 就是文件真实字节数，拿它当分母是诚实的，不是估算）。
  int? get _total {
    final wire = _wireTotal;
    if (wire != null && wire > 0) return wire;
    final declared = widget.asset.sizeBytes;
    if (declared != null && declared > 0) return declared;
    return null;
  }

  Future<AppUpdateInstallResult> _run() async {
    final result = await widget.service.downloadAndInstall(
      widget.asset,
      onProgress: (received, total) {
        if (!mounted || _closing || _cancelling) return;
        setState(() {
          _received = received;
          _wireTotal = total;
        });
      },
      onPhase: (phase) {
        if (!mounted || _closing || _cancelling) return;
        setState(() => _phase = phase);
      },
      cancelToken: _cancelToken,
    );
    if (mounted && !_closing) {
      _closing = true;
      Navigator.of(context).pop(result);
    }
    return result;
  }

  void _cancel() {
    if (_cancelling || _closing) return;
    setState(() => _cancelling = true);
    _cancelToken.cancel('用户取消下载');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.lf;
    final handingOff = _phase == AppUpdateInstallPhase.handingOff;
    final total = handingOff ? _received : _total;
    final ratio = handingOff
        ? 1.0
        : total == null
        ? null
        : (_received / total).clamp(0.0, 1.0);
    final percent = ratio == null ? null : '${(ratio * 100).floor()}%';

    return PopScope<AppUpdateInstallResult>(
      // 交接已发生时不能把系统返回误报成「取消下载」。
      canPop: !handingOff || _closing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop || _closing) return;
        _closing = true;
        // State 在退场动画结束前仍 mounted，等 dispose 才取消会留下空窗。
        _cancelToken.cancel('弹层已关闭');
      },
      child: SingleChildScrollView(
        child: Column(
          key: const Key('update-download-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('下载新版本', style: LfText.headline),
            const SizedBox(height: LfDimens.spaceXSmall),
            Text(
              handingOff ? '下载完成，正在交给系统安装…' : '正在下载 ${widget.asset.name}…',
              key: const Key('update-download-phase'),
              style: LfText.caption.copyWith(color: c.mutedForeground),
            ),
            const SizedBox(height: LfDimens.spaceLarge),
            if (ratio != null) ...[
              LfProgressBar(
                key: const Key('update-download-progress'),
                value: ratio,
                semanticLabel: '下载进度',
                semanticValue: percent,
              ),
              const SizedBox(height: LfDimens.spaceSmall),
              Row(
                children: [
                  Text(
                    percent!,
                    key: const Key('update-download-percent'),
                    style: LfText.bodyStrong.copyWith(color: c.cardForeground),
                  ),
                  const SizedBox(width: LfDimens.spaceSmall),
                  Expanded(
                    child: Text(
                      _bytesLine(total),
                      key: const Key('update-download-bytes'),
                      style: LfText.caption.copyWith(color: c.mutedForeground),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // 不知道总大小：给一个「还在动」的信号，而不是一条永远 0% 的假进度条。
              const Center(
                child: SizedBox(
                  width: LfDimens.iconLg,
                  height: LfDimens.iconLg,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
              const SizedBox(height: LfDimens.spaceSmall),
              Center(
                child: Text(
                  _bytesLine(null),
                  key: const Key('update-download-bytes'),
                  style: LfText.caption.copyWith(color: c.mutedForeground),
                ),
              ),
            ],
            const SizedBox(height: LfDimens.spaceLarge),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                LfTextButton(
                  key: const Key('update-download-cancel'),
                  label: handingOff
                      ? '正在打开安装器…'
                      : _cancelling
                      ? '正在取消…'
                      : '取消下载',
                  busy: handingOff || _cancelling,
                  // 交接给系统安装器之后取消已经没有意义（文件已落盘）。
                  onPressed: (_cancelling || handingOff) ? null : _cancel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 「已下载 15.6 MB / 共 39.1 MB」；总大小未知时只说已下载多少。
  String _bytesLine(int? total) {
    final received = formatMegabytes(_received);
    if (total == null) return '已下载 $received（服务器没给总大小）';
    return '已下载 $received / 共 ${formatMegabytes(total)}';
  }
}
