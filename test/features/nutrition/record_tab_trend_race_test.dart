import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/record_tab.dart';
import 'package:localfit_ai/features/progress/application/trend_calculator.dart';

/// 趋势窗口竞态回归（原 `nutritional_trend_card_race_test.dart` 的断言落点，
/// 阶段 I 收口时迁移到新设计的记录页）。
///
/// 旧卡片自带 7/30 切换，两次请求可能乱序返回。新记录页把窗口挂在**选中
/// 日期**上，同一类竞态依然存在：用户连点两天，先发的请求若后落地，页面会
/// 拿旧窗口的数据冒充当前选中的日子——这正是「不得撒谎」要拦的场景。
void main() {
  late AppDatabase database;
  late MealRepository meals;

  final now = DateTime(2026, 9, 11, 12);

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    meals = MealRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(now.toUtc()),
    );
  });

  tearDown(() => database.close());

  IntakeTrend trend(double kcal) => IntakeTrend(
    trackedDays: 1,
    averageKcal: kcal,
    averageMacros: const MacroAverages(
      proteinGrams: 0,
      carbsGrams: 0,
      fatGrams: 0,
    ),
    goalDaysMet: null,
    records: [
      DailyIntakeRecord(
        localDate: '2026-09-11',
        kcal: kcal,
        proteinGrams: 0,
        carbsGrams: 0,
        fatGrams: 0,
      ),
    ],
  );

  testWidgets('慢的旧窗口请求后落地，不得冒充当前选中日的趋势', (tester) async {
    // 分析卡是懒加载 sliver：视口不够高就根本不会构建，断言会假阴性。
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final older = Completer<IntakeTrend>();
    final newer = Completer<IntakeTrend>();

    Future<void> pumpDate(DateTime date) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordTab(
              mealRepository: meals,
              selectedDate: date,
              now: now,
              onSelectDate: (_) {},
              onEditMeal: (_) {},
              onDeleteMeal: (_) {},
              loadTrend: (days, endDate) =>
                  endDate.day == 10 ? older.future : newer.future,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    try {
      // 选中 9/10 → 发起「旧」请求；改选 9/11 → 发起「新」请求。
      await pumpDate(DateTime(2026, 9, 10));
      await pumpDate(DateTime(2026, 9, 11));

      // 新请求先回来：此时趋势卡与分析卡显示 2000。
      newer.complete(trend(2000));
      await tester.pump();
      await tester.pump();
      expect(find.text('2000'), findsOneWidget, reason: '新窗口的结果应当先渲染');

      // 旧请求（9/10 的加载）后落地：绝不能把 9/10 的窗口数据画成 9/11 的趋势。
      older.complete(trend(1000));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('1000'),
        findsNothing,
        reason: '过期窗口的结果不得覆盖当前选中日的数据（旧卡片 race 断言的落点）',
      );
      expect(find.text('2000'), findsOneWidget);
    } finally {
      // 收尾：显式卸载，排掉 drift 流的取消定时器（失败路径也走这里，
      // 否则挂起的流会让用例一直等到 10 分钟超时）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'race-${_value++}';
}
