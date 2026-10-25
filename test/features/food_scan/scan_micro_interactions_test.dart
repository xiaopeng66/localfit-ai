import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/design/widgets/app_button_states.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/features/food_scan/domain/meal_image.dart';
import 'package:localfit_ai/features/food_scan/presentation/food_scan_widgets.dart';

const _fakeImage = PreparedMealImage(
  path: '/nonexistent/meal.jpg',
  width: 100,
  height: 100,
  byteLength: 1,
);

void main() {
  group('识别中：照片呼吸缩放 + 三行骨架（docs/21 §3）', () {
    testWidgets('照片在树、呼吸缩放层在跑、三行骨架、原文案保留', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScanRecognitionProgressCard(
              image: _fakeImage,
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byKey(const Key('scan-recognizing')), findsOneWidget);
      // 原文案逐字不变。
      expect(find.text('正在发送并分析当前图片…'), findsOneWidget);
      expect(find.text('不会自动重试；取消后本地预览会保留。'), findsOneWidget);
      expect(find.text('取消分析'), findsOneWidget);
      expect(find.byKey(const Key('scan-cancel-recognition')), findsOneWidget);

      // 照片 + 呼吸缩放层。
      expect(find.byType(Image), findsOneWidget);
      expect(
        find.ancestor(of: find.byType(Image), matching: find.byType(Transform)),
        findsOneWidget,
        reason: '识别中照片呼吸缩放',
      );

      // 三行骨架。
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('减弱动画：照片静止、骨架静态对色', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: ScanRecognitionProgressCard(
                image: _fakeImage,
                onCancel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(
        find.ancestor(of: find.byType(Image), matching: find.byType(Transform)),
        findsNothing,
        reason: '减弱动画下照片不呼吸',
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('保存成功卡：mint100 闪现 + ✓ 弹簧（docs/21 §3）', () {
    testWidgets('✓ 包在弹簧组件里，闪现后停在 mint100', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ScanSuccessCard(message: '餐食已保存到本机，并已计入今日统计。')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const Key('scan-success')), findsOneWidget);
      expect(find.text('餐食已保存到本机，并已计入今日统计。'), findsOneWidget);
      expect(find.byType(AppSuccessCheck), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byIcon(Icons.check_circle),
          matching: find.byType(AppSuccessCheck),
        ),
        findsOneWidget,
      );

      // 闪现结束（600ms）后背景停在 mint100。
      await tester.pumpAndSettle();
      final box = tester.widget<DecoratedBox>(
        find.byKey(const Key('scan-success')),
      );
      expect(
        (box.decoration as BoxDecoration).color,
        LfSemanticColors.light.evidenceA,
      );
    });

    testWidgets('减弱动画：直接 mint100，无闪现动画', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: Scaffold(
              body: ScanSuccessCard(message: '餐食已保存到本机，并已计入今日统计。'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final box = tester.widget<DecoratedBox>(
        find.byKey(const Key('scan-success')),
      );
      expect(
        (box.decoration as BoxDecoration).color,
        LfSemanticColors.light.evidenceA,
      );
    });
  });
}
