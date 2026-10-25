import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_router.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/localfit_app.dart';
import 'package:localfit_ai/core/ids/id_generator.dart';
import 'package:localfit_ai/core/time/app_clock.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/nutrition/data/food_repository.dart';
import 'package:localfit_ai/features/nutrition/data/meal_repository.dart';

/// 新底栏契约（docs/21 §3.6 / §4.1 / §5.8.4，**视觉值按 Round7 A 有效层叠**）：
/// 贴底 64dp 直角栏（border-t + card 95% + backdrop-blur，五槽 px-2），
/// 中央 AI 凸起圆 56dp（A `refinement.css:3` `.nav-ai .nav-icon`：实心 `--brand`
/// + 5dp `--card` 描边 + `#10271D` sparkles），**净上凸 9.5dp**（位移量 16 是
/// CSS margin，不是视觉量）。
///
/// 历史教训（docs/21 §5.8.4）：凸起圆曾因玻璃层裁剪 + 槽位盒不覆盖上凸带
/// 出现「看得见但点不到」。本文件同时验证可见性（像素为证）与命中区
/// （上凸带 tapAt），两项分别断言。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late FoodRepository foodRepository;
  late MealRepository mealRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    final clock = FixedAppClock(DateTime(2026, 9, 17, 12).toUtc());
    foodRepository = FoodRepository(
      database: database,
      idGenerator: const _FixedIdGenerator(),
      clock: clock,
    );
    mealRepository = MealRepository(
      database: database,
      idGenerator: const _FixedIdGenerator(),
      clock: clock,
    );
  });

  tearDown(() => database.close());

  Widget app() => LocalFitApp(
    initialLocation: AppRoutes.dashboard,
    foodRepository: foodRepository,
    mealRepository: mealRepository,
    now: DateTime(2026, 9, 17, 12),
  );

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  /// 卸载树：Dashboard 的跨零点 rollover Timer 在树销毁时才取消，
  /// 不卸载会挂「Timer is still pending」。
  Future<void> unmountApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('底栏为贴底直角栏：BackdropFilter + card 95% + 顶部描边', (tester) async {
    await pumpApp(tester);

    final nav = find.byKey(const Key('lf-bottom-nav'));
    expect(nav, findsOneWidget);
    // blur 包着键容器：从键向外找祖先。
    final blur = tester.widget<BackdropFilter>(
      find.ancestor(of: nav, matching: find.byType(BackdropFilter)),
    );
    expect(blur.filter, isA<ImageFilter>());

    // 贴底满宽直角（非旧悬浮胶囊）：无圆角裁剪器。
    expect(
      find.ancestor(of: nav, matching: find.byType(ClipRRect)),
      findsNothing,
    );

    final barContainer = tester.widget<Container>(nav);
    final decoration = barContainer.decoration! as BoxDecoration;
    // 亮色 card #FFFFFF 95%。
    expect(decoration.color, const Color(0xFFFFFFFF).withValues(alpha: 0.95));
    expect(decoration.border!.top.color, const Color(0xFFDDE5E1));
    await unmountApp(tester);
  });

  // 【语义变更，2026-10-25 用户：「软件删除夜间模式，白天晚上都是一个样式」】
  //
  // 原来这条钉的是「系统切暗色 → 底栏用暗色 card #171E1A」。
  // 夜间模式已按用户要求删除（`MaterialApp.themeMode` 固定 `light`），
  // 所以判据反转：**系统是暗色时，底栏仍是亮色 card**——那才是
  // 「白天晚上一个样式」的可测含义。
  testWidgets('系统切暗色时底栏仍是亮色（夜间模式已删，白天晚上同一样式）', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(
      () => tester.platformDispatcher.clearPlatformBrightnessTestValue(),
    );
    await pumpApp(tester);

    final barContainer = tester.widget<Container>(
      find.byKey(const Key('lf-bottom-nav')),
    );
    final decoration = barContainer.decoration! as BoxDecoration;
    expect(
      decoration.color,
      isNot(const Color(0xFF171E1A).withValues(alpha: 0.95)),
      reason: '系统暗色不该再让底栏变成暗色（夜间模式已删除）',
    );
    // 亮色主题的 `card` 是纯白（`LfSemanticColors.light.card == #FFFFFF`），
    // 底栏用它的 95% 不透明度。
    expect(
      decoration.color,
      const Color(0xFFFFFFFF).withValues(alpha: 0.95),
      reason: '底栏应当仍用亮色主题的 card（纯白 95%）——白天晚上一个样式',
    );
    await unmountApp(tester);
  });

  testWidgets('旧 mint 滑动胶囊指示器取消（docs/21 §3.6）', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const Key('nav-indicator-capsule')), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('五槽键齐全，标签与图标对齐设计稿（home/utensils/AI/dumbbell/user）', (
    tester,
  ) async {
    await pumpApp(tester);

    // 页面正文也可能出现同名词（如今日页问候），槽位断言用「至少一个」。
    expect(find.text('今日'), findsWidgets);
    expect(find.text('饮食'), findsWidgets);
    expect(find.text('AI'), findsWidgets);
    expect(find.text('训练'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
    // 页面正文可能复用同图标（今日页统计行等），用「至少一个」。
    expect(find.byIcon(Icons.home_outlined), findsWidgets);
    expect(find.byIcon(Icons.restaurant_outlined), findsWidgets);
    expect(find.byIcon(Icons.fitness_center_outlined), findsWidgets);
    expect(find.byIcon(Icons.person_outline), findsWidgets);
    // 凸起圆内是 sparkles 图标：A 有效值（`refinement.css:3`
    // `.nav-ai .nav-icon{...background:var(--brand);color:#10271D}`）——实心品牌底
    // 配**深墨字** `#10271D`（= `--lf-primary-foreground`），不再是旧稿的白图标
    // （旧稿底是 mint-600→700 渐变，白字才有对比；底换成 brand 后白字对比不足）。
    final sparkles = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('nav-ai-workbench')),
        matching: find.byIcon(Icons.auto_awesome),
      ),
    );
    expect(sparkles.color, LfSemanticColors.light.primaryForeground);
    expect(find.byKey(const Key('nav-dashboard')), findsOneWidget);
    expect(find.byKey(const Key('nav-nutrition')), findsOneWidget);
    expect(find.byKey(const Key('nav-training')), findsOneWidget);
    expect(find.byKey(const Key('nav-settings')), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('中央凸起圆 56dp 正圆：实心 brand 底 + 5dp card 描边（Round7 A）', (
    tester,
  ) async {
    await pumpApp(tester);

    final bump = find.byKey(const Key('nav-ai-workbench'));
    final rect = tester.getRect(bump);
    expect(rect.width, LfDimens.navBumpSize);
    expect(rect.height, LfDimens.navBumpSize);
    expect(rect.width, rect.height, reason: '正圆：宽高必须相等');

    final container = tester.widget<Container>(
      find
          .descendant(
            of: bump,
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.decoration is BoxDecoration,
            ),
          )
          .last,
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    // A 有效值：`refinement.css:3` `.nav-ai .nav-icon{width:46px;height:46px;
    // border-width:5px;box-sizing:content-box;background:var(--brand);
    // color:#10271D}` → 46+2×5 = 56 的实心圆，5dp 描边取 `--card`
    // （= 栏体底色，视觉上「贴在栏上」）；旧稿的 135° 渐变 + 双层白/彩阴影
    // 已被 A 覆盖。渐变与阴影必须**真的没有**——否则会把栏顶那条 1px 描边盖住。
    expect(decoration.color, LfSemanticColors.light.primary);
    expect(decoration.gradient, isNull);
    expect(decoration.boxShadow, isNull);
    final border = decoration.border! as Border;
    expect(border.top.width, 5);
    expect(border.top.color, LfSemanticColors.light.card);
    await unmountApp(tester);
  });

  testWidgets('凸起圆上凸完整可见：9.5dp 净上凸 + 无裁剪祖先 + 像素为证 + 上凸带可点', (tester) async {
    await pumpApp(tester);

    final bump = find.byKey(const Key('nav-ai-workbench'));
    final bar = find.byKey(const Key('lf-bottom-nav'));
    final bumpRect = tester.getRect(bump);
    final barRect = tester.getRect(bar);

    // ① 几何：圆顶高出栏顶 9.5dp（docs/21 §5.8.4 实测；不是 CSS 的 16）。
    expect(
      barRect.top - bumpRect.top,
      closeTo(LfDimens.navBumpProtrusion, 0.01),
      reason: '净视觉上凸必须是实测的 9.5dp（按 16 校验会得到 6.5dp 假超标）',
    );

    // ② 机制：祖先链上不得有「会削到圆顶」的裁剪器。问渲染层的
    // `describeApproximatePaintClip`（返回的是裁剪后可见区）：
    // 可见区顶边高于圆顶 = 顶部被削掉。getRect 是布局矩形，糊弄不了
    // 本断言——这正是历史上「拍照钮上半部分看不到」的根因审计法。
    final cuts = _clippingAncestorsCuttingAbove(
      tester.renderObject<RenderObject>(bump),
      bumpRect.top,
    );
    expect(cuts, isEmpty, reason: '这些裁剪祖先会把圆顶削平：\n${cuts.join('\n')}');

    // ③ 像素：栏顶之上、凸起圆中心列必须真的画出薄荷绿。
    final captured = await tester.binding.runAsync<ui.Image?>(
      () => captureImage(find.byType(MaterialApp).evaluate().single),
    );
    if (captured == null) {
      fail('captureImage 返回 null');
    }
    final pixels = await tester.binding.runAsync<ByteData?>(
      () => captured.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    if (pixels == null) {
      fail('toByteData 返回 null');
    }
    final sampleY = (barRect.top - 3).round();
    final buttonColumn = bumpRect.center.dx.round();
    final controlColumn = barRect.left.round() + 8;
    final buttonPixel = _rgbAt(pixels, captured.width, buttonColumn, sampleY);
    final controlPixel = _rgbAt(pixels, captured.width, controlColumn, sampleY);
    expect(
      _isMint(buttonPixel),
      isTrue,
      reason:
          '栏顶之上 3dp（y=$sampleY）的凸起圆中心列应是薄荷绿圆顶，'
          '实测 #${buttonPixel.toRadixString(16).padLeft(6, '0')}（被削平时这里是页面底色）',
    );
    expect(
      _isMint(controlPixel),
      isFalse,
      reason:
          '对照列（远离凸起圆）不该是薄荷绿，否则说明取样位置本身有问题：'
          '#${controlPixel.toRadixString(16).padLeft(6, '0')}',
    );
    captured.dispose();

    // ④ 可点：上凸带里的点必须命中凸起圆（不是死区）。
    await tester.tapAt(Offset(bumpRect.center.dx, barRect.top - 3));
    await tester.pumpAndSettle();
    expect(
      find.text('AI 对话服务尚未配置，请先在「我的」里完成 AI 服务。'),
      findsOneWidget,
      reason: '上凸带应可点且切到 AI 对话分支（不是「看得见点不到」的死区）',
    );

    await unmountApp(tester);
  });

  testWidgets('中央槽点按切到 AI 对话分支（docs/21 §4.1：中间槽 = AI）', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const Key('nav-ai-workbench')));
    await tester.pumpAndSettle();

    expect(find.text('AI 对话服务尚未配置，请先在「我的」里完成 AI 服务。'), findsOneWidget);
    // 中央槽「AI」标签区也可点（整个槽是一个链接）。
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('AI 对话服务尚未配置，请先在「我的」里完成 AI 服务。'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('外壳 extendBody：页面内容延伸到底栏下方', (tester) async {
    await pumpApp(tester);

    final shellScaffold = tester.widget<Scaffold>(
      find
          .ancestor(
            of: find.byKey(const Key('lf-bottom-nav')),
            matching: find.byType(Scaffold),
          )
          .first,
    );
    expect(shellScaffold.extendBody, isTrue);
    await unmountApp(tester);
  });

  testWidgets('普通槽位选中态：图标与标签均 brand-strong 文字绿 + w600（Round7 A）', (
    tester,
  ) async {
    await pumpApp(tester);

    // A `styles.css:115` `.nav-item[aria-current="page"]{color:var(--brand-strong);
    // font-weight:600}` + `refinement.css:1` `--brand-strong:#187653`
    // （= `LfColors.mintText(Brightness.light)`）。旧稿用**实心主按钮那种**
    // primary（#2FBE8F）画选中态——在 card 底上它是文字，对比不足，A 已改。
    final selected = LfColors.mintText(Brightness.light);
    final unselected = LfSemanticColors.light.mutedForeground;
    expect(
      selected,
      isNot(LfSemanticColors.light.primary),
      reason: 'A 的选中态与实心档不同色，两者搞混等于没做这档',
    );

    final homeIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('nav-dashboard')),
        matching: find.byIcon(Icons.home_outlined),
      ),
    );
    expect(homeIcon.color, selected);

    await tester.tap(find.byKey(const Key('nav-nutrition')));
    await tester.pumpAndSettle();

    final restaurantIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('nav-nutrition')),
        matching: find.byIcon(Icons.restaurant_outlined),
      ),
    );
    expect(restaurantIcon.color, selected);
    final homeAfter = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const Key('nav-dashboard')),
        matching: find.byIcon(Icons.home_outlined),
      ),
    );
    expect(homeAfter.color, unselected);

    // 标签同色，并且**选中加粗到 w600**（A 的 `font-weight:600`）——
    // 只换色不加粗的话，10px 小字在彩色下更糊，层次反而比旧稿差。
    TextStyle labelStyle(String text) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(
              Key(text == '饮食' ? 'nav-nutrition' : 'nav-dashboard'),
            ),
            matching: find.text(text),
          ),
        )
        .style!;
    expect(labelStyle('饮食').color, selected);
    expect(labelStyle('饮食').fontWeight, FontWeight.w600);
    expect(labelStyle('今日').color, unselected);
    expect(labelStyle('今日').fontWeight, FontWeight.w400);

    // 中央 AI 槽在 A 里也是 `.nav-item`（`styles.css:117-119`），
    // `aria-current="page"` 时同样吃 brand-strong + w600。
    await tester.tap(find.byKey(const Key('nav-ai-workbench')));
    await tester.pumpAndSettle();
    final aiLabel = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const Key('lf-bottom-nav')),
            matching: find.text('AI'),
          ),
        )
        .style!;
    expect(aiLabel.color, selected, reason: 'AI 槽选中时标签点亮，与其余四槽一致');
    expect(aiLabel.fontWeight, FontWeight.w600);
    await unmountApp(tester);
  });
}

final class _FixedIdGenerator implements IdGenerator {
  const _FixedIdGenerator();

  @override
  String next() => 'nav-test-id';
}

/// 列出会削到 [top] 以上（含）的裁剪祖先，每项是「渲染对象 + 裁剪矩形」。
///
/// 不看 widget 类型而是问渲染对象 `describeApproximatePaintClip`：它正是
/// Flutter 自己回答「这个子节点会不会被裁」的接口。它返回的是**裁剪后
/// 仍然可见**的区域，所以「可见区顶边低于子节点顶边」= 子节点顶部被削掉。
List<String> _clippingAncestorsCuttingAbove(RenderObject target, double top) {
  final offenders = <String>[];
  RenderObject? child = target;
  for (RenderObject? node = target.parent; node != null; node = node.parent) {
    final currentChild = child!;
    final clip = node.describeApproximatePaintClip(currentChild);
    if (clip != null) {
      final globalClip = MatrixUtils.transformRect(
        node.getTransformTo(null),
        clip,
      );
      if (globalClip.top > top) {
        final creator = node.debugCreator;
        offenders.add(
          '${node.runtimeType}'
          '${creator is Element ? '(${creator.widget.runtimeType})' : ''}: '
          '可见区顶边 ${globalClip.top} > 凸起圆顶边 $top',
        );
      }
    }
    child = node;
  }
  return offenders;
}

/// [rawRgba] 里 (x, y) 处的颜色（0xRRGGBB）。
int _rgbAt(ByteData rawRgba, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  final r = rawRgba.getUint8(offset);
  final g = rawRgba.getUint8(offset + 1);
  final b = rawRgba.getUint8(offset + 2);
  return (r << 16) | (g << 8) | b;
}

/// 薄荷绿判据：G 通道显著高于 R，且整体偏亮。
///
/// 用「关系」而不是精确色值：凸起圆是 mint-500→mint-600 渐变（上浅下深），
/// 加上背景描边与抗锯齿，任何等值断言都会随取点位置漂移。
bool _isMint(int rgb) {
  final r = (rgb >> 16) & 0xFF;
  final g = (rgb >> 8) & 0xFF;
  final b = rgb & 0xFF;
  return g > 140 && g - r > 50 && g - b > 15;
}
