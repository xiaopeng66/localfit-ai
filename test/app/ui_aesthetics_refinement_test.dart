import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/application/build_calorie_trend.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_record_energy_card.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/nutrition_trend_card.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';
import 'package:drift/drift.dart' show Value;

/// WCAG 2.1 相对对比度：(L1 + 0.05) / (L2 + 0.05)，L 为相对亮度。
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// 界面美观与整齐性回归（docs/27）：等高瓦片、值+小单位、hero 墨色、
/// 空态紧凑。用户点名的「健康数据中间卡与两边不一样」「成就高低不齐」
/// 在这里钉死。
void main() {
  void viewport(WidgetTester tester, Size size, {double scale = 1}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget app(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

  List<Rect> textBoxes(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final length = paragraph.text.toPlainText().length;
    return paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: length),
        )
        .map((box) => box.toRect())
        .toList();
  }

  Future<void> scrollTo(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('健康数据三卡同宽竖排，BMR 值单行且单位字号更小（docs/29 §P2 / D10）', (tester) async {
    viewport(tester, const Size(500, 900));
    final now = DateTime.utc(2026, 9, 12, 10);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile',
            birthYear: const Value(1995),
            biologicalSex: const Value('female'),
            heightCm: const Value(165),
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.measurements)
        .insert(
          MeasurementsCompanion.insert(
            id: 'weight',
            profileId: 'profile',
            localDate: '2026-09-12',
            weightKg: 62,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await tester.pumpWidget(
      app(
        SettingsPage(
          profileOverviewLoader: LoadProfileOverview(
            database: database,
            clock: FixedAppClock(now),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, const Key('settings-health-metrics'));

    // docs/29 §P2 起健康数据不再是等高瓦片，而是**图形卡**（裁决 D10：
    // BMI 分档刻度尺 / BMR 区间指示）。两种图形的语义不同，高度本来就不该被
    // 拉平，故把「瓦片等高」换成语义等价的整齐性约束：两张卡同宽、按固定
    // 顺序竖排、互不重叠（卡仍由同一个 keyed Column 承载）。
    // 2026-10-16：用户删掉了第三张（饮水进度环）——约束随之落到两张卡上。
    Rect cardRect(Key key) => tester.getRect(find.byKey(key));
    final bmiRect = cardRect(const Key('settings-health-bmi'));
    final bmrRect = cardRect(const Key('settings-health-bmr'));
    expect(
      (bmiRect.width - bmrRect.width).abs(),
      lessThan(0.5),
      reason: '两张图形卡必须同宽（同一列内拉伸）：${bmiRect.width} / ${bmrRect.width}',
    );
    expect(
      bmiRect.bottom,
      lessThanOrEqualTo(bmrRect.top + 0.5),
      reason: 'BMI 卡必须在 BMR 卡上方且不重叠',
    );

    // BMR：值是纯数字（设计稿形态），单位是独立的小字，两者各占一行不折行。
    expect(textBoxes(tester, find.text('1,335')), hasLength(1));
    expect(textBoxes(tester, find.text('kcal/天')), hasLength(1));
    final valueStyle = tester.widget<Text>(find.text('1,335')).style!;
    final unitStyle = tester.widget<Text>(find.text('kcal/天')).style!;
    expect(
      unitStyle.fontSize!,
      lessThan(valueStyle.fontSize!),
      reason: '单位必须比数字小一号（数字强调、单位弱化）',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('成就四格等高（docs/27 R1：CSS grid 等高语义）', (tester) async {
    viewport(tester, const Size(320, 900), scale: 2);
    await tester.pumpWidget(app(SettingsPage()));
    await tester.pumpAndSettle();
    await scrollTo(tester, const Key('settings-achievements'));
    final heights = [
      for (var i = 1; i <= 4; i++)
        tester.getRect(find.byKey(Key('settings-achievement-$i'))).height,
    ];
    expect(
      heights.reduce((a, b) => a > b ? a : b) -
          heights.reduce((a, b) => a < b ? a : b),
      lessThan(0.5),
      reason: '成就四格必须等高：$heights',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('浅色记录卡文字用墨色而不是白色（docs/27 R2 / docs/30 D4：配色不伤可读性）', (
    tester,
  ) async {
    viewport(tester, const Size(390, 800));
    await tester.pumpWidget(
      app(
        NutritionRecordEnergyCard(
          consumed: const NutritionValues(
            kcal: 0,
            proteinGrams: 0,
            carbsGrams: 0,
            fatGrams: 0,
          ),
          target: const DailyNutritionTarget(
            calorieMinKcal: 1500,
            calorieMaxKcal: 1748,
            proteinMinGrams: 50,
            proteinMaxGrams: 62,
            carbsMinGrams: 180,
            carbsMaxGrams: 205,
            fatMinGrams: 40,
            fatMaxGrams: 52,
          ),
          selectedDate: DateTime(2026, 9, 12),
          now: DateTime(2026, 9, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 契约变过两次、意图没变：docs/30 D4 把这张卡从 mint 渐变 hero 换成白
    // [DesignCard]，阶段 2B D10 又把它换成两页共享的热量卡（仍是白卡）——
    // 「墨色而不是白色」的落点一直在**卡片自己的** `cardForeground`
    // （docs/21 §3.1：卡内文字用卡前景色）。断言因此不是「换成另一个常量」，
    // 而是**对着卡片真实底色算对比度**——谁把文字改回白色（或把底改成深色
    // 而文字不改），这里立刻 RED。
    final cardColor = tester
        .widget<Material>(
          find
              .descendant(
                of: find.byKey(const Key('nutrition-record-energy')),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;
    expect(
      cardColor,
      LfSemanticColors.light.card,
      reason: '记录卡必须是白卡（docs/30 D4）；透明/渐变底会让下面的对比度断言失去意义',
    );
    expect(cardColor.a, 1.0, reason: '底必须不透明：对比度是按合成后颜色算的');

    // 标题取卡头（今日页/记录页共用同一件，标题按选中日选词）、数值取环心
    // 的已摄入段（`find.text('0')` 会撞上宏量行的 0，锚点由 Key 指定）。
    final titleColor = tester.widget<Text>(find.text('今日营养')).style!.color!;
    final valueColor = tester
        .widget<Text>(find.byKey(const Key('nutrition-record-energy-consumed')))
        .style!
        .color!;
    final labelColor = tester.widget<Text>(find.text('已摄入 kcal')).style!.color!;
    expect(titleColor, LfSemanticColors.light.cardForeground);
    expect(valueColor, LfSemanticColors.light.cardForeground);
    expect(labelColor, LfSemanticColors.light.mutedForeground);

    // 正文级文字按 WCAG AA 要求 ≥ 4.5:1。卡前景色对白底实测 16.6:1。
    expect(
      _contrast(titleColor, cardColor),
      greaterThanOrEqualTo(4.5),
      reason: '标题是正文级文字，对卡片底色必须 ≥ 4.5:1',
    );
    expect(
      _contrast(valueColor, cardColor),
      greaterThanOrEqualTo(4.5),
      reason: '「已摄入」数字是这张卡的主信息，对卡片底色必须 ≥ 4.5:1',
    );
    // 标签是 12px 次级说明，mutedForeground 对白底实测 4.30:1——低于 4.5 但
    // 高于 4.0，且它与主信息是**主次**关系（不承担「唯一通道」）。这里钉 4.0
    // 是为了拦住「把它再调淡」的改动，而不是宣称它达标 AA。
    expect(
      _contrast(labelColor, cardColor),
      greaterThan(4.0),
      reason: '标签是次级说明：可以略低于 AA，但不能淡到 4.0:1 以下',
    );
  });

  testWidgets('趋势卡：空态 80dp 且无轴/日号/hint；有数据图区 145 / 柱区 101（A 实测）', (
    tester,
  ) async {
    CalorieTrendBars bars(List<double> kcals) => buildCalorieTrendBars(
      records: [
        for (var i = 0; i < kcals.length; i++)
          DailyIntakeRecord(
            localDate: '2026-09-${(7 + i).toString().padLeft(2, '0')}',
            kcal: kcals[i],
            proteinGrams: 0,
            carbsGrams: 0,
            fatGrams: 0,
          ),
      ],
      endDate: DateTime(2026, 9, 13),
    );

    await tester.pumpWidget(app(NutritionTrendCard(bars: bars(const []))));
    await tester.pumpAndSettle();
    // A `.chart-empty{min-height:80}`（2B 步骤 4 起；旧件 72 是上一版视觉）。
    expect(
      tester
          .getSize(find.byKey(const Key('nutrition-record-trend-empty')))
          .height,
      80,
    );
    // 横轴是日期数字（docs/27 §R8：设计稿 17/18/19…），空态不渲染。
    expect(find.text('7'), findsNothing, reason: '空图表的坐标轴是装饰，空态不渲染');

    await tester.pumpWidget(app(NutritionTrendCard(bars: bars(const [2000]))));
    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget, reason: '横轴为日期数字');
    // A：图区 145（`padding:22 0`）里柱区 101（旧件 120 是上一版视觉）。
    expect(
      tester
          .getSize(find.byKey(const Key('nutrition-record-trend-chart-area')))
          .height,
      145,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('nutrition-record-trend-plot')))
          .height,
      101,
    );
  });
}
