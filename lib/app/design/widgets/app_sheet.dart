import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';

/// 底部弹层用的共享外壳（规范第二批「AlertDialog→底部弹层」）。
///
/// `show` 提供标题+内容+按钮行的标准布局；`showStateful` 允许调用方用
/// `StatefulBuilder` 自持弹层内部状态（如输入错误提示、进行中标记）。
/// 文案、Key 与返回值语义与原 `showDialog` 完全一致，仅改变容器。
/// 弹出/收起动效统一走 [AppMotion] 令牌（250ms easeOutCubic 入场 / 150ms 退场）。
/// 弹层底部内衬：键盘高 + 安全区内边距，**下限** [LfDimens.sheetBottomMinInset]。
///
/// 2026-10-16 用户实测「添加记录时保存按钮太靠下」：两值都为 0 时（无键盘、
/// 手势条不占内边距）弹层最下边的控件会贴到屏幕底边。所有弹层入口共用这一
/// 个计算点，避免「这个弹层垫了、那个没垫」。
double sheetBottomInset(BuildContext context) {
  final insets =
      MediaQuery.viewInsetsOf(context).bottom +
      MediaQuery.paddingOf(context).bottom;
  return insets < LfDimens.sheetBottomMinInset
      ? LfDimens.sheetBottomMinInset
      : insets;
}

class AppSheet {
  const AppSheet._();

  /// 弹出底部弹层并返回结果，语义与 `showDialog` 相同（点遮罩/返回 = null）。
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    Widget? content,
    Widget? actions,
  }) => _show<T>(
    context,
    title: title,
    bodyBuilder: (context) =>
        _AppSheetBody(title: title, content: content, actions: actions),
  );

  /// 同 [show]，但整个弹层主体（内容+按钮）由 [bodyBuilder] 构建，
  /// 配合 `StatefulBuilder` 即可让弹层内部状态驱动重建。
  static Future<T?> showStateful<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder bodyBuilder,
  }) => _show<T>(
    context,
    title: title,
    bodyBuilder: (sheetContext) => _StatefulSheetBody(
      title: title,
      child: Builder(builder: bodyBuilder),
    ),
  );

  /// 大弹层（内容可能超一屏）：[body] 可滚动，[actions] 固定在弹层底部
  /// 不随内容滚走（docs/21 §3.1「大弹层内 sticky 底部按钮区」）。
  ///
  /// 两个 builder 都收到同一个 [setSheetState]，所以 body 里的状态变化
  /// （如「正在保存…」禁用态）能同步刷新 sticky 按钮行。
  static Future<T?> showForm<T>(
    BuildContext context, {
    required String title,
    required Widget Function(BuildContext context, StateSetter setSheetState)
    body,
    required Widget Function(BuildContext context, StateSetter setSheetState)
    actions,
  }) {
    return _show<T>(
      context,
      title: title,
      bodyBuilder: (sheetContext) =>
          _FormSheetBody(title: title, body: body, actions: actions),
    );
  }

  /// 【N7 机制化】带提交的表单弹层：保存失败**不关窗**。
  ///
  /// [onSubmit] 返回 `null` = 保存成功（弹层自动关闭，返回值由 [resultBuilder]
  /// 给出）；返回字符串 = 这条错误留在弹层内显示，输入内容与弹窗都不丢。
  /// 提交进行中整条行动行被禁用（`IgnorePointer`）且主行动按钮转入 busy，
  /// 防重复提交。
  ///
  /// 长耗时/会抛异常的落库调用一律写在 [onSubmit] 里 `try/catch`，把异常翻成
  /// 一句人话返回——**不要先 pop 再报错**（弹层挂在根导航器上盖住整页，
  /// 页面级 snackbar 物理上看不见，这正是用户点名的缺陷）。
  static Future<T?> showSubmitForm<T>(
    BuildContext context, {
    required String title,
    required Widget Function(BuildContext context, StateSetter setSheetState)
    body,
    required Future<String?> Function() onSubmit,
    T? Function()? resultBuilder,
    String submitLabel = '保存',
    String cancelLabel = '取消',
    Key? submitKey,
    Key? errorKey,
  }) {
    return _show<T>(
      context,
      title: title,
      bodyBuilder: (sheetContext) => _SubmitSheetBody<T>(
        title: title,
        body: body,
        onSubmit: onSubmit,
        resultBuilder: resultBuilder,
        submitLabel: submitLabel,
        cancelLabel: cancelLabel,
        submitKey: submitKey,
        errorKey: errorKey,
      ),
    );
  }

  /// 弹出完全自定义主体的底部弹层（返回内容全权由 [builder] 决定），
  /// 自带键盘内边距与拖拽把手。语义与 `showDialog` 相同。
  static Future<T?> showCustom<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      // 拖拽只认把手，不给整层（docs/21 §2.9「把手跟随拖拽」）：
      // `enableDrag: true` 会把整张弹层变成纵向拖拽区，层内滚动/滑块
      // 下拉时变成关弹层，窄屏巡检与训练记录弹层都会被打断。
      // Flutter 在 `showDragHandle: true && !enableDrag` 时给把手单独挂
      // 手势，效果正是「按住把手拖动跟手、松手按进度回弹」。
      enableDrag: false,
      showDragHandle: true,
      useSafeArea: true,
      // 【旧视觉·待按 docs/21 重建】 旧毛玻璃底栏；新底栏为贴底直角栏，弹层仍走根导航器（docs/21 §3.6）。
      // 动作闭包因此须用弹层内 context 弹出（见各调用点的 Builder 模式）。
      useRootNavigator: true,
      sheetAnimationStyle: _motion,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: LfDimens.pagePadding,
            right: LfDimens.pagePadding,
            // 键盘高 + 安全区，但**至少** [LfDimens.sheetBottomMinInset]：
            // 两者都为 0 时主行动会贴到屏幕底边（2026-10-16 用户实测）。
            bottom: sheetBottomInset(sheetContext),
          ),
          child: builder(sheetContext),
        ),
      ),
    );
  }

  static Future<T?> _show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder bodyBuilder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      showDragHandle: true,
      useSafeArea: true,
      // docs/21 §3.6：弹层走根导航器浮在毛玻璃底栏上方，玻璃与 hit 链互不干扰。
      // 动作闭包因此须用弹层内 context 弹出（见各调用点的 Builder 模式）。
      useRootNavigator: true,
      sheetAnimationStyle: _motion,
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
        ),
        child: Padding(
          // 键盘弹出时保证内容可见（isScrollControlled + 视图插值）。
          padding: EdgeInsets.only(
            left: LfDimens.pagePadding,
            right: LfDimens.pagePadding,
            // 键盘高 + 安全区，但**至少** [LfDimens.sheetBottomMinInset]：
            // 两者都为 0 时主行动会贴到屏幕底边（2026-10-16 用户实测）。
            bottom: sheetBottomInset(sheetContext),
          ),
          child: bodyBuilder(sheetContext),
        ),
      ),
    );
  }

  /// 弹层进出场：与页面转场同曲线，入场 250ms、退场 150ms（docs/21 §2.9）。
  static const AnimationStyle _motion = AnimationStyle(
    curve: AppMotion.curve,
    duration: AppMotion.base,
    reverseDuration: AppMotion.fast,
  );
}

class _AppSheetBody extends StatelessWidget {
  const _AppSheetBody({required this.title, this.content, this.actions});

  final String title;
  final Widget? content;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final header = Text(title, style: LfText.headline);
    final body = content;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(alignment: Alignment.centerLeft, child: header),
        // 内容在滚动的弹层里，短内容按自身高度收缩。
        //
        // 刻意**不**在这里套 Flexible：调用方可能已经把自己的内容放进滚动
        // 视图（training 记录组弹层就是），此时再插 Flexible，父节点会是
        // _SingleChildViewport 而不是 Flex，直接抛
        // 「Incorrect use of ParentDataWidget」。超高内容由调用方自己滚动
        // （见文档里的做法），弹层壳只负责标题与按钮行的固定位置。
        if (body != null) ...[const SizedBox(height: 12), body],
        if (actions != null) ...[const SizedBox(height: 16), actions!],
        const SizedBox(height: 4),
      ],
    );
  }
}

/// 弹层内部状态型布局：标题 + 单一主体（内容由调用方的 StatefulBuilder 提供）。
class _StatefulSheetBody extends StatelessWidget {
  const _StatefulSheetBody({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(title, style: LfText.headline),
      ),
      const SizedBox(height: 12),
      Flexible(child: SingleChildScrollView(child: child)),
      const SizedBox(height: 4),
    ],
  );
}

/// 大弹层布局：标题 + 可滚动 [body] + 固定底部 [actions]（sticky）。
///
/// `body` 放在 `Flexible` 的滚动区里、`actions` 留在滚动区之外，所以内容
/// 再长也只在中间滚动，按钮行始终贴在弹层底部（docs/21 §3.1）。
/// 内层 `StatefulBuilder` 让两个 builder 共享同一个 [StateSetter]。
class _FormSheetBody extends StatefulWidget {
  const _FormSheetBody({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final Widget Function(BuildContext context, StateSetter setSheetState) body;
  final Widget Function(BuildContext context, StateSetter setSheetState)
  actions;

  @override
  State<_FormSheetBody> createState() => _FormSheetBodyState();
}

class _FormSheetBodyState extends State<_FormSheetBody> {
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: Alignment.centerLeft,
        child: Text(widget.title, style: LfText.headline),
      ),
      const SizedBox(height: 12),
      Flexible(
        child: SingleChildScrollView(child: widget.body(context, setState)),
      ),
      const SizedBox(height: 16),
      widget.actions(context, setState),
      const SizedBox(height: 4),
    ],
  );
}

/// 常见「文本说明 + 错误提示」内容块（多用于表单型弹层）。
class SheetMessage extends StatelessWidget {
  const SheetMessage(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: LfText.bodySmall.copyWith(color: color));
}

/// 提交型表单弹层（[AppSheet.showSubmitForm]）：标题 + 可滚动 body +
/// 行动行上方错误行（仅失败时） + 统一行动行（左取消 B6 / 右主行动 B2）。
///
/// 提交中整行禁用；失败不 pop，只把错误文案画出来，输入内容原样保留。
class _SubmitSheetBody<T> extends StatefulWidget {
  const _SubmitSheetBody({
    required this.title,
    required this.body,
    required this.onSubmit,
    required this.resultBuilder,
    required this.submitLabel,
    required this.cancelLabel,
    required this.submitKey,
    required this.errorKey,
  });

  final String title;
  final Widget Function(BuildContext context, StateSetter setSheetState) body;
  final Future<String?> Function() onSubmit;
  final T? Function()? resultBuilder;
  final String submitLabel;
  final String cancelLabel;
  final Key? submitKey;
  final Key? errorKey;

  @override
  State<_SubmitSheetBody<T>> createState() => _SubmitSheetBodyState<T>();
}

class _SubmitSheetBodyState<T> extends State<_SubmitSheetBody<T>> {
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    String? failure;
    try {
      failure = await widget.onSubmit();
    } catch (_) {
      // 落库异常也不关窗：兜底文案，输入内容原样可继续编辑。
      failure = '保存失败，请重试。';
    }
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(widget.resultBuilder?.call());
      return;
    }
    setState(() {
      _submitting = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(widget.title, style: LfText.headline),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: SingleChildScrollView(child: widget.body(context, setState)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: widget.errorKey,
            style: LfText.bodySmall.copyWith(color: context.lf.error),
          ),
        ],
        const SizedBox(height: 16),
        IgnorePointer(
          ignoring: _submitting,
          child: Opacity(
            opacity: _submitting ? 0.6 : 1,
            child: OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 12,
              overflowSpacing: 8,
              children: [
                LfTextButton(
                  label: widget.cancelLabel,
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                LfConfirmButton(
                  key: widget.submitKey,
                  label: widget.submitLabel,
                  busy: _submitting,
                  expand: false,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
