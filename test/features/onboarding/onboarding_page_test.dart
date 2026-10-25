import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/features/onboarding/domain/complete_onboarding.dart';
import 'package:localfit_ai/features/onboarding/presentation/onboarding_page.dart';
import 'package:localfit_ai/features/onboarding/domain/nutrition_target_calculator.dart';

void main() {
  testWidgets('requires valid fields before showing the target review', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.onboarding,
        completeOnboarding: (_) => Future.error('must not save'),
      ),
    );
    await tester.pumpAndSettle();

    final submit = find.byKey(const Key('onboarding-submit')).last;
    await tester.tap(submit);
    await tester.pump();

    expect(find.text('请填写年龄'), findsOneWidget);
    expect(find.text('请填写身高'), findsOneWidget);
    expect(find.text('请填写当前体重'), findsOneWidget);
    expect(find.text('结果仅供日常健康管理参考，不能替代医生、营养师或专业教练。'), findsOneWidget);
  });

  testWidgets(
    'shows professional guidance and does not calculate risky plans',
    (tester) async {
      var saved = false;
      tester.view.physicalSize = const Size(900, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        LocalFitApp(
          initialLocation: AppRoutes.onboarding,
          completeOnboarding: (_) async {
            saved = true;
            throw StateError('must not save');
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(_field('年龄'), '30');
      await tester.enterText(_field('身高'), '165');
      await tester.enterText(_field('当前体重'), '65');
      await _scrollTo(tester, find.byKey(const Key('onboarding-chronic-risk')));
      await tester.tap(find.byKey(const Key('onboarding-chronic-risk')));
      await tester.tap(find.byKey(const Key('onboarding-submit')).last);
      await tester.pumpAndSettle();

      expect(find.text('请先寻求专业帮助'), findsOneWidget);
      expect(find.textContaining('请先咨询医生或注册营养师'), findsOneWidget);
      expect(find.text('确认每日目标'), findsNothing);
      expect(saved, isFalse);
    },
  );

  testWidgets('validates malformed optional target weight', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.onboarding,
        completeOnboarding: (_) => Future.error('must not save'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_field('年龄'), '30');
    await tester.enterText(_field('身高'), '165');
    await tester.enterText(_field('当前体重'), '65');
    await tester.enterText(_field('目标体重'), 'not-a-number');
    // 主行动固定在底部（T15），只需把承载错误文案的字段滚进构建范围。
    await _scrollTo(tester, _field('目标体重'));
    await tester.tap(find.byKey(const Key('onboarding-submit')).last);
    await tester.pump();

    expect(find.text('请输入有效数值'), findsOneWidget);
    expect(find.text('确认每日目标'), findsNothing);
  });

  testWidgets('rejects a fractional age with a localized message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.onboarding,
        completeOnboarding: (_) => Future.error('must not save'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_field('年龄'), '30.5');
    await tester.enterText(_field('身高'), '165');
    await tester.enterText(_field('当前体重'), '65');
    // 年龄错误文案在表单首屏区域内，主行动固定在底部 ⇒ 无需滚动。
    await tester.tap(find.byKey(const Key('onboarding-submit')).last);
    await tester.pump();

    expect(find.text('年龄必须是整数'), findsOneWidget);
    expect(find.text('确认每日目标'), findsNothing);
  });

  testWidgets('reviews, confirms and saves an onboarding profile', (
    tester,
  ) async {
    OnboardingInput? saved;
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      LocalFitApp(
        initialLocation: AppRoutes.onboarding,
        completeOnboarding: (input) async {
          saved = input;
          return const NutritionTarget(
            bmrKcal: 1699,
            tdeeKcal: 2633,
            calorieMinKcal: 2126,
            calorieMaxKcal: 2350,
            proteinMinGrams: 120,
            proteinMaxGrams: 150,
            carbsMinGrams: 200,
            carbsMaxGrams: 300,
            fatMinGrams: 53,
            fatMaxGrams: 75,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(_field('年龄'), '30');
    await tester.enterText(_field('身高'), '175');
    await tester.enterText(_field('当前体重'), '75');
    await _scrollTo(tester, find.text('男性'));
    await tester.tap(find.text('男性'));
    final submit = find.byKey(const Key('onboarding-submit')).last;
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('确认每日目标'), findsOneWidget);
    expect(find.textContaining('热量'), findsOneWidget);

    final haptics = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.tap(find.text('确认保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(saved, isNotNull);
    expect(saved!.age, 30);
    expect(saved!.biologicalSex, BiologicalSex.male);
    // docs/21 §2.9：完成档案触发首次庆祝（每会话最多 1 次）。
    expect(find.byKey(const Key('app-celebration-painter')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('热量、营养目标和今日训练将在这里汇总。'), findsOneWidget);
    expect(haptics, contains('HapticFeedbackType.mediumImpact'));
  });

  testWidgets('目标大卡吞没变形：springStandard 380ms + easeOutBack，选中 1.0/未选 0.97', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingPage(completeOnboarding: (_) async => throw 'unused'),
      ),
    );
    await tester.pumpAndSettle();

    AnimatedContainer containerOf(String label) =>
        tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
    AnimatedScale scaleOf(String label) => tester.widget<AnimatedScale>(
      find
          .ancestor(of: find.text(label), matching: find.byType(AnimatedScale))
          .first,
    );

    // 初始：减脂选中。
    final loseFat = containerOf('减脂');
    expect(loseFat.duration, AppMotion.springStandardDuration);
    expect(loseFat.curve, Curves.easeOutBack);
    expect(scaleOf('减脂').scale, 1.0);
    expect(scaleOf('增肌').scale, 0.97);

    // 切换到增肌：吞没变形参数不变，选中态位移。
    await tester.tap(find.text('增肌'));
    await tester.pumpAndSettle();
    expect(containerOf('增肌').duration, AppMotion.springStandardDuration);
    expect(scaleOf('增肌').scale, 1.0);
    expect(scaleOf('减脂').scale, 0.97);
    final decoration = containerOf('增肌').decoration! as BoxDecoration;
    expect(decoration.color, LfColors.mintLight.tone(50));
  });

  testWidgets('减弱动画：目标大卡直接呈现终态（无变形过程）', (tester) async {
    // 长表单在默认 800×600 视口里目标卡落在构建范围外（数值字段标签移到
    // 框外后表单更高）；给足高度让卡片真的渲染出来。
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: OnboardingPage(completeOnboarding: (_) async => throw 'unused'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('减脂'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(container.duration, Duration.zero);
    final scale = tester.widget<AnimatedScale>(
      find
          .ancestor(of: find.text('减脂'), matching: find.byType(AnimatedScale))
          .first,
    );
    expect(scale.duration, Duration.zero);
  });
}

/// 按字段名取输入框：数值字段走 `AppNumberField`（docs/21 §3.3），标签在
/// 框外、`InputDecoration.labelText` 已不再承载字段名，所以按字段自己的
/// Key 定位（页面用 `onboarding-<字段名>` 作为 Key）。
Finder _field(String label) => find.byKey(Key('onboarding-$label'));

/// 滚到目标可见后再操作。
///
/// 数值字段的标签移到框外后每个字段多一行，长表单比原来高；目标卡与安全
/// 筛查行会落在这些测试的固定视口外。真实用户也是滚动过去的。
///
/// 2026-10-13（docs/32 §4 T15）：主行动已移入固定底部行动区 ⇒ 需要滚动的
/// 只剩**表单里的字段/行**，`onboarding-submit` 一行都不用滚。
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}
