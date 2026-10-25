import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/domain/health_metric_bands.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

/// 健康数据三张图形卡（docs/29 §P2 / 裁决 D10）。
///
/// 这个包把「三格等高的统计瓦片」换成了三件**各说一件事**的图形：BMI 分档
/// 刻度尺、BMR 区间指示、饮水进度环。图形比数字更容易说谎，所以这里钉三条：
///
/// 1. **分档边界**只认 `health_metric_bands.dart` 的口径（18.5 / 24.0 / 28.0
///    三个跳变点，逐个测到 0.1 的差）；
/// 2. **缺数据不给假档位**：空库时没有档位文字、没有指示器/标记点、没有目标
///    区间、没有百分比——图能不画就不画，只留诚实的「—」；
/// 3. **2.0× 字号不换行**：每段字仍是单行（`maxLines: 1`），且值行缩放到
///    卡片以内（FittedBox 兜底），没有 RenderFlex 溢出。
void main() {
  final now = DateTime.utc(2026, 9, 12, 10);

  void viewport(WidgetTester tester, Size size, {double scale = 1}) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget page(AppDatabase database) => MaterialApp(
    theme: AppTheme.light(),
    home: SettingsPage(
      profileOverviewLoader: LoadProfileOverview(
        database: database,
        clock: FixedAppClock(now),
      ),
    ),
  );

  /// 身高 165cm 的女档案（BMI = weightKg / 1.65²；BMR = Mifflin-St Jeor）。
  /// [weightKg] 传 null = 只有档案没有体重（BMI 无从派生）。
  Future<void> seedProfile(
    AppDatabase database, {
    double? weightKg,
    double? calorieMinKcal,
    double? calorieMaxKcal,
  }) async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'hm-profile',
            birthYear: const Value(1995),
            biologicalSex: const Value('female'),
            heightCm: const Value(165.0),
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (weightKg != null) {
      await database
          .into(database.measurements)
          .insert(
            MeasurementsCompanion.insert(
              id: 'hm-weight',
              profileId: 'hm-profile',
              localDate: '2026-09-12',
              weightKg: weightKg,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    if (calorieMinKcal != null && calorieMaxKcal != null) {
      await database
          .into(database.goals)
          .insert(
            GoalsCompanion.insert(
              id: 'hm-goal',
              profileId: 'hm-profile',
              type: 'loseFat',
              calorieMinKcal: calorieMinKcal,
              calorieMaxKcal: calorieMaxKcal,
              effectiveFrom: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
  }

  /// 每日目标行：水分目标与热量区间都从这里读（热量区间另有一路 Goals）。
  Future<void> seedDailyTarget(
    AppDatabase database, {
    required double waterTargetMl,
    double calorieMin = 1400,
    double calorieMax = 1600,
  }) async {
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 'hm-target',
            goalId: 'hm-goal',
            effectiveDate: '2026-09-12',
            calorieMinKcal: calorieMin,
            calorieMaxKcal: calorieMax,
            proteinMinGrams: 60,
            proteinMaxGrams: 120,
            carbsMinGrams: 150,
            carbsMaxGrams: 220,
            fatMinGrams: 40,
            fatMaxGrams: 60,
            waterTargetMl: Value(waterTargetMl),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> seedWater(AppDatabase database, double amountMl) async {
    await database
        .into(database.waterIntakes)
        .insert(
          WaterIntakesCompanion.insert(
            id: 'hm-water-${amountMl.round()}',
            localDate: '2026-09-12',
            amountMl: amountMl,
            recordedAt: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> scrollToHealth(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-health-metrics')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// 某张卡右上角的档位/位置徽标文字；没有徽标 ⇒ null（空态就该是 null）。
  String? badgeOf(WidgetTester tester, Key cardKey) {
    final badge = find.descendant(
      of: find.byKey(cardKey),
      matching: find.byKey(const Key('lf-gauge-badge')),
    );
    if (badge.evaluate().isEmpty) return null;
    return tester
        .widget<Text>(find.descendant(of: badge, matching: find.byType(Text)))
        .data;
  }

  /// 某张卡的值行文字（大字那个）。刻度尺上的档界数字可能是同一个字符串
  /// （18.5 既是 BMI 值也是档界），所以按 key 取而不是按文本取。
  String? valueOf(WidgetTester tester, Key cardKey) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(cardKey),
          matching: find.byKey(const Key('lf-gauge-value')),
        ),
      )
      .data;

  const bmiCard = Key('settings-health-bmi');
  const bmrCard = Key('settings-health-bmr');

  group('分档口径（纯函数，边界逐个钉）', () {
    test('BMI：18.5 / 24.0 / 28.0 三个跳变点的左右各测一档', () {
      expect(bmiTierOf(18.4), BmiTier.thin);
      expect(bmiTierOf(18.5), BmiTier.normal);
      expect(bmiTierOf(23.9), BmiTier.normal);
      expect(bmiTierOf(24.0), BmiTier.over);
      expect(bmiTierOf(27.9), BmiTier.over);
      expect(bmiTierOf(28.0), BmiTier.obese);
    });

    test('BMI：缺值与非有限数不给档（不猜档）', () {
      expect(bmiTierOf(null), isNull);
      expect(bmiTierOf(double.nan), isNull);
      expect(bmiTierOf(double.infinity), isNull);
    });

    test('BMR：低于 / 落在（含两端点） / 高于目标区间', () {
      BmrPosition? at(int bmr) => bmrPositionOf(
        bmrKcal: bmr,
        calorieMinKcal: 1900,
        calorieMaxKcal: 2100,
      );
      expect(at(1899), BmrPosition.below);
      expect(at(1900), BmrPosition.within);
      expect(at(2100), BmrPosition.within);
      expect(at(2101), BmrPosition.above);
    });

    test('BMR：缺值或缺区间 ⇒ 不给位置（无从比较 ≠ 在中间）', () {
      expect(
        bmrPositionOf(
          bmrKcal: null,
          calorieMinKcal: 1900,
          calorieMaxKcal: 2100,
        ),
        isNull,
      );
      expect(
        bmrPositionOf(
          bmrKcal: 1900,
          calorieMinKcal: null,
          calorieMaxKcal: 2100,
        ),
        isNull,
      );
      expect(
        bmrPositionOf(
          bmrKcal: 1900,
          calorieMinKcal: 1900,
          calorieMaxKcal: null,
        ),
        isNull,
      );
      // 反向区间（脏数据）也不给结论。
      expect(
        bmrPositionOf(
          bmrKcal: 2000,
          calorieMinKcal: 2100,
          calorieMaxKcal: 1900,
        ),
        isNull,
      );
    });

    // 2026-10-16：`waterProgressOf` 随水分环卡一起删除（生产上零调用方）。
    // 这几条纯函数断言随之退场——饮水达成度的表达搬到今日页饮水卡
    // （`dashboard-stat-water` 的「已饮 / 目标 ml + 达标 N%」，那里有自己的
    // 覆盖）。
  });

  group('BMI 刻度尺（档位文字必须与口径一致）', () {
    testWidgets('六个边界体重逐个归对档，值按一位小数显示', (tester) async {
      viewport(tester, const Size(390, 1000));
      // BMI = 体重 / 1.65²（2.7225）。体重取在边界**两侧一指之宽**处而不是
      // 数学上的等号点：`2.7225 * 18.5` 在 double 里会落到 18.4999…，
      // 等号点归哪档取决于浮点末位，不该由这个测试来钉（精确等号由上面的
      // 纯函数边界测试负责）。这里钉的是「口径真的接进了页面」。
      const cases = <({double weightKg, String shown, String tier})>[
        (weightKg: 50.10, shown: '18.4', tier: '偏瘦'),
        (weightKg: 50.40, shown: '18.5', tier: '正常'),
        (weightKg: 65.10, shown: '23.9', tier: '正常'),
        (weightKg: 65.40, shown: '24.0', tier: '超重'),
        (weightKg: 76.00, shown: '27.9', tier: '超重'),
        (weightKg: 76.30, shown: '28.0', tier: '肥胖'),
      ];
      for (final item in cases) {
        final database = AppDatabase(NativeDatabase.memory());
        try {
          await seedProfile(database, weightKg: item.weightKg);
          await tester.pumpWidget(page(database));
          await tester.pumpAndSettle();
          await scrollToHealth(tester);

          expect(
            valueOf(tester, bmiCard),
            item.shown,
            reason: '体重 ${item.weightKg}kg 的 BMI 应显示 ${item.shown}',
          );
          expect(
            badgeOf(tester, bmiCard),
            item.tier,
            reason: 'BMI ${item.shown} 应归「${item.tier}」档',
          );
          // 有值 ⇒ 刻度尺上必须有指示器（否则等于把值藏了）。
          expect(
            find.descendant(
              of: find.byKey(bmiCard),
              matching: find.byKey(const Key('lf-gauge-marker')),
            ),
            findsOneWidget,
          );
        } finally {
          // 卸载整棵页面树再关库：旧页面留着已关闭的库会在下一条里炸，
          // 而没关掉的库会让 drift 打出「multiple databases」警告。
          // finally 保证断言中途失败也不会把库漏在那儿。
          await tester.pumpWidget(const SizedBox.shrink());
          await database.close();
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('四段就是灰/绿/橙/红（设备实测抓出：超重段一度画成近黑色）', (tester) async {
      viewport(tester, const Size(390, 1000));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await seedProfile(database, weightKg: 65.4); // BMI 24.0 ⇒ 超重档
      await tester.pumpWidget(page(database));
      await tester.pumpAndSettle();
      await scrollToHealth(tester);

      // 刻度尺的四段是四个 ColoredBox（顺序 = 档位顺序）。
      final segments = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byKey(bmiCard),
              matching: find.byType(ColoredBox),
            ),
          )
          .toList();
      expect(segments, hasLength(4), reason: 'BMI 刻度尺应当正好四段');
      final light = LfSemanticColors.light;
      expect(segments.map((s) => s.color).toList(), [
        light.mutedForeground, // 偏瘦：灰
        LfColors.mintText(Brightness.light), // 正常：绿
        light.carbs, // 超重：橙（**不是**徽标上写字的 cardForeground）
        light.error, // 肥胖：红
      ], reason: '四段必须是灰/绿/橙/红的数据色：橙色段画成墨色就是设备上抓到的那个缺陷');
      expect(tester.takeException(), isNull);
    });

    testWidgets('空库：不给档位文字、不给指示器，值只写「—」', (tester) async {
      viewport(tester, const Size(390, 1000));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(page(database));
      await tester.pumpAndSettle();
      await scrollToHealth(tester);

      expect(
        find.descendant(of: find.byKey(bmiCard), matching: find.text('—')),
        findsOneWidget,
      );
      expect(
        badgeOf(tester, bmiCard),
        isNull,
        reason: '没有体重/身高就没有档位——不许默认给「正常」',
      );
      expect(
        find.descendant(
          of: find.byKey(bmiCard),
          matching: find.byKey(const Key('lf-gauge-marker')),
        ),
        findsNothing,
        reason: '指示器会指一个不存在的值，空态必须不画',
      );
      // 档名（偏瘦/正常/超重/肥胖）是尺子的刻度，仍然要在——它们不是结论。
      for (final label in const ['偏瘦', '正常', '超重', '肥胖']) {
        expect(
          find.descendant(of: find.byKey(bmiCard), matching: find.text(label)),
          findsOneWidget,
          reason: '刻度尺的档名与「判出档位」是两件事：$label',
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('BMR 区间指示', () {
    testWidgets('有目标区间：区间、位置文字、标记点三样齐活', (tester) async {
      viewport(tester, const Size(390, 1000));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await seedProfile(
        database,
        weightKg: 62,
        calorieMinKcal: 1400,
        calorieMaxKcal: 1600,
      );
      await seedDailyTarget(database, waterTargetMl: 2000);
      await tester.pumpWidget(page(database));
      await tester.pumpAndSettle();
      await scrollToHealth(tester);

      // BMR = 1,335（Mifflin-St Jeor），低于 1,400–1,600 ⇒ 位置文字如实写。
      expect(
        find.descendant(of: find.byKey(bmrCard), matching: find.text('1,335')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(bmrCard),
          matching: find.text('目标 1,400–1,600 kcal'),
        ),
        findsOneWidget,
      );
      expect(badgeOf(tester, bmrCard), '低于目标区间');
      expect(
        find.descendant(
          of: find.byKey(bmrCard),
          matching: find.byKey(const Key('lf-gauge-value-dot')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('区间填充与灰轨同轴（2026-10-08 用户走查的「偏上了一点」）', (tester) async {
      viewport(tester, const Size(390, 1000));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await seedProfile(
        database,
        weightKg: 62,
        calorieMinKcal: 1400,
        calorieMaxKcal: 1600,
      );
      await seedDailyTarget(database, waterTargetMl: 2000);
      await tester.pumpWidget(page(database));
      await tester.pumpAndSettle();
      await scrollToHealth(tester);

      final track = tester.getRect(
        find.descendant(
          of: find.byKey(bmrCard),
          matching: find.byKey(const Key('lf-gauge-band-track')),
        ),
      );
      final fill = tester.getRect(
        find.descendant(
          of: find.byKey(bmrCard),
          matching: find.byKey(const Key('lf-gauge-band-fill')),
        ),
      );
      // 同轴 = 两条 8dp 带的上下边各自重合。填充写成 `top: 0` 时会高出
      // 4dp（fill.top = track.top − 4），这条断言就是那个偏移的守卫。
      expect(
        fill.top,
        moreOrLessEquals(track.top, epsilon: 0.5),
        reason: '绿色区间填充的顶边必须与灰轨顶边重合（曾经高 4dp）',
      );
      expect(
        fill.bottom,
        moreOrLessEquals(track.bottom, epsilon: 0.5),
        reason: '两条带的底边也要重合',
      );
      // 带相对 16dp 容器垂直居中：容器 16、带 8 ⇒ 上边距 4。
      expect(fill.height, moreOrLessEquals(8, epsilon: 0.5));
      expect(
        fill.top - track.top,
        moreOrLessEquals(0, epsilon: 0.5),
        reason: '两条带同一条线，差值恒 0',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('无目标区间：整块图形不画，位置文字也不给', (tester) async {
      viewport(tester, const Size(390, 1000));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      // 有档案有体重 ⇒ BMR 有值，但没有任何 Goals 行 ⇒ 没有可比区间。
      await seedProfile(database, weightKg: 62);
      await tester.pumpWidget(page(database));
      await tester.pumpAndSettle();
      await scrollToHealth(tester);

      expect(
        find.descendant(of: find.byKey(bmrCard), matching: find.text('1,335')),
        findsOneWidget,
      );
      expect(badgeOf(tester, bmrCard), isNull, reason: '没有区间就没有「落在区间内」');
      expect(
        find.descendant(
          of: find.byKey(bmrCard),
          matching: find.byKey(const Key('lf-gauge-value-dot')),
        ),
        findsNothing,
      );
      expect(find.textContaining('目标 '), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('饮水进度环', () {
    Future<void> pumpWith({
      required WidgetTester tester,
      required double? targetMl,
      required double consumedMl,
    }) async {
      viewport(tester, const Size(390, 1000));
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      // daily_targets.goal_id 是外键：哪怕这个用例只看水分，也要有 Goal 行。
      await seedProfile(
        database,
        weightKg: 62,
        calorieMinKcal: 1400,
        calorieMaxKcal: 1600,
      );
      // 只有**行不存在**才叫「没有水分目标」：`water_target_ml` 列不可空且
      // 默认 2000，行里写不出 NULL（生产上也只有「还没算过每日目标」这一种
      // 无目标情形）。
      if (targetMl != null) {
        await seedDailyTarget(database, waterTargetMl: targetMl);
      }
      if (consumedMl > 0) await seedWater(database, consumedMl);
      await tester.pumpWidget(page(database));
      await tester.pumpAndSettle();
      await scrollToHealth(tester);
    }

    // 2026-10-16 用户：「去除水分摄入目标卡片」——健康区从三格改回两格
    // （BMI + 基础代谢率）。上面 4 条水分环用例（0% / 75% / 120% / 无目标）
    // 随卡一起下线：那些事实现在由**今日页的饮水卡**（`dashboard-stat-water`
    // 的「已饮 / 目标 ml + 达标 N%」）与加水弹层承载，不再是死信息。
    testWidgets('水分卡已下线：健康区只有 BMI 与基础代谢率两张卡', (tester) async {
      await pumpWith(tester: tester, targetMl: 2000, consumedMl: 1500);
      expect(find.byKey(const Key('settings-health-water')), findsNothing);
      expect(find.text('水分摄入目标'), findsNothing);
      expect(find.byKey(bmiCard), findsOneWidget);
      expect(find.byKey(bmrCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('2.0× 字号：两张卡里每段文字仍是单行，且不越出卡片', (tester) async {
    viewport(tester, const Size(390, 1000), scale: 2);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await seedProfile(
      database,
      weightKg: 62,
      calorieMinKcal: 1400,
      calorieMaxKcal: 1600,
    );
    await seedDailyTarget(database, waterTargetMl: 2000);
    await seedWater(database, 1500);
    await tester.pumpWidget(page(database));
    await tester.pumpAndSettle();
    await scrollToHealth(tester);

    // 三张卡里每一段可见文字都要过关：**只占一行**（`maxLines: 1` 真的生效）
    // 且**没被挤窄**——单行文字的排版宽度一旦小于它需要的宽度，不是折行就是
    // 被裁掉（`softWrap: false` 的默认结局是裁），两种都是坏。值行有
    // FittedBox 兜底（它的排版宽度=需要宽度，缩放发生在绘制阶段），所以这条
    // 「需要宽度 ≤ 排版宽度」对它天然成立，不会被误报。
    const texts = [
      'BMI',
      '22.8',
      '偏瘦',
      '正常',
      '超重',
      '肥胖',
      '基础代谢率',
      '1,335',
      'kcal/天',
      '目标 1,400–1,600 kcal',
      '低于目标区间',
      // 尺子上的刻度数字也受 2.0× 影响，而且是设备上真的被裁过的一处。
      '18.5',
      '24',
      '28',
    ];
    final multiLine = <String>[];
    final squeezed = <String>[];
    final clipped = <String>[];
    for (final text in texts) {
      final finder = find.text(text);
      expect(finder, findsWidgets, reason: '2.0× 下这段文字应当可见：$text');
      // '正常' 之类会同时命中档名与徽标：每一处都要过关。
      for (final paragraph in tester.renderObjectList<RenderParagraph>(
        finder,
      )) {
        final textLength = paragraph.text.toPlainText().length;
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: textLength),
        );
        if (boxes.map((box) => box.top).toSet().length > 1) multiLine.add(text);
        if (paragraph.size.width + 0.5 <
            paragraph.getMaxIntrinsicWidth(double.infinity)) {
          squeezed.add(
            '$text（要 ${paragraph.getMaxIntrinsicWidth(double.infinity).toStringAsFixed(0)}'
            '，只有 ${paragraph.size.width.toStringAsFixed(0)}）',
          );
        }
        // 纵向也会静默裁：父级把行高写死时（设备实测：刻度行写死 14px，
        // 2.0× 下 micro 字高 20px）段落盒子仍是满高，字却只露上半截 ——
        // 判据是文字选区的底越过段落底沿。
        final bottom = boxes.isEmpty
            ? 0.0
            : boxes.map((box) => box.bottom).reduce((a, b) => a > b ? a : b);
        if (bottom > paragraph.size.height + 1.0) {
          clipped.add(
            '$text（字底 ${bottom.toStringAsFixed(1)}，'
            '段落只有 ${paragraph.size.height.toStringAsFixed(1)}）',
          );
        }
      }
    }
    expect(multiLine, isEmpty, reason: '2.0× 下折行了的文字：${multiLine.join('、')}');
    expect(
      squeezed,
      isEmpty,
      reason: '2.0× 下宽度不够、会被裁的文字：${squeezed.join('、')}',
    );
    expect(clipped, isEmpty, reason: '2.0× 下纵向被裁半截的文字：${clipped.join('、')}');

    // 刻度数字要真的挂在轴上它标的那个点（轴 15–35），而不是随字宽往中间
    // 挤——那说明位置是按「剩余空间」摊的。每个数字各自对齐自己的点，比
    // 「跨度够大」这种松判据严得多。
    final ticksRect = tester.getRect(find.byKey(const Key('lf-gauge-ticks')));
    const tickValues = [('18.5', 18.5), ('24', 24.0), ('28', 28.0)];
    for (final (label, value) in tickValues) {
      final center = tester
          .getCenter(
            find.descendant(
              of: find.byKey(bmiCard),
              matching: find.text(label),
            ),
          )
          .dx;
      final expected = ticksRect.left + (value - 15) / 20 * ticksRect.width;
      expect(
        (center - expected).abs(),
        lessThan(3.0),
        reason:
            '「$label」没挂在轴上它标的那个点：实际 ${center.toStringAsFixed(1)}，'
            '应在 ${expected.toStringAsFixed(1)}'
            '（刻度行 ${ticksRect.left.toStringAsFixed(1)}–'
            '${ticksRect.right.toStringAsFixed(1)}）',
      );
    }

    // 值行（大数字 + 单位）不许横溢出卡片右沿。
    for (final key in const [bmiCard, bmrCard]) {
      final card = tester.getRect(find.byKey(key));
      for (final text in const ['22.8', '1,335']) {
        final finder = find.descendant(
          of: find.byKey(key),
          matching: find.text(text),
        );
        if (finder.evaluate().isEmpty) continue;
        expect(
          tester.getRect(finder.first).right,
          lessThanOrEqualTo(card.right + 0.5),
          reason: '$text 越出了卡片右沿',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });
}
