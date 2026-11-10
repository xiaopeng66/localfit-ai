@Tags(['capture'])
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/training/data/exercise_seed_importer.dart';
import 'package:localfit_ai/features/training/data/workout_session_repository.dart';
import 'package:localfit_ai/features/training/domain/workout_session.dart';
import 'package:localfit_ai/features/training/presentation/training_page.dart';

import 'support/round7_render.dart';

/// R-5（个人记录图形化）取帧：真实内存库种三条纪录 → 弹层直接 pump，
/// 320×2.0 与 412×1.0 各一张，逐张自看后归档
/// `docs/evidence/2026-10-29-round5/frames/`。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 种子导入与数据库 I/O 都是真实异步：放 runAsync；同时关动效让
  // pumpAndSettle 可收敛（训练页有无限脉冲动画）。
  TestWidgetsFlutterBinding
      .instance
      .platformDispatcher
      .accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  testWidgets('个人纪录卡·三条数据（320×2.0 与 412×1.0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final database = AppDatabase(NativeDatabase.memory());
    // logSet 校验动作必须存在于本地动作库——先种内置动作。
    await tester.runAsync(
      () => const ExerciseSeedImporter().importIfNeeded(database),
    );
    final sessions = WorkoutSessionRepository(
      database: database,
      idGenerator: _Ids(),
      clock: FixedAppClock(DateTime.utc(2026, 10, 28, 10)),
    );
    // 三条纪录：深蹲 60 / 卧推 45 / 划船 40（名次与比例条都各有形态）；
    // 同一动作两次（取更重的那次）验证口径来自真实仓储链路。
    for (final (exercise, weight, reps) in const [
      ('ex-barbell-squat', 60.0, 8),
      ('ex-dumbbell-bench-press', 45.0, 10),
      ('ex-barbell-row', 40.0, 12),
    ]) {
      final id = await sessions.start(localDate: '2026-10-28');
      await sessions.logSet(
        id,
        WorkoutSetDraft(exerciseId: exercise, weightKg: weight, reps: reps),
      );
      await sessions.finish(id);
    }

    for (final (tag, w, ts) in const [
      ('320x2', 320.0, 2.0),
      ('412x1', 412.0, 1.0),
    ]) {
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = Size(w * 2, 900 * 2);
      tester.platformDispatcher.textScaleFactorTestValue = ts;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(w, 900),
            textScaler: TextScaler.linear(ts),
          ),
          child: RepaintBoundary(
            key: round7Boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: round7CaptureTheme(AppTheme.light()),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: PersonalRecordsSheet(sessionRepository: sessions),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureRound7(tester, 'review2-personal-records-$tag');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'cap-${_value++}';
}
