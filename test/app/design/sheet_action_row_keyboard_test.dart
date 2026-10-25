import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/widgets/app_sheet.dart';
import 'package:localfit_ai/app/design/widgets/lf_text_field.dart';
import 'package:localfit_ai/features/hydration/presentation/water_entry_dialog.dart';
import 'package:localfit_ai/features/progress/presentation/weight_entry_dialog.dart';

/// 大字号 + 键盘下，弹层的行动行必须还落在「键盘线之上」（用户点得到）。
///
/// 由来（2026-10-04 设备 2.0× 抽查抓到的真缺陷）：`AppSheet.showCustom` 的
/// 契约是「弹层壳只负责标题与行动行的固定位置，超高内容由调用方自己滚动」
/// （见 `app_sheet.dart` 的 `_AppSheetBody` 注释）。`AppNumberField` /
/// `LfTextField` 把标签搬到框外后，记录体重这类四字段弹层在 2.0× 下自然高度
/// 超过 `0.9 × 屏高 − 键盘高`，而弹层体是没有滚动区的刚性 `Column` ⇒
/// RenderFlex 溢出，**行动行被画到弹层框之外（键盘底下）**：保存按钮既看不见
/// 也点不到。设备实测：1080×2340、2.0×、键盘顶 1563 时保存按钮落在
/// 1855–2008（完全在键盘后面）。
///
/// 两个机型都跑：780dp（本项目走查机型）与 640dp（小屏机）。小屏那一档才是
/// 「记录饮水」滚动区的承重点——只跑 780dp 时把它的滚动去掉测试仍是绿的
/// （变异 M15 如实记过存活），换成小屏就抓得住。
///
/// 判据取「主行动整块在键盘线之上」——比「没有 overflow 日志」更贴近用户，
/// 溢出只是它的机器信号。
void main() {
  const double screenW = 360;
  const double keyboard = 260;

  void useLargeFontKeyboardViewport(WidgetTester tester, double screenH) {
    tester.view.physicalSize = Size(screenW, screenH);
    tester.view.devicePixelRatio = 1.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget host(Future<void> Function(BuildContext context) open) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => open(context),
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );

  /// 打开弹层并断言主行动仍在键盘线之上、且弹层体没有 RenderFlex 溢出。
  Future<void> expectActionRowAboveKeyboard(
    WidgetTester tester, {
    required double screenH,
    required Future<void> Function(BuildContext context) open,
    required Key submitKey,
    required String label,
  }) async {
    useLargeFontKeyboardViewport(tester, screenH);
    final keyboardLine = screenH - keyboard;

    final overflows = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('RenderFlex overflowed')) {
        overflows.add(message.split('\n').first);
        return;
      }
      previous?.call(details);
    };
    try {
      await tester.pumpWidget(host(open));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
    } finally {
      FlutterError.onError = previous;
    }

    final action = tester.getRect(find.byKey(submitKey));
    expect(
      action.bottom,
      lessThanOrEqualTo(keyboardLine + 1),
      reason:
          '$label @ ${screenH}dp：2.0× + 键盘下主行动必须整块在键盘线'
          '（${keyboardLine}dp）之上，实际底边 ${action.bottom}'
          '（行动行被画到弹层框外就是点不到）',
    );
    expect(
      overflows,
      isEmpty,
      reason:
          '$label @ ${screenH}dp：弹层体在 2.0× + 键盘下不该溢出\n'
          '${overflows.join('\n')}',
    );
  }

  Future<void> openWeight(BuildContext context) => AppSheet.showCustom<void>(
    context,
    builder: (_) =>
        WeightEntryDialog(initialWeightKg: 66.0, onSubmit: (_) async => null),
  );

  Future<void> openWater(BuildContext context) => AppSheet.showCustom<void>(
    context,
    builder: (_) =>
        WaterEntryDialog(todayConsumedMl: 600, onSubmit: (_) async => null),
  );

  Future<void> openSubmitFormProbe(BuildContext context) =>
      AppSheet.showSubmitForm<void>(
        context,
        title: '示范表单',
        submitKey: const Key('probe-save'),
        onSubmit: () async => null,
        body: (context, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final label in ['体重', '体脂率（可选）', '肌肉量（可选）', '备注（可选）'])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: LfTextField(fieldKey: Key('probe-$label'), label: label),
              ),
          ],
        ),
      );

  // 2026-10-16 用户实测：「添加记录时保存按钮太靠下」——弹层底衬原来只等于
  // 「键盘 + 安全区」，两者都为 0 时（手势条内边距为 0 的机型）主行动就贴到
  // 屏幕底边。这里钉住**最小底衬**：任何情况下最后一颗控件离底边 ≥ 16dp。
  for (final screenH in <double>[780, 640]) {
    testWidgets('${screenH}dp：无键盘且安全区为 0，主行动离底边仍有最小内衬', (tester) async {
      tester.view.physicalSize = Size(screenW, screenH);
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewInsets = FakeViewPadding.zero;
      tester.view.padding = FakeViewPadding.zero;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPadding);

      await tester.pumpWidget(host(openWeight));
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      final save = tester.getRect(find.byKey(const Key('weight-save')));
      expect(
        screenH - save.bottom,
        greaterThanOrEqualTo(LfDimens.sheetBottomMinInset),
        reason:
            '弹层最下边的控件不能贴到屏幕底边（实测底距 '
            '${(screenH - save.bottom).toStringAsFixed(1)}dp）',
      );
    });
  }

  for (final screenH in <double>[780, 640]) {
    testWidgets('${screenH}dp：记录体重 @ 2.0× + 键盘，保存按钮仍在键盘线之上', (tester) async {
      await expectActionRowAboveKeyboard(
        tester,
        screenH: screenH,
        label: '记录体重',
        submitKey: const Key('weight-save'),
        open: openWeight,
      );
    });

    testWidgets('${screenH}dp：记录饮水 @ 2.0× + 键盘，记录按钮仍在键盘线之上', (tester) async {
      await expectActionRowAboveKeyboard(
        tester,
        screenH: screenH,
        label: '记录饮水',
        submitKey: const Key('water-amount-submit'),
        open: openWater,
      );
    });

    testWidgets('${screenH}dp：showSubmitForm 四字段体 @ 2.0× + 键盘，按钮仍在键盘线之上', (
      tester,
    ) async {
      await expectActionRowAboveKeyboard(
        tester,
        screenH: screenH,
        label: 'showSubmitForm',
        submitKey: const Key('probe-save'),
        open: openSubmitFormProbe,
      );
    });
  }
}
