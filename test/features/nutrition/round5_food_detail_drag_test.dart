import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';

import 'dart:async';

import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/domain/food_detail.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_detail_sheet.dart';

/// T5（docs/32 §4 T5 / 需求 67）：食物详情抽屉拖动稳定性。
///
/// 根因（docs/32 §2·67）：`FoodDetailSheet` 是 `StatelessWidget`，
/// `FutureBuilder(future: load())` 在 **build 内**创建 future；把手拖动起止会
/// `setState` 切换 `WidgetState.dragged`（Flutter `bottom_sheet.dart`）⇒ 重建整棵
/// 子树 ⇒ **重新 `load()`** ⇒ 命中 waiting 分支的 24dp 进度圈 ⇒ 高度跳变。
///
/// 契约：装载只发生一次；拖动（起止）不得再触发 loader；无 waiting 帧。

/// 在**真实弹层**里拖把手：AppSheet 用 `enableDrag: false`，整层没有手势，
/// 只有把手挂了 drag（Flutter `bottom_sheet.dart:377-384`）。把手在弹层顶边
/// 中央往下约 16dp；拖动起止会 `setState` 切换 `WidgetState.dragged`
/// ⇒ 重建 builder ⇒ 旧实现每次都重新 `load()`（实测 1 → 3 → 5）。
Future<void> dragHandle(WidgetTester tester, double dy) async {
  final rect = tester.getRect(find.byType(BottomSheet));
  final start = Offset(rect.center.dx, rect.top + 16);
  final gesture = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.moveBy(Offset(0, dy));
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  const item = FoodLibraryItem(
    id: 'off:1001',
    name: '蒸米饭',
    source: 'openfoodfacts',
    state: 'verified',
    canJoinPlan: true,
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbsPer100g: 25.9,
    fatPer100g: 0.3,
  );

  const detail = FoodDetail(
    foodId: 'off:1001',
    name: '蒸米饭',
    state: 'verified',
    source: 'openfoodfacts',
    licenseStatus: 'allowed',
    isUserCreated: false,
    canJoinPlan: true,
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbsPer100g: 25.9,
    fatPer100g: 0.3,
  );

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: child),
  );

  testWidgets('真弹层里拖把手起止不重新调用 loader（装载恰一次）', (tester) async {
    var loadCalls = 0;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => FoodDetailSheet.show(
                context,
                item: item,
                load: () async {
                  loadCalls++;
                  return detail;
                },
              ),
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pumpAndSettle();
    expect(loadCalls, 1, reason: '首次装载一次');

    // 拖把手起止两次：旧实现在这里涨到 5（每次拖动 2 次重建）。
    await dragHandle(tester, 40);
    await dragHandle(tester, -20);

    expect(
      loadCalls,
      1,
      reason: '拖动起止只重建 UI，不得重新装载（旧实现 build 内建 future ⇒ 实测 1→3→5）',
    );
    expect(
      find.byKey(const Key('food-detail-sheet')),
      findsOneWidget,
      reason: '抽屉没被拖走',
    );
  });

  testWidgets('拖把手后不回到 waiting 帧（用户看到的「拖动时闪加载」）', (tester) async {
    final completer = Completer<FoodDetail?>();
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => FoodDetailSheet.show(
                context,
                item: item,
                load: () => completer.future,
              ),
              child: const Text('打开详情'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开详情'));
    await tester.pump();
    expect(
      find.byKey(const Key('food-detail-loading')),
      findsOneWidget,
      reason: '首次装载时显示 loading',
    );

    completer.complete(detail);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('food-detail-loading')), findsNothing);

    // 拖把手（起止各触发一次 setState 重建）：不得回到 waiting 帧。
    await dragHandle(tester, 40);
    expect(
      find.byKey(const Key('food-detail-loading')),
      findsNothing,
      reason: '拖动重建不得回到 waiting（旧实现会闪回 loading，伴随高度跳变）',
    );
  });
}
