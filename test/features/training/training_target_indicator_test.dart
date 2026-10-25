import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/features/training/presentation/sections/training_target_indicator.dart';

/// 训练达标指标（docs/21 §5.1 第 5 项）。
///
/// 锁住两件事：计数文案是「已完成/计划」的原始事实，且语义色按是否达标切换
/// （达标=成功绿、未达标=警告橙）——颜色不是唯一表达，数值同时在场。
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  testWidgets('展示已完成/计划计数与单位', (tester) async {
    await pump(
      tester,
      const TrainingTargetIndicator(
        label: '今日计划',
        completed: 3,
        total: 5,
        unit: '个动作',
      ),
    );

    expect(find.text('今日计划'), findsOneWidget);
    expect(find.text('3/5 个动作'), findsOneWidget);
  });

  testWidgets('达标用成功色，未达标用警告色', (tester) async {
    await pump(
      tester,
      const TrainingTargetIndicator(label: '本周计划', completed: 4, total: 6),
    );
    // 未达标：进度条填充应为警告色（与成功色不同）。
    final notMet = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(FractionallySizedBox),
            matching: find.byType(ColoredBox),
          )
          .first,
    );

    await pump(
      tester,
      const TrainingTargetIndicator(label: '本周计划', completed: 6, total: 6),
    );
    final met = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(FractionallySizedBox),
            matching: find.byType(ColoredBox),
          )
          .first,
    );

    expect(
      met.color,
      isNot(notMet.color),
      reason: '达标与未达标必须用不同语义色（成功绿 vs 警告橙）',
    );
  });

  testWidgets('没有计划（total <= 0）不显示 0/0 的进度', (tester) async {
    await pump(
      tester,
      const TrainingTargetIndicator(label: '本周计划', completed: 0, total: 0),
    );

    expect(find.text('—'), findsOneWidget);
    expect(find.textContaining('0/0'), findsNothing);
    // 分母为 0 不得让进度条宽度变成 NaN 或越界。
    final fraction = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fraction.widthFactor, 0.0);
  });

  testWidgets('超额完成时进度条封顶在 1.0，不越界绘制', (tester) async {
    await pump(
      tester,
      const TrainingTargetIndicator(label: '本周计划', completed: 9, total: 6),
    );

    final fraction = tester.widget<FractionallySizedBox>(
      find.byType(FractionallySizedBox),
    );
    expect(fraction.widthFactor, 1.0);
    // 计数仍显示真实事实（9/6），不裁剪成 6/6。
    expect(find.text('9/6 天'), findsOneWidget);
  });
}
