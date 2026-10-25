import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/goal_big_card.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/hydration/application/update_water_target_ml.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart'
    show HealthGoal;
import 'package:localfit_ai/features/progress/data/steps_repository.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/presentation/profile_edit_page.dart';

import '../../support/round7_render.dart';

/// 「编辑资料」页的「每日目标」两行（docs/32 §4 T9 / §3 D11 需求 64/72）。
///
/// 契约（逐条对应下面的断言）：
/// - 两行**预填**库里当前值（步数缺键 = 10000；水分读当日生效行 = 2000 ⇒ 显示「2」）；
/// - 改了就写（步数进 `AppSettings`；水分走 `UpdateWaterTargetMl`）；
/// - **空框 = 不改**（这两个字段没有 null 语义，不假装写入）；
/// - 越界当场拦下（校验文案上屏，不写库、不弹确认）；
/// - 未接线 ⇒ 整行不渲染（不画点了没反应的输入框）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late StepsRepository stepsRepository;
  late UpdateWaterTargetMl updateWaterTarget;
  late ProfileEditPage page;
  var closed = false;

  const today = '2026-10-13';

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(_nowUtc);
    stepsRepository = StepsRepository(
      database: database,
      channel: StepsChannel(),
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    updateWaterTarget = UpdateWaterTargetMl(
      database: database,
      idGenerator: const UuidV7Generator(),
      clock: clock,
    );
    closed = false;
    page = _buildPage(
      database: database,
      stepsRepository: stepsRepository,
      updateWaterTargetMl: updateWaterTarget,
      onClose: () => closed = true,
    );
  });

  tearDown(() => database.close());

  // 2026-10-16 用户：「编辑资料里的训练目标做成引导页那种形式」——三行
  // `RadioListTile` 换成引导页同款的三张 `GoalBigCard`（同一件公共组件）。
  testWidgets('训练目标 = 三张 GoalBigCard，点了就选中（不再是 RadioListTile）', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfileEditPage(
          repository: ProfileIdentityRepository(database: database),
          currentGoal: HealthGoal.loseFat,
          onClose: () {},
          now: DateTime(2026, 10, 13),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GoalBigCard), findsNWidgets(3));
    expect(find.byType(RadioListTile<HealthGoal>), findsNothing);
    expect(
      tester
          .widget<GoalBigCard>(find.byKey(const Key('profile-goal-loseFat')))
          .selected,
      isTrue,
      reason: '回填：当前目标是减脂，那第一张必须是选中态',
    );

    await tester.tap(find.byKey(const Key('profile-goal-gainMuscle')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<GoalBigCard>(find.byKey(const Key('profile-goal-gainMuscle')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<GoalBigCard>(find.byKey(const Key('profile-goal-loseFat')))
          .selected,
      isFalse,
      reason: '单选：选中新的就取消旧的',
    );
  });

  testWidgets('训练目标三条的标签随主题字体（缺陷 ㉔，与 ⑫/⑮/㉒ 同族）', (tester) async {
    // Round7 阶段 6 渲染审看抓到（`renders/6b-pages/profile-edit-light-360-1.0.png`）：
    // 三条 `RadioListTile` 的标题是 **`□□` 空方框**——`ListTile` 系用
    // `titleTextStyle` **替换**环境 `DefaultTextStyle`，而默认那份不带主题
    // 字体族（与 ⑮ 的食物选择弹层、㉒ 的 `AppBar` 同一机制）。
    // 目标三行在页首，但默认 600dp 视口下 `ListView` 懒建——拉高视口（同本文件
    // 既有 `pump` 的做法）。
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 用**捕获件主题**（帧的真实来源）：`AppTheme` 不内置族（§2.6.1），
    // 冻结在 `listTileTheme` 里的标题样式要靠捕获件注族——本判据钉的就是
    // 「帧里的这三行不是空方框」。（第一版用裸 `ThemeData.light()`，没有
    // `listTileTheme` 覆盖 ⇒ 空转通过；已改。）
    final theme = round7CaptureTheme(AppTheme.light());
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: ProfileEditPage(
          repository: ProfileIdentityRepository(database: database),
          currentGoal: null,
          onClose: () {},
          now: DateTime(2026, 10, 13),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final label in const ['减脂', '维持', '增肌']) {
      final text = tester.widget<Text>(find.text(label));
      final data = text.style;
      final inherited = DefaultTextStyle.of(tester.element(find.text(label)))
          .style;
      expect(
        data?.fontFamily ?? inherited.fontFamily,
        'Round7LocalCjk',
        reason: '「$label」这一行的字体族必须随主题（否则帧里是空方框）',
      );
    }
  });

  Future<void> pump(WidgetTester tester) async {
    // 窗口拉高：`ListView(children:)` 懒建，默认 600dp 高时最后几个字段
    // 还没进元素树，`enterText` 会找不到目标（不是页面缺陷）。
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pumpAndSettle();
  }

  Future<String?> storedStepsGoal() async {
    final row =
        await (database.select(database.appSettings)
              ..where((r) => r.key.equals(StepsRepository.dailyGoalKey)))
            .getSingleOrNull();
    return row?.value;
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
  }

  testWidgets('两行都在、Key 齐、预填库里当前值（10000 / 2）', (tester) async {
    await _seedWaterTarget(database, effectiveDate: today);
    await pump(tester);

    expect(find.text('每日目标'), findsOneWidget);
    expect(find.byKey(const Key('profile-steps-goal')), findsOneWidget);
    expect(find.byKey(const Key('profile-water-target')), findsOneWidget);
    final stepsField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('profile-steps-goal')),
        matching: find.byType(TextField),
      ),
    );
    expect(stepsField.controller?.text, '10000');
    final waterField = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('profile-water-target')),
        matching: find.byType(TextField),
      ),
    );
    expect(waterField.controller?.text, '2');
  });

  testWidgets('改步数目标 ⇒ 写进 AppSettings（12000）且保存后关页', (tester) async {
    await _seedWaterTarget(database, effectiveDate: today);
    await pump(tester);

    await tester.enterText(
      find.byKey(const Key('profile-steps-goal')),
      '12000',
    );
    await tapSave(tester);
    await confirm(tester);

    expect(await storedStepsGoal(), '12000');
    expect(closed, isTrue);
  });

  testWidgets('改水分目标 ⇒ 落成 ml（2.5 ⇒ 2500），历史行不动', (tester) async {
    await _seedWaterTarget(database, effectiveDate: '2026-10-12');
    await pump(tester);

    await tester.enterText(
      find.byKey(const Key('profile-water-target')),
      '2.5',
    );
    await tapSave(tester);
    await confirm(tester);

    expect(await updateWaterTarget.readCurrentMl(today), 2500);
    expect(await updateWaterTarget.readCurrentMl('2026-10-12'), 2000);
    expect(await database.select(database.dailyTargets).get(), hasLength(2));
  });

  testWidgets('值没变 ⇒ 一次都不写（水分不落无意义的新版本行）', (tester) async {
    await _seedWaterTarget(database, effectiveDate: today, id: 'target-today');
    await pump(tester);

    await tapSave(tester);
    await confirm(tester);

    expect(await storedStepsGoal(), isNull, reason: '步数没改就不该落键');
    final rows = await database.select(database.dailyTargets).get();
    expect(rows, hasLength(1));
    expect(
      rows.single.updatedAt.toUtc(),
      DateTime.utc(2026, 10, 12, 4),
      reason: 'updatedAt 未被刷新',
    );
  });

  testWidgets('清空两行 ⇒ 不改库（空 ≠ 删除）', (tester) async {
    await _seedWaterTarget(database, effectiveDate: today);
    await pump(tester);

    await tester.enterText(find.byKey(const Key('profile-steps-goal')), '');
    await tester.enterText(find.byKey(const Key('profile-water-target')), '');
    await tapSave(tester);
    await confirm(tester);

    expect(await storedStepsGoal(), isNull);
    expect(await updateWaterTarget.readCurrentMl(today), 2000);
    expect(closed, isTrue, reason: '没有要写的东西也照常完成保存');
  });

  testWidgets('越界当场拦下：步数 999 / 水分 7.5 都不写库、不弹确认', (tester) async {
    await _seedWaterTarget(database, effectiveDate: today);
    await pump(tester);

    await tester.enterText(find.byKey(const Key('profile-steps-goal')), '999');
    await tapSave(tester);
    expect(find.text('步数目标需在 1000–50000 之间'), findsOneWidget);
    expect(find.text('确认更新个人资料？'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('profile-steps-goal')),
      '12000',
    );
    await tester.enterText(
      find.byKey(const Key('profile-water-target')),
      '7.5',
    );
    await tapSave(tester);
    expect(find.text('水分目标需在 0.5–6.0 L 之间'), findsOneWidget);
    expect(find.text('确认更新个人资料？'), findsNothing);

    expect(await storedStepsGoal(), isNull);
    expect(await updateWaterTarget.readCurrentMl(today), 2000);
    expect(closed, isFalse);
  });

  testWidgets('未接线：两行与分组标题都不渲染（老调用点零变化）', (tester) async {
    page = _buildPage(
      database: database,
      stepsRepository: null,
      updateWaterTargetMl: null,
      onClose: () => closed = true,
    );
    await pump(tester);

    expect(find.text('每日目标'), findsNothing);
    expect(find.byKey(const Key('profile-steps-goal')), findsNothing);
    expect(find.byKey(const Key('profile-water-target')), findsNothing);
    // 既有字段一个不少。
    expect(find.byKey(const Key('profile-target-weight')), findsOneWidget);
    expect(find.byKey(const Key('profile-height')), findsOneWidget);
    expect(find.byKey(const Key('profile-age')), findsOneWidget);
    expect(find.byKey(const Key('profile-sex')), findsOneWidget);
  });

  testWidgets('只接线一半：只有步数行时只渲染它（分组标题仍在）', (tester) async {
    page = _buildPage(
      database: database,
      stepsRepository: stepsRepository,
      updateWaterTargetMl: null,
      onClose: () => closed = true,
    );
    await pump(tester);

    expect(find.text('每日目标'), findsOneWidget);
    expect(find.byKey(const Key('profile-steps-goal')), findsOneWidget);
    expect(find.byKey(const Key('profile-water-target')), findsNothing);
  });
}

/// 组装页面：两处接线各自可断（未接线 ⇒ 对应行不渲染，老调用点零变化）。
///
/// 放在顶层而不是 `main()` 里的局部函数：局部函数不能被声明之前的代码
/// 引用，而 `setUp` 就在它上面。
ProfileEditPage _buildPage({
  required AppDatabase database,
  required StepsRepository? stepsRepository,
  required UpdateWaterTargetMl? updateWaterTargetMl,
  required VoidCallback onClose,
}) => ProfileEditPage(
  repository: ProfileIdentityRepository(database: database),
  currentGoal: null,
  onClose: onClose,
  now: _nowUtc,
  stepsRepository: stepsRepository,
  updateWaterTargetMl: updateWaterTargetMl,
);

/// 固定「现在」：本地时区（UTC+8）下仍是 2026-10-13，页面里的
/// `today` 与下面断言用的日期同一个。
final _nowUtc = DateTime.utc(2026, 10, 13, 4);

/// 种一条当日生效的每日目标行；上游 `profiles` / `goals` 也要先种上
/// （`daily_targets.goal_id` 有外键，drift 默认开着 `PRAGMA foreign_keys`）。
Future<void> _seedWaterTarget(
  AppDatabase database, {
  required String effectiveDate,
  String id = 'target-1',
}) async {
  final now = DateTime.utc(2026, 10, 12, 4);
  await database
      .into(database.profiles)
      .insertOnConflictUpdate(
        ProfilesCompanion.insert(
          id: 'p-1',
          activityLevel: 'moderate',
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.goals)
      .insertOnConflictUpdate(
        GoalsCompanion.insert(
          id: 'goal-1',
          profileId: 'p-1',
          type: 'maintain',
          calorieMinKcal: 1800,
          calorieMaxKcal: 2200,
          effectiveFrom: now,
          createdAt: now,
          updatedAt: now,
        ),
      );
  await database
      .into(database.dailyTargets)
      .insert(
        DailyTargetsCompanion.insert(
          id: id,
          goalId: 'goal-1',
          effectiveDate: effectiveDate,
          calorieMinKcal: 1800,
          calorieMaxKcal: 2200,
          proteinMinGrams: 90,
          proteinMaxGrams: 120,
          carbsMinGrams: 200,
          carbsMaxGrams: 260,
          fatMinGrams: 50,
          fatMaxGrams: 70,
          waterTargetMl: const Value(2000),
          createdAt: now,
          updatedAt: now,
        ),
      );
}
