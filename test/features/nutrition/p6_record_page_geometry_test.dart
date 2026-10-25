import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/record_fab.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/campus_menus/data/canteen_repository.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/record_tab.dart';

/// docs/29 §P6 需求 12/13 的**几何**断言（间距与浮空程度）。
///
/// 需求 12 说 hero 与下一餐推荐卡之间此前外部间距 = 0，并要求加
/// `LfDimens.pagePadding`（16dp）；需求 13 要求把 FAB 抬到约 96 并加大阴影，
/// 且**改后必须实测** FAB 与中间凸起圆的像素间距（原值只有约 6.5dp）。
///
/// 两件事都不是「看起来差不多」能验收的，所以这里用 `getRect` 量真实渲染盒：
/// 间距量 hero 外框与 leading 外框之间那段**没有任何卡片**的空白；FAB 量
/// 关键件外框底边与凸起圆顶边之差。文字/色值断言在别的文件里，这里只管几何。
void main() {
  testWidgets('需求 12：hero 与下一餐卡之间是 16dp 外部间距（此前 0）', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = FixedAppClock(DateTime.utc(2026, 9, 9));
    final meals = MealRepository(
      database: db,
      idGenerator: _Ids(),
      clock: clock,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordTab(
            mealRepository: meals,
            selectedDate: DateTime(2026, 9, 9),
            now: DateTime(2026, 9, 9),
            onSelectDate: (_) {},
            onEditMeal: (_) {},
            onDeleteMeal: (_) {},
            leading: const SizedBox(
              key: Key('p6-leading-probe'),
              height: 40,
              width: double.infinity,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cardBottom = tester
        .getRect(find.byKey(const Key('nutrition-record-energy')))
        .bottom;
    final leadingTop = tester
        .getRect(find.byKey(const Key('p6-leading-probe')))
        .top;
    final gap = leadingTop - cardBottom;

    // 判据是「真的空出 16dp」，不是「有个 Padding 件」——所以量盒子。
    expect(
      gap,
      closeTo(LfDimens.pagePadding, 0.5),
      reason:
          '页首卡外框底边 $cardBottom 与卡顶边 $leadingTop 之间的间距应为 '
          '${LfDimens.pagePadding}dp；实测 ${gap}dp。'
          '（卡自带的 18dp 内边距在卡片内部，不属于外部间距。）',
    );
    // 反向钉住「不是 0」：把上面那条的 Padding 删掉时，这条会先红。
    expect(gap, greaterThan(0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('需求 13：FAB 抬到 96，与凸起圆净距 ≥20dp（此前 6.5dp）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = FixedAppClock(DateTime.utc(2026, 9, 9));
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.nutrition,
        foodRepository: FoodRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        mealRepository: MealRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        canteenRepository: CanteenRepository(
          database: db,
          idGenerator: _Ids(),
          clock: clock,
        ),
        now: DateTime(2026, 9, 9),
      ),
    );
    await tester.pumpAndSettle();

    // 常量：设计稿给的是 80，docs/29 §P6 抬到 96（理由写在 record_fab.dart）。
    expect(RecordFab.bottomOffset, 96);

    final fab = find.byKey(const Key('nutrition-record-fab'));
    expect(fab, findsOneWidget);
    final bump = find.byKey(const Key('nav-ai-workbench'));
    expect(bump, findsOneWidget);

    final clearance = tester.getRect(bump).top - tester.getRect(fab).bottom;
    // 旧值 6.5dp 让 FAB 像是贴在凸起圆上（这正是用户提的「不够浮空」）。
    // 20dp 是下限而不是精确值：FAB 外框还包着 1dp 阴影留白，改留白不该红。
    expect(
      clearance,
      greaterThanOrEqualTo(20.0),
      reason: 'FAB 下缘到凸起圆顶的净距应 ≥20dp；实测 ${clearance.toStringAsFixed(1)}dp',
    );
    // 上限同样是判据：不设上限时「把 FAB 抬到天上」也能过。docs/29 的目标值
    // 是 22.5dp（= bottomOffset 96 − 预留 73.5），容差覆盖 1dp 描边环。
    expect(clearance, lessThanOrEqualTo(26.0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('需求 13：FAB 阴影按 docs/29 加强（blur 20 / 下移 6 / primary 40%）', (
    tester,
  ) async {
    const primary = Color(0xFF2FBE8F);
    final shadow = LfShadows.recordFab(primary).single;
    expect(shadow.blurRadius, 20);
    expect(shadow.offset, const Offset(0, 6));
    // docs/29 原文写 α .38；docs/21 §2.4 的彩色阴影白名单是 N ∈ {25,30,35,40}
    // 且明写「不新增阴影 token」⇒ 取最近档 40%。38/40 在屏上不可分辨，
    // 白名单才是硬约束（偏离已记进 lf_tokens.dart 与 P6 证据文件）。
    expect(shadow.color, primary.withValues(alpha: 0.40));
    // 反向前提：旧值本来是 12/30%，别把回归当达标。
    expect(shadow.blurRadius, greaterThan(12));
    expect(shadow.color.a, greaterThan(0.30));
  });
}

final class _Ids implements IdGenerator {
  int _n = 0;
  @override
  String next() => 'p6-${_n++}';
}
