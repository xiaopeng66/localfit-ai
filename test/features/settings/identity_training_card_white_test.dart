import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/design_card.dart';
import 'package:localfit_ai/data/database/app_database.dart';
import 'package:localfit_ai/features/settings/data/profile_identity_repository.dart';
import 'package:localfit_ai/features/settings/presentation/settings_page.dart';
import 'package:localfit_ai/features/training/presentation/sections/training_hero.dart';
import 'package:localfit_ai/app/design/widgets/user_avatar.dart';

/// docs/30 §2 D5/D6（用户走查需求 5「我的界面的绿色个人信息卡…很丑」+ 需求 6
/// 「训练界面的黑色数据卡…很丑」）的**设计契约**：两张顶部卡从「大色块 +
/// 装饰层」换成标准白 [DesignCard]。
///
/// 与 R4 同一套断言思路——**对着渲染出的颜色/盒子**，而不是 widget 类型名：
/// 换皮最容易犯的错是只换一半（外层白卡、里面仍留白色文字），那种缺陷 Key
/// 一个不少、只能靠截图才发现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(LfDimens.pagePadding),
        child: child,
      ),
    ),
  );

  Color cardBackground(WidgetTester tester, Key cardKey) {
    final material = tester.widget<Material>(
      find
          .descendant(of: find.byKey(cardKey), matching: find.byType(Material))
          .first,
    );
    final color = material.color;
    expect(color, isNotNull, reason: '$cardKey 的卡片底色不得为 null（透明）');
    expect(color!.a, 1.0, reason: '$cardKey 的卡片底色必须不透明');
    return color;
  }

  List<Color> textColors(WidgetTester tester, Key cardKey) {
    final out = <Color>[];
    for (final text in tester.widgetList<Text>(
      find.descendant(of: find.byKey(cardKey), matching: find.byType(Text)),
    )) {
      final color = text.style?.color;
      if (color != null) out.add(color);
    }
    expect(out, isNotEmpty, reason: '$cardKey 上应当有带显式颜色的文字');
    return out;
  }

  void expectNoWhiteText(WidgetTester tester, Key cardKey) {
    final white = LfSemanticColors.light.primaryForeground;
    for (final color in textColors(tester, cardKey)) {
      expect(color, isNot(white), reason: '白卡上的文字不得用 $white（白底白字）');
    }
  }

  group('我的页身份卡（docs/30 D5）', () {
    late AppDatabase database;
    late ProfileIdentityRepository repository;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      repository = ProfileIdentityRepository(database: database);
    });

    tearDown(() async {
      await database.close();
    });

    /// 一个**有生效目标**的资料：这样副标题才有「目标减脂」那一段可断言
    /// （无目标时那段整省，是另一条用例的事）。
    Future<void> seedActiveGoal() async {
      final now = DateTime.utc(2026, 9, 1);
      await database
          .into(database.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: 'identity-profile',
              activityLevel: 'moderate',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.goals)
          .insert(
            GoalsCompanion.insert(
              id: 'identity-goal',
              profileId: 'identity-profile',
              type: 'loseFat',
              calorieMinKcal: 1900,
              calorieMaxKcal: 2100,
              effectiveFrom: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await database
          .into(database.dailyTargets)
          .insert(
            DailyTargetsCompanion.insert(
              id: 'identity-target',
              goalId: 'identity-goal',
              effectiveDate: '2026-09-01',
              calorieMinKcal: 1900,
              calorieMaxKcal: 2100,
              proteinMinGrams: 84,
              proteinMaxGrams: 105,
              carbsMinGrams: 200,
              carbsMaxGrams: 260,
              fatMinGrams: 45,
              fatMaxGrams: 65,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    Widget page({VoidCallback? onEdit}) => host(
      SettingsPage(
        profileIdentityRepository: repository,
        now: DateTime(2026, 9, 12),
        onOpenProfileEdit: onEdit,
      ),
    );

    testWidgets('白卡化：外层是 DesignCard，底色不透明 card，且卡上无任何白色文字', (tester) async {
      await seedActiveGoal();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings-identity-card')), findsOneWidget);
      final background = cardBackground(
        tester,
        const Key('settings-identity-card'),
      );
      expect(background, LfSemanticColors.light.card);
      expectNoWhiteText(tester, const Key('settings-identity-card'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('点纹理与渐变整块退场：**像素级**证明卡面是平的', (tester) async {
      await seedActiveGoal();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      // 为什么不用「卡内不得有 CustomPaint」这种结构断言：`Material` 自己就会
      // 为 InkWell 的水波纹挂一个 CustomPaint，所以那条断言**恒假**（实测 1 个）。
      // 而真正要证明的事是**像素**：旧实现是 `ClipRRect > DecoratedBox(gradient)
      // > Stack > Positioned.fill(_DotTexture)`——14dp 间距、半径 1.0、`card`
      // 10% 白的点阵 + 一条 mint 渐变。白卡化后卡面上的空白区域必须**处处
      // 等于 `light.card`**：任何点或渐变都会让某个采样点偏离这个值。
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find
            .ancestor(
              of: find.byKey(const Key('settings-identity-card')),
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      // **必须包在 `runAsync` 里**：`toImage`/`toByteData` 要真事件循环，
      // 在 `testWidgets` 的 fake-async 区里 await 会**永远不返回**（实测整条
      // 用例卡满 10 分钟超时）。
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return data;
      });
      final data = bytes!.buffer.asUint8List();
      final imageWidth = boundary.size.width.round();
      final card = tester.getRect(
        find.byKey(const Key('settings-identity-card')),
      );
      final origin = boundary.globalToLocal(card.topLeft);
      final cardColor = LfSemanticColors.light.card;
      var sampled = 0;
      // 沿卡片头部那一行的空白带逐像素扫（避开文字与头像：取卡右半边）。
      for (var dx = (card.width * 0.55).round(); dx < card.width - 4; dx += 2) {
        for (var dy = 8; dy < 40; dy += 2) {
          final x = origin.dx.round() + dx;
          final y = origin.dy.round() + dy;
          final i = (y * imageWidth + x) * 4;
          final pixel = Color.fromARGB(
            data[i + 3],
            data[i],
            data[i + 1],
            data[i + 2],
          );
          expect(
            pixel,
            cardColor,
            reason:
                '卡面上的空白区必须处处是纯卡色（$x,$y 处是 $pixel）——'
                '任何点纹理或渐变都会在这里露出来',
          );
          sampled++;
        }
      }
      expect(sampled, greaterThan(100), reason: '采样点太少，断言会空转');

      // 结构层再补一条：卡内不得有任何 `BoxDecoration.gradient`（点纹理可以
      // 伪装成别的绘制器，渐变不会）。
      for (final decorated in tester.widgetList<DecoratedBox>(
        find.descendant(
          of: find.byKey(const Key('settings-identity-card')),
          matching: find.byType(DecoratedBox),
        ),
      )) {
        final decoration = decorated.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.gradient, isNull, reason: '身份卡内不应再有任何渐变');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('头部一行：头像 56dp，姓名在头像右邻，「编辑资料」在行尾（D9 后无副标题）', (tester) async {
      await seedActiveGoal();
      await tester.pumpWidget(page(onEdit: () {}));
      await tester.pumpAndSettle();

      final avatar = find.byKey(const Key('settings-avatar'));
      expect(avatar, findsOneWidget);
      // 头像 56（旧实现 64）：卡的第一行只有「我是谁」这一件事，56 已是
      // 视觉重心的上限（列表项图标 40、分类图标 40）。
      // D9：尺寸由调用方给 `UserAvatar(size: 56)`——直接量该组件的盒子。
      final avatarBox = tester.getRect(find.byType(UserAvatar));
      expect(avatarBox.width, 56);
      expect(avatarBox.height, 56);

      // 头像底 = mint-100（不再是半透明白：白卡上无物可透）。
      final avatarMaterial = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(UserAvatar),
              matching: find.byWidgetPredicate(
                (w) => w is Container && w.decoration is BoxDecoration,
              ),
            )
            .first,
      );
      final decoration = avatarMaterial.decoration! as BoxDecoration;
      expect(decoration.color, LfColors.mintLight.tone(100));
      // D9：形状由 `UserAvatar.circle` 决定（默认圆形，圆角 = size/2）。
      expect(
        decoration.borderRadius,
        BorderRadius.circular(28),
        reason: '56dp 圆 = size/2 圆角',
      );

      // docs/32 §3 D9：姓名在头像**右邻**（同一行）；**副标题已删**。
      // `find.text('Fit')` 会同时命中头像里那两个字与姓名文本，挑没有 Key 的那个。
      final name = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data == 'Fit' && widget.key == null,
        ),
      );
      expect(name.left, greaterThanOrEqualTo(avatarBox.right));
      expect(
        find.byKey(const Key('settings-identity-subtitle')),
        findsNothing,
        reason: 'D9：副标题整行删除',
      );
      // 「编辑资料」在行尾（它的左边缘在姓名右边缘之后）。
      final edit = tester.getRect(find.byKey(const Key('cta-edit-profile')));
      expect(edit.left, greaterThan(name.right - 1));
      // 垂直居中（D9：头像与昵称块中心等高）——几何断言。
      expect(
        (avatarBox.center.dy - name.center.dy).abs(),
        lessThan(1.0),
        reason: 'D9：头像与昵称必须垂直居中对齐',
      );
      // 编辑钮走 B6 文字钮（不是旧的手写半透明药丸）：它自己不带不透明底色。
      final editMaterial = tester.widgetList<Material>(
        find.descendant(
          of: find.byKey(const Key('cta-edit-profile')),
          matching: find.byType(Material),
        ),
      );
      for (final material in editMaterial) {
        expect(
          material.color?.a ?? 0.0,
          0.0,
          reason: 'B6 是纯文字钮：不得带实底（旧药丸是 onHero α0.15 的半透明底）',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('三段统计带 1px 分隔线，数字与标签分别是卡前景/次级色', (tester) async {
      await seedActiveGoal();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('settings-identity-card'));
      // 两段之间各一条 1dp 竖线（三段 → 两条）。
      final dividers = tester
          .widgetList<Container>(
            find.descendant(of: card, matching: find.byType(Container)),
          )
          .where((container) {
            final decoration = container.decoration;
            return container.constraints?.maxWidth == 1 ||
                (decoration is BoxDecoration &&
                    decoration.color != null &&
                    container.constraints?.maxWidth == 1);
          })
          .length;
      expect(dividers, 2, reason: '三段统计之间必须有 2 条分隔线');

      final stat = find.byKey(const Key('settings-stat-records'));
      final valueText = tester.widget<Text>(
        find.descendant(of: stat, matching: find.byType(Text)).first,
      );
      expect(valueText.style!.color, LfSemanticColors.light.cardForeground);
      final labelText = tester.widget<Text>(
        find.descendant(of: stat, matching: find.byType(Text)).last,
      );
      expect(labelText.style!.color, LfSemanticColors.light.mutedForeground);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });

    testWidgets('头像字用 mint-700（浅底上的品牌字色），不是 primary', (tester) async {
      await seedActiveGoal();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      // docs/32 §3 D9：头像改共享件 `UserAvatar`——`settings-avatar` 现在是
      // 外层可点容器，首字母在它内部（`settings-avatar-initial`）。
      final avatarText = tester.widget<Text>(
        find.byKey(const Key('settings-avatar-initial')),
      );
      // 直接取 `primary`（#2FBE8F）在 mint-100 上对比约 2.2:1，不足；
      // `LfColors.mintText` 才是「浅底上的品牌字色」这一档（mint-700）。
      expect(avatarText.style!.color, LfColors.mintText(Brightness.light));
      expect(avatarText.style!.color, isNot(LfSemanticColors.light.primary));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  });

  group('训练页顶部卡（docs/30 D6）', () {
    Widget hero({
      int finishedCount = 4,
      Duration duration = const Duration(minutes: 168),
      int? weekIndex = 38,
      List<int> capacity = const [30, 0, 45, 0, 60, 0, 0],
      int todayIndex = 4,
      List<int> rest = const [2, 4, 7],
    }) => host(
      TrainingHero(
        weekIndex: weekIndex,
        finishedCount: finishedCount,
        totalDuration: duration,
        totalKcal: null,
        capacityMinutes: capacity,
        todayIndex: todayIndex,
        restWeekdays: rest,
      ),
    );

    testWidgets('白卡化：外层是 DesignCard，底色不透明 card，且卡上无任何白色文字', (tester) async {
      await tester.pumpWidget(hero());
      await tester.pumpAndSettle();

      expect(find.byType(DesignCard), findsOneWidget);
      final background = cardBackground(tester, const Key('training-hero'));
      expect(background, LfSemanticColors.light.card);
      expectNoWhiteText(tester, const Key('training-hero'));
    });

    testWidgets('不再自己吃顶部叠层：注入状态栏后卡片位置一动不动（留白由页面给）', (tester) async {
      // 这是 D6 与旧契约的**分界点**。旧实现读 `LfInsets.top(context)` 把内容
      // 推下去（色块自己铺到 y=0）；新实现把这件事交给页面的
      // `pagePadding + LfInsets.top`。所以本 widget 的判据是**对叠层不敏感**：
      // 同一个 widget 在 0 / 48 两种叠层下，卡片顶边与标题位置必须完全相同。
      //
      // 用「位置相同」而不是「位置 == 某常量」来断言，是因为后者只能验证
      // 当前这一版排布，前者验证的是**职责边界**——那正是这次改动的实质。
      Future<({double cardTop, double titleTop, double cardLeft, double width})>
      measure(double inset) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: EdgeInsets.only(top: inset),
                  viewPadding: EdgeInsets.only(top: inset),
                ),
                child: Scaffold(
                  // 复刻页面排布：外层只有页面留白，**不含叠层**——叠层由
                  // 页面另加，本 widget 不许自己消费它。
                  body: Padding(
                    padding: const EdgeInsets.all(LfDimens.pagePadding),
                    child: TrainingHero(
                      weekIndex: 38,
                      finishedCount: 4,
                      totalDuration: const Duration(minutes: 168),
                      totalKcal: null,
                      capacityMinutes: const [30, 0, 45, 0, 60, 0, 0],
                      todayIndex: 4,
                      restWeekdays: const [2, 4, 7],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final card = tester.getRect(find.byKey(const Key('training-hero')));
        return (
          cardTop: card.top,
          titleTop: tester
              .getTopLeft(find.byKey(const Key('training-title')))
              .dy,
          cardLeft: card.left,
          width: card.width,
        );
      }

      final plain = await measure(0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final shifted = await measure(48);

      expect(shifted.cardTop, plain.cardTop, reason: '卡片自己不得再消费顶部叠层（那是页面的职责）');
      expect(shifted.titleTop, plain.titleTop);
      // 左右留白 = 外层 host 的 16（本 widget 自己又给了一层 16，所以卡片
      // 相对屏幕的左边距是 32；**关键是有留白，不是铺满屏宽**）。
      expect(plain.cardLeft, greaterThan(0), reason: '卡片不得贴屏幕左边');
      // 外层的 2×16（页面留白）之外，本 widget 自己又给了一层 2×16，所以
      // 卡片比屏幕窄 4×16。旧实现是 `width: double.infinity` 的色块（与外层
      // 同宽）——这条断言就是拦它回来的。
      final hostWidth = tester.getSize(find.byType(Scaffold).first).width;
      expect(
        plain.width,
        closeTo(hostWidth - LfDimens.pagePadding * 4, 1),
        reason: '卡片必须比外层容器再窄 2×16（不再铺满）',
      );
      expect(
        plain.cardTop,
        greaterThanOrEqualTo(LfDimens.pagePadding),
        reason: '卡片顶边至少要有页面留白',
      );
    });

    testWidgets('30px 数值与三段 Key 全保留（白卡化不动字阶、不动契约）', (tester) async {
      await tester.pumpWidget(hero());
      await tester.pumpAndSettle();

      for (final key in [
        'training-hero-count',
        'training-hero-duration',
        'training-hero-kcal',
        'training-capacity-chart',
        'training-rest-legend',
        'training-hero-week',
        'training-title',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      // displayHero 30：这张卡的量级感来源，白卡化不许把它调小。
      final valueText = tester.widget<Text>(
        find
            .descendant(
              of: find.byKey(const Key('training-hero-count')),
              matching: find.byType(Text),
            )
            .first,
      );
      expect(valueText.style!.fontSize, 30);
      expect(valueText.style!.color, LfSemanticColors.light.cardForeground);
      // 无数据源的热量仍写「—」，不编数字（§6.1）。
      expect(
        tester
            .widget<Text>(
              find
                  .descendant(
                    of: find.byKey(const Key('training-hero-kcal')),
                    matching: find.byType(Text),
                  )
                  .first,
            )
            .data,
        '—',
      );
    });

    testWidgets('容量图白底配色：今日比其余训练日更深，无训练日是 muted', (tester) async {
      await tester.pumpWidget(hero());
      await tester.pumpAndSettle();

      // 7 根柱。**2026-10-15 结构迁移**（Round7 阶段 4 · 缺陷 ⑳）：柱体从
      // `Container` 改成 `DecoratedBox`——旧写法用 `FractionallySizedBox`
      // + `minHeight` 表达最小柱，而 `heightFactor: 0` 会把 `minHeight` 一并
      // 压成 0（无训练日那一列在白卡上空白）；现在高度显式算（空日 3px、
      // 有训练下限 6px）。**本判据的三条颜色断言一字未改**，只换取件方式。
      final bars = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(const Key('training-capacity-chart')),
              matching: find.byType(DecoratedBox),
            ),
          )
          .where((box) {
            final decoration = box.decoration;
            return decoration is BoxDecoration && decoration.color != null;
          })
          .toList();
      expect(bars.length, 7, reason: '容量图恒 7 柱');
      final colors = [
        for (final bar in bars) (bar.decoration as BoxDecoration).color,
      ];
      final mint = LfColors.mintLight;
      // 索引 4 = 周五 = todayIndex（capacity 第 5 项 60 分钟）。
      expect(
        colors[4],
        mint.tone(600),
        reason:
            '今日柱用 mint-600：白底上「更饱和 = 更近」，'
            '旧实现的 mint-300（更浅）在近黑底上成立、在白底上会读成'
            '「今天最不重要」',
      );
      // 训练日（索引 0/2）用 mint-400。
      expect(colors[0], mint.tone(400));
      expect(colors[2], mint.tone(400));
      // 无训练日（索引 1/3/5/6）：`muted`，不再是对 hero 前景色的 12% 透明
      // （那是「压深色底」的画法，搬到白卡上几乎看不见）。
      for (final i in [1, 3, 5, 6]) {
        expect(colors[i], LfSemanticColors.light.muted, reason: '索引 $i');
      }
    });

    testWidgets('容量图配色不许退回「今日更浅」的旧暗底方案', (tester) async {
      await tester.pumpWidget(hero());
      await tester.pumpAndSettle();

      final mint = LfColors.mintLight;
      final todayLuminance = mint.tone(600).computeLuminance();
      final otherLuminance = mint.tone(400).computeLuminance();
      // 白底（亮度 ≈ 1）上，**更饱和/更深的那个更近**。旧实现今日用 300 档
      // （比 400 更浅）——那条规则只在近黑底上成立。
      expect(
        todayLuminance,
        lessThan(otherLuminance),
        reason: '今日柱必须比其余训练日更深，否则「今天」在白色卡片上读不出来',
      );
    });

    testWidgets('休息日图例来自计划：空列表时整条不渲染（不硬编码二/四/日）', (tester) async {
      await tester.pumpWidget(hero(rest: const []));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('training-rest-legend')), findsNothing);
      expect(find.textContaining('休息日'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pumpWidget(hero(rest: const [3]));
      await tester.pumpAndSettle();
      expect(find.text('休息日 · 三'), findsOneWidget);
    });

    testWidgets('无训练历史：不渲染「第 N 周」，且三段仍齐全', (tester) async {
      await tester.pumpWidget(hero(weekIndex: null));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('training-hero-week')), findsNothing);
      expect(find.byKey(const Key('training-hero-count')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
