import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/fixed_bottom_primary_action.dart';

/// 拍照页重建（阶段 D）共用的测试辅助。
///
/// 背景：页面的固定底部 CTA（`FixedBottomPrimaryAction`）占掉 body 视口底部
/// 约 72dp。`tester.ensureVisible` 只保证目标「进入视口」，不保证它完整落在
/// 底栏之上——实测会把一个 48dp 的按钮留在「上半截可见、下半截压在栏下」
/// 的位置，此时 `tap` 的坐标落在栏上，点击被吞（而且是无声的：`tapAt` 命中
/// 了栏，不会有 warnIfMissed）。
///
/// [revealFully] 把目标**完整**滚进「底栏之上」的可视区：先 `ensureVisible`，
/// 再按实测矩形与可视底边的差值逐次上推。可视底边 = 底栏顶边（底栏在屏时）。
///
/// 几何探针而不是魔法数：不同视口（800×600 / 900×1600 / 320dp）下差值不同，
/// 固定 nudge 会从「不够」摆到「推过头」（目标顶边越过视口顶，tap 同样落空）。
Future<void> revealFully(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();

  var visibleBottom =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  final bar = find.byType(FixedBottomPrimaryAction);
  if (bar.evaluate().isNotEmpty) {
    visibleBottom = tester.getTopLeft(bar).dy;
  }

  for (var i = 0; i < 4; i++) {
    final rect = tester.getRect(finder);
    final overflow = rect.bottom - visibleBottom;
    if (overflow <= 0) return;
    await tester.drag(find.byType(ListView), Offset(0, -overflow - 4));
    await tester.pumpAndSettle();
  }
}

/// 进入候选编辑面（docs/21 §5.4：结果卡是主面，编辑器是 `cta-edit-items`
/// 进入的二级面，两面互斥渲染）。识别完成后必须先走这一步，才能看到
/// `scan-candidate-*` 这些编辑控件。
Future<void> enterEditor(WidgetTester tester) async {
  final enter = find.byKey(const Key('cta-edit-items'));
  await tester.scrollUntilVisible(
    enter,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await revealFully(tester, enter);
  await tester.tap(enter);
  await tester.pumpAndSettle();
}

/// 进入编辑面后页面总高度变短，原滚动位置可能已越过新的 max extent，
/// ListView 会钳在底部；先滚回顶部再找编辑器顶部的控件。
Future<void> scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 4000));
  await tester.pumpAndSettle();
}
