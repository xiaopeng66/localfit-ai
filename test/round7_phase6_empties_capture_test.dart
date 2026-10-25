import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/features/nutrition/presentation/sections/menu_dish_list.dart';
import 'package:localfit_ai/features/training/data/exercise_repository.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/presentation/exercise_library_page.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:drift/native.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/app/design/widgets/lf_empty_state.dart';

import 'support/round7_render.dart';

/// Round7 阶段 6 · 缺陷 ㉓ 的空态帧：菜单 tab 空态（浅/深）+ 动作库无匹配空态。
///
/// 这三处是本轮从旧 `AppEmptyState`（80dp 渐变圆 + emoji）换成 `LfEmptyState`
/// （A `.empty-state`：52 R18 `brand-soft` 图标块）的**可审看**证据——菜单的
/// 24 帧矩阵有种子数据、不含空态，故单独出帧。
void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await const ExerciseSeedImporter().importIfNeeded(database);
  });
  tearDown(() => database.close());

  Future<void> pumpTree(
    WidgetTester tester,
    Widget page, {
    required bool dark,
    double width = 390,
    double height = 844,
    double scale = 1,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
    tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
    await tester.pumpWidget(
      RepaintBoundary(
        key: round7Boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: round7CaptureTheme(dark ? AppTheme.dark() : AppTheme.light()),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(body: page),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('空态帧：菜单 tab（浅/深）+ 动作库无匹配（3 帧）', (tester) async {
    await tester.runAsync(loadRound7Fonts);

    for (final (dark, name) in [
      (false, 'menu-empty-light-360-1.0'),
      (true, 'menu-empty-dark-360-1.0'),
    ]) {
      await pumpTree(
        tester,
        const MenuDishList(repository: null),
        dark: dark,
        width: 360,
        height: 844,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(LfEmptyState), findsOneWidget);
      await captureRound7(tester, name);
    }

    final exercises = ExerciseRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime(2026, 10, 15, 10)),
    );
    await pumpTree(
      tester,
      ExerciseLibraryPage(repository: exercises),
      dark: false,
      width: 390,
      height: 900,
    );
    await tester.enterText(
      find.byKey(const Key('training-exercise-search')),
      'zzzz-no-match',
    );
    await tester.pump(ExerciseLibraryPage.searchDebounce);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(LfEmptyState), findsOneWidget);
    await captureRound7(tester, 'library-empty-light-390-1.0');

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
  });
}

final class _Ids implements IdGenerator {
  int _v = 0;
  @override
  String next() => 'pe-${_v++}';
}
