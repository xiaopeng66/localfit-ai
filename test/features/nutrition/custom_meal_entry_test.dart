import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/custom_meal_sheet.dart';
import 'package:localfit_ai/features/nutrition/presentation/meal_entry_chooser_sheet.dart';

/// **「自定义一顿」**（2026-10-26 用户：「营养摄入自己不能改」）。
///
/// 复核发现的缺口：记餐只有「食物库 × 克数」两条路（另加 AI 识餐）。库里没有
/// 的外卖/家常菜/聚餐，只能先建食物或拍照让 AI 估——**没有「我就吃了这么多」
/// 的入口**，于是「营养摄入」看上去没法自己改。
///
/// 数据层不需要迁移：`MealItems` 本来就允许 `foodId = null` +
/// `sourceType = 'manual'` + 四个营养快照列，`MealDraft` 也接受任意营养值。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late MealRepository meals;

  const localDate = '2026-10-26';
  final now = DateTime(2026, 10, 26, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    meals = MealRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now.toUtc()),
    );
  });

  tearDown(() => database.close());

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('记餐入口有第三项「自定义一顿」（另两项不动）', (tester) async {
    await tester.pumpWidget(host(const MealRecordEntryChooser()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('meal-entry-by-food')), findsOneWidget);
    expect(find.byKey(const Key('meal-entry-by-dish')), findsOneWidget);
    expect(
      find.byKey(const Key('meal-entry-by-custom')),
      findsOneWidget,
      reason: '库里没有的东西也要能记：直接填热量与宏量',
    );
    expect(find.textContaining('自定义'), findsWidgets);
  });

  testWidgets('自定义一顿：填热量与宏量 → 落库一条 manual 项（foodId 为空）', (tester) async {
    MealDraft? captured;
    await tester.pumpWidget(
      host(
        CustomMealSheet(
          localDate: localDate,
          initialSlot: MealSlot.breakfast,
          onSubmit: (draft) async {
            captured = draft;
            await meals.create(draft);
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('custom-meal-name')), '楼下炒饭');
    await tester.enterText(find.byKey(const Key('custom-meal-kcal')), '650');
    await tester.enterText(find.byKey(const Key('custom-meal-protein')), '30');
    await tester.enterText(find.byKey(const Key('custom-meal-carbs')), '70');
    await tester.enterText(find.byKey(const Key('custom-meal-fat')), '20');
    expect(find.text('g'), findsNWidgets(3), reason: '输入值后宏量单位仍须可见');
    await tester.tap(find.byKey(const Key('custom-meal-save')));
    await tester.pumpAndSettle();

    expect(captured, isNotNull, reason: '保存要真的提交');
    expect(captured!.slot, MealSlot.breakfast, reason: '预选餐次要用上');
    expect(captured!.items, hasLength(1));
    final item = captured!.items.single;
    expect(item.foodName, '楼下炒饭');
    expect(item.foodId, isNull, reason: '自定义项不挂食物库 id');
    expect(item.sourceType, 'manual');
    expect(item.nutrition.kcal, 650);
    expect(item.nutrition.proteinGrams, 30);
    expect(item.nutrition.carbsGrams, 70);
    expect(item.nutrition.fatGrams, 20);

    // 落库同样能读回来（走真实仓储）。
    final rows = await database.select(database.mealItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.foodId, isNull);
    expect(rows.single.kcalSnapshot, 650);
    expect(rows.single.sourceType, 'manual');
  });

  testWidgets('R-2：三宏量标签不折行、三个输入框等高（320dp × 2.0×）', (tester) async {
    tester.view.physicalSize = const Size(320 * 2, 900 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 900),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: CustomMealSheet(
                  localDate: localDate,
                  onSubmit: (draft) async => null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 标签只留三个字（括号注退役——320dp 三列 ~85dp 放不下「蛋白质（g，可选）」）。
    expect(find.text('蛋白质'), findsOneWidget);
    expect(find.text('碳水'), findsOneWidget);
    expect(find.text('脂肪'), findsOneWidget);
    expect(
      find.text('蛋白质（g，可选）'),
      findsNothing,
      reason:
          '「（g，可选）」括号注退役：折行是三框不等高的根因'
          '（「名称（可选）」是整行字段，不受三列宽度约束，保留）',
    );
    // 三个输入框顶边/底边对齐（差 ≤0.5dp）。
    final tops = [
      for (final key in const [
        'custom-meal-protein',
        'custom-meal-carbs',
        'custom-meal-fat',
      ])
        tester.getTopLeft(find.byKey(Key(key))).dy,
    ];
    final bottoms = [
      for (final key in const [
        'custom-meal-protein',
        'custom-meal-carbs',
        'custom-meal-fat',
      ])
        tester.getBottomRight(find.byKey(Key(key))).dy,
    ];
    // 最大差 = max − min（相邻差 reduce 会算成 |差 − 下一项|，错）。
    double spread(List<double> values) {
      final lo = values.reduce((a, b) => a < b ? a : b);
      final hi = values.reduce((a, b) => a > b ? a : b);
      return hi - lo;
    }

    expect(
      spread(tops) <= 0.5,
      isTrue,
      reason: '顶边对齐（实际 tops=$tops bottoms=$bottoms）',
    );
    expect(
      spread(bottoms) <= 0.5,
      isTrue,
      reason: '底边对齐（实际 tops=$tops bottoms=$bottoms）',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('热量留空：如实提示，不落库', (tester) async {
    var submits = 0;
    await tester.pumpWidget(
      host(
        CustomMealSheet(
          localDate: localDate,
          onSubmit: (draft) async {
            submits++;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('custom-meal-name')), '炒饭');
    await tester.tap(find.byKey(const Key('custom-meal-save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('热量'), findsWidgets, reason: '要说清缺的是热量');
    expect(submits, 0, reason: '没填热量不该提交');
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'custom-${_value++}';
}
