import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

/// 「我的」页切回分页时重读派生数据（docs/29 §P2 连带缺陷）。
///
/// 背景：`SettingsPage` 的派生数据是 `initState` 里一次性加载的快照，而「我的」
/// 是 shell 里常驻的分支——切走期间别的页面写库（今日页记饮水/记体重），切回来
/// 还显示旧数字。修法是按分支可见性重读，可见性来自 `TickerMode`。
///
/// 2026-10-16：水分环卡按用户要求下线，这两条用例改钉**同一份 overview future**
/// 驱动的 BMI 卡（切走期间改体重 → 切回 BMI 必须跟着变）——刷新语义一字未改，
/// 只是换成还活着的那个宿主。
void main() {
  final now = DateTime.utc(2026, 9, 12, 10);

  /// 复刻 go_router `StatefulShellRoute` 的分支容器（17.1.0 `src/route.dart:1695`）：
  /// 非当前分支 `Offstage` + `TickerMode(enabled: false)`，切回来翻 true。
  Widget host(AppDatabase database, {required bool visible}) => MaterialApp(
    theme: AppTheme.light(),
    home: Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: SettingsPage(
          profileOverviewLoader: LoadProfileOverview(
            database: database,
            clock: FixedAppClock(now),
          ),
        ),
      ),
    ),
  );

  Future<void> seedProfile(
    AppDatabase database, {
    required double weightKg,
  }) async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'br-profile',
            birthYear: const Value(1995),
            biologicalSex: const Value('female'),
            heightCm: const Value(165.0),
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.measurements)
        .insert(
          MeasurementsCompanion.insert(
            id: 'br-weight',
            profileId: 'br-profile',
            localDate: '2026-09-12',
            weightKg: weightKg,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'br-goal',
            profileId: 'br-profile',
            type: 'loseFat',
            calorieMinKcal: 1400,
            calorieMaxKcal: 1600,
            effectiveFrom: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 'br-target',
            goalId: 'br-goal',
            effectiveDate: '2026-09-12',
            calorieMinKcal: 1400,
            calorieMaxKcal: 1600,
            proteinMinGrams: 60,
            proteinMaxGrams: 120,
            carbsMinGrams: 150,
            carbsMaxGrams: 220,
            fatMinGrams: 40,
            fatMaxGrams: 60,
            waterTargetMl: const Value(2000),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  /// 改体重（模拟「切走后别的页面写库」：今日页/拍照识别都能记体重）。
  Future<void> updateWeight(AppDatabase database, double weightKg) async {
    await (database.update(database.measurements)
          ..where((row) => row.id.equals('br-weight')))
        .write(MeasurementsCompanion(weightKg: Value(weightKg)));
  }

  /// 让健康卡一定被懒列表构建出来（视口够高，不用滚）。
  Future<void> bigViewport(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1400);
    addTearDown(tester.view.reset);
  }

  testWidgets('切走期间改的体重，切回「我的」时 BMI 会跟着重读', (tester) async {
    await bigViewport(tester);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await seedProfile(database, weightKg: 62);

    // 首次加载：62 / 1.65² = 22.8。
    await tester.pumpWidget(host(database, visible: false));
    await tester.pumpAndSettle();
    expect(find.text('22.8', skipOffstage: false), findsOneWidget);

    // 切走期间在别处写了库：体重改成 70。
    await updateWeight(database, 70);

    // 切回来：分支重新可见 ⇒ 重读。
    await tester.pumpWidget(host(database, visible: true));
    await tester.pumpAndSettle();

    expect(
      find.text('25.7'),
      findsOneWidget,
      reason: '70 / 1.65² = 25.7：切回来必须重读，不能停在首次加载的 22.8',
    );
    expect(find.text('22.8'), findsNothing, reason: '旧值不许留在屏上');
    expect(tester.takeException(), isNull);
  });

  testWidgets('重读期间不闪空态：旧值一直显示到新值到达', (tester) async {
    await bigViewport(tester);
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await seedProfile(database, weightKg: 62);

    await tester.pumpWidget(host(database, visible: false));
    await tester.pumpAndSettle();
    await updateWeight(database, 70);

    // 切回分页后的**每一帧**（含重建的那一帧——闪空态就发生在这一帧）都不许
    // 出现空态「—」。
    await tester.pumpWidget(host(database, visible: true));
    var sawEmpty = false;
    for (var i = 0; i < 8; i++) {
      final card = find.byKey(const Key('settings-health-bmi'));
      expect(card, findsOneWidget, reason: 'BMI 卡应该一直建着（视口够高）——第 $i 帧');
      if (find
          .descendant(of: card, matching: find.text('—'))
          .evaluate()
          .isNotEmpty) {
        sawEmpty = true;
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(sawEmpty, isFalse, reason: '重读期间闪了空态（「—」）——旧值应当一直显示到新值到达');
    expect(find.text('25.7'), findsOneWidget);
    expect(find.text('22.8'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
