import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/features/nutrition/application/food_library_controller.dart';
import 'package:localfit_ai/features/nutrition/domain/food_detail.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_detail_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/new_food_dialog.dart';

import 'support/round7_render.dart';

/// Round7 阶段 3 · 3-2d 的渲染矩阵（详情弹层与新建/编辑表单）。
///
/// 12 帧：详情 4（浅/深 360-1.0、浅 320-2.0、深 430-1.5）+ 详情行动行 2
/// （自建条目 浅/深 360-1.0）+ 无热量档 1 + 长名长牌 320-2.0 深 1 + 表单 3
/// （新建 浅/深 360-1.0、浅 320-2.0）+ 编辑回显 1。
///
/// 弹层走**真 chrome**（`FoodDetailSheet.show` / `NewFoodDialog.show` 挂进
/// `MaterialApp` 自己的 navigator）：`RepaintBoundary` 包在 `MaterialApp`
/// **外面**（阶段 1 组件矩阵的同一手法），模态弹层才在边界之内。
/// 每帧带哨兵断言（关键件在、无溢出异常）。
void main() {
  const builtIn = FoodLibraryItem(
    id: 'off:1001',
    name: '蒸米饭',
    source: 'catalog',
    state: 'verified',
    canJoinPlan: true,
    brand: '金龙鱼',
    category: 'staple',
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbsPer100g: 25.9,
    fatPer100g: 0.3,
  );

  const userCreated = FoodLibraryItem(
    id: 'user:1',
    name: '自制鸡肉沙拉',
    source: 'main',
    state: 'user_created',
    canJoinPlan: true,
    isUserCreated: true,
    brand: '自家',
    category: 'protein',
    kcalPer100g: 120,
    proteinPer100g: 12,
    carbsPer100g: 6,
    fatPer100g: 5,
  );

  const noKcal = FoodLibraryItem(
    id: 'off:2002',
    name: '某品牌风味饮',
    source: 'catalog',
    state: 'incomplete',
    canJoinPlan: false,
    brand: '某某饮料（华东）有限公司',
    category: 'beverage',
    kcalPer100g: null,
    proteinPer100g: null,
    carbsPer100g: null,
    fatPer100g: null,
  );

  FoodDetail detailOf(FoodLibraryItem item) => FoodDetail(
    foodId: item.id,
    name: item.name,
    state: item.state,
    source: item.source == 'catalog' ? 'openfoodfacts' : 'user',
    licenseStatus: 'allowed',
    isUserCreated: item.isUserCreated,
    // 裁决 ①（2026-10-15）：详情与卡同源 ⇒ 自建条目不再显示「营养不完整」，
    // 自建帧因此会变（本轮重拍并实看）。
    canJoinPlan: item.canJoinPlan,
    kcalPer100g: item.kcalPer100g ?? 0,
    proteinPer100g: item.proteinPer100g ?? 0,
    carbsPer100g: item.carbsPer100g ?? 0,
    fatPer100g: item.fatPer100g ?? 0,
  );

  final editing = FoodRecord(
    id: 'user:1',
    name: '自制鸡肉沙拉',
    brand: '自家',
    kcalPer100g: 120,
    proteinPer100g: 12,
    carbsPer100g: 6,
    fatPer100g: 5,
    isUserCreated: true,
    category: FoodCategory.protein,
  );

  Future<void> pumpHost(
    WidgetTester tester, {
    required bool dark,
    required double width,
    required double height,
    required double scale,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: round7CaptureTheme(dark ? AppTheme.dark() : AppTheme.light()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Center(
                    child: LfTextButton(
                      key: const Key('open-detail'),
                      label: '打开详情',
                      onPressed: () => FoodDetailSheet.show(
                        context,
                        item: builtIn,
                        load: () async => detailOf(builtIn),
                      ),
                    ),
                  ),
                  Center(
                    child: LfTextButton(
                      key: const Key('open-detail-user'),
                      label: '打开自建详情',
                      onPressed: () => FoodDetailSheet.show(
                        context,
                        item: userCreated,
                        load: () async => detailOf(userCreated),
                        onEdit: () async {},
                        onDelete: () async {},
                      ),
                    ),
                  ),
                  Center(
                    child: LfTextButton(
                      key: const Key('open-detail-nokcal'),
                      label: '打开无热量详情',
                      onPressed: () => FoodDetailSheet.show(
                        context,
                        item: noKcal,
                        load: () async => detailOf(noKcal),
                      ),
                    ),
                  ),
                  Center(
                    child: LfTextButton(
                      key: const Key('open-form-new'),
                      label: '新建食物',
                      onPressed: () => NewFoodDialog.show(
                        context,
                        onSubmit: (_) async => null,
                      ),
                    ),
                  ),
                  Center(
                    child: LfTextButton(
                      key: const Key('open-form-edit'),
                      label: '编辑食物',
                      onPressed: () => NewFoodDialog.show(
                        context,
                        editing: editing,
                        onSubmit: (_) async => null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> shot(
    WidgetTester tester,
    String name, {
    required Key opener,
    required Key sentinel,
  }) async {
    await tester.tap(find.byKey(opener));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '$name：弹层布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
    // 换下一档前把弹层丢掉（重挂整棵树比逐层 pop 稳）。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('详情弹层的渲染矩阵（浅深 / 窄屏大字 / 行动行 / 无热量）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    // 浅 360-1.0（内置条目：无行动行）
    await pumpHost(tester, dark: false, width: 360, height: 800, scale: 1);
    await shot(
      tester,
      'detail-light-360-1.0',
      opener: const Key('open-detail'),
      sentinel: const Key('food-detail-panel'),
    );

    // 深 360-1.0
    await pumpHost(tester, dark: true, width: 360, height: 800, scale: 1);
    await shot(
      tester,
      'detail-dark-360-1.0',
      opener: const Key('open-detail'),
      sentinel: const Key('food-detail-panel'),
    );

    // 浅 320-2.0（窄屏大字：meta 折行、面板宏量列最窄）
    await pumpHost(tester, dark: false, width: 320, height: 800, scale: 2);
    await shot(
      tester,
      'detail-light-320-2.0',
      opener: const Key('open-detail'),
      sentinel: const Key('food-detail-panel'),
    );

    // 深 430-1.5
    await pumpHost(tester, dark: true, width: 430, height: 900, scale: 1.5);
    await shot(
      tester,
      'detail-dark-430-1.5',
      opener: const Key('open-detail'),
      sentinel: const Key('food-detail-panel'),
    );

    // 自建条目：行动行（浅 / 深）
    await pumpHost(tester, dark: false, width: 360, height: 800, scale: 1);
    await shot(
      tester,
      'detail-actions-light-360-1.0',
      opener: const Key('open-detail-user'),
      sentinel: const Key('food-detail-actions'),
    );
    await pumpHost(tester, dark: true, width: 360, height: 800, scale: 1);
    await shot(
      tester,
      'detail-actions-dark-360-1.0',
      opener: const Key('open-detail-user'),
      sentinel: const Key('food-detail-actions'),
    );

    // 无热量档：环 `—` + 居中「无热量数据」
    await pumpHost(tester, dark: false, width: 360, height: 800, scale: 1);
    await shot(
      tester,
      'detail-nokcal-light-360-1.0',
      opener: const Key('open-detail-nokcal'),
      sentinel: const Key('food-detail-ring-label'),
    );

    // 长名 + 长品牌在 320-2.0 深色下的折行
    await pumpHost(tester, dark: true, width: 320, height: 800, scale: 2);
    await shot(
      tester,
      'detail-nokcal-dark-320-2.0',
      opener: const Key('open-detail-nokcal'),
      sentinel: const Key('food-detail-meta'),
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });

  testWidgets('新建/编辑表单的渲染矩阵（2×2 网格 + 注）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    await pumpHost(tester, dark: false, width: 360, height: 900, scale: 1);
    await shot(
      tester,
      'form-light-360-1.0',
      opener: const Key('open-form-new'),
      sentinel: const Key('new-food-note'),
    );

    await pumpHost(tester, dark: true, width: 360, height: 900, scale: 1);
    await shot(
      tester,
      'form-dark-360-1.0',
      opener: const Key('open-form-new'),
      sentinel: const Key('new-food-note'),
    );

    // 窄屏大字：两列标签折行、字段不错位
    await pumpHost(tester, dark: false, width: 320, height: 1200, scale: 2);
    await shot(
      tester,
      'form-light-320-2.0',
      opener: const Key('open-form-new'),
      sentinel: const Key('new-food-note'),
    );

    // 编辑回显（种类 + 四项营养）
    await pumpHost(tester, dark: false, width: 360, height: 900, scale: 1);
    await shot(
      tester,
      'form-edit-light-360-1.0',
      opener: const Key('open-form-edit'),
      sentinel: const Key('new-food-note'),
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}
