import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/campus_menus/presentation/manual_nutrition_sheet.dart';

/// 手动营养弹层的**可操作性**判据（docs/41 D10）。
///
/// 重点不是「字段能填」，而是**保存按钮真的能点到**：该弹层曾用
/// `showModalBottomSheet` 的默认 `useRootNavigator: false`，弹层挂进
/// 分支导航器、被 shell 的底部导航条（1080×2340 实测高 189px）盖住最后
/// 一行——`保存（标为用户输入）` 的 bounds 落在导航条下面，点击落到了
/// 导航中间槽（跳到 AI 页），营养没写进库。本文件把「底栏在场时也能保存」
/// 钉死。
void main() {
  CanteenDish dish() => const CanteenDish(
    id: 'm1',
    windowId: 'w1',
    name: 'TomatoEgg',
    evidenceGrade: 'D',
    itemStatus: 'estimated',
    evidence: null,
    tags: [],
  );

  /// 一个带**贴底导航条**的宿主页，形状与 shell 一致：正文是**内嵌
  /// Navigator**（`StatefulShellRoute` 每个分支一个），导航条画在它下面。
  ///
  /// 【为什么必须内嵌】`showModalBottomSheet` 默认 `useRootNavigator: false`
  /// ⇒ 弹层挂进**最近**的 Navigator。在真实 shell 里那就是分支导航器，
  /// 于是弹层落在 body 区域内、被 shell 的底栏盖住；直接在 MaterialApp 的
  /// 根 Navigator 里测**复现不出来**（根路由在 Scaffold 之上）。
  Widget host({
    required Future<void> Function() openSheet,
    required VoidCallback onNavTap,
  }) => MaterialApp(
    home: Scaffold(
      // 与 `AppShell` 同形：正文延伸到贴底栏之下（`app_router.dart` 的
      // `extendBody: true`），弹层若挂在分支导航器里就会被栏盖住。
      extendBody: true,
      body: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          builder: (context) => Center(
            child: TextButton(
              key: const Key('open-manual-sheet'),
              onPressed: openSheet,
              child: const Text('打开'),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.black12,
        height: 80,
        child: Row(
          children: [
            Expanded(
              child: TextButton(
                key: const Key('nav-center'),
                onPressed: onNavTap,
                child: const Text('导航'),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  testWidgets('底栏在场时，保存按钮仍可点击（不被导航条盖住）', (tester) async {
    double? savedKcal;
    var navTaps = 0;

    await tester.pumpWidget(
      host(
        onNavTap: () => navTaps++,
        openSheet: () async {
          final context = tester.element(
            find.byKey(const Key('open-manual-sheet')),
          );
          await ManualNutritionSheet.show(
            context,
            dish: dish(),
            onSubmit: (kcal, protein, carbs, fat) async {
              savedKcal = kcal;
              return null; // null = 成功关窗
            },
          );
        },
      ),
    );

    await tester.tap(find.byKey(const Key('open-manual-sheet')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('manual-nutrition-sheet')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('manual-nutrition-kcal')),
      '180',
    );
    await tester.enterText(
      find.byKey(const Key('manual-nutrition-protein')),
      '7',
    );
    await tester.enterText(
      find.byKey(const Key('manual-nutrition-carbs')),
      '20',
    );
    await tester.enterText(find.byKey(const Key('manual-nutrition-fat')), '5');
    await tester.pump();

    await tester.tap(find.byKey(const Key('manual-nutrition-save')));
    await tester.pumpAndSettle();

    expect(savedKcal, 180, reason: '保存必须真的点到（历史上它落在导航条下面，点击被导航吃掉）');
    expect(navTaps, 0, reason: '点击不得穿透到底部导航');
    expect(find.byKey(const Key('manual-nutrition-sheet')), findsNothing);
  });

  testWidgets('四值都带单位，并有「每 100g / 不会被 AI 覆盖」的说明', (tester) async {
    await tester.pumpWidget(
      host(
        onNavTap: () {},
        openSheet: () async {
          final context = tester.element(
            find.byKey(const Key('open-manual-sheet')),
          );
          await ManualNutritionSheet.show(
            context,
            dish: dish(),
            onSubmit: (kcal, protein, carbs, fat) async => null,
          );
        },
      ),
    );
    await tester.tap(find.byKey(const Key('open-manual-sheet')));
    await tester.pumpAndSettle();

    // 2026-10-23 用户：「手动营养四值没有单位和说明」——四个字段的
    // 单位必须各自写出来，不能只靠标题里的「每 100g」。
    expect(find.text('热量 kcal'), findsOneWidget);
    expect(find.text('蛋白质 g'), findsOneWidget);
    expect(find.text('碳水 g'), findsOneWidget);
    expect(find.text('脂肪 g'), findsOneWidget);
    expect(find.byKey(const Key('manual-nutrition-hint')), findsOneWidget);
    expect(
      find.textContaining('每 100 克'),
      findsWidgets,
      reason: '口径（每 100 克）必须在弹层里写清楚',
    );
  });

  testWidgets('非法数字留在弹层内报错，不落库', (tester) async {
    var saves = 0;
    await tester.pumpWidget(
      host(
        onNavTap: () {},
        openSheet: () async {
          final context = tester.element(
            find.byKey(const Key('open-manual-sheet')),
          );
          await ManualNutritionSheet.show(
            context,
            dish: dish(),
            onSubmit: (kcal, protein, carbs, fat) async {
              saves++;
              return null;
            },
          );
        },
      ),
    );
    await tester.tap(find.byKey(const Key('open-manual-sheet')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('manual-nutrition-kcal')), '');
    await tester.tap(find.byKey(const Key('manual-nutrition-save')));
    await tester.pumpAndSettle();

    expect(saves, 0);
    expect(find.byKey(const Key('manual-nutrition-error')), findsOneWidget);
    expect(find.byKey(const Key('manual-nutrition-sheet')), findsOneWidget);
  });
}
