import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/features/settings/application/load_profile_overview.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/settings/presentation/profile_edit_page.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ProfileIdentityRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = ProfileIdentityRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedActiveGoal() async {
    final now = DateTime.utc(2026, 9, 1);
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'identity-profile',
            activityLevel: 'moderate',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.goals)
        .insert(
          GoalsCompanion.insert(
            id: 'identity-goal',
            profileId: 'identity-profile',
            type: 'loseFat',
            calorieMinKcal: 1900,
            calorieMaxKcal: 2100,
            effectiveFrom: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.dailyTargets)
        .insert(
          DailyTargetsCompanion.insert(
            id: 'identity-target',
            goalId: 'identity-goal',
            effectiveDate: '2026-09-01',
            calorieMinKcal: 1900,
            calorieMaxKcal: 2100,
            proteinMinGrams: 84,
            proteinMaxGrams: 105,
            carbsMinGrams: 200,
            carbsMaxGrams: 260,
            fatMinGrams: 45,
            fatMaxGrams: 65,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Widget app() => MaterialApp(
    home: SettingsPage(
      profileIdentityRepository: repository,
      now: DateTime(2026, 9, 12),
    ),
  );

  /// 带派生数据加载器的页面（身份卡三段统计/健康数据/成就都吃它）。
  Widget overviewApp() => MaterialApp(
    home: SettingsPage(
      profileIdentityRepository: repository,
      profileOverviewLoader: LoadProfileOverview(
        database: database,
        clock: FixedAppClock(DateTime.utc(2026, 9, 12, 10)),
      ),
      now: DateTime(2026, 9, 12),
    ),
  );

  /// 一条体重测量（今天）+ 一条餐记录（今天）⇒ streak = 1、总记录 = 1。
  Future<void> seedWeightAndMeal() async {
    final now = DateTime.utc(2026, 9, 12, 10);
    final profile = await (database.select(
      database.profiles,
    )..limit(1)).getSingleOrNull();
    final profileId =
        profile?.id ??
        await database
                .into(database.profiles)
                .insert(
                  ProfilesCompanion.insert(
                    id: 'overview-profile',
                    activityLevel: 'moderate',
                    createdAt: now,
                    updatedAt: now,
                  ),
                )
            as String;
    await database
        .into(database.measurements)
        .insert(
          MeasurementsCompanion.insert(
            id: 'overview-weight',
            profileId: profileId,
            localDate: '2026-09-12',
            weightKg: 65.2,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await database
        .into(database.meals)
        .insert(
          MealsCompanion.insert(
            id: 'overview-meal',
            localDate: '2026-09-12',
            slot: 'lunch',
            eatenAt: now,
            source: 'manual',
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  testWidgets('identity card shows real streak, weight and records', (
    tester,
  ) async {
    await seedActiveGoal();
    await seedWeightAndMeal();
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-identity-card')), findsOneWidget);
    // docs/32 §3 D9（需求 69）：副标题整行**已删除**——用户原话
    // 「昵称下边的已坚持 n 天及后边的句子都删掉」。三段统计仍在（下方断言）。
    expect(
      find.byKey(const Key('settings-identity-subtitle')),
      findsNothing,
      reason: 'D9：副标题整行删除',
    );
    expect(find.textContaining('已坚持'), findsNothing, reason: 'D9：同样不许以别处文本残留');
    // 三段统计全部来自真实库：体重 / 总记录（餐次数） / 连续天数。
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-stat-weight')),
        matching: find.text('65.2 kg'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-stat-records')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-stat-streak')),
        matching: find.text('1 天'),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('identity card falls back when no profile goal exists', (
    tester,
  ) async {
    await tester.pumpWidget(overviewApp());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-identity-card')), findsOneWidget);
    // docs/32 §3 D9：副标题已删（无目标时同样不存在）；三段统计按「无数据」显示。
    expect(find.textContaining('已坚持'), findsNothing, reason: 'D9：副标题整行删除');
    expect(find.byKey(const Key('settings-identity-subtitle')), findsNothing);
    expect(find.byKey(const Key('settings-stat-weight')), findsOneWidget);
    expect(find.text('65.2 kg'), findsNothing);
    // 「目标」断言收在身份卡内：健康数据格的「水分摄入目标」是另一回事。
    expect(
      find.descendant(
        of: find.byKey(const Key('settings-identity-card')),
        matching: find.textContaining('目标'),
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('身份卡「编辑资料」入口：接线时出现且真的调起回调', (tester) async {
    await seedActiveGoal();
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          profileIdentityRepository: repository,
          now: DateTime(2026, 9, 12),
          onOpenProfileEdit: () => opened++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final edit = find.byKey(const Key('cta-edit-profile'));
    expect(edit, findsOneWidget);
    await tester.tap(edit);
    await tester.pump();
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('身份卡未接线时不给编辑入口（避免点了没反应）', (tester) async {
    await seedActiveGoal();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cta-edit-profile')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('ProfileEditPage：改目标经二次确认后才写库', (tester) async {
    await seedActiveGoal();
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditPage(
          repository: repository,
          currentGoal: HealthGoal.loseFat,
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 切到「增肌」并发起保存 → 出现二次确认弹窗。
    await tester.tap(find.text('增肌'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('确认更新个人资料？'), findsOneWidget);

    // 先取消：不得写库。
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    var rows = await database.select(database.goals).get();
    expect(rows.single.type, 'loseFat');

    // 再来一次并确认：这次才写。
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    rows = await database.select(database.goals).get();
    expect(rows.single.type, 'gainMuscle');
  });

  // ── T7（docs/32 §4 T7 / §3 D9）：昵称与头像 ──────────────────────────
  // 2026-10-16（S6，用户「头像和昵称应统一在『编辑资料』界面里更改」）：
  // 昵称/头像的**就地编辑**整族从设置页搬到「编辑资料」页——上面两条
  // 弹层用例随之改写为「身份卡只展示，改在资料页」。
  // 2026-10-16 用户：「我的界面，头像和昵称不要能跳转点击，就在后边的
  // 编辑资料按钮点击就好了」。
  testWidgets('身份卡：头像与昵称都不可点，「编辑资料」是唯一入口', (tester) async {
    await seedActiveGoal();
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          profileIdentityRepository: repository,
          onOpenProfileEdit: () => edits++,
          now: DateTime(2026, 9, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('settings-avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-name')));
    await tester.pumpAndSettle();
    expect(edits, 0, reason: '头像与昵称不再是跳转入口');

    await tester.tap(find.byKey(const Key('cta-edit-profile')));
    await tester.pumpAndSettle();
    expect(edits, 1, reason: '「编辑资料」按钮才是入口');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('身份卡只展示：显示真实昵称与头像首字，改动入口在「编辑资料」', (tester) async {
    await seedActiveGoal();
    await repository.updateDisplayName('李雷');
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          profileIdentityRepository: repository,
          now: DateTime(2026, 9, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 昵称替换硬编码「Fit」；头像显示昵称首字。
    expect(find.text('李雷'), findsOneWidget);
    expect(find.byKey(const Key('settings-name')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('settings-avatar-initial')))
          .data,
      '李',
      reason: 'D9：头像显示昵称首字',
    );
    // 就地弹层已删：点昵称不再开「修改昵称」（那是改在资料页的事）。
    await tester.tap(find.byKey(const Key('settings-name')));
    await tester.pumpAndSettle();
    expect(find.text('修改昵称'), findsNothing);
    expect(find.byKey(const Key('settings-name-field')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('昵称改在「编辑资料」页：预填当前昵称，空输入不写库', (tester) async {
    await seedActiveGoal();
    await repository.updateDisplayName('李雷');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ProfileEditPage(
          repository: repository,
          currentGoal: null,
          onClose: () {},
          now: DateTime(2026, 9, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 预填当前昵称；头像显示首字。
    // 注意 `fieldKey` 挂在内部 `TextFormField` 上（LfTextField 的约定），
    // 所以这里读的是那个字段自己的 controller。
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('profile-display-name')))
          .controller!
          .text,
      '李雷',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('profile-avatar-initial'))).data,
      '李',
    );

    // 空输入保存 = 清除昵称（与设置页原语义一致），且不报错。
    await tester.enterText(
      find.byKey(const Key('profile-display-name')),
      '   ',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect((await repository.loadIdentity())?.displayName, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
