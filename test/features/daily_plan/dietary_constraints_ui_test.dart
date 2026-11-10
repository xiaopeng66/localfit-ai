import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/design/widgets/lf_buttons.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/daily_plan/domain/planning_constraints.dart';
import 'package:localfit_ai/features/daily_plan/presentation/dietary_constraints_sheet.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_settings.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';

/// C-2（docs/64 阶段 2）：**饮食约束（素食标签 + 过敏原）可以自己设**。
///
/// 现状证据：模型（`planning_constraints.dart`）与仓储（load/save）现成，
/// 但 `grep planningConstraintsRepository lib/features`（除 ai_conversation）= 0
/// ——唯一写入者是对话命令 `constraints.set`，用户不该为「我花生过敏」去跟
/// AI 说话。
///
/// 契约：**同一张表**（`profiles.dietaryPreferencesJson` /
/// `allergenAvoidancesJson`）——AI 写的约束 UI 打开就能看到，反之亦然；
/// 上限（4 标签 / 9 过敏原）就地报错、不保存。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 26, 12);
  late AppDatabase database;
  late PlanningConstraintsRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = PlanningConstraintsRepository(
      database: database,
      clock: FixedAppClock(now.toUtc()),
    );
    await database
        .into(database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: 'profile-1',
            activityLevel: 'moderate',
            createdAt: now.toUtc(),
            updatedAt: now.toUtc(),
          ),
        );
  });

  tearDown(() => database.close());

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844 * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (pageContext) => Center(
              child: LfTextButton(
                label: '打开',
                onPressed: () => showDietaryConstraintsSheet(
                  pageContext,
                  repository: repository,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('打开'));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  void sheetTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }

  sheetTest('勾素食 + 填「芒果」→ 保存 → load() 读回同一份', (tester) async {
    await pumpSheet(tester);
    expect(find.byKey(const Key('dietary-constraints-sheet')), findsOneWidget);

    await tester.tap(find.text('素食'));
    await tester.enterText(
      find.byKey(const Key('dietary-allergen-input')),
      '芒果',
    );
    await tester.tap(find.byKey(const Key('dietary-allergen-add')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byKey(const Key('dietary-constraints-save')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final saved = await repository.load();
    expect(saved.dietaryLabels.map((item) => item.name), ['vegetarian']);
    expect(saved.allergenAvoidances, ['芒果']);
  });

  testWidgets('设置页入口：行显示当前约束摘要，保存回来重读（不拿旧值）', (tester) async {
    tester.view.physicalSize = const Size(390, 844 * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (pageContext) => SettingsPage(
            settingsStore: _FakeSettingsStore(),
            dietaryConstraintsSummary: () async =>
                (await repository.load()).summaryLabel,
            onOpenDietaryConstraints: () => showDietaryConstraintsSheet(
              pageContext,
              repository: repository,
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 先滚到那一行（设置页很长）。
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-dietary-constraints')),
      300,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
          )
          .first,
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('未设置'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-dietary-constraints')));
    for (var i = 0; i < 14; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.text('素食'));
    await tester.enterText(
      find.byKey(const Key('dietary-allergen-input')),
      '芒果',
    );
    await tester.tap(find.byKey(const Key('dietary-allergen-add')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const Key('dietary-constraints-save')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(
      find.text('素食 · 忌口 1 项'),
      findsOneWidget,
      reason: '弹层保存回来后行必须重读，不许继续显示「未设置」',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  sheetTest('保存后，AI 快照读的那两列确实是这份内容（同一张表）', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('素食'));
    await tester.enterText(
      find.byKey(const Key('dietary-allergen-input')),
      '芒果',
    );
    await tester.tap(find.byKey(const Key('dietary-allergen-add')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const Key('dietary-constraints-save')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // AI 快照（DriftChatEditContextLoader 的「饮食偏好与忌口」段）读的就是
    // profiles 这两列——直接查库钉住「UI 写的与 AI 读的是同一份数据」。
    final row = await (database.select(
      database.profiles,
    )..limit(1)).getSingle();
    expect(row.dietaryPreferencesJson, contains('vegetarian'));
    expect(row.allergenAvoidancesJson, contains('芒果'));
  });

  sheetTest('AI 写的约束，UI 打开就能看到（同一张表）', (tester) async {
    await repository.save(
      const PlanningConstraints(
        dietaryLabels: [DietaryLabel.vegan],
        allergenAvoidances: ['花生'],
      ),
    );
    await pumpSheet(tester);

    // 预置块「纯素」选中；「花生」在固定位置且为选中态（不会跳到末尾）。
    final veganChip = tester.widget<DietaryConstraintChoice>(
      find.byKey(const Key('dietary-label-vegan')),
    );
    expect(veganChip.selected, isTrue, reason: 'AI 写的标签必须在 UI 里是选中态');
    final peanutChip = tester.widget<DietaryConstraintChoice>(
      find.byKey(const Key('dietary-allergen-peanut')),
    );
    expect(peanutChip.selected, isTrue, reason: 'AI 写的花生必须在固定格子里选中');
    expect(find.text('花生'), findsOneWidget, reason: '选中项不从原位置消失，也不复制到末尾');
  });

  sheetTest('超过上限（5 个过敏原 → 第 10 个之后）→ 就地报错、不保存', (tester) async {
    // 先在库里存满 9 个过敏原（上限）。
    await repository.save(
      const PlanningConstraints(
        allergenAvoidances: [
          '芒果',
          '菠萝',
          '草莓',
          '芹菜',
          '芥末',
          '酒精',
          '味精',
          '槟榔',
          '芋头',
        ],
      ),
    );
    await pumpSheet(tester);

    await tester.enterText(
      find.byKey(const Key('dietary-allergen-input')),
      '花生',
    );
    await tester.tap(find.byKey(const Key('dietary-allergen-add')));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.byKey(const Key('dietary-constraints-error')),
      findsOneWidget,
      reason: '超上限必须就地报错',
    );

    await tester.tap(find.byKey(const Key('dietary-constraints-save')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final saved = await repository.load();
    expect(saved.allergenAvoidances, hasLength(9), reason: '报错的那一次不许落库');
  });
}

/// 设置页只需要一个「能 load」的假 store（与 settings_page_test 同口径的最小面）。
final class _FakeSettingsStore implements AiProviderSettingsStore {
  @override
  Future<AiProviderSettings> load() async =>
      AiProviderSettings(configuration: null, hasApiKey: false);

  @override
  Future<void> save(AiProviderSettingsInput input) async {}

  @override
  Future<void> clearApiKey() async {}

  @override
  Future<AiProviderConfiguration?> loadConfiguration() async => null;
}
