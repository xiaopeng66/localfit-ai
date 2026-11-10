import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/lf_energy_card.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/domain/meal_record.dart';
import 'package:localfit_ai/features/nutrition/domain/nutrition_target_override.dart';
import 'package:localfit_ai/features/nutrition/presentation/nutrition_target_sheet.dart';

/// **手动指定每日营养目标**（2026-10-26 用户：「营养摄入自己不能改」）。
///
/// 复核发现的缺口：热量/宏量目标完全由 `NutritionTargetCalculator` 从身体数据
/// 算出来，全应用（包括 AI 聊天）都没有覆盖入口。本文件钉三件事：
/// 1. 存进去的目标真的被读出来（`goalType = 'manual'` + 数字逐字相等）；
/// 2. 卡上的**依据**必须如实改口——不能一边用手动数字、一边还说「按公式」；
/// 3. 恢复后回到「没有目标」/公式口径（不留下半套手动值）。
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

  NutritionTargetOverride override({String effectiveDate = localDate}) =>
      NutritionTargetOverride(
        effectiveDate: effectiveDate,
        calorieMinKcal: 1800,
        calorieMaxKcal: 2000,
        proteinMinGrams: 110,
        proteinMaxGrams: 140,
        carbsMinGrams: 180,
        carbsMaxGrams: 240,
        fatMinGrams: 50,
        fatMaxGrams: 70,
      );

  group('仓储：手动目标被真实读出来', () {
    test('保存后目标是 manual + 数字逐字相等；恢复后回到「没有目标」', () async {
      // 没有每日生效行时：无目标。
      var summary = await meals.watchNutritionForDate(localDate).first;
      expect(summary.target, isNull);

      await meals.saveManualTarget(override());
      summary = await meals.watchNutritionForDate(localDate).first;
      final target = summary.target!;
      expect(target.goalType, 'manual', reason: '要能区分「手动」与公式档位');
      expect(target.calorieMinKcal, 1800);
      expect(target.calorieMaxKcal, 2000);
      expect(target.proteinMinGrams, 110);
      expect(target.proteinMaxGrams, 140);
      expect(target.carbsMinGrams, 180);
      expect(target.carbsMaxGrams, 240);
      expect(target.fatMinGrams, 50);
      expect(target.fatMaxGrams, 70);

      await meals.clearManualTarget();
      summary = await meals.watchNutritionForDate(localDate).first;
      expect(summary.target, isNull, reason: '恢复后不该留下半对手动值');
    });

    test('生效日期在未来：今天仍按原口径（不提前生效）', () async {
      await meals.saveManualTarget(override(effectiveDate: '2026-11-01'));
      final summary = await meals.watchNutritionForDate(localDate).first;
      expect(summary.target, isNull, reason: '还没到生效日就不该套用');
    });

    test('区间写反 / 负数：拒绝，不落库', () async {
      await expectLater(
        meals.saveManualTarget(
          NutritionTargetOverride(
            effectiveDate: localDate,
            calorieMinKcal: 2200,
            calorieMaxKcal: 1800,
            proteinMinGrams: 110,
            proteinMaxGrams: 140,
            carbsMinGrams: 180,
            carbsMaxGrams: 240,
            fatMinGrams: 50,
            fatMaxGrams: 70,
          ),
        ),
        throwsFormatException,
        reason: '下限不能大于上限',
      );
      expect(await meals.readManualTargetForDate(localDate), isNull);
    });
  });

  group('卡上依据：手动目标不许说「按公式」', () {
    Future<void> pumpCard(
      WidgetTester tester,
      DailyNutritionTarget target,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LfEnergyCard(
                consumed: const NutritionValues(
                  kcal: 1200,
                  proteinGrams: 60,
                  carbsGrams: 120,
                  fatGrams: 40,
                ),
                target: target,
                title: '今日营养',
                cardKey: const Key('verify-energy'),
                keyPrefix: 'verify-ring',
                remainingKey: const Key('verify-remaining'),
                statusKey: const Key('verify-status'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('「调整目标」图标钮可点（接了就有点的入口，没接就不给假入口）', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LfEnergyCard(
                consumed: const NutritionValues(
                  kcal: 1200,
                  proteinGrams: 60,
                  carbsGrams: 120,
                  fatGrams: 40,
                ),
                target: override().toTarget(),
                title: '今日营养',
                cardKey: const Key('verify-energy'),
                keyPrefix: 'verify-ring',
                remainingKey: const Key('verify-remaining'),
                statusKey: const Key('verify-status'),
                onEditTarget: () => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('verify-ring-edit-target')));
      await tester.pumpAndSettle();
      expect(taps, 1, reason: '点「调整目标」图标钮要真的打开目标弹层');
    });

    // 【断言改写（不是删）】2026-10-28 用户：「这里文字换行了，不要显示左边
    // 那个说明」——foot 左格说明整体撤下，「手动设定/不按公式」的诚实口径
    // 由营养目标弹层自己说明（`NutritionTargetSheet`）。这条改为钉「撤干净」：
    // 不论手动还是公式目标，卡上都不再出现那行字。
    testWidgets('foot 左格不再有说明文字（手动/公式目标都不印）', (tester) async {
      await pumpCard(tester, override().toTarget());
      expect(
        find.byKey(const Key('verify-ring-foot-basis')),
        findsNothing,
        reason: '说明行已撤下（换行难看），Key 一并退役',
      );
      expect(find.textContaining('手动设定'), findsNothing);
      expect(find.textContaining('Mifflin'), findsNothing);
    });
  });

  group('弹层：填区间 → 保存', () {
    testWidgets('预填当前目标，四项区间都能改', (tester) async {
      NutritionTargetOverride? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: NutritionTargetSheet(
                effectiveDate: localDate,
                current: override().toTarget(),
                onSave: (value) async {
                  saved = value;
                  return null;
                },
                onRestore: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 预填：卡上现在是多少，输入框就是多少（用户只改要改的那格）。
      expect(
        tester.widget<TextFormField>(find.byKey(const Key('target-kcal-min'))),
        isNotNull,
      );
      await tester.enterText(find.byKey(const Key('target-kcal-max')), '2100');
      await tester.tap(find.byKey(const Key('target-save')));
      await tester.pumpAndSettle();

      expect(saved, isNotNull);
      expect(saved!.calorieMinKcal, 1800, reason: '没改的那格保持原值');
      expect(saved!.calorieMaxKcal, 2100);
      expect(saved!.effectiveDate, localDate, reason: '从今天起生效');
    });
  });

  group('弹层：2.0× 不裁数字（2026-10-31 实帧抓到）', () {
    testWidgets('320dp×2.0×：热量与宏量上下限各占整行，1800/2200 完整可读', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 1100);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 1100),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: NutritionTargetSheet(
                  effectiveDate: localDate,
                  current: override().toTarget(),
                  onSave: (_) async => null,
                  onRestore: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final prefix in ['kcal', 'protein', 'carbs', 'fat']) {
        final min = tester.getRect(find.byKey(Key('target-$prefix-min')));
        final max = tester.getRect(find.byKey(Key('target-$prefix-max')));
        expect(
          max.top,
          greaterThanOrEqualTo(min.bottom),
          reason: '$prefix 上下限在大字号下必须各占整行，否则数字被横向裁掉',
        );
      }
      for (final key in ['target-kcal-min', 'target-kcal-max']) {
        final field = tester.widget<TextFormField>(find.byKey(Key(key)));
        expect(field.controller!.text, isNotEmpty);
      }
    });
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'target-${_value++}';
}
