// 2026-10-14 Round7 A：仅更新视觉期望，保留行为、无障碍与性能约束。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_dimens.dart';
import 'package:localfit_ai/app/design/lf_text_styles.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

void main() {
  group('LfColors ramp（docs/21 §2.1.1/§2.1.2）', () {
    test('亮色 mint ramp 逐档对齐设计稿', () {
      expect(LfColors.mintLight.tone(500), const Color(0xFF2FBE8F));
      expect(LfColors.mintLight.tone(50), const Color(0xFFECFBF5));
      expect(LfColors.mintLight.tone(100), const Color(0xFFD2F5E6));
      expect(LfColors.mintLight.tone(200), const Color(0xFFA8EBCF));
      expect(LfColors.mintLight.tone(300), const Color(0xFF6FDBB0));
      expect(LfColors.mintLight.tone(400), const Color(0xFF4ED9A6));
      expect(LfColors.mintLight.tone(600), const Color(0xFF22A877));
      expect(LfColors.mintLight.tone(900), const Color(0xFF114A36));
    });

    test('暗色 mint ramp 50–400 覆盖、500–900 与亮色同值', () {
      expect(LfColors.mintDark.tone(50), const Color(0xFF0F1412));
      expect(LfColors.mintDark.tone(100), const Color(0xFF1F2823));
      expect(LfColors.mintDark.tone(200), const Color(0xFF242E28));
      expect(LfColors.mintDark.tone(300), const Color(0xFF2A3A32));
      expect(LfColors.mintDark.tone(400), const Color(0xFF4ED9A6));
      for (final tone in [500, 600, 700, 800, 900]) {
        expect(
          LfColors.mintDark.tone(tone),
          LfColors.mintLight.tone(tone),
          reason: 'tone $tone 暗色应与亮色同值',
        );
      }
    });

    test('暗色 neutral ramp 方向相反（50 最深、900 最浅）', () {
      expect(
        LfColors.neutralDark.tone(50).computeLuminance(),
        lessThan(LfColors.neutralDark.tone(900).computeLuminance()),
      );
      expect(LfColors.neutralDark.tone(100), const Color(0xFF171E1A));
      expect(LfColors.neutralDark.tone(200), const Color(0xFF1F2823));
      expect(LfColors.neutralDark.tone(900), const Color(0xFFDDE5E1));
    });

    test('分类数据色编码不变：蛋白=珊瑚、碳水=蜜黄、脂肪=雾紫', () {
      // 亮色锚点与旧设计逐值一致（docs/21 §2.8.1 完全一致项）。
      expect(LfColors.proteinLight, const Color(0xFFFF8A65));
      expect(LfColors.carbsLight, const Color(0xFFFFC94D));
      expect(LfColors.fatLight, const Color(0xFFB39DDB));
      expect(LfColors.waterLight, const Color(0xFFA8C4D9));
      expect(LfColors.weightLight, const Color(0xFFC9A27E));
      // 暗色只提亮，色相通道不调换（按 RGB 序蛋白红分量最高）。
      expect(LfColors.proteinDark.r, greaterThan(LfColors.proteinDark.b));
      expect(LfColors.carbsDark.g, greaterThan(LfColors.carbsDark.b));
    });

    test('tone 只认 50..900 十档，越界抛 ArgumentError', () {
      for (final ramp in [
        LfColors.mintLight,
        LfColors.mintDark,
        LfColors.neutralLight,
        LfColors.neutralDark,
      ]) {
        for (final tone in [50, 100, 200, 300, 400, 500, 600, 700, 800, 900]) {
          expect(ramp.tone(tone), isA<Color>(), reason: 'tone $tone 缺失');
        }
        expect(ramp.values, hasLength(10));
        expect(() => ramp.tone(0), throwsArgumentError);
        expect(() => ramp.tone(950), throwsArgumentError);
      }
    });

    test('亮色 ramp 逐档亮度单调变暗', () {
      for (final ramp in [LfColors.mintLight, LfColors.neutralLight]) {
        var previous = ramp.tone(50).computeLuminance();
        for (final tone in [100, 200, 300, 400, 500, 600, 700, 800, 900]) {
          final luminance = ramp.tone(tone).computeLuminance();
          expect(
            luminance,
            lessThanOrEqualTo(previous),
            reason: 'tone $tone 亮度未单调下降',
          );
          previous = luminance;
        }
      }
    });

    test('mintText 文字级品牌绿：亮 #187653 / 暗 400（浅底上可读）', () {
      expect(LfColors.mintText(Brightness.light), const Color(0xFF187653));
      expect(LfColors.mintText(Brightness.dark), LfColors.mintDark.tone(400));
      expect(
        LfColors.mintText(Brightness.light).computeLuminance(),
        lessThan(LfColors.mintLight.tone(100).computeLuminance()),
        reason: 'mint-100 浅底上的文字必须比底更暗',
      );
      expect(
        LfColors.mintText(Brightness.dark).computeLuminance(),
        greaterThan(LfColors.mintDark.tone(100).computeLuminance()),
        reason: 'mint-100 深底上的文字必须比底更亮',
      );
    });

    test('brandSoft 亮暗浅品牌底独立于 mint-100 原始色阶', () {
      expect(LfColors.brandSoft(Brightness.light), const Color(0xFFECFBF5));
      expect(LfColors.brandSoft(Brightness.dark), const Color(0xFF203C30));
    });

    test('暗色数据色只提亮不换相（色相漂移 < 15°）', () {
      final pairs = <(Color, Color)>[
        (LfColors.proteinLight, LfColors.proteinDark),
        (LfColors.carbsLight, LfColors.carbsDark),
        (LfColors.fatLight, LfColors.fatDark),
        (LfColors.waterLight, LfColors.waterDark),
        (LfColors.weightLight, LfColors.weightDark),
      ];
      double hueOf(Color c) => HSLColor.fromColor(c).hue;
      for (final (light, dark) in pairs) {
        expect(
          dark.computeLuminance(),
          greaterThan(light.computeLuminance()),
          reason: '暗色应比亮色更亮',
        );
        expect(
          (hueOf(dark) - hueOf(light)).abs(),
          lessThan(15),
          reason: '数据色编码不可换相',
        );
      }
    });
  });

  group('LfSemanticColors（docs/21 §2.1.6/§2.2.1）', () {
    test('亮色语义表面逐值对齐设计稿', () {
      const c = LfSemanticColors.light;
      expect(c.background, const Color(0xFFF7F9F8));
      expect(c.foreground, const Color(0xFF1A201D));
      expect(c.card, const Color(0xFFFFFFFF));
      expect(c.muted, const Color(0xFFEFF3F1));
      expect(c.mutedForeground, const Color(0xFF5C7067));
      expect(c.border, const Color(0xFFDDE5E1));
      expect(c.input, const Color(0xFFDDE5E1));
      expect(c.ring, const Color(0xFF2FBE8F));
      expect(c.primary, const Color(0xFF2FBE8F));
      expect(c.primaryForeground, const Color(0xFF10271D));
      // 亮色 success == mint-500（设计稿如此，非笔误）。
      expect(c.success, c.primary);
    });

    test('暗色语义表面逐值对齐设计稿', () {
      const c = LfSemanticColors.dark;
      expect(c.background, const Color(0xFF0F1412));
      expect(c.foreground, const Color(0xFFDDE5E1));
      expect(c.card, const Color(0xFF171E1A));
      expect(c.popover, const Color(0xFF1F2823));
      expect(c.muted, const Color(0xFF1F2823));
      expect(c.mutedForeground, const Color(0xFF8FA09A));
      expect(c.border, const Color(0xFF2A342F));
      expect(c.primary, const Color(0xFF4ED9A6));
      expect(c.primaryForeground, const Color(0xFF10271D));
    });

    test('证据分级三档（亮=100 档浅底，暗=深底）', () {
      const light = LfSemanticColors.light;
      expect(light.evidenceA, const Color(0xFFD2F5E6));
      expect(light.evidenceB, const Color(0xFFFFF4D6));
      expect(light.evidenceC, const Color(0xFFEDE6F7));
      const dark = LfSemanticColors.dark;
      expect(dark.evidenceA, const Color(0xFF1F2823));
      expect(dark.evidenceB, const Color(0xFF2A2438));
      expect(dark.evidenceC, const Color(0xFF242E28));
    });

    test('copyWith/lerp/相等性成立（ThemeExtension 契约）', () {
      const a = LfSemanticColors.light;
      expect(a.copyWith(), a);
      expect(
        a.copyWith(primary: const Color(0xFF123456)).primary,
        const Color(0xFF123456),
      );
      final mixed = a.lerp(LfSemanticColors.dark, 0.5);
      expect(
        mixed.background,
        Color.lerp(const Color(0xFFF7F9F8), const Color(0xFF0F1412), 0.5),
      );
      // 契约要求的是端点短路，而不是逐字段相等——`Color.lerp` 浮点通道
      // 有 ±1 漂移，自实现 lerp 的逐字段相等不是 ThemeExtension 的一部分。
      expect(a.lerp(LfSemanticColors.dark, 0), same(a));
      expect(a.lerp(LfSemanticColors.dark, 1), same(LfSemanticColors.dark));
      expect(a.lerp(null, 0.5), same(a));
    });

    test('状态四色与 on 前景齐备、互相可辨（docs/21 §2.1.4）', () {
      const light = LfSemanticColors.light;
      expect({light.warning, light.error, light.info}, hasLength(3));
      for (final on in [
        light.primaryForeground,
        light.successForeground,
        light.warningForeground,
        light.errorForeground,
        light.infoForeground,
      ]) {
        expect(on, isA<Color>());
      }
      const dark = LfSemanticColors.dark;
      expect({dark.warning, dark.error, dark.info}, hasLength(3));
      expect(dark.success, dark.primary);
    });
  });

  group('LfComponentColors / LfShadows / LfGradients（docs/21 §2.4/§2.5）', () {
    test('hero 渐变三停靠亮暗各一套，停靠位 0/0.55/1 与 0/0.5/1', () {
      expect(LfComponentColors.light.heroGradient, const [
        Color(0xFF2FBE8F),
        Color(0xFFA8EBCF),
        Color(0xFFECFBF5),
      ]);
      expect(LfComponentColors.light.heroStops, [0.0, 0.55, 1.0]);
      expect(LfComponentColors.dark.heroGradient, const [
        Color(0xFF166B4D),
        Color(0xFF1B8A62),
        Color(0xFF0F1412),
      ]);
      expect(LfComponentColors.dark.heroStops, [0.0, 0.5, 1.0]);
    });

    test('静态表面阴影 alpha 上限 0.05（docs/21 §2.4 硬规则）', () {
      for (final shadows in [
        ...LfShadows.surface(true),
        ...LfShadows.float(true),
        ...LfShadows.floatLg(true),
        ...LfShadows.surface(false),
      ]) {
        // 硬规则是 alpha ≤ 0.05；0.05 经 8bit 量化为 13/255 ≈ 0.0509，容差容纳量化。
        expect(
          shadows.color.a,
          lessThanOrEqualTo(0.05 + 0.5 / 255 + 1e-6),
          reason: '静态阴影 alpha ${shadows.color.a} 超限',
        );
      }
    });

    test('凸起圆双层阴影：内圈为 background 描边、外圈 primary 30%', () {
      const bg = Color(0xFFF7F9F8);
      final shadows = LfShadows.navBump(bg);
      expect(shadows, hasLength(2));
      expect(shadows[0].color, bg);
      expect(shadows[0].spreadRadius, 2);
      expect(shadows[1].blurRadius, 12);
      expect(shadows[1].color, const Color(0x4D2FBE8F));
    });

    test('FAB 与 AI 主按钮是两条不同阴影（40% 无负 spread vs 35% 有负 spread）', () {
      const primary = Color(0xFF2FBE8F);
      final fab = LfShadows.fabPrimary(primary).single;
      final cta = LfShadows.aiPrimaryCta(primary).single;
      expect(fab.spreadRadius, 0);
      expect(cta.spreadRadius, -4);
      expect(fab.color, primary.withValues(alpha: 0.40));
      expect(cta.color, primary.withValues(alpha: 0.35));
    });

    test('凸起圆/气泡渐变取暗色 ramp 对应档位', () {
      final bumpDark = LfGradients.navBump(Brightness.dark).colors;
      expect(bumpDark[0], LfColors.mintDark.tone(500));
      expect(bumpDark[1], LfColors.mintDark.tone(600));
    });

    test('组件底色逐值：环轨/骨架对色/Snack 底色亮暗各一套', () {
      const light = LfComponentColors.light;
      expect(light.ringTrack, const Color(0xFFEFF3F1));
      expect(light.skeletonBase, const Color(0xFFDDE5E1));
      expect(light.skeletonHighlight, const Color(0xFFEFF3F1));
      expect(light.snackBarBackground, const Color(0xFF1A201D));
      expect(light.onSnackBar, const Color(0xFFFFFFFF));
      const dark = LfComponentColors.dark;
      expect(dark.ringTrack, const Color(0xFF26332C));
      expect(dark.skeletonBase, const Color(0xFF242E28));
      expect(dark.skeletonHighlight, const Color(0xFF2A342F));
      expect(dark.snackBarBackground, const Color(0xFF171E1A));
      expect(dark.onSnackBar, const Color(0xFFDDE5E1));
      // 骨架高光必须比底轨亮（亮暗都成立），否则骨架不可见。
      for (final c in [light, dark]) {
        expect(
          c.skeletonHighlight.computeLuminance(),
          greaterThan(c.skeletonBase.computeLuminance()),
        );
      }
    });

    test('copyWith/lerp 满足 ThemeExtension 契约（端点短路）', () {
      const light = LfComponentColors.light;
      const dark = LfComponentColors.dark;
      expect(
        light.copyWith(ringTrack: const Color(0xFF123456)).ringTrack,
        const Color(0xFF123456),
      );
      expect(light.lerp(dark, 0), same(light));
      expect(light.lerp(dark, 1), same(dark));
      expect(light.lerp(null, 0.5), same(light));
      final mid = light.lerp(dark, 0.5);
      expect(mid.heroGradient, hasLength(3));
      expect(mid.ringTrack, isNot(light.ringTrack));
    });
  });

  group('LfDimens（docs/21 §2.3/§2.7/§3.6）', () {
    test('间距档对齐 Tailwind gap 档', () {
      expect(LfDimens.spaceMicro, 2);
      expect(LfDimens.spaceXSmall, 4);
      expect(LfDimens.spaceTiny, 6);
      expect(LfDimens.spaceSmall, 8);
      expect(LfDimens.spaceSmallPlus, 10);
      expect(LfDimens.spaceMedium, 12);
      expect(LfDimens.spaceMediumPlus, 14);
      expect(LfDimens.spaceLarge, 16);
      expect(LfDimens.spaceLargePlus, 20);
      expect(LfDimens.pagePadding, 16);
      expect(LfDimens.cardPadding, 16);
      expect(LfDimens.cardGap, 16);
    });

    test('圆角收敛为 8/12/16/full', () {
      expect(LfDimens.radiusSm, 8);
      expect(LfDimens.radiusMd, 12);
      expect(LfDimens.radiusLg, 16);
      expect(LfDimens.radiusXl, 16);
      expect(LfDimens.radius2xl, 16);
    });

    test('底栏几何：64 栏高 + 56 凸起圆 + 12 净上凸', () {
      expect(LfDimens.navBarHeight, 64);
      expect(LfDimens.navBumpSize, 56);
      expect(LfDimens.navBumpMarginLift, 16);
      expect(
        LfDimens.navReservedSpace,
        LfDimens.navBarHeight + LfDimens.navBumpProtrusion,
      );
    });
  });

  group('LfText（docs/21 §2.6）', () {
    test('字阶 11 档 + display 三档，字号逐档对齐', () {
      expect(LfText.micro.fontSize, 10);
      expect(LfText.label.fontSize, 11);
      expect(LfText.caption.fontSize, 12);
      expect(LfText.bodySmall.fontSize, 13);
      expect(LfText.body.fontSize, 14);
      expect(LfText.title.fontSize, 15);
      expect(LfText.titleLarge.fontSize, 16);
      expect(LfText.headline.fontSize, 18);
      expect(LfText.displayLarge.fontSize, 22);
      expect(LfText.displayXLarge.fontSize, 26);
      expect(LfText.displayHero.fontSize, 30);
    });

    test('全档数字等宽（设计稿 body 全局 tnum）', () {
      for (final style in [
        LfText.micro,
        LfText.microStrong,
        LfText.label,
        LfText.caption,
        LfText.captionStrong,
        LfText.bodySmall,
        LfText.body,
        LfText.bodyStrong,
        LfText.title,
        LfText.titleLarge,
        LfText.headline,
        LfText.displayLarge,
        LfText.displayXLarge,
        LfText.displayHero,
      ]) {
        expect(
          style.fontFeatures,
          contains(FontFeature.tabularFigures()),
          reason: 'fontSize ${style.fontSize} 缺 tabular figures',
        );
      }
    });

    test('.lf-display 特征：w800 + h1.0/1.1 + letterSpacing -0.02em', () {
      for (final style in [
        LfText.displayLarge,
        LfText.displayXLarge,
        LfText.displayHero,
      ]) {
        expect(style.fontWeight, FontWeight.w800);
        expect(
          style.letterSpacing,
          closeTo(-0.02 * style.fontSize!, 1e-9),
          reason: 'fontSize ${style.fontSize} 的 letterSpacing 应为 -0.02em',
        );
      }
      expect(LfText.displayLarge.height, 1.1);
      expect(LfText.displayXLarge.height, 1.0);
      expect(LfText.displayHero.height, 1.0);
    });

    test('主题注册了 Lf 两组扩展，亮暗各一套（docs/22 §2.3）', () {
      expect(
        AppTheme.light().extension<LfSemanticColors>(),
        LfSemanticColors.light,
      );
      expect(
        AppTheme.dark().extension<LfSemanticColors>(),
        LfSemanticColors.dark,
      );
      expect(
        AppTheme.light().extension<LfComponentColors>(),
        LfComponentColors.light,
      );
      expect(
        AppTheme.dark().extension<LfComponentColors>(),
        LfComponentColors.dark,
      );
    });
  });
}
