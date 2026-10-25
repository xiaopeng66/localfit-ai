import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/widgets/goal_big_card.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';

/// docs/29 §P1 验收：个人资料页三件（报错 / 身高 / 关闭）。
///
/// 三条用例都从「我的」页身份卡的真实入口 `cta-edit-profile` 出发——只有
/// 走**入口的 push** 才能复现 `GoError: There is nothing to pop`：直接
/// `initialLocation: /profile-edit` 时返回栈同样是空的，测不出方向差异。
///
/// 现场：入口曾用 `GoRouter.go`（替换栈顶），而退出用 `pop`（AppBar 关闭钮 /
/// 保存成功）⇒ 委托层没有可弹出的层级，抛 `GoError: There is nothing to pop`；
/// 该异常发生在 `_save` 的 `try` 内，被 `catch` 捕成「更新失败」——用户看到的
/// 就是「保存时报错」。修法见 docs/29 §P1 / D2：入口改 `push`，并删掉 `_save`
/// 里那一次多余的裸 `Navigator.pop`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  final now = DateTime(2026, 9, 17, 12);

  const profileId = 'profile-1';

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() => database.close());

  /// 建一条档案行：`loadBodyProfile`/`updateBodyProfile` 都以「存在档案行」
  /// 为前提（未建档时静默返回，与 `updateGoal` 同风格）。
  Future<void> seedProfile({
    double? heightCm,
    int? birthYear,
    String? sex,
  }) async {
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: profileId,
            activityLevel: 'sedentary',
            birthYear: Value(birthYear),
            biologicalSex: Value(sex),
            heightCm: Value(heightCm),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.settings,
        profileIdentityRepository: ProfileIdentityRepository(
          database: database,
        ),
        now: now,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openProfileEdit(WidgetTester tester) async {
    final entry = find.byKey(const Key('cta-edit-profile'));
    expect(entry, findsOneWidget, reason: '身份卡「编辑资料」入口不存在');
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(
      find.text('编辑个人资料'),
      findsOneWidget,
      reason: '入口必须落到个人资料编辑页（docs/29 §P1 / D3 页名）',
    );
  }

  Future<void> tapSaveAndConfirm(WidgetTester tester) async {
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('确认更新个人资料？'), findsOneWidget, reason: '保存应弹二次确认');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
  }

  /// drift 的 `QueryStream` 取消会留一个 `Duration.zero` 定时器（
  /// `StreamQueryStore.markAsClosed`），不显式卸载会在框架期末报 pending timer。
  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('① push 进入后保存：不报「更新失败」且退回「我的」页', (tester) async {
    await seedProfile(heightCm: 160, birthYear: 1990, sex: 'female');
    await pumpSettings(tester);
    await openProfileEdit(tester);

    await tester.enterText(find.byKey(const Key('profile-height')), '172');
    await tester.pumpAndSettle();
    await tapSaveAndConfirm(tester);

    // 缺陷现场：`go` 进入 + `pop` 退出抛的 GoError 被 `_save` 捕成「更新失败」。
    expect(find.textContaining('更新失败'), findsNothing);
    expect(find.textContaining('There is nothing to pop'), findsNothing);

    // 保存成功 → 退回上一页（「我的」页身份卡入口重新可见，编辑页已不在）。
    expect(find.byKey(const Key('cta-edit-profile')), findsOneWidget);
    expect(find.text('编辑个人资料'), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('② 保存成功后身高已落库，且未改动字段不被清空', (tester) async {
    await seedProfile(heightCm: 160, birthYear: 1990, sex: 'female');
    await pumpSettings(tester);
    await openProfileEdit(tester);

    // 回填（docs/29 §P1 / D3）：身高 160、年龄 = 2026 − 1990 = 36。
    expect(find.text('160'), findsOneWidget, reason: '已建档身高必须回填');
    expect(find.text('36'), findsOneWidget, reason: '出生年必须回填为年龄');

    await tester.enterText(find.byKey(const Key('profile-height')), '172');
    await tester.pumpAndSettle();
    await tapSaveAndConfirm(tester);

    final row = await database.select(database.profiles).getSingle();
    expect(row.heightCm, 172, reason: '身高必须真的写进 Profiles.heightCm');
    expect(row.birthYear, 1990, reason: '未改动的出生年必须原样写回，不能被清空');
    expect(row.biologicalSex, 'female', reason: '未改动的性别必须原样写回');

    await unmountApp(tester);
  });

  testWidgets('③ 关闭按钮存在且能返回「我的」页', (tester) async {
    await seedProfile(heightCm: 160);
    await pumpSettings(tester);
    await openProfileEdit(tester);

    final close = find.byKey(const Key('profile-edit-close'));
    expect(close, findsOneWidget, reason: 'docs/29 §P1：AppBar 必须有关闭钮');
    await tester.tap(close);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cta-edit-profile')), findsOneWidget);
    expect(find.text('编辑个人资料'), findsNothing);

    await unmountApp(tester);
  });

  testWidgets('④ 当前目标与目标体重被回填，保存不得把它们覆盖成默认值', (tester) async {
    await seedProfile(heightCm: 160, birthYear: 1990, sex: 'female');
    final nowUtc = DateTime.utc(2026, 9, 1);
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'goal-1',
            profileId: profileId,
            type: 'loseFat',
            targetWeightKg: const Value(60.0),
            calorieMinKcal: 1900,
            calorieMaxKcal: 2100,
            effectiveFrom: nowUtc,
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
    await pumpSettings(tester);
    await openProfileEdit(tester);

    // 回填证据：目标大卡停在真实目标「减脂」、目标体重显示 60（不是默认「维持」+ 空）。
    // 2026-10-16：训练目标从三行 `RadioListTile` 换成引导页同款的三张
    // `GoalBigCard`（用户要求），回填的读法随之改读卡片的选中态。
    expect(
      tester
          .widget<GoalBigCard>(find.byKey(const Key('profile-goal-loseFat')))
          .selected,
      isTrue,
      reason: '当前目标必须回填',
    );
    expect(
      tester
          .widget<GoalBigCard>(find.byKey(const Key('profile-goal-maintain')))
          .selected,
      isFalse,
    );
    expect(find.text('60'), findsOneWidget, reason: '目标体重必须回填');

    // 只改身高就保存。
    await tester.enterText(find.byKey(const Key('profile-height')), '172');
    await tester.pumpAndSettle();
    await tapSaveAndConfirm(tester);

    final goal = await database.select(database.goals).getSingle();
    expect(goal.type, 'loseFat', reason: '未改动的目标不得被默认档覆盖');
    expect(goal.targetWeightKg, 60, reason: '未改动的目标体重不得被清空');

    await unmountApp(tester);
  });
}
