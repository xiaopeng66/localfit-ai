import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/core/errors/diagnostic_text.dart';
import 'package:localfit_ai/features/ai/data/ai_protocol_wire.dart';
import 'package:localfit_ai/features/settings/domain/ai_provider_protocol.dart';
import 'package:localfit_ai/features/ai_conversation/domain/degradation_matrix.dart';
import 'package:localfit_ai/features/training/presentation/sections/training_hero.dart';

/// P2 批次 B/D 的判据（2026-10-21）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('RV-P2-13 诊断文本脱敏：抹掉绝对路径并截断', () {
    const raw =
        r'SqliteException: no such table: meals (path E:\AI\Zcode\data\localfit.db)';
    final text = sanitizeDiagnosticText(raw);
    expect(text, isNot(contains(r'E:\AI')));
    expect(text, contains('<path>'));
    expect(sanitizeDiagnosticText('x' * 500).length, lessThanOrEqualTo(161));
  });

  test('RV-P2-17 三协议都能识别「输出被截断」', () {
    expect(
      AiProviderProtocol.chatCompletions.truncationNotice({
        'choices': [
          {'finish_reason': 'length'},
        ],
      }),
      contains('截断'),
    );
    expect(
      AiProviderProtocol.responses.truncationNotice({
        'type': 'response.incomplete',
      }),
      contains('截断'),
    );
    expect(
      AiProviderProtocol.anthropicMessages.truncationNotice({
        'type': 'message_delta',
        'delta': {'stop_reason': 'max_tokens'},
      }),
      contains('截断'),
    );
    // 正常结束不得误报。
    expect(
      AiProviderProtocol.chatCompletions.truncationNotice({
        'choices': [
          {'finish_reason': 'stop'},
        ],
      }),
      isNull,
    );
  });

  test('RV-P2-09 记餐格文案不再把 origin 说成 meal_items 的列', () {
    final cell =
        kDegradationMatrix[DegradationRow.aiNotConfigured]![DegradationColumn
            .mealLogging]!;
    expect(cell.behavior, contains('食堂营养证据'));
    expect(cell.behavior, isNot(contains('手填 origin=user_input')));
  });

  testWidgets('RV-P2-24 减少动画时不启动无限脉冲', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: TrainingHero(
              weekIndex: 1,
              finishedCount: 3,
              totalDuration: const Duration(hours: 2),
              totalKcal: null,
              capacityMinutes: const [30, 45, 60, 20, 0, 0, 0],
              todayIndex: 1,
            ),
          ),
        ),
      ),
    );
    // 减少动画下 pumpAndSettle 必须收敛（无限 repeat 会让它超时）。
    await tester.pumpAndSettle();
    expect(find.byType(TrainingHero), findsOneWidget);
  });

  // 【测试退役】`RV-P2-04 并发 load 结束后状态稳定` 随
  // `NextMealDecisionController` 整族退役删除（`docs/56` R4 / `docs/58` §5
  // 台账）。断言的**对象**（那个控制器的 `loading`/`data`）不存在了。
}
