@Tags(['capture'])
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/ai_memory/data/ai_memory_repository.dart';
import 'package:localfit_ai/features/ai_memory/domain/ai_memory.dart';
import 'package:localfit_ai/features/ai_memory/presentation/ai_memory_page.dart';

import 'support/round7_render.dart';

/// R-8（记忆页重设计）取帧：真实内存库种三条记忆 → 页面直接 pump，
/// 320×2.0 与 412×1.0 各一张，逐张自看后归档。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AI 记忆页（320×2.0 与 412×1.0）', (tester) async {
    await tester.runAsync(loadRound7Fonts);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final database = AppDatabase(NativeDatabase.memory());
    final repository = AiMemoryRepository(
      database: database,
      clock: FixedAppClock(DateTime.utc(2026, 10, 24, 2)),
      idGenerator: _Ids(),
    );
    await tester.runAsync(() async {
      await repository.remember(
        text: '沟通偏好：确认份量后喜欢直接记住，若记录没显示会要求重记，关注记录是否真正写入。',
        kind: AiMemoryKind.preference,
      );
      await repository.remember(
        text: '常去食堂窗口：东苑一楼快餐窗口，常见菜有汉堡、鸡蛋等。',
        kind: AiMemoryKind.fact,
      );
      await repository.remember(
        text: '用餐记录习惯：常把拍照的食堂餐食按早餐/午餐/晚餐/加餐分餐次记录。',
        kind: AiMemoryKind.habit,
      );
    });

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
              home: AiMemoryPage(repository: repository),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureRound7(tester, 'review2-ai-memory-$tag');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await database.close();
  });
}

final class _Ids implements IdGenerator {
  int _value = 0;

  @override
  String next() => 'mem-${_value++}';
}
