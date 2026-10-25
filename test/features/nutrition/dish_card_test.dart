import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/lf_badge.dart';
import 'package:localfit_ai/app/design/widgets/lf_progress_bar.dart';
import 'package:localfit_ai/features/nutrition/domain/dish_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/dish_card.dart';

/// 菜品卡（docs/21 §5.3、裁决 10 / 13）：**有数据才渲染**是这张卡的核心
/// 契约——不能凭菜名猜配料，也不能把没有的微量营养素画成 0。
void main() {
  final created = DateTime.utc(2026, 9, 28);

  // 菜品卡在列表里拿的是**固有高度**（≈717dp），默认 800×600 的测试面会把
  // 它压到 600 而溢出。这里给足高度，让断言面对的是卡片自身的布局，
  // 而不是测试面太小导致的假溢出。
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(400, 1600);
    view.devicePixelRatio = 1;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  DishRecord dish({
    String name = '番茄炒蛋',
    String mealSlot = 'lunch',
    double kcal = 142,
    double proteinG = 8.4,
    double carbsG = 6.2,
    double fatG = 9.1,
    String source = 'manual',
    String? servingWindow,
    bool isHot = false,
    double? fiberG,
    double? sodiumMg,
    double? vitaminDMcg,
    String? comment,
  }) => DishRecord(
    id: 'dish-1',
    name: name,
    mealSlot: mealSlot,
    kcal: kcal,
    proteinG: proteinG,
    carbsG: carbsG,
    fatG: fatG,
    source: source,
    servingWindow: servingWindow,
    isHot: isHot,
    fiberG: fiberG,
    sodiumMg: sodiumMg,
    vitaminDMcg: vitaminDMcg,
    comment: comment,
    createdAt: created,
    updatedAt: created,
  );

  group('mealSlotLabel', () {
    test('存储值翻成中文，不把 breakfast 印到角标上', () {
      expect(DishCard.mealSlotLabel('breakfast'), '早餐');
      expect(DishCard.mealSlotLabel('lunch'), '午餐');
      expect(DishCard.mealSlotLabel('dinner'), '晚餐');
      expect(DishCard.mealSlotLabel('snack'), '加餐');
    });

    test('意外的存储值不崩，退化成原值而不是空白', () {
      expect(DishCard.mealSlotLabel('brunch'), isNotEmpty);
    });
  });

  group('dominantMacro', () {
    test('按热量贡献判定，不按克数（脂肪 9 kcal/g）', () {
      // 脂肪 5g = 45 kcal > 碳水 10g = 40 kcal，尽管碳水克数更多。
      final record = dish(proteinG: 0, carbsG: 10, fatG: 5);
      expect(DishCard.dominantMacro(record), MacroAccent.fat);
    });

    test('蛋白质与碳水并列时取蛋白质（稳定，不随列表顺序抖动）', () {
      final record = dish(proteinG: 10, carbsG: 10, fatG: 0);
      expect(DishCard.dominantMacro(record), MacroAccent.protein);
    });

    test('碳水独占时取碳水', () {
      final record = dish(proteinG: 0, carbsG: 30, fatG: 0);
      expect(DishCard.dominantMacro(record), MacroAccent.carbs);
    });
  });

  group('图片占位', () {
    testWidgets('无照片时渲染渐变 + 图标，不伪造菜品照片', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DishCard(dish: dish(), index: 0)),
        ),
      );

      expect(find.byType(Image), findsNothing, reason: '没有照片就不该出现 Image');
      expect(find.byIcon(DishCard.placeholderIcon(dish())), findsWidgets);
    });

    testWidgets('占位色系按主要宏量稳定映射：同一道菜每次同一个渐变', (tester) async {
      final carbsDish = dish(proteinG: 0, carbsG: 30, fatG: 0);
      final fatDish = dish(proteinG: 0, carbsG: 0, fatG: 20);
      final proteinDish = dish(proteinG: 30, carbsG: 0, fatG: 0);

      final gradients = <List<Color>>[];
      for (final record in [carbsDish, fatDish, proteinDish]) {
        late LinearGradient gradient;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  gradient = DishCard.placeholderGradient(context, record);
                  return DishCard(dish: record, index: 0);
                },
              ),
            ),
          ),
        );
        gradients.add(gradient.colors);
      }

      // 三种主要宏量必须是三个不同的色系，否则「按宏量映射」是空话。
      expect(gradients[0], isNot(gradients[1]));
      expect(gradients[1], isNot(gradients[2]));
      expect(gradients[0], isNot(gradients[2]));
    });

    testWidgets('同一道菜重复渲染拿到同一个渐变（不按 index 取色）', (tester) async {
      final record = dish(proteinG: 0, carbsG: 30, fatG: 0);
      final seen = <List<Color>>[];
      for (var index = 0; index < 3; index++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  seen.add(
                    DishCard.placeholderGradient(context, record).colors,
                  );
                  return DishCard(dish: record, index: index);
                },
              ),
            ),
          ),
        );
      }
      expect(seen[0], seen[1]);
      expect(seen[1], seen[2]);
    });
  });

  group('微量营养素行（裁决 10：有才渲染）', () {
    testWidgets('三项全空时一行都不渲染，不画成 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DishCard(dish: dish(), index: 0)),
        ),
      );

      expect(find.textContaining('膳食纤维'), findsNothing);
      expect(find.textContaining('钠'), findsNothing);
      expect(find.textContaining('维D'), findsNothing);
    });

    testWidgets('只渲染有数据的那几项', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DishCard(dish: dish(fiberG: 1.8, sodiumMg: 320), index: 0),
          ),
        ),
      );

      // 标签与数值在同一个 Text 里（`'$label $value'`）。
      expect(find.text('膳食纤维 1.8g'), findsOneWidget);
      expect(find.text('钠 320mg'), findsOneWidget);
      expect(find.textContaining('维D'), findsNothing, reason: '没有维D数据就不渲染这一项');
    });
  });

  group('营养师点评块', () {
    testWidgets('无点评时不渲染', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DishCard(dish: dish(), index: 0)),
        ),
      );
      expect(find.textContaining('营养师'), findsNothing);
    });

    testWidgets('有点评时渲染原文', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DishCard(dish: dish(comment: '蛋白质偏低，建议配一份鸡蛋。'), index: 0),
          ),
        ),
      );
      expect(find.text('蛋白质偏低，建议配一份鸡蛋。'), findsOneWidget);
      // docs/21 §5.3 Key 表：点评块自己的锚点。
      expect(
        find.byKey(const Key('nutrition-menu-dish-comment-0')),
        findsOneWidget,
      );
    });

    testWidgets('来源徽标用 docs/21 §5.3 的 Key（每张卡都渲染）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DishCard(dish: dish(source: 'ai_scan'), index: 2),
          ),
        ),
      );
      expect(
        find.byKey(const Key('nutrition-menu-dish-source-2')),
        findsOneWidget,
      );
    });
  });

  group('每日目标进度条', () {
    testWidgets('无目标时不画进度条（分母不存在时画任何长度都是编事实）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DishCard(dish: dish(), index: 0)),
        ),
      );
      expect(find.byType(LfProgressBar), findsNothing);
    });

    testWidgets('目标非正时同样不画', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DishCard(dish: dish(), index: 0, targetKcal: 0)),
        ),
      );
      expect(find.byType(LfProgressBar), findsNothing);
    });

    testWidgets('有目标时画进度条', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DishCard(dish: dish(kcal: 350), index: 0, targetKcal: 2000),
          ),
        ),
      );
      expect(find.byType(LfProgressBar), findsOneWidget);
    });
  });

  group('「加入」按钮', () {
    testWidgets('未接线时不渲染按钮，不给点了没反应的入口', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DishCard(dish: dish(mealSlot: 'breakfast'), index: 0),
          ),
        ),
      );
      expect(find.byKey(const Key('cta-add-meal-0')), findsNothing);
    });

    testWidgets('接线后按钮带餐次文案，点击回传该菜品', (tester) async {
      DishRecord? received;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DishCard(
              dish: dish(mealSlot: 'breakfast'),
              index: 3,
              onAddToMeal: (record) async => received = record,
            ),
          ),
        ),
      );

      expect(find.text('加入早餐'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cta-add-meal-3')));
      await tester.pumpAndSettle();
      expect(received?.id, 'dish-1');
    });
  });

  // docs/28 §4.2：三宏量小卡（圆点 + 名称 + 克数 + **该项热量贡献**）+
  // 主按钮落到卡底。两条都是「形态变了，行为判据得跟着变」的那类改动。
  group('三宏量小卡（docs/28 §4.2）', () {
    testWidgets('每项写出自己的热量贡献（4/4/9 由克数算出）', (tester) async {
      // 蛋白质 8.4g → 34 kcal；碳水 6.2g → 25 kcal；脂肪 9.1g → 82 kcal。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DishCard(dish: dish(), index: 0)),
        ),
      );

      expect(
        find.byKey(const Key('nutrition-menu-macro-row-0')),
        findsOneWidget,
      );
      expect(find.text('34 kcal'), findsOneWidget, reason: '蛋白质贡献 8.4×4');
      expect(find.text('25 kcal'), findsOneWidget, reason: '碳水贡献 6.2×4');
      expect(find.text('82 kcal'), findsOneWidget, reason: '脂肪贡献 9.1×9');
      // 克数不能被贡献值顶掉（两项都要在）。
      expect(find.text('8.4g'), findsOneWidget);
      expect(find.text('9.1g'), findsOneWidget);
    });

    testWidgets('三项等宽：三张小卡各自占满一等分', (tester) async {
      // 用克数差距悬殊的一道菜：若按内容伸缩，三块宽度必然不等。
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DishCard(
              dish: dish(proteinG: 1, carbsG: 100, fatG: 2),
              index: 0,
            ),
          ),
        ),
      );

      final row = find.byKey(const Key('nutrition-menu-macro-row-0'));
      // 每张小卡内部只有一个 FittedBox（等比缩小兜底），它的宽度就是那张卡的
      // 内容宽；三块等宽 ⇔ 三个 FittedBox 等宽。
      final tiles = find.descendant(of: row, matching: find.byType(FittedBox));
      expect(tiles, findsNWidgets(3), reason: '三宏量 = 三张小卡');
      final widths = [
        for (final element in tiles.evaluate())
          tester.getSize(find.byElementPredicate((e) => e == element)).width,
      ];
      expect(widths[0], widths[1]);
      expect(widths[1], widths[2]);
    });

    testWidgets('主按钮在卡底：位于点评块之下，不再挤在 kcal 右边', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DishCard(
              dish: dish(comment: '蛋白质偏低，建议配一份鸡蛋。'),
              index: 0,
              onAddToMeal: (_) async {},
            ),
          ),
        ),
      );

      final button = tester.getRect(find.byKey(const Key('cta-add-meal-0')));
      final comment = tester.getRect(
        find.byKey(const Key('nutrition-menu-dish-comment-0')),
      );
      final kcal = tester.getRect(find.textContaining('kcal').first);
      expect(button.top, greaterThan(comment.top), reason: '主按钮必须在点评块之下（卡底）');
      expect(button.top, greaterThan(kcal.bottom), reason: '主按钮不再与大号 kcal 同排');
    });
  });

  group('进度条说明随分母走（docs/28 §4.2 / §4.1）', () {
    testWidgets('默认写「每日目标进度」', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DishCard(dish: dish(), index: 0, targetKcal: 2000),
          ),
        ),
      );
      expect(find.text('每日目标进度'), findsOneWidget);
    });

    testWidgets('分母是本餐预算时写本餐预算，不说成全天目标', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DishCard(
              dish: dish(),
              index: 0,
              targetKcal: 640,
              progressLabel: '本餐预算',
            ),
          ),
        ),
      );
      expect(find.text('本餐预算'), findsOneWidget);
      expect(find.text('每日目标进度'), findsNothing);
      // 进度仍是「该菜 kcal ÷ 分母」：142 / 640 = 22%。
      expect(find.text('22%'), findsOneWidget);
    });
  });

  testWidgets('卡片 Key 用列表序号，可按序号定位', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DishCard(dish: dish(), index: 5)),
      ),
    );
    expect(find.byKey(const Key('nutrition-menu-dish-card-5')), findsOneWidget);
  });

  testWidgets('热门角标只在 isHot 时出现', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DishCard(dish: dish(), index: 0)),
      ),
    );
    expect(find.textContaining('热门'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DishCard(dish: dish(isHot: true), index: 0)),
      ),
    );
    expect(find.textContaining('热门'), findsWidgets);
    // docs/21 §5.3 Key 表：热门角标自己的锚点。
    final hot = find.byKey(const Key('nutrition-menu-dish-hot-0'));
    expect(hot, findsOneWidget);
    // 档位也是契约（§3.9）：原手写胶囊是 `primary@15%`，收敛到 honey 档
    // ——只断言「文字/Key 在不在」抓不住档位被换掉。
    expect(tester.widget<LfBadge>(hot).variant, LfBadgeVariant.honey);
  });

  testWidgets('供应时段角标只在有 servingWindow 时出现', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DishCard(dish: dish(), index: 0)),
      ),
    );
    expect(find.textContaining('11:00'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DishCard(dish: dish(servingWindow: '11:00-13:30'), index: 0),
        ),
      ),
    );
    expect(find.textContaining('11:00-13:30'), findsWidgets);
  });
}
