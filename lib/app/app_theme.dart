import 'package:flutter/material.dart';
import 'package:localfit_ai/app/design/app_motion.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

abstract final class AppTheme {
  /// A 的静息卡阴影（`refinement.css:3` `.card{box-shadow:0 1px 3px #1A201D05}`）
  /// ——单层、alpha 5/255。`DesignCard` 画的同一条。
  static const aCardShadow = Color(0x051A201D);

  static ThemeData light({bool highContrast = false}) =>
      _theme(Brightness.light, highContrast: highContrast);

  static ThemeData dark({bool highContrast = false}) =>
      _theme(Brightness.dark, highContrast: highContrast);

  static ThemeData _theme(Brightness brightness, {required bool highContrast}) {
    final isLight = brightness == Brightness.light;
    final lf = isLight ? LfSemanticColors.light : LfSemanticColors.dark;
    final lfc = isLight ? LfComponentColors.light : LfComponentColors.dark;
    final accent = LfColors.mintText(brightness);
    final soft = LfColors.brandSoft(brightness);
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: lf.primary,
      onPrimary: lf.primaryForeground,
      primaryContainer: soft,
      onPrimaryContainer: accent,
      secondary: lf.primary,
      onSecondary: lf.primaryForeground,
      secondaryContainer: soft,
      onSecondaryContainer: accent,
      tertiary: lf.primary,
      onTertiary: lf.primaryForeground,
      tertiaryContainer: lf.carbs100,
      onTertiaryContainer: lf.cardForeground,
      error: lf.error,
      onError: lf.errorForeground,
      surface: lf.card,
      onSurface: lf.foreground,
      surfaceContainerLowest: lf.card,
      surfaceContainerLow: lf.card,
      surfaceContainer: lf.card,
      surfaceContainerHigh: lf.card,
      surfaceContainerHighest: lf.muted,
      onSurfaceVariant: lf.mutedForeground,
      outline: lf.border,
      outlineVariant: lf.border,
      inverseSurface: lf.foreground,
      onInverseSurface: lf.background,
    );
    final textTheme = TextTheme(
      displayLarge: LfText.displayHero,
      displayMedium: LfText.displayXLarge,
      displaySmall: LfText.displayLarge,
      headlineLarge: LfText.displayLarge,
      headlineMedium: LfText.displayLarge,
      headlineSmall: LfText.headline,
      titleLarge: LfText.headline,
      titleMedium: LfText.titleLarge,
      titleSmall: LfText.title,
      bodyLarge: LfText.body,
      bodyMedium: LfText.body,
      bodySmall: LfText.caption,
      labelLarge: LfText.bodyStrong,
      labelMedium: LfText.captionStrong,
      labelSmall: LfText.label,
    ).apply(bodyColor: lf.foreground, displayColor: lf.foreground);
    final solidFill = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.disabled) ? lf.muted : lf.primary,
    );
    final solidForeground = WidgetStateProperty.resolveWith<Color?>(
      (states) => states.contains(WidgetState.disabled)
          ? lf.mutedForeground
          : lf.primaryForeground,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(LfDimens.buttonRadius),
    );
    final solidStyle = ButtonStyle(
      backgroundColor: solidFill,
      foregroundColor: solidForeground,
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      shape: WidgetStatePropertyAll(buttonShape),
      textStyle: WidgetStatePropertyAll(LfText.bodyStrong),
      elevation: const WidgetStatePropertyAll(0),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      side: highContrast
          ? WidgetStatePropertyAll(BorderSide(color: lf.foreground, width: 2))
          : null,
    );
    OutlineInputBorder inputBorder(BorderSide side) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(LfDimens.inputRadius),
      borderSide: side,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      extensions: [lf, lfc],
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeUpwardTransitionsBuilder(),
          TargetPlatform.iOS: _FadeUpwardTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: lf.background,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: lf.background,
        foregroundColor: lf.foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // 【为什么**不**写 `titleTextStyle`】（Round7 阶段 5 · 缺陷 ㉒，渲染审看
        // 抓到）：写死一份自建 `TextStyle`（`LfText.headline`）时，`AppBar` 会
        // 用它**替换**环境 `DefaultTextStyle`——而 `LfText.*` 按本仓口径
        // **不带字体族**（字体族用平台默认 CJK）⇒ 测试引擎里标题渲染成
        // `.notdef` 空方框（与 ⑫ 的 `ButtonStyleButton`、⑮ 的 `ListTile` 同族
        // 同因；真机靠系统兜底看不出来）。留空则走 M3 默认：`titleTextStyle`
        // = `textTheme.titleLarge`（本主题里就是 `LfText.headline`，字阶一字
        // 不差）⇒ **族随主题**，测试与真机一致。全仓 10 处裸 `AppBar`
        // （`app_router`、引导、计划、AI 画廊…）都吃这一条。
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lf.card,
        indicatorColor: soft,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: lf.card,
        // A 有效值（`refinement.css:3`）：亮色 `.card{border-color:transparent;
        // box-shadow:0 1px 3px #1A201D05}`、深色 `html[data-theme="dark"] .card
        // {border-color:var(--border);box-shadow:none}`。裸 `Card` 若被用到，
        // 观感必须与 `DesignCard` 同形，不再有 M3 基线阴影。
        shadowColor: isLight ? aCardShadow : Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LfDimens.radiusLg),
          side: BorderSide(color: isLight ? Colors.transparent : lf.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // A `styles.css:422` `.form-field input{border-radius:12px;
        // background:var(--bg);border:1px solid var(--border);height:48px}`
        // （refinement 只改 label 字号）——填色是**页面底色**而不是轨道色，
        // 常规态有可见 1dp 描边；聚焦环换 `--brand-strong`（refinement:9
        // `:focus-visible{outline:2px solid var(--brand-strong)}`）。
        fillColor: lf.background,
        floatingLabelBehavior: FloatingLabelBehavior.never,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        hintStyle: LfText.body.copyWith(color: lf.mutedForeground),
        helperStyle: LfText.caption.copyWith(color: lf.mutedForeground),
        errorStyle: LfText.caption.copyWith(color: lf.error),
        errorMaxLines: 4,
        helperMaxLines: 4,
        border: inputBorder(BorderSide(color: lf.border)),
        enabledBorder: inputBorder(
          highContrast
              ? BorderSide(color: lf.foreground, width: 2)
              : BorderSide(color: lf.border),
        ),
        focusedBorder: inputBorder(BorderSide(color: accent, width: 2)),
        errorBorder: inputBorder(BorderSide(color: lf.error)),
        focusedErrorBorder: inputBorder(BorderSide(color: lf.error, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: solidStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: solidStyle),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? lf.mutedForeground
                : accent,
          ),
          textStyle: WidgetStatePropertyAll(
            LfText.body.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(lf.foreground),
          side: WidgetStatePropertyAll(BorderSide(color: lf.border)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(buttonShape),
          textStyle: WidgetStatePropertyAll(LfText.bodyStrong),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(lf.mutedForeground),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lf.muted,
        selectedColor: soft,
        disabledColor: lf.muted,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
        labelStyle: LfText.captionStrong.copyWith(color: lf.foreground),
        secondaryLabelStyle: LfText.captionStrong.copyWith(color: accent),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: lf.mutedForeground,
        textColor: lf.cardForeground,
        // 【为什么要 `.merge(textTheme…)`】（Round7 阶段 6 · 缺陷 ㉔，渲染审看
        // 抓到）：`ListTile` 用 `titleTextStyle/subtitleTextStyle` **替换**
        // 环境 `DefaultTextStyle`（不是合并），而 `LfText.*` 按本仓口径
        // **不带字体族**（字体族用平台默认 CJK）⇒ 标题/副标题在测试帧里渲染成
        // `.notdef` 空方框（`RadioListTile` 的选项、各处 `ListTile` 同吃这一条；
        // 与 ⑫ 的 `ButtonStyleButton`、㉒ 的 `AppBar` 同族同因）。merge 只补
        // 字体族，字号/字重仍由 `LfText` 说了算。
        titleTextStyle: textTheme.bodyLarge!.merge(
          LfText.body.copyWith(color: lf.cardForeground),
        ),
        subtitleTextStyle: textTheme.bodySmall!.merge(
          LfText.caption.copyWith(color: lf.mutedForeground),
        ),
      ),
      dividerTheme: DividerThemeData(color: lf.border, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: lf.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LfDimens.radiusLg),
          side: BorderSide(color: lf.border),
        ),
        titleTextStyle: LfText.headline.copyWith(color: lf.foreground),
        contentTextStyle: LfText.body.copyWith(color: lf.mutedForeground),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: lf.card,
        modalBackgroundColor: lf.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: lf.border,
        dragHandleSize: const Size(32, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(LfDimens.sheetRadius),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: lf.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LfDimens.radiusLg),
        ),
        textStyle: LfText.body.copyWith(color: lf.foreground),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: lf.primary,
        linearTrackColor: lfc.ringTrack,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: lfc.snackBarBackground,
          borderRadius: BorderRadius.circular(LfDimens.radiusSm),
        ),
        textStyle: LfText.caption.copyWith(color: lfc.onSnackBar),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: lf.primary,
        foregroundColor: lf.primaryForeground,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lfc.snackBarBackground,
        contentTextStyle: LfText.body.copyWith(color: lfc.onSnackBar),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LfDimens.radiusLg),
        ),
        // RV4-P2-01（docs/57 §3）：撤销动作原先回落到 `ColorScheme.secondary`
        // ——与全局强调同色系、在黑底上「不够跳」。
        //
        // 【亮/暗两档不是同一个 tone】mint ramp 的暗色只覆盖 50–400，且
        // 300 档本身就是**深色**（#2A3A32，对提示条底 #171E1A 只有 1.41:1，
        // 实测红过）。所以亮色取 300（#6FDBB0 ≈ 9.9:1）、暗色取 400
        // （#4ED9A6 ≈ 8.5:1）——两边都远超 4.5，并与正文白字拉开层次。
        actionTextColor: LfColors.mint(brightness)
            .tone(brightness == Brightness.dark ? 400 : 300),
        // 长文案时动作换行而不是被压成省略号（撤销只有两个字，阈值给宽）。
        actionOverflowThreshold: 0.4,
      ),
    );
  }
}

class _FadeUpwardTransitionsBuilder extends PageTransitionsBuilder {
  const _FadeUpwardTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.01),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
