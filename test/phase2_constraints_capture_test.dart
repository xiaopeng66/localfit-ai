@Tags(['capture'])
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/daily_plan/data/planning_constraints_repository.dart';
import 'package:localfit_ai/features/daily_plan/presentation/dietary_constraints_sheet.dart';

import 'support/round7_render.dart';

/// 阶段 2（docs/64 C-2）取帧件：设置页「饮食约束」弹层（已选态 + 报错态）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 26, 12);
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
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

  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> shot(WidgetTester tester, String name, Key sentinel) async {
    expect(tester.takeException(), isNull, reason: '$name：布局溢出');
    expect(find.byKey(sentinel), findsOneWidget, reason: '$name：关键件不在帧内');
    await captureRound7(tester, name);
  }

  testWidgets('C-2 饮食约束弹层：预置标签 + 自由忌口', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    final repository = PlanningConstraintsRepository(
      database: database,
      clock: FixedAppClock(now.toUtc()),
    );
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(412 * 2, 950 * 2);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: const Size(412, 950)),
        child: RepaintBoundary(
          key: round7Boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: round7CaptureTheme(AppTheme.light()),
            home: Scaffold(
              body: Builder(
                builder: (pageContext) => Center(
                  child: FilledButton(
                    onPressed: () => showDietaryConstraintsSheet(
                      pageContext,
                      repository: repository,
                    ),
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('打开'));
    await settle(tester);

    await tester.tap(find.text('素食'));
    await tester.tap(find.text('无乳制品'));
    await tester.enterText(
      find.byKey(const Key('dietary-allergen-input')),
      '芒果',
    );
    await tester.tap(find.byKey(const Key('dietary-allergen-add')));
    await settle(tester, 4);
    await shot(
      tester,
      'fix2-dietary-constraints',
      const Key('dietary-constraints-sheet'),
    );

    // 报错态：再点预置过敏原把第 11 项塞进去（9 上限）。
    for (var i = 0; i < 9; i++) {
      await tester.enterText(
        find.byKey(const Key('dietary-allergen-input')),
        '忌口${i + 1}',
      );
      await tester.tap(find.byKey(const Key('dietary-allergen-add')));
      await settle(tester, 2);
    }
    await shot(
      tester,
      'fix2-dietary-constraints-limit',
      const Key('dietary-constraints-error'),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
