import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/nutrition/data/food_csv_importer.dart';
import 'package:localfit_ai/features/nutrition/domain/food_category.dart';
import 'package:localfit_ai/features/nutrition/domain/food_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/food_import_preview_sheet.dart';

/// 导入预览弹层（docs/31 S5 需求 57 / 稿 ④）：三本账 + 重复样例 + 两个决定。
void main() {
  /// 打开弹层；返回的闭包读出弹层的返回值（null = 取消）。
  Future<FoodCsvImportPolicy? Function()> openSheet(
    WidgetTester tester,
    FoodCsvImportPreview preview,
  ) async {
    tester.view.physicalSize = const Size(900, 1700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    FoodCsvImportPolicy? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showFoodImportPreviewSheet(context, preview);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('同排等高：三本账账目块与两条动作钮（320dp × 2.0× 不齐高）', (tester) async {
    // Round7 阶段 3 · 3-4 渲染审看抓到：320dp + 2.0× 下，三本账里「可导入」
    // 只有一行说明，另两块是两行 ⇒ 三个块高低不齐；动作行的「跳过重复，导入
    // N 条」折三行、「全部导入」折两行 ⇒ 两钮也不齐。修法：两处 Row 走
    // `IntrinsicHeight` + `CrossAxisAlignment.stretch`（等高不裁字、不改文案）。
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFoodImportPreviewSheet(
                context,
                FoodCsvImportPreview(
                  newFoods: [
                    for (var i = 0; i < 3; i++)
                      NewFood(
                        name: '新食材$i',
                        kcalPer100g: 100,
                        proteinPer100g: 1,
                        carbsPer100g: 2,
                        fatPer100g: 3,
                      ),
                  ],
                  duplicates: [
                    const FoodCsvDuplicate(
                      food: NewFood(
                        name: '鸡蛋',
                        kcalPer100g: 144,
                        proteinPer100g: 13.3,
                        carbsPer100g: 2.8,
                        fatPer100g: 8.8,
                      ),
                      existingIsUserCreated: false,
                    ),
                  ],
                  errors: const [],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final tiles = [
      tester.getRect(find.byKey(const Key('food-import-count-new'))),
      tester.getRect(find.byKey(const Key('food-import-count-dup'))),
      tester.getRect(find.byKey(const Key('food-import-count-error'))),
    ];
    for (final tile in tiles) {
      expect(tile.height, closeTo(tiles.first.height, 0.5), reason: '三本账等高');
    }

    final skip = tester.getRect(find.byKey(const Key('food-import-skip-dup')));
    final all = tester.getRect(find.byKey(const Key('food-import-import-all')));
    expect(
      all.height,
      closeTo(skip.height, 0.5),
      reason: '同排两条动作钮等高（2.0× 下一条折三行、一条折两行）',
    );
  });

  testWidgets('三本账 + 重复样例（内置/自建徽标）+ 错误样例如实展示', (tester) async {
    final readResult = await openSheet(
      tester,
      FoodCsvImportPreview(
        newFoods: [
          const NewFood(
            name: '新食材',
            kcalPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 2,
            fatPer100g: 3,
          ),
        ],
        duplicates: [
          const FoodCsvDuplicate(
            food: NewFood(
              name: '鸡蛋',
              kcalPer100g: 144,
              proteinPer100g: 13.3,
              carbsPer100g: 2.8,
              fatPer100g: 8.8,
            ),
            existingIsUserCreated: false,
          ),
          const FoodCsvDuplicate(
            food: NewFood(
              name: '无糖酸奶',
              brand: '某乳业',
              kcalPer100g: 62,
              proteinPer100g: 3.2,
              carbsPer100g: 4.8,
              fatPer100g: 3.1,
            ),
            existingIsUserCreated: true,
          ),
        ],
        errors: const [
          FoodCsvRowError(row: 18, message: '第 18 行「蛋白质 abc g」不是数字。'),
          FoodCsvRowError(row: 19, message: '第 19 行营养数值超出合理范围。'),
        ],
      ),
    );

    // 三本账：可导入 / 与库内重复 / 格式错误跳过。计数走 key 下的后代查找——
    // 重复账与错误账都是 2，裸 find.text('2') 会命中两个。
    Finder statValue(String key, String value) =>
        find.descendant(of: find.byKey(Key(key)), matching: find.text(value));
    expect(statValue('food-import-count-new', '1'), findsOneWidget);
    expect(statValue('food-import-count-dup', '2'), findsOneWidget);
    expect(statValue('food-import-count-error', '2'), findsOneWidget);
    expect(find.text('可导入'), findsOneWidget);
    expect(find.text('与库内重复'), findsOneWidget);
    expect(find.text('格式错误跳过'), findsOneWidget);
    // 重复样例带库内身份徽标。
    expect(find.byKey(const Key('food-import-dup-samples')), findsOneWidget);
    expect(find.text('鸡蛋（无品牌）'), findsOneWidget);
    expect(find.text('内置'), findsOneWidget);
    expect(find.text('自建'), findsOneWidget);
    // 错误只给首条样例 + 总数。
    expect(
      tester
          .widget<Text>(find.byKey(const Key('food-import-error-sample')))
          .data,
      '第 18 行「蛋白质 abc g」不是数字。',
    );
    expect(find.textContaining('共 2 行格式错误'), findsOneWidget);
    // 两个决定按钮 + 取消都在。
    expect(find.textContaining('跳过重复，导入 1 条'), findsOneWidget);
    expect(find.byKey(const Key('food-import-skip-dup')), findsOneWidget);
    expect(find.byKey(const Key('food-import-import-all')), findsOneWidget);
    expect(find.byKey(const Key('food-import-cancel')), findsOneWidget);

    // 全部导入 = importAll。
    await tester.tap(find.byKey(const Key('food-import-import-all')));
    await tester.pumpAndSettle();
    expect(readResult(), FoodCsvImportPolicy.importAll);
  });

  testWidgets('「跳过重复，导入 N 条」返回 skipDuplicates', (tester) async {
    final readResult = await openSheet(
      tester,
      FoodCsvImportPreview(
        newFoods: [
          const NewFood(
            name: '新食材',
            kcalPer100g: 100,
            proteinPer100g: 1,
            carbsPer100g: 2,
            fatPer100g: 3,
          ),
        ],
        duplicates: const [],
        errors: const [],
      ),
    );
    await tester.tap(find.byKey(const Key('food-import-skip-dup')));
    await tester.pumpAndSettle();
    expect(readResult(), FoodCsvImportPolicy.skipDuplicates);
  });

  testWidgets('没有新增候选时不出「跳过重复」（否则就是一个 0 条的死按钮）', (tester) async {
    await openSheet(
      tester,
      FoodCsvImportPreview(
        newFoods: const [],
        duplicates: [
          const FoodCsvDuplicate(
            food: NewFood(
              name: '鸡蛋',
              kcalPer100g: 144,
              proteinPer100g: 13.3,
              carbsPer100g: 2.8,
              fatPer100g: 8.8,
              category: FoodCategory.protein,
            ),
            existingIsUserCreated: false,
          ),
        ],
        errors: const [],
      ),
    );
    expect(find.byKey(const Key('food-import-skip-dup')), findsNothing);
    expect(find.byKey(const Key('food-import-import-all')), findsOneWidget);
  });
}
