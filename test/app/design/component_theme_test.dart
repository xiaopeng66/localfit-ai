// 2026-10-14 Round7 A：仅更新视觉期望，保留行为、无障碍与性能约束。

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 主题层契约（docs/21 §3.8/§3.9）：这些槽位原先**全部缺席**，于是 200+ 处
/// 裸 Material 控件直接落在 M3 基线观感上。本套断言把每个槽钉到 Lf token，
/// 顺序与 `app_theme.dart` 的 `_theme()` 一致。
void main() {
  final light = AppTheme.light();
  final dark = AppTheme.dark();
  final lightHighContrast = AppTheme.light(highContrast: true);
  final darkHighContrast = AppTheme.dark(highContrast: true);
  final lfLight = LfSemanticColors.light;
  final lfDark = LfSemanticColors.dark;
  final softLight = LfColors.brandSoft(Brightness.light);

  BorderRadius? radiusOf(ShapeBorder? shape) => shape is RoundedRectangleBorder
      ? shape.borderRadius as BorderRadius?
      : null;

  Color? solidFill(ThemeData theme, [Set<WidgetState> states = const {}]) =>
      theme.filledButtonTheme.style?.backgroundColor?.resolve(states);

  Color? solidForeground(
    ThemeData theme, [
    Set<WidgetState> states = const {},
  ]) => theme.filledButtonTheme.style?.foregroundColor?.resolve(states);

  double contrastRatio(Color a, Color b) {
    final aLuminance = a.computeLuminance();
    final bLuminance = b.computeLuminance();
    return aLuminance > bLuminance
        ? (aLuminance + 0.05) / (bLuminance + 0.05)
        : (bLuminance + 0.05) / (aLuminance + 0.05);
  }

  group('ColorScheme 补全（消掉 M3 回落链漏色）', () {
    test('secondaryContainer 不再是 secondary（.tonal 曾与实心主按钮同色）', () {
      expect(light.colorScheme.secondaryContainer, softLight);
      expect(light.colorScheme.secondary, lfLight.primary);
      // 关键判据：两者必须不同——若漏设，回落链 `secondaryContainer ?? secondary`
      // 会让 `.tonal` 底等于实心档。
      expect(
        light.colorScheme.secondaryContainer,
        isNot(light.colorScheme.secondary),
      );
      expect(
        light.colorScheme.onSecondaryContainer,
        LfColors.mintText(Brightness.light),
      );
    });

    test('次级文字 / 描边 / 浮层底全部锁到 token（原先亮色纯黑、暗色纯白）', () {
      for (final theme in [light, dark]) {
        final lf = theme.brightness == Brightness.light ? lfLight : lfDark;
        expect(theme.colorScheme.onSurfaceVariant, lf.mutedForeground);
        expect(theme.colorScheme.outline, lf.border);
        expect(theme.colorScheme.outlineVariant, lf.border);
        expect(theme.colorScheme.onSurface, lf.foreground);
        expect(theme.colorScheme.surface, lf.card);
      }
      expect(light.colorScheme.onSurfaceVariant, isNot(Colors.black));
      expect(dark.colorScheme.onSurfaceVariant, isNot(Colors.white));
      expect(light.colorScheme.outline, isNot(Colors.black));
      expect(dark.colorScheme.outline, isNot(Colors.white));
    });

    test('每个 surfaceContainer 档位有值（不外泄 M3 基线灰）', () {
      expect(light.colorScheme.surfaceContainerLowest, lfLight.card);
      expect(light.colorScheme.surfaceContainerLow, lfLight.card);
      expect(light.colorScheme.surfaceContainer, lfLight.card);
      expect(light.colorScheme.surfaceContainerHigh, lfLight.card);
      expect(light.colorScheme.surfaceContainerHighest, lfLight.muted);
      expect(dark.colorScheme.surfaceContainerHighest, lfDark.muted);
    });

    test('primary/tertiaryContainer 不再回落到纯品牌色（状态标曾与主按钮同色）', () {
      // 回落链是 `<slot> ?? primary` / `?? tertiary`（`color_scheme.dart` 的
      // getter 逐条核对过，不是 `fromSeed` 那套淡紫）——本主题的
      // `primary = tertiary = 品牌色`，所以「不设」的后果不是漏出 M3 基线，
      // 而是状态标被画成**与主按钮同重的薄荷实心胶囊**，且两个状态同色。
      // 下一餐决策卡与推荐菜单的状态标（原 `_StateChip`）读的正是这两槽。
      for (final theme in [light, dark]) {
        final lf = theme.brightness == Brightness.light ? lfLight : lfDark;
        final soft = LfColors.brandSoft(theme.brightness);
        expect(theme.colorScheme.primaryContainer, soft);
        expect(
          theme.colorScheme.onPrimaryContainer,
          LfColors.mintText(theme.brightness),
        );
        expect(theme.colorScheme.tertiaryContainer, lf.carbs100);
        expect(theme.colorScheme.onTertiaryContainer, lf.cardForeground);
        // 关键判据：容器槽必须与回落目标**不同**，否则等于没设。
        expect(
          theme.colorScheme.primaryContainer,
          isNot(theme.colorScheme.primary),
        );
        expect(
          theme.colorScheme.tertiaryContainer,
          isNot(theme.colorScheme.tertiary),
        );
        // 且两种容器槽彼此不同——否则「已匹配 / 待确认」状态不可辨。
        expect(
          theme.colorScheme.primaryContainer,
          isNot(theme.colorScheme.tertiaryContainer),
        );
      }
    });
  });

  group('filledButtonTheme（B1 的实心档来源）', () {
    test('实心档随主题：亮/高对比/暗都取 primary', () {
      expect(solidFill(light), lfLight.primary);
      expect(solidFill(lightHighContrast), lfLight.primary);
      expect(solidFill(dark), lfDark.primary);
      expect(dark.colorScheme.primary, lfDark.primary);
      expect(solidFill(darkHighContrast), lfDark.primary);
    });

    test('高对比：品牌底深字 + 2dp 前景描边，文字与轮廓可辨', () {
      for (final theme in [lightHighContrast, darkHighContrast]) {
        final lf = theme.brightness == Brightness.light ? lfLight : lfDark;
        for (final style in [
          theme.filledButtonTheme.style!,
          theme.elevatedButtonTheme.style!,
        ]) {
          final fill = style.backgroundColor!.resolve(const {})!;
          final foreground = style.foregroundColor!.resolve(const {})!;
          final side = style.side!.resolve(const {})!;
          expect(fill, lf.primary);
          expect(foreground, const Color(0xFF10271D));
          expect(side.color, lf.foreground);
          expect(side.width, 2);
          expect(side.style, BorderStyle.solid);
          expect(
            contrastRatio(foreground, fill),
            greaterThanOrEqualTo(4.5),
            reason: '高对比按钮文字仍须满足正文对比度',
          );
          for (final surface in [lf.background, lf.card]) {
            expect(
              contrastRatio(side.color, surface),
              greaterThanOrEqualTo(3),
              reason: '2dp 描边须在页面和卡片底上清晰可辨',
            );
          }
        }
      }
    });

    test('禁用档落 muted（不是与可用按钮同色）', () {
      expect(solidFill(light, const {WidgetState.disabled}), lfLight.muted);
      expect(solidForeground(light), lfLight.primaryForeground);
      expect(
        solidForeground(light, const {WidgetState.disabled}),
        lfLight.mutedForeground,
      );
      for (final theme in [light, dark, lightHighContrast, darkHighContrast]) {
        final lf = theme.brightness == Brightness.light ? lfLight : lfDark;
        expect(solidFill(theme, const {WidgetState.disabled}), lf.muted);
        expect(
          solidForeground(theme, const {WidgetState.disabled}),
          lf.mutedForeground,
        );
      }
    });

    test('几何：12 圆角 / h44 / bodyStrong / 无阴影', () {
      final style = light.filledButtonTheme.style!;
      expect(
        radiusOf(style.shape!.resolve(const {})),
        BorderRadius.circular(LfDimens.radiusMd),
      );
      expect(style.minimumSize!.resolve(const {})!.height, 44);
      expect(
        style.textStyle!.resolve(const {})!.fontSize,
        LfText.bodyStrong.fontSize,
      );
      expect(style.elevation!.resolve(const {}), 0);
      expect(style.surfaceTintColor!.resolve(const {}), Colors.transparent);
    });
  });

  group('textButtonTheme / outlinedButtonTheme / iconButtonTheme', () {
    test('文字按钮字色 = mintText，禁用落 mutedForeground', () {
      expect(
        light.textButtonTheme.style!.foregroundColor!.resolve(const {}),
        LfColors.mintText(Brightness.light),
      );
      expect(
        dark.textButtonTheme.style!.foregroundColor!.resolve(const {}),
        LfColors.mintText(Brightness.dark),
      );
      expect(
        light.textButtonTheme.style!.foregroundColor!.resolve(const {
          WidgetState.disabled,
        }),
        lfLight.mutedForeground,
      );
    });

    test('描边按钮：前景 = foreground，描边 = border，12 圆角 / h44', () {
      final style = light.outlinedButtonTheme.style!;
      expect(style.foregroundColor!.resolve(const {}), lfLight.foreground);
      expect(style.side!.resolve(const {})!.color, lfLight.border);
      expect(
        radiusOf(style.shape!.resolve(const {})),
        BorderRadius.circular(LfDimens.radiusMd),
      );
      expect(style.minimumSize!.resolve(const {})!.height, 44);
    });

    test('图标按钮默认前景 = mutedForeground', () {
      expect(
        light.iconButtonTheme.style!.foregroundColor!.resolve(const {}),
        lfLight.mutedForeground,
      );
    });
  });

  group('chipTheme / listTileTheme / dividerTheme', () {
    test('chip：muted 底 + 浅品牌选中底 + 无勾号 + 胶囊', () {
      expect(light.chipTheme.backgroundColor, lfLight.muted);
      expect(light.chipTheme.selectedColor, softLight);
      expect(light.chipTheme.disabledColor, lfLight.muted);
      expect(light.chipTheme.showCheckmark, isFalse);
      expect(light.chipTheme.shape, isA<StadiumBorder>());
      expect(light.chipTheme.side, BorderSide.none);
      expect(light.chipTheme.elevation, 0);
      expect(light.chipTheme.pressElevation, 0);
    });

    test('ListTile 当内容卡时与卡片同字色、同内边距', () {
      expect(light.listTileTheme.titleTextStyle!.color, lfLight.cardForeground);
      expect(
        light.listTileTheme.subtitleTextStyle!.color,
        lfLight.mutedForeground,
      );
      expect(light.listTileTheme.iconColor, lfLight.mutedForeground);
      expect(
        light.listTileTheme.contentPadding,
        const EdgeInsets.symmetric(horizontal: LfDimens.cardPadding),
      );
    });

    test('分隔线 = border / 1px', () {
      expect(light.dividerTheme.color, lfLight.border);
      expect(light.dividerTheme.thickness, 1);
      expect(dark.dividerTheme.color, lfDark.border);
    });
  });

  group('卡片 / 浮层形态语言统一（卡片 16 圆角、底部面板上圆角 24）', () {
    test('cardTheme：elevation 0 + 16 圆角 + 亮透明边 / 暗 border 描边', () {
      expect(light.cardTheme.elevation, 0);
      expect(light.cardTheme.color, lfLight.card);
      final shape = light.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(LfDimens.radiusLg));
      expect(shape.side.color, Colors.transparent);
      final darkShape = dark.cardTheme.shape as RoundedRectangleBorder;
      expect(dark.cardTheme.elevation, 0);
      expect(dark.cardTheme.color, lfDark.card);
      expect(darkShape.borderRadius, BorderRadius.circular(LfDimens.radiusLg));
      expect(darkShape.side.color, lfDark.border);
      expect(darkShape.side.width, 1);
    });

    test('dialogTheme：card 底 / 16 圆角 / 无阴影 / 1px 描边', () {
      expect(light.dialogTheme.backgroundColor, lfLight.card);
      expect(light.dialogTheme.elevation, 0);
      final shape = light.dialogTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(LfDimens.radiusLg));
      expect(shape.side.color, lfLight.border);
      expect(light.dialogTheme.titleTextStyle!.color, lfLight.foreground);
      expect(
        light.dialogTheme.contentTextStyle!.color,
        lfLight.mutedForeground,
      );
    });

    test('bottomSheetTheme：card 底 / 仅上圆角 24 / 无阴影 / 拖拽柄 32×4', () {
      expect(light.bottomSheetTheme.backgroundColor, lfLight.card);
      expect(light.bottomSheetTheme.modalBackgroundColor, lfLight.card);
      expect(light.bottomSheetTheme.elevation, 0);
      expect(light.bottomSheetTheme.modalElevation, 0);
      final shape = light.bottomSheetTheme.shape as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(24)),
      );
      expect(light.bottomSheetTheme.dragHandleSize, const Size(32, 4));
    });

    test('popupMenuTheme：card 底 + 16 圆角 + foreground 字', () {
      expect(light.popupMenuTheme.color, lfLight.card);
      expect(
        radiusOf(light.popupMenuTheme.shape),
        BorderRadius.circular(LfDimens.radiusLg),
      );
      expect(light.popupMenuTheme.textStyle!.color, lfLight.foreground);
    });
  });

  group('其余槽位', () {
    test('progressIndicatorTheme：primary 前景 / ringTrack 轨道', () {
      expect(light.progressIndicatorTheme.color, lfLight.primary);
      expect(light.progressIndicatorTheme.linearTrackColor, lfLight.muted);
      expect(
        light.progressIndicatorTheme.linearTrackColor,
        LfComponentColors.light.ringTrack,
      );
      expect(dark.progressIndicatorTheme.color, lfDark.primary);
      expect(
        dark.progressIndicatorTheme.linearTrackColor,
        LfComponentColors.dark.ringTrack,
      );
    });

    test('tooltipTheme：不再是系统灰（用 snackBar 底 + onSnackBar 字）', () {
      final decoration = light.tooltipTheme.decoration as BoxDecoration;
      expect(decoration.color, LfComponentColors.light.snackBarBackground);
      expect(
        light.tooltipTheme.textStyle!.color,
        LfComponentColors.light.onSnackBar,
      );
      expect(decoration.borderRadius, BorderRadius.circular(LfDimens.radiusSm));
    });

    test('floatingActionButtonTheme：实心档 + 圆形 + 无阴影', () {
      expect(light.floatingActionButtonTheme.backgroundColor, lfLight.primary);
      expect(
        light.floatingActionButtonTheme.foregroundColor,
        lfLight.primaryForeground,
      );
      expect(light.floatingActionButtonTheme.elevation, 0);
      expect(light.floatingActionButtonTheme.highlightElevation, 0);
      expect(light.floatingActionButtonTheme.shape, isA<CircleBorder>());
    });

    test('elevatedButtonTheme 保留既有对外契约（背景 + ≥44 最小高）', () {
      // 波 3 会迁走唯一一处裸 `ElevatedButton`，此处是防御性配置。
      expect(
        light.elevatedButtonTheme.style!.backgroundColor!.resolve(const {}),
        lfLight.primary,
      );
      expect(
        lightHighContrast.elevatedButtonTheme.style!.backgroundColor!.resolve(
          const {},
        ),
        lfLight.primary,
      );
      expect(
        dark.elevatedButtonTheme.style!.backgroundColor!.resolve(const {}),
        lfDark.primary,
      );
      expect(
        light.elevatedButtonTheme.style!.minimumSize!.resolve(const {})!.height,
        greaterThanOrEqualTo(LfDimens.minTouchTarget),
      );
    });
  });
}
