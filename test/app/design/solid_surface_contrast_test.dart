import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localfit_ai/app/app_theme.dart';
import 'package:localfit_ai/app/design/lf_tokens.dart';

/// 【2026-10-29 用户裁决】「绿色按钮配黑字，根本看不清……你所有的东西都要
/// 符合软件的主题样式。」
///
/// 实心品牌面（按钮 / FAB / 导航凸起 / 选中胶囊 / 对话气泡 / 训练横幅）
/// 统一回到设计源稿基础层的配对：`--brand-strong` 底 + `var(--card)` 字
/// （亮：深绿 #187653 + 白；暗：薄荷 mint-400 + 卡片深字 #171E1A）。
///
/// 本文件是这条裁决的**数值门禁**：任何一次把实心面的字色/底色改回
/// 「绿底深字」或「白字压亮绿」，下面的对比度断言都会当场变红。
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  test('实心品牌面：两套主题的底/字对比都 ≥ 4.5', () {
    for (final brightness in Brightness.values) {
      final fill = LfColors.brandStrong(brightness);
      final fg = LfColors.onBrandStrong(brightness);
      expect(
        contrast(fill, fg),
        greaterThanOrEqualTo(4.5),
        reason:
            '$brightness 的实心面（#${fill.toARGB32().toRadixString(16)} '
            '+ #${fg.toARGB32().toRadixString(16)}）必须可读',
      );
    }
  });

  test('主题实心档（亮/暗/高对比）读的就是 brandStrong 对', () {
    for (final theme in [
      AppTheme.light(),
      AppTheme.dark(),
      AppTheme.light(highContrast: true),
      AppTheme.dark(highContrast: true),
    ]) {
      final style = theme.filledButtonTheme.style!;
      final fill = style.backgroundColor!.resolve(const {})!;
      final fg = style.foregroundColor!.resolve(const {})!;
      expect(fill, LfColors.brandStrong(theme.brightness));
      expect(fg, LfColors.onBrandStrong(theme.brightness));
      expect(contrast(fill, fg), greaterThanOrEqualTo(4.5));
    }
  });

  test('用户气泡渐变两端 vs 白字 ≥ 4.5（旧档白压亮薄荷只有 1.8:1）', () {
    for (final brightness in Brightness.values) {
      final gradient = LfGradients.userBubble(brightness);
      for (final color in gradient.colors) {
        expect(
          contrast(color, LfColors.onMedia),
          greaterThanOrEqualTo(4.5),
          reason: '气泡渐变停靠位 ${color.toARGB32().toRadixString(16)} 上的白字',
        );
      }
    }
  });

  test('训练横幅渐变两端 vs 白字 ≥ 4.5', () {
    for (final brightness in Brightness.values) {
      final gradient = LfGradients.activeBanner(
        LfSemanticColors.light.primary,
        brightness,
      );
      for (final color in gradient.colors) {
        expect(
          contrast(color, LfColors.onMedia),
          greaterThanOrEqualTo(4.5),
          reason: '横幅渐变停靠位 ${color.toARGB32().toRadixString(16)} 上的白字',
        );
      }
    }
  });

  test('亮色下 brandStrong 与 primary 是两个角色（实心面不再用 primary 底）', () {
    // 亮色：primary #2FBE8F（圆点/细线/进度填充）与 brandStrong #187653
    // （带文字的实心面）必须不同——旧档混用正是「看不清」的根因。
    // 暗色两值同为 mint-400（设计源稿 dark `--brand-strong` = mint-400），
    // 角色仍分离（语义不同），数值相同是设计源稿的事实。
    expect(
      LfColors.brandStrong(Brightness.light),
      isNot(LfSemanticColors.light.primary),
      reason: 'primary 只做圆点/细线/进度填充；实心面带文字的面取 brandStrong',
    );
  });
}
