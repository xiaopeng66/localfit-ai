import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/nutrition/data/food_csv_importer.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_import_preview_sheet.dart';

import 'support/round7_render.dart';

/// Round7 阶段 3 · 3-4 的渲染矩阵（食物 CSV 导入预览弹层）。
///
/// 6 帧：三本账齐全（含重复样例）浅/深 360-1.0、含格式错误浅 360-1.0、
/// 只有新条（无重复/无错误）浅 360-1.0、全是重复（新条 0）深 360-1.0、
/// 三本账齐全浅 320-2.0（长文案折行）。
///
/// A 未画 CSV 预览（docs/33 §3.6 按同主题补齐）；帧用于审看「三本账 / 重复
/// 样例与库内身份 / 两条政策 + 取消」的形态与深浅色、窄屏大字。
void main() {
  NewFood food(String name, {String? brand}) => NewFood(
    name: name,
    brand: brand,
    kcalPer100g: 116,
    proteinPer100g: 2.6,
    carbsPer100g: 25.9,
    fatPer100g: 0.3,
  );

  FoodCsvImportPreview resolve({
    required List<String> newNames,
    required List<(String, String?)> dupNames,
    required List<String> errors,
  }) => FoodCsvImportPreview(
    newFoods: [for (final name in newNames) food(name)],
    duplicates: [
      for (final (name, brand) in dupNames)
        FoodCsvDuplicate(
          food: food(name, brand: brand),
          existingIsUserCreated: name.contains('自制'),
        ),
    ],
    errors: [
      for (var i = 0; i < errors.length; i++)
        FoodCsvRowError(row: i + 2, message: errors[i]),
    ],
  );

  Future<void> pumpSheet(
    WidgetTester tester, {
    required bool dark,
    required double width,
    required double height,
    required double scale,
    required FoodCsvImportPreview preview,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
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
              builder: (context) => Center(
                child: TextButton(
                  key: const Key('open-preview'),
                  onPressed: () => showFoodImportPreviewSheet(context, preview),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-preview')));
    await tester.pumpAndSettle();
  }

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  testWidgets('CSV 导入预览的渲染矩阵（6 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    final full = resolve(
      newNames: ['蒸米饭', '鸡胸肉', '西兰花'],
      dupNames: [('米饭', '金龙鱼'), ('自制鸡肉沙拉', null), ('纯牛奶', '蒙牛')],
      errors: const [],
    );
    await pumpSheet(
      tester,
      dark: false,
      width: 360,
      height: 900,
      scale: 1,
      preview: full,
    );
    await shot(
      tester,
      'csv-full-light-360-1.0',
      const Key('food-import-dup-samples'),
    );

    await pumpSheet(
      tester,
      dark: true,
      width: 360,
      height: 900,
      scale: 1,
      preview: full,
    );
    await shot(
      tester,
      'csv-full-dark-360-1.0',
      const Key('food-import-dup-samples'),
    );

    final withErrors = resolve(
      newNames: ['蒸米饭'],
      dupNames: [('米饭', null)],
      errors: const ['第 4 行「abc」不是数字。', '第 7 行缺少「name」列。', '第 9 行热量超出范围。'],
    );
    await pumpSheet(
      tester,
      dark: false,
      width: 360,
      height: 900,
      scale: 1,
      preview: withErrors,
    );
    await shot(
      tester,
      'csv-errors-light-360-1.0',
      const Key('food-import-error-sample'),
    );

    final newOnly = resolve(
      newNames: ['蒸米饭', '鸡胸肉'],
      dupNames: const [],
      errors: const [],
    );
    await pumpSheet(
      tester,
      dark: false,
      width: 360,
      height: 900,
      scale: 1,
      preview: newOnly,
    );
    await shot(
      tester,
      'csv-new-only-light-360-1.0',
      const Key('food-import-import-all'),
    );

    final allDup = resolve(
      newNames: const [],
      dupNames: [('米饭', '金龙鱼'), ('鸡胸肉', '正大')],
      errors: const [],
    );
    await pumpSheet(
      tester,
      dark: true,
      width: 360,
      height: 900,
      scale: 1,
      preview: allDup,
    );
    await shot(
      tester,
      'csv-all-dup-dark-360-1.0',
      const Key('food-import-import-all'),
    );

    await pumpSheet(
      tester,
      dark: false,
      width: 320,
      height: 900,
      scale: 2,
      preview: full,
    );
    await shot(
      tester,
      'csv-full-light-320-2.0',
      const Key('food-import-dup-samples'),
    );

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}
