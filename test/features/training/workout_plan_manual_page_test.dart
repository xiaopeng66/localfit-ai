import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/widgets/app_error_text.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_plan_repository.dart';
import 'package:localfit_ai/features/training/presentation/workout_plan_manual_page.dart';

/// 手动创建训练计划页（docs/30 §2 D7 / 用户需求 7「训练计划需要设置成可
/// ai 可手动」）。
///
/// 本文件的重点是**手动这条路本身能不能走通、且不撒谎**：
///
/// ① 保存的前置条件是「名称非空 + 至少一个动作」——旧实现是 `days: const []`
///    静默建空计划，用户得再进详情逐个补；这一页把动线收进一屏，**没内容就
///    存不下来**；
/// ② 落库的 `source` 必须是 `'manual'`（详情页据此显示来源标签）；
/// ③ 取消勾选训练日时该天已排的动作一并撤掉——否则「未选中但仍有动作」的天
///    在保存时到底存不存就没有答案；
/// ④ 「添加动作」弹层里的字段 Key 与训练页详情**同源**（共享件），不新造一套。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 勾选 chips 走 `AnimatedContainer`（AppMotion.fast），按系统「减弱动画」
  // 跑才不用逐帧 pump。
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  late AppDatabase database;
  late ExerciseRepository exercises;
  late WorkoutPlanRepository plans;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await const ExerciseSeedImporter().importIfNeeded(database);
    exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids('ex-user'),
      clock: FixedAppClock(DateTime.utc(2026, 10, 8, 9)),
    );
    plans = WorkoutPlanRepository(
      database: database,
      idGenerator: _Ids('plan'),
      clock: FixedAppClock(DateTime.utc(2026, 10, 8, 9)),
    );
  });

  tearDown(() async {
    await database.close();
  });

  Widget host({VoidCallback? onCreated}) => MaterialApp(
    theme: AppTheme.light(),
    home: WorkoutPlanManualPage(
      exerciseRepository: exercises,
      workoutPlanRepository: plans,
      onCreated: onCreated,
    ),
  );

  /// 手机竖屏：默认 800×600 会把这一页的保存按钮挤到屏外。
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
      await tester.pumpAndSettle();
    }
  }

  Future<void> enterName(WidgetTester tester, String name) async {
    await tester.enterText(find.byKey(const Key('manual-plan-name')), name);
    await tester.pumpAndSettle();
  }

  Future<void> toggleWeekday(WidgetTester tester, int weekday) async {
    final finder = find.byKey(Key('manual-plan-weekday-$weekday'));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// 走完「添加动作」弹层：填组次（+ 可选重量）→ 保存。
  ///
  /// **不碰动作下拉**：候选是 312 条种子动作，菜单要滚动才点得到远处的项，
  /// 那是在测 Flutter 的下拉而不是被测页面。弹层的默认值是候选第一条，
  /// 需要名字的断言去 `defaultExerciseName()` 取同一个来源。
  Future<void> addEntry(
    WidgetTester tester, {
    required int dayAddKey,
    String sets = '4',
    String reps = '8',
    String? weight,
  }) async {
    final addKey = Key('manual-plan-day-add-$dayAddKey');
    await scrollTo(tester, find.byKey(addKey));
    await tester.ensureVisible(find.byKey(addKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(addKey));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('training-entry-weekday')),
      findsOneWidget,
      reason: '添加动作弹层必须复用既有字段 Key（共享件，不新造一套）',
    );
    await tester.enterText(find.byKey(const Key('training-entry-sets')), sets);
    await tester.enterText(find.byKey(const Key('training-entry-reps')), reps);
    if (weight != null) {
      await tester.enterText(
        find.byKey(const Key('training-entry-weight')),
        weight,
      );
    }
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('training-entry-save')));
    await tester.pumpAndSettle();
  }

  /// 弹层默认选中的那条动作名（与页面用同一个查询口径取候选）。
  Future<String> defaultExerciseName() async =>
      (await exercises.search('', limit: 200)).first.name;

  Future<void> tapSave(WidgetTester tester) async {
    await scrollTo(tester, find.byKey(const Key('manual-plan-save')));
    await tester.ensureVisible(find.byKey(const Key('manual-plan-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manual-plan-save')));
    await tester.pumpAndSettle();
  }

  group('手动计划页（docs/30 D7）', () {
    testWidgets('空计划存不下来：无名称无动作时保存按钮禁用并说明原因', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      // 旧实现 `days: const []` 建出的就是这种空计划，且没有任何提示。
      await scrollTo(tester, find.byKey(const Key('manual-plan-save')));
      expect(
        find.byKey(const Key('manual-plan-save-hint')),
        findsOneWidget,
        reason: '按钮禁用时必须说明「还差什么」，否则用户只看到一个灰按钮',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('manual-plan-save-hint')))
            .data,
        '填写名称并添加至少一个动作后可保存。',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('manual-plan-empty-hint')))
            .data,
        '先选训练日，再给每天添加动作。',
        reason: '空态如实说明下一步（Key manual-plan-empty-hint）',
      );
      expect(await plans.list(), isEmpty, reason: '什么都没填时页面上没有任何保存路径');
    });

    testWidgets('只填名称、零动作：仍然存不下来，提示改口说「至少一个动作」', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await enterName(tester, '早晨力量');
      await scrollTo(tester, find.byKey(const Key('manual-plan-save-hint')));
      expect(
        tester
            .widget<Text>(find.byKey(const Key('manual-plan-save-hint')))
            .data,
        '至少添加一个动作才能保存。',
        reason: '两个前置条件各自有话说：缺动作时不能沿用「填写名称」那句',
      );
      // 名称字段本身没有任何「先存个壳」的旁路。
      expect(await plans.list(), isEmpty);
    });

    testWidgets('名称 + 一个动作 → 落库 source=manual、名称与组次都对', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await enterName(tester, '早晨力量');
      await toggleWeekday(tester, 1);
      await addEntry(tester, dayAddKey: 1, sets: '4', reps: '8', weight: '60');

      await tapSave(tester);

      final summaries = await plans.list();
      expect(summaries, hasLength(1), reason: '保存后库里应有一条计划');
      expect(summaries.single.name, '早晨力量');
      expect(summaries.single.entryCount, 1, reason: '这一条动作真落到了训练日里');
      // `source` 从详情读（`WorkoutPlanRecord`）——来源标签就长在详情页上，
      // 摘要不带这个字段。
      final record = await plans.getById(summaries.single.id);
      expect(
        record!.source,
        'manual',
        reason: '手动路径必须落 source=manual（详情页据此显示来源标签）',
      );
    });

    testWidgets('落库的计划详情带 source=manual 与正确的星期', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await enterName(tester, '周三腿日');
      await toggleWeekday(tester, 3);
      await addEntry(tester, dayAddKey: 3, sets: '5', reps: '5');
      await tapSave(tester);

      final planId = (await plans.list()).single.id;
      final record = await plans.getById(planId);
      expect(record, isNotNull);
      expect(
        record!.source,
        'manual',
        reason: 'WorkoutPlanRecord 也要带 source——详情页读的是它',
      );
      expect(record.days, hasLength(1));
      expect(
        record.days.single.weekday,
        3,
        reason: '动作落在点「添加动作」的那一天（周三），不是默认的周一',
      );
    });

    testWidgets('重量留空写 null：自重动作不编数字', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await enterName(tester, '自重日');
      await toggleWeekday(tester, 2);
      await addEntry(tester, dayAddKey: 2, sets: '3', reps: '12');

      await tapSave(tester);

      final planId = (await plans.list()).single.id;
      final record = await plans.getById(planId);
      expect(
        record!.days.single.entries.single.targetWeightKg,
        isNull,
        reason: '留空就是「没有这个量」，不能退化成 0kg',
      );
    });

    testWidgets('取消勾选训练日时该天已排的动作一并撤掉', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await enterName(tester, '两天计划');
      await toggleWeekday(tester, 1);
      await addEntry(tester, dayAddKey: 1, sets: '4', reps: '8');
      expect(
        find.byKey(const Key('manual-plan-day-1')),
        findsOneWidget,
        reason: '加了动作后周一应当有一块',
      );

      // 撤掉周一：留着「未选中但仍有动作」的天，保存时到底存不存它没有答案。
      await toggleWeekday(tester, 1);
      expect(
        find.byKey(const Key('manual-plan-day-1')),
        findsNothing,
        reason: '取消勾选必须连该天的动作一起撤掉',
      );
      expect(
        find.byKey(const Key('manual-plan-save-hint')),
        findsOneWidget,
        reason: '动作被撤光后回到「没内容就存不下来」',
      );
    });

    testWidgets('多个训练日 + 多个动作：一次保存全落库，按星期升序', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await enterName(tester, '推拉腿');
      await toggleWeekday(tester, 5);
      await toggleWeekday(tester, 1);
      await addEntry(tester, dayAddKey: 1, sets: '4', reps: '8');
      await addEntry(tester, dayAddKey: 1, sets: '3', reps: '10');
      await addEntry(tester, dayAddKey: 5, sets: '5', reps: '5');

      await tapSave(tester);

      final planId = (await plans.list()).single.id;
      final record = await plans.getById(planId);
      expect(record!.days.map((day) => day.weekday).toList(), [1, 5]);
      expect(record.days.first.entries, hasLength(2));
      expect(record.days.last.entries, hasLength(1));
    });

    testWidgets('保存成功后回调被调用（路由层据此返回上一页）', (tester) async {
      usePhoneViewport(tester);
      var created = 0;
      await tester.pumpWidget(host(onCreated: () => created++));
      await tester.pumpAndSettle();

      await enterName(tester, '回调计划');
      await toggleWeekday(tester, 1);
      await addEntry(tester, dayAddKey: 1, sets: '3', reps: '10');
      await tapSave(tester);

      expect(created, 1, reason: 'onCreated 是路由层唯一的返回信号');
    });

    testWidgets('「添加动作」弹层锁定当天的训练日（不给静默改错的路）', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await toggleWeekday(tester, 4);
      await scrollTo(tester, find.byKey(const Key('manual-plan-day-add-4')));
      await tester.ensureVisible(
        find.byKey(const Key('manual-plan-day-add-4')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manual-plan-day-add-4')));
      await tester.pumpAndSettle();

      // 锁定态仍渲染**同一个 Key** 的节点：断言与读屏都还拿得到「几号训练日」。
      final weekdayNode = find.byKey(const Key('training-entry-weekday'));
      expect(weekdayNode, findsOneWidget);
      expect(
        tester.widget<Text>(weekdayNode).data,
        '周四',
        reason: '从周四的按钮进去，弹层就写周四；换天等于把数字静默记到另一天',
      );
      expect(
        find.byType(DropdownButtonFormField<int>),
        findsNothing,
        reason: '锁定态没有下拉（否则用户以为能换天）',
      );
    });

    testWidgets('动作行显示真实组次与重量（与计划详情同形）', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await enterName(tester, '显示校验');
      await toggleWeekday(tester, 1);
      await addEntry(
        tester,
        dayAddKey: 1,
        sets: '4',
        reps: '8',
        weight: '62.5',
      );

      final name = await defaultExerciseName();
      expect(find.text(name), findsWidgets);
      expect(
        find.text('4 组 × 8 次 · 62.5kg'),
        findsOneWidget,
        reason: '小数重量不能显示成 62.5kg 以外的样子（如 62.5.0kg）',
      );
      expect(
        find.byKey(const Key('manual-plan-entry-remove-1-0')),
        findsOneWidget,
        reason: '每条动作都能单独移除',
      );
    });

    testWidgets('保存时动作已被从库里删掉：错误写在页面上（manual-plan-error），且不落半条计划', (
      tester,
    ) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await enterName(tester, '竞态计划');
      await toggleWeekday(tester, 1);
      await addEntry(tester, dayAddKey: 1, sets: '4', reps: '8');

      // 页面打开后、点保存前，这一条动作从库里消失了（换种子、清库、
      // 另一个入口删掉它都会这样）。仓储会抛 `动作不存在于本地动作库。`
      final selected = (await exercises.search('', limit: 200)).first;
      await (database.delete(
        database.exercises,
      )..where((row) => row.id.equals(selected.id))).go();

      await tapSave(tester);

      // 错误必须出现在**页面上**：`_errorText` 有 Key，用户不会对着一屏
      // 没反应的界面猜发生了什么。
      expect(
        tester
            .widget<AppErrorText>(find.byKey(const Key('manual-plan-error')))
            .message,
        '动作不存在于本地动作库。',
        reason: '仓储的失败原因原样透出，不换成一句含糊的「保存失败」',
      );
      expect(await plans.list(), isEmpty, reason: '整个草稿在一个事务里，失败不得留下半条计划');
    });

    testWidgets('移除动作后回到「没内容就存不下来」', (tester) async {
      usePhoneViewport(tester);
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await enterName(tester, '移除校验');
      await toggleWeekday(tester, 1);
      await addEntry(tester, dayAddKey: 1, sets: '4', reps: '8');
      expect(
        find.byKey(const Key('manual-plan-save-hint')),
        findsNothing,
        reason: '有名称有动作时可保存，不该再出现提示',
      );

      final remove = find.byKey(const Key('manual-plan-entry-remove-1-0'));
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('manual-plan-save-hint')),
        findsOneWidget,
        reason: '唯一动作被移除后，保存重新变得不可用',
      );
      expect(await plans.list(), isEmpty);
    });
  });
}

final class _Ids implements IdGenerator {
  _Ids(this._prefix);

  final String _prefix;
  int _value = 0;

  @override
  String next() => '$_prefix-${_value++}';
}
