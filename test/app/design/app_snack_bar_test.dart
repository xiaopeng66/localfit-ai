import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';
import 'package:localfit_ai/app/design/widgets/app_snack_bar.dart';

void main() {
  group('AppSnackBar（docs/21 §3.1：左图标槽 / 操作按钮 / 连续弹合并）', () {
    testWidgets('左图标槽：图标在文案左侧，取 onSnackBar 色（与文案同色）', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      AppSnackBar.show(
        pageContext,
        '已保存到本机。',
        icon: Icons.check_circle_outline,
      );
      await tester.pumpAndSettle();

      expect(find.text('已保存到本机。'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle_outline));
      expect(icon.size, 18);
      expect(icon.color, LfComponentColors.light.onSnackBar);

      // 图标槽在文案左侧：图标右缘不超过文案左缘。
      final iconRect = tester.getRect(find.byIcon(Icons.check_circle_outline));
      final textRect = tester.getRect(find.text('已保存到本机。'));
      expect(iconRect.center.dy, closeTo(textRect.center.dy, 0.5));
      expect(iconRect.right, lessThanOrEqualTo(textRect.left + 0.5));
    });

    testWidgets('不传图标时不占图标槽（纯文案）', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      AppSnackBar.show(pageContext, '计划餐食已安排。');
      await tester.pumpAndSettle();

      expect(find.text('计划餐食已安排。'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Icon)),
        findsNothing,
      );
    });

    testWidgets('操作按钮：撤销 label 渲染为 SnackBarAction 且可点', (tester) async {
      late BuildContext pageContext;
      var undos = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      AppSnackBar.show(
        pageContext,
        '餐食已删除。',
        icon: Icons.delete_outline,
        actionLabel: '撤销',
        onAction: () => undos++,
      );
      await tester.pumpAndSettle();

      expect(find.text('撤销'), findsOneWidget);
      expect(find.byType(SnackBarAction), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(undos, 1);
    });

    testWidgets('连续弹两条：替换式合并，屏上只留最新一条', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      AppSnackBar.show(pageContext, '第一条消息。');
      await tester.pumpAndSettle();
      expect(find.text('第一条消息。'), findsOneWidget);

      AppSnackBar.show(pageContext, '第二条消息。');
      await tester.pumpAndSettle();

      // 替换而非排队：旧条被撤下，最新一条立即顶上（排队实现下此处会
      // 仍显示「第一条消息。」）。
      expect(find.text('第二条消息。'), findsOneWidget);
      expect(find.text('第一条消息。'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('浮岛墨绿底由主题提供（组件不写死颜色）', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      AppSnackBar.show(pageContext, 'AI 配置已仅保存到本机。');
      await tester.pumpAndSettle();

      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.backgroundColor, isNull, reason: '底色交由 snackBarTheme');
      expect(snack.behavior, isNull, reason: '浮动/圆角交由 snackBarTheme');

      final theme = AppTheme.light().snackBarTheme;
      expect(theme.behavior, SnackBarBehavior.floating);
      expect(theme.backgroundColor, LfComponentColors.light.snackBarBackground);
      expect(theme.contentTextStyle?.color, LfComponentColors.light.onSnackBar);
    });
  });

  /// RV4-P1-01 / RV4-P2-01（`docs/57` §3，`docs/58` B2）：
  ///
  /// SDK `SnackBar.persist = persist ?? action != null` —— **只要带 action 就
  /// 默认永不过期**。删除流正好命中：删完一餐，「餐食已删除 + 撤销」永久挂在
  /// 屏幕上。原有的 5 条断言只验证「撤销按钮在且可点」，从不推进时间，
  /// 所以 2856 条测试全绿也抓不到。
  group('RV4-P1-01 · 带 action 的提示条必须会自己消失', () {
    testWidgets('showOn(撤销) 后推进 7 秒 → SnackBar 不在了', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      AppSnackBar.show(
        pageContext,
        '餐食已删除。',
        icon: AppSnackBar.deleteIcon,
        actionLabel: '撤销',
        onAction: () {},
      );
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      // 默认 4s + 退出动画；推到 7s 留足余量。
      await tester.pump(const Duration(seconds: 7));
      await tester.pumpAndSettle();
      expect(
        find.byType(SnackBar),
        findsNothing,
        reason:
            '带 action 的提示条也必须到期消失（SDK 默认 persist=true 是陷阱，'
            'AppSnackBar 必须显式传 persist: false）',
      );
    });

    testWidgets('带 action 时 SnackBar.persist 必须显式为 false', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      AppSnackBar.show(
        pageContext,
        '餐食已删除。',
        actionLabel: '撤销',
        onAction: () {},
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(
        bar.persist,
        isFalse,
        reason: '必须显式传 persist（null 会让 SDK 按 action != null 推断成 true）',
      );
    });

    testWidgets('删除族显式给 6 秒（比默认 4 秒长，不是全局放宽）', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      AppSnackBar.show(
        pageContext,
        '餐食已删除。',
        actionLabel: '撤销',
        onAction: () {},
        duration: const Duration(seconds: 6),
      );
      await tester.pumpAndSettle();

      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, const Duration(seconds: 6));

      // 6 秒后仍在（说明不是被默认 4 秒提前收走），8 秒后消失。
      await tester.pump(const Duration(seconds: 6, milliseconds: 500));
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  /// RV4-P2-01：撤销按钮在墨绿底上「不够跳」——原先无 `actionTextColor`，
  /// 回落到 `ColorScheme.secondary`（与全局强调同色系、12px 无字重）。
  ///
  /// 【计划与 SDK 的差异，如实记录】`docs/58` 写「加 `actionTextStyle`（w600）」，
  /// 但本仓 Flutter 3.47.2 的 `SnackBarThemeData` **没有** `actionTextStyle`
  /// 字段（只有 `actionTextColor` / `actionOverflowThreshold` /
  /// `actionBackgroundColor`），`SnackBarAction` 内部固定把 label 画成
  /// 普通 `Text`。所以字重与字号改为在 `AppSnackBar` 里**显式传
  /// `SnackBarAction.textColor` + 加粗 label 层**实现，主题侧只断言能设的字段。
  /// 按 §6.5「文档与实现冲突以实现为准」登记。
  group('RV4-P2-01 · 撤销动作的文字要够跳', () {
    for (final dark in [false, true]) {
      final mode = dark ? '暗色' : '亮色';

      test('主题（$mode）：actionTextColor 非空、actionOverflowThreshold 0.4', () {
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        final snack = theme.snackBarTheme;
        expect(
          snack.actionTextColor,
          isNotNull,
          reason: '不设就回落 ColorScheme.secondary（与全局强调同色系，不够跳）',
        );
        expect(snack.actionOverflowThreshold, 0.4);
      });

      test('对比度（$mode）：动作色 vs 提示条底色 ≥ 4.5', () {
        final theme = dark ? AppTheme.dark() : AppTheme.light();
        final snack = theme.snackBarTheme;
        final ratio = contrastRatio(
          snack.actionTextColor!,
          snack.backgroundColor!,
        );
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$mode 动作色对比度 $ratio < 4.5',
        );
      });
    }

    testWidgets('撤销动作色显式取专用 token（不再是 ColorScheme.secondary）', (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              pageContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );

      AppSnackBar.show(
        pageContext,
        '餐食已删除。',
        actionLabel: '撤销',
        onAction: () {},
      );
      await tester.pumpAndSettle();

      final action = tester.widget<SnackBarAction>(find.byType(SnackBarAction));
      final expected = AppTheme.light().snackBarTheme.actionTextColor;
      expect(
        action.textColor,
        expected,
        reason: '动作色必须显式传专用 token（SDK 内是普通 Text，不吃正文样式）',
      );
      // 【为什么不断言 w600】本仓 Flutter 3.47.2 的 `SnackBarThemeData` 没有
      // `actionTextStyle` 字段，`SnackBarAction` 内部固定画普通 `Text`——
      // 「加粗」在这一版 SDK 上不可达。计划里的 `actionTextStyle: w600` 按
      // docs/58 §6.5「文档与实现冲突以实现为准」改为「专用高对比动作色 +
      // 溢出阈值」，可读性由下面的对比度断言兜住。
      expect(
        action.textColor,
        isNot(AppTheme.light().colorScheme.secondary),
        reason: '回落 ColorScheme.secondary 就是原来的缺陷（与全局强调同色系）',
      );
    });
  });
}

/// WCAG 2.x 相对亮度对比度（与 `token_contrast_test` 同一口径）。
double contrastRatio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

double _luminance(Color color) {
  double channel(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}
