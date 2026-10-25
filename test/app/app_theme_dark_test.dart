import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 主题装配审计（docs/21 §2）。旧 `design_test.dart` / `app_tokens_test.dart`
/// 里的主题接线断言在阶段 I-3 一并迁到这里：它们断言的是**主题行为**，
/// 与已被删除的 `App*` token 命名无关，只把取值改指 `Lf*` 单源。
void main() {
  testWidgets('暗色主题按 docs/21 §2.2/§2.7 token 接线（不再 fromSeed 回退）', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const Scaffold()),
    );
    final theme = Theme.of(tester.element(find.byType(Scaffold)));

    expect(theme.colorScheme.primary, const Color(0xFF4ED9A6));
    expect(theme.scaffoldBackgroundColor, const Color(0xFF0F1412));
    expect(theme.appBarTheme.backgroundColor, const Color(0xFF0F1412));
    expect(theme.cardTheme.color, const Color(0xFF171E1A));
    // Round7 A（`styles.css:422` `.form-field input{background:var(--bg)...}`）：
    // 输入框底改成**页面底色**层（暗色 `--bg`=#0F1412），不再是轨道层
    // （旧 docs/21 §2.2 的 muted #1F2823）——A 用它 + 1px 描边表达「内陷格」。
    expect(theme.inputDecorationTheme.fillColor, const Color(0xFF0F1412));
    expect(
      theme.elevatedButtonTheme.style?.backgroundColor?.resolve({}),
      LfSemanticColors.dark.primary,
    );
    expect(theme.snackBarTheme.backgroundColor, const Color(0xFF171E1A));
    // 文本色随亮度解析（旧 design_test.dart 的 textTheme 解析链断言）。
    expect(theme.textTheme.bodyLarge!.color, LfSemanticColors.dark.foreground);
  });

  testWidgets('亮色主题按 docs/21 §2.1 token 接线', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const Scaffold()),
    );
    final theme = Theme.of(tester.element(find.byType(Scaffold)));

    expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F9F8));
    expect(theme.colorScheme.primary, const Color(0xFF2FBE8F));
    expect(theme.colorScheme.error, const Color(0xFFF44336));
    expect(theme.cardTheme.color, const Color(0xFFFFFFFF));
    expect(theme.inputDecorationTheme.fillColor, const Color(0xFFF7F9F8));
    expect(theme.textTheme.bodyLarge!.color, LfSemanticColors.light.foreground);
  });

  test('卡片：16 圆角 + A 的静息面容（亮色透明描边 + 单层 0.02 阴影）', () {
    final light = AppTheme.light();
    final shape = light.cardTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(LfDimens.radiusLg));
    // Round7 A（`refinement.css:3` `.card{border-color:transparent;
    // box-shadow:0 1px 3px #1A201D05}` / `html[data-theme="dark"] .card
    // {border-color:var(--border);box-shadow:none}`）：亮色卡片**没有**描边，
    // 层级靠一条 alpha 5/255 的极轻阴影；暗色反向——有描边、无阴影。
    // 旧的「1px border + `--lf-shadow-1` 双层阴影」是 docs/21 §2.4 时代的形态。
    expect(light.cardTheme.elevation, 0);
    expect(shape.side.color, Colors.transparent);
    expect(light.cardTheme.shadowColor, AppTheme.aCardShadow);
    expect(light.cardTheme.surfaceTintColor, Colors.transparent);
    // 暗色下阴影不可见，层级靠描边分层表达，不靠 elevation。
    final darkTheme = AppTheme.dark();
    final darkShape = darkTheme.cardTheme.shape! as RoundedRectangleBorder;
    expect(darkTheme.cardTheme.elevation, 0);
    expect(darkShape.side.color, LfSemanticColors.dark.border);
    expect(darkTheme.cardTheme.shadowColor, Colors.transparent);
  });

  test('输入框：A 的 form-field 形态（bg 底 + 1dp 描边 + 12 圆角 + 2dp 聚焦环）', () {
    final input = AppTheme.light().inputDecorationTheme;
    expect(input.filled, isTrue);
    // `styles.css:422`：底是 `--bg`（不是 `--track`），常规态**有** 1dp 描边；
    // 圆角 12（refinement 的 `.form-field textarea` 同值）。
    expect(input.fillColor, LfSemanticColors.light.background);
    expect(input.fillColor, isNot(LfSemanticColors.light.muted));
    expect(
      (input.enabledBorder! as OutlineInputBorder).borderRadius,
      BorderRadius.circular(LfDimens.inputRadius),
    );
    expect(LfDimens.inputRadius, 12);
    expect(
      input.enabledBorder!.borderSide,
      BorderSide(color: LfSemanticColors.light.border),
    );
    final focused = input.focusedBorder! as OutlineInputBorder;
    // 聚焦环取 A 的 `--brand-strong`（`refinement.css:9`
    // `:focus-visible{outline:2px solid var(--brand-strong)}`）。
    expect(focused.borderSide.color, LfColors.mintText(Brightness.light));
    expect(focused.borderSide.width, 2.0);
    expect(
      (input.errorBorder! as OutlineInputBorder).borderSide.color,
      LfSemanticColors.light.error,
    );
    // 暗色同样一档：底 `--bg`、描边 `--border`。
    final darkInput = AppTheme.dark().inputDecorationTheme;
    expect(darkInput.fillColor, LfSemanticColors.dark.background);
    expect(
      darkInput.enabledBorder!.borderSide,
      BorderSide(color: LfSemanticColors.dark.border),
    );
  });

  test('主按钮：A 的实心档（h44 / 12 圆角 / brand 底 / 深墨字）', () {
    final button = AppTheme.light().elevatedButtonTheme.style!;
    // A 有效值：`styles.css:147` `.btn{min-height:44px}` + `refinement.css:3`
    // `.btn{border-radius:12px;font-size:14px}` + `.btn.primary{background:
    // var(--brand);color:#10271D}`。旧的「48dp 胶囊/16 圆角 + 白字」是
    // docs/21 §3.8 时代的形态（A 的 48 只出现在弹层/吸底行动，见 B2）。
    expect(button.minimumSize?.resolve({}), const Size(0, 44));
    expect(
      (button.shape?.resolve({})! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(LfDimens.buttonRadius),
    );
    expect(LfDimens.buttonRadius, 12);
    expect(button.backgroundColor?.resolve({}), LfSemanticColors.light.primary);
    expect(
      button.foregroundColor?.resolve({}),
      LfSemanticColors.light.primaryForeground,
    );
    expect(
      button.backgroundColor?.resolve(const {WidgetState.disabled}),
      LfSemanticColors.light.muted,
    );
  });

  test('高对比档：品牌底**不加深**（深墨字下加深会跌破 4.5），改靠 2dp 描边', () {
    // 旧档把 primary 提到 mint-700（#1B8A62）是为了配白字；A 的按钮字是
    // `--lf-primary-foreground`=#10271D，底再加深会让对比从 ~7 掉到 ~3.9，
    // 所以高对比的表达只剩「2dp 前景描边」，底与常档同色。
    expect(
      AppTheme.light(highContrast: true).colorScheme.primary,
      LfSemanticColors.light.primary,
    );
    expect(
      AppTheme.light().colorScheme.primary,
      LfSemanticColors.light.primary,
    );
    final highContrastBorder = AppTheme.light(highContrast: true)
        .inputDecorationTheme
        .enabledBorder!
        .borderSide;
    // 高对比档的可见描边在 A 里加粗到 2dp（`lf` 的 HC 分支）：常态 1dp
    // `--border`，HC 2dp `--fg`——因为 HC 不再靠「加深品牌底」提升对比。
    expect(highContrastBorder.style, BorderStyle.solid);
    expect(highContrastBorder.color, LfSemanticColors.light.foreground);
    expect(highContrastBorder.width, 2);
    expect(AppTheme.dark().colorScheme.primary, LfSemanticColors.dark.primary);
    expect(
      AppTheme.dark(highContrast: true).colorScheme.primary,
      LfSemanticColors.dark.primary,
    );
  });

  test('两组 Lf 扩展按亮度成组注入（identity：漏注入会回落亮色）', () {
    expect(
      AppTheme.dark().extension<LfSemanticColors>(),
      same(LfSemanticColors.dark),
    );
    expect(
      AppTheme.dark().extension<LfComponentColors>(),
      same(LfComponentColors.dark),
    );
    expect(
      AppTheme.light().extension<LfSemanticColors>(),
      same(LfSemanticColors.light),
    );
    expect(
      AppTheme.light(highContrast: true).extension<LfSemanticColors>(),
      same(LfSemanticColors.light),
    );
  });

  test('触达底线：主按钮最小高度 ≥ 44dp（docs/21 §2.7）', () {
    final minSize = AppTheme.light().elevatedButtonTheme.style?.minimumSize
        ?.resolve(const {});
    expect(LfDimens.minTouchTarget, 44);
    expect(minSize?.height, greaterThanOrEqualTo(LfDimens.minTouchTarget));
  });
}
